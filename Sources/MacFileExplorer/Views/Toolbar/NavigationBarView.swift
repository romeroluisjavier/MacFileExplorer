import SwiftUI

/// Segunda fila de la barra superior estilo Windows 11 Explorer:
/// [←] [→] [▾] [↑] | [ Barra Breadcrumb / Ruta (Cmd+L) ] | [ 🔍 Buscar en <Carpeta> ]
public struct NavigationBarView: View {
    @Bindable var viewModel: ExplorerViewModel
    @FocusState private var isSearchFocused: Bool

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
                    isSearchFocused = false
                    KeyboardShortcuts.resignTextFocus()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(loc.text(es: "Limpiar búsqueda", en: "Clear search"))
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 230, height: 30)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    !viewModel.searchQuery.isEmpty
                        ? Color.accentColor.opacity(0.75)
                        : Color.primary.opacity(0.14),
                    lineWidth: 0.8
                )
        )
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
