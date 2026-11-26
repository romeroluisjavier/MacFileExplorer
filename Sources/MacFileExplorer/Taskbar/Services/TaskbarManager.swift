import AppKit
import CoreGraphics
import Foundation
import Observation
import SwiftUI

/// Orquestador central de la Barra de tareas estilo Windows en `MacFileExplorer`.
/// Administra paneles multimonitor (hasta 5 pantallas), visibilidad por pantalla completa,
/// sincronización con `TaskbarWindowTracker`, auto-redimensionamiento y ciclo de vida seguro del Dock.
@MainActor
@Observable
public final class TaskbarManager {

    public static let shared = TaskbarManager()

    /// ID de ventana siendo arrastrada horizontalmente en la barra (para feedback visual en tiempo real).
    public var draggingWindowID: String?

    /// ID de app fijada siendo arrastrada horizontalmente.
    public var draggingPinnedAppID: String?

    /// ID de la pantalla donde actualmente está abierto el Menú Inicio (si alguno).
    public var openStartMenuDisplayID: String?

    /// Paneles flotantes activos por `displayID` (máximo 5 monitores).
    private var panelsByDisplayID: [String: TaskbarPanel] = [:]
    private var isInstalled = false
    private var isSyncingEnabled = false

    private init() {}

    // MARK: - Instalación y Ciclo de Vida

    public func installIfNeeded() {
        guard !isInstalled else { return }
        isInstalled = true

        let prefs = TaskbarPreferences.shared
        prefs.onEnabledChanged = { [weak self] enabled in
            self?.applyEnabledState(enabled, allowSetupPrompt: true)
        }
        prefs.onAppearanceOrLayoutChanged = { [weak self] in
            self?.rebuildBarPanels()
            TaskbarWindowTracker.shared.reapplyWindowOrderingImmediately()
            TaskbarOverlapResizer.shared.syncInteractionMonitors()
            self?.triggerOverlapResizeCheck()
        }
        prefs.onWindowFilteringChanged = { [weak self] in
            TaskbarWindowTracker.shared.reapplyWindowOrderingImmediately()
            TaskbarWindowTracker.shared.refreshNow()
            TaskbarOverlapResizer.shared.syncInteractionMonitors()
            self?.triggerOverlapResizeCheck()
        }

        TaskbarWindowTracker.shared.registerOwnedWindowNumbersProvider(key: "taskbar") { [weak self] in
            self?.ownedWindowNumbers ?? []
        }
        TaskbarOverlapResizer.shared.barContextProvider = { [weak self] in
            guard let self else { return ([], [], 0) }
            let prefs = TaskbarPreferences.shared
            let fullScreenIDs = TaskbarWindowTracker.shared.fullScreenDisplayIDs
            let visibleBarDisplayIDs = Set(self.panelsByDisplayID.keys.filter { !fullScreenIDs.contains($0) })
            let reservedBarHeight = CGFloat(prefs.barHeight) + (prefs.barStyle == .floatingIsland ? 6 : 0)
            return (TaskbarWindowTracker.shared.connectedScreens, visibleBarDisplayIDs, reservedBarHeight)
        }
        TaskbarWindowTracker.shared.onWindowGeometryPotentiallyChanged = { [weak self] in
            self?.triggerOverlapResizeCheck()
        }
        TaskbarWindowTracker.shared.onAXWindowGeometryChanged = { element in
            TaskbarOverlapResizer.shared.handleAXWindowGeometryEvent(element: element)
        }
        TaskbarWindowTracker.shared.onLocalWindowGeometryChanged = { window in
            TaskbarOverlapResizer.shared.adjustLocalWindowImmediately(window)
        }

        // Arranca desactivada por defecto (`startEnabledByDefault == false`), salvo que el usuario
        // haya habilitado explícitamente en Configuración arrancar con la barra activa.
        if prefs.isEnabled {
            applyEnabledState(true, allowSetupPrompt: false)
        }
    }

    /// Cambia el estado de la barra de tareas desde menús o botones de configuración.
    public func setEnabled(_ enabled: Bool, allowSetupPrompt: Bool = true) {
        let prefs = TaskbarPreferences.shared
        if prefs.isEnabled != enabled {
            isSyncingEnabled = true
            prefs.isEnabled = enabled
            isSyncingEnabled = false
        }
        applyEnabledState(enabled, allowSetupPrompt: allowSetupPrompt)
    }

    private func applyEnabledState(_ enabled: Bool, allowSetupPrompt: Bool) {
        guard !isSyncingEnabled else { return }

        if enabled {
            WindowServicesKeepAlive.shared.acquire(for: .taskbar)
            TaskbarAppCatalogService.shared.refreshCatalogIfNeeded()
            TaskbarWindowTracker.shared.acquireMonitoring(for: .taskbar)
            TaskbarDockManager.shared.reapplyDockModeIfNeededOnEnable()
            rebuildBarPanels()
            TaskbarOverlapResizer.shared.syncInteractionMonitors()
            triggerOverlapResizeCheck()

            let prefs = TaskbarPreferences.shared
            let hasAX = TaskbarWindowTracker.shared.checkAccessibilityPermission(prompt: false)
            if allowSetupPrompt && (!prefs.hasCompletedSetup || !hasAX) {
                TaskbarSetupWizardWindowController.shared.show()
            }
        } else {
            TaskbarPreviewPanelController.shared.hideImmediately()
            TaskbarPinnedOrderHintController.shared.hideImmediately()
            TaskbarStartMenuController.shared.close()
            destroyAllBarPanels()
            TaskbarWindowTracker.shared.releaseMonitoring(for: .taskbar)
            TaskbarOverlapResizer.shared.resetState()
            if !AltTabPreferences.shared.isEnabled {
                TaskbarThumbnailService.shared.clearCache()
            }
            WindowServicesKeepAlive.shared.release(for: .taskbar)
            // Garantizar que si el usuario había ocultado el Dock por completo, el Dock vuelva a responder
            TaskbarDockManager.shared.revertFullyHiddenIfNeededForDisableOrQuit()
        }

        StatusBarManager.shared.refreshTooltipAndMenu()
    }

    /// Invocado antes de cerrar `MacFileExplorer` para limpiar observadores y restaurar Dock si estaba en `fullyHidden`.
    public func prepareForTermination() {
        TaskbarPreviewPanelController.shared.hideImmediately()
        TaskbarPinnedOrderHintController.shared.hideImmediately()
        TaskbarStartMenuController.shared.close()
        destroyAllBarPanels()
        TaskbarOverlapResizer.shared.resetState()
        TaskbarWindowTracker.shared.releaseMonitoring(for: .taskbar)
        WindowServicesKeepAlive.shared.release(for: .taskbar)
        TaskbarDockManager.shared.revertFullyHiddenIfNeededForDisableOrQuit()
    }

    // MARK: - Monitores y Ventanas Visibles por Barra

    public var ownedWindowNumbers: Set<Int> {
        var numbers = Set(panelsByDisplayID.values.map(\.windowNumber))
        if let previewNum = TaskbarPreviewPanelController.shared.panelWindowNumber {
            numbers.insert(previewNum)
        }
        if let startNum = TaskbarStartMenuController.shared.panelWindowNumber {
            numbers.insert(startNum)
        }
        if let hintNum = TaskbarPinnedOrderHintController.shared.panelWindowNumber {
            numbers.insert(hintNum)
        }
        return numbers
    }

    /// Devuelve los monitores elegibles para mostrar barra (hasta 5 monitores según `displayMode` y `hiddenDisplayIDs`).
    public func eligibleScreens() -> [TaskbarScreenDescriptor] {
        let prefs = TaskbarPreferences.shared
        let all = Array(TaskbarWindowTracker.shared.connectedScreens.prefix(5))
        guard !all.isEmpty else { return [] }

        let scoped: [TaskbarScreenDescriptor]
        switch prefs.displayMode {
        case .allDisplays:
            scoped = all
        case .mainDisplayOnly:
            scoped = all.first.map { [$0] } ?? []
        }

        return scoped.filter { !prefs.hiddenDisplayIDs.contains($0.id) }
    }

    /// Devuelve las ventanas que deben mostrarse en la barra del monitor `displayID`.
    public func windowsForDisplay(_ displayID: String) -> [TaskbarWindowItem] {
        let allWindows = TaskbarWindowTracker.shared.windows
        switch TaskbarPreferences.shared.windowScopeMode {
        case .allWindowsOnAllBars:
            return allWindows
        case .perDisplay:
            return allWindows.filter { $0.screenID == displayID }
        }
    }

    public func handleScreensChanged() {
        guard TaskbarPreferences.shared.isEnabled else { return }
        TaskbarPreviewPanelController.shared.hideImmediately()
        TaskbarStartMenuController.shared.close()
        rebuildBarPanels()
        triggerOverlapResizeCheck()
    }

    public func rebuildBarPanels() {
        guard TaskbarPreferences.shared.isEnabled else {
            destroyAllBarPanels()
            return
        }

        let prefs = TaskbarPreferences.shared
        let screens = eligibleScreens()
        let activeIDs = Set(screens.map(\.id))

        // Quitar paneles de monitores desconectados u ocultos
        for (displayID, panel) in panelsByDisplayID where !activeIDs.contains(displayID) {
            panel.orderOut(nil)
            panel.close()
            panelsByDisplayID.removeValue(forKey: displayID)
        }

        let barHeight = CGFloat(prefs.barHeight)
        let isFloating = (prefs.barStyle == .floatingIsland)
        let fullScreenIDs = TaskbarWindowTracker.shared.fullScreenDisplayIDs

        for screen in screens {
            let horizInset: CGFloat = isFloating ? min(14, screen.frameCocoa.width * 0.01) : 0
            let bottomInset: CGFloat = isFloating ? 6 : 0
            let targetFrame = NSRect(
                x: round(screen.frameCocoa.minX + horizInset),
                y: round(screen.frameCocoa.minY + bottomInset),
                width: round(max(240, screen.frameCocoa.width - horizInset * 2)),
                height: round(barHeight)
            )

            let panel: TaskbarPanel
            if let existing = panelsByDisplayID[screen.id] {
                panel = existing
            } else {
                let created = TaskbarPanel(displayID: screen.id, contentRect: targetFrame)
                let rootView = TaskbarBarView(displayID: screen.id)
                let hostingView = NSHostingView(rootView: rootView)
                hostingView.autoresizingMask = [.width, .height]
                created.contentView = hostingView
                panelsByDisplayID[screen.id] = created
                panel = created
            }

            panel.applyThemeAppearance(prefs.themeMode)
            panel.hasShadow = isFloating
            if panel.frame != targetFrame {
                panel.setFrame(targetFrame, display: true)
            }
            if isFloating {
                panel.invalidateShadow()
            }

            if fullScreenIDs.contains(screen.id) {
                panel.orderOut(nil)
            } else {
                panel.orderFrontRegardless()
            }
        }
    }

    public func updateFullScreenVisibility() {
        guard TaskbarPreferences.shared.isEnabled else { return }
        let fullScreenIDs = TaskbarWindowTracker.shared.fullScreenDisplayIDs
        for (displayID, panel) in panelsByDisplayID {
            if fullScreenIDs.contains(displayID) {
                panel.orderOut(nil)
            } else if !panel.isVisible {
                panel.orderFrontRegardless()
            }
        }
    }

    public func refreshLocalizedUI() {
        guard TaskbarPreferences.shared.isEnabled else { return }
        rebuildBarPanels()
    }

    public func triggerOverlapResizeCheck() {
        let prefs = TaskbarPreferences.shared
        guard prefs.isEnabled, prefs.autoResizeOverlappingWindows else { return }
        let fullScreenIDs = TaskbarWindowTracker.shared.fullScreenDisplayIDs
        let visibleBarDisplayIDs = Set(panelsByDisplayID.keys.filter { !fullScreenIDs.contains($0) })
        let reservedBarHeight = CGFloat(prefs.barHeight) + (prefs.barStyle == .floatingIsland ? 6 : 0)
        TaskbarOverlapResizer.shared.adjustOverlappingWindowsIfNeeded(
            windows: TaskbarWindowTracker.shared.windows,
            screens: TaskbarWindowTracker.shared.connectedScreens,
            visibleBarDisplayIDs: visibleBarDisplayIDs,
            barHeight: reservedBarHeight
        )
    }

    public func barFrame(for displayID: String) -> NSRect? {
        panelsByDisplayID[displayID]?.frame
    }

    public func toggleStartMenu(for displayID: String? = nil) {
        let resolvedDisplayID = displayID
            ?? eligibleScreens().first?.id
            ?? TaskbarWindowTracker.shared.connectedScreens.first?.id
            ?? "primary"
        let anchorRect: NSRect
        if let barFrame = panelsByDisplayID[resolvedDisplayID]?.frame {
            anchorRect = NSRect(x: barFrame.minX + 6, y: barFrame.minY, width: 42, height: barFrame.height)
        } else if let screen = NSScreen.main ?? NSScreen.screens.first {
            anchorRect = NSRect(x: screen.visibleFrame.minX + 6, y: screen.visibleFrame.minY, width: 42, height: 42)
        } else {
            anchorRect = NSRect(x: 20, y: 20, width: 42, height: 42)
        }
        TaskbarStartMenuController.shared.toggle(displayID: resolvedDisplayID, anchorButtonRect: anchorRect)
    }

    private func destroyAllBarPanels() {
        for (_, panel) in panelsByDisplayID {
            panel.orderOut(nil)
            panel.close()
        }
        panelsByDisplayID.removeAll()
    }
}
