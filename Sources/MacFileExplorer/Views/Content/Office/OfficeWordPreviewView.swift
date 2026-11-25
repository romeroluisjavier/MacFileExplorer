import AppKit
import Observation
import SwiftUI

// MARK: - Controlador del Editor Nativo de Word (NSTextView + OOXML)

@MainActor
@Observable
public final class WordEditorController {
    public weak var textView: NSTextView?

    public var selectedFontFamily: String = "Helvetica Neue"
    public var selectedFontSize: Double = 13
    public var isBold: Bool = false
    public var isItalic: Bool = false
    public var isUnderline: Bool = false
    public var isStrikethrough: Bool = false
    public var alignment: NSTextAlignment = .left
    public var wordCount: Int = 0
    public var charCount: Int = 0
    public var hasUnsavedChanges: Bool = false
    public var canUndo: Bool = false
    public var canRedo: Bool = false
    public var statusToast: String? = nil

    public static let fontFamilies: [String] = [
        "Helvetica Neue",
        "Arial",
        "Times New Roman",
        "Georgia",
        "Verdana",
        "Courier New",
        "Menlo"
    ]

    public static let fontSizes: [Double] = [9, 10, 11, 12, 13, 14, 16, 18, 20, 24, 28, 36, 48]

    public func syncFromSelection() {
        guard let tv = textView else { return }
        let attrs = tv.typingAttributes
        if let font = attrs[.font] as? NSFont {
            let traits = NSFontManager.shared.traits(of: font)
            isBold = traits.contains(.boldFontMask)
            isItalic = traits.contains(.italicFontMask)
            selectedFontSize = Double(round(font.pointSize))
            if let family = font.familyName, Self.fontFamilies.contains(family) {
                selectedFontFamily = family
            }
        }
        let underlineVal = (attrs[.underlineStyle] as? Int) ?? 0
        isUnderline = underlineVal != 0
        let strikeVal = (attrs[.strikethroughStyle] as? Int) ?? 0
        isStrikethrough = strikeVal != 0
        if let para = attrs[.paragraphStyle] as? NSParagraphStyle {
            alignment = para.alignment
        }
        canUndo = tv.undoManager?.canUndo ?? false
        canRedo = tv.undoManager?.canRedo ?? false
        updateWordAndCharCount()
    }

    public func updateWordAndCharCount() {
        guard let str = textView?.string else {
            wordCount = 0
            charCount = 0
            return
        }
        charCount = str.count
        wordCount = str.split { $0.isWhitespace || $0.isNewline }.count
    }

    // MARK: - Acciones de Portapapeles e Historial

    public func undo() {
        textView?.undoManager?.undo()
        syncFromSelection()
    }

    public func redo() {
        textView?.undoManager?.redo()
        syncFromSelection()
    }

    public func cut() {
        textView?.cut(nil)
        markDirtyAndSync()
    }

    public func copy() {
        textView?.copy(nil)
    }

    public func pasteRich() {
        textView?.paste(nil)
        markDirtyAndSync()
    }

    public func pastePlainText() {
        textView?.pasteAsPlainText(nil)
        markDirtyAndSync()
    }

    public func openFindBar() {
        guard let tv = textView else { return }
        tv.window?.makeFirstResponder(tv)
        let item = NSMenuItem()
        item.tag = Int(NSTextFinder.Action.showFindInterface.rawValue)
        tv.performFindPanelAction(item)
    }

    // MARK: - Acciones de Formato Estilo LibreOffice Writer / Word

    public func applyFontFamily(_ family: String) {
        selectedFontFamily = family
        applyFontTransform { currentFont in
            let traits = NSFontManager.shared.traits(of: currentFont)
            return NSFontManager.shared.font(
                withFamily: family,
                traits: traits,
                weight: traits.contains(.boldFontMask) ? 9 : 5,
                size: currentFont.pointSize
            ) ?? currentFont
        }
    }

    public func applyFontSize(_ size: Double) {
        let clamped = min(max(size, 8), 72)
        selectedFontSize = clamped
        applyFontTransform { currentFont in
            NSFontManager.shared.convert(currentFont, toSize: CGFloat(clamped))
        }
    }

    public func stepFontSize(delta: Double) {
        applyFontSize(selectedFontSize + delta)
    }

    public func toggleBold() {
        let enable = !isBold
        applyFontTransform { currentFont in
            enable
                ? NSFontManager.shared.convert(currentFont, toHaveTrait: .boldFontMask)
                : NSFontManager.shared.convert(currentFont, toNotHaveTrait: .boldFontMask)
        }
    }

    public func toggleItalic() {
        let enable = !isItalic
        applyFontTransform { currentFont in
            enable
                ? NSFontManager.shared.convert(currentFont, toHaveTrait: .italicFontMask)
                : NSFontManager.shared.convert(currentFont, toNotHaveTrait: .italicFontMask)
        }
    }

    public func toggleUnderline() {
        let next = isUnderline ? 0 : NSUnderlineStyle.single.rawValue
        applyAttribute(.underlineStyle, value: next)
    }

    public func toggleStrikethrough() {
        let next = isStrikethrough ? 0 : NSUnderlineStyle.single.rawValue
        applyAttribute(.strikethroughStyle, value: next)
    }

    public func applyTextColor(_ color: NSColor) {
        applyAttribute(.foregroundColor, value: color)
    }

    public func applyHighlightColor(_ color: NSColor?) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = tv.selectedRange()
        if range.length > 0 {
            if tv.shouldChangeText(in: range, replacementString: nil) {
                storage.beginEditing()
                if let color {
                    storage.addAttribute(.backgroundColor, value: color, range: range)
                } else {
                    storage.removeAttribute(.backgroundColor, range: range)
                }
                storage.endEditing()
                tv.didChangeText()
            }
        } else {
            var typing = tv.typingAttributes
            if let color {
                typing[.backgroundColor] = color
            } else {
                typing.removeValue(forKey: .backgroundColor)
            }
            tv.typingAttributes = typing
        }
        markDirtyAndSync()
    }

    public func clearFormatting() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = tv.selectedRange()
        let baseFont = NSFont.systemFont(ofSize: 13)
        let defaultAttrs: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: NSColor.textColor,
            .underlineStyle: 0,
            .strikethroughStyle: 0
        ]
        if range.length > 0 {
            if tv.shouldChangeText(in: range, replacementString: nil) {
                storage.beginEditing()
                storage.removeAttribute(.backgroundColor, range: range)
                storage.addAttributes(defaultAttrs, range: range)
                storage.endEditing()
                tv.didChangeText()
            }
        } else {
            tv.typingAttributes = defaultAttrs
        }
        markDirtyAndSync()
    }

    public func applyAlignment(_ target: NSTextAlignment) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        alignment = target
        let nsString = storage.string as NSString
        let sel = tv.selectedRange()
        let paraRange = nsString.paragraphRange(for: sel)
        if paraRange.length > 0 {
            if tv.shouldChangeText(in: paraRange, replacementString: nil) {
                storage.beginEditing()
                storage.enumerateAttribute(.paragraphStyle, in: paraRange) { value, subRange, _ in
                    let mutable = ((value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                    mutable.alignment = target
                    storage.addAttribute(.paragraphStyle, value: mutable, range: subRange)
                }
                storage.endEditing()
                tv.didChangeText()
            }
        } else {
            let mutable = ((tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            mutable.alignment = target
            tv.typingAttributes[.paragraphStyle] = mutable
        }
        markDirtyAndSync()
    }

    public func insertList(numbered: Bool) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let nsString = storage.string as NSString
        let sel = tv.selectedRange()
        let paraRange = nsString.paragraphRange(for: sel)
        let chunk = nsString.substring(with: paraRange)
        let lines = chunk.components(separatedBy: .newlines)
        var counter = 1
        let transformed = lines.map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return line }
            let prefix = numbered ? "\(counter). " : "• "
            counter += 1
            if line.hasPrefix("• ") {
                return numbered ? prefix + String(line.dropFirst(2)) : String(line.dropFirst(2))
            }
            return prefix + line
        }.joined(separator: "\n")

        if tv.shouldChangeText(in: paraRange, replacementString: transformed) {
            storage.replaceCharacters(in: paraRange, with: transformed)
            tv.didChangeText()
            markDirtyAndSync()
        }
    }

    public func adjustIndent(delta: CGFloat) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let nsString = storage.string as NSString
        let paraRange = nsString.paragraphRange(for: tv.selectedRange())
        guard paraRange.length > 0 else { return }
        if tv.shouldChangeText(in: paraRange, replacementString: nil) {
            storage.beginEditing()
            storage.enumerateAttribute(.paragraphStyle, in: paraRange) { value, subRange, _ in
                let mutable = ((value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                mutable.headIndent = max(0, mutable.headIndent + delta)
                mutable.firstLineHeadIndent = max(0, mutable.firstLineHeadIndent + delta)
                storage.addAttribute(.paragraphStyle, value: mutable, range: subRange)
            }
            storage.endEditing()
            tv.didChangeText()
            markDirtyAndSync()
        }
    }

    // MARK: - Guardado Nativo (.docx / .rtf / .odt)

    public func save(to url: URL) throws {
        guard let tv = textView else { return }
        let attrStr = tv.attributedString()
        let fullRange = NSRange(location: 0, length: attrStr.length)
        let ext = url.pathExtension.lowercased()

        let docType: NSAttributedString.DocumentType
        switch ext {
        case "rtf":
            docType = .rtf
        case "odt":
            docType = .openDocument
        default:
            docType = .officeOpenXML
        }

        let data = try attrStr.data(from: fullRange, documentAttributes: [.documentType: docType])
        try data.write(to: url, options: .atomic)
    }

    public func showToast(_ message: String) {
        statusToast = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.8))
            if statusToast == message { statusToast = nil }
        }
    }

    // MARK: - Helpers Privados

    private func applyFontTransform(_ transform: (NSFont) -> NSFont) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = tv.selectedRange()
        if range.length > 0 {
            if tv.shouldChangeText(in: range, replacementString: nil) {
                storage.beginEditing()
                storage.enumerateAttribute(.font, in: range) { value, subRange, _ in
                    let base = (value as? NSFont) ?? NSFont.systemFont(ofSize: CGFloat(selectedFontSize))
                    storage.addAttribute(.font, value: transform(base), range: subRange)
                }
                storage.endEditing()
                tv.didChangeText()
            }
        } else {
            let base = (tv.typingAttributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: CGFloat(selectedFontSize))
            tv.typingAttributes[.font] = transform(base)
        }
        markDirtyAndSync()
    }

    private func applyAttribute(_ key: NSAttributedString.Key, value: Any) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = tv.selectedRange()
        if range.length > 0 {
            if tv.shouldChangeText(in: range, replacementString: nil) {
                storage.beginEditing()
                storage.addAttribute(key, value: value, range: range)
                storage.endEditing()
                tv.didChangeText()
            }
        } else {
            tv.typingAttributes[key] = value
        }
        markDirtyAndSync()
    }

    private func markDirtyAndSync() {
        hasUnsavedChanges = true
        syncFromSelection()
    }
}

// MARK: - Envoltorio NSViewRepresentable sobre NSTextView con Hoja estilo Documento

private struct WordRichTextEditorRepresentable: NSViewRepresentable {
    let initialAttributedString: NSAttributedString
    let controller: WordEditorController

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor

        if let textView = scrollView.documentView as? NSTextView {
            textView.delegate = context.coordinator
            textView.isEditable = true
            textView.isSelectable = true
            textView.isRichText = true
            textView.importsGraphics = true
            textView.allowsUndo = true
            textView.usesFindBar = true
            textView.isIncrementalSearchingEnabled = true
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.textContainerInset = NSSize(width: 36, height: 28)
            textView.backgroundColor = NSColor.textBackgroundColor
            textView.textStorage?.setAttributedString(initialAttributedString)
            controller.textView = textView
            DispatchQueue.main.async {
                controller.syncFromSelection()
            }
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let textView = nsView.documentView as? NSTextView, controller.textView !== textView {
            controller.textView = textView
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let controller: WordEditorController
        init(controller: WordEditorController) {
            self.controller = controller
        }
        func textDidChange(_ notification: Notification) {
            controller.hasUnsavedChanges = true
            controller.syncFromSelection()
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            controller.syncFromSelection()
        }
    }
}

// MARK: - Vista Principal de Microsoft Word (.docx / .doc / .rtf / .odt)

public struct OfficeWordPreviewView: View {
    public let fileURL: URL

    @Bindable private var loc = LocalizationManager.shared
    @Bindable private var officePrefs = OfficePreferences.shared
    @ViewState private var controller = WordEditorController()
    @ViewState private var loadedAttributedString: NSAttributedString? = nil
    @ViewState private var isLoading: Bool = true
    @ViewState private var loadError: String? = nil
    @ViewState private var showOriginalQuickLook: Bool = true

    public init(fileURL: URL) {
        self.fileURL = fileURL
        _showOriginalQuickLook = ViewState(initialValue: OfficePreferences.shared.shouldOpenInOriginalView)
    }

    private var effectiveShowOriginal: Bool {
        !officePrefs.isOfficeEditingEnabled || showOriginalQuickLook
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if effectiveShowOriginal {
                NativeQLPreviewRepresentable(fileURL: fileURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                    Text(loadError)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                    Button(loc.text(es: "Ver con Vista original (Quick Look)", en: "View Original Layout (Quick Look)")) {
                        showOriginalQuickLook = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let content = loadedAttributedString {
                writerToolbarRow1
                Divider()
                writerToolbarRow2
                Divider()
                WordRichTextEditorRepresentable(initialAttributedString: content, controller: controller)
                    .id(fileURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                statusBar
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: fileURL) {
            await loadWordDocument()
        }
        .background {
            Group {
                Button("") { saveDocument() }.keyboardShortcut("s", modifiers: [.command])
                Button("") { saveDocumentCopy() }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button("") { controller.openFindBar() }.keyboardShortcut("f", modifiers: [.command])
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        }
    }

    private var headerBar: some View {
        HStack(spacing: 10) {
            Label(
                loc.text(es: "Microsoft Word · Editor rápido", en: "Microsoft Word · Quick Editor"),
                systemImage: OfficeDocumentKind.word.symbolName
            )
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(OfficeDocumentKind.word.accentColor)

            if controller.hasUnsavedChanges {
                Text(loc.text(es: "Sin guardar", en: "Unsaved"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Color.orange.opacity(0.14), in: Capsule())
            }

            Spacer()

            if officePrefs.isOfficeEditingEnabled {
                Picker("", selection: $showOriginalQuickLook) {
                    Text(loc.text(es: "Vista original", en: "Original View")).tag(true)
                    Text(loc.text(es: "Editor", en: "Editor")).tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
            } else {
                Text(loc.text(es: "Solo lectura", en: "Read-Only"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.035))
    }

    private var writerToolbarRow1: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button {
                    saveDocument()
                } label: {
                    HStack(spacing: 6) {
                        FloppyDiskIconView(size: PreviewToolbarMetrics.iconSize)
                        Text(loc.text(es: "Guardar", en: "Save"))
                            .font(.system(size: PreviewToolbarMetrics.labelFontSize, weight: .semibold))
                        if controller.hasUnsavedChanges {
                            Circle().fill(Color.orange).frame(width: 6, height: 6)
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .buttonStyle(PreviewToolbarButtonStyle(variant: .prominent))
                .help(loc.text(es: "Guardar documento (⌘S)", en: "Save document (⌘S)"))

                Button {
                    saveDocumentCopy()
                } label: {
                    HStack(spacing: 6) {
                        FloppyDiskCopyIconView(size: PreviewToolbarMetrics.iconSize)
                        Text(loc.text(es: "Guardar copia…", en: "Save Copy…"))
                            .font(.system(size: PreviewToolbarMetrics.labelFontSize, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                }
                .buttonStyle(PreviewToolbarButtonStyle(variant: .standard))
                .help(loc.text(es: "Guardar como una copia nueva (⇧⌘S)", en: "Save as a new copy (⇧⌘S)"))

                Divider().frame(height: 16)

                iconBtn("arrow.uturn.backward", help: loc.text(es: "Deshacer (⌘Z)", en: "Undo (⌘Z)"), disabled: !controller.canUndo) { controller.undo() }
                iconBtn("arrow.uturn.forward", help: loc.text(es: "Rehacer (⇧⌘Z)", en: "Redo (⇧⌘Z)"), disabled: !controller.canRedo) { controller.redo() }

                Divider().frame(height: 16)

                iconBtn("scissors", help: loc.text(es: "Cortar (⌘X)", en: "Cut (⌘X)")) { controller.cut() }
                iconBtn("doc.on.doc", help: loc.text(es: "Copiar (⌘C)", en: "Copy (⌘C)")) { controller.copy() }
                iconBtn("doc.on.clipboard", help: loc.text(es: "Pegar con formato e imágenes (⌘V)", en: "Paste rich text & images (⌘V)")) { controller.pasteRich() }
                iconBtn("doc.plaintext", help: loc.text(es: "Pegar sin formato (⇧⌘V)", en: "Paste without formatting (⇧⌘V)")) { controller.pastePlainText() }

                Divider().frame(height: 16)

                iconBtn("magnifyingglass", help: loc.text(es: "Buscar y reemplazar (⌘F)", en: "Find & Replace (⌘F)")) { controller.openFindBar() }
                iconBtn("eraser", help: loc.text(es: "Limpiar formato del texto seleccionado", en: "Clear formatting on selection")) { controller.clearFormatting() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .background(Color.primary.opacity(0.025))
    }

    private var writerToolbarRow2: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Familia tipográfica
                Picker("", selection: Binding(
                    get: { controller.selectedFontFamily },
                    set: { controller.applyFontFamily($0) }
                )) {
                    ForEach(WordEditorController.fontFamilies, id: \.self) { fam in
                        Text(fam).tag(fam)
                    }
                }
                .labelsHidden()
                .frame(width: 126)
                .controlSize(.small)

                // Tamaño + A- / A+
                Picker("", selection: Binding(
                    get: { controller.selectedFontSize },
                    set: { controller.applyFontSize($0) }
                )) {
                    ForEach(WordEditorController.fontSizes, id: \.self) { sz in
                        Text("\(Int(sz)) pt").tag(sz)
                    }
                }
                .labelsHidden()
                .frame(width: 68)
                .controlSize(.small)

                iconBtn("textformat.size.smaller", help: loc.text(es: "Reducir tamaño de fuente (A-)", en: "Decrease font size (A-)")) { controller.stepFontSize(delta: -1) }
                iconBtn("textformat.size.larger", help: loc.text(es: "Aumentar tamaño de fuente (A+)", en: "Increase font size (A+)")) { controller.stepFontSize(delta: 1) }

                Divider().frame(height: 16)

                // B / I / U / S
                toggleCharBtn("B", bold: true, active: controller.isBold, help: loc.text(es: "Negrita (⌘B)", en: "Bold (⌘B)")) { controller.toggleBold() }
                toggleCharBtn("I", italic: true, active: controller.isItalic, help: loc.text(es: "Cursiva (⌘I)", en: "Italic (⌘I)")) { controller.toggleItalic() }
                toggleCharBtn("U", underline: true, active: controller.isUnderline, help: loc.text(es: "Subrayado (⌘U)", en: "Underline (⌘U)")) { controller.toggleUnderline() }
                toggleCharBtn("S", strikethrough: true, active: controller.isStrikethrough, help: loc.text(es: "Tachado", en: "Strikethrough")) { controller.toggleStrikethrough() }

                Divider().frame(height: 16)

                // Color de texto
                Menu {
                    Button(loc.text(es: "Automático", en: "Automatic")) { controller.applyTextColor(.textColor) }
                    Button(loc.text(es: "Negro", en: "Black")) { controller.applyTextColor(.black) }
                    Button(loc.text(es: "Azul", en: "Blue")) { controller.applyTextColor(.systemBlue) }
                    Button(loc.text(es: "Rojo", en: "Red")) { controller.applyTextColor(.systemRed) }
                    Button(loc.text(es: "Verde", en: "Green")) { controller.applyTextColor(.systemGreen) }
                    Button(loc.text(es: "Naranja", en: "Orange")) { controller.applyTextColor(.systemOrange) }
                    Button(loc.text(es: "Violeta", en: "Purple")) { controller.applyTextColor(.systemPurple) }
                    Button(loc.text(es: "Gris", en: "Gray")) { controller.applyTextColor(.secondaryLabelColor) }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "textformat")
                            .font(.system(size: PreviewToolbarMetrics.iconSize, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 36, height: PreviewToolbarMetrics.controlHeight)
                    .background(
                        RoundedRectangle(cornerRadius: PreviewToolbarMetrics.cornerRadius, style: .continuous)
                            .fill(Color.primary.opacity(0.085))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: PreviewToolbarMetrics.cornerRadius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.11), lineWidth: 0.75)
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(loc.text(es: "Color de texto", en: "Text color"))

                // Color de resaltado (marcador)
                Menu {
                    Button(loc.text(es: "Sin resaltado", en: "No Highlight")) { controller.applyHighlightColor(nil) }
                    Button(loc.text(es: "Amarillo", en: "Yellow")) { controller.applyHighlightColor(NSColor.systemYellow.withAlphaComponent(0.45)) }
                    Button(loc.text(es: "Verde", en: "Green")) { controller.applyHighlightColor(NSColor.systemGreen.withAlphaComponent(0.32)) }
                    Button(loc.text(es: "Celeste", en: "Cyan")) { controller.applyHighlightColor(NSColor.systemCyan.withAlphaComponent(0.32)) }
                    Button(loc.text(es: "Rosa", en: "Pink")) { controller.applyHighlightColor(NSColor.systemPink.withAlphaComponent(0.32)) }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "highlighter")
                            .font(.system(size: PreviewToolbarMetrics.iconSize, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 36, height: PreviewToolbarMetrics.controlHeight)
                    .background(
                        RoundedRectangle(cornerRadius: PreviewToolbarMetrics.cornerRadius, style: .continuous)
                            .fill(Color.primary.opacity(0.085))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: PreviewToolbarMetrics.cornerRadius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.11), lineWidth: 0.75)
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(loc.text(es: "Color de resaltado", en: "Highlight color"))

                Divider().frame(height: 16)

                // Alineación de párrafo
                iconBtn("text.alignleft", active: controller.alignment == .left, help: loc.text(es: "Alinear a la izquierda", en: "Align left")) { controller.applyAlignment(.left) }
                iconBtn("text.aligncenter", active: controller.alignment == .center, help: loc.text(es: "Centrar", en: "Align center")) { controller.applyAlignment(.center) }
                iconBtn("text.alignright", active: controller.alignment == .right, help: loc.text(es: "Alinear a la derecha", en: "Align right")) { controller.applyAlignment(.right) }
                iconBtn("text.justify", active: controller.alignment == .justified, help: loc.text(es: "Justificar", en: "Justify")) { controller.applyAlignment(.justified) }

                Divider().frame(height: 16)

                // Listas y sangría
                iconBtn("list.bullet", help: loc.text(es: "Lista con viñetas", en: "Bulleted list")) { controller.insertList(numbered: false) }
                iconBtn("list.number", help: loc.text(es: "Lista numerada", en: "Numbered list")) { controller.insertList(numbered: true) }
                iconBtn("decrease.indent", help: loc.text(es: "Reducir sangría", en: "Decrease indent")) { controller.adjustIndent(delta: -18) }
                iconBtn("increase.indent", help: loc.text(es: "Aumentar sangría", en: "Increase indent")) { controller.adjustIndent(delta: 18) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .background(Color.primary.opacity(0.018))
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Text(loc.text(
                es: "\(controller.wordCount) palabras · \(controller.charCount) caracteres",
                en: "\(controller.wordCount) words · \(controller.charCount) characters"
            ))
            .monospacedDigit()

            if let toast = controller.statusToast {
                Text("· \(toast)")
                    .foregroundStyle(Color.accentColor)
                    .fontWeight(.medium)
            }

            Spacer()

            Text(fileURL.pathExtension.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03))
    }

    private func loadWordDocument() async {
        isLoading = true
        loadError = nil
        let targetURL = fileURL
        let result = await Task.detached(priority: .userInitiated) { () -> Result<Data, Error> in
            Result { try Data(contentsOf: targetURL) }
        }.value

        switch result {
        case .success(let data):
            do {
                let ext = targetURL.pathExtension.lowercased()
                var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [:]
                switch ext {
                case "docx": options[.documentType] = NSAttributedString.DocumentType.officeOpenXML
                case "doc": options[.documentType] = NSAttributedString.DocumentType.docFormat
                case "rtf": options[.documentType] = NSAttributedString.DocumentType.rtf
                case "odt": options[.documentType] = NSAttributedString.DocumentType.openDocument
                default: break
                }
                let attr = try NSAttributedString(data: data, options: options, documentAttributes: nil)
                loadedAttributedString = attr
                controller.hasUnsavedChanges = false
            } catch {
                loadError = error.localizedDescription
            }
        case .failure(let error):
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func saveDocument() {
        let ext = fileURL.pathExtension.lowercased()
        // El formato binario `.doc` antiguo no tiene escritor nativo en macOS: ofrece guardar copia en `.docx`
        if ext == "doc" {
            saveDocumentCopy(preferredExtension: "docx")
            return
        }
        do {
            try controller.save(to: fileURL)
            controller.hasUnsavedChanges = false
            controller.showToast(loc.text(es: "Documento guardado", en: "Document saved"))
        } catch {
            controller.showToast(error.localizedDescription)
        }
    }

    private func saveDocumentCopy(preferredExtension: String? = nil) {
        let ext = preferredExtension ?? (fileURL.pathExtension.lowercased() == "doc" ? "docx" : fileURL.pathExtension)
        guard let dest = OfficeSavePanelHelper.chooseCopyDestination(
            originalURL: fileURL,
            preferredExtension: ext,
            title: loc.text(es: "Guardar copia del documento", en: "Save Document Copy")
        ) else { return }
        do {
            try controller.save(to: dest)
            controller.showToast(loc.text(es: "Copia guardada", en: "Copy saved"))
        } catch {
            controller.showToast(error.localizedDescription)
        }
    }

    private func iconBtn(_ symbol: String, active: Bool = false, help: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        PreviewToolbarIconButton(symbol, active: active, help: help, disabled: disabled, action: action)
    }

    private func toggleCharBtn(
        _ text: String,
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        strikethrough: Bool = false,
        active: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        PreviewToolbarToggleCharButton(
            text,
            bold: bold,
            italic: italic,
            underline: underline,
            strikethrough: strikethrough,
            active: active,
            help: help,
            action: action
        )
    }
}
