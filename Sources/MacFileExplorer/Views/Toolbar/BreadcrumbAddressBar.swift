import AppKit
import SwiftUI

/// Barra de ruta híbrida estilo Windows 11 Explorer:
/// - Modo por defecto: "Breadcrumb" interactivo con segmentos clicables y menú de subcarpetas en cada `>`.
/// - Clic en el segmento actual, en el espacio libre de la barra, en el icono o `Cmd+L`: activa el modo de texto plano
///   seleccionando toda la ruta para escribir o pegar directamente (por ej. `~/Documents/Proyectos`) con autocompletado.
public struct BreadcrumbAddressBar: View {
    @Bindable var viewModel: ExplorerViewModel

    @ViewState private var suggestions: [(displayText: String, fullPath: String, url: URL)] = []
    @ViewState private var highlightedSuggestionIndex: Int? = nil

    private var loc: LocalizationManager { LocalizationManager.shared }

    public init(viewModel: ExplorerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 6) {
            // Icono de carpeta/volumen actual a la izquierda de la barra de ruta (clic activa edición)
            Button {
                viewModel.beginAddressBarEditing()
            } label: {
                Image(systemName: viewModel.currentDirectoryURL.path == "/" ? "internaldrive.fill" : "folder.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor)
                    .padding(.leading, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .help(loc.text(
                es: "Haz clic o presiona ⌘L para escribir o pegar una ruta",
                en: "Click or press ⌘L to type or paste a path"
            ))

            if viewModel.isEditingAddressBar {
                // Modo Texto Plano Editable estilo Windows Explorer (selecciona toda la ruta + autocompletado)
                EditableAddressTextField(
                    text: $viewModel.addressBarText,
                    placeholder: loc.text(
                        es: "Escribe o pega una ruta (ej. ~/Documents/Proyectos)",
                        en: "Type or paste a path (e.g. ~/Documents/Projects)"
                    ),
                    suggestions: suggestions,
                    highlightedIndex: $highlightedSuggestionIndex,
                    onTextChanged: { updatedText in
                        refreshSuggestions(for: updatedText)
                    },
                    onSelectSuggestion: { selected in
                        navigateToSuggestion(selected)
                    },
                    onTabComplete: {
                        acceptTabCompletion()
                    },
                    onCommit: {
                        commitCurrentInputOrSelection()
                    },
                    onCancel: {
                        dismissSuggestionsAndCancel()
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    refreshSuggestions(for: viewModel.addressBarText)
                }
                .onDisappear {
                    PathSuggestionsPopupController.shared.hide()
                }

                Button(loc.text(es: "Ir", en: "Go")) {
                    PathSuggestionsPopupController.shared.hide()
                    viewModel.commitAddressBarNavigation()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    dismissSuggestionsAndCancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
                .help(loc.text(es: "Cancelar edición (Esc)", en: "Cancel editing (Esc)"))

            } else {
                // Modo Breadcrumb Clicable + Zona Libre Clicable estilo Windows Explorer
                ZStack(alignment: .leading) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.beginAddressBarEditing()
                        }

                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 1) {
                                let segments = viewModel.breadcrumbSegments
                                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                                    let isLast = index == segments.count - 1
                                    BreadcrumbSegmentChip(
                                        segment: segment,
                                        isCurrent: isLast,
                                        onPrimaryClick: {
                                            if isLast {
                                                // Clic en el segmento actual activa el campo editable (como Windows Explorer)
                                                viewModel.beginAddressBarEditing()
                                            } else {
                                                viewModel.navigate(to: segment.url)
                                            }
                                        },
                                        onDoubleClick: {
                                            viewModel.beginAddressBarEditing()
                                        }
                                    )
                                    .id(segment.id)
                                    .help(
                                        isLast
                                            ? loc.text(
                                                es: "Haz clic para escribir o pegar una ruta (~/Documents/Proyectos)",
                                                en: "Click to type or paste a path (~/Documents/Projects)"
                                            )
                                            : loc.text(
                                                es: "Ir a \(segment.title) (doble clic para editar ruta)",
                                                en: "Go to \(segment.title) (double-click to edit path)"
                                            )
                                    )

                                    if !isLast {
                                        let nextSegmentURL = segments[index + 1].url
                                        BreadcrumbChevronMenuButton(
                                            activeChildURL: nextSegmentURL,
                                            fetchChildren: {
                                                viewModel.breadcrumbChildFolders(in: segment.url)
                                            },
                                            onSelectFolder: { folderURL in
                                                viewModel.navigate(to: folderURL)
                                            }
                                        )
                                    }
                                }
                            }
                            .padding(.vertical, 3)
                        }
                        .onChange(of: viewModel.currentDirectoryURL) { _, newURL in
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(newURL.standardizedFileURL, anchor: .trailing)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Espacio vacío clicable adicional a la derecha para asegurar activación inmediata
                Color.clear
                    .frame(width: 24)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.beginAddressBarEditing()
                    }
                    .help(loc.text(
                        es: "Haz clic aquí o presiona ⌘L para escribir una ruta",
                        en: "Click here or press ⌘L to type a path"
                    ))

                // Botones de acción integrados a la derecha de la barra de ruta
                HStack(spacing: 4) {
                    Button {
                        viewModel.beginAddressBarEditing()
                    } label: {
                        Image(systemName: "character.textbox")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help(loc.text(es: "Editar ruta como texto plano (⌘L)", en: "Edit path as plain text (⌘L)"))

                    Button {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(viewModel.currentDirectoryURL.path(percentEncoded: false), forType: .string)
                    } label: {
                        Image(systemName: "link")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help(loc.text(es: "Copiar ruta actual al portapapeles", en: "Copy current path to clipboard"))

                    Divider()
                        .frame(height: 14)

                    Button {
                        viewModel.refresh(preservingSelection: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help(loc.text(es: "Actualizar carpeta actual (⌘R)", en: "Refresh current folder (⌘R)"))
                }
                .padding(.trailing, 6)
            }
        }
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    viewModel.isEditingAddressBar
                        ? Color.accentColor.opacity(0.85)
                        : Color.primary.opacity(0.14),
                    lineWidth: viewModel.isEditingAddressBar ? 1.5 : 0.8
                )
        )
        .onChange(of: viewModel.isEditingAddressBar) { _, editing in
            if editing {
                refreshSuggestions(for: viewModel.addressBarText)
            } else {
                suggestions = []
                highlightedSuggestionIndex = nil
                PathSuggestionsPopupController.shared.hide()
            }
        }
    }

    // MARK: - Helpers de Autocompletado

    private func refreshSuggestions(for text: String) {
        highlightedSuggestionIndex = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != viewModel.currentDirectoryURL.path(percentEncoded: false) else {
            suggestions = []
            PathSuggestionsPopupController.shared.hide()
            return
        }
        suggestions = viewModel.addressBarAutocompleteSuggestions(for: trimmed)
    }

    private func acceptTabCompletion() {
        guard !suggestions.isEmpty else { return }
        let idx = highlightedSuggestionIndex ?? 0
        guard suggestions.indices.contains(idx) else { return }
        let chosen = suggestions[idx].displayText
        let completed = chosen.hasSuffix("/") ? chosen : "\(chosen)/"
        viewModel.addressBarText = completed
        refreshSuggestions(for: completed)
    }

    private func navigateToSuggestion(_ suggestion: (displayText: String, fullPath: String, url: URL)) {
        PathSuggestionsPopupController.shared.hide()
        viewModel.addressBarText = suggestion.fullPath
        viewModel.isEditingAddressBar = false
        viewModel.navigate(to: suggestion.url, recordHistory: true)
    }

    private func commitCurrentInputOrSelection() {
        if let idx = highlightedSuggestionIndex, suggestions.indices.contains(idx) {
            navigateToSuggestion(suggestions[idx])
        } else {
            PathSuggestionsPopupController.shared.hide()
            viewModel.commitAddressBarNavigation()
        }
    }

    private func dismissSuggestionsAndCancel() {
        PathSuggestionsPopupController.shared.hide()
        viewModel.cancelAddressBarEditing()
    }
}

// MARK: - Chip Individual de Breadcrumb

private struct BreadcrumbSegmentChip: View {
    let segment: BreadcrumbSegment
    let isCurrent: Bool
    let onPrimaryClick: () -> Void
    let onDoubleClick: () -> Void

    @ViewState private var isHovered: Bool = false

    var body: some View {
        Text(segment.title)
            .font(.system(size: 12.5, weight: isCurrent ? .semibold : .regular))
            .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                onDoubleClick()
            }
            .onTapGesture(count: 1) {
                onPrimaryClick()
            }
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

// MARK: - Separador `>` con Menú Nativo de Subcarpetas

private struct BreadcrumbChevronMenuButton: View {
    let activeChildURL: URL
    let fetchChildren: () -> [BreadcrumbSegment]
    let onSelectFolder: (URL) -> Void

    @ViewState private var isHovered: Bool = false

    var body: some View {
        Button {
            presentSubfolderMenu()
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isHovered ? .primary : .tertiary)
                .frame(width: 14, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func presentSubfolderMenu() {
        let children = fetchChildren()
        guard !children.isEmpty else { return }

        let menu = NSMenu(title: "")
        let activeStandard = activeChildURL.standardizedFileURL.path(percentEncoded: false)
        let coordinator = BreadcrumbMenuCoordinator.shared

        for child in children {
            let item = NSMenuItem(
                title: child.title,
                action: #selector(BreadcrumbMenuCoordinator.handleSelect(_:)),
                keyEquivalent: ""
            )
            item.target = coordinator
            item.representedObject = BreadcrumbMenuActionPayload(url: child.url, handler: onSelectFolder)
            let icon = NSWorkspace.shared.icon(forFile: child.url.path(percentEncoded: false))
            icon.size = NSSize(width: 15, height: 15)
            item.image = icon
            if child.url.standardizedFileURL.path(percentEncoded: false) == activeStandard {
                item.state = .on
            }
            menu.addItem(item)
        }

        if let event = NSApp.currentEvent, let view = event.window?.contentView {
            let locationInView = event.locationInWindow
            let targetPoint = NSPoint(x: max(0, locationInView.x - 6), y: max(0, locationInView.y - 14))
            menu.popUp(positioning: nil, at: targetPoint, in: view)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }
}

private final class BreadcrumbMenuActionPayload: NSObject {
    let url: URL
    let handler: (URL) -> Void

    init(url: URL, handler: @escaping (URL) -> Void) {
        self.url = url
        self.handler = handler
    }
}

@MainActor
private final class BreadcrumbMenuCoordinator: NSObject {
    static let shared = BreadcrumbMenuCoordinator()

    @objc func handleSelect(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? BreadcrumbMenuActionPayload else { return }
        payload.handler(payload.url)
    }
}

// MARK: - Campo Editable AppKit con Auto-selección y Autocompletado Flotante

private struct EditableAddressTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let suggestions: [(displayText: String, fullPath: String, url: URL)]
    @Binding var highlightedIndex: Int?
    let onTextChanged: (String) -> Void
    let onSelectSuggestion: ((displayText: String, fullPath: String, url: URL)) -> Void
    let onTabComplete: () -> Void
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        field.textColor = NSColor.labelColor
        field.placeholderString = placeholder
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.lineBreakMode = .byTruncatingHead
        field.delegate = context.coordinator

        context.coordinator.textField = field
        DispatchQueue.main.async {
            context.coordinator.focusAndSelectAllIfNeeded()
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        context.coordinator.isDismantled = false

        if nsView.stringValue != text {
            nsView.stringValue = text
            // Si fue completado programáticamente (ej. Tab), mover cursor al final sin re-seleccionar todo
            if let editor = nsView.currentEditor() {
                let len = (nsView.stringValue as NSString).length
                editor.selectedRange = NSRange(location: len, length: 0)
            }
        }
        nsView.placeholderString = placeholder

        if !context.coordinator.didPerformInitialSelectAll {
            DispatchQueue.main.async {
                context.coordinator.focusAndSelectAllIfNeeded()
            }
        }

        if suggestions.isEmpty {
            PathSuggestionsPopupController.shared.hide()
        } else {
            PathSuggestionsPopupController.shared.show(
                below: nsView,
                suggestions: suggestions,
                highlightedIndex: highlightedIndex,
                onSelect: { suggestion in
                    context.coordinator.suppressEndEditingCancel = true
                    onSelectSuggestion(suggestion)
                }
            )
        }
    }

    static func dismantleNSView(_ nsView: NSTextField, coordinator: Coordinator) {
        coordinator.isDismantled = true
        PathSuggestionsPopupController.shared.hide()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: EditableAddressTextField
        weak var textField: NSTextField?
        var didPerformInitialSelectAll = false
        var isFinishingCommand = false
        var suppressEndEditingCancel = false
        var isDismantled = false

        init(parent: EditableAddressTextField) {
            self.parent = parent
        }

        func focusAndSelectAllIfNeeded() {
            guard !isDismantled,
                  !didPerformInitialSelectAll,
                  let field = textField,
                  let window = field.window else {
                return
            }
            didPerformInitialSelectAll = true
            window.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            let newValue = field.stringValue
            parent.text = newValue
            parent.onTextChanged(newValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                isFinishingCommand = true
                PathSuggestionsPopupController.shared.hide()
                parent.onCommit()
                return true

            case #selector(NSResponder.cancelOperation(_:)):
                isFinishingCommand = true
                PathSuggestionsPopupController.shared.hide()
                parent.onCancel()
                return true

            case #selector(NSResponder.insertTab(_:)):
                if !parent.suggestions.isEmpty {
                    parent.onTabComplete()
                    return true
                }
                return false

            case #selector(NSResponder.moveDown(_:)):
                guard !parent.suggestions.isEmpty else { return false }
                let count = parent.suggestions.count
                if let current = parent.highlightedIndex {
                    parent.highlightedIndex = min(count - 1, current + 1)
                } else {
                    parent.highlightedIndex = 0
                }
                return true

            case #selector(NSResponder.moveUp(_:)):
                guard !parent.suggestions.isEmpty else { return false }
                if let current = parent.highlightedIndex {
                    parent.highlightedIndex = current > 0 ? (current - 1) : nil
                }
                return true

            default:
                return false
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            if isFinishingCommand || suppressEndEditingCancel || isDismantled {
                isFinishingCommand = false
                suppressEndEditingCancel = false
                return
            }
            // Pequeña espera para permitir que un clic en el botón "Ir" o en una sugerencia se procese primero
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self, !self.isDismantled else { return }
                if self.suppressEndEditingCancel {
                    self.suppressEndEditingCancel = false
                    return
                }
                if let field = self.textField,
                   let firstResponder = field.window?.firstResponder as? NSTextView,
                   firstResponder === field.currentEditor() {
                    return
                }
                PathSuggestionsPopupController.shared.hide()
                self.parent.onCancel()
            }
        }
    }
}

// MARK: - Popup Flotante No-Activante de Sugerencias de Ruta

@MainActor
private final class PathSuggestionsPopupController {
    static let shared = PathSuggestionsPopupController()

    private var panel: NSPanel?
    private weak var parentWindow: NSWindow?

    private init() {}

    func show(
        below anchorView: NSView,
        suggestions: [(displayText: String, fullPath: String, url: URL)],
        highlightedIndex: Int?,
        onSelect: @escaping ((displayText: String, fullPath: String, url: URL)) -> Void
    ) {
        guard let hostWindow = anchorView.window else {
            hide()
            return
        }

        let contentView = PathSuggestionsListView(
            suggestions: suggestions,
            highlightedIndex: highlightedIndex,
            onSelect: onSelect
        )

        let rowHeight: CGFloat = 28
        let panelHeight = min(CGFloat(suggestions.count) * rowHeight + 12, 240)
        let anchorRectInWindow = anchorView.convert(anchorView.bounds, to: nil)
        let anchorRectOnScreen = hostWindow.convertToScreen(anchorRectInWindow)
        let panelWidth = max(320, anchorRectOnScreen.width + 90)
        let origin = NSPoint(
            x: anchorRectOnScreen.minX - 24,
            y: anchorRectOnScreen.minY - panelHeight - 6
        )
        let frame = NSRect(origin: origin, size: NSSize(width: panelWidth, height: panelHeight))

        let targetPanel: NSPanel
        if let existing = panel {
            targetPanel = existing
        } else {
            let created = NSPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            created.isFloatingPanel = true
            created.level = .popUpMenu
            created.hasShadow = true
            created.backgroundColor = .clear
            created.isOpaque = false
            created.hidesOnDeactivate = true
            self.panel = created
            targetPanel = created
        }

        let hosting = NSHostingView(rootView: contentView)
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        targetPanel.contentView = hosting
        targetPanel.setFrame(frame, display: true)

        if parentWindow !== hostWindow {
            if let oldParent = parentWindow {
                oldParent.removeChildWindow(targetPanel)
            }
            hostWindow.addChildWindow(targetPanel, ordered: .above)
            parentWindow = hostWindow
        }
        targetPanel.orderFront(nil)
    }

    func hide() {
        guard let panel else { return }
        if let parentWindow {
            parentWindow.removeChildWindow(panel)
        }
        panel.orderOut(nil)
        parentWindow = nil
    }
}

private struct PathSuggestionsListView: View {
    let suggestions: [(displayText: String, fullPath: String, url: URL)]
    let highlightedIndex: Int?
    let onSelect: ((displayText: String, fullPath: String, url: URL)) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, item in
                let isHighlighted = highlightedIndex == index
                Button {
                    onSelect(item)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(isHighlighted ? .white : Color.accentColor)

                        Text(item.displayText)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(isHighlighted ? .white : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(isHighlighted ? Color.accentColor : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.8)
        )
    }
}
