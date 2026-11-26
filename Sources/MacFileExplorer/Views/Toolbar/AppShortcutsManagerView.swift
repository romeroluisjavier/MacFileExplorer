import AppKit
import Observation
import SwiftUI

/// Filtro de categoría en el Administrador Central de Atajos (`Archivo → Administrar todos los atajos`).
public enum AppShortcutCategoryFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case tools
    case tabsAndNavigation
    case filesAndViews
    case clipboard
    case altTab
    case standardReference

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .all:
            return loc.text(es: "Todos", en: "All")
        case .tools:
            return AppShortcutCategory.tools.localizedTitle(using: loc)
        case .tabsAndNavigation:
            return AppShortcutCategory.tabsAndNavigation.localizedTitle(using: loc)
        case .filesAndViews:
            return AppShortcutCategory.filesAndViews.localizedTitle(using: loc)
        case .clipboard:
            return AppShortcutCategory.clipboard.localizedTitle(using: loc)
        case .altTab:
            return AppShortcutCategory.altTab.localizedTitle(using: loc)
        case .standardReference:
            return AppShortcutCategory.standardReference.localizedTitle(using: loc)
        }
    }

    public var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .tools: return AppShortcutCategory.tools.systemImage
        case .tabsAndNavigation: return AppShortcutCategory.tabsAndNavigation.systemImage
        case .filesAndViews: return AppShortcutCategory.filesAndViews.systemImage
        case .clipboard: return AppShortcutCategory.clipboard.systemImage
        case .altTab: return AppShortcutCategory.altTab.systemImage
        case .standardReference: return AppShortcutCategory.standardReference.systemImage
        }
    }
}

@MainActor
@Observable
private final class AppShortcutsWindowState {
    var selectedCategory: AppShortcutCategoryFilter = .all
}

/// Controlador de la ventana central para administrar TODOS los atajos de teclado de `MacFileExplorer`
/// (Herramientas globales como «Ver Escritorio», Explorador, Portapapeles Maccy, AltTab y atajos estándar).
@MainActor
public final class AppShortcutsWindowController: NSObject, NSWindowDelegate {

    public static let shared = AppShortcutsWindowController()

    private var window: NSWindow?
    private let state = AppShortcutsWindowState()

    private override init() {
        super.init()
    }

    public func show(initialCategory: AppShortcutCategoryFilter = .all) {
        state.selectedCategory = initialCategory
        let loc = LocalizationManager.shared

        if let existing = window {
            existing.title = localizedWindowTitle(using: loc)
            NSApplication.shared.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.minSize = NSSize(width: 680, height: 480)
        win.isReleasedWhenClosed = false
        win.tabbingMode = .disallowed
        win.delegate = self
        win.title = localizedWindowTitle(using: loc)
        win.contentViewController = NSHostingController(
            rootView: AppShortcutsManagerView(state: state) { [weak win] in
                win?.close()
            }
        )
        win.center()
        self.window = win

        NSApplication.shared.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    public func refreshLocalizedTitle() {
        window?.title = localizedWindowTitle(using: .shared)
    }

    private func localizedWindowTitle(using loc: LocalizationManager) -> String {
        loc.text(
            es: "Administrar todos los atajos de teclado",
            en: "Manage All Keyboard Shortcuts"
        )
    }

    public func windowWillClose(_ notification: Notification) {
        ToolsShortcutManager.shared.setRecordingSuspended(false)
        ClipboardHistoryManager.shared.setRecordingSuspended(false)
        AltTabHotkeyMonitor.shared.isRecordingShortcut = false
    }
}

private enum RecordingTarget: Equatable {
    case appAction(AppShortcutAction)
    case clipboardQuickPaste
    case clipboardFullSearch
    case clipboardPin
    case clipboardDelete
    case clipboardPlainText
    case clipboardClearHistory
}

private struct StandardReferenceShortcut: Identifiable {
    let id: String
    let icon: String
    let keys: String
    let titleES: String
    let titleEN: String
    let subtitleES: String
    let subtitleEN: String
}

private let standardReferenceShortcuts: [StandardReferenceShortcut] = [
    StandardReferenceShortcut(
        id: "std-quicklook",
        icon: "eye",
        keys: "Space",
        titleES: "Vista Rápida (Quick Look)",
        titleEN: "Quick Look Preview",
        subtitleES: "Abre o cierra la vista previa del archivo seleccionado.",
        subtitleEN: "Toggles preview for the selected file."
    ),
    StandardReferenceShortcut(
        id: "std-rename",
        icon: "pencil",
        keys: "F2 / ↵",
        titleES: "Renombrar elementos",
        titleEN: "Rename Items",
        subtitleES: "Renombra en línea (1 archivo) o abre Renombrado masivo (varios).",
        subtitleEN: "Inline rename (1 item) or Bulk Rename (multiple items)."
    ),
    StandardReferenceShortcut(
        id: "std-open",
        icon: "arrow.down.circle",
        keys: "⌘↓",
        titleES: "Abrir archivo o carpeta",
        titleEN: "Open File or Folder",
        subtitleES: "Abre el elemento seleccionado actualmente.",
        subtitleEN: "Opens the currently selected item."
    ),
    StandardReferenceShortcut(
        id: "std-cut-copy-paste",
        icon: "doc.on.doc",
        keys: "⌘X / ⌘C / ⌘V",
        titleES: "Cortar, Copiar y Pegar",
        titleEN: "Cut, Copy & Paste",
        subtitleES: "Operaciones estándar de archivos, texto y vista previa de medios.",
        subtitleEN: "Standard operations for files, text, and Quick Look media."
    ),
    StandardReferenceShortcut(
        id: "std-select-all",
        icon: "checkmark.circle",
        keys: "⌘A",
        titleES: "Seleccionar todo",
        titleEN: "Select All",
        subtitleES: "Selecciona todos los elementos de la carpeta abierta.",
        subtitleEN: "Selects every item in the current folder."
    ),
    StandardReferenceShortcut(
        id: "std-undo-redo",
        icon: "arrow.uturn.backward",
        keys: "⌘Z / ⇧⌘Z",
        titleES: "Deshacer / Rehacer operación de archivo",
        titleEN: "Undo / Redo File Operation",
        subtitleES: "Revierte o rehace movimientos, copias, renombrados y eliminaciones.",
        subtitleEN: "Reverts or redoes moves, copies, renames, and deletions."
    ),
    StandardReferenceShortcut(
        id: "std-trash",
        icon: "trash",
        keys: "⌫ / ⌘⌫",
        titleES: "Mover a la Papelera",
        titleEN: "Move to Trash",
        subtitleES: "Envía los elementos seleccionados a la Papelera de macOS.",
        subtitleEN: "Moves selected items to macOS Trash."
    ),
    StandardReferenceShortcut(
        id: "std-perm-delete",
        icon: "trash.slash",
        keys: "⇧⌫",
        titleES: "Eliminar permanentemente",
        titleEN: "Delete Permanently",
        subtitleES: "Borra sin pasar por la Papelera (con confirmación previa).",
        subtitleEN: "Deletes permanently bypassing Trash (with confirmation)."
    ),
    StandardReferenceShortcut(
        id: "std-office-save",
        icon: "square.and.arrow.down",
        keys: "⌘S / ⇧⌘S",
        titleES: "Guardar / Guardar copia (Editor Office y CSV)",
        titleEN: "Save / Save Copy (Office & CSV Editor)",
        subtitleES: "Guarda cambios dentro del editor rápido de Excel, CSV, Word y PowerPoint.",
        subtitleEN: "Saves changes inside the Quick Look Office & CSV editor."
    ),
    StandardReferenceShortcut(
        id: "std-office-find",
        icon: "magnifyingglass",
        keys: "⌘F",
        titleES: "Buscar / Filtrar (Editor Office y CSV)",
        titleEN: "Find / Filter (Office & CSV Editor)",
        subtitleES: "Busca texto o filtra filas en documentos abiertos en Vista Rápida.",
        subtitleEN: "Searches text or filters rows inside Quick Look documents."
    ),
    StandardReferenceShortcut(
        id: "std-help",
        icon: "questionmark.circle",
        keys: "⌘?",
        titleES: "Ayuda de MacFileExplorer",
        titleEN: "MacFileExplorer Help",
        subtitleES: "Abre la guía completa de funciones, atajos y ajustes.",
        subtitleEN: "Opens the complete features, shortcuts, and settings guide."
    )
]

private struct AppShortcutsManagerView: View {
    @Bindable var state: AppShortcutsWindowState
    let onClose: () -> Void

    @Bindable private var loc = LocalizationManager.shared
    @Bindable private var shortcutPrefs = AppShortcutPreferences.shared
    @Bindable private var toolsManager = ToolsShortcutManager.shared
    @Bindable private var clipboardPrefs = ClipboardHistoryPreferences.shared
    @Bindable private var altTabPrefs = AltTabPreferences.shared

    @ViewState private var searchQuery: String = ""
    @ViewState private var recordingTarget: RecordingTarget? = nil
    @ViewState private var recordingMonitor: Any? = nil

    private var normalizedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            filterBarSection
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if shouldShowSection(.tools) {
                        toolsSectionCard
                    }
                    if shouldShowSection(.tabsAndNavigation) {
                        appActionsCard(
                            category: .tabsAndNavigation,
                            actions: filteredActions(in: .tabsAndNavigation)
                        )
                    }
                    if shouldShowSection(.filesAndViews) {
                        appActionsCard(
                            category: .filesAndViews,
                            actions: filteredActions(in: .filesAndViews)
                        )
                    }
                    if shouldShowSection(.clipboard) {
                        clipboardSectionCard
                    }
                    if shouldShowSection(.altTab) {
                        altTabSectionCard
                    }
                    if shouldShowSection(.standardReference) {
                        standardReferenceSectionCard
                    }
                }
                .padding(18)
            }

            Divider()
            footerSection
        }
        .frame(minWidth: 680, minHeight: 480)
        .onDisappear {
            stopRecording()
        }
    }

    // MARK: - Header & Filter Bar

    private var headerSection: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: "keyboard")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(loc.text(
                    es: "Administrador de Atajos de Teclado",
                    en: "Keyboard Shortcuts Manager"
                ))
                .font(.system(size: 15.5, weight: .bold))

                Text(loc.text(
                    es: "Activá, cambiá o restablecé todos los atajos de MacFileExplorer en un solo lugar. Hacé clic en cualquier tecla para grabar una nueva combinación (Esc cancela).",
                    en: "Enable, customize, or reset every shortcut in MacFileExplorer from one place. Click any key badge to record a new combination (Esc cancels)."
                ))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                TextField(
                    loc.text(es: "Buscar atajo o acción…", en: "Search shortcut or action…"),
                    text: $searchQuery
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(width: 175)

                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var filterBarSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(AppShortcutCategoryFilter.allCases) { filter in
                    let isSelected = state.selectedCategory == filter
                    Button {
                        state.selectedCategory = filter
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: filter.systemImage)
                                .font(.system(size: 10.5, weight: .semibold))
                            Text(filter.localizedTitle(using: loc))
                                .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.07))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
        }
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.45))
    }

    // MARK: - Section 1: Tools & Global System (View Desktop)

    @ViewBuilder
    private var toolsSectionCard: some View {
        let actions = filteredActions(in: .tools)
        if !actions.isEmpty {
            sectionContainer(
                title: AppShortcutCategory.tools.localizedTitle(using: loc),
                icon: AppShortcutCategory.tools.systemImage,
                accent: .blue,
                trailing: {
                    Button {
                        ToolsSettingsWindowController.shared.show(initialSection: .viewDesktop)
                    } label: {
                        Label(
                            loc.text(es: "Configuración de Herramientas…", en: "Tools Settings…"),
                            systemImage: "slider.horizontal.3"
                        )
                        .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            ) {
                ForEach(actions) { action in
                    appActionRow(action: action, showGlobalStatus: action == .viewDesktop)
                }
            }
        }
    }

    // MARK: - Section 2 & 3: Customizable Explorer Actions

    @ViewBuilder
    private func appActionsCard(category: AppShortcutCategory, actions: [AppShortcutAction]) -> some View {
        if !actions.isEmpty {
            sectionContainer(
                title: category.localizedTitle(using: loc),
                icon: category.systemImage,
                accent: category == .tabsAndNavigation ? .indigo : .teal
            ) {
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                    if index > 0 {
                        Divider().opacity(0.55)
                    }
                    appActionRow(action: action, showGlobalStatus: false)
                }
            }
        }
    }

    private func appActionRow(action: AppShortcutAction, showGlobalStatus: Bool) -> some View {
        let current = shortcutPrefs.shortcut(for: action)
        let isRecordingThis = recordingTarget == .appAction(action)
        let conflicts = shortcutPrefs.conflictingActionTitles(
            for: current.conflictSignature,
            excludingIdentifier: action.id,
            using: loc
        )

        return HStack(spacing: 10) {
            Toggle(
                "",
                isOn: Binding(
                    get: { shortcutPrefs.shortcut(for: action).isEnabled },
                    set: { shortcutPrefs.setEnabled($0, for: action) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)

            Image(systemName: action.systemImage)
                .font(.system(size: 13))
                .foregroundStyle(current.isEnabled ? Color.accentColor : Color.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(action.localizedTitle(using: loc))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(current.isEnabled ? .primary : .secondary)

                    if action.isGlobalSystemHotkey {
                        badgePill(
                            text: loc.text(es: "Global macOS", en: "System-wide"),
                            color: .blue
                        )
                    }

                    if showGlobalStatus && current.isEnabled {
                        if toolsManager.isViewDesktopHotKeyRegistered {
                            badgePill(
                                text: loc.text(es: "Activo", en: "Active"),
                                color: .green
                            )
                        } else if !toolsManager.isRecordingSuspended {
                            badgePill(
                                text: loc.text(es: "En uso por otra app", en: "In use by another app"),
                                color: .orange
                            )
                        }
                    }
                }

                Text(action.localizedSubtitle(using: loc))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if !conflicts.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                        Text(loc.text(
                            es: "Conflicto con: \(conflicts.joined(separator: ", "))",
                            en: "Conflicts with: \(conflicts.joined(separator: ", "))"
                        ))
                        .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(Color.orange)
                }
            }

            Spacer(minLength: 8)

            if !shortcutPrefs.isDefault(for: action) {
                Button {
                    if isRecordingThis { stopRecording() }
                    shortcutPrefs.resetShortcut(for: action)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(loc.text(
                    es: "Restablecer a \(action.defaultShortcut.displayString)",
                    en: "Reset to \(action.defaultShortcut.displayString)"
                ))
            }

            recorderButton(
                label: current.displayString,
                isRecording: isRecordingThis,
                isEnabled: current.isEnabled
            ) {
                if isRecordingThis {
                    stopRecording()
                } else {
                    startRecording(for: .appAction(action))
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Section 4: Clipboard History (Maccy)

    private struct ClipboardShortcutDescriptor: Identifiable {
        let id: String
        let target: RecordingTarget
        let icon: String
        let isGlobal: Bool
        let titleES: String
        let titleEN: String
        let subtitleES: String
        let subtitleEN: String
        let getShortcut: () -> ClipboardKeyShortcut
        let setShortcut: (ClipboardKeyShortcut) -> Void
    }

    private var clipboardDescriptors: [ClipboardShortcutDescriptor] {
        [
            ClipboardShortcutDescriptor(
                id: "clipboard.quickPaste",
                target: .clipboardQuickPaste,
                icon: "macwindow.on.rectangle",
                isGlobal: true,
                titleES: "Abrir menú desplegable para pegar",
                titleEN: "Open Quick Paste Dropdown",
                subtitleES: "Global en todo macOS: muestra tus últimos elementos copiados.",
                subtitleEN: "Global across macOS: shows your recent copied items.",
                getShortcut: { clipboardPrefs.quickPasteDropdownShortcut },
                setShortcut: { clipboardPrefs.quickPasteDropdownShortcut = $0 }
            ),
            ClipboardShortcutDescriptor(
                id: "clipboard.fullSearch",
                target: .clipboardFullSearch,
                icon: "magnifyingglass",
                isGlobal: true,
                titleES: "Buscar en todo el Historial del Portapapeles",
                titleEN: "Search Full Clipboard History",
                subtitleES: "Global en todo macOS: abre el buscador completo del historial.",
                subtitleEN: "Global across macOS: opens the full history search view.",
                getShortcut: { clipboardPrefs.fullHistorySearchShortcut },
                setShortcut: { clipboardPrefs.fullHistorySearchShortcut = $0 }
            ),
            ClipboardShortcutDescriptor(
                id: "clipboard.pin",
                target: .clipboardPin,
                icon: "pin",
                isGlobal: false,
                titleES: "Fijar / Desfijar elemento en el menú",
                titleEN: "Pin / Unpin Item in Menu",
                subtitleES: "Mantiene un elemento fijado arriba dentro del menú Maccy.",
                subtitleEN: "Pins or unpins the selected item inside the Maccy popup.",
                getShortcut: { clipboardPrefs.pinShortcut },
                setShortcut: { clipboardPrefs.pinShortcut = $0 }
            ),
            ClipboardShortcutDescriptor(
                id: "clipboard.delete",
                target: .clipboardDelete,
                icon: "trash",
                isGlobal: false,
                titleES: "Eliminar elemento del historial",
                titleEN: "Delete Item from History",
                subtitleES: "Borra el elemento seleccionado dentro del menú del portapapeles.",
                subtitleEN: "Removes the selected entry from Clipboard History.",
                getShortcut: { clipboardPrefs.deleteShortcut },
                setShortcut: { clipboardPrefs.deleteShortcut = $0 }
            ),
            ClipboardShortcutDescriptor(
                id: "clipboard.plainText",
                target: .clipboardPlainText,
                icon: "text.alignleft",
                isGlobal: false,
                titleES: "Pegar / Copiar como texto plano",
                titleEN: "Paste / Copy as Plain Text",
                subtitleES: "Pega sin estilos ni formato dentro del menú del portapapeles.",
                subtitleEN: "Pastes without formatting from the clipboard dropdown.",
                getShortcut: { clipboardPrefs.plainTextShortcut },
                setShortcut: { clipboardPrefs.plainTextShortcut = $0 }
            ),
            ClipboardShortcutDescriptor(
                id: "clipboard.clear",
                target: .clipboardClearHistory,
                icon: "trash.slash",
                isGlobal: false,
                titleES: "Limpiar todo el historial no fijado",
                titleEN: "Clear All Unpinned History",
                subtitleES: "Elimina todos los elementos copiados salvo los fijados.",
                subtitleEN: "Clears all copied entries except pinned items.",
                getShortcut: { clipboardPrefs.clearHistoryShortcut },
                setShortcut: { clipboardPrefs.clearHistoryShortcut = $0 }
            )
        ]
    }

    @ViewBuilder
    private var clipboardSectionCard: some View {
        let items = clipboardDescriptors.filter { item in
            guard !normalizedQuery.isEmpty else { return true }
            let sc = item.getShortcut().displayString.lowercased()
            return item.titleES.lowercased().contains(normalizedQuery)
                || item.titleEN.lowercased().contains(normalizedQuery)
                || item.subtitleES.lowercased().contains(normalizedQuery)
                || item.subtitleEN.lowercased().contains(normalizedQuery)
                || sc.contains(normalizedQuery)
                || "clipboard portapapeles maccy".contains(normalizedQuery)
        }

        if !items.isEmpty {
            sectionContainer(
                title: AppShortcutCategory.clipboard.localizedTitle(using: loc),
                icon: AppShortcutCategory.clipboard.systemImage,
                accent: .purple,
                trailing: {
                    HStack(spacing: 8) {
                        if !clipboardPrefs.isEnabled {
                            badgePill(
                                text: loc.text(es: "Módulo desactivado", en: "Module off"),
                                color: .secondary
                            )
                        }
                        Button {
                            ClipboardShortcutsWindowController.shared.show()
                        } label: {
                            Label(
                                loc.text(es: "Configuración del Portapapeles…", en: "Clipboard Settings…"),
                                systemImage: "slider.horizontal.3"
                            )
                            .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            ) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, desc in
                    if index > 0 {
                        Divider().opacity(0.55)
                    }
                    let current = desc.getShortcut()
                    let isRecordingThis = recordingTarget == desc.target
                    let sig: String? = current.isEnabled
                        ? "\(current.keyCode)|\(current.command ? 1 : 0)|\(current.control ? 1 : 0)|\(current.option ? 1 : 0)|\(current.shift ? 1 : 0)"
                        : nil
                    let conflicts = shortcutPrefs.conflictingActionTitles(
                        for: sig,
                        excludingIdentifier: desc.id,
                        using: loc
                    )

                    HStack(spacing: 10) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { desc.getShortcut().isEnabled },
                                set: { enabled in
                                    var updated = desc.getShortcut()
                                    updated.isEnabled = enabled
                                    desc.setShortcut(updated)
                                }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)

                        Image(systemName: desc.icon)
                            .font(.system(size: 13))
                            .foregroundStyle(current.isEnabled ? Color.purple : Color.secondary)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(loc.text(es: desc.titleES, en: desc.titleEN))
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(current.isEnabled ? .primary : .secondary)

                                if desc.isGlobal {
                                    badgePill(
                                        text: loc.text(es: "Global macOS", en: "System-wide"),
                                        color: .purple
                                    )
                                }
                            }
                            Text(loc.text(es: desc.subtitleES, en: desc.subtitleEN))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)

                            if !conflicts.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 10))
                                    Text(loc.text(
                                        es: "Conflicto con: \(conflicts.joined(separator: ", "))",
                                        en: "Conflicts with: \(conflicts.joined(separator: ", "))"
                                    ))
                                    .font(.system(size: 10.5, weight: .medium))
                                }
                                .foregroundStyle(Color.orange)
                            }
                        }

                        Spacer(minLength: 8)

                        recorderButton(
                            label: current.displayString,
                            isRecording: isRecordingThis,
                            isEnabled: current.isEnabled
                        ) {
                            if isRecordingThis {
                                stopRecording()
                            } else {
                                startRecording(for: desc.target)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .opacity(clipboardPrefs.isEnabled ? 1.0 : 0.65)
                }
            }
        }
    }

    // MARK: - Section 5: AltTab Profiles

    @ViewBuilder
    private var altTabSectionCard: some View {
        let profiles = altTabPrefs.shortcutProfiles.filter { profile in
            guard !normalizedQuery.isEmpty else { return true }
            return profile.name.lowercased().contains(normalizedQuery)
                || profile.displayString.lowercased().contains(normalizedQuery)
                || "alttab ventanas windows switcher".contains(normalizedQuery)
        }

        if !profiles.isEmpty {
            sectionContainer(
                title: loc.text(es: "AltTab — Selector de Ventanas", en: "AltTab — Window Switcher"),
                icon: AppShortcutCategory.altTab.systemImage,
                accent: .orange,
                trailing: {
                    HStack(spacing: 8) {
                        if !altTabPrefs.isEnabled {
                            badgePill(
                                text: loc.text(es: "Módulo desactivado", en: "Module off"),
                                color: .secondary
                            )
                        }
                        Button {
                            AltTabSettingsWindowController.shared.show()
                        } label: {
                            Label(
                                loc.text(es: "Personalizar perfiles AltTab…", en: "Customize AltTab Profiles…"),
                                systemImage: "slider.horizontal.3"
                            )
                            .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            ) {
                ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                    if index > 0 {
                        Divider().opacity(0.55)
                    }
                    HStack(spacing: 10) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { profile.isEnabled },
                                set: { enabled in
                                    var updated = altTabPrefs.shortcutProfiles
                                    if let idx = updated.firstIndex(where: { $0.id == profile.id }) {
                                        updated[idx].isEnabled = enabled
                                        altTabPrefs.shortcutProfiles = updated
                                    }
                                }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)

                        Image(systemName: "rectangle.stack.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(profile.isEnabled ? Color.orange : Color.secondary)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(profile.name)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(profile.isEnabled ? .primary : .secondary)
                                badgePill(
                                    text: loc.text(es: "Global macOS", en: "System-wide"),
                                    color: .orange
                                )
                            }
                            Text(loc.text(
                                es: "Mantené el modificador y tocá la tecla para alternar ventanas. Configurá filtros por Space, monitor o app desde Ajustes de AltTab.",
                                en: "Hold the modifier and tap the key to switch windows. Configure Space, display, or app filters in AltTab Settings."
                            ))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        Text(profile.displayString)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(minWidth: 94)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.primary.opacity(0.07))
                            )
                    }
                    .padding(.vertical, 4)
                    .opacity(altTabPrefs.isEnabled ? 1.0 : 0.65)
                }
            }
        }
    }

    // MARK: - Section 6: Built-in / Standard Reference

    @ViewBuilder
    private var standardReferenceSectionCard: some View {
        let items = standardReferenceShortcuts.filter { item in
            guard !normalizedQuery.isEmpty else { return true }
            return item.titleES.lowercased().contains(normalizedQuery)
                || item.titleEN.lowercased().contains(normalizedQuery)
                || item.subtitleES.lowercased().contains(normalizedQuery)
                || item.subtitleEN.lowercased().contains(normalizedQuery)
                || item.keys.lowercased().contains(normalizedQuery)
        }

        if !items.isEmpty {
            sectionContainer(
                title: loc.text(es: "Atajos Estándar y Contextuales (Solo lectura)", en: "Standard & Contextual Shortcuts (Built-in)"),
                icon: AppShortcutCategory.standardReference.systemImage,
                accent: .secondary
            ) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider().opacity(0.55)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: item.icon)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.text(es: item.titleES, en: item.titleEN))
                                .font(.system(size: 12.5, weight: .medium))
                            Text(loc.text(es: item.subtitleES, en: item.subtitleEN))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        Text(item.keys)
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.055))
                            )
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: 10) {
            Button {
                stopRecording()
                shortcutPrefs.resetAllToDefaults()
                clipboardPrefs.resetShortcutsToDefaults()
            } label: {
                Label(
                    loc.text(es: "Restablecer todos los atajos", en: "Reset All Shortcuts"),
                    systemImage: "arrow.counterclockwise"
                )
                .font(.system(size: 12))
            }
            .buttonStyle(.bordered)

            Spacer()

            Text(loc.text(
                es: "Los cambios se guardan y aplican al instante.",
                en: "Changes save and take effect immediately."
            ))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            Button(loc.text(es: "Listo", en: "Done")) {
                stopRecording()
                onClose()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Helpers

    private func shouldShowSection(_ category: AppShortcutCategory) -> Bool {
        switch state.selectedCategory {
        case .all: return true
        case .tools: return category == .tools
        case .tabsAndNavigation: return category == .tabsAndNavigation
        case .filesAndViews: return category == .filesAndViews
        case .clipboard: return category == .clipboard
        case .altTab: return category == .altTab
        case .standardReference: return category == .standardReference
        }
    }

    private func filteredActions(in category: AppShortcutCategory) -> [AppShortcutAction] {
        AppShortcutAction.allCases.filter { action in
            guard action.category == category else { return false }
            guard !normalizedQuery.isEmpty else { return true }
            let sc = shortcutPrefs.shortcut(for: action).displayString.lowercased()
            return action.localizedTitle(using: loc).lowercased().contains(normalizedQuery)
                || action.localizedSubtitle(using: loc).lowercased().contains(normalizedQuery)
                || sc.contains(normalizedQuery)
                || (action == .viewDesktop && "desktop escritorio win+d cmd+d".contains(normalizedQuery))
        }
    }

    @ViewBuilder
    private func sectionContainer<Trailing: View, Content: View>(
        title: String,
        icon: String,
        accent: Color,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                trailing()
            }

            VStack(alignment: .leading, spacing: 6) {
                content()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func badgePill(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(
                Capsule()
                    .fill(color.opacity(0.14))
            )
    }

    private func recorderButton(
        label: String,
        isRecording: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(
                isRecording
                    ? loc.text(es: "Presioná teclas…", en: "Press keys…")
                    : label
            )
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(isRecording ? Color.white : (isEnabled ? Color.primary : Color.secondary))
            .frame(minWidth: 112)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isRecording ? Color.accentColor : Color.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isRecording ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(loc.text(
            es: "Hacé clic y presioná la nueva combinación (Esc cancela)",
            en: "Click and press your new key combination (Esc cancels)"
        ))
    }

    // MARK: - Grabador de Teclas Seguro (suspende hotkeys globales durante la captura)

    private func startRecording(for target: RecordingTarget) {
        stopRecording()
        recordingTarget = target
        ToolsShortcutManager.shared.setRecordingSuspended(true)
        ClipboardHistoryManager.shared.setRecordingSuspended(true)
        AltTabHotkeyMonitor.shared.isRecordingShortcut = true

        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let appRecorded = AppKeyShortcut.from(event: event, allowFunctionKeyWithoutModifiers: true)
            let clipRecorded = ClipboardKeyShortcut.from(event: event)

            let consumed = MainActor.assumeIsolated { () -> Bool in
                if keyCode == 53 { // Escape cancela
                    stopRecording()
                    return true
                }

                switch target {
                case .appAction(let action):
                    if let appRecorded {
                        shortcutPrefs.setShortcut(appRecorded, for: action)
                        stopRecording()
                        return true
                    }
                    return false

                case .clipboardQuickPaste:
                    if let clipRecorded {
                        clipboardPrefs.quickPasteDropdownShortcut = clipRecorded
                        stopRecording()
                        return true
                    }
                    return false

                case .clipboardFullSearch:
                    if let clipRecorded {
                        clipboardPrefs.fullHistorySearchShortcut = clipRecorded
                        stopRecording()
                        return true
                    }
                    return false

                case .clipboardPin:
                    if let clipRecorded {
                        clipboardPrefs.pinShortcut = clipRecorded
                        stopRecording()
                        return true
                    }
                    return false

                case .clipboardDelete:
                    if let clipRecorded {
                        clipboardPrefs.deleteShortcut = clipRecorded
                        stopRecording()
                        return true
                    }
                    return false

                case .clipboardPlainText:
                    if let clipRecorded {
                        clipboardPrefs.plainTextShortcut = clipRecorded
                        stopRecording()
                        return true
                    }
                    return false

                case .clipboardClearHistory:
                    if let clipRecorded {
                        clipboardPrefs.clearHistoryShortcut = clipRecorded
                        stopRecording()
                        return true
                    }
                    return false
                }
            }
            return consumed ? nil : event
        }
    }

    private func stopRecording() {
        if let monitor = recordingMonitor {
            NSEvent.removeMonitor(monitor)
            recordingMonitor = nil
        }
        recordingTarget = nil
        ToolsShortcutManager.shared.setRecordingSuspended(false)
        ClipboardHistoryManager.shared.setRecordingSuspended(false)
        AltTabHotkeyMonitor.shared.isRecordingShortcut = false
    }
}
