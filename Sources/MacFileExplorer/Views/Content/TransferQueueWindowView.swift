import AppKit
import SwiftUI

/// Controlador singleton de la ventana flotante unificada de Cola de Transferencias (> 1 GB).
@MainActor
public final class TransferQueueWindowController {
    public static let shared = TransferQueueWindowController()

    private var window: NSWindow?

    private init() {}

    public func showWindow() {
        let loc = LocalizationManager.shared
        if let existing = window {
            existing.title = loc.text(es: "Cola de transferencias", en: "Transfer Queue")
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = TransferQueueWindowView()
        let hostingController = NSHostingController(rootView: contentView)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 340),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = loc.text(es: "Cola de transferencias", en: "Transfer Queue")
        win.isReleasedWhenClosed = false
        win.level = .floating
        win.minSize = NSSize(width: 400, height: 220)
        win.contentViewController = hostingController
        win.center()
        win.makeKeyAndOrderFront(nil)
        self.window = win
    }
}

public struct TransferQueueWindowView: View {
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
                .font(.system(size: 13.5, weight: .semibold))

                Spacer()

                if manager.jobs.contains(where: { $0.status.isTerminal }) {
                    Button(loc.text(es: "Limpiar finalizados", en: "Clear Finished")) {
                        manager.clearFinished()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            if manager.jobs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text(loc.text(es: "No hay transferencias activas.", en: "No active transfers."))
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 10) {
                        ForEach(manager.jobs) { job in
                            TransferJobRowView(job: job, manager: manager)
                        }
                    }
                    .padding(14)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 220)
        .background(Color(nsColor: .windowBackgroundColor))
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

                if !job.status.isTerminal {
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
            }

            if !job.status.isTerminal {
                ProgressView(value: job.progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(job.status == .paused ? .orange : Color.accentColor)
            }
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
