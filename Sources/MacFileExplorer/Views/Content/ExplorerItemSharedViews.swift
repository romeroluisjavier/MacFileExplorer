import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// PreferenceKey para registrar los marcos (`CGRect`) de cada elemento renderizado y permitir
/// la selección múltiple mediante cuadro de arrastre ("rubber-band selection").
public struct ItemFramePreferenceKey: PreferenceKey {
    public static let defaultValue: [FileItem.ID: CGRect] = [:]

    public static func reduce(
        value: inout [FileItem.ID: CGRect],
        nextValue: () -> [FileItem.ID: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Rectángulo visual translúcido de selección por arrastre (estilo Windows Explorer / Finder).
public struct RubberBandSelectionOverlay: View {
    public let rect: CGRect?

    public init(rect: CGRect?) {
        self.rect = rect
    }

    public var body: some View {
        if let rect, rect.width > 2 || rect.height > 2 {
            Rectangle()
                .fill(Color.accentColor.opacity(0.16))
                .overlay(
                    Rectangle()
                        .strokeBorder(Color.accentColor.opacity(0.75), lineWidth: 1)
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
        }
    }
}

/// Campo de texto en línea para renombrar archivos o carpetas (`F2` / `Enter`).
/// Selecciona automáticamente solo el nombre base (sin la extensión en archivos, ej. `ecoway` en `ecoway.zip`).
public struct InlineRenameTextField: View {
    @Bindable var viewModel: ExplorerViewModel
    let alignment: TextAlignment

    public init(viewModel: ExplorerViewModel, alignment: TextAlignment = .leading) {
        self.viewModel = viewModel
        self.alignment = alignment
    }

    private var targetItem: FileItem? {
        guard let itemID = viewModel.renamingItemID else { return nil }
        return viewModel.allItems.first(where: { $0.id == itemID })
    }

    public var body: some View {
        AppKitRenameTextField(
            text: $viewModel.renamingDraftName,
            itemID: viewModel.renamingItemID,
            isDirectory: targetItem?.isNavigableFolder ?? false,
            alignment: alignment,
            onCommit: {
                viewModel.commitRename()
            },
            onCancel: {
                viewModel.cancelRename()
            }
        )
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 1.5)
        )
    }
}

private final class RenameNSTextField: NSTextField {
    var onMoveToWindow: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            onMoveToWindow?()
        }
    }
}

private struct AppKitRenameTextField: NSViewRepresentable {
    @Binding var text: String
    let itemID: FileItem.ID?
    let isDirectory: Bool
    let alignment: TextAlignment
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> RenameNSTextField {
        let field = RenameNSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        field.textColor = .labelColor
        field.alignment = nsAlignment
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingMiddle
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.stringValue = text

        let coordinator = context.coordinator
        field.onMoveToWindow = { [weak field, weak coordinator] in
            guard let field, let coordinator else { return }
            coordinator.focusAndSelectStemIfNeeded(on: field)
        }
        return field
    }

    func updateNSView(_ nsView: RenameNSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.alignment != nsAlignment {
            nsView.alignment = nsAlignment
        }
        if nsView.stringValue != text, nsView.currentEditor() == nil {
            nsView.stringValue = text
        }
        if context.coordinator.activeItemID != itemID {
            context.coordinator.activeItemID = itemID
            context.coordinator.didApplyInitialSelection = false
            context.coordinator.didFinishEditing = false
            nsView.stringValue = text
        }
        context.coordinator.focusAndSelectStemIfNeeded(on: nsView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: RenameNSTextField, context: Context) -> CGSize? {
        let intrinsic = nsView.intrinsicContentSize
        let width = proposal.width ?? max(80, intrinsic.width)
        return CGSize(width: width, height: max(18, intrinsic.height))
    }

    private var nsAlignment: NSTextAlignment {
        switch alignment {
        case .leading:
            return .left
        case .center:
            return .center
        case .trailing:
            return .right
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AppKitRenameTextField
        var activeItemID: FileItem.ID?
        var didApplyInitialSelection: Bool = false
        var didFinishEditing: Bool = false

        init(_ parent: AppKitRenameTextField) {
            self.parent = parent
            self.activeItemID = parent.itemID
        }

        func focusAndSelectStemIfNeeded(on field: RenameNSTextField) {
            guard !didApplyInitialSelection, let window = field.window else { return }
            didApplyInitialSelection = true

            DispatchQueue.main.async { [weak self, weak field, weak window] in
                guard let self, let field, let window else { return }
                guard self.parent.itemID != nil else { return }

                if window.firstResponder !== field && window.firstResponder !== field.currentEditor() {
                    window.makeFirstResponder(field)
                }

                let selectionRange = Self.stemSelectionRange(
                    for: field.stringValue,
                    isDirectory: self.parent.isDirectory
                )

                if let editor = field.currentEditor() as? NSTextView {
                    editor.selectedRange = selectionRange
                } else {
                    DispatchQueue.main.async { [weak field] in
                        if let editor = field?.currentEditor() as? NSTextView {
                            editor.selectedRange = selectionRange
                        }
                    }
                }
            }
        }

        /// Calcula el rango de selección inicial excluyendo la extensión en archivos (ej. "ecoway" en "ecoway.zip").
        static func stemSelectionRange(for name: String, isDirectory: Bool) -> NSRange {
            let nsName = name as NSString
            let fullLength = nsName.length
            guard fullLength > 0, !isDirectory else {
                return NSRange(location: 0, length: fullLength)
            }

            let lastDotRange = nsName.range(of: ".", options: .backwards)
            if lastDotRange.location != NSNotFound, lastDotRange.location > 0 {
                return NSRange(location: 0, length: lastDotRange.location)
            }
            return NSRange(location: 0, length: fullLength)
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                didFinishEditing = true
                if let field = control as? NSTextField {
                    parent.text = field.stringValue
                }
                parent.onCommit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                didFinishEditing = true
                parent.onCancel()
                return true
            }
            return false
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard !didFinishEditing, parent.itemID != nil else { return }
            didFinishEditing = true
            if let field = obj.object as? NSTextField {
                parent.text = field.stringValue
            }
            parent.onCommit()
        }
    }
}

/// Menú contextual rico al hacer clic derecho sobre un archivo o carpeta.
public struct ExplorerItemContextMenu: View {
    let item: FileItem
    @Bindable var viewModel: ExplorerViewModel

    private var loc: LocalizationManager { LocalizationManager.shared }

    public init(item: FileItem, viewModel: ExplorerViewModel) {
        self.item = item
        self.viewModel = viewModel
    }

    public var body: some View {
        Group {
            Button {
                ensureSelected()
                viewModel.openItem(item)
            } label: {
                Label(
                    item.isNavigableFolder
                        ? loc.text(es: "Abrir carpeta", en: "Open folder")
                        : loc.text(es: "Abrir", en: "Open"),
                    systemImage: item.isNavigableFolder ? "folder" : "arrow.up.forward.app"
                )
            }

            if item.isZipArchive {
                Button {
                    ensureSelected()
                    viewModel.unarchiveItem(item)
                } label: {
                    Label(
                        loc.text(es: "Desarchivar", en: "Unarchive"),
                        systemImage: "doc.zipper"
                    )
                }
            }

            // Submenú "Open with... / Abrir con..." con todas las aplicaciones compatibles del sistema
            Menu {
                openWithMenuItems
            } label: {
                Label(
                    loc.text(es: "Abrir con...", en: "Open with..."),
                    systemImage: "arrow.up.forward.square"
                )
            }

            Button {
                ensureSelected()
                viewModel.isQuickLookPresented = true
            } label: {
                Label(loc.text(es: "Vista Rápida (Espacio)", en: "Quick Look (Space)"), systemImage: "eye")
            }

            if !item.isNavigableFolder {
                Button {
                    viewModel.openInNativePreviewApp(item)
                } label: {
                    Label("Open in Preview", systemImage: "arrow.up.forward.app.fill")
                }
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Label(loc.text(es: "Mostrar en Finder", en: "Show in Finder"), systemImage: "macwindow")
            }

            if item.isNavigableFolder {
                Button {
                    viewModel.openTerminal(at: item.url)
                } label: {
                    Label(loc.text(es: "Abrir Terminal aquí...", en: "Open Terminal here..."), systemImage: "terminal")
                }
            }

            Divider()

            Button {
                ensureSelected()
                viewModel.cutSelectedItems()
            } label: {
                Label(loc.text(es: "Cortar", en: "Cut"), systemImage: "scissors")
            }

            Button {
                ensureSelected()
                viewModel.copySelectedItems()
            } label: {
                Label(loc.text(es: "Copiar", en: "Copy"), systemImage: "doc.on.doc")
            }

            if viewModel.canPaste {
                Button {
                    viewModel.pasteItems()
                } label: {
                    Label(loc.text(es: "Pegar en carpeta actual", en: "Paste into current folder"), systemImage: "doc.on.clipboard")
                }
            }

            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(item.url.path(percentEncoded: false), forType: .string)
            } label: {
                Label(loc.text(es: "Copiar como ruta", en: "Copy as path"), systemImage: "link")
            }

            Divider()

            Button {
                viewModel.selectedItemIDs = [item.id]
                viewModel.selectionAnchorID = item.id
                viewModel.beginRenamingSelectedItem()
            } label: {
                Label(loc.text(es: "Renombrar (F2)", en: "Rename (F2)"), systemImage: "character.cursor.ibeam")
            }

            Button(role: .destructive) {
                ensureSelected()
                viewModel.moveSelectedItemsToTrash()
            } label: {
                Label(loc.text(es: "Mover a la Papelera", en: "Move to Trash"), systemImage: "trash")
            }

            Button(role: .destructive) {
                ensureSelected()
                viewModel.requestPermanentDeleteSelectedItems()
            } label: {
                Label(
                    loc.text(es: "Eliminar permanentemente (⇧⌫)", en: "Delete permanently (⇧⌫)"),
                    systemImage: "trash.slash"
                )
            }

            Divider()

            Button {
                ensureSelected()
                viewModel.showProperties(for: item)
            } label: {
                Label(loc.text(es: "Propiedades", en: "Properties"), systemImage: "info.circle")
            }

            AddToGeminiMenuButton(viewModel: viewModel) {
                targetURLsToOpen()
            }
        }
    }

    // MARK: - Submenú "Open with... / Abrir con..."

    @ViewBuilder
    private var openWithMenuItems: some View {
        let defaultApp = defaultApplicationURL()
        let otherApps = otherCompatibleApplicationURLs(excluding: defaultApp)

        if let defaultApp {
            Button {
                openTargetItems(withApplicationAt: defaultApp)
            } label: {
                Label {
                    Text("\(appDisplayName(for: defaultApp)) (\(loc.text(es: "Predeterminada", en: "Default")))")
                } icon: {
                    Image(nsImage: appMenuIcon(for: defaultApp))
                }
            }

            Divider()
        }

        if !otherApps.isEmpty {
            ForEach(otherApps, id: \.self) { appURL in
                Button {
                    openTargetItems(withApplicationAt: appURL)
                } label: {
                    Label {
                        Text(appDisplayName(for: appURL))
                    } icon: {
                        Image(nsImage: appMenuIcon(for: appURL))
                    }
                }
            }

            Divider()
        }

        Button {
            chooseCustomApplicationAndOpen()
        } label: {
            Label(
                loc.text(es: "Otra aplicación...", en: "Other Application..."),
                systemImage: "ellipsis.circle"
            )
        }
    }

    private func defaultApplicationURL() -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: item.url)?.standardizedFileURL
    }

    private func otherCompatibleApplicationURLs(excluding defaultAppURL: URL?) -> [URL] {
        let rawApps = NSWorkspace.shared.urlsForApplications(toOpen: item.url)
        var seen: Set<URL> = []
        if let defaultAppURL {
            seen.insert(defaultAppURL.standardizedFileURL)
        }

        var uniqueApps: [URL] = []
        for url in rawApps {
            let std = url.standardizedFileURL
            guard !seen.contains(std) else { continue }
            seen.insert(std)
            uniqueApps.append(std)
        }

        uniqueApps.sort {
            appDisplayName(for: $0).localizedStandardCompare(appDisplayName(for: $1)) == .orderedAscending
        }
        return uniqueApps
    }

    private func appDisplayName(for appURL: URL) -> String {
        let rawName = FileManager.default.displayName(atPath: appURL.path(percentEncoded: false))
        if rawName.lowercased().hasSuffix(".app") {
            return String(rawName.dropLast(4))
        }
        let stem = appURL.deletingPathExtension().lastPathComponent
        return stem.isEmpty ? rawName : stem
    }

    private func appMenuIcon(for appURL: URL) -> NSImage {
        let rawIcon = NSWorkspace.shared.icon(forFile: appURL.path(percentEncoded: false))
        let sized = (rawIcon.copy() as? NSImage) ?? rawIcon
        sized.size = NSSize(width: 16, height: 16)
        return sized
    }

    private func targetURLsToOpen() -> [URL] {
        ensureSelected()
        let selectedURLs = viewModel.selectedItems.map(\.url)
        return selectedURLs.isEmpty ? [item.url] : selectedURLs
    }

    private func openTargetItems(withApplicationAt appURL: URL) {
        let urls = targetURLsToOpen()
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: config)
    }

    private func chooseCustomApplicationAndOpen() {
        let urls = targetURLsToOpen()
        let panel = NSOpenPanel()
        panel.title = loc.text(
            es: "Elegir aplicación para abrir \"\(item.name)\"",
            en: "Choose Application to open \"\(item.name)\""
        )
        panel.prompt = loc.text(es: "Abrir", en: "Open")
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let chosenAppURL = panel.url {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open(urls, withApplicationAt: chosenAppURL, configuration: config)
        }
    }

    private func ensureSelected() {
        if !viewModel.selectedItemIDs.contains(item.id) {
            viewModel.selectedItemIDs = [item.id]
            viewModel.selectionAnchorID = item.id
        }
    }
}

/// Botón reutilizable de menú contextual que replica "Add to Gemini" de Finder.
public struct AddToGeminiMenuButton: View {
    let viewModel: ExplorerViewModel
    let urlsProvider: () -> [URL]

    private var loc: LocalizationManager { LocalizationManager.shared }

    public init(viewModel: ExplorerViewModel, urls: @escaping () -> [URL]) {
        self.viewModel = viewModel
        self.urlsProvider = urls
    }

    public var body: some View {
        if let geminiIcon = viewModel.geminiMenuIcon() {
            Divider()

            Button {
                viewModel.addToGemini(urlsProvider())
            } label: {
                Label {
                    Text(loc.text(es: "Añadir a Gemini", en: "Add to Gemini"))
                } icon: {
                    Image(nsImage: geminiIcon)
                }
            }
        }
    }
}
