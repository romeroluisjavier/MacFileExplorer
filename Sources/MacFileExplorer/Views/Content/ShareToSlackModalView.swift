import SwiftUI
import AppKit

/// Diálogo modal nativo para "Compartir con Slack" desde el menú contextual.
/// Permite seleccionar canal o destinatario (con sugerencias de recientes),
/// escribir un mensaje opcional y adjuntar automáticamente los archivos en la conversación de Slack.
public struct ShareToSlackModalView: View {
    let viewModel: ExplorerViewModel
    @Environment(\.dismiss) private var dismiss

    @ViewState private var destination: String = ""
    @ViewState private var message: String = ""
    @ViewState private var recentDestinations: [String] = []

    private var loc: LocalizationManager { LocalizationManager.shared }

    public init(viewModel: ExplorerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 18) {
                    filesPreviewSection

                    destinationSection

                    messageSection

                    helperTipSection
                }
                .padding(20)
            }

            Divider()

            footerBar
        }
        .frame(width: 480, height: 490)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            let loaded = PersistenceService.shared.loadSlackRecentDestinations()
            recentDestinations = loaded
            if destination.isEmpty, let first = loaded.first {
                destination = first
            }
        }
    }

    // MARK: - Barra Superior

    private var headerBar: some View {
        HStack(spacing: 10) {
            if let slackIcon = viewModel.slackMenuIcon() {
                Image(nsImage: slackIcon)
                    .resizable()
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.accentColor)
            }

            Text(loc.text(es: "Compartir con Slack", en: "Share with Slack"))
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(5)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Sección de Previsualización de Archivos

    private var filesPreviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc.text(
                es: "Archivos a compartir (\(viewModel.slackShareURLs.count))",
                en: "Files to share (\(viewModel.slackShareURLs.count))"
            ))
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                ForEach(viewModel.slackShareURLs.prefix(4), id: \.self) { url in
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                            .resizable()
                            .frame(width: 20, height: 20)

                        Text(url.lastPathComponent)
                            .font(.system(size: 12.5, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Text(fileSizeString(for: url))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                }

                if viewModel.slackShareURLs.count > 4 {
                    Text(loc.text(
                        es: "... y \(viewModel.slackShareURLs.count - 4) archivo(s) más",
                        en: "... and \(viewModel.slackShareURLs.count - 4) more file(s)"
                    ))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                }
            }
        }
    }

    // MARK: - Sección de Destino (Canal o Persona)

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(loc.text(es: "Canal o persona", en: "Channel or person"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)

                Text(loc.text(es: "(opcional si ya estás en el chat)", en: "(optional if already in chat)"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Image(systemName: destination.starts(with: "@") ? "person.fill" : "number")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                TextField(
                    loc.text(es: "ej. #general, #proyecto, @nombre...", en: "e.g. #general, #project, @name..."),
                    text: $destination
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit {
                    submitShare()
                }

                if !destination.isEmpty {
                    Button {
                        destination = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )

            // Chips de destinos frecuentes
            if !recentDestinations.isEmpty {
                HStack(spacing: 6) {
                    Text(loc.text(es: "Sugerencias:", en: "Recent:"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(recentDestinations, id: \.self) { chip in
                                Button {
                                    destination = chip
                                } label: {
                                    Text(chip)
                                        .font(.system(size: 11, weight: destination == chip ? .semibold : .regular))
                                        .foregroundStyle(destination == chip ? Color.white : Color.primary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(destination == chip ? Color.accentColor : Color.secondary.opacity(0.12))
                                        .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Sección de Mensaje

    private var messageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.text(es: "Mensaje adicional (opcional)", en: "Additional message (optional)"))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.primary)

            TextField(
                loc.text(
                    es: "Escribe un comentario o nota para acompañar el archivo...",
                    en: "Write a comment or note to accompany the file..."
                ),
                text: $message,
                axis: .vertical
            )
            .lineLimit(3...5)
            .font(.system(size: 12.5))
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
    }

    // MARK: - Nota informativa

    private var helperTipSection: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 1)

            Text(loc.text(
                es: "Al pulsar «Compartir», se abrirá Slack, se seleccionará la conversación y se adjuntarán los archivos seleccionados automáticamente.",
                en: "Clicking «Share» will open Slack, jump to the chosen conversation, and automatically attach the selected files."
            ))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.06))
        .cornerRadius(6)
    }

    // MARK: - Barra Inferior

    private var footerBar: some View {
        HStack(spacing: 10) {
            Spacer()

            Button {
                dismiss()
            } label: {
                Text(loc.text(es: "Cancelar", en: "Cancel"))
                    .frame(minWidth: 75)
            }
            .keyboardShortcut(.cancelAction)

            Button {
                submitShare()
            } label: {
                HStack(spacing: 6) {
                    if let slackIcon = viewModel.slackMenuIcon() {
                        Image(nsImage: slackIcon)
                            .resizable()
                            .frame(width: 14, height: 14)
                    }
                    Text(loc.text(es: "Compartir en Slack", en: "Share in Slack"))
                }
                .fontWeight(.semibold)
                .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.slackShareURLs.isEmpty)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }

    private func submitShare() {
        guard !viewModel.slackShareURLs.isEmpty else { return }
        let urlsToShare = viewModel.slackShareURLs
        let dest = destination
        let msg = message
        dismiss()
        viewModel.sendToSlack(urls: urlsToShare, destination: dest, message: msg)
    }

    private func fileSizeString(for url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)),
              let size = attrs[.size] as? Int64 else {
            return ""
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
