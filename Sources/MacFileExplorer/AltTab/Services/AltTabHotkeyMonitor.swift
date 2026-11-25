import AppKit
import CoreGraphics
import Foundation
import Observation

/// Callback C de `CGEventTap` ejecutado en el `CFRunLoopGetMain()` (hilo principal)
/// para evaluar en sub-milisegundos la pulsación y liberación de modificadores (`⌥⇥`, `⌘⇥`, `⌥\``, etc.).
private func altTabCGEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags
    let shouldConsume = MainActor.assumeIsolated {
        AltTabHotkeyMonitor.shared.handleCGEvent(type: type, keyCode: keyCode, flags: flags)
    }
    return shouldConsume ? nil : Unmanaged.passUnretained(event)
}

/// Monitor global de teclado de bajísima latencia para **AltTab** mediante `CGEventTap`.
///
/// Características clave:
/// - Detecta combinación de modificador retenido + tecla (`⌥⇥`, `⌘⇥`, `⌃⇥`, `⌥\``, hasta 5 perfiles).
/// - Detecta la liberación exacta del modificador (`.flagsChanged`) para cambiar de ventana al instante.
/// - Permite `⇧` para retroceder, flechas, `Esc`, `Return`, `W`/`M`/`H`/`Q`/`F` y `/` para buscar.
/// - Se auto-reactiva inmediatamente si macOS desactiva el tap por timeout (`tapDisabledByTimeout`).
/// - Pasa intactos todos los eventos cuando el usuario graba un atajo en Configuración (`isRecordingShortcut`).
@MainActor
@Observable
public final class AltTabHotkeyMonitor {

    public static let shared = AltTabHotkeyMonitor()

    public private(set) var isTapActive: Bool = false

    /// Bandera activada mientras el grabador de atajos de `AltTabSettingsView` está capturando una tecla.
    public var isRecordingShortcut: Bool = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?
    private var isDesiredEnabled = false

    private init() {}

    public func start() {
        isDesiredEnabled = true
        installTapIfPossible()
        if !isTapActive {
            startRetryTimerIfNeeded()
        }
    }

    public func stop() {
        isDesiredEnabled = false
        retryTimer?.invalidate()
        retryTimer = nil
        teardownTap()
    }

    /// Re-verifica e instala el tap (útil cuando el usuario acaba de conceder Accesibilidad).
    public func retryInstallationIfNeeded() {
        guard isDesiredEnabled, !isTapActive else { return }
        installTapIfPossible()
    }

    private func installTapIfPossible() {
        guard eventTap == nil else {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                isTapActive = CGEvent.tapIsEnabled(tap: tap)
            }
            return
        }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: altTabCGEventTapCallback,
            userInfo: nil
        ) else {
            isTapActive = false
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        self.isTapActive = CGEvent.tapIsEnabled(tap: tap)

        if self.isTapActive {
            retryTimer?.invalidate()
            retryTimer = nil
        }
    }

    private func teardownTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isTapActive = false
    }

    private func startRetryTimerIfNeeded() {
        guard retryTimer == nil else { return }
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isDesiredEnabled else { return }
                if TaskbarWindowTracker.shared.checkAccessibilityPermission(prompt: false) {
                    self.installTapIfPossible()
                }
            }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
    }

    // MARK: - Procesamiento Síncrono en Sub-Milisegundos

    /// Devuelve `true` si el evento fue consumido por AltTab (no debe llegar a la app de fondo).
    fileprivate func handleCGEvent(
        type: CGEventType,
        keyCode: UInt16,
        flags: CGEventFlags
    ) -> Bool {
        // Recuperación automática inmediata ante timeout del sistema
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap, isDesiredEnabled {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return false
        }

        guard isDesiredEnabled, !isRecordingShortcut else {
            return false
        }

        let manager = AltTabManager.shared

        if type == .flagsChanged {
            if manager.isSwitcherOpen,
               !manager.isSearchActive,
               let profile = manager.activeProfile,
               profile.releaseBehavior == .switchOnModifierRelease,
               profile.areHoldModifiersReleased(currentFlags: flags) {
                manager.confirmSelection()
            }
            return false
        }

        guard type == .keyDown else {
            return false
        }

        // 1. Si el selector NO está abierto: verificar si dispara alguno de los perfiles configurados
        if !manager.isSwitcherOpen {
            for profile in AltTabPreferences.shared.shortcutProfiles {
                let result = profile.matchesKeyDown(keyCode: keyCode, flags: flags)
                if result.matched {
                    manager.openOrStep(profile: profile, reverse: result.isReverse)
                    return true // Consumir la tecla para que no llegue a la app de fondo
                }
            }
            return false
        }

        // 2. El selector YA está abierto
        // Si el usuario está escribiendo dentro de la barra de búsqueda integrada:
        if manager.isSearchActive {
            switch keyCode {
            case 53: // Escape
                manager.cancelSwitcher()
                return true
            case 36, 76: // Return / Enter
                manager.confirmSelection()
                return true
            case 125: // Down
                manager.navigateGrid(direction: .down)
                return true
            case 126: // Up
                manager.navigateGrid(direction: .up)
                return true
            case 48: // Tab dentro de búsqueda -> avanzar selección
                manager.stepSelection(reverse: flags.contains(.maskShift))
                return true
            default:
                // Permitir escritura libre en el TextField de búsqueda
                return false
            }
        }

        // Modo navegación rápido (con modificador retenido o selector abierto sin búsqueda activa)
        if let activeProfile = manager.activeProfile {
            let repeated = activeProfile.matchesKeyDown(keyCode: keyCode, flags: flags)
            if repeated.matched {
                manager.stepSelection(reverse: repeated.isReverse)
                return true
            }
        }

        // También permitir cambiar de perfil al vuelo si pulsa otro atajo configurado
        for profile in AltTabPreferences.shared.shortcutProfiles where profile.id != manager.activeProfile?.id {
            let match = profile.matchesKeyDown(keyCode: keyCode, flags: flags)
            if match.matched {
                manager.switchProfileWhileOpen(profile: profile, reverse: match.isReverse)
                return true
            }
        }

        switch keyCode {
        case 48: // Tab
            manager.stepSelection(reverse: flags.contains(.maskShift))
            return true
        case 53: // Escape
            manager.cancelSwitcher()
            return true
        case 36, 76, 49: // Return / Enter / Space
            manager.confirmSelection()
            return true
        case 123: // Left
            manager.navigateGrid(direction: .left)
            return true
        case 124: // Right
            manager.navigateGrid(direction: .right)
            return true
        case 125: // Down
            manager.navigateGrid(direction: .down)
            return true
        case 126: // Up
            manager.navigateGrid(direction: .up)
            return true
        case 13: // W -> Cerrar ventana seleccionada
            manager.closeSelectedWindow()
            return true
        case 46: // M -> Minimizar / Restaurar ventana seleccionada
            manager.minimizeSelectedWindow()
            return true
        case 4: // H -> Ocultar / Mostrar app
            manager.hideSelectedWindowApp()
            return true
        case 12: // Q -> Salir de app
            manager.quitSelectedWindowApp()
            return true
        case 3: // F -> Pantalla completa
            manager.toggleFullScreenSelectedWindow()
            return true
        case 44: // '/' -> Activar búsqueda instantánea
            manager.activateInlineSearch()
            return true
        default:
            return false
        }
    }
}
