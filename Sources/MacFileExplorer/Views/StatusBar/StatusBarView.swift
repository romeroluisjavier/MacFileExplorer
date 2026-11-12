import SwiftUI

/// Barra de Estado Inferior estilo Windows 11 Explorer con estética macOS.
/// Muestra el total de elementos en la carpeta actual, el conteo de elementos seleccionados,
/// la suma combinada de sus tamaños y conmutadores rápidos de modo de vista a la derecha.
public struct StatusBarView: View {
    @Bindable var viewModel: ExplorerViewModel

    private var loc: LocalizationManager { LocalizationManager.shared }

    public init(viewModel: ExplorerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 10) {
            // 1. Contador total de elementos en la carpeta actual
            HStack(spacing: 5) {
                Image(systemName: "folder")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                Text(totalItemsText)
                    .font(.system(size: 11.5, weight: .regular).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // 2. Contador de elementos seleccionados + suma de tamaños combinados
            if viewModel.selectedItemCount > 0 {
                Divider()
                    .frame(height: 12)

                HStack(spacing: 6) {
                    Text(selectedItemsText)
                        .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(.primary.opacity(0.85))

                    if !viewModel.formattedSelectedTotalSize.isEmpty {
                        Text(viewModel.formattedSelectedTotalSize)
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.accentColor.opacity(0.12))
                            )
                    }
                }
            }

            // 3. Indicador de filtro activo si hay búsqueda local
            if !viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider()
                    .frame(height: 12)

                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.accentColor)
                    Text("\(loc.text(es: "Filtro", en: "Filter")): \"\(viewModel.searchQuery)\"")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // 4. Estado de carga + Conmutadores rápidos de vista (Esquina inferior derecha Windows 11)
            if viewModel.isLoading {
                HStack(spacing: 5) {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                    Text(loc.text(es: "Cargando...", en: "Loading..."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            // Slider de tamaño de icono estilo Finder (visible en Large icons)
            if viewModel.viewMode == .largeIcons {
                Divider()
                    .frame(height: 12)

                HStack(spacing: 5) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            GridIconPreferences.shared.iconSize = max(
                                GridIconPreferences.shared.iconSize - 16,
                                GridIconPreferences.minIconSize
                            )
                        }
                    } label: {
                        Image(systemName: "photo")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(loc.text(es: "Reducir tamaño de icono", en: "Decrease icon size"))

                    Slider(
                        value: Binding(
                            get: { GridIconPreferences.shared.iconSize },
                            set: { GridIconPreferences.shared.iconSize = $0 }
                        ),
                        in: GridIconPreferences.minIconSize...GridIconPreferences.maxIconSize
                    )
                    .controlSize(.mini)
                    .frame(width: 96)

                    Button {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            GridIconPreferences.shared.iconSize = min(
                                GridIconPreferences.shared.iconSize + 16,
                                GridIconPreferences.maxIconSize
                            )
                        }
                    } label: {
                        Image(systemName: "photo")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(loc.text(es: "Aumentar tamaño de icono", en: "Increase icon size"))
                }
                .help(loc.text(
                    es: "Tamaño de iconos: \(Int(GridIconPreferences.shared.iconSize)) px",
                    en: "Icon size: \(Int(GridIconPreferences.shared.iconSize)) px"
                ))
            }

            Divider()
                .frame(height: 12)

            HStack(spacing: 2) {
                ForEach(ExplorerViewMode.allCases) { mode in
                    Button {
                        viewModel.viewMode = mode
                    } label: {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 11, weight: viewModel.viewMode == mode ? .semibold : .regular))
                            .foregroundStyle(viewModel.viewMode == mode ? Color.accentColor : Color.secondary)
                            .frame(width: 24, height: 20)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(viewModel.viewMode == mode ? Color.accentColor.opacity(0.14) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(loc.viewModeTitle(mode))
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(.bar)
    }

    private var totalItemsText: String {
        let count = viewModel.totalItemCount
        return loc.text(
            es: "\(count) \(count == 1 ? "elemento" : "elementos")",
            en: "\(count) \(count == 1 ? "item" : "items")"
        )
    }

    private var selectedItemsText: String {
        let count = viewModel.selectedItemCount
        return loc.text(
            es: "\(count) \(count == 1 ? "elemento seleccionado" : "elementos seleccionados")",
            en: "\(count) \(count == 1 ? "item selected" : "items selected")"
        )
    }
}
