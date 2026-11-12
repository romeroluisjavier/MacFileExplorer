import SwiftUI

/// Barra de Comandos Superior estilo Windows 11 Explorer con estética nativa de macOS.
/// Incluye: [+ Nuevo ▾] | [Cortar] [Copiar] [Pegar] [Renombrar] [Eliminar] | [Ordenar ▾] [Ver ▾] [☰|⊞] ... [🌐].
public struct CommandBarView: View {
    @Bindable var viewModel: ExplorerViewModel
    @Bindable private var bookmarksManager: BookmarksManager = .shared
    @Bindable private var toolbarPrefs: ToolbarPreferences = .shared

    private var loc: LocalizationManager { LocalizationManager.shared }

    public init(viewModel: ExplorerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 6) {
            if toolbarPrefs.isNewButtonVisible {
                // 1. Botón desplegable "+ Nuevo / + New" (Estilo Windows 11 Command Bar)
                newItemMenu

                commandDivider
            }

            // 2. Grupo de Acciones de Portapapeles y Edición
            HStack(spacing: 4) {
                CommandActionButton(
                    title: loc.text(es: "Cortar", en: "Cut"),
                    systemImage: "scissors",
                    shortcutHint: "⌘X",
                    isEnabled: viewModel.canCutOrCopy,
                    isActive: viewModel.clipboardManager.activeMode == .cut
                ) {
                    viewModel.cutSelectedItems()
                }

                CommandActionButton(
                    title: loc.text(es: "Copiar", en: "Copy"),
                    systemImage: "doc.on.doc",
                    shortcutHint: "⌘C",
                    isEnabled: viewModel.canCutOrCopy
                ) {
                    viewModel.copySelectedItems()
                }

                CommandActionButton(
                    title: loc.text(es: "Pegar", en: "Paste"),
                    systemImage: "doc.on.clipboard",
                    shortcutHint: "⌘V",
                    isEnabled: viewModel.canPaste,
                    prominentBadge: viewModel.clipboardManager.activeMode == .cut
                ) {
                    viewModel.pasteItems()
                }

                CommandActionButton(
                    title: loc.text(es: "Renombrar", en: "Rename"),
                    systemImage: "character.cursor.ibeam",
                    shortcutHint: "F2 / ↩",
                    isEnabled: viewModel.canRename
                ) {
                    viewModel.beginRenamingSelectedItem()
                }

                CommandActionButton(
                    title: loc.text(es: "Eliminar", en: "Delete"),
                    systemImage: "trash",
                    shortcutHint: "⌫",
                    isEnabled: viewModel.canDelete,
                    isDestructive: true
                ) {
                    viewModel.moveSelectedItemsToTrash()
                }
            }

            commandDivider

            // 3. Menús Ordenar y Ver + Conmutador rápido de iconos sin desbordamiento
            HStack(spacing: 6) {
                sortMenu
                viewOptionsMenu
                compactViewModeToggle
            }

            Spacer(minLength: 8)

            // 4. Indicador contextual del Portapapeles (cuando hay elementos cortados o copiados)
            if let payload = viewModel.clipboardManager.payload, !payload.urls.isEmpty {
                clipboardIndicatorPill(payload: payload)
            }

            // 5. Sección de Marcadores / Favoritos de Chrome (en el recuadro superior derecho)
            if bookmarksManager.isBookmarksBarVisible {
                ChromeBookmarksBarView()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }

    // MARK: - Subvistas

    private var newItemMenu: some View {
        Menu {
            Button {
                viewModel.createNewFolder()
            } label: {
                Label(loc.text(es: "Carpeta", en: "Folder"), systemImage: "folder.badge.plus")
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button {
                viewModel.createNewTextFile()
            } label: {
                Label(loc.text(es: "Documento de texto (.txt)", en: "Text Document (.txt)"), systemImage: "doc.badge.plus")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 14, weight: .semibold))
                Text(loc.text(es: "Nuevo", en: "New"))
                    .font(.system(size: 12.5, weight: .medium))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .help(loc.text(es: "Crear un nuevo elemento en la carpeta actual (⇧⌘N)", en: "Create a new item in the current folder (⇧⌘N)"))
    }

    private var sortMenu: some View {
        Menu {
            Section(loc.text(es: "Ordenar por", en: "Sort by")) {
                ForEach(FileItem.SortField.allCases, id: \.self) { field in
                    Toggle(isOn: Binding(
                        get: { viewModel.sortField == field },
                        set: { _ in viewModel.toggleSort(by: field) }
                    )) {
                        Label(loc.sortFieldTitle(field), systemImage: field.systemImage)
                    }
                }
            }

            Divider()

            Section(loc.text(es: "Dirección", en: "Direction")) {
                Toggle(isOn: Binding(
                    get: { viewModel.sortAscending },
                    set: { _ in viewModel.sortAscending = true }
                )) {
                    Label(loc.text(es: "Ascendente", en: "Ascending"), systemImage: "arrow.up")
                }

                Toggle(isOn: Binding(
                    get: { !viewModel.sortAscending },
                    set: { _ in viewModel.sortAscending = false }
                )) {
                    Label(loc.text(es: "Descendente", en: "Descending"), systemImage: "arrow.down")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 12, weight: .medium))
                Text(loc.text(es: "Ordenar", en: "Sort"))
                    .font(.system(size: 12, weight: .regular))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .help(loc.text(es: "Cambiar columna y dirección de ordenamiento", en: "Change sort column and direction"))
    }

    private var viewOptionsMenu: some View {
        Menu {
            Section(loc.text(es: "Diseño", en: "Layout")) {
                ForEach(ExplorerViewMode.allCases) { mode in
                    Toggle(isOn: Binding(
                        get: { viewModel.viewMode == mode },
                        set: { _ in viewModel.viewMode = mode }
                    )) {
                        Label(loc.viewModeTitle(mode), systemImage: mode.systemImage)
                    }
                }
            }

            Divider()

            Toggle(isOn: $viewModel.showHiddenFiles) {
                Label(loc.text(es: "Mostrar archivos ocultos (⇧⌘.)", en: "Show hidden files (⇧⌘.)"), systemImage: "eye")
            }

            Toggle(isOn: $bookmarksManager.isBookmarksBarVisible) {
                Label(
                    loc.text(es: "Mostrar barra de marcadores (⇧⌘B)", en: "Show Bookmarks Bar (⇧⌘B)"),
                    systemImage: "bookmark"
                )
            }

            Divider()

            Section(loc.text(es: "Iconos en vista Lista:", en: "List view icons:")) {
                ForEach(ListIconDisplayMode.allCases) { mode in
                    Toggle(isOn: Binding(
                        get: { ListIconPreferences.shared.mode == mode },
                        set: { _ in ListIconPreferences.shared.mode = mode }
                    )) {
                        Label(loc.listIconDisplayModeTitle(mode), systemImage: mode.systemImage)
                    }
                }
            }

            Divider()

            Section(loc.text(es: "Abrir marcadores web en:", en: "Open web bookmarks in:")) {
                ForEach(BookmarkOpenBehavior.allCases) { behavior in
                    Toggle(isOn: Binding(
                        get: { bookmarksManager.openBehavior == behavior },
                        set: { _ in bookmarksManager.openBehavior = behavior }
                    )) {
                        Label(behavior.localizedTitle, systemImage: behavior.systemImage)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: viewModel.viewMode.systemImage)
                    .font(.system(size: 12, weight: .medium))
                Text(loc.text(es: "Ver", en: "View"))
                    .font(.system(size: 12, weight: .regular))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .help(loc.text(es: "Opciones de visualización y archivos ocultos", en: "View layout and hidden files options"))
    }

    private var compactViewModeToggle: some View {
        HStack(spacing: 2) {
            ForEach(ExplorerViewMode.allCases) { mode in
                let isSelected = viewModel.viewMode == mode
                Button {
                    viewModel.viewMode = mode
                } label: {
                    Image(systemName: mode.systemImage)
                        .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .frame(width: 26, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(loc.viewModeTitle(mode))
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func clipboardIndicatorPill(payload: ClipboardPayload) -> some View {
        let isCut = payload.mode == .cut
        let count = payload.urls.count
        let labelText: String
        if isCut {
            labelText = loc.text(
                es: "\(count) \(count == 1 ? "ítem cortado" : "ítems cortados")",
                en: "\(count) \(count == 1 ? "item cut" : "items cut")"
            )
        } else {
            labelText = loc.text(
                es: "\(count) \(count == 1 ? "ítem copiado" : "ítems copiados")",
                en: "\(count) \(count == 1 ? "item copied" : "items copied")"
            )
        }

        return HStack(spacing: 6) {
            Image(systemName: isCut ? "scissors" : "doc.on.doc")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isCut ? Color.orange : Color.accentColor)

            Text(labelText)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)

            Button {
                viewModel.clipboardManager.clear()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help(loc.text(es: "Limpiar portapapeles (Esc)", en: "Clear clipboard (Esc)"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(isCut ? Color.orange.opacity(0.12) : Color.accentColor.opacity(0.10))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(isCut ? Color.orange.opacity(0.30) : Color.accentColor.opacity(0.22), lineWidth: 0.5)
        )
    }

    private var commandDivider: some View {
        Divider()
            .frame(height: 20)
            .padding(.horizontal, 4)
    }
}

// MARK: - Botón Individual de la Barra de Comandos

private struct CommandActionButton: View {
    let title: String
    let systemImage: String
    let shortcutHint: String
    let isEnabled: Bool
    var isActive: Bool = false
    var prominentBadge: Bool = false
    var isDestructive: Bool = false
    let action: () -> Void

    @ViewState private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(iconColor)

                Text(title)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.55))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering in
            isHovered = hovering
        }
        .help("\(title) (\(shortcutHint))")
    }

    private var iconColor: Color {
        guard isEnabled else { return .secondary.opacity(0.4) }
        if isDestructive && isHovered {
            return .red
        }
        if isActive || prominentBadge {
            return .orange
        }
        return .primary
    }

    private var backgroundColor: Color {
        guard isEnabled else { return .clear }
        if isActive {
            return Color.orange.opacity(0.15)
        }
        if isHovered {
            return Color.primary.opacity(0.07)
        }
        return .clear
    }

    private var borderColor: Color {
        if isActive && isEnabled {
            return Color.orange.opacity(0.35)
        }
        if isHovered && isEnabled {
            return Color.primary.opacity(0.10)
        }
        return .clear
    }
}
