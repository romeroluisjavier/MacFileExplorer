import AppKit
import Carbon
import CoreGraphics
import Darwin
import Foundation
import Observation

/// Firma Carbon dedicada para atajos globales de Herramientas (`'MFET'`).
private let toolsCarbonHotKeySignature: OSType = 0x4D464554

/// Callback C para `RegisterEventHotKey` de Carbon que reenvía los atajos globales de Herramientas
/// (ej. `⌘D` para «Ver Escritorio») al `@MainActor`, cediendo cualquier evento que no pertenezca a `'MFET'`.
private func toolsCarbonHotKeyHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == toolsCarbonHotKeySignature else {
        return OSStatus(eventNotHandledErr)
    }
    let id = hotKeyID.id
    Task { @MainActor in
        ToolsShortcutManager.shared.handleCarbonHotKeyTriggered(id: id)
    }
    return noErr
}

/// Puente dinámico seguro hacia `CoreDockSendNotification` (HIServices / ApplicationServices)
/// para disparar el «Mostrar Escritorio» nativo de macOS sin requerir permisos extra.
private enum CoreDockDesktopBridge {
    private typealias CoreDockSendNotificationFn = @convention(c) (CFString, UnsafeMutableRawPointer?) -> OSStatus

    private static let sendNotificationFn: CoreDockSendNotificationFn? = {
        let candidatePaths = [
            "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices",
            "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
        ]
        for path in candidatePaths {
            if let handle = dlopen(path, RTLD_LAZY),
               let sym = dlsym(handle, "CoreDockSendNotification") {
                return unsafeBitCast(sym, to: CoreDockSendNotificationFn.self)
            }
        }
        return nil
    }()

    /// Envía `"com.apple.showdesktop.awake"` al Dock/Mission Control de macOS.
    /// Devuelve `true` si el símbolo existe y respondió `noErr`.
    static func toggleNativeShowDesktop() -> Bool {
        guard let fn = sendNotificationFn else { return false }
        let status = fn("com.apple.showdesktop.awake" as CFString, nil)
        return status == noErr
    }
}

/// Referencia débil a ventanas regulares propias de `MacFileExplorer` para poder ocultarlas/restaurarlas
/// sin afectar los paneles de la Barra de tareas ni el icono de menú.
@MainActor
private final class WeakNSWindowRef {
    weak var window: NSWindow?
    init(_ window: NSWindow) {
        self.window = window
    }
}

/// Administrador global de atajos y acciones del submenú **Archivo → Herramientas (Tools)**.
///
/// Primera herramienta integrada: **View Desktop Shortcut** (por defecto `⌘D`), que funciona de forma
/// global en todo macOS mediante Carbon `RegisterEventHotKey` (sin necesidad de permisos de Accesibilidad).
@MainActor
@Observable
public final class ToolsShortcutManager {

    public static let shared = ToolsShortcutManager()

    /// Indica si el atajo global de «Ver Escritorio» está registrado activamente en el sistema.
    public private(set) var isViewDesktopHotKeyRegistered: Bool = false

    /// Código `OSStatus` del último intento de registro en Carbon (`0` = `noErr`).
    public private(set) var lastViewDesktopRegistrationStatus: OSStatus = noErr

    /// Indica si un grabador de atajos está capturando teclas en este momento (suspende hotkeys globales).
    public private(set) var isRecordingSuspended: Bool = false

    private var isInstalled = false
    private var carbonEventHandlerRef: EventHandlerRef?
    private var viewDesktopHotKeyRef: EventHotKeyRef?

    // Estado para el modo «Ocultar ventanas y enfocar Escritorio (Estilo Win+D)»
    private var isDesktopShownByHideMode = false
    private var hiddenOtherAppPIDs: [pid_t] = []
    private var hiddenOwnWindows: [WeakNSWindowRef] = []
    private var previousFrontmostPID: pid_t?
    private var lastTriggerTimestamp: TimeInterval = 0

    private init() {}

    // MARK: - Ciclo de Vida y Registro Global

    public func installIfNeeded() {
        guard !isInstalled else { return }
        isInstalled = true

        AppShortcutPreferences.shared.onViewDesktopShortcutChanged = { [weak self] in
            self?.syncGlobalHotKeys()
        }
        syncGlobalHotKeys()
    }

    /// Suspende temporalmente los atajos globales mientras el usuario graba una nueva combinación en cualquier panel.
    public func setRecordingSuspended(_ suspended: Bool) {
        guard isRecordingSuspended != suspended else { return }
        isRecordingSuspended = suspended
        if suspended {
            unregisterGlobalHotKeys()
        } else {
            syncGlobalHotKeys()
        }
    }

    /// Registra o actualiza los atajos globales de Herramientas en macOS mediante Carbon `RegisterEventHotKey`.
    public func syncGlobalHotKeys() {
        unregisterGlobalHotKeys()

        guard !isRecordingSuspended else { return }

        let shortcut = AppShortcutPreferences.shared.viewDesktopShortcut
        guard shortcut.isEnabled else {
            isViewDesktopHotKeyRegistered = false
            lastViewDesktopRegistrationStatus = noErr
            return
        }

        if carbonEventHandlerRef == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            InstallEventHandler(
                GetApplicationEventTarget(),
                toolsCarbonHotKeyHandler,
                1,
                &eventType,
                nil,
                &carbonEventHandlerRef
            )
        }

        let hotKeyID = EventHotKeyID(signature: toolsCarbonHotKeySignature, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        lastViewDesktopRegistrationStatus = status
        if status == noErr, let ref {
            viewDesktopHotKeyRef = ref
            isViewDesktopHotKeyRegistered = true
        } else {
            viewDesktopHotKeyRef = nil
            isViewDesktopHotKeyRegistered = false
        }
    }

    public func unregisterGlobalHotKeys() {
        if let existing = viewDesktopHotKeyRef {
            UnregisterEventHotKey(existing)
            viewDesktopHotKeyRef = nil
        }
        isViewDesktopHotKeyRegistered = false
    }

    fileprivate func handleCarbonHotKeyTriggered(id: UInt32) {
        guard !isRecordingSuspended else { return }
        switch id {
        case 1:
            guard AppShortcutPreferences.shared.isViewDesktopShortcutEnabled else { return }
            triggerViewDesktop()
        default:
            break
        }
    }

    // MARK: - Acción «Ver Escritorio» (View Desktop)

    /// Muestra / enfoca el Escritorio de macOS (o restaura las ventanas previas al volver a activarse).
    public func triggerViewDesktop() {
        // Evitar doble disparo por rebote de tecla rápido (< 140 ms)
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTriggerTimestamp >= 0.14 else { return }
        lastTriggerTimestamp = now

        // Cerrar el Menú Inicio de la Barra de tareas si estaba desplegado
        TaskbarStartMenuController.shared.close()

        switch AppShortcutPreferences.shared.viewDesktopBehavior {
        case .nativeShowDesktop:
            if !CoreDockDesktopBridge.toggleNativeShowDesktop() {
                toggleHideWindowsAndFocusDesktop()
            }
        case .hideWindowsFocusDesktop:
            toggleHideWindowsAndFocusDesktop()
        }
    }

    /// Modo estilo Windows `Win+D`: oculta todas las ventanas abiertas (dejando la Barra de tareas intacta)
    /// y enfoca el Escritorio; al pulsar por segunda vez restaura exactamente las ventanas que ocultó.
    private func toggleHideWindowsAndFocusDesktop() {
        let myPID = ProcessInfo.processInfo.processIdentifier

        // Si el usuario ya restauró o abrió manualmente otra app mientras estaba en el Escritorio,
        // reiniciar el estado para que esta pulsación vuelva a mostrar el Escritorio.
        if isDesktopShownByHideMode {
            let frontApp = NSWorkspace.shared.frontmostApplication
            let hasVisibleOwnNormalWindow = NSApp.windows.contains { win in
                isRegularHideableOwnWindow(win)
            }
            let frontIsFinder = frontApp?.bundleIdentifier == "com.apple.finder"
            let frontIsSelfWithNoNormalWindow = (frontApp?.processIdentifier == myPID && !hasVisibleOwnNormalWindow)

            if frontApp != nil && !frontIsFinder && !frontIsSelfWithNoNormalWindow {
                clearHideModeState()
            }
        }

        if isDesktopShownByHideMode {
            restoreWindowsFromHideMode()
        } else {
            hideWindowsAndFocusDesktop()
        }
    }

    private func hideWindowsAndFocusDesktop() {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let workspace = NSWorkspace.shared
        previousFrontmostPID = workspace.frontmostApplication?.processIdentifier
        hiddenOtherAppPIDs = []
        hiddenOwnWindows = []

        var finderApp: NSRunningApplication?
        var finderHasVisibleWindows = false

        for app in workspace.runningApplications {
            guard app.activationPolicy == .regular,
                  !app.isTerminated,
                  app.processIdentifier != myPID else {
                continue
            }

            if app.bundleIdentifier == "com.apple.finder" {
                finderApp = app
                finderHasVisibleWindows = applicationHasVisibleNormalWindows(pid: app.processIdentifier)
                if finderHasVisibleWindows && !app.isHidden {
                    if app.hide() {
                        hiddenOtherAppPIDs.append(app.processIdentifier)
                    }
                }
                continue
            }

            if !app.isHidden {
                if app.hide() {
                    hiddenOtherAppPIDs.append(app.processIdentifier)
                }
            }
        }

        // Ocultar únicamente ventanas regulares de MacFileExplorer (nunca la Barra de tareas ni paneles de sistema)
        for window in NSApp.windows where isRegularHideableOwnWindow(window) {
            hiddenOwnWindows.append(WeakNSWindowRef(window))
            window.orderOut(nil)
        }

        // Si Finder no tiene ventanas abiertas, activarlo para que el Escritorio reciba el foco de teclado real
        if let finderApp, !finderHasVisibleWindows {
            finderApp.activate(options: [])
        }

        isDesktopShownByHideMode = true
    }

    private func restoreWindowsFromHideMode() {
        let pidsToRestore = hiddenOtherAppPIDs
        let ownWindowsToRestore = hiddenOwnWindows
        let prevFrontPID = previousFrontmostPID
        clearHideModeState()

        for pid in pidsToRestore {
            if let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated {
                app.unhide()
            }
        }

        for ref in ownWindowsToRestore {
            if let window = ref.window {
                window.orderFront(nil)
            }
        }

        if let prevFrontPID,
           let prevApp = NSRunningApplication(processIdentifier: prevFrontPID),
           !prevApp.isTerminated {
            prevApp.activate(options: [])
        }
    }

    private func clearHideModeState() {
        isDesktopShownByHideMode = false
        hiddenOtherAppPIDs = []
        hiddenOwnWindows = []
        previousFrontmostPID = nil
    }

    private func isRegularHideableOwnWindow(_ window: NSWindow) -> Bool {
        guard window.isVisible,
              !window.isMiniaturized,
              !(window is NSPanel),
              window.level == .normal else {
            return false
        }
        return true
    }

    private func applicationHasVisibleNormalWindows(pid: pid_t) -> Bool {
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }

        for info in infoList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid else {
                continue
            }
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { continue }
            if let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
               let height = boundsDict["Height"] as? CGFloat,
               let width = boundsDict["Width"] as? CGFloat,
               height > 44, width > 80 {
                return true
            }
        }
        return false
    }
}
