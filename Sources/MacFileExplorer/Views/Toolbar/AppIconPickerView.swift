import AppKit
import SwiftUI

/// Controlador singleton de la ventana visual para elegir el ícono de `MacFileExplorer` en macOS.
@MainActor
public final class AppIconPickerWindowController: NSObject, NSWindowDelegate {
    public static let shared = AppIconPickerWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    public func show() {
        let title = LocalizationManager.shared.text(
            es: "Ícono de MacFileExplorer",
            en: "MacFileExplorer App Icon"
        )
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let existing = window {
            existing.title = title
            existing.contentView = NSHostingView(rootView: AppIconPickerModalView(onClose: { [weak self] in
                self?.close()
            }))
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let created = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        created.delegate = self
        created.title = title
        created.titlebarAppearsTransparent = true
        created.titleVisibility = .hidden
        created.isMovableByWindowBackground = true
        created.isReleasedWhenClosed = false
        created.tabbingMode = .disallowed
        created.contentView = NSHostingView(rootView: AppIconPickerModalView(onClose: { [weak self] in
            self?.close()
        }))
        created.center()
        created.makeKeyAndOrderFront(nil)
        self.window = created
    }

    public func refreshLocalizedTitle() {
        window?.title = LocalizationManager.shared.text(
            es: "Ícono de MacFileExplorer",
            en: "MacFileExplorer App Icon"
        )
    }

    public func close() {
        window?.close()
    }

    public func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
    }
}

/// Grilla reutilizable con los 5 íconos seleccionables de `MacFileExplorer` (Clásico + 4 estilos modernos).
public struct MacFileExplorerAppIconGridView: View {
    public let previewDark: Bool
    @Bindable private var iconProvider = FileIconProvider.shared
    @Bindable private var loc = LocalizationManager.shared

    private let columns = [GridItem(.adaptive(minimum: 106, maximum: 136), spacing: 10)]

    public init(previewDark: Bool) {
        self.previewDark = previewDark
    }

    public var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(MacFileExplorerAppIcon.allCases) { option in
                let isSelected = iconProvider.selectedAppIcon == option
                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.74)) {
                        iconProvider.selectedAppIcon = option
                    }
                } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(previewDark ? Color(white: 0.14) : Color(white: 0.94))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(
                                            previewDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08),
                                            lineWidth: 0.8
                                        )
                                )
                                .frame(width: 68, height: 68)

                            if let img = iconProvider.previewImage(for: option, colorScheme: previewDark ? .dark : .light) {
                                Image(nsImage: img)
                                    .resizable()
                                    .interpolation(.high)
                                    .scaledToFit()
                                    .frame(width: 56, height: 56)
                                    .scaleEffect(isSelected ? 1.04 : 1.0)
                            }
                        }

                        VStack(spacing: 1) {
                            Text(option.localizedTitle(using: loc))
                                .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)

                            Text(option.localizedSubtitle(using: loc))
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.035))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                                lineWidth: isSelected ? 1.5 : 0.75
                            )
                    )
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.accentColor)
                                .padding(6)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Ventana modal elegante con vista previa en vivo en un mini Dock de macOS.
private struct AppIconPickerModalView: View {
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var iconProvider = FileIconProvider.shared
    @Bindable private var loc = LocalizationManager.shared

    var body: some View {
        let isDark = colorScheme == .dark
        VStack(spacing: 18) {
            VStack(spacing: 5) {
                Text(loc.text(es: "Ícono de MacFileExplorer en macOS", en: "MacFileExplorer App Icon on macOS"))
                    .font(.system(size: 18, weight: .bold))
                Text(loc.text(
                    es: "Elegí qué ícono mostrar en el Dock de macOS, ⌘+Tab, la Barra de tareas, AltTab y las ventanas de la app.",
                    en: "Choose which icon appears in the macOS Dock, ⌘+Tab, Taskbar, AltTab, and app windows."
                ))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            .padding(.top, 12)

            // Vista previa en vivo dentro de un mini Dock estilo macOS
            HStack(spacing: 14) {
                dockSampleIcon("/System/Applications/Finder.app")
                dockSampleIcon("/System/Applications/Notes.app")

                VStack(spacing: 3) {
                    if let current = iconProvider.appIcon(for: colorScheme) {
                        Image(nsImage: current)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 48, height: 48)
                    }
                    Circle()
                        .fill(Color.primary.opacity(0.75))
                        .frame(width: 4, height: 4)
                }

                dockSampleIcon("/System/Applications/Messages.app")
                dockSampleIcon("/System/Applications/System Settings.app")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isDark ? Color.white.opacity(0.16) : Color.black.opacity(0.10), lineWidth: 1)
            )

            MacFileExplorerAppIconGridView(previewDark: isDark)

            HStack {
                Text(loc.text(
                    es: "Se aplica al instante y se recuerda automáticamente al volver a abrir la app.",
                    en: "Applies immediately and is remembered automatically across launches."
                ))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                Spacer()

                Button(loc.text(es: "Listo", en: "Done")) {
                    onClose()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(width: 640, height: 430)
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand { onClose() }
    }

    private func dockSampleIcon(_ path: String) -> some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 42, height: 42)
            .opacity(0.78)
    }
}
