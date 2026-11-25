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

/// Redimensiona automáticamente ventanas normales cuyo borde inferior se superpone con la barra de tareas,
/// sin interferir durante arrastres activos ni bloquear jamás el hilo principal:
/// - Ventanas propias de `MacFileExplorer`: ajuste directo vía `NSWindow.setFrame` en `@MainActor` (cero AX).
/// - Ventanas de apps externas: ajuste AX en cola dedicada en segundo plano con timeout corto.
@MainActor
public final class TaskbarOverlapResizer {

    public static let shared = TaskbarOverlapResizer()

    private let resizeQueue = DispatchQueue(label: "com.macfileexplorer.taskbar.overlap-resizer", qos: .utility)

    /// Registro temporal por ID de ventana para evitar reintentos en bucle si la app impone una altura mínima mayor.
    private var lastAdjustmentAttemptByWindowID: [String: (frame: CGRect, timestamp: Date)] = [:]

    private init() {}

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
            activeIDs.contains($0.key) && now.timeIntervalSince($0.value.timestamp) < 10
        }

        var remoteJobs: [ResizerAXBox] = []

        for item in windows {
            guard !item.isFullScreen,
                  !item.isMinimized,
                  !item.isAppHidden,
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
                continue
            }

            // Evitar bucle si ya intentamos ajustar exactamente este mismo frame recientemente
            if let previous = lastAdjustmentAttemptByWindowID[item.id],
               abs(previous.frame.origin.y - item.frameAX.origin.y) < 2,
               abs(previous.frame.height - item.frameAX.height) < 2,
               now.timeIntervalSince(previous.timestamp) < 2.0 {
                continue
            }

            lastAdjustmentAttemptByWindowID[item.id] = (frame: item.frameAX, timestamp: now)

            if item.pid == selfPID {
                // Ventana propia de MacFileExplorer: ajustar vía NSWindow sin AX IPC
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
                    AXUIElementSetMessagingTimeout(job.element, 0.18)
                    var sizeSettable: DarwinBoolean = false
                    guard AXUIElementIsAttributeSettable(job.element, kAXSizeAttribute as CFString, &sizeSettable) == .success,
                          sizeSettable.boolValue else {
                        continue
                    }

                    if abs(job.targetFrameAX.origin.y - job.currentFrameAX.origin.y) >= 1 {
                        var newOrigin = job.targetFrameAX.origin
                        if let posValue = AXValueCreate(.cgPoint, &newOrigin) {
                            AXUIElementSetAttributeValue(job.element, kAXPositionAttribute as CFString, posValue)
                        }
                    }

                    var newSize = job.targetFrameAX.size
                    if let sizeValue = AXValueCreate(.cgSize, &newSize) {
                        AXUIElementSetAttributeValue(job.element, kAXSizeAttribute as CFString, sizeValue)
                    }
                }
            }
        }
    }

    public func resetState() {
        lastAdjustmentAttemptByWindowID.removeAll()
    }
}
