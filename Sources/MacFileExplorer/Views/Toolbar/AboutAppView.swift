import AppKit
import SwiftUI

/// Controlador singleton para presentar la ventana nativa "Acerca de MacFileExplorer"
/// con información de autoría, versión y Notas de la versión.
@MainActor
public final class AboutWindowController {
    public static let shared = AboutWindowController()

    private var window: NSWindow?

    private init() {}

    public func show() {
        let title = LocalizationManager.shared.text(
            es: "Acerca de MacFileExplorer",
            en: "About MacFileExplorer"
        )

        if let existingWindow = window {
            existingWindow.title = title
            existingWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let createdWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 660),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        createdWindow.title = title
        createdWindow.titlebarAppearsTransparent = true
        createdWindow.titleVisibility = .hidden
        createdWindow.isMovableByWindowBackground = true
        createdWindow.isReleasedWhenClosed = false
        createdWindow.contentView = NSHostingView(
            rootView: AboutAppView(onClose: { [weak self] in
                self?.close()
            })
        )
        createdWindow.center()
        createdWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.window = createdWindow
    }

    public func close() {
        window?.close()
    }
}

/// Ventana "Acerca de MacFileExplorer" con créditos de autoría y Release Notes en lenguaje claro.
public struct AboutAppView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var loc = LocalizationManager.shared

    private let onClose: (() -> Void)?

    public init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal, 28)
                .padding(.top, 26)
                .padding(.bottom, 18)

            Divider()

            releaseNotesSection

            Divider()

            footerSection
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
        }
        .frame(width: 540, height: 660)
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand {
            closeWindow()
        }
    }

    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "3"
        return "\(version) (Build \(build) • Swift 6)"
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Group {
                if let appIcon = FileIconProvider.shared.appIcon(for: colorScheme) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 78, height: 78)
                } else {
                    Image(systemName: "folder.fill.badge.gearshape")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 78, height: 78)
                }
            }

            VStack(spacing: 3) {
                Text("MacFileExplorer")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.primary)

                Text(loc.text(
                    es: "Versión \(versionLabel)",
                    en: "Version \(versionLabel)"
                ))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
            }

            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Text(loc.text(es: "Desarrollado por", en: "Developed by"))
                        .foregroundStyle(.secondary)
                    Text("Luis Javier Romero")
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                }
                .font(.system(size: 12.5))

                Text(loc.text(es: "Creador y Arquitecto de Software", en: "Creator & Software Architect"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)

            Text(loc.text(
                es: "Explorador de Archivos estilo Windows 11 con estética nativa para macOS.\nConstruido con Swift 6, SwiftUI y AppKit.",
                en: "Windows 11 Style File Explorer with native macOS aesthetics.\nBuilt with Swift 6, SwiftUI & AppKit."
            ))
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .padding(.top, 2)
        }
    }

    private var releaseNotesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                Text(loc.text(es: "Notas de la versión", en: "Release Notes"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Text(loc.text(
                    es: "\(totalFeatureCount) novedades",
                    en: "\(totalFeatureCount) updates"
                ))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2.5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(ReleaseNotesCatalog.sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(section.localizedVersionLabel(using: loc))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.primary)

                                Spacer(minLength: 8)

                                Text(section.localizedDateLabel(using: loc))
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(Color.accentColor.opacity(0.12))
                                    )
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(section.items) { item in
                                    ReleaseNoteRow(
                                        icon: item.icon,
                                        title: item.localizedTitle(using: loc),
                                        detail: item.localizedSummary(using: loc)
                                    )
                                }
                            }
                            .padding(11)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.primary.opacity(0.035))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.8)
                            )
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
    }

    private var footerSection: some View {
        HStack {
            Text(loc.text(
                es: "© 2026 Luis Javier Romero. Todos los derechos reservados.",
                en: "© 2026 Luis Javier Romero. All rights reserved."
            ))
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)

            Spacer()

            Button(loc.text(es: "Cerrar", en: "Close")) {
                closeWindow()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var totalFeatureCount: Int {
        ReleaseNotesCatalog.sections.reduce(0) { $0 + $1.items.count }
    }

    private func closeWindow() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}

private struct ReleaseNoteRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18, height: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(1.5)
            }
        }
    }
}
