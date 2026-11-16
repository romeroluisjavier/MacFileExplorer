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
/// - `.md` / `.markdown`: renderizado formateado con alternancia a fuente.
/// - `.json`: árbol colapsable interactivo con colores por tipo y alternancia a texto formateado.
/// - Código fuente: numeración de líneas y resaltado de sintaxis.
public struct RichCodePreviewView: View {
    public let fileURL: URL

    @ViewState private var rawText: String = ""
    @ViewState private var loadError: String? = nil
    @ViewState private var showRawSource: Bool = false

    private var loc: LocalizationManager { LocalizationManager.shared }

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    private var ext: String {
        fileURL.pathExtension.lowercased()
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let loadError {
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
            loadFile()
        }
    }

    private func loadFile() {
        loadError = nil
        do {
            let data = try Data(contentsOf: fileURL)
            if data.count > 2_500_000 {
                let prefixData = data.prefix(2_500_000)
                rawText = (String(data: prefixData, encoding: .utf8) ?? "") + "\n\n… (archivo truncado para vista rápida)"
            } else if let str = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                rawText = str
            } else {
                loadError = loc.text(es: "No se pudo decodificar el archivo de texto.", en: "Could not decode text file.")
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: - Markdown Formateado

    private var markdownView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Markdown")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $showRawSource) {
                    Text(loc.text(es: "Formateado", en: "Formatted")).tag(false)
                    Text(loc.text(es: "Código", en: "Source")).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.03))

            Divider()

            if showRawSource {
                highlightedCodeScrollView(text: rawText, language: "md")
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(parseMarkdownBlocks(rawText).enumerated()), id: \.offset) { _, block in
                            renderMarkdownBlock(block)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(22)
                }
            }
        }
    }

    // MARK: - JSON Colapsable

    private var jsonView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("JSON")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $showRawSource) {
                    Text(loc.text(es: "Árbol colapsable", en: "Collapsible Tree")).tag(false)
                    Text(loc.text(es: "Texto formateado", en: "Pretty Text")).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.03))

            Divider()

            if showRawSource {
                highlightedCodeScrollView(text: prettyPrintedJSON(from: rawText) ?? rawText, language: "json")
            } else if let parsed = parseJSONObject(from: rawText) {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 4) {
                        JSONTreeNodeView(key: nil, value: parsed, initiallyExpanded: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
            } else {
                highlightedCodeScrollView(text: rawText, language: "json")
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
                            .frame(minWidth: 34, alignment: .trailing)

                        Text(highlightSyntax(line: line, language: language))
                            .font(.system(size: 12.5, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
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

    // MARK: - Helpers Markdown & JSON

    private enum MarkdownBlock {
        case heading(level: Int, text: String)
        case codeBlock(String)
        case quote(String)
        case bullet(String)
        case divider
        case paragraph(String)
    }

    private func parseMarkdownBlocks(_ text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var inCode = false
        var codeBuffer: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    blocks.append(.codeBlock(codeBuffer.joined(separator: "\n")))
                    codeBuffer.removeAll()
                    inCode = false
                } else {
                    inCode = true
                }
                continue
            }
            if inCode {
                codeBuffer.append(line)
                continue
            }
            if trimmed.isEmpty { continue }
            if trimmed == "---" || trimmed == "***" {
                blocks.append(.divider)
            } else if trimmed.hasPrefix("### ") {
                blocks.append(.heading(level: 3, text: String(trimmed.dropFirst(4))))
            } else if trimmed.hasPrefix("## ") {
                blocks.append(.heading(level: 2, text: String(trimmed.dropFirst(3))))
            } else if trimmed.hasPrefix("# ") {
                blocks.append(.heading(level: 1, text: String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("> ") {
                blocks.append(.quote(String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                blocks.append(.bullet(String(trimmed.dropFirst(2))))
            } else {
                blocks.append(.paragraph(trimmed))
            }
        }
        if !codeBuffer.isEmpty {
            blocks.append(.codeBlock(codeBuffer.joined(separator: "\n")))
        }
        return blocks
    }

    @ViewBuilder
    private func renderMarkdownBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            let size: CGFloat = level == 1 ? 22 : (level == 2 ? 17.5 : 15)
            inlineMarkdownText(text)
                .font(.system(size: size, weight: .bold))
                .padding(.top, 4)
        case .codeBlock(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
        case .quote(let text):
            HStack(spacing: 10) {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: 3)
                inlineMarkdownText(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        case .bullet(let text):
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.system(size: 13, weight: .bold))
                inlineMarkdownText(text)
                    .font(.system(size: 13.5))
            }
            .padding(.leading, 8)
        case .divider:
            Divider()
        case .paragraph(let text):
            inlineMarkdownText(text)
                .font(.system(size: 13.5))
        }
    }

    private func inlineMarkdownText(_ text: String) -> Text {
        if let attr = try? AttributedString(markdown: text) {
            return Text(attr)
        }
        return Text(text)
    }

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
