import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import Darwin
import Foundation
import Observation

// MARK: - Puentes Dinámicos Seguros (`_AXUIElementGetWindow` y Metadatos de Spaces CGS)

private typealias AXUIElementGetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
private typealias CGSMainConnectionIDFn = @convention(c) () -> Int32
private typealias CGSCopyManagedDisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
private typealias CGSCopySpacesForWindowsFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

private enum AXPrivateBridge {
    private static let getWindowSymbol: AXUIElementGetWindowFn? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let sym = dlsym(handle, "_AXUIElementGetWindow") else {
            return nil
        }
        return unsafeBitCast(sym, to: AXUIElementGetWindowFn.self)
    }()

    static func windowID(for element: AXUIElement) -> CGWindowID? {
        guard let fn = getWindowSymbol else { return nil }
        var windowID: CGWindowID = 0
        let err = fn(element, &windowID)
        guard err == .success, windowID != 0 else { return nil }
        return windowID
    }
}

private typealias GetProcessForPIDFn = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
private typealias SLPSSetFrontProcessWithOptionsFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
private typealias SLPSPostEventRecordToFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError

/// Puente dinámico seguro hacia `SkyLight` (`_SLPSSetFrontProcessWithOptions` + `SLPSPostEventRecordTo`)
/// para enfocar y elevar **únicamente** la ventana específica (`CGWindowID`) en su monitor actual,
/// sin traer al frente otras ventanas de la misma app (ej. Chrome en dos monitores) ni moverla de pantalla.
private enum SkyLightSingleWindowFocusBridge {
    private static let kCPSUserGenerated: UInt32 = 0x200

    private struct Symbols: @unchecked Sendable {
        let getProcessForPID: GetProcessForPIDFn
        let setFrontProcessWithOptions: SLPSSetFrontProcessWithOptionsFn
        let postEventRecordTo: SLPSPostEventRecordToFn
    }

    private static let symbols: Symbols? = {
        guard let sl = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let appSvc = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
              let sGetProc = dlsym(appSvc, "GetProcessForPID"),
              let sSetFront = dlsym(sl, "_SLPSSetFrontProcessWithOptions"),
              let sPostEvent = dlsym(sl, "SLPSPostEventRecordTo") else {
            return nil
        }
        return Symbols(
            getProcessForPID: unsafeBitCast(sGetProc, to: GetProcessForPIDFn.self),
            setFrontProcessWithOptions: unsafeBitCast(sSetFront, to: SLPSSetFrontProcessWithOptionsFn.self),
            postEventRecordTo: unsafeBitCast(sPostEvent, to: SLPSPostEventRecordToFn.self)
        )
    }()

    /// Eleva y da foco de teclado únicamente a `windowID` de `pid`, dejando intactas las demás ventanas
    /// de esa aplicación en cualquier otro monitor o detrás de otras apps.
    @discardableResult
    static func focusSingleWindow(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard windowID != 0, let symbols else { return false }
        var psn = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: 0)
        guard symbols.getProcessForPID(pid, &psn) == noErr else { return false }

        let frontErr = symbols.setFrontProcessWithOptions(&psn, windowID, kCPSUserGenerated)
        guard frontErr == .success else { return false }

        var bytes1 = [UInt8](repeating: 0, count: 0xf8)
        bytes1[0x04] = 0xf8
        bytes1[0x08] = 0x01
        bytes1[0x3a] = 0x10

        var bytes2 = [UInt8](repeating: 0, count: 0xf8)
        bytes2[0x04] = 0xf8
        bytes2[0x08] = 0x02
        bytes2[0x3a] = 0x10

        var widLE = windowID.littleEndian
        withUnsafeBytes(of: &widLE) { raw in
            for i in 0..<4 {
                bytes1[0x3c + i] = raw[i]
                bytes2[0x3c + i] = raw[i]
            }
        }
        for i in 0x20..<0x30 {
            bytes1[i] = 0xff
            bytes2[i] = 0xff
        }

        _ = bytes1.withUnsafeMutableBufferPointer { ptr in
            symbols.postEventRecordTo(&psn, ptr.baseAddress!)
        }
        _ = bytes2.withUnsafeMutableBufferPointer { ptr in
            symbols.postEventRecordTo(&psn, ptr.baseAddress!)
        }
        return true
    }
}

/// Resuelve en < 0.5 ms el número de escritorio virtual (`Space 1, 2, 3…`) y si pertenece al Space activo
/// mediante carga dinámica segura (`dlsym`), degradando limpiamente si un símbolo no estuviera disponible.
private enum TaskbarSpaceMetadataResolver {
    private struct Symbols {
        let mainConnection: CGSMainConnectionIDFn
        let copyManagedDisplaySpaces: CGSCopyManagedDisplaySpacesFn
        let copySpacesForWindows: CGSCopySpacesForWindowsFn
    }

    private static let symbols: Symbols? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let s1 = dlsym(handle, "CGSMainConnectionID"),
              let s2 = dlsym(handle, "CGSCopyManagedDisplaySpaces"),
              let s3 = dlsym(handle, "CGSCopySpacesForWindows") else {
            return nil
        }
        return Symbols(
            mainConnection: unsafeBitCast(s1, to: CGSMainConnectionIDFn.self),
            copyManagedDisplaySpaces: unsafeBitCast(s2, to: CGSCopyManagedDisplaySpacesFn.self),
            copySpacesForWindows: unsafeBitCast(s3, to: CGSCopySpacesForWindowsFn.self)
        )
    }()

    struct Snapshot: Sendable {
        let spaceNumberBySpaceID: [UInt64: Int]
        let activeSpaceIDs: Set<UInt64>
        let totalDesktopSpaces: Int
    }

    static func captureDisplaySpacesSnapshot() -> Snapshot? {
        guard let symbols else { return nil }
        let conn = symbols.mainConnection()
        guard let cfDisplays = symbols.copyManagedDisplaySpaces(conn)?.takeRetainedValue(),
              let displays = cfDisplays as? [[String: Any]] else {
            return nil
        }

        var spaceNumberByID: [UInt64: Int] = [:]
        var activeIDs: Set<UInt64> = []
        var desktopIndex = 1

        for display in displays {
            if let current = display["Current Space"] as? [String: Any],
               let curID = (current["id64"] as? NSNumber)?.uint64Value {
                activeIDs.insert(curID)
            }
            if let spaces = display["Spaces"] as? [[String: Any]] {
                for space in spaces {
                    guard let sid = (space["id64"] as? NSNumber)?.uint64Value else { continue }
                    let spaceType = (space["type"] as? NSNumber)?.intValue ?? 0
                    // type == 0 corresponde a escritorios virtuales normales (Desktop Spaces)
                    if spaceType == 0 {
                        spaceNumberByID[sid] = desktopIndex
                        desktopIndex += 1
                    }
                }
            }
        }

        return Snapshot(
            spaceNumberBySpaceID: spaceNumberByID,
            activeSpaceIDs: activeIDs,
            totalDesktopSpaces: max(1, desktopIndex - 1)
        )
    }

    static func resolveSpaceInfo(
        for windowID: CGWindowID,
        snapshot: Snapshot?
    ) -> (spaceIndex: Int?, isOnActiveSpace: Bool, hasAnySpace: Bool)? {
        guard windowID != 0, let symbols, let snapshot else { return nil }
        let conn = symbols.mainConnection()
        let arr = [NSNumber(value: windowID)] as CFArray
        // 0x7 = kCGSAllSpacesMask (incluye Spaces visibles y otros Spaces)
        guard let cfSpaces = symbols.copySpacesForWindows(conn, 0x7, arr)?.takeRetainedValue(),
              let spaceIDs = (cfSpaces as? [NSNumber])?.map(\.uint64Value) else {
            return nil
        }

        if spaceIDs.isEmpty {
            // Pestañas inactivas de NSWindowTabGroup (Fork, Finder, Terminal, etc.) y ventanas fantasma devuelven []
            return (nil, false, false)
        }

        let isActive = spaceIDs.contains { snapshot.activeSpaceIDs.contains($0) }
        if let activeMatched = spaceIDs.first(where: { snapshot.activeSpaceIDs.contains($0) && snapshot.spaceNumberBySpaceID[$0] != nil }),
           let number = snapshot.spaceNumberBySpaceID[activeMatched] {
            return (number, true, true)
        }
        if let anyMapped = spaceIDs.compactMap({ snapshot.spaceNumberBySpaceID[$0] }).first {
            return (anyMapped, isActive, true)
        }
        return (nil, isActive, true)
    }
}

/// Callback C para `AXObserver` que reenvía eventos de ventanas al `@MainActor`.
private func taskbarAXObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    let notifName = notification as String
    let isGeometryChange = (notifName == (kAXWindowMovedNotification as String)) ||
        (notifName == (kAXWindowResizedNotification as String)) ||
        (notifName == (kAXWindowCreatedNotification as String)) ||
        (notifName == (kAXWindowDeminiaturizedNotification as String))
    let isHighFrequency = (notifName == (kAXWindowMovedNotification as String)) ||
        (notifName == (kAXWindowResizedNotification as String)) ||
        (notifName == (kAXTitleChangedNotification as String))
    let elementBox = isGeometryChange ? AXElementBox(element) : nil
    Task { @MainActor in
        TaskbarWindowTracker.shared.handleAXEventNotification(
            elementBox: elementBox,
            isGeometryChange: isGeometryChange,
            isHighFrequency: isHighFrequency
        )
    }
}

// MARK: - Estructuras de Transferencia entre Hilo Principal y Cola de Escaneo AX

private struct CGWindowSnapshotInfo: Sendable {
    let windowID: CGWindowID
    let pid: pid_t
    let layer: Int
    let bounds: CGRect
    let alpha: Double
    let isOnScreen: Bool
    let title: String
}

private struct RunningAppSnapshot: Sendable {
    let pid: pid_t
    let bundleIdentifier: String
    let appName: String
    let bundleURL: URL?
    let isHidden: Bool
}

private struct TaskbarScanContext: Sendable {
    let isTrusted: Bool
    let screens: [TaskbarScreenDescriptor]
    let ownedWindowNumbers: Set<Int>
    let showNotificationBadges: Bool
    let shouldRefreshBadges: Bool
    let cachedBadges: [String: String]
    let frontmostPID: pid_t
    let dockPID: pid_t?
    let runningApps: [RunningAppSnapshot]
    let recentlyInteractedIDs: Set<String>
}

private final class AXElementBox: @unchecked Sendable {
    let element: AXUIElement
    init(_ element: AXUIElement) {
        self.element = element
    }
}

private final class WeakNSWindowBox {
    weak var window: NSWindow?
    init(_ window: NSWindow) {
        self.window = window
    }
}

private struct TaskbarScanResult: Sendable {
    let discoveredAllSpaces: [TaskbarWindowItem]
    let liveIDsAllSpaces: Set<String>
    let axElementsByID: [String: AXElementBox]
    let axTimedOutPIDs: Set<pid_t>
    let fullScreenDisplayIDs: Set<String>
    let updatedBadges: [String: String]?
    let spaceSnapshot: TaskbarSpaceMetadataResolver.Snapshot?
}

// MARK: - Motor Compartido de Ventanas, Monitores, Spaces, MRU y Control AX (Taskbar + AltTab)

@MainActor
@Observable
public final class TaskbarWindowTracker {

    public static let shared = TaskbarWindowTracker()

    /// Lista filtrada y ordenada para la **Barra de tareas (`Taskbar`)** (respeta `syncWithActiveSpace`, exclusiones de Taskbar y orden manual).
    public private(set) var windows: [TaskbarWindowItem] = []

    /// Lista completa de TODAS las ventanas vivas en todos los Spaces (activas, minimizadas, ocultas y en otros Spaces),
    /// ordenadas por uso más reciente (**MRU**) para **AltTab** sin duplicar escaneos ni observadores.
    public private(set) var allWindowsAcrossSpaces: [TaskbarWindowItem] = []

    /// Monitores conectados actualmente (hasta 5 monitores soportados).
    public private(set) var connectedScreens: [TaskbarScreenDescriptor] = []

    /// Monitores que tienen actualmente una ventana en pantalla completa nativa.
    public private(set) var fullScreenDisplayIDs: Set<String> = []

    /// Badges de notificación por nombre/URL de aplicación leídos del Dock (si Accesibilidad está activa).
    public private(set) var badgeByAppKey: [String: String] = [:]

    /// Estado en vivo del permiso de Accesibilidad.
    public private(set) var isAccessibilityGranted: Bool = AXIsProcessTrusted()

    /// Consumidores activos (`taskbar`, `altTab`). El monitoreo corre mientras al menos uno esté activo.
    public private(set) var activeConsumers: Set<WindowServiceConsumer> = []

    /// Callback invocado cuando cambia la geometría de ventanas tras completar escaneo (para `TaskbarOverlapResizer`).
    public var onWindowGeometryPotentiallyChanged: (() -> Void)?

    /// Ruta rápida directa: invocado al instante con el `AXUIElement` exacto que acaba de cambiar de tamaño/posición.
    public var onAXWindowGeometryChanged: ((AXUIElement) -> Void)?

    /// Ruta rápida local: invocado al instante cuando una ventana propia de `MacFileExplorer` cambia de tamaño/posición.
    public var onLocalWindowGeometryChanged: ((NSWindow) -> Void)?

    /// Marca si debemos disparar un barrido de superposición justo al terminar el próximo escaneo (evita leer frames viejos).
    private var pendingGeometryCheckAfterScan = false

    /// Cachés O(1) de aplicaciones actualmente en ejecución para evitar `NSWorkspace.runningApplications` y `stat()` en SwiftUI `body`.
    public private(set) var runningBundleIDsLowercased: Set<String> = []
    public private(set) var runningBundlePathsLowercased: Set<String> = []

    /// Cola serial dedicada en núcleos de eficiencia (`.utility`) para todas las llamadas IPC de Accessibility, CGS y `CGWindowList`,
    /// manteniendo el hilo principal libre y evitando despertar los núcleos P de Apple Silicon en sondeos periódicos.
    private let scanQueue = DispatchQueue(label: "com.macfileexplorer.taskbar.window-scan", qos: .utility)
    private let actionQueue = DispatchQueue(label: "com.macfileexplorer.taskbar.window-action", qos: .userInitiated)

    private var ownedWindowProviders: [String: @MainActor () -> Set<Int>] = [:]
    private var orderEngine = TaskbarWindowOrderEngine()
    private var axElementsByWindowItemID: [String: AXUIElement] = [:]
    private var localWindowsByItemID: [String: WeakNSWindowBox] = [:]
    private var axObserversByPID: [pid_t: AXObserver] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private var localWindowObservers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?
    private var fallbackRefreshTimer: Timer?
    private var lastBadgeFetchDate: Date = .distantPast
    private var pendingRefreshWorkItem: DispatchWorkItem?
    private var pendingGeometryWorkItem: DispatchWorkItem?
    private var isMonitoring = false
    private var isScanInFlight = false
    private var hasPendingRescan = false

    // Seguimiento MRU (Most Recently Used) + pre-calentamiento de miniaturas al perder foco
    private var focusSequenceCounter: UInt64 = 1
    private var focusRequestToken: UInt64 = 0
    private var lastFocusedOrderByItemID: [String: UInt64] = [:]
    private var lastFocusedWindowItemID: String?
    private var lastFocusedCGWindowID: CGWindowID = 0
    /// Ventanas recién interactuadas (minimizar/restaurar) protegidas brevemente contra descartes transitorios.
    private var recentlyInteractedUntilByID: [String: TimeInterval] = [:]
    /// Caché por PID del último escaneo externo válido para no parpadear si una app tarda >250ms en responder AX al restaurarse.
    private var lastExternalItemsByPID: [pid_t: [TaskbarWindowItem]] = [:]

    private init() {
        refreshConnectedScreens()
    }

    // MARK: - Registro de Proveedores de Ventanas Internas Excluidas

    public func registerOwnedWindowNumbersProvider(
        key: String,
        provider: @escaping @MainActor () -> Set<Int>
    ) {
        ownedWindowProviders[key] = provider
    }

    private func collectAllOwnedWindowNumbers() -> Set<Int> {
        var combined: Set<Int> = []
        for provider in ownedWindowProviders.values {
            combined.formUnion(provider())
        }
        return combined
    }

    // MARK: - Permisos de Accesibilidad

    @discardableResult
    public func checkAccessibilityPermission(prompt: Bool = false) -> Bool {
        let trusted: Bool
        if prompt {
            let promptKey = "AXTrustedCheckOptionPrompt" as CFString
            let options = [promptKey: kCFBooleanTrue!] as CFDictionary
            trusted = AXIsProcessTrustedWithOptions(options)
        } else {
            trusted = AXIsProcessTrusted()
        }
        isAccessibilityGranted = trusted
        return trusted
    }

    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Ciclo de Vida del Monitoreo (Ref-Counted entre Taskbar y AltTab)

    public func acquireMonitoring(for consumer: WindowServiceConsumer) {
        activeConsumers.insert(consumer)
        if !isMonitoring {
            beginMonitoringInternal()
        } else {
            refreshNow()
        }
    }

    public func releaseMonitoring(for consumer: WindowServiceConsumer) {
        activeConsumers.remove(consumer)
        if activeConsumers.isEmpty {
            endMonitoringInternal()
        }
    }

    /// Retrocompatibilidad directa para `TaskbarManager`.
    public func startMonitoring() {
        acquireMonitoring(for: .taskbar)
    }

    /// Retrocompatibilidad directa para `TaskbarManager`.
    public func stopMonitoring() {
        releaseMonitoring(for: .taskbar)
    }

    public func stopAllMonitoringForTermination() {
        activeConsumers.removeAll()
        endMonitoringInternal()
    }

    private func beginMonitoringInternal() {
        guard !isMonitoring else { return }
        isMonitoring = true
        refreshConnectedScreens()
        installWorkspaceObservers()
        installAXObserversForRunningApps()
        startFallbackTimer()
        refreshNow()
    }

    private func endMonitoringInternal() {
        guard isMonitoring else { return }
        isMonitoring = false
        hasPendingRescan = false

        pendingRefreshWorkItem?.cancel()
        pendingRefreshWorkItem = nil
        pendingGeometryWorkItem?.cancel()
        pendingGeometryWorkItem = nil

        fallbackRefreshTimer?.invalidate()
        fallbackRefreshTimer = nil

        let wsCenter = NSWorkspace.shared.notificationCenter
        for token in workspaceObservers {
            wsCenter.removeObserver(token)
        }
        workspaceObservers.removeAll()

        for token in localWindowObservers {
            NotificationCenter.default.removeObserver(token)
        }
        localWindowObservers.removeAll()

        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }

        removeAllAXObservers()
        axElementsByWindowItemID.removeAll()
        localWindowsByItemID.removeAll()
        lastExternalItemsByPID.removeAll()
        recentlyInteractedUntilByID.removeAll()
        windows.removeAll()
        allWindowsAcrossSpaces.removeAll()
        fullScreenDisplayIDs.removeAll()
    }

    /// Reconstruye observadores AX y refresca pantallas/ventanas tras despertar de reposo o desbloquear la Mac.
    public func recoverAfterSystemWake() {
        guard isMonitoring else { return }
        removeAllAXObservers()
        refreshConnectedScreens()
        _ = checkAccessibilityPermission(prompt: false)
        installAXObserversForRunningApps()
        startFallbackTimer()
        refreshNow()
        TaskbarManager.shared.handleScreensChanged()
    }

    // MARK: - Monitores Conectados

    public func refreshConnectedScreens() {
        let nsScreens = Array(NSScreen.screens.prefix(5))
        guard let primary = nsScreens.first else {
            connectedScreens = []
            return
        }
        let primaryHeight = primary.frame.height
        connectedScreens = nsScreens.enumerated().map { index, screen in
            let displayID = Self.displayID(for: screen)
            let stableID = Self.stableDisplayIdentifier(for: displayID, fallbackIndex: index)
            let frameCocoa = screen.frame
            let frameAX = TaskbarGeometry.cocoaRectToAX(frameCocoa, primaryScreenHeight: primaryHeight)
            return TaskbarScreenDescriptor(
                id: stableID,
                displayID: displayID,
                localizedName: screen.localizedName,
                frameCocoa: frameCocoa,
                frameAX: frameAX,
                isMain: index == 0
            )
        }
    }

    public static func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return CGDirectDisplayID(number.uint32Value)
        }
        return CGMainDisplayID()
    }

    public static func stableDisplayIdentifier(for displayID: CGDirectDisplayID, fallbackIndex: Int) -> String {
        if let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
           let uuidString = CFUUIDCreateString(nil, cfUUID) as String? {
            return uuidString
        }
        return "display-\(displayID)-\(fallbackIndex)"
    }

    /// Identificador del monitor donde se encuentra actualmente el puntero del ratón.
    public func screenDescriptorUnderMouse() -> TaskbarScreenDescriptor? {
        if connectedScreens.isEmpty { refreshConnectedScreens() }
        let mouseLoc = NSEvent.mouseLocation
        return connectedScreens.first(where: { $0.frameCocoa.contains(mouseLoc) }) ?? connectedScreens.first
    }

    // MARK: - Observadores del Sistema y AXObserver

    private func installWorkspaceObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        let watchedNames: [NSNotification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ]

        for name in watchedNames {
            let token = wsCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let notifName = notification.name
                Task { @MainActor [weak self] in
                    guard let self else { return }

                    if notifName == NSWorkspace.didWakeNotification ||
                       notifName == NSWorkspace.screensDidWakeNotification ||
                       notifName == NSWorkspace.sessionDidBecomeActiveNotification {
                        self.recoverAfterSystemWake()
                        return
                    }

                    if notifName == NSWorkspace.didLaunchApplicationNotification, let app {
                        self.installAXObserverIfNeeded(for: app)
                        if let url = app.bundleURL, app.activationPolicy == .regular {
                            TaskbarPreferences.shared.recordRecentApp(bundleURL: url)
                        }
                    } else if notifName == NSWorkspace.didTerminateApplicationNotification, let app {
                        self.removeAXObserver(for: app.processIdentifier)
                    } else if notifName == NSWorkspace.didActivateApplicationNotification, let app {
                        self.installAXObserverIfNeeded(for: app)
                        if let url = app.bundleURL, app.activationPolicy == .regular {
                            TaskbarPreferences.shared.recordRecentApp(bundleURL: url)
                        }
                    }

                    self.scheduleCoalescedRefresh(delay: notifName == NSWorkspace.activeSpaceDidChangeNotification ? 0.04 : 0.03)
                    if notifName == NSWorkspace.didActivateApplicationNotification || notifName == NSWorkspace.didLaunchApplicationNotification {
                        self.pendingGeometryCheckAfterScan = true
                        self.scheduleGeometryCheck()
                    }
                }
            }
            workspaceObservers.append(token)
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshConnectedScreens()
                self.refreshNow()
                TaskbarManager.shared.handleScreensChanged()
            }
        }

        // Observar ventanas propias de MacFileExplorer nativamente vía NSWindow (nunca usar AX sobre selfPID)
        let localNames: [NSNotification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.willCloseNotification,
            NSWindow.didResizeNotification,
            NSWindow.didMoveNotification,
            NSApplication.didBecomeActiveNotification,
            NSApplication.didResignActiveNotification
        ]
        for name in localNames {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                if let win = notification.object as? NSWindow, win is NSPanel {
                    return
                }
                let targetWin = notification.object as? NSWindow
                let isGeo = (name == NSWindow.didResizeNotification || name == NSWindow.didMoveNotification || name == NSWindow.didDeminiaturizeNotification)
                Task { @MainActor [weak self, weak targetWin] in
                    guard let self, self.isMonitoring else { return }
                    self.scheduleCoalescedRefresh(delay: 0.04)
                    if isGeo {
                        if let targetWin {
                            self.onLocalWindowGeometryChanged?(targetWin)
                        }
                        self.pendingGeometryCheckAfterScan = true
                    }
                }
            }
            localWindowObservers.append(token)
        }
    }

    private func installAXObserversForRunningApps() {
        guard checkAccessibilityPermission(prompt: false) else { return }
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let livePIDs = Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != selfPID }
                .map(\.processIdentifier)
        )
        for deadPID in axObserversByPID.keys where !livePIDs.contains(deadPID) {
            removeAXObserver(for: deadPID)
        }
        for app in NSWorkspace.shared.runningApplications
            where app.activationPolicy == .regular && !app.isTerminated && app.processIdentifier != selfPID {
            installAXObserverIfNeeded(for: app)
        }
    }

    private func installAXObserverIfNeeded(for app: NSRunningApplication) {
        let pid = app.processIdentifier
        let selfPID = ProcessInfo.processInfo.processIdentifier
        // NUNCA registrar AXObserver ni llamar AX sobre el propio proceso (evita deadlock HIServices <-> AppKit)
        guard pid > 0, pid != selfPID, axObserversByPID[pid] == nil, isAccessibilityGranted else { return }
        guard app.activationPolicy == .regular else { return }

        var observer: AXObserver?
        let createResult = AXObserverCreate(pid, taskbarAXObserverCallback, &observer)
        guard createResult == .success, let observer else { return }

        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.25)

        let events: [String] = [
            kAXWindowCreatedNotification as String,
            kAXUIElementDestroyedNotification as String,
            kAXFocusedWindowChangedNotification as String,
            kAXMainWindowChangedNotification as String,
            kAXWindowMiniaturizedNotification as String,
            kAXWindowDeminiaturizedNotification as String,
            kAXTitleChangedNotification as String,
            kAXWindowMovedNotification as String,
            kAXWindowResizedNotification as String
        ]

        for eventName in events {
            AXObserverAddNotification(observer, appElement, eventName as CFString, nil)
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        axObserversByPID[pid] = observer
    }

    private func removeAXObserver(for pid: pid_t) {
        guard let observer = axObserversByPID.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    private func removeAllAXObservers() {
        for (_, observer) in axObserversByPID {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        axObserversByPID.removeAll()
    }

    private func startFallbackTimer() {
        fallbackRefreshTimer?.invalidate()
        // Intervalo coalescido (4 s, tolerancia 1 s): los AXObservers y NSWorkspace cubren eventos instantáneos
        // y este respaldo liviano mantiene Apple Silicon en reposo casi total.
        let timer = Timer(timeInterval: 4.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isMonitoring else { return }
                let wasTrusted = self.isAccessibilityGranted
                let nowTrusted = self.checkAccessibilityPermission(prompt: false)
                if !wasTrusted && nowTrusted {
                    self.installAXObserversForRunningApps()
                }
                self.refreshNow()
            }
        }
        timer.tolerance = 1.0
        RunLoop.main.add(timer, forMode: .common)
        fallbackRefreshTimer = timer
    }

    fileprivate func handleAXEventNotification(
        elementBox: AXElementBox? = nil,
        isGeometryChange: Bool,
        isHighFrequency: Bool = false
    ) {
        guard isMonitoring else { return }
        if isGeometryChange {
            pendingGeometryCheckAfterScan = true
            if let element = elementBox?.element {
                onAXWindowGeometryChanged?(element)
            }
        }
        scheduleCoalescedRefresh(delay: isHighFrequency ? 0.14 : 0.04)
    }

    public func scheduleCoalescedRefresh(delay: TimeInterval = 0.04) {
        pendingRefreshWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshNow()
            }
        }
        pendingRefreshWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func scheduleGeometryCheck() {
        pendingGeometryWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.onWindowGeometryPotentiallyChanged?()
            }
        }
        pendingGeometryWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: item)
    }

    // MARK: - Escaneo Asíncrono Único (Alimenta tanto Taskbar como AltTab)

    public func refreshNow() {
        guard isMonitoring else { return }
        if isScanInFlight {
            hasPendingRescan = true
            return
        }

        let trusted = checkAccessibilityPermission(prompt: false)
        if connectedScreens.isEmpty {
            refreshConnectedScreens()
        }

        let taskbarPrefs = TaskbarPreferences.shared
        let ownedWindowNumbers = collectAllOwnedWindowNumbers()
        let shouldRefreshBadges = trusted && activeConsumers.contains(.taskbar) && taskbarPrefs.showNotificationBadges && Date().timeIntervalSince(lastBadgeFetchDate) >= 5.0
        if shouldRefreshBadges {
            lastBadgeFetchDate = Date()
        }

        let allRunning = NSWorkspace.shared.runningApplications
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let dockPID = allRunning.first(where: { $0.bundleIdentifier == "com.apple.dock" })?.processIdentifier
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1

        var nextRunningBIDs = Set<String>()
        var nextRunningPaths = Set<String>()
        nextRunningBIDs.reserveCapacity(allRunning.count)
        nextRunningPaths.reserveCapacity(allRunning.count)

        var regularSnapshots: [RunningAppSnapshot] = []
        regularSnapshots.reserveCapacity(allRunning.count)
        for app in allRunning where app.activationPolicy == .regular && !app.isTerminated {
            let bundleID = app.bundleIdentifier ?? ""
            if !bundleID.isEmpty {
                nextRunningBIDs.insert(bundleID.lowercased())
            }
            if let bURL = app.bundleURL {
                nextRunningPaths.insert(Self.normalizedBundlePathKey(for: bURL))
            }
            if app.processIdentifier == selfPID { continue }
            if TaskbarPreferences.defaultExcludedSystemBundleIDs.contains(bundleID) { continue }
            if trusted {
                installAXObserverIfNeeded(for: app)
            }
            let rawName = app.localizedName ?? bundleID
            let cleanName = TaskbarStringSanitizer.sanitizeDisplayName(rawName)
            regularSnapshots.append(
                RunningAppSnapshot(
                    pid: app.processIdentifier,
                    bundleIdentifier: bundleID,
                    appName: cleanName.isEmpty ? rawName : cleanName,
                    bundleURL: app.bundleURL,
                    isHidden: app.isHidden
                )
            )
        }
        if runningBundleIDsLowercased != nextRunningBIDs {
            runningBundleIDsLowercased = nextRunningBIDs
        }
        if runningBundlePathsLowercased != nextRunningPaths {
            runningBundlePathsLowercased = nextRunningPaths
        }

        let nowRef = Date().timeIntervalSinceReferenceDate
        recentlyInteractedUntilByID = recentlyInteractedUntilByID.filter { $0.value > nowRef }
        let activeInteractedIDs = Set(recentlyInteractedUntilByID.keys)

        let context = TaskbarScanContext(
            isTrusted: trusted,
            screens: connectedScreens,
            ownedWindowNumbers: ownedWindowNumbers,
            showNotificationBadges: activeConsumers.contains(.taskbar) && taskbarPrefs.showNotificationBadges,
            shouldRefreshBadges: shouldRefreshBadges,
            cachedBadges: badgeByAppKey,
            frontmostPID: frontmostPID,
            dockPID: dockPID,
            runningApps: regularSnapshots,
            recentlyInteractedIDs: activeInteractedIDs
        )

        isScanInFlight = true
        hasPendingRescan = false

        scanQueue.async { [weak self] in
            let result = Self.performOffMainWindowScan(context: context)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isScanInFlight = false
                guard self.isMonitoring else { return }

                if let updatedBadges = result.updatedBadges, self.badgeByAppKey != updatedBadges {
                    self.badgeByAppKey = updatedBadges
                }

                let scannedApps = context.runningApps
                let runningPIDs = Set(scannedApps.map(\.pid)).union([selfPID])

                // Actualizar caché por PID: si una app tuvo timeout AX momentáneo (ej. durante animación de desminimizar),
                // preservamos sus ítems previos para que el botón jamás parpadee ni pierda su posición.
                var discoveredByPID: [pid_t: [TaskbarWindowItem]] = [:]
                for item in result.discoveredAllSpaces {
                    discoveredByPID[item.pid, default: []].append(item)
                }

                var effectiveExternalItems: [TaskbarWindowItem] = []
                var mergedAXElements: [String: AXUIElement] = result.axElementsByID.mapValues(\.element)
                var nextExternalCache: [pid_t: [TaskbarWindowItem]] = [:]

                for app in scannedApps {
                    if result.axTimedOutPIDs.contains(app.pid),
                       let previousItems = self.lastExternalItemsByPID[app.pid],
                       !previousItems.isEmpty {
                        effectiveExternalItems.append(contentsOf: previousItems)
                        nextExternalCache[app.pid] = previousItems
                        for prev in previousItems {
                            if let existingAX = self.axElementsByWindowItemID[prev.id] {
                                mergedAXElements[prev.id] = existingAX
                            }
                        }
                    } else {
                        let fresh = discoveredByPID[app.pid] ?? []
                        effectiveExternalItems.append(contentsOf: fresh)
                        nextExternalCache[app.pid] = fresh
                    }
                }
                self.lastExternalItemsByPID = nextExternalCache

                let latestOwned = self.collectAllOwnedWindowNumbers()
                let latestLocal = self.collectOwnMacFileExplorerWindows(
                    ownedWindowNumbers: latestOwned,
                    spaceSnapshot: result.spaceSnapshot
                )

                let rawCombined = latestLocal.items + effectiveExternalItems
                let combinedRawLiveIDs = Set(rawCombined.map(\.id))
                let combinedFullScreen = latestLocal.fullScreenDisplayIDs.union(result.fullScreenDisplayIDs)

                // Actualizar secuencia MRU y pre-calentar miniatura de la ventana que acaba de perder foco
                self.updateMRUAndPrewarmThumbnail(for: rawCombined, liveIDs: combinedRawLiveIDs)

                // Inyectar `lastFocusedOrder` en cada ítem y deduplicar pestañas inactivas de NSWindowTabGroup
                // (ej. Fork, Finder, Terminal minimizados con múltiples pestañas), priorizando el ID que ya tenía lugar en la barra.
                let enrichedRaw: [TaskbarWindowItem] = rawCombined.map { item in
                    let order = self.lastFocusedOrderByItemID[item.id] ?? 0
                    guard order != item.lastFocusedOrder else { return item }
                    return TaskbarWindowItem(
                        id: item.id,
                        windowID: item.windowID,
                        pid: item.pid,
                        bundleIdentifier: item.bundleIdentifier,
                        appName: item.appName,
                        appBundleURL: item.appBundleURL,
                        title: item.title,
                        frameAX: item.frameAX,
                        screenID: item.screenID,
                        isFocused: item.isFocused,
                        isMinimized: item.isMinimized,
                        isAppHidden: item.isAppHidden,
                        isFullScreen: item.isFullScreen,
                        badgeLabel: item.badgeLabel,
                        spaceIndex: item.spaceIndex,
                        isOnActiveSpace: item.isOnActiveSpace,
                        hasSpaceMembership: item.hasSpaceMembership,
                        lastFocusedOrder: order,
                        isWindowlessApp: item.isWindowlessApp
                    )
                }
                let enrichedAll = TaskbarTabGroupDeduplicator.deduplicate(
                    enrichedRaw,
                    preferredOrderIDs: self.orderEngine.orderedWindowIDs
                )

                // 1. Vista completa MRU para AltTab (solo ventanas reales en todos los Spaces, minimizadas y ocultas)
                let mruSortedAll = enrichedAll
                    .filter { !$0.isWindowlessApp }
                    .sorted { lhs, rhs in
                        if lhs.isFocused != rhs.isFocused { return lhs.isFocused }
                        if lhs.lastFocusedOrder != rhs.lastFocusedOrder { return lhs.lastFocusedOrder > rhs.lastFocusedOrder }
                        if lhs.isOnActiveSpace != rhs.isOnActiveSpace { return lhs.isOnActiveSpace }
                        if lhs.isMinimized != rhs.isMinimized { return !lhs.isMinimized }
                        return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
                    }

                // 2. Vista filtrada para Taskbar (respeta exclusiones, `syncWithActiveSpace` y apps abiertas sin ventanas como VS Code)
                let taskbarPrefs = TaskbarPreferences.shared
                var taskbarEligible = enrichedAll.filter { item in
                    if taskbarPrefs.isAppExcluded(bundleIdentifier: item.bundleIdentifier) {
                        return false
                    }
                    if taskbarPrefs.syncWithActiveSpace && !item.isOnActiveSpace && !item.isMinimized && !item.isAppHidden {
                        return false
                    }
                    return true
                }

                // Sintetizar botones para apps abiertas sin ventanas (ej. VS Code, Terminal, Numbers tras cerrar su última ventana),
                // excluyendo Finder (siempre corriendo en macOS) y apps ya fijadas (que ya muestran su punto activo en la sección Fijadas).
                var windowlessItems: [TaskbarWindowItem] = []
                if taskbarPrefs.showWindowlessRunningApps {
                    let pidsWithAnyRealWindow = Set(enrichedAll.map(\.pid))
                    let mainScreenID = self.connectedScreens.first(where: \.isMain)?.id
                        ?? self.connectedScreens.first?.id
                        ?? "main"

                    for app in scannedApps {
                        if pidsWithAnyRealWindow.contains(app.pid) { continue }
                        if result.axTimedOutPIDs.contains(app.pid) { continue }
                        if app.bundleIdentifier.caseInsensitiveCompare("com.apple.finder") == .orderedSame { continue }
                        if taskbarPrefs.isAppExcluded(bundleIdentifier: app.bundleIdentifier) { continue }
                        if taskbarPrefs.isHiddenWhenWindowless(bundleIdentifier: app.bundleIdentifier) { continue }
                        let appPath = app.bundleURL?.standardizedFileURL.path(percentEncoded: false)
                        if taskbarPrefs.isPinned(bundleIdentifier: app.bundleIdentifier, bundlePath: appPath) { continue }

                        let friendlyName = Self.friendlyBundleDisplayName(bundleURL: app.bundleURL, fallbackName: app.appName)
                        let badge = taskbarPrefs.showNotificationBadges
                            ? self.badgeLabel(
                                forBundleIdentifier: app.bundleIdentifier,
                                appName: app.appName,
                                bundleURL: app.bundleURL,
                                pid: app.pid
                            )
                            : nil

                        windowlessItems.append(
                            TaskbarWindowItem(
                                id: "\(app.pid)-windowless",
                                windowID: 0,
                                pid: app.pid,
                                bundleIdentifier: app.bundleIdentifier,
                                appName: friendlyName,
                                appBundleURL: app.bundleURL,
                                title: "",
                                frameAX: .zero,
                                screenID: mainScreenID,
                                isFocused: app.pid == frontmostPID && !app.isHidden,
                                isMinimized: false,
                                isAppHidden: app.isHidden,
                                isFullScreen: false,
                                badgeLabel: badge,
                                spaceIndex: nil,
                                isOnActiveSpace: true,
                                hasSpaceMembership: true,
                                lastFocusedOrder: 0,
                                isWindowlessApp: true
                            )
                        )
                    }
                    taskbarEligible.append(contentsOf: windowlessItems)
                }

                let deduplicatedLiveIDs = Set(enrichedAll.map(\.id)).union(windowlessItems.map(\.id))
                let taskbarOrdered = self.orderEngine.orderedWindows(
                    from: taskbarEligible,
                    groupByApp: taskbarPrefs.groupWindowsByApp,
                    pinnedAppsForOrdering: taskbarPrefs.orderWindowsByPinnedApps ? taskbarPrefs.pinnedApps : nil,
                    liveWindowIDsAcrossAllSpaces: deduplicatedLiveIDs,
                    runningPIDs: runningPIDs
                )

                self.localWindowsByItemID = latestLocal.windowsByID
                self.axElementsByWindowItemID = mergedAXElements

                if self.fullScreenDisplayIDs != combinedFullScreen {
                    self.fullScreenDisplayIDs = combinedFullScreen
                    TaskbarManager.shared.updateFullScreenVisibility()
                }
                if self.allWindowsAcrossSpaces != mruSortedAll {
                    self.allWindowsAcrossSpaces = mruSortedAll
                }
                let framesChanged = self.windows.count != taskbarOrdered.count || zip(self.windows, taskbarOrdered).contains { lhs, rhs in
                    lhs.id != rhs.id || lhs.frameAX != rhs.frameAX || lhs.isMinimized != rhs.isMinimized || lhs.isFullScreen != rhs.isFullScreen
                }
                if self.windows != taskbarOrdered {
                    self.windows = taskbarOrdered
                }
                if self.pendingGeometryCheckAfterScan || framesChanged {
                    self.pendingGeometryCheckAfterScan = false
                    self.onWindowGeometryPotentiallyChanged?()
                }

                // Purgar miniaturas cacheadas de ventanas cerradas
                let liveCGIDs = Set(enrichedAll.map(\.windowID).filter { $0 != 0 })
                TaskbarThumbnailService.shared.purgeClosedWindows(keeping: liveCGIDs)

                if self.hasPendingRescan {
                    self.hasPendingRescan = false
                    self.scheduleCoalescedRefresh(delay: 0.03)
                }
            }
        }
    }

    private func updateMRUAndPrewarmThumbnail(for items: [TaskbarWindowItem], liveIDs: Set<String>) {
        // Purgar IDs cerrados del mapa MRU
        lastFocusedOrderByItemID = lastFocusedOrderByItemID.filter { liveIDs.contains($0.key) }

        // Inicializar orden base para ventanas recién descubiertas (sin desplazar a la actualmente enfocada)
        for item in items where lastFocusedOrderByItemID[item.id] == nil {
            focusSequenceCounter &+= 1
            lastFocusedOrderByItemID[item.id] = item.isFocused ? (focusSequenceCounter &+ 1) : 1
        }

        if let currentFocused = items.first(where: { $0.isFocused }) {
            if currentFocused.id != lastFocusedWindowItemID {
                let shouldPrewarm = activeConsumers.contains(.altTab)
                    || (activeConsumers.contains(.taskbar) && TaskbarPreferences.shared.showHoverPreviews)
                let prewarmDim = max(340, TaskbarPreferences.shared.thumbnailSize.maxDimension)

                // Pre-calentar en background la miniatura de la ventana que acaba de perder foco (mientras sigue fresca)
                if lastFocusedCGWindowID != 0 && shouldPrewarm {
                    TaskbarThumbnailService.shared.prewarmThumbnailInBackground(for: lastFocusedCGWindowID, maxDimension: prewarmDim)
                }
                // También pre-calentar la ventana nueva tras un instante si aún no está en caché
                if currentFocused.windowID != 0 &&
                   shouldPrewarm &&
                   TaskbarThumbnailService.shared.cachedThumbnail(for: currentFocused.windowID) == nil {
                    TaskbarThumbnailService.shared.prewarmThumbnailInBackground(for: currentFocused.windowID, maxDimension: prewarmDim)
                }

                focusSequenceCounter &+= 1
                lastFocusedOrderByItemID[currentFocused.id] = focusSequenceCounter
                lastFocusedWindowItemID = currentFocused.id
                lastFocusedCGWindowID = currentFocused.windowID
            }
        }
    }

    private func collectOwnMacFileExplorerWindows(
        ownedWindowNumbers: Set<Int>,
        spaceSnapshot: TaskbarSpaceMetadataResolver.Snapshot?
    ) -> (items: [TaskbarWindowItem], liveIDs: Set<String>, windowsByID: [String: WeakNSWindowBox], fullScreenDisplayIDs: Set<String>) {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 900
        let bundleID = Bundle.main.bundleIdentifier ?? "com.macfileexplorer.app"
        let bundleURL = Bundle.main.bundleURL
        let appName = LocalizationManager.shared.text(es: "Explorador de Archivos", en: "MacFileExplorer")
        let appIsActive = NSApp.isActive
        let appIsHidden = NSApp.isHidden

        var items: [TaskbarWindowItem] = []
        var liveIDs: Set<String> = []
        var windowsByID: [String: WeakNSWindowBox] = [:]
        var fullScreens: Set<String> = []

        for window in NSApp.windows {
            if window is NSPanel { continue }
            if ownedWindowNumbers.contains(window.windowNumber) { continue }
            guard window.styleMask.contains(.titled) else { continue }
            guard window.isVisible || window.isMiniaturized else { continue }
            if let tabGroup = window.tabGroup, tabGroup.selectedWindow !== window { continue }
            guard window.frame.width >= 100, window.frame.height >= 60 else { continue }

            let winNum = CGWindowID(max(0, window.windowNumber))
            let itemID = "\(selfPID)-\(winNum)"
            liveIDs.insert(itemID)

            let spaceInfo = TaskbarSpaceMetadataResolver.resolveSpaceInfo(for: winNum, snapshot: spaceSnapshot)
            let isOnSpace = spaceInfo?.isOnActiveSpace ?? window.isOnActiveSpace
            let spaceIndex = spaceInfo?.spaceIndex
            let isMini = window.isMiniaturized

            let frameAX = TaskbarGeometry.cocoaRectToAX(window.frame, primaryScreenHeight: primaryHeight)
            let screenID = TaskbarGeometry.assignScreenID(forWindowFrameAX: frameAX, screens: connectedScreens)
            let isFullScreen = window.styleMask.contains(.fullScreen)
            if isFullScreen && isOnSpace {
                fullScreens.insert(screenID)
            }

            let isFocused = appIsActive && !isMini && !appIsHidden && (window.isKeyWindow || window.isMainWindow)
            let title = TaskbarStringSanitizer.sanitizeDisplayName(window.title)

            items.append(
                TaskbarWindowItem(
                    id: itemID,
                    windowID: winNum,
                    pid: selfPID,
                    bundleIdentifier: bundleID,
                    appName: appName,
                    appBundleURL: bundleURL,
                    title: title,
                    frameAX: frameAX,
                    screenID: screenID,
                    isFocused: isFocused,
                    isMinimized: isMini,
                    isAppHidden: appIsHidden,
                    isFullScreen: isFullScreen,
                    badgeLabel: nil,
                    spaceIndex: spaceIndex,
                    isOnActiveSpace: isOnSpace
                )
            )
            windowsByID[itemID] = WeakNSWindowBox(window)
        }

        return (items, liveIDs, windowsByID, fullScreens)
    }

    public func localWindow(for itemID: String) -> NSWindow? {
        localWindowsByItemID[itemID]?.window
    }

    private nonisolated static func performOffMainWindowScan(context: TaskbarScanContext) -> TaskbarScanResult {
        let onScreenCGWindows = fetchCGWindowSnapshots(onScreenOnly: true)
        let onScreenByID: [CGWindowID: CGWindowSnapshotInfo] = Dictionary(
            onScreenCGWindows.map { ($0.windowID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let spaceSnapshot = TaskbarSpaceMetadataResolver.captureDisplaySpacesSnapshot()

        let updatedBadges: [String: String]?
        let activeBadges: [String: String]
        if context.shouldRefreshBadges {
            let lsBadges = fetchLaunchServicesBadgesOffMain()
            let dockBadges: [String: String]?
            if let dockPID = context.dockPID {
                dockBadges = fetchDockBadgesOffMain(dockPID: dockPID)
            } else {
                dockBadges = nil
            }
            if let dockBadges {
                // Combinar LaunchServices + Dock AX (Dock AX tiene prioridad para apps Catalyst como WhatsApp)
                var merged = lsBadges
                for (k, v) in dockBadges {
                    merged[k] = v
                }
                updatedBadges = merged
                activeBadges = merged
            } else if !lsBadges.isEmpty {
                // Si el Dock tuvo un timeout transitorio, conservar previos y superponer LaunchServices frescos
                var merged = context.cachedBadges
                for (k, v) in lsBadges {
                    merged[k] = v
                }
                updatedBadges = merged
                activeBadges = merged
            } else {
                updatedBadges = nil
                activeBadges = context.cachedBadges
            }
        } else {
            updatedBadges = nil
            activeBadges = context.cachedBadges
        }

        var discoveredAll: [TaskbarWindowItem] = []
        var liveIDsAllSpaces: Set<String> = []
        var newAXElements: [String: AXElementBox] = [:]
        var axTimedOutPIDs: Set<pid_t> = []
        var detectedFullScreenDisplays: Set<String> = []
        var cachedAllCGWindows: [CGWindowSnapshotInfo]?

        if context.isTrusted {
            for app in context.runningApps {
                let pid = app.pid
                let appElement = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(appElement, 0.25)

                let focusedAXWindow = axElementAttribute(appElement, kAXFocusedWindowAttribute)
                let focusedWinID = focusedAXWindow.flatMap { AXPrivateBridge.windowID(for: $0) }
                let axWinFetch = axWindowsAttributeResult(appElement)
                if axWinFetch.timedOutOrFailed {
                    axTimedOutPIDs.insert(pid)
                    continue
                }
                let axWindows = axWinFetch.windows
                let appBadge = context.showNotificationBadges
                    ? lookupBadge(
                        in: activeBadges,
                        bundleIdentifier: app.bundleIdentifier,
                        appName: app.appName,
                        bundleURL: app.bundleURL,
                        pid: pid
                    )
                    : nil

                for axWindow in axWindows {
                    AXUIElementSetMessagingTimeout(axWindow, 0.25)
                    guard isTrackableAXWindow(axWindow) else { continue }

                    let role = axStringAttribute(axWindow, kAXRoleAttribute) ?? ""
                    let subrole = axStringAttribute(axWindow, kAXSubroleAttribute) ?? ""
                    let isMinimized = axBoolAttribute(axWindow, kAXMinimizedAttribute) ?? false
                    let isFullScreenAttr = axBoolAttribute(axWindow, "AXFullScreen") ?? false
                    let axPosition = axPointAttribute(axWindow, kAXPositionAttribute) ?? .zero
                    let axSize = axSizeAttribute(axWindow, kAXSizeAttribute) ?? .zero
                    let frameAX = CGRect(origin: axPosition, size: axSize)
                    let rawTitle = axStringAttribute(axWindow, kAXTitleAttribute) ?? ""
                    let axTitle = TaskbarStringSanitizer.sanitizeDisplayName(rawTitle)

                    if !role.isEmpty && role != (kAXWindowRole as String) {
                        continue
                    }
                    if !subrole.isEmpty && subrole != (kAXStandardWindowSubrole as String) && subrole != (kAXDialogSubrole as String) {
                        continue
                    }
                    if subrole == (kAXDialogSubrole as String) && (frameAX.width < 240 || frameAX.height < 140) {
                        continue
                    }

                    var resolvedWindowID: CGWindowID = AXPrivateBridge.windowID(for: axWindow)
                        ?? matchCGWindowID(pid: pid, frameAX: frameAX, title: axTitle, candidates: onScreenCGWindows)
                        ?? 0

                    // Respaldo con TODAS las ventanas CG (incluidas minimizadas/ocultas) para evitar cambios de ID `pid-ax-hash` ↔ `pid-windowID`
                    if resolvedWindowID == 0 {
                        if cachedAllCGWindows == nil {
                            cachedAllCGWindows = fetchCGWindowSnapshots(onScreenOnly: false)
                        }
                        if let allCG = cachedAllCGWindows {
                            resolvedWindowID = matchCGWindowID(pid: pid, frameAX: frameAX, title: axTitle, candidates: allCG) ?? 0
                        }
                    }

                    if resolvedWindowID != 0 && context.ownedWindowNumbers.contains(Int(resolvedWindowID)) {
                        continue
                    }

                    let stableItemID: String = resolvedWindowID != 0
                        ? "\(pid)-\(resolvedWindowID)"
                        : "\(pid)-ax-\(CFHash(axWindow))"

                    let isRecentlyInteracted = context.recentlyInteractedIDs.contains(stableItemID)

                    if !isMinimized && !isRecentlyInteracted && (frameAX.width < 100 || frameAX.height < 60) {
                        continue
                    }

                    liveIDsAllSpaces.insert(stableItemID)

                    let cgInfo = resolvedWindowID != 0 ? onScreenByID[resolvedWindowID] : nil
                    let isOnScreenNow = (cgInfo != nil && cgInfo?.layer == 0)
                    let spaceInfo = TaskbarSpaceMetadataResolver.resolveSpaceInfo(for: resolvedWindowID, snapshot: spaceSnapshot)
                    let hasSpaceMembership = spaceInfo?.hasAnySpace ?? isOnScreenNow

                    // Descartar inmediatamente pestañas inactivas de NSWindowTabGroup y ventanas fantasma
                    // que no están en pantalla, no están minimizadas/ocultas y no pertenecen a ningún Space (`spaces == []`).
                    // Nunca descartar una ventana recién desminimizada/enfocada durante su animación de transición.
                    if !isOnScreenNow && !isMinimized && !app.isHidden && !isRecentlyInteracted && spaceInfo != nil && !hasSpaceMembership {
                        continue
                    }

                    let isOnActiveSpace: Bool = {
                        if isOnScreenNow { return true }
                        if let spaceInfo, spaceInfo.hasAnySpace { return spaceInfo.isOnActiveSpace }
                        return isMinimized || app.isHidden
                    }()
                    let spaceIndex = spaceInfo?.spaceIndex

                    let screenID = TaskbarGeometry.assignScreenID(forWindowFrameAX: frameAX, screens: context.screens)
                    let matchingScreen = context.screens.first(where: { $0.id == screenID })
                    let fillsEntireScreen: Bool = {
                        guard let scr = matchingScreen, isOnActiveSpace, !isMinimized else { return false }
                        return abs(frameAX.minX - scr.frameAX.minX) <= 2 &&
                            abs(frameAX.minY - scr.frameAX.minY) <= 2 &&
                            abs(frameAX.width - scr.frameAX.width) <= 2 &&
                            abs(frameAX.height - scr.frameAX.height) <= 2
                    }()
                    let isFullScreen = isFullScreenAttr || fillsEntireScreen
                    if isFullScreen && isOnActiveSpace {
                        detectedFullScreenDisplays.insert(screenID)
                    }

                    let isFocused: Bool = {
                        guard pid == context.frontmostPID, !isMinimized, !app.isHidden, isOnActiveSpace else { return false }
                        if let focusedWinID, resolvedWindowID != 0 {
                            return focusedWinID == resolvedWindowID
                        }
                        if let focusedAXWindow {
                            return CFEqual(focusedAXWindow, axWindow)
                        }
                        return false
                    }()

                    let finalTitle = axTitle.isEmpty
                        ? TaskbarStringSanitizer.sanitizeDisplayName(cgInfo?.title ?? "")
                        : axTitle

                    let windowBadge: String? = {
                        guard context.showNotificationBadges else { return nil }
                        if let appBadge, !appBadge.isEmpty { return appBadge }
                        return Self.extractUnreadBadgeFromWindowTitle(
                            finalTitle,
                            bundleIdentifier: app.bundleIdentifier,
                            bundleURL: app.bundleURL
                        )
                    }()

                    let item = TaskbarWindowItem(
                        id: stableItemID,
                        windowID: resolvedWindowID,
                        pid: pid,
                        bundleIdentifier: app.bundleIdentifier,
                        appName: app.appName,
                        appBundleURL: app.bundleURL,
                        title: finalTitle,
                        frameAX: frameAX,
                        screenID: screenID,
                        isFocused: isFocused,
                        isMinimized: isMinimized,
                        isAppHidden: app.isHidden,
                        isFullScreen: isFullScreen,
                        badgeLabel: windowBadge,
                        spaceIndex: spaceIndex,
                        isOnActiveSpace: isOnActiveSpace,
                        hasSpaceMembership: hasSpaceMembership
                    )

                    discoveredAll.append(item)
                    newAXElements[stableItemID] = AXElementBox(axWindow)
                }
            }
        } else {
            // Respaldo de solo lectura si aún no se otorgó Accesibilidad (usando CGWindowList)
            let allCGWindows = fetchCGWindowSnapshots(onScreenOnly: false)
            let appsByPID = Dictionary(
                context.runningApps.map { ($0.pid, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            for cg in allCGWindows where cg.layer == 0 && cg.alpha > 0.05 {
                if context.ownedWindowNumbers.contains(Int(cg.windowID)) { continue }
                guard let app = appsByPID[cg.pid] else { continue }
                guard cg.bounds.width >= 100, cg.bounds.height >= 60 else { continue }

                let spaceInfo = TaskbarSpaceMetadataResolver.resolveSpaceInfo(for: cg.windowID, snapshot: spaceSnapshot)
                let isOnScreenNow = (onScreenByID[cg.windowID] != nil)
                let hasSpaceMembership = spaceInfo?.hasAnySpace ?? isOnScreenNow
                if !isOnScreenNow && !app.isHidden && spaceInfo != nil && !hasSpaceMembership {
                    continue
                }
                let isOnActive = isOnScreenNow || (spaceInfo?.isOnActiveSpace ?? false)
                let screenID = TaskbarGeometry.assignScreenID(forWindowFrameAX: cg.bounds, screens: context.screens)
                let itemID = "\(cg.pid)-\(cg.windowID)"
                liveIDsAllSpaces.insert(itemID)
                discoveredAll.append(
                    TaskbarWindowItem(
                        id: itemID,
                        windowID: cg.windowID,
                        pid: cg.pid,
                        bundleIdentifier: app.bundleIdentifier,
                        appName: app.appName,
                        appBundleURL: app.bundleURL,
                        title: TaskbarStringSanitizer.sanitizeDisplayName(cg.title),
                        frameAX: cg.bounds,
                        screenID: screenID,
                        isFocused: isOnActive && cg.pid == context.frontmostPID && discoveredAll.allSatisfy { $0.pid != context.frontmostPID },
                        isMinimized: false,
                        isAppHidden: app.isHidden,
                        isFullScreen: false,
                        badgeLabel: nil,
                        spaceIndex: spaceInfo?.spaceIndex,
                        isOnActiveSpace: isOnActive,
                        hasSpaceMembership: hasSpaceMembership
                    )
                )
            }
        }

        return TaskbarScanResult(
            discoveredAllSpaces: discoveredAll,
            liveIDsAllSpaces: liveIDsAllSpaces,
            axElementsByID: newAXElements,
            axTimedOutPIDs: axTimedOutPIDs,
            fullScreenDisplayIDs: detectedFullScreenDisplays,
            updatedBadges: updatedBadges,
            spaceSnapshot: spaceSnapshot
        )
    }

    // MARK: - Reordenamiento Manual y Agrupación Inmediata (Taskbar)

    /// Reaplica de forma síncrona el orden/agrupación actual sobre las ventanas visibles (0 ms de espera al activar/desactivar la opción).
    public func reapplyWindowOrderingImmediately() {
        guard !windows.isEmpty else { return }
        let taskbarPrefs = TaskbarPreferences.shared
        let liveIDs = Set(allWindowsAcrossSpaces.map(\.id)).union(windows.map(\.id))
        let reordered = orderEngine.orderedWindows(
            from: windows,
            groupByApp: taskbarPrefs.groupWindowsByApp,
            pinnedAppsForOrdering: taskbarPrefs.orderWindowsByPinnedApps ? taskbarPrefs.pinnedApps : nil,
            liveWindowIDsAcrossAllSpaces: liveIDs
        )
        if reordered != windows {
            windows = reordered
        }
    }

    /// Resultado de intentar reordenar manualmente un botón de ventana en la Barra de tareas.
    public enum MoveWindowResult: Equatable, Sendable {
        case moved
        case blockedByPinnedOrder(sourceAppName: String, isSourcePinned: Bool)
    }

    @discardableResult
    public func moveWindow(sourceID: String, toTargetID targetID: String) -> MoveWindowResult {
        let taskbarPrefs = TaskbarPreferences.shared

        if taskbarPrefs.orderWindowsByPinnedApps,
           let sourceWin = windows.first(where: { $0.id == sourceID }),
           let targetWin = windows.first(where: { $0.id == targetID }) {
            let sourcePinned = taskbarPrefs.isPinned(
                bundleIdentifier: sourceWin.bundleIdentifier,
                bundlePath: sourceWin.appBundleURL?.standardizedFileURL.path(percentEncoded: false)
            )
            let targetPinned = taskbarPrefs.isPinned(
                bundleIdentifier: targetWin.bundleIdentifier,
                bundlePath: targetWin.appBundleURL?.standardizedFileURL.path(percentEncoded: false)
            )
            if (sourcePinned || targetPinned) && sourceWin.appGroupKey != targetWin.appGroupKey {
                return .blockedByPinnedOrder(sourceAppName: sourceWin.appName, isSourcePinned: sourcePinned)
            }
        }

        orderEngine.moveWindow(
            sourceID: sourceID,
            toTargetID: targetID,
            visibleWindows: windows,
            groupByApp: taskbarPrefs.groupWindowsByApp
        )
        if taskbarPrefs.orderWindowsByPinnedApps {
            reapplyWindowOrderingImmediately()
            return .moved
        }
        let byID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        let reordered = orderEngine.orderedWindowIDs.compactMap { byID[$0] }
        if reordered.count == windows.count {
            windows = reordered
        } else {
            refreshNow()
        }
        return .moved
    }

    // MARK: - Acciones Instantáneas Compartidas sobre Ventanas y Aplicaciones (macOS 14+ / Catalyst / PWAs / Cross-Space)

    public func axElement(for itemID: String) -> AXUIElement? {
        axElementsByWindowItemID[itemID]
    }

    public func handlePrimaryClick(on item: TaskbarWindowItem) {
        if item.isWindowlessApp {
            openWindowlessApplication(item)
            return
        }
        let isActuallyFrontmost = (NSWorkspace.shared.frontmostApplication?.processIdentifier == item.pid) && item.isFocused
        if isActuallyFrontmost && !item.isMinimized && !item.isAppHidden {
            switch TaskbarPreferences.shared.clickFocusedAction {
            case .minimizeWindow:
                minimizeWindow(item)
            case .hideApp:
                hideApplication(pid: item.pid)
            case .doNothing:
                break
            }
            return
        }
        focusWindow(item)
    }

    private func openWindowlessApplication(_ item: TaskbarWindowItem) {
        markRecentlyInteracted(item.id, duration: 2.5)
        if let url = item.appBundleURL ?? NSRunningApplication(processIdentifier: item.pid)?.bundleURL {
            launchOrFocusApplication(bundleIdentifier: item.bundleIdentifier, bundleURL: url)
        } else if let app = NSRunningApplication(processIdentifier: item.pid), !app.isTerminated {
            activateRunningApp(app, allWindows: true)
            scheduleCoalescedRefresh(delay: 0.20)
        }
    }

    private func markRecentlyInteracted(_ itemID: String, duration: TimeInterval = 2.0) {
        recentlyInteractedUntilByID[itemID] = Date().timeIntervalSinceReferenceDate + duration
    }

    private static func friendlyBundleDisplayName(bundleURL: URL?, fallbackName: String) -> String {
        if let bundleURL {
            let raw = FileManager.default.displayName(atPath: bundleURL.path(percentEncoded: false))
                .replacingOccurrences(of: ".app", with: "", options: [.caseInsensitive, .anchored, .backwards])
            let sanitized = TaskbarStringSanitizer.sanitizeDisplayName(raw)
            if !sanitized.isEmpty {
                return sanitized
            }
        }
        return fallbackName
    }

    private func activateRunningApp(_ app: NSRunningApplication, allWindows: Bool) {
        if app.isHidden {
            app.unhide()
        }
        NSApplication.shared.yieldActivation(to: app)
        if allWindows {
            _ = app.activate(options: [.activateAllWindows])
        } else {
            _ = app.activate()
        }
    }

    /// Enfoca y eleva instantáneamente la ventana exacta (incluyendo cambio de Space, minimizadas,
    /// ocultas, WhatsApp Catalyst, PWAs y ventanas propias de MacFileExplorer).
    public func focusWindow(_ item: TaskbarWindowItem) {
        focusRequestToken &+= 1
        let requestToken = focusRequestToken

        if item.isWindowlessApp {
            openWindowlessApplication(item)
            return
        }

        // Proteger esta ventana durante la animación de desminimizado/cambio de Space para no perder su posición
        markRecentlyInteracted(item.id, duration: 2.2)

        // Registrar MRU inmediatamente para que el siguiente AltTab recuerde el nuevo orden
        focusSequenceCounter &+= 1
        lastFocusedOrderByItemID[item.id] = focusSequenceCounter
        lastFocusedWindowItemID = item.id
        lastFocusedCGWindowID = item.windowID

        // Caso propio (MacFileExplorer): manipular NSWindow directamente en @MainActor (cero AX IPC, cero deadlock)
        if item.pid == ProcessInfo.processInfo.processIdentifier {
            applyOptimisticFocus(windowItemID: item.id)
            if let localWin = localWindowsByItemID[item.id]?.window {
                if localWin.isMiniaturized {
                    localWin.deminiaturize(nil)
                }
                if NSApp.isHidden {
                    NSApp.unhide(nil)
                }
                let localWID = CGWindowID(max(0, localWin.windowNumber))
                if !SkyLightSingleWindowFocusBridge.focusSingleWindow(pid: item.pid, windowID: localWID) {
                    NSApp.activate()
                }
                localWin.orderFrontRegardless()
                localWin.makeKeyAndOrderFront(nil)
            } else {
                GoogleAccountsManager.shared.openOrFocusMainWindow()
            }
            scheduleCoalescedRefresh(delay: 0.08)
            return
        }

        guard let app = NSRunningApplication(processIdentifier: item.pid), !app.isTerminated else {
            if let url = item.appBundleURL {
                openApplicationViaWorkspaceAndFallback(
                    bundleURL: url,
                    isPWA: TaskbarStringSanitizer.isWebAppPWA(bundleIdentifier: item.bundleIdentifier, bundleURL: url)
                )
            }
            scheduleCoalescedRefresh(delay: 0.08)
            return
        }

        applyOptimisticFocus(windowItemID: item.id)

        let pid = item.pid
        let targetWindowID = item.windowID
        let axBox = axElementsByWindowItemID[item.id].map(AXElementBox.init)
        let wasMinimized = item.isMinimized

        if app.isHidden {
            app.unhide()
        }
        NSApplication.shared.yieldActivation(to: app)

        // Enfoque quirúrgico de UNA sola ventana vía SkyLight (`_SLPSSetFrontProcessWithOptions` + `makeKeyWindow`):
        // evita que macOS traiga al frente el resto de las ventanas de la misma app (ej. Chrome en otro monitor)
        // y nunca mueve la ventana de su pantalla original.
        let skyLightFocused = (!wasMinimized && targetWindowID != 0)
            ? SkyLightSingleWindowFocusBridge.focusSingleWindow(pid: pid, windowID: targetWindowID)
            : false

        if !skyLightFocused && !wasMinimized {
            activateRunningApp(app, allWindows: false)
        }

        actionQueue.async {
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, 0.25)

            // Resolver el AXUIElement exacto (cacheado o buscando en vivo por `CGWindowID`)
            var resolvedAXWin: AXUIElement? = axBox?.element
            if resolvedAXWin == nil && targetWindowID != 0 {
                var windowsRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                   let axWindows = windowsRef as? [AXUIElement] {
                    resolvedAXWin = axWindows.first { AXPrivateBridge.windowID(for: $0) == targetWindowID }
                }
            }

            if let axWin = resolvedAXWin {
                AXUIElementSetMessagingTimeout(axWin, 0.25)
                if wasMinimized {
                    AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                    usleep(40_000)
                }
                AXUIElementSetAttributeValue(axWin, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementSetAttributeValue(axWin, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
            }

            if wasMinimized && targetWindowID != 0 {
                let postDeminiOK = SkyLightSingleWindowFocusBridge.focusSingleWindow(pid: pid, windowID: targetWindowID)
                if !postDeminiOK {
                    AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
                }
            } else if !skyLightFocused {
                AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            }

            if let axWin = resolvedAXWin {
                usleep(25_000)
                AXUIElementSetAttributeValue(axWin, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
                if targetWindowID != 0 {
                    _ = SkyLightSingleWindowFocusBridge.focusSingleWindow(pid: pid, windowID: targetWindowID)
                }
            }
        }

        // Verificación rápida a los 90ms solo si el proceso aún no recibió foco (ej. salto cross-Space o Catalyst).
        // Importante: nunca usar `allWindows: true` para no levantar otras ventanas de la misma app en otro monitor.
        let bundleURL = item.appBundleURL ?? app.bundleURL
        let bundleID = item.bundleIdentifier
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { [weak self] in
            guard let self, self.focusRequestToken == requestToken else { return }
            let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if frontPID != pid {
                let retryOK = targetWindowID != 0
                    ? SkyLightSingleWindowFocusBridge.focusSingleWindow(pid: pid, windowID: targetWindowID)
                    : false
                if !retryOK {
                    if let liveApp = NSRunningApplication(processIdentifier: pid), !liveApp.isTerminated {
                        self.activateRunningApp(liveApp, allWindows: false)
                    }
                    if let bundleURL,
                       TaskbarStringSanitizer.isWebAppPWA(bundleIdentifier: bundleID, bundleURL: bundleURL) || targetWindowID == 0 {
                        let isPWA = TaskbarStringSanitizer.isWebAppPWA(bundleIdentifier: bundleID, bundleURL: bundleURL)
                        self.openApplicationViaWorkspaceAndFallback(bundleURL: bundleURL, isPWA: isPWA) { [weak self] in
                            guard let self, self.focusRequestToken == requestToken, let axBox else { return }
                            self.actionQueue.async {
                                AXUIElementSetMessagingTimeout(axBox.element, 0.25)
                                AXUIElementSetAttributeValue(axBox.element, kAXMainAttribute as CFString, kCFBooleanTrue)
                                AXUIElementPerformAction(axBox.element, kAXRaiseAction as CFString)
                            }
                        }
                    }
                }
            }
            self.scheduleCoalescedRefresh(delay: 0.08)
        }
    }

    private func applyOptimisticFocus(windowItemID: String) {
        let mapTransform: (TaskbarWindowItem) -> TaskbarWindowItem = { w in
            let isTarget = (w.id == windowItemID)
            if w.isFocused == isTarget && (!isTarget || (!w.isMinimized && !w.isAppHidden)) {
                return w
            }
            return TaskbarWindowItem(
                id: w.id,
                windowID: w.windowID,
                pid: w.pid,
                bundleIdentifier: w.bundleIdentifier,
                appName: w.appName,
                appBundleURL: w.appBundleURL,
                title: w.title,
                frameAX: w.frameAX,
                screenID: w.screenID,
                isFocused: isTarget,
                isMinimized: isTarget ? false : w.isMinimized,
                isAppHidden: isTarget ? false : w.isAppHidden,
                isFullScreen: w.isFullScreen,
                badgeLabel: w.badgeLabel,
                spaceIndex: w.spaceIndex,
                isOnActiveSpace: isTarget ? true : w.isOnActiveSpace,
                hasSpaceMembership: w.hasSpaceMembership,
                lastFocusedOrder: isTarget ? self.focusSequenceCounter : w.lastFocusedOrder,
                isWindowlessApp: w.isWindowlessApp
            )
        }
        windows = windows.map(mapTransform)
        allWindowsAcrossSpaces = allWindowsAcrossSpaces.map(mapTransform)
    }

    public func minimizeWindow(_ item: TaskbarWindowItem) {
        guard !item.isWindowlessApp else { return }
        markRecentlyInteracted(item.id, duration: 2.2)
        if item.pid == ProcessInfo.processInfo.processIdentifier {
            if let win = localWindowsByItemID[item.id]?.window {
                if win.isMiniaturized {
                    win.deminiaturize(nil)
                } else {
                    win.miniaturize(nil)
                }
            }
            scheduleCoalescedRefresh(delay: 0.10)
            return
        }
        guard let axWin = axElementsByWindowItemID[item.id] else { return }
        let box = AXElementBox(axWin)
        let targetState = !item.isMinimized
        actionQueue.async {
            AXUIElementSetMessagingTimeout(box.element, 0.25)
            AXUIElementSetAttributeValue(box.element, kAXMinimizedAttribute as CFString, targetState ? kCFBooleanTrue : kCFBooleanFalse)
        }
        scheduleCoalescedRefresh(delay: 0.12)
    }

    public func toggleFullScreen(_ item: TaskbarWindowItem) {
        guard !item.isWindowlessApp else { return }
        markRecentlyInteracted(item.id, duration: 2.5)
        if item.pid == ProcessInfo.processInfo.processIdentifier {
            localWindowsByItemID[item.id]?.window?.toggleFullScreen(nil)
            scheduleCoalescedRefresh(delay: 0.25)
            return
        }
        guard let axWin = axElementsByWindowItemID[item.id] else { return }
        let box = AXElementBox(axWin)
        let targetFullScreen = !item.isFullScreen
        actionQueue.async {
            AXUIElementSetMessagingTimeout(box.element, 0.25)
            AXUIElementSetAttributeValue(box.element, "AXFullScreen" as CFString, targetFullScreen ? kCFBooleanTrue : kCFBooleanFalse)
        }
        scheduleCoalescedRefresh(delay: 0.25)
    }

    public func closeWindow(_ item: TaskbarWindowItem) {
        if item.isWindowlessApp {
            quitApplication(pid: item.pid, force: false)
            return
        }
        if item.pid == ProcessInfo.processInfo.processIdentifier {
            localWindowsByItemID[item.id]?.window?.performClose(nil)
            scheduleCoalescedRefresh(delay: 0.12)
            return
        }
        guard let axWin = axElementsByWindowItemID[item.id] else { return }
        let box = AXElementBox(axWin)
        actionQueue.async { [weak self] in
            AXUIElementSetMessagingTimeout(box.element, 0.25)
            if let closeButton = Self.axElementAttribute(box.element, kAXCloseButtonAttribute) {
                AXUIElementPerformAction(closeButton, kAXPressAction as CFString)
            } else {
                DispatchQueue.main.async {
                    self?.focusWindow(item)
                }
            }
        }
        scheduleCoalescedRefresh(delay: 0.16)
    }

    public func hideApplication(pid: pid_t) {
        if pid == ProcessInfo.processInfo.processIdentifier {
            if NSApp.isHidden { NSApp.unhide(nil) } else { NSApp.hide(nil) }
            scheduleCoalescedRefresh(delay: 0.10)
            return
        }
        if let app = NSRunningApplication(processIdentifier: pid) {
            if app.isHidden {
                app.unhide()
            } else {
                app.hide()
            }
        }
        scheduleCoalescedRefresh(delay: 0.10)
    }

    public func quitApplication(pid: pid_t, force: Bool = false) {
        if pid == ProcessInfo.processInfo.processIdentifier {
            TaskbarManager.shared.prepareForTermination()
            AltTabManager.shared.prepareForTermination()
            GoogleAccountsManager.shared.prepareForTermination()
            NSApp.terminate(nil)
            return
        }
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        if force {
            app.forceTerminate()
        } else {
            app.terminate()
        }
        scheduleCoalescedRefresh(delay: 0.25)
    }

    public func launchOrFocusApplication(bundleIdentifier: String, bundleURL: URL) {
        if let selfBundleID = Bundle.main.bundleIdentifier,
           bundleIdentifier.caseInsensitiveCompare(selfBundleID) == .orderedSame {
            GoogleAccountsManager.shared.openOrFocusMainWindow()
            return
        }
        let standardizedTargetURL = bundleURL.standardizedFileURL
        let isPWA = TaskbarStringSanitizer.isWebAppPWA(bundleIdentifier: bundleIdentifier, bundleURL: standardizedTargetURL)

        let running = NSWorkspace.shared.runningApplications.first { app in
            guard !app.isTerminated else { return false }
            if !bundleIdentifier.isEmpty,
               let runningID = app.bundleIdentifier,
               runningID.caseInsensitiveCompare(bundleIdentifier) == .orderedSame {
                return true
            }
            if let runningURL = app.bundleURL?.standardizedFileURL,
               runningURL == standardizedTargetURL {
                return true
            }
            return false
        }

        TaskbarPreferences.shared.recordRecentApp(bundleURL: standardizedTargetURL)

        if let running {
            let appWindows = allWindowsAcrossSpaces.filter { $0.pid == running.processIdentifier }
            if let target = appWindows.first(where: { !$0.isFocused }) ?? appWindows.first {
                focusWindow(target)
                return
            }

            activateRunningApp(running, allWindows: true)

            let pid = running.processIdentifier
            actionQueue.async {
                let appElement = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(appElement, 0.25)
                if let firstWin = Self.axWindowsAttribute(appElement).first {
                    AXUIElementSetMessagingTimeout(firstWin, 0.25)
                    AXUIElementSetAttributeValue(firstWin, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                    AXUIElementSetAttributeValue(firstWin, kAXMainAttribute as CFString, kCFBooleanTrue)
                    AXUIElementPerformAction(firstWin, kAXRaiseAction as CFString)
                }
                AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            }

            openApplicationViaWorkspaceAndFallback(bundleURL: standardizedTargetURL, isPWA: isPWA)
            scheduleCoalescedRefresh(delay: 0.20)
            return
        }

        openApplicationViaWorkspaceAndFallback(bundleURL: standardizedTargetURL, isPWA: isPWA)
        scheduleCoalescedRefresh(delay: 0.35)
    }

    private func openApplicationViaWorkspaceAndFallback(
        bundleURL: URL,
        isPWA: Bool,
        onActivated: (@MainActor @Sendable () -> Void)? = nil
    ) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.hidesOthers = false
        config.promptsUserIfNeeded = true

        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { [weak self] runningApp, error in
            if let runningApp, error == nil {
                DispatchQueue.main.async {
                    self?.activateRunningApp(runningApp, allWindows: true)
                    onActivated?()
                    self?.scheduleCoalescedRefresh(delay: 0.15)
                }
                if isPWA {
                    let pid = runningApp.processIdentifier
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                        if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
                            self?.launchViaOpenUtility(bundleURL: bundleURL)
                        }
                    }
                }
            } else {
                self?.launchViaOpenUtility(bundleURL: bundleURL)
            }
        }
    }

    private nonisolated func launchViaOpenUtility(bundleURL: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [bundleURL.standardizedFileURL.path(percentEncoded: false)]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
        }
    }

    public func openNewWindowForApplication(bundleURL: URL?, pid: pid_t) {
        if let app = NSRunningApplication(processIdentifier: pid),
           app.bundleIdentifier == Bundle.main.bundleIdentifier {
            GoogleAccountsManager.shared.openStandaloneFileExplorerWindow()
            return
        }
        if let bundleURL {
            openApplicationViaWorkspaceAndFallback(
                bundleURL: bundleURL,
                isPWA: TaskbarStringSanitizer.isWebAppPWA(bundleIdentifier: "", bundleURL: bundleURL)
            )
        }
    }

    public func isAppRunning(bundleIdentifier: String, bundlePath: String) -> Bool {
        // Búsqueda O(1) 100% en memoria (cero llamadas IPC a NSWorkspace ni syscalls `stat()` en cada redibujo de SwiftUI)
        if !runningBundleIDsLowercased.isEmpty || !runningBundlePathsLowercased.isEmpty {
            if !bundleIdentifier.isEmpty,
               runningBundleIDsLowercased.contains(bundleIdentifier.lowercased()) {
                return true
            }
            if !bundlePath.isEmpty {
                let normalizedKey = bundlePath
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    .lowercased()
                if runningBundlePathsLowercased.contains("/" + normalizedKey)
                    || runningBundlePathsLowercased.contains(bundlePath.lowercased()) {
                    return true
                }
            }
            return false
        }
        // Respaldo inicial solo antes del primer escaneo
        return NSWorkspace.shared.runningApplications.contains { app in
            guard !app.isTerminated, app.activationPolicy == .regular else { return false }
            if !bundleIdentifier.isEmpty,
               app.bundleIdentifier?.caseInsensitiveCompare(bundleIdentifier) == .orderedSame {
                return true
            }
            return false
        }
    }

    public func badgeLabel(
        forBundleIdentifier bundleIdentifier: String = "",
        appName: String,
        bundleURL: URL?,
        pid: pid_t? = nil
    ) -> String? {
        if let direct = Self.lookupBadge(
            in: badgeByAppKey,
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            bundleURL: bundleURL,
            pid: pid
        ) {
            return direct
        }
        // Respaldo: si alguna ventana abierta de esta misma app reportó badge por título (ej. PWA "(3) WhatsApp"), propagarlo al ícono fijado
        let lowerBID = bundleIdentifier.lowercased()
        let normPath = bundleURL.map(Self.normalizedBundlePathKey(for:))
        if let matchingWindow = windows.first(where: { win in
            guard let b = win.badgeLabel, !b.isEmpty else { return false }
            if let pid, win.pid == pid { return true }
            if !lowerBID.isEmpty && win.bundleIdentifier.lowercased() == lowerBID { return true }
            if let normPath, let wURL = win.appBundleURL, Self.normalizedBundlePathKey(for: wURL) == normPath { return true }
            return false
        }) {
            return matchingWindow.badgeLabel
        }
        return nil
    }

    public nonisolated static func normalizedBundlePathKey(for url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false).lowercased()
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    public nonisolated static func lookupBadge(
        in badges: [String: String],
        bundleIdentifier: String = "",
        appName: String,
        bundleURL: URL?,
        pid: pid_t? = nil
    ) -> String? {
        if let pid, let badge = badges["pid:\(pid)"], !badge.isEmpty {
            return badge
        }
        let lowerBID = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !lowerBID.isEmpty, let badge = badges["bid:\(lowerBID)"], !badge.isEmpty {
            return badge
        }
        if let url = bundleURL {
            let key = "path:\(normalizedBundlePathKey(for: url))"
            if let badge = badges[key], !badge.isEmpty {
                return badge
            }
        }
        let cleanName = TaskbarStringSanitizer.sanitizeDisplayName(appName).lowercased()
        if !cleanName.isEmpty, let badge = badges["name:\(cleanName)"], !badge.isEmpty {
            return badge
        }
        return nil
    }

    /// Extrae contadores de mensajes sin leer desde el título de la ventana para PWAs y apps de mensajería/correo
    /// (ej. `(3) WhatsApp`, `(12) Recibidos - Gmail`, `[2] Slack`), evitando falsos positivos en editores/exploradores.
    public nonisolated static func extractUnreadBadgeFromWindowTitle(
        _ title: String,
        bundleIdentifier: String,
        bundleURL: URL?
    ) -> String? {
        let trimmed = TaskbarStringSanitizer.sanitizeDisplayName(title)
        guard !trimmed.isEmpty else { return nil }

        let lowerID = bundleIdentifier.lowercased()
        let isEligibleApp: Bool = TaskbarStringSanitizer.isWebAppPWA(bundleIdentifier: bundleIdentifier, bundleURL: bundleURL)
            || lowerID.contains("whatsapp")
            || lowerID.contains("telegram")
            || lowerID.contains("discord")
            || lowerID.contains("slack")
            || lowerID.contains("signal")
            || lowerID.contains("teams")
            || lowerID.contains("messages")
            || lowerID.contains("mail")
            || lowerID.contains("messenger")
        guard isEligibleApp else { return nil }

        // Aceptar prefijos estándar `(3) ...`, `(99+) ...` o `[3] ...`
        guard let first = trimmed.first, first == "(" || first == "[" else { return nil }
        let closing: Character = (first == "(") ? ")" : "]"
        guard let closeIdx = trimmed.firstIndex(of: closing) else { return nil }
        let inner = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closeIdx])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inner.isEmpty, inner.count <= 4 else { return nil }

        let digitsPart = inner.hasSuffix("+") ? String(inner.dropLast()) : inner
        guard !digitsPart.isEmpty,
              digitsPart.allSatisfy(\.isASCII),
              digitsPart.allSatisfy(\.isNumber),
              let numeric = Int(digitsPart),
              numeric > 0 else {
            return nil
        }
        return inner
    }

    // MARK: - Lectura Multi-Fuente de Badges (Dock AX + LaunchServices StatusLabel)

    private enum LaunchServicesSymbols {
        typealias CopyRunningFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
        typealias CopyAppInfoFn = @convention(c) (Int32, CFTypeRef, CFArray?) -> Unmanaged<CFDictionary>?

        static let resolved: (copyRunning: CopyRunningFn, copyInfo: CopyAppInfoFn)? = {
            guard let handle = dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_LAZY),
                  let symRunning = dlsym(handle, "_LSCopyRunningApplicationArray"),
                  let symInfo = dlsym(handle, "_LSCopyApplicationInformation") else {
                return nil
            }
            return (
                unsafeBitCast(symRunning, to: CopyRunningFn.self),
                unsafeBitCast(symInfo, to: CopyAppInfoFn.self)
            )
        }()

        nonisolated(unsafe) static let requestedKeys: CFArray = [
            "StatusLabel", "pid", "CFBundleIdentifier", "LSBundlePath", "CFBundleName"
        ] as CFArray
    }

    /// Lee `StatusLabel` directamente desde LaunchServices solicitando únicamente las 5 claves necesarias
    /// (en lugar del diccionario completo de +50 claves por proceso) y reutilizando los símbolos resueltos una sola vez.
    private nonisolated static func fetchLaunchServicesBadgesOffMain() -> [String: String] {
        guard let syms = LaunchServicesSymbols.resolved,
              let asns = syms.copyRunning(-2)?.takeRetainedValue() as? [AnyObject] else {
            return [:]
        }

        let keys = LaunchServicesSymbols.requestedKeys
        var badges: [String: String] = [:]
        for asn in asns {
            guard let info = syms.copyInfo(-2, asn, keys)?.takeRetainedValue() as? [String: Any],
                  let statusDict = info["StatusLabel"] as? [String: Any] else {
                continue
            }

            let rawLabel: String?
            if let str = statusDict["label"] as? String {
                rawLabel = str
            } else if let num = statusDict["label"] as? NSNumber {
                rawLabel = num.intValue > 0 ? "\(num.intValue)" : nil
            } else {
                rawLabel = nil
            }

            guard let rawLabel else { continue }
            let cleanLabel = TaskbarStringSanitizer.sanitizeDisplayName(rawLabel)
            guard !cleanLabel.isEmpty else { continue }

            if let pidNum = info["pid"] as? NSNumber {
                badges["pid:\(pidNum.int32Value)"] = cleanLabel
            }
            if let bid = info["CFBundleIdentifier"] as? String, !bid.isEmpty {
                badges["bid:\(bid.lowercased())"] = cleanLabel
            }
            if let pathStr = info["LSBundlePath"] as? String, !pathStr.isEmpty {
                let norm = normalizedBundlePathKey(for: URL(fileURLWithPath: pathStr))
                badges["path:\(norm)"] = cleanLabel
            }
            if let name = info["CFBundleName"] as? String {
                let cleanName = TaskbarStringSanitizer.sanitizeDisplayName(name)
                if !cleanName.isEmpty {
                    badges["name:\(cleanName.lowercased())"] = cleanLabel
                }
            }
        }
        return badges
    }

    /// Lee badges directamente desde los ítems de `Dock.app` (necesario para apps Mac Catalyst como WhatsApp
    /// y apps que publican globos vía `UNUserNotificationCenter`). Devuelve `nil` si el Dock no respondió.
    private nonisolated static func fetchDockBadgesOffMain(dockPID: pid_t) -> [String: String]? {
        let dockElement = AXUIElementCreateApplication(dockPID)
        AXUIElementSetMessagingTimeout(dockElement, 0.45)
        guard let rootChildren = axElementArrayAttribute(dockElement, kAXChildrenAttribute) else {
            return nil
        }

        var dockItems: [AXUIElement] = []
        collectDockItems(from: rootChildren, depth: 0, into: &dockItems)

        var badges: [String: String] = [:]
        for dockItem in dockItems {
            AXUIElementSetMessagingTimeout(dockItem, 0.20)
            guard let statusLabel = axBadgeStringAttribute(dockItem), !statusLabel.isEmpty else {
                continue
            }
            if let urlValue = axURLAttribute(dockItem, kAXURLAttribute) {
                let normPath = normalizedBundlePathKey(for: urlValue)
                badges["path:\(normPath)"] = statusLabel
                if let bid = Bundle(url: urlValue)?.bundleIdentifier, !bid.isEmpty {
                    badges["bid:\(bid.lowercased())"] = statusLabel
                }
            }
            if let title = axStringAttribute(dockItem, kAXTitleAttribute) {
                let clean = TaskbarStringSanitizer.sanitizeDisplayName(title)
                if !clean.isEmpty {
                    badges["name:\(clean.lowercased())"] = statusLabel
                }
            }
        }
        return badges
    }

    private nonisolated static func collectDockItems(
        from elements: [AXUIElement],
        depth: Int,
        into result: inout [AXUIElement]
    ) {
        guard depth <= 3 else { return }
        for el in elements {
            AXUIElementSetMessagingTimeout(el, 0.25)
            let role = axStringAttribute(el, kAXRoleAttribute) ?? ""
            if role == "AXDockItem" {
                result.append(el)
            } else if role == (kAXListRole as String) || role == (kAXGroupRole as String) || role.isEmpty {
                if let sub = axElementArrayAttribute(el, kAXChildrenAttribute) {
                    collectDockItems(from: sub, depth: depth + 1, into: &result)
                }
            }
        }
    }

    private nonisolated static func axBadgeStringAttribute(_ element: AXUIElement) -> String? {
        for key in ["AXStatusLabel", "AXBadge", "AXBadgeValue"] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success,
                  let unwrapped = value else {
                continue
            }
            if let str = unwrapped as? String {
                let clean = TaskbarStringSanitizer.sanitizeDisplayName(str)
                if !clean.isEmpty { return clean }
            } else if let num = unwrapped as? NSNumber {
                if num.intValue > 0 { return "\(num.intValue)" }
            } else if let attr = unwrapped as? NSAttributedString {
                let clean = TaskbarStringSanitizer.sanitizeDisplayName(attr.string)
                if !clean.isEmpty { return clean }
            }
        }
        return nil
    }

    // MARK: - Helpers AX / CGWindowList (Seguros en Segundo Plano)

    private nonisolated static func fetchCGWindowSnapshots(onScreenOnly: Bool) -> [CGWindowSnapshotInfo] {
        var options: CGWindowListOption = [.excludeDesktopElements]
        if onScreenOnly {
            options.insert(.optionOnScreenOnly)
        }
        guard let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var result: [CGWindowSnapshotInfo] = []
        result.reserveCapacity(rawList.count)

        for dict in rawList {
            guard let windowNumber = dict[kCGWindowNumber as String] as? NSNumber,
                  let ownerPID = dict[kCGWindowOwnerPID as String] as? NSNumber else {
                continue
            }
            let layer = (dict[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            let alpha = (dict[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1.0
            let isOnScreen = (dict[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? onScreenOnly
            let title = (dict[kCGWindowName as String] as? String) ?? ""
            var bounds = CGRect.zero
            if let boundsDict = dict[kCGWindowBounds as String] as? NSDictionary {
                CGRectMakeWithDictionaryRepresentation(boundsDict, &bounds)
            }
            result.append(
                CGWindowSnapshotInfo(
                    windowID: CGWindowID(windowNumber.uint32Value),
                    pid: pid_t(ownerPID.int32Value),
                    layer: layer,
                    bounds: bounds,
                    alpha: alpha,
                    isOnScreen: isOnScreen,
                    title: title
                )
            )
        }
        return result
    }

    private nonisolated static func matchCGWindowID(
        pid: pid_t,
        frameAX: CGRect,
        title: String,
        candidates: [CGWindowSnapshotInfo]
    ) -> CGWindowID? {
        let samePID = candidates.filter { $0.pid == pid && $0.layer == 0 }
        guard !samePID.isEmpty else { return nil }

        if let exact = samePID.first(where: {
            abs($0.bounds.origin.x - frameAX.origin.x) <= 2 &&
            abs($0.bounds.origin.y - frameAX.origin.y) <= 2 &&
            abs($0.bounds.width - frameAX.width) <= 2 &&
            abs($0.bounds.height - frameAX.height) <= 2
        }) {
            return exact.windowID
        }

        if !title.isEmpty, let byTitle = samePID.first(where: { $0.title == title }) {
            return byTitle.windowID
        }
        return nil
    }

    private nonisolated static func isTrackableAXWindow(_ element: AXUIElement) -> Bool {
        let subrole = axStringAttribute(element, kAXSubroleAttribute) ?? ""
        if subrole == "AXSheet" ||
           subrole == "AXDrawer" ||
           subrole == (kAXSystemDialogSubrole as String) ||
           subrole == (kAXFloatingWindowSubrole as String) ||
           subrole == "AXPopover" ||
           subrole == "AXHelpTag" {
            return false
        }
        return true
    }

    nonisolated static func axWindowsAttribute(_ element: AXUIElement) -> [AXUIElement] {
        axWindowsAttributeResult(element).windows
    }

    nonisolated static func axWindowsAttributeResult(_ element: AXUIElement) -> (windows: [AXUIElement], timedOutOrFailed: Bool) {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value)
        if err == .success, let array = value as? [AXUIElement] {
            return (array, false)
        }
        if err == .attributeUnsupported || err == .noValue {
            return ([], false)
        }
        return ([], true)
    }

    nonisolated static func axElementArrayAttribute(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let array = value as? [AXUIElement] else {
            return nil
        }
        return array
    }

    nonisolated static func axElementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let unwrapped = value,
              CFGetTypeID(unwrapped) == AXUIElementGetTypeID() else {
            return nil
        }
        return (unwrapped as! AXUIElement)
    }

    nonisolated static func axStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    nonisolated static func axURLAttribute(_ element: AXUIElement, _ attribute: String) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        if let url = value as? URL {
            return url
        }
        if let cfURL = value as? NSURL {
            return cfURL as URL
        }
        if let str = value as? String, !str.isEmpty {
            return URL(string: str) ?? URL(fileURLWithPath: str)
        }
        return nil
    }

    nonisolated static func axBoolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? Bool
    }

    nonisolated static func axPointAttribute(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let axValue = value,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    nonisolated static func axSizeAttribute(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let axValue = value,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue(axValue as! AXValue, .cgSize, &size) else { return nil }
        return size
    }
}
