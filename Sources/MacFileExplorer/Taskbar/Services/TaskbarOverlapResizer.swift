import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation

private final class ResizerAXBox: @unchecked Sendable {
    let element: AXUIElement
    let currentFrameAX: CGRect
    let targetFrameAX: CGRect

    init(element: AXUIElement, currentFrameAX: CGRect, targetFrameAX: CGRect) {
        self.element = element
        self.currentFrameAX = currentFrameAX
        self.targetFrameAX = targetFrameAX
    }
}

private final class DirectAXCheckBox: @unchecked Sendable {
    let element: AXUIElement
    init(_ element: AXUIElement) {
        self.element = element
    }
}

/// Redimensiona automáticamente ventanas normales cuyo borde inferior se superpone con la barra de tareas,
/// con respuesta casi instantánea (~15–40 ms) al maximizar con doble clic, arrastrar o redimensionar,
/// sin interferir durante arrastres activos ni bloquear jamás el hilo principal:
/// - Ruta rápida A (AX directo): evalúa y ajusta el único `AXUIElement` que acaba de cambiar de tamaño/posición (< 2 ms).
/// - Ruta rápida B (Mouse-Up): al soltar doble clic o arrastre sobre otra app (ej. Chrome), verifica al instante la ventana enfocada.
/// - Ruta rápida C (Local): ventanas propias de `MacFileExplorer` ajustadas directo vía `NSWindow.setFrame` en `@MainActor`.
@MainActor
public final class TaskbarOverlapResizer {

    public static let shared = TaskbarOverlapResizer()

    /// Cola de alta prioridad (`.userInteractive`) para que el ajuste al maximizar Chrome u otra app sea inmediato.
    private let resizeQueue = DispatchQueue(label: "com.macfileexplorer.taskbar.overlap-resizer", qos: .userInteractive)

    /// Registro temporal por ID de ventana para evitar reintentos en bucle si la app impone una altura mínima mayor.
    private var lastAdjustmentAttemptByWindowID: [String: (frame: CGRect, timestamp: Date)] = [:]

    /// Monitores livianos de mouse para detectar fin de doble clic en barra de título o fin de arrastre/redimensionado.
    private var globalMouseDownMonitor: Any?
    private var globalMouseUpMonitor: Any?
    private var localMouseUpMonitor: Any?
    private var lastMouseDownLocation: NSPoint?
    private var deferredAXElementOnMouseUp: AXUIElement?
    private var hadGeometryEventWhileMouseDown = false
    private var pendingDirectCheckItems: [DispatchWorkItem] = []

    /// Proveedor de geometría actual de las barras visibles (inyectado por `TaskbarManager`).
    public var barContextProvider: (() -> (screens: [TaskbarScreenDescriptor], visibleBarDisplayIDs: Set<String>, barHeight: CGFloat))?

    private init() {}

    // MARK: - Ciclo de Vida de Monitores de Interacción (Mouse-Up / Doble Clic)

    public func syncInteractionMonitors() {
        let prefs = TaskbarPreferences.shared
        let shouldInstall = prefs.isEnabled && prefs.autoResizeOverlappingWindows
        if shouldInstall {
            installInteractionMonitorsIfNeeded()
        } else {
            removeInteractionMonitors()
        }
    }

    private func installInteractionMonitorsIfNeeded() {
        if globalMouseDownMonitor == nil {
            globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
                let location = NSEvent.mouseLocation
                Task { @MainActor [weak self] in
                    self?.lastMouseDownLocation = location
                    self?.hadGeometryEventWhileMouseDown = false
                }
            }
        }

        if globalMouseUpMonitor == nil {
            globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                let clickCount = event.clickCount
                let upLocation = NSEvent.mouseLocation
                Task { @MainActor [weak self] in
                    self?.handleExternalLeftMouseUp(clickCount: clickCount, upLocation: upLocation)
                }
            }
        }

        if localMouseUpMonitor == nil {
            localMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                let clickCount = event.clickCount
                let targetWindow = event.window
                Task { @MainActor [weak self] in
                    guard let self,
                          let targetWindow,
                          !(targetWindow is NSPanel),
                          clickCount >= 2 || self.hadGeometryEventWhileMouseDown else {
                        return
                    }
                    self.hadGeometryEventWhileMouseDown = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self, weak targetWindow] in
                        guard let self, let targetWindow else { return }
                        self.adjustLocalWindowImmediately(targetWindow)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self, weak targetWindow] in
                        guard let self, let targetWindow else { return }
                        self.adjustLocalWindowImmediately(targetWindow)
                    }
                }
                return event
            }
        }
    }

    private func removeInteractionMonitors() {
        if let m = globalMouseDownMonitor {
            NSEvent.removeMonitor(m)
            globalMouseDownMonitor = nil
        }
        if let m = globalMouseUpMonitor {
            NSEvent.removeMonitor(m)
            globalMouseUpMonitor = nil
        }
        if let m = localMouseUpMonitor {
            NSEvent.removeMonitor(m)
            localMouseUpMonitor = nil
        }
        cancelPendingDirectChecks()
        lastMouseDownLocation = nil
        deferredAXElementOnMouseUp = nil
        hadGeometryEventWhileMouseDown = false
    }

    private func handleExternalLeftMouseUp(clickCount: Int, upLocation: NSPoint) {
        let prefs = TaskbarPreferences.shared
        guard prefs.isEnabled,
              prefs.autoResizeOverlappingWindows,
              TaskbarWindowTracker.shared.isAccessibilityGranted else {
            return
        }

        let movedDistance: CGFloat = {
            guard let down = lastMouseDownLocation else { return 0 }
            return hypot(upLocation.x - down.x, upLocation.y - down.y)
        }()
        let wasDragOrMove = movedDistance >= 6 || hadGeometryEventWhileMouseDown
        let isDoubleClick = clickCount >= 2
        let deferredElement = deferredAXElementOnMouseUp

        lastMouseDownLocation = nil
        deferredAXElementOnMouseUp = nil
        hadGeometryEventWhileMouseDown = false

        // Solo actuar tras doble clic (maximizar barra de título), arrastre/redimensionado o cambio AX pendiente
        guard isDoubleClick || wasDragOrMove || deferredElement != nil else { return }

        if let deferredElement {
            scheduleDirectAXCheck(for: deferredElement, delays: [0.015, 0.14])
        } else {
            // Doble clic en Chrome u otra app: consultar la ventana enfocada del proceso activo
            scheduleFrontmostFocusedWindowCheck(delays: isDoubleClick ? [0.02, 0.12, 0.26] : [0.02, 0.15])
        }
    }

    // MARK: - Ruta Rápida A: Evento AX directo sobre una ventana específica

    /// Invocado de inmediato desde `AXObserver` cuando una ventana externa cambia de tamaño, posición o se crea.
    public func handleAXWindowGeometryEvent(element: AXUIElement) {
        let prefs = TaskbarPreferences.shared
        guard prefs.isEnabled,
              prefs.autoResizeOverlappingWindows,
              TaskbarWindowTracker.shared.isAccessibilityGranted else {
            return
        }

        // Si el usuario está arrastrando/redimensionando activamente con el mouse, diferir hasta `leftMouseUp`
        if NSEvent.pressedMouseButtons != 0 {
            hadGeometryEventWhileMouseDown = true
            deferredAXElementOnMouseUp = element
            return
        }

        // Ejecutar ajuste inmediato (~15 ms) y un re-chequeo breve por si la animación de zoom de macOS sigue corriendo
        scheduleDirectAXCheck(for: element, delays: [0.015, 0.16])
    }

    // MARK: - Ruta Rápida C: Ventana propia de `MacFileExplorer`

    /// Ajusta en 0 ms una ventana nativa de `MacFileExplorer` tras redimensionarse o maximizarse.
    public func adjustLocalWindowImmediately(_ window: NSWindow) {
        let prefs = TaskbarPreferences.shared
        guard prefs.isEnabled,
              prefs.autoResizeOverlappingWindows,
              NSEvent.pressedMouseButtons == 0,
              !(window is NSPanel),
              window.isVisible,
              !window.isMiniaturized,
              !window.styleMask.contains(.fullScreen),
              window.styleMask.contains(.resizable),
              let ctx = barContextProvider?(),
              !ctx.visibleBarDisplayIDs.isEmpty else {
            return
        }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 900
        let frameAX = TaskbarGeometry.cocoaRectToAX(window.frame, primaryScreenHeight: primaryHeight)
        let screenID = TaskbarGeometry.assignScreenID(forWindowFrameAX: frameAX, screens: ctx.screens)
        guard ctx.visibleBarDisplayIDs.contains(screenID),
              let screen = ctx.screens.first(where: { $0.id == screenID }),
              let targetFrameAX = TaskbarGeometry.adjustedFrameAvoidingTaskbar(
                  windowFrameAX: frameAX,
                  screenFrameAX: screen.frameAX,
                  barHeight: ctx.barHeight,
                  isFullScreen: false,
                  isMinimized: false
              ) else {
            return
        }

        let cocoaFrame = TaskbarGeometry.axRectToCocoa(targetFrameAX, primaryScreenHeight: primaryHeight)
        window.setFrame(cocoaFrame, display: true, animate: false)
    }

    // MARK: - Helpers de Rutas Rápidas (`.userInteractive`)

    private func cancelPendingDirectChecks() {
        for item in pendingDirectCheckItems {
            item.cancel()
        }
        pendingDirectCheckItems.removeAll()
    }

    private func scheduleDirectAXCheck(for element: AXUIElement, delays: [TimeInterval]) {
        cancelPendingDirectChecks()
        let box = DirectAXCheckBox(element)
        for delay in delays {
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor [weak self] in
                    self?.performDirectAXCheck(box: box)
                }
            }
            pendingDirectCheckItems.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func scheduleFrontmostFocusedWindowCheck(delays: [TimeInterval]) {
        cancelPendingDirectChecks()
        for delay in delays {
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor [weak self] in
                    self?.performFrontmostFocusedWindowCheck()
                }
            }
            pendingDirectCheckItems.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func performDirectAXCheck(box: DirectAXCheckBox) {
        let prefs = TaskbarPreferences.shared
        guard prefs.isEnabled,
              prefs.autoResizeOverlappingWindows,
              NSEvent.pressedMouseButtons == 0,
              let ctx = barContextProvider?(),
              !ctx.visibleBarDisplayIDs.isEmpty else {
            return
        }

        let screens = ctx.screens
        let visibleBarDisplayIDs = ctx.visibleBarDisplayIDs
        let barHeight = ctx.barHeight

        resizeQueue.async {
            Self.inspectAndAdjustAXWindowIfOverlapping(
                box.element,
                screens: screens,
                visibleBarDisplayIDs: visibleBarDisplayIDs,
                barHeight: barHeight
            )
        }
    }

    private func performFrontmostFocusedWindowCheck() {
        let prefs = TaskbarPreferences.shared
        guard prefs.isEnabled,
              prefs.autoResizeOverlappingWindows,
              NSEvent.pressedMouseButtons == 0,
              let ctx = barContextProvider?(),
              !ctx.visibleBarDisplayIDs.isEmpty,
              let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.activationPolicy == .regular else {
            return
        }

        let selfPID = ProcessInfo.processInfo.processIdentifier
        if frontApp.processIdentifier == selfPID {
            if let keyWin = NSApp.keyWindow ?? NSApp.mainWindow {
                adjustLocalWindowImmediately(keyWin)
            }
            return
        }

        let pid = frontApp.processIdentifier
        let screens = ctx.screens
        let visibleBarDisplayIDs = ctx.visibleBarDisplayIDs
        let barHeight = ctx.barHeight

        resizeQueue.async {
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, 0.14)
            var focusedRef: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedRef)
            let windowElement: AXUIElement?
            if err == .success, let ref = focusedRef, CFGetTypeID(ref) == AXUIElementGetTypeID() {
                windowElement = unsafeDowncast(ref, to: AXUIElement.self)
            } else {
                var mainRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainRef) == .success,
                   let ref = mainRef, CFGetTypeID(ref) == AXUIElementGetTypeID() {
                    windowElement = unsafeDowncast(ref, to: AXUIElement.self)
                } else {
                    windowElement = nil
                }
            }

            if let windowElement {
                Self.inspectAndAdjustAXWindowIfOverlapping(
                    windowElement,
                    screens: screens,
                    visibleBarDisplayIDs: visibleBarDisplayIDs,
                    barHeight: barHeight
                )
            }
        }
    }

    /// Consulta de ultra-baja latencia (< 2 ms) sobre un único `AXUIElement` y lo ajusta en el acto si pisa la barra.
    private nonisolated static func inspectAndAdjustAXWindowIfOverlapping(
        _ rawElement: AXUIElement,
        screens: [TaskbarScreenDescriptor],
        visibleBarDisplayIDs: Set<String>,
        barHeight: CGFloat
    ) {
        AXUIElementSetMessagingTimeout(rawElement, 0.15)

        // Si la notificación AX llegó sobre un subelemento, subir a su `AXWindow` contenedor si existe
        var targetElement = rawElement
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(rawElement, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String,
           role != (kAXWindowRole as String) {
            var winRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(rawElement, kAXWindowAttribute as CFString, &winRef) == .success,
               let ref = winRef, CFGetTypeID(ref) == AXUIElementGetTypeID() {
                targetElement = unsafeDowncast(ref, to: AXUIElement.self)
                AXUIElementSetMessagingTimeout(targetElement, 0.15)
            } else {
                return
            }
        }

        // Ignorar minimizadas o en pantalla completa nativa
        var minRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(targetElement, kAXMinimizedAttribute as CFString, &minRef) == .success,
           let isMin = minRef as? Bool, isMin {
            return
        }
        var fsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(targetElement, "AXFullScreen" as CFString, &fsRef) == .success,
           let isFS = fsRef as? Bool, isFS {
            return
        }

        guard let origin = TaskbarWindowTracker.axPointAttribute(targetElement, kAXPositionAttribute as String),
              let size = TaskbarWindowTracker.axSizeAttribute(targetElement, kAXSizeAttribute as String),
              size.width >= 100, size.height >= 60 else {
            return
        }

        let currentFrameAX = CGRect(origin: origin, size: size)
        let screenID = TaskbarGeometry.assignScreenID(forWindowFrameAX: currentFrameAX, screens: screens)
        guard visibleBarDisplayIDs.contains(screenID),
              let screen = screens.first(where: { $0.id == screenID }),
              let targetFrameAX = TaskbarGeometry.adjustedFrameAvoidingTaskbar(
                  windowFrameAX: currentFrameAX,
                  screenFrameAX: screen.frameAX,
                  barHeight: barHeight,
                  isFullScreen: false,
                  isMinimized: false
              ) else {
            return
        }

        applyAXFrameAdjustment(element: targetElement, currentFrameAX: currentFrameAX, targetFrameAX: targetFrameAX)
    }

    private nonisolated static func applyAXFrameAdjustment(
        element: AXUIElement,
        currentFrameAX: CGRect,
        targetFrameAX: CGRect
    ) {
        AXUIElementSetMessagingTimeout(element, 0.18)
        var sizeSettable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &sizeSettable) == .success,
              sizeSettable.boolValue else {
            return
        }

        if abs(targetFrameAX.origin.y - currentFrameAX.origin.y) >= 1 {
            var newOrigin = targetFrameAX.origin
            if let posValue = AXValueCreate(.cgPoint, &newOrigin) {
                AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, posValue)
            }
        }

        var newSize = targetFrameAX.size
        if let sizeValue = AXValueCreate(.cgSize, &newSize) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        }
    }

    // MARK: - Barrido Completo de Respaldo (tras escaneo o cambio de pantallas/preferencias)

    /// Evalúa las ventanas actuales y ajusta aquellas que se superpongan con alguna barra visible.
    public func adjustOverlappingWindowsIfNeeded(
        windows: [TaskbarWindowItem],
        screens: [TaskbarScreenDescriptor],
        visibleBarDisplayIDs: Set<String>,
        barHeight: CGFloat
    ) {
        let prefs = TaskbarPreferences.shared
        guard prefs.isEnabled,
              prefs.autoResizeOverlappingWindows,
              TaskbarWindowTracker.shared.isAccessibilityGranted else {
            return
        }

        // Nunca redimensionar mientras el usuario está arrastrando/redimensionando con el mouse
        guard NSEvent.pressedMouseButtons == 0 else { return }

        let selfPID = ProcessInfo.processInfo.processIdentifier
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 900
        let screenByID = Dictionary(uniqueKeysWithValues: screens.map { ($0.id, $0) })
        let now = Date()

        // Limpiar registros antiguos de ventanas cerradas
        let activeIDs = Set(windows.map(\.id))
        lastAdjustmentAttemptByWindowID = lastAdjustmentAttemptByWindowID.filter {
            activeIDs.contains($0.key) && now.timeIntervalSince($0.value.timestamp) < 6
        }

        var remoteJobs: [ResizerAXBox] = []

        for item in windows {
            guard !item.isFullScreen,
                  !item.isMinimized,
                  !item.isAppHidden,
                  !item.isWindowlessApp,
                  visibleBarDisplayIDs.contains(item.screenID),
                  let screen = screenByID[item.screenID] else {
                continue
            }

            guard let targetFrame = TaskbarGeometry.adjustedFrameAvoidingTaskbar(
                windowFrameAX: item.frameAX,
                screenFrameAX: screen.frameAX,
                barHeight: barHeight,
                isFullScreen: item.isFullScreen,
                isMinimized: item.isMinimized
            ) else {
                // La ventana ya no se superpone: limpiar cualquier registro previo para que un nuevo maximizado sea instantáneo
                lastAdjustmentAttemptByWindowID.removeValue(forKey: item.id)
                continue
            }

            // Evitar bucle solo si esta ventana sigue bloqueada en exactamente este mismo frame tras un intento reciente
            if let previous = lastAdjustmentAttemptByWindowID[item.id],
               abs(previous.frame.origin.y - item.frameAX.origin.y) < 2,
               abs(previous.frame.height - item.frameAX.height) < 2,
               now.timeIntervalSince(previous.timestamp) < 0.75 {
                continue
            }

            lastAdjustmentAttemptByWindowID[item.id] = (frame: item.frameAX, timestamp: now)

            if item.pid == selfPID {
                if let localWin = TaskbarWindowTracker.shared.localWindow(for: item.id),
                   localWin.styleMask.contains(.resizable) {
                    let cocoaFrame = TaskbarGeometry.axRectToCocoa(targetFrame, primaryScreenHeight: primaryHeight)
                    localWin.setFrame(cocoaFrame, display: true, animate: false)
                }
            } else if let axWindow = TaskbarWindowTracker.shared.axElement(for: item.id) {
                remoteJobs.append(ResizerAXBox(element: axWindow, currentFrameAX: item.frameAX, targetFrameAX: targetFrame))
            }
        }

        if !remoteJobs.isEmpty {
            let jobsToRun = remoteJobs
            resizeQueue.async {
                for job in jobsToRun {
                    Self.applyAXFrameAdjustment(
                        element: job.element,
                        currentFrameAX: job.currentFrameAX,
                        targetFrameAX: job.targetFrameAX
                    )
                }
            }
        }
    }

    public func resetState() {
        removeInteractionMonitors()
        lastAdjustmentAttemptByWindowID.removeAll()
    }
}
