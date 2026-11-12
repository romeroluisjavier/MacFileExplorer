import SwiftUI
import AppKit
import QuickLookUI

/// Envoltorio `NSViewRepresentable` sobre `QLPreviewView` nativo de macOS (`QuickLookUI`).
/// Permite previsualizar PDFs, imágenes, vídeos, audio, código fuente, documentos de texto y carpetas.
public struct NativeQLPreviewRepresentable: NSViewRepresentable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func makeNSView(context: Context) -> QLPreviewView {
        let previewView = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        previewView.autostarts = true
        previewView.shouldCloseWithWindow = false
        previewView.previewItem = fileURL.standardizedFileURL as NSURL
        return previewView
    }

    public func updateNSView(_ nsView: QLPreviewView, context: Context) {
        let targetURL = fileURL.standardizedFileURL as NSURL
        if let current = nsView.previewItem as? NSURL, current == targetURL {
            return
        }
        nsView.previewItem = targetURL
        nsView.refreshPreviewItem()
    }
}

/// Ventana flotante de Vista Rápida (Quick Look) al presionar la Barra Espaciadora (`Space`),
/// emulando el Quick Look del Finder de macOS con el botón "Open in Preview" arriba a la derecha.
public struct QuickLookPreviewModalView: View {
    @Bindable var viewModel: ExplorerViewModel
    let item: FileItem

    public init(viewModel: ExplorerViewModel, item: FileItem) {
        self.viewModel = viewModel
        self.item = item
    }

    public var body: some View {
        ZStack {
            // Fondo semitransparente que cierra el Quick Look al hacer clic fuera
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture {
                    viewModel.closeQuickLook()
                }

            // Panel flotante estilo Quick Look de macOS Finder
            VStack(spacing: 0) {
                // Barra superior del Quick Look (Cerrar, Navegación ‹ ›, Título y botón "Open in Preview" a la derecha)
                quickLookHeaderBar

                Divider()

                // Cuerpo del Previsualizador: Propiedades completas para carpetas, QLPreviewView nativo para archivos
                ZStack {
                    if item.isNavigableFolder {
                        Color(nsColor: .windowBackgroundColor)
                        ItemPropertiesContentView(
                            item: item,
                            horizontalPadding: 32,
                            verticalPadding: 22
                        )
                        .frame(maxWidth: 640)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id(item.id)
                    } else {
                        Color(nsColor: .underPageBackgroundColor)
                        NativeQLPreviewRepresentable(fileURL: item.url)
                            .id(item.id)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 680, idealWidth: 820, maxWidth: 980, minHeight: 480, idealHeight: 580, maxHeight: 720)
            .padding(28)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThickMaterial)
                    .shadow(color: .black.opacity(0.38), radius: 28, y: 12)
                    .padding(28)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.8)
                    .padding(28)
            )
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    // MARK: - Barra Superior estilo Finder Quick Look

    private var quickLookHeaderBar: some View {
        let loc = LocalizationManager.shared
        return HStack(spacing: 10) {
            // 1. Botón de cerrar (✕) y flechas de elemento anterior/siguiente (‹ ›)
            Button {
                viewModel.closeQuickLook()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(loc.text(es: "Cerrar Vista Rápida (Espacio / Esc)", en: "Close Quick Look (Space / Esc)"))

            HStack(spacing: 2) {
                Button {
                    viewModel.selectAdjacentItem(offset: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!viewModel.canSelectPreviousItem)
                .help(loc.text(es: "Elemento anterior (↑ / ←)", en: "Previous item (↑ / ←)"))

                Button {
                    viewModel.selectAdjacentItem(offset: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!viewModel.canSelectNextItem)
                .help(loc.text(es: "Elemento siguiente (↓ / →)", en: "Next item (↓ / →)"))
            }

            Divider()
                .frame(height: 16)

            // 2. Icono y Nombre del archivo previsualizado
            HStack(spacing: 7) {
                Image(nsImage: FileIconProvider.shared.icon(for: item, size: 18))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 18, height: 18)

                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !item.formattedSize.isEmpty {
                    Text("(\(item.formattedSize))")
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            // 3. Acción principal contextual arriba a la derecha: "Abrir carpeta" o "Open in Preview"
            if item.isNavigableFolder {
                Button {
                    let target = item
                    viewModel.closeQuickLook()
                    viewModel.openItem(target)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 11.5, weight: .medium))
                        Text(loc.text(es: "Abrir carpeta", en: "Open Folder"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help(loc.text(
                    es: "Entrar en esta carpeta",
                    en: "Open this folder"
                ))
            } else {
                Button {
                    viewModel.openInNativePreviewApp(item)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.forward.app.fill")
                            .font(.system(size: 12, weight: .medium))
                        Text("Open in Preview")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help(loc.text(
                    es: "Abrir este archivo en la aplicación nativa 'Preview' (Vista Previa) de macOS",
                    en: "Open this file in macOS native 'Preview' application"
                ))
            }

            // Botón de compartir nativo opcional (como en Quick Look de Finder)
            ShareLink(item: item.url) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(loc.text(es: "Compartir archivo", en: "Share file"))
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(.bar)
    }
}
