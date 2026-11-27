import AppKit
import Foundation
import SwiftUI

/// Determina si un archivo debe usar el visor enriquecido (Markdown, JSON o código con resaltado de sintaxis)
/// dentro de Quick Look (`Espacio`).
public enum RichCodePreviewSupport {
    public static let markdownExtensions: Set<String> = ["md", "markdown"]
    public static let jsonExtensions: Set<String> = ["json"]
    public static let codeExtensions: Set<String> = [
        "swift", "py", "js", "ts", "tsx", "jsx", "html", "htm", "css", "scss",
        "xml", "yaml", "yml", "sh", "zsh", "bash", "sql", "go", "rs", "java",
        "kt", "c", "cpp", "cc", "h", "hpp", "rb", "php", "toml", "ini", "plist"
    ]

    public static func supportsRichPreview(for url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return markdownExtensions.contains(ext)
            || jsonExtensions.contains(ext)
            || codeExtensions.contains(ext)
    }
}

/// Visor enriquecido para Quick Look (`Espacio`):
/// - `.md` / `.markdown`: renderizado formateado completo con alternancia a Texto plano nativo.
/// - `.json`: árbol colapsable interactivo con colores por tipo y alternancia a Texto plano formateado.
/// - Código fuente: numeración de líneas y resaltado de sintaxis sin quiebres estrechos.
public struct RichCodePreviewView: View {
    public let fileURL: URL

    @ViewState private var rawText: String = ""
    @ViewState private var loadError: String? = nil
    @ViewState private var isLoading: Bool = true
    @ViewState private var showPlainText: Bool = false

    private var loc: LocalizationManager { LocalizationManager.shared }

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    private var ext: String {
        fileURL.pathExtension.lowercased()
    }

    public var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                    Text(loadError)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if RichCodePreviewSupport.markdownExtensions.contains(ext) {
                markdownView
            } else if RichCodePreviewSupport.jsonExtensions.contains(ext) {
                jsonView
            } else {
                codeSyntaxView
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: fileURL) {
            await loadFileAsync()
        }
    }

    private func loadFileAsync() async {
        isLoading = true
        loadError = nil
        let targetURL = fileURL
        let result = await Task.detached(priority: .userInitiated) { () -> Result<String, Error> in
            do {
                let data = try Data(contentsOf: targetURL)
                let decoded: String?
                let isES = LocalizationManager.currentLanguageIsSpanish()
                if data.count > 2_500_000 {
                    let prefixData = data.prefix(2_500_000)
                    let truncatedSuffix = isES
                        ? "\n\n… (archivo truncado para vista rápida)"
                        : "\n\n… (file truncated for quick preview)"
                    decoded = (String(data: prefixData, encoding: .utf8) ?? String(data: prefixData, encoding: .isoLatin1))
                        .map { $0 + truncatedSuffix }
                } else {
                    decoded = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
                }
                if let decoded {
                    return .success(decoded)
                }
                return .failure(NSError(
                    domain: "MacFileExplorer.QuickLook",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: isES
                            ? "No se pudo decodificar el archivo de texto."
                            : "Could not decode text file."
                    ]
                ))
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let text):
            rawText = text
            loadError = nil
        case .failure(let error):
            rawText = ""
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Markdown Formateado + Texto Plano Limpio

    private var markdownView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Markdown")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $showPlainText) {
                    Text(loc.text(es: "Formateado", en: "Formatted")).tag(false)
                    Text(loc.text(es: "Texto plano", en: "Plain Text")).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 195)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.03))

            Divider()

            if showPlainText {
                PlainTextDocumentView(text: rawText)
            } else {
                let parsed = MarkdownDocumentParser.parse(rawText)
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 11) {
                        ForEach(Array(parsed.enumerated()), id: \.offset) { _, block in
                            renderMarkdownBlock(block)
                        }
                    }
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 22)
                }
            }
        }
    }

    // MARK: - JSON Colapsable + Texto Plano Limpio

    private var jsonView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("JSON")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $showPlainText) {
                    Text(loc.text(es: "Árbol colapsable", en: "Collapsible Tree")).tag(false)
                    Text(loc.text(es: "Texto plano", en: "Plain Text")).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 245)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.03))

            Divider()

            if showPlainText {
                PlainTextDocumentView(text: prettyPrintedJSON(from: rawText) ?? rawText)
            } else if let parsed = parseJSONObject(from: rawText) {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 4) {
                        JSONTreeNodeView(key: nil, value: parsed, initiallyExpanded: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
            } else {
                PlainTextDocumentView(text: rawText)
            }
        }
    }

    // MARK: - Código con Resaltado de Sintaxis

    private var codeSyntaxView: some View {
        highlightedCodeScrollView(text: rawText, language: ext)
    }

    private func highlightedCodeScrollView(text: String, language: String) -> some View {
        let lines = text.components(separatedBy: .newlines)
        return ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(idx + 1)")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 42, alignment: .trailing)

                        Text(highlightSyntax(line: line.isEmpty ? " " : line, language: language))
                            .font(.system(size: 12.5, design: .monospaced))
                            .fixedSize(horizontal: true, vertical: false)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private func highlightSyntax(line: String, language: String) -> AttributedString {
        var attr = AttributedString(line)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("//") || trimmed.hasPrefix("#") || trimmed.hasPrefix("--") {
            attr.foregroundColor = .secondary
            return attr
        }

        let keywords = [
            "func", "let", "var", "struct", "class", "enum", "protocol", "import", "return",
            "if", "else", "for", "while", "switch", "case", "guard", "public", "private",
            "async", "await", "try", "catch", "throw", "def", "from", "const", "function",
            "export", "default", "true", "false", "null", "nil", "SELECT", "FROM", "WHERE"
        ]
        for kw in keywords {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: kw))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let nsRange = NSRange(line.startIndex..., in: line)
                for match in regex.matches(in: line, range: nsRange) {
                    if let swiftRange = Range(match.range, in: line),
                       let attrRange = Range(swiftRange, in: attr) {
                        attr[attrRange].foregroundColor = .pink
                    }
                }
            }
        }

        if let strRegex = try? NSRegularExpression(pattern: "\"[^\"]*\"") {
            let nsRange = NSRange(line.startIndex..., in: line)
            for match in strRegex.matches(in: line, range: nsRange) {
                if let swiftRange = Range(match.range, in: line),
                   let attrRange = Range(swiftRange, in: attr) {
                    attr[attrRange].foregroundColor = .orange
                }
            }
        }

        return attr
    }

    // MARK: - Renderizado de Bloques Markdown

    @ViewBuilder
    private func renderMarkdownBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .frontmatter(let entries):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    HStack(alignment: .top, spacing: 8) {
                        Text(entry.key)
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 88, alignment: .leading)
                        Text(entry.value)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
            )

        case .heading(let level, let text):
            let size: CGFloat = switch level {
            case 1: 23
            case 2: 18
            case 3: 15.5
            case 4: 14
            default: 13
            }
            VStack(alignment: .leading, spacing: 5) {
                inlineMarkdownText(text)
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(level >= 5 ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                if level <= 2 {
                    Divider()
                }
            }
            .padding(.top, level == 1 ? 2 : 6)

        case .codeBlock(let language, let code):
            VStack(alignment: .leading, spacing: 0) {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 7)
                        .padding(.bottom, 2)
                }
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(code.isEmpty ? " " : code)
                        .font(.system(size: 12, design: .monospaced))
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 12)
                        .padding(.vertical, (language?.isEmpty == false) ? 8 : 10)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
            )

        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.accentColor.opacity(0.7))
                    .frame(width: 3)
                inlineMarkdownText(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)

        case .bullet(let indentLevel, let marker, let checked, let text):
            HStack(alignment: .top, spacing: 8) {
                if let checked {
                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                        .font(.system(size: 13))
                        .foregroundStyle(checked ? Color.accentColor : Color.secondary)
                        .padding(.top, 1.5)
                } else {
                    Text(marker)
                        .font(.system(size: 13, weight: marker == "•" ? .bold : .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: marker == "•" ? 10 : 18, alignment: .trailing)
                }
                inlineMarkdownText(text)
                    .font(.system(size: 13.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(8 + indentLevel * 18))

        case .table(let headers, let rows):
            ScrollView(.horizontal, showsIndicators: true) {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        ForEach(Array(headers.enumerated()), id: \.offset) { _, cell in
                            inlineMarkdownText(cell)
                                .font(.system(size: 12.5, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .frame(minWidth: 90, alignment: .leading)
                        }
                    }
                    .background(Color.primary.opacity(0.06))

                    Divider()

                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                        GridRow {
                            ForEach(0..<headers.count, id: \.self) { colIndex in
                                let value = colIndex < row.count ? row[colIndex] : ""
                                inlineMarkdownText(value)
                                    .font(.system(size: 12.5))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .frame(minWidth: 90, alignment: .leading)
                            }
                        }
                        .background(rowIndex.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.025))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

        case .divider:
            Divider()
                .padding(.vertical, 4)

        case .paragraph(let text):
            inlineMarkdownText(text)
                .font(.system(size: 13.5))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func inlineMarkdownText(_ raw: String) -> Text {
        let normalized = MarkdownDocumentParser.normalizeInlineMarkup(raw)
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let attr = try? AttributedString(markdown: normalized, options: options) {
            return Text(attr)
        }
        return Text(normalized)
    }

    // MARK: - Helpers JSON

    private func parseJSONObject(from text: String) -> Any? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private func prettyPrintedJSON(from text: String) -> String? {
        guard let obj = parseJSONObject(from: text),
              let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Visor Nativo de Texto Plano (AppKit NSTextView)

/// Visor de solo texto plano nativo con ajuste de línea a todo el ancho de la ventana,
/// selección de texto fluida y sin columnas artificiales ni números de línea.
private struct PlainTextDocumentView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = NSBorderType.noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor

        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.isRichText = false
            textView.importsGraphics = false
            textView.allowsUndo = false
            textView.usesFindPanel = true
            textView.backgroundColor = NSColor.textBackgroundColor
            textView.textColor = NSColor.labelColor
            textView.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
            textView.textContainerInset = NSSize(width: 20, height: 16)
            textView.string = text
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }
}

// MARK: - Parser Markdown Mejorado

private enum MarkdownBlock {
    case frontmatter([(key: String, value: String)])
    case heading(level: Int, text: String)
    case codeBlock(language: String?, code: String)
    case quote(String)
    case bullet(indentLevel: Int, marker: String, checked: Bool?, text: String)
    case table(headers: [String], rows: [[String]])
    case divider
    case paragraph(String)
}

private enum MarkdownDocumentParser {
    static func parse(_ rawText: String) -> [MarkdownBlock] {
        let normalizedNewlines = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalizedNewlines.components(separatedBy: "\n")

        var blocks: [MarkdownBlock] = []
        var index = 0

        // 1. YAML Frontmatter opcional al inicio (`--- ... ---`)
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            var endIdx: Int?
            for candidate in 1..<min(lines.count, 40) {
                let t = lines[candidate].trimmingCharacters(in: .whitespaces)
                if t == "---" || t == "..." {
                    endIdx = candidate
                    break
                }
            }
            if let endIdx, endIdx > 1 {
                var entries: [(key: String, value: String)] = []
                for line in lines[1..<endIdx] {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
                    if (line.hasPrefix(" ") || line.hasPrefix("\t")), !entries.isEmpty, !trimmed.hasPrefix("-") {
                        let lastIdx = entries.count - 1
                        let prev = entries[lastIdx].value
                        entries[lastIdx].value = prev.isEmpty ? trimmed : "\(prev) \(trimmed)"
                    } else if let colonIdx = trimmed.firstIndex(of: ":") {
                        let key = String(trimmed[..<colonIdx]).trimmingCharacters(in: .whitespaces)
                        var val = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                        if (val.hasPrefix("\"") && val.hasSuffix("\"")) || (val.hasPrefix("'") && val.hasSuffix("'")),
                           val.count >= 2 {
                            val = String(val.dropFirst().dropLast())
                        }
                        if val == "|" || val == ">" || val == "|-" || val == ">-" {
                            val = ""
                        }
                        if !key.isEmpty {
                            entries.append((key: key, value: val))
                        }
                    }
                }
                if !entries.isEmpty {
                    blocks.append(.frontmatter(entries))
                    index = endIdx + 1
                }
            }
        }

        var paragraphBuffer: [String] = []
        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            let joined = paragraphBuffer.joined(separator: " ")
            blocks.append(.paragraph(joined))
            paragraphBuffer.removeAll(keepingCapacity: true)
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Línea vacía -> cierra párrafo
            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            // Bloque de código cercado (``` o ~~~)
            if let fence = codeFencePrefix(in: trimmed) {
                flushParagraph()
                let language = String(trimmed.dropFirst(fence.count)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                index += 1
                while index < lines.count {
                    let candidateTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
                    if candidateTrimmed.hasPrefix(fence) {
                        index += 1
                        break
                    }
                    codeLines.append(lines[index])
                    index += 1
                }
                blocks.append(.codeBlock(language: language.isEmpty ? nil : language, code: codeLines.joined(separator: "\n")))
                continue
            }

            // Divisor horizontal
            if isHorizontalRule(trimmed) {
                flushParagraph()
                blocks.append(.divider)
                index += 1
                continue
            }

            // Encabezados (# hasta ######)
            if let heading = parseHeading(trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            // Tabla Markdown (`| ... |` + línea separadora `| --- |`)
            if index + 1 < lines.count,
               trimmed.contains("|"),
               isTableSeparatorRow(lines[index + 1].trimmingCharacters(in: .whitespaces)) {
                flushParagraph()
                let headers = splitTableRow(trimmed)
                index += 2
                var rows: [[String]] = []
                while index < lines.count {
                    let rowTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
                    if rowTrimmed.isEmpty || !rowTrimmed.contains("|") {
                        break
                    }
                    rows.append(splitTableRow(rowTrimmed))
                    index += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                continue
            }

            // Citas (`> ...`)
            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoteLines: [String] = []
                while index < lines.count {
                    let qTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
                    guard qTrimmed.hasPrefix(">") else { break }
                    var inner = String(qTrimmed.dropFirst())
                    if inner.hasPrefix(" ") {
                        inner.removeFirst()
                    }
                    quoteLines.append(inner)
                    index += 1
                }
                blocks.append(.quote(quoteLines.joined(separator: "\n")))
                continue
            }

            // Listas (viñetas, tareas o numeradas)
            if let listItem = parseListItem(line: line) {
                flushParagraph()
                blocks.append(.bullet(
                    indentLevel: listItem.indentLevel,
                    marker: listItem.marker,
                    checked: listItem.checked,
                    text: listItem.text
                ))
                index += 1
                continue
            }

            // Párrafo normal (agrupa líneas contiguas)
            paragraphBuffer.append(trimmed)
            index += 1
        }

        flushParagraph()
        return blocks
    }

    static func normalizeInlineMarkup(_ text: String) -> String {
        var result = text
        // Convierte `<kbd>Cmd</kbd>` en código inline `` `Cmd` ``
        result = result.replacingOccurrences(of: "<kbd>", with: "`")
        result = result.replacingOccurrences(of: "</kbd>", with: "`")
        result = result.replacingOccurrences(of: "<br>", with: "\n")
        result = result.replacingOccurrences(of: "<br/>", with: "\n")
        result = result.replacingOccurrences(of: "<br />", with: "\n")
        return result
    }

    private static func codeFencePrefix(in trimmed: String) -> String? {
        if trimmed.hasPrefix("```") { return "```" }
        if trimmed.hasPrefix("~~~") { return "~~~" }
        return nil
    }

    private static func isHorizontalRule(_ trimmed: String) -> Bool {
        let cleaned = trimmed.replacingOccurrences(of: " ", with: "")
        guard cleaned.count >= 3 else { return false }
        return cleaned.allSatisfy { $0 == "-" }
            || cleaned.allSatisfy { $0 == "*" }
            || cleaned.allSatisfy { $0 == "_" }
    }

    private static func parseHeading(_ trimmed: String) -> (level: Int, text: String)? {
        var hashes = 0
        for ch in trimmed {
            if ch == "#" {
                hashes += 1
            } else {
                break
            }
        }
        guard (1...6).contains(hashes) else { return nil }
        let rest = String(trimmed.dropFirst(hashes))
        guard rest.hasPrefix(" ") else { return nil }
        return (hashes, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func parseListItem(
        line: String
    ) -> (indentLevel: Int, marker: String, checked: Bool?, text: String)? {
        var spaces = 0
        for ch in line {
            if ch == " " {
                spaces += 1
            } else if ch == "\t" {
                spaces += 2
            } else {
                break
            }
        }
        let indentLevel = min(spaces / 2, 4)
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        for prefix in ["- ", "* ", "+ "] {
            if trimmed.hasPrefix(prefix) {
                let body = String(trimmed.dropFirst(2))
                if body.hasPrefix("[ ] ") {
                    return (indentLevel, "•", false, String(body.dropFirst(4)))
                }
                if body.hasPrefix("[x] ") || body.hasPrefix("[X] ") {
                    return (indentLevel, "•", true, String(body.dropFirst(4)))
                }
                return (indentLevel, "•", nil, body)
            }
        }

        // Lista numerada (`1. texto`, `12. texto`)
        if let dotIndex = trimmed.firstIndex(of: "."), dotIndex > trimmed.startIndex {
            let numberPart = trimmed[..<dotIndex]
            let afterDot = trimmed.index(after: dotIndex)
            if afterDot < trimmed.endIndex,
               trimmed[afterDot] == " ",
               numberPart.allSatisfy(\.isNumber) {
                let textStart = trimmed.index(after: afterDot)
                return (indentLevel, "\(numberPart).", nil, String(trimmed[textStart...]))
            }
        }
        return nil
    }

    private static func isTableSeparatorRow(_ trimmed: String) -> Bool {
        guard trimmed.contains("-") && trimmed.contains("|") else { return false }
        let allowed = CharacterSet(charactersIn: "|-: ")
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func splitTableRow(_ trimmed: String) -> [String] {
        var work = trimmed
        if work.hasPrefix("|") { work.removeFirst() }
        if work.hasSuffix("|") { work.removeLast() }
        return work.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

// MARK: - Árbol JSON Colapsable

private struct JSONTreeNodeView: View {
    let key: String?
    let value: Any
    @ViewState var isExpanded: Bool

    init(key: String?, value: Any, initiallyExpanded: Bool = false) {
        self.key = key
        self.value = value
        _isExpanded = ViewState(initialValue: initiallyExpanded)
    }

    var body: some View {
        if let dict = value as? [String: Any] {
            let sortedKeys = dict.keys.sorted()
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(sortedKeys, id: \.self) { k in
                        if let child = dict[k] {
                            JSONTreeNodeView(key: k, value: child, initiallyExpanded: false)
                        }
                    }
                }
                .padding(.leading, 14)
            } label: {
                HStack(spacing: 4) {
                    if let key {
                        Text("\"\(key)\":")
                            .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.purple)
                    }
                    Text("{ \(sortedKeys.count) }")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        } else if let array = value as? [Any] {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(array.enumerated()), id: \.offset) { idx, child in
                        JSONTreeNodeView(key: "[\(idx)]", value: child, initiallyExpanded: false)
                    }
                }
                .padding(.leading, 14)
            } label: {
                HStack(spacing: 4) {
                    if let key {
                        Text("\"\(key)\":")
                            .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.purple)
                    }
                    Text("[ \(array.count) ]")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            HStack(spacing: 6) {
                if let key {
                    Text("\"\(key)\":")
                        .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.purple)
                }
                Text(formattedLeafValue)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(leafColor)
                    .textSelection(.enabled)
            }
            .padding(.leading, 4)
        }
    }

    private var formattedLeafValue: String {
        if let str = value as? String {
            return "\"\(str)\""
        }
        if value is NSNull {
            return "null"
        }
        if let num = value as? NSNumber {
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                return num.boolValue ? "true" : "false"
            }
            return num.stringValue
        }
        return "\(value)"
    }

    private var leafColor: Color {
        if value is String { return .green }
        if value is NSNull { return .secondary }
        return .blue
    }
}
