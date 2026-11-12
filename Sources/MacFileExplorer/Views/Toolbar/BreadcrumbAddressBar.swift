import SwiftUI
import AppKit

/// Barra de ruta híbrida estilo Windows 11 Explorer:
/// - Modo por defecto: "Breadcrumb" interactivo con segmentos clicables.
/// - Modo edición (`Cmd+L` o clic en el área vacía de la barra): campo de texto plano para escribir o pegar rutas (`/Users/...`).
public struct BreadcrumbAddressBar: View {
    @Bindable var viewModel: ExplorerViewModel
    @FocusState private var isTextFieldFocused: Bool

    private var loc: LocalizationManager { LocalizationManager.shared }

    public init(viewModel: ExplorerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 6) {
            // Icono de carpeta/volumen actual a la izquierda de la barra de ruta
            Image(systemName: viewModel.currentDirectoryURL.path == "/" ? "internaldrive.fill" : "folder.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.accentColor)
                .padding(.leading, 8)

            if viewModel.isEditingAddressBar {
                // Modo Texto Plano Editable (Cmd+L)
                TextField(
                    loc.text(
                        es: "Escribe una ruta (/Users/... o ~/Downloads)",
                        en: "Type a path (/Users/... or ~/Downloads)"
                    ),
                    text: $viewModel.addressBarText
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, design: .monospaced))
                .focused($isTextFieldFocused)
                .onSubmit {
                    viewModel.commitAddressBarNavigation()
                }
                .onExitCommand {
                    viewModel.cancelAddressBarEditing()
                }
                .onAppear {
                    isTextFieldFocused = true
                }

                Button(loc.text(es: "Ir", en: "Go")) {
                    viewModel.commitAddressBarNavigation()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    viewModel.cancelAddressBarEditing()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
                .help(loc.text(es: "Cancelar edición (Esc)", en: "Cancel editing (Esc)"))

            } else {
                // Modo Breadcrumb Clicable
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            let segments = viewModel.breadcrumbSegments
                            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                                BreadcrumbSegmentChip(
                                    segment: segment,
                                    isCurrent: index == segments.count - 1
                                ) {
                                    viewModel.navigate(to: segment.url)
                                }
                                .id(segment.id)

                                if index < segments.count - 1 {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal, 1)
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

                // Espacio vacío clicable para conmutar a edición de ruta plana (como en Windows Explorer)
                Color.clear
                    .frame(minWidth: 28, maxHeight: .infinity)
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
                isTextFieldFocused = true
            }
        }
    }
}

// MARK: - Chip Individual de Breadcrumb

private struct BreadcrumbSegmentChip: View {
    let segment: BreadcrumbSegment
    let isCurrent: Bool
    let action: () -> Void

    @ViewState private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
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
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
