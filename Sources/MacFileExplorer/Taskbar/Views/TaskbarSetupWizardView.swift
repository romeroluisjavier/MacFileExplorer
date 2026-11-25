import AppKit
import SwiftUI

/// Controlador singleton del Asistente Inicial y de Permisos de la Barra de tareas.
@MainActor
public final class TaskbarSetupWizardWindowController {
    public static let shared = TaskbarSetupWizardWindowController()

    private var window: NSWindow?

    private init() {}

    public func show() {
        let loc = LocalizationManager.shared
        let title = loc.text(es: "Configuración inicial de la Barra de tareas", en: "Taskbar Setup & Permissions")
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let existing = window {
            existing.title = title
            existing.contentView = NSHostingView(rootView: TaskbarSetupWizardView(onFinish: { [weak self] in
                self?.close()
            }))
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let created = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        created.title = title
        created.isReleasedWhenClosed = false
        created.tabbingMode = .disallowed
        created.contentView = NSHostingView(rootView: TaskbarSetupWizardView(onFinish: { [weak self] in
            self?.close()
        }))
        created.center()
        created.makeKeyAndOrderFront(nil)
        self.window = created
    }

    public func close() {
        window?.close()
    }
}

private struct TaskbarSetupWizardView: View {
    let onFinish: () -> Void

    @Bindable private var prefs = TaskbarPreferences.shared
    @Bindable private var tracker = TaskbarWindowTracker.shared
    @Bindable private var thumbs = TaskbarThumbnailService.shared
    @Bindable private var loc = LocalizationManager.shared

    @ViewState private var pollingTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Cabecera
            HStack(spacing: 12) {
                Image(systemName: "dock.rectangle")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(loc.text(es: "Barra de tareas en MacFileExplorer", en: "Taskbar in MacFileExplorer"))
                        .font(.system(size: 17, weight: .bold))
                    Text(loc.text(
                        es: "Verificá los permisos opcionales y obligatorios. El Dock original de macOS permanece activo por defecto salvo que elijas cambiarlo.",
                        en: "Review required and optional permissions. The original macOS Dock stays active by default unless you choose to change it."
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Tarjeta 1: Accesibilidad (Requerido)
            wizardCard(
                badgeText: loc.text(es: "Requerido", en: "Required"),
                badgeColor: tracker.isAccessibilityGranted ? .green : .orange,
                icon: tracker.isAccessibilityGranted ? "checkmark.circle.fill" : "lock.shield",
                title: loc.text(es: "1. Permiso de Accesibilidad", en: "1. Accessibility Permission"),
                description: loc.text(
                    es: "Permite que MacFileExplorer vea cada ventana abierta, enfoque la ventana exacta que elijas, minimice, cierre con clic central y evite superposiciones.",
                    en: "Allows MacFileExplorer to list individual open windows, focus the exact window you click, minimize, middle-click close, and prevent overlaps."
                )
            ) {
                if tracker.isAccessibilityGranted {
                    Label(loc.text(es: "Permiso activo y listo", en: "Permission active and ready"), systemImage: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.green)
                } else {
                    Button {
                        tracker.checkAccessibilityPermission(prompt: true)
                        tracker.openAccessibilitySettings()
                    } label: {
                        Label(loc.text(es: "Abrir Ajustes de Accesibilidad", en: "Open Accessibility Settings"), systemImage: "gearshape")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            // Tarjeta 2: Grabación de pantalla (Opcional)
            wizardCard(
                badgeText: loc.text(es: "Opcional", en: "Optional"),
                badgeColor: thumbs.hasScreenRecordingPermission ? .green : .secondary,
                icon: thumbs.hasScreenRecordingPermission ? "checkmark.circle.fill" : "rectangle.on.rectangle.angled",
                title: loc.text(es: "2. Miniaturas en vivo (Grabación de pantalla)", en: "2. Live Hover Thumbnails (Screen Recording)"),
                description: loc.text(
                    es: "Opcional: solo se usa para tomar la miniatura en vivo al pasar el cursor sobre un botón. No se graba ni se envía nada. Si lo omitís, todo lo demás funciona igual.",
                    en: "Optional: used solely to render live hover thumbnails. Nothing is recorded or uploaded. Skip it if you prefer—everything else works identically."
                )
            ) {
                if thumbs.hasScreenRecordingPermission {
                    Label(loc.text(es: "Miniaturas en vivo habilitadas", en: "Live thumbnails enabled"), systemImage: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.green)
                } else {
                    Button {
                        thumbs.requestScreenRecordingPermission()
                    } label: {
                        Label(loc.text(es: "Habilitar miniaturas en vivo", en: "Enable Live Thumbnails"), systemImage: "photo")
                    }
                    .buttonStyle(.bordered)
                }
            }

            // Tarjeta 3: Dock de macOS (Opcional — Dock original activo por defecto)
            wizardCard(
                badgeText: loc.text(es: "Opcional", en: "Optional"),
                badgeColor: .blue,
                icon: "dock.rectangle",
                title: loc.text(es: "3. Dock de macOS (Original activo por defecto)", en: "3. macOS Dock (Original Active by Default)"),
                description: loc.text(
                    es: "Tu Dock original de macOS queda intacto y activo por defecto. Si deseás moverlo para que no compita con el borde inferior, podés elegirlo aquí o luego en Ajustes (con botón de emergencia siempre disponible).",
                    en: "Your original macOS Dock stays untouched and active by default. Optionally move it aside below or later in Settings (an emergency restore button is always available)."
                )
            ) {
                HStack(spacing: 8) {
                    dockQuickButton(
                        title: loc.text(es: "Dejar Dock original", en: "Keep Original Dock"),
                        mode: .unchanged
                    )
                    dockQuickButton(
                        title: loc.text(es: "Auto-ocultar izquierda", en: "Auto-Hide Left"),
                        mode: .autoHideLeft
                    )
                    dockQuickButton(
                        title: loc.text(es: "Auto-ocultar derecha", en: "Auto-Hide Right"),
                        mode: .autoHideRight
                    )
                }
            }

            Spacer(minLength: 0)

            Divider()

            HStack {
                Button {
                    TaskbarSettingsWindowController.shared.show()
                } label: {
                    Label(loc.text(es: "Más opciones…", en: "More Settings…"), systemImage: "slider.horizontal.3")
                }

                Spacer()

                Button {
                    prefs.hasCompletedSetup = true
                    TaskbarWindowTracker.shared.refreshNow()
                    TaskbarManager.shared.rebuildBarPanels()
                    onFinish()
                } label: {
                    Text(loc.text(es: "Listo", en: "Done"))
                        .frame(minWidth: 90)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .onAppear {
            startPermissionPolling()
        }
        .onDisappear {
            pollingTimer?.invalidate()
            pollingTimer = nil
        }
    }

    private func dockQuickButton(title: String, mode: TaskbarDockMode) -> some View {
        let isSelected = prefs.dockMode == mode
        return Button {
            TaskbarDockManager.shared.applyUserSelectedDockMode(mode)
        } label: {
            Text(title)
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.10), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func wizardCard<ActionContent: View>(
        badgeText: String,
        badgeColor: Color,
        icon: String,
        title: String,
        description: String,
        @ViewBuilder action: () -> ActionContent
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(badgeColor)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(badgeText)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(badgeColor.opacity(0.14), in: Capsule())
            }
            Text(description)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            action()
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.75)
        )
    }

    private func startPermissionPolling() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                let previouslyGranted = tracker.isAccessibilityGranted
                let nowGranted = tracker.checkAccessibilityPermission(prompt: false)
                thumbs.refreshPermissionStatus()
                if !previouslyGranted && nowGranted {
                    TaskbarWindowTracker.shared.refreshNow()
                }
            }
        }
    }
}
