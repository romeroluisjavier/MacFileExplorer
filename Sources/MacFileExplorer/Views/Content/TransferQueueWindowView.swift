import AppKit
import SwiftUI

/// Panel desplegable (popover) anclado a la barra de progreso inferior para controlar
/// la cola de transferencias (> 1 GB) con Pausar, Reanudar y Cancelar sin ventanas flotantes huérfanas.
public struct TransferQueuePopoverView: View {
    @Bindable private var manager = TransferQueueManager.shared

    private var loc: LocalizationManager { LocalizationManager.shared }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(
                    loc.text(es: "Cola de transferencias", en: "Transfer Queue"),
                    systemImage: "arrow.up.arrow.down.circle.fill"
                )
                .font(.system(size: 13, weight: .semibold))

                Spacer()

                Text("\(manager.jobs.count)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            ScrollView(.vertical) {
                LazyVStack(spacing: 8) {
                    ForEach(manager.jobs) { job in
                        TransferJobRowView(job: job, manager: manager)
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 280)
        }
        .frame(width: 400)
    }
}

private struct TransferJobRowView: View {
    @Bindable var job: TransferJob
    let manager: TransferQueueManager

    private var loc: LocalizationManager { LocalizationManager.shared }

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: job.kind == .copy ? "doc.on.doc.fill" : "arrow.right.doc.on.clipboard")
                    .font(.system(size: 13))
                    .foregroundStyle(statusColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(job.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(subtitleText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if job.status == .running {
                    Button {
                        manager.pause(job)
                    } label: {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(loc.text(es: "Pausar", en: "Pause"))
                } else if job.status == .paused {
                    Button {
                        manager.resume(job)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help(loc.text(es: "Reanudar", en: "Resume"))
                }

                Button {
                    manager.cancel(job)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(loc.text(es: "Cancelar", en: "Cancel"))
            }

            ProgressView(value: job.progress, total: 1.0)
                .progressViewStyle(.linear)
                .tint(job.status == .paused ? .orange : Color.accentColor)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
        )
    }

    private var statusColor: Color {
        switch job.status {
        case .queued: return .secondary
        case .running: return Color.accentColor
        case .paused: return .orange
        case .completed: return .green
        case .cancelled: return .secondary
        case .failed: return .red
        }
    }

    private var subtitleText: String {
        let transferred = Self.byteFormatter.string(fromByteCount: job.transferredBytes)
        let total = Self.byteFormatter.string(fromByteCount: job.totalBytes)
        let pct = Int((job.progress * 100).rounded())

        switch job.status {
        case .queued:
            return loc.text(es: "En cola (\(total))", en: "Queued (\(total))")
        case .running:
            let filePrefix = job.currentFileName.isEmpty ? "" : "\(job.currentFileName) • "
            return "\(filePrefix)\(transferred) / \(total) (\(pct)%)"
        case .paused:
            return loc.text(
                es: "Pausado • \(transferred) / \(total) (\(pct)%)",
                en: "Paused • \(transferred) / \(total) (\(pct)%)"
            )
        case .completed:
            return loc.text(es: "Completado (\(total))", en: "Completed (\(total))")
        case .cancelled:
            return loc.text(es: "Cancelado", en: "Cancelled")
        case .failed(let msg):
            return loc.text(es: "Error: \(msg)", en: "Error: \(msg)")
        }
    }
}
