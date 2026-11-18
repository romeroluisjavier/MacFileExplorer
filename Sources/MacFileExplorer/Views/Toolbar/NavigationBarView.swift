import SwiftUI

/// Segunda fila de la barra superior estilo Windows 11 Explorer:
/// [←] [→] [▾] [↑] | [ Barra Breadcrumb / Ruta (Cmd+L) ] | [ 🔍 Buscar en <Carpeta> ]
public struct NavigationBarView: View {
    @Bindable var viewModel: ExplorerViewModel
    @FocusState private var isSearchFocused: Bool
    @ViewState private var isAdvancedSearchPresented: Bool = false
    @ViewState private var optionsSnapshotOnOpen: AdvancedSearchOptions? = nil
    @ViewState private var cancelledPopoverClose: Bool = false

    private var loc: LocalizationManager { LocalizationManager.shared }

    public init(viewModel: ExplorerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 8) {
            // 1. Controles de Navegación (Atrás, Adelante, Historial, Subir)
            HStack(spacing: 2) {
                NavigationIconButton(
                    systemImage: "arrow.left",
                    helpText: loc.text(es: "Atrás (⌥←)", en: "Back (⌥←)"),
                    isEnabled: viewModel.canGoBack
                ) {
                    viewModel.goBack()
                }

                NavigationIconButton(
                    systemImage: "arrow.right",
                    helpText: loc.text(es: "Adelante (⌥→)", en: "Forward (⌥→)"),
                    isEnabled: viewModel.canGoForward
                ) {
                    viewModel.goForward()
                }

                historyMenu

                NavigationIconButton(
                    systemImage: "arrow.up",
                    helpText: loc.text(es: "Subir a carpeta superior (⌥↑)", en: "Up one level (⌥↑)"),
                    isEnabled: viewModel.canGoUp
                ) {
                    viewModel.goUp()
                }
            }

            // 2. Barra de Direcciones Breadcrumb / Texto Plano
            BreadcrumbAddressBar(viewModel: viewModel)
                .frame(maxWidth: .infinity)

            // 3. Caja de Búsqueda Local Rápida a la derecha (Estilo Windows 11)
            searchBox
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    // MARK: - Subvistas

    private var historyMenu: some View {
        Menu {
            if viewModel.backStack.isEmpty && viewModel.forwardStack.isEmpty {
                Text(loc.text(es: "Sin historial reciente", en: "No recent history"))
            } else {
                if !viewModel.forwardStack.isEmpty {
                    Section(loc.text(es: "Adelante", en: "Forward")) {
                        ForEach(viewModel.forwardStack.reversed(), id: \.self) { url in
                            Button {
                                viewModel.navigate(to: url)
                            } label: {
                                Label(
                                    url.path == "/" ? "Macintosh HD" : url.lastPathComponent,
                                    systemImage: "folder"
                                )
                            }
                        }
                    }
                }
                if !viewModel.backStack.isEmpty {
                    Section(loc.text(es: "Atrás", en: "Back")) {
                        ForEach(viewModel.backStack.reversed(), id: \.self) { url in
                            Button {
                                viewModel.navigate(to: url)
                            } label: {
                                Label(
                                    url.path == "/" ? "Macintosh HD" : url.lastPathComponent,
                                    systemImage: "folder"
                                )
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(
                    (viewModel.canGoBack || viewModel.canGoForward)
                        ? Color.secondary
                        : Color.secondary.opacity(0.35)
                )
                .frame(width: 18, height: 26)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(!viewModel.canGoBack && !viewModel.canGoForward)
        .help(loc.text(es: "Ubicaciones recientes", en: "Recent locations"))
    }

    private var searchBox: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(
                loc.text(
                    es: "Buscar en \(viewModel.currentFolderTitle)",
                    en: "Search \(viewModel.currentFolderTitle)"
                ),
                text: $viewModel.searchQuery
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .focused($isSearchFocused)
            .onSubmit {
                isSearchFocused = false
                KeyboardShortcuts.resignTextFocus()
            }
            .onAppear {
                DispatchQueue.main.async {
                    isSearchFocused = false
                    if viewModel.renamingItemID == nil && !viewModel.isEditingAddressBar {
                        KeyboardShortcuts.resignTextFocus()
                    }
                }
            }

            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
                    if !viewModel.isAdvancedSearchActive {
                        isSearchFocused = false
                        KeyboardShortcuts.resignTextFocus()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(loc.text(es: "Limpiar búsqueda", en: "Clear search"))
            }

            Button {
                isAdvancedSearchPresented.toggle()
            } label: {
                Image(
                    systemName: viewModel.isAdvancedSearchActive
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(viewModel.isAdvancedSearchActive ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(loc.text(es: "Buscador avanzado", en: "Advanced Search"))
            .popover(isPresented: $isAdvancedSearchPresented, arrowEdge: .bottom) {
                advancedSearchPopover
            }
            .onChange(of: isAdvancedSearchPresented) { wasOpen, isOpen in
                if isOpen {
                    cancelledPopoverClose = false
                    optionsSnapshotOnOpen = viewModel.advancedSearchOptions
                } else if wasOpen {
                    if cancelledPopoverClose {
                        cancelledPopoverClose = false
                    } else if let prev = optionsSnapshotOnOpen,
                              prev != viewModel.advancedSearchOptions {
                        viewModel.runAdvancedSearch()
                    }
                    optionsSnapshotOnOpen = nil
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 245, height: 30)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    (!viewModel.searchQuery.isEmpty || viewModel.isAdvancedSearchActive)
                        ? Color.accentColor.opacity(0.75)
                        : Color.primary.opacity(0.14),
                    lineWidth: 0.8
                )
        )
    }

    private var advancedSearchPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    loc.text(es: "Buscador avanzado", en: "Advanced Search"),
                    systemImage: "magnifyingglass.circle.fill"
                )
                .font(.system(size: 13, weight: .semibold))
                Spacer()
                if viewModel.isAdvancedSearchActive || viewModel.advancedSearchOptions.hasActiveFilters {
                    Button(loc.text(es: "Limpiar", en: "Reset")) {
                        viewModel.clearAdvancedSearch()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11.5))
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(loc.text(es: "Texto:", en: "Query:"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .leading)
                    TextField(
                        loc.text(es: "Nombre o contenido…", en: "Name or content…"),
                        text: $viewModel.searchQuery
                    )
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        cancelledPopoverClose = true
                        isAdvancedSearchPresented = false
                        viewModel.runAdvancedSearch()
                    }
                }

                HStack {
                    Text(loc.text(es: "Tipo:", en: "File type:"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .leading)
                    Picker("", selection: $viewModel.advancedSearchOptions.fileType) {
                        ForEach(AdvancedSearchFileType.allCases) { type in
                            Text(type.localizedTitle(using: loc)).tag(type)
                        }
                    }
                    .labelsHidden()
                }

                HStack {
                    Text(loc.text(es: "Extensión:", en: "Extension:"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .leading)
                    TextField(
                        loc.text(es: "Ej: pdf, jpg, swift", en: "e.g. pdf, jpg, swift"),
                        text: $viewModel.advancedSearchOptions.customExtension
                    )
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        cancelledPopoverClose = true
                        isAdvancedSearchPresented = false
                        viewModel.runAdvancedSearch()
                    }
                }

                HStack {
                    Text(loc.text(es: "Tamaño:", en: "File size:"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .leading)
                    Picker("", selection: $viewModel.advancedSearchOptions.sizeComparison) {
                        ForEach(AdvancedSearchSizeComparison.allCases) { cmp in
                            Text(cmp.localizedTitle(using: loc)).tag(cmp)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 118)

                    if viewModel.advancedSearchOptions.sizeComparison != .any {
                        TextField("10", text: $viewModel.advancedSearchOptions.sizeValueText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 56)

                        Picker("", selection: $viewModel.advancedSearchOptions.sizeUnit) {
                            ForEach(AdvancedSearchSizeUnit.allCases) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 62)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Toggle(
                    loc.text(
                        es: "Incluir subcarpetas",
                        en: "Include subfolders"
                    ),
                    isOn: $viewModel.advancedSearchOptions.includeSubfolders
                )
                .font(.system(size: 12))

                Toggle(
                    loc.text(
                        es: "Buscar dentro de archivos (Texto, PDF e Imágenes OCR)",
                        en: "Search inside files (Text, PDF & Image OCR)"
                    ),
                    isOn: $viewModel.advancedSearchOptions.searchInsideContent
                )
                .font(.system(size: 12))
            }

            HStack {
                Spacer()
                Button(loc.text(es: "Cancelar", en: "Cancel")) {
                    cancelledPopoverClose = true
                    if let prev = optionsSnapshotOnOpen {
                        viewModel.advancedSearchOptions = prev
                    }
                    isAdvancedSearchPresented = false
                }
                .buttonStyle(.bordered)

                Button(loc.text(es: "Buscar", en: "Search")) {
                    cancelledPopoverClose = true
                    isAdvancedSearchPresented = false
                    viewModel.runAdvancedSearch()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 365)
    }
}

// MARK: - Botón Redondeado de Navegación

private struct NavigationIconButton: View {
    let systemImage: String
    let helpText: String
    let isEnabled: Bool
    let action: () -> Void

    @ViewState private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.35))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovered && isEnabled ? Color.primary.opacity(0.08) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(helpText)
    }
}
