import AppKit
import Observation
import SwiftUI

/// Secciones extensibles de la ventana **Archivo → Herramientas (Tools)**.
/// Diseñada para incorporar fácilmente nuevas utilidades y configuraciones globales del sistema.
public enum ToolsSettingsSection: String, CaseIterable, Identifiable, Sendable {
    case viewDesktop

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .viewDesktop:
            return loc.text(es: "View Desktop Shortcut", en: "View Desktop Shortcut")
        }
    }

    @MainActor
    public func localizedSubtitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .viewDesktop:
            return loc.text(es: "Mostrar y enfocar el Escritorio", en: "Show & focus Mac Desktop")
        }
    }

    public var systemImage: String {
        switch self {
        case .viewDesktop:
            return "macwindow.on.rectangle"
        }
    }
}

@MainActor
@Observable
private final class ToolsSettingsWindowState {
    var selectedSection: ToolsSettingsSection = .viewDesktop
}

/// Controlador de la ventana de configuración del submenú **Archivo → Herramientas (Tools)**.
@MainActor
public final class ToolsSettingsWindowController: NSObject, NSWindowDelegate {

    public static let shared = ToolsSettingsWindowController()

    private var window: NSWindow?
    private let state = ToolsSettingsWindowState()

    private override init() {
        super.init()
    }

    public func show(initialSection: ToolsSettingsSection = .viewDesktop) {
        state.selectedSection = initialSection
        let loc = LocalizationManager.shared

        if let existing = window {
            existing.title = localizedWindowTitle(using: loc)
            NSApplication.shared.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.minSize = NSSize(width: 620, height: 450)
        win.isReleasedWhenClosed = false
        win.tabbingMode = .disallowed
        win.delegate = self
        win.title = localizedWindowTitle(using: loc)
        win.contentViewController = NSHostingController(
            rootView: ToolsSettingsView(state: state) { [weak win] in
                win?.close()
            }
        )
        win.center()
        self.window = win

        NSApplication.shared.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    public func refreshLocalizedTitle() {
        window?.title = localizedWindowTitle(using: .shared)
    }

    private func localizedWindowTitle(using loc: LocalizationManager) -> String {
        loc.text(
            es: "Configuración de Herramientas",
            en: "Tools Settings"
        )
    }

    public func windowWillClose(_ notification: Notification) {
        ToolsShortcutManager.shared.setRecordingSuspended(false)
        ClipboardHistoryManager.shared.setRecordingSuspended(false)
        AltTabHotkeyMonitor.shared.isRecordingShortcut = false
    }
}

private struct ToolsSettingsView: View {
    @Bindable var state: ToolsSettingsWindowState
    let onClose: () -> Void

    @Bindable private var loc = LocalizationManager.shared
    @Bindable private var shortcutPrefs = AppShortcutPreferences.shared
    @Bindable private var toolsManager = ToolsShortcutManager.shared

    @ViewState private var isRecordingViewDesktop = false
    @ViewState private var recordingMonitor: Any? = nil

    private struct ShortcutPreset: Identifiable {
        let id: String
        let label: String
        let shortcut: AppKeyShortcut
    }

    private var viewDesktopPresets: [ShortcutPreset] {
        [
            ShortcutPreset(
                id: "cmd_d",
                label: loc.text(es: "⌘D (Por defecto)", en: "⌘D (Default)"),
                shortcut: .defaultViewDesktop
            ),
            ShortcutPreset(
                id: "opt_d",
                label: "⌥D",
                shortcut: AppKeyShortcut(keyCode: 2, option: true, keyDisplayLabel: "D")
            ),
            ShortcutPreset(
                id: "ctrl_cmd_d",
                label: "⌃⌘D",
                shortcut: AppKeyShortcut(keyCode: 2, command: true, control: true, keyDisplayLabel: "D")
            ),
            ShortcutPreset(
                id: "shift_cmd_d",
                label: "⇧⌘D",
                shortcut: AppKeyShortcut(keyCode: 2, command: true, shift: true, keyDisplayLabel: "D")
            ),
            ShortcutPreset(
                id: "f11",
                label: "F11",
                shortcut: AppKeyShortcut(keyCode: 103, keyDisplayLabel: "F11")
            )
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebarPane
                Divider()
                detailPane
            }
            Divider()
            footerPane
        }
        .frame(minWidth: 620, minHeight: 450)
        .onDisappear {
            stopRecording()
        }
    }

    // MARK: - Sidebar extensible de Herramientas

    private var sidebarPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(loc.text(es: "Herramientas", en: "Tools"))
                    .font(.system(size: 13, weight: .bold))
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            ForEach(ToolsSettingsSection.allCases) { section in
                let isSelected = state.selectedSection == section
                Button {
                    state.selectedSection = section
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: section.systemImage)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 1.5) {
                            Text(section.localizedTitle(using: loc))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isSelected ? Color.white : Color.primary)
                                .lineLimit(1)
                            Text(section.localizedSubtitle(using: loc))
                                .font(.system(size: 10))
                                .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(isSelected ? Color.accentColor : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text(loc.text(es: "Espacio modular", en: "Extensible Hub"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(loc.text(
                    es: "Las nuevas utilidades y configuraciones de herramientas aparecerán aquí.",
                    en: "New system utilities and tool configurations will live here."
                ))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
        }
        .padding(12)
        .frame(width: 215)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))
    }

    // MARK: - Panel de detalle

    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch state.selectedSection {
                case .viewDesktop:
                    viewDesktopDetailContent
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var viewDesktopDetailContent: some View {
        let current = shortcutPrefs.viewDesktopShortcut
        let conflicts = shortcutPrefs.conflictingActionTitles(
            for: current.conflictSignature,
            excludingIdentifier: AppShortcutAction.viewDesktop.id,
            using: loc
        )

        return VStack(alignment: .leading, spacing: 16) {
            // Cabecera de herramienta
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: "macwindow.on.rectangle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(loc.text(es: "View Desktop Shortcut", en: "View Desktop Shortcut"))
                            .font(.system(size: 16, weight: .bold))

                        statusBadge(for: current)
                    }

                    Text(loc.text(
                        es: "Muestra y pone en foco el Escritorio de tu Mac al instante desde cualquier aplicación (por defecto ⌘D, al estilo Win+D de Windows). Volvé a pulsar el atajo para regresar a tus ventanas.",
                        en: "Instantly reveals and focuses your Mac Desktop from any application (default ⌘D, just like Windows Win+D). Press the shortcut again to return to your windows."
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Tarjeta 1: Activación y grabación del atajo
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $shortcutPrefs.isViewDesktopShortcutEnabled) {
                    VStack(alignment: .leading, spacing: 1.5) {
                        Text(loc.text(
                            es: "Activar atajo global «Ver Escritorio»",
                            en: "Enable global \"View Desktop\" shortcut"
                        ))
                        .font(.system(size: 13, weight: .semibold))

                        Text(loc.text(
                            es: "Funciona en todo macOS sin necesidad de permisos adicionales.",
                            en: "Works system-wide across macOS without extra permissions."
                        ))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Divider()

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.text(es: "Combinación de teclas", en: "Key Combination"))
                            .font(.system(size: 12.5, weight: .semibold))
                        Text(loc.text(
                            es: "Hacé clic en el botón y presioná tu combinación preferida (o una tecla F1–F19).",
                            en: "Click the button and press your preferred key combo (or an F1–F19 key)."
                        ))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        if isRecordingViewDesktop {
                            stopRecording()
                        } else {
                            startRecordingViewDesktop()
                        }
                    } label: {
                        Text(
                            isRecordingViewDesktop
                                ? loc.text(es: "Presioná teclas…", en: "Press keys…")
                                : current.displayString
                        )
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(isRecordingViewDesktop ? Color.white : Color.primary)
                        .frame(minWidth: 124)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isRecordingViewDesktop ? Color.accentColor : Color.primary.opacity(0.09))
                        )
                    }
                    .buttonStyle(.plain)

                    if !shortcutPrefs.isDefault(for: .viewDesktop) {
                        Button {
                            stopRecording()
                            shortcutPrefs.resetShortcut(for: .viewDesktop)
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(loc.text(es: "Restablecer a ⌘D", en: "Reset to ⌘D"))
                    }
                }

                // Presets rápidos
                VStack(alignment: .leading, spacing: 6) {
                    Text(loc.text(es: "Atajos sugeridos:", en: "Quick presets:"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        ForEach(viewDesktopPresets) { preset in
                            let isActive = current.isEnabled
                                && current.keyCode == preset.shortcut.keyCode
                                && current.command == preset.shortcut.command
                                && current.option == preset.shortcut.option
                                && current.control == preset.shortcut.control
                                && current.shift == preset.shortcut.shift

                            Button {
                                stopRecording()
                                shortcutPrefs.viewDesktopShortcut = preset.shortcut
                            } label: {
                                Text(preset.label)
                                    .font(.system(size: 11, weight: isActive ? .bold : .medium, design: .monospaced))
                                    .foregroundStyle(isActive ? Color.white : Color.primary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4.5)
                                    .background(
                                        Capsule()
                                            .fill(isActive ? Color.accentColor : Color.primary.opacity(0.07))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !conflicts.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(loc.text(
                            es: "Este atajo coincide con: \(conflicts.joined(separator: ", ")).",
                            en: "This shortcut conflicts with: \(conflicts.joined(separator: ", "))."
                        ))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                    }
                }

                if current.command && !current.option && !current.control && !current.shift && current.keyCode == 2 && current.isEnabled {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .padding(.top, 1)
                        Text(loc.text(
                            es: "Con ⌘D activo a nivel global, ⌘D mostrará el Escritorio en lugar de guardar marcadores en navegadores. Si preferís dejar ⌘D libre para el navegador, elegí ⌥D, ⌃⌘D o F11 arriba.",
                            en: "While ⌘D is active globally, ⌘D reveals the Desktop instead of browser bookmarking. If you prefer keeping ⌘D free for browsers, pick ⌥D, ⌃⌘D, or F11 above."
                        ))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

            // Tarjeta 2: Modo de comportamiento
            VStack(alignment: .leading, spacing: 10) {
                Text(loc.text(es: "Comportamiento al mostrar el Escritorio", en: "Show Desktop Behavior"))
                    .font(.system(size: 12.5, weight: .bold))

                ForEach(ViewDesktopBehavior.allCases) { mode in
                    let isSelected = shortcutPrefs.viewDesktopBehavior == mode
                    Button {
                        shortcutPrefs.viewDesktopBehavior = mode
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 14))
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                .padding(.top, 1)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(mode.localizedTitle(using: loc))
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text(mode.localizedDescription(using: loc))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(isSelected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func statusBadge(for shortcut: AppKeyShortcut) -> some View {
        if !shortcut.isEnabled {
            Text(loc.text(es: "Desactivado", en: "Disabled"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
        } else if toolsManager.isViewDesktopHotKeyRegistered {
            HStack(spacing: 4) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text(loc.text(
                    es: "Activo (\(shortcut.displayString))",
                    en: "Active (\(shortcut.displayString))"
                ))
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.green)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.green.opacity(0.14)))
        } else if !toolsManager.isRecordingSuspended {
            Text(loc.text(es: "Conflicto con otra app", en: "System shortcut conflict"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.orange.opacity(0.14)))
        }
    }

    // MARK: - Footer

    private var footerPane: some View {
        HStack(spacing: 10) {
            Button {
                toolsManager.triggerViewDesktop()
            } label: {
                Label(
                    loc.text(es: "Probar «Ver Escritorio» ahora", en: "Test \"View Desktop\" Now"),
                    systemImage: "play.fill"
                )
                .font(.system(size: 12))
            }
            .buttonStyle(.bordered)

            Button {
                stopRecording()
                AppShortcutsWindowController.shared.show(initialCategory: .all)
            } label: {
                Label(
                    loc.text(es: "Administrar todos los atajos…", en: "Manage All Shortcuts…"),
                    systemImage: "keyboard"
                )
                .font(.system(size: 12))
            }
            .buttonStyle(.bordered)

            Spacer()

            Button(loc.text(es: "Listo", en: "Done")) {
                stopRecording()
                onClose()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Grabador de Teclas

    private func startRecordingViewDesktop() {
        stopRecording()
        isRecordingViewDesktop = true
        ToolsShortcutManager.shared.setRecordingSuspended(true)
        ClipboardHistoryManager.shared.setRecordingSuspended(true)
        AltTabHotkeyMonitor.shared.isRecordingShortcut = true

        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let recorded = AppKeyShortcut.from(event: event, allowFunctionKeyWithoutModifiers: true)
            let consumed = MainActor.assumeIsolated { () -> Bool in
                if keyCode == 53 {
                    stopRecording()
                    return true
                }
                if let recorded {
                    shortcutPrefs.viewDesktopShortcut = recorded
                    stopRecording()
                    return true
                }
                return false
            }
            return consumed ? nil : event
        }
    }

    private func stopRecording() {
        if let monitor = recordingMonitor {
            NSEvent.removeMonitor(monitor)
            recordingMonitor = nil
        }
        isRecordingViewDesktop = false
        ToolsShortcutManager.shared.setRecordingSuspended(false)
        ClipboardHistoryManager.shared.setRecordingSuspended(false)
        AltTabHotkeyMonitor.shared.isRecordingShortcut = false
    }
}
