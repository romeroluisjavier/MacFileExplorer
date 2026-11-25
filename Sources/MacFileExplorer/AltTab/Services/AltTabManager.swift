import AppKit
import CoreGraphics
import Foundation
import Observation

public enum AltTabNavigationDirection: Sendable {
    case left
    case right
    case up
    case down
}

/// Orquestador central de **AltTab** en `MacFileExplorer`.
/// Reutiliza el motor compartido (`TaskbarWindowTracker`, `TaskbarThumbnailService`, `WindowServicesKeepAlive`)
/// para cero duplicación y latencia de apertura `< 16 ms`.
@MainActor
@Observable
public final class AltTabManager {

    public static let shared = AltTabManager()

    public private(set) var isSwitcherOpen: Bool = false
    public private(set) var activeProfile: AltTabShortcutProfile?
    public private(set) var displayedWindows: [TaskbarWindowItem] = []
    public private(set) var selectedIndex: Int = 0
    public private(set) var layoutMetrics: AltTabLayoutMetrics = AltTabLayoutMetrics(
        columns: 1, rows: 1, cellWidth: 240, cellHeight: 180, panelWidth: 500, panelHeight: 240
    )

    public var isSearchActive: Bool = false
    public var searchQuery: String = "" {
        didSet {
            guard isSwitcherOpen, searchQuery != oldValue else { return }
            refilterCurrentSession(preserveSelectionID: selectedWindow?.id)
        }
    }

    private var isInstalled = false
    private var isSyncingEnabled = false
    private var sessionFrontmostPID: pid_t?
    private var sessionMouseScreenID: String?
    private var sessionMainScreenID: String?
    private var sessionTargetScreenFrameCocoa: NSRect = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    private var batchThumbnailTask: Task<Void, Never>?

    private init() {}

    public var selectedWindow: TaskbarWindowItem? {
        guard selectedIndex >= 0, selectedIndex < displayedWindows.count else { return nil }
        return displayedWindows[selectedIndex]
    }

    public var ownedWindowNumbers: Set<Int> {
        var numbers: Set<Int> = []
        if let hudNum = AltTabSwitcherPanelController.shared.panelWindowNumber {
            numbers.insert(hudNum)
        }
        if let previewNum = AltTabFullPreviewPanelController.shared.panelWindowNumber {
            numbers.insert(previewNum)
        }
        return numbers
    }

    // MARK: - Instalación y Ciclo de Vida

    public func installIfNeeded() {
        guard !isInstalled else { return }
        isInstalled = true

        let prefs = AltTabPreferences.shared
        prefs.onEnabledChanged = { [weak self] enabled in
            self?.applyEnabledState(enabled, promptIfMissingPermission: true)
        }
        prefs.onShortcutsChanged = {
            AltTabHotkeyMonitor.shared.retryInstallationIfNeeded()
        }

        TaskbarWindowTracker.shared.registerOwnedWindowNumbersProvider(key: "alttab") { [weak self] in
            self?.ownedWindowNumbers ?? []
        }

        if prefs.isEnabled {
            applyEnabledState(true, promptIfMissingPermission: false)
        }
    }

    public func setEnabled(_ enabled: Bool, promptIfMissingPermission: Bool = true) {
        let prefs = AltTabPreferences.shared
        if prefs.isEnabled != enabled {
            isSyncingEnabled = true
            prefs.isEnabled = enabled
            isSyncingEnabled = false
        }
        applyEnabledState(enabled, promptIfMissingPermission: promptIfMissingPermission)
    }

    private func applyEnabledState(_ enabled: Bool, promptIfMissingPermission: Bool) {
        guard !isSyncingEnabled else { return }

        if enabled {
            WindowServicesKeepAlive.shared.acquire(for: .altTab)
            TaskbarWindowTracker.shared.acquireMonitoring(for: .altTab)
            AltTabSwitcherPanelController.shared.prewarmPanel()
            AltTabFullPreviewPanelController.shared.prewarmPanel()
            AltTabHotkeyMonitor.shared.start()

            if promptIfMissingPermission && !TaskbarWindowTracker.shared.checkAccessibilityPermission(prompt: false) {
                AltTabSettingsWindowController.shared.show(tab: .general)
            }
        } else {
            cancelSwitcher()
            AltTabHotkeyMonitor.shared.stop()
            TaskbarWindowTracker.shared.releaseMonitoring(for: .altTab)
            if !TaskbarPreferences.shared.isEnabled {
                TaskbarThumbnailService.shared.clearCache()
            }
            WindowServicesKeepAlive.shared.release(for: .altTab)
        }

        StatusBarManager.shared.refreshTooltipAndMenu()
    }

    public func prepareForTermination() {
        cancelSwitcher()
        AltTabHotkeyMonitor.shared.stop()
        TaskbarWindowTracker.shared.releaseMonitoring(for: .altTab)
        WindowServicesKeepAlive.shared.release(for: .altTab)
    }

    // MARK: - Apertura y Navegación del Selector (< 16 ms)

    public func openOrStep(profile: AltTabShortcutProfile, reverse: Bool) {
        if isSwitcherOpen {
            stepSelection(reverse: reverse)
            return
        }
        beginSession(profile: profile, reverse: reverse, forceKeepOpen: false)
    }

    public func switchProfileWhileOpen(profile: AltTabShortcutProfile, reverse: Bool) {
        activeProfile = profile
        refilterCurrentSession(preserveSelectionID: nil)
        selectedIndex = AltTabLayoutEngine.initialSelectionIndex(windowCount: displayedWindows.count, reverse: reverse)
        presentFullSizePreviewForSelection()
    }

    /// Abre el selector en modo interactivo desde el menú superior o Ajustes para probar estilos y buscar libremente.
    public func openInteractiveTestSwitcher() {
        let base = AltTabPreferences.shared.shortcutProfiles.first ?? AltTabShortcutProfile.makeDefaultProfiles()[0]
        var demoProfile = base
        demoProfile.releaseBehavior = .keepOpenUntilConfirmed
        // Asegurar que el tracker tenga snapshot fresco si AltTab estaba apagado
        if !AltTabPreferences.shared.isEnabled {
            TaskbarWindowTracker.shared.acquireMonitoring(for: .altTab)
            TaskbarWindowTracker.shared.refreshNow()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.beginSession(profile: demoProfile, reverse: false, forceKeepOpen: true)
            }
        } else {
            beginSession(profile: demoProfile, reverse: false, forceKeepOpen: true)
        }
    }

    private func beginSession(profile: AltTabShortcutProfile, reverse: Bool, forceKeepOpen: Bool) {
        // Ocultar popups de Taskbar si estuvieran visibles para evitar solapamientos
        TaskbarPreviewPanelController.shared.hideImmediately()
        TaskbarStartMenuController.shared.close()

        var effectiveProfile = profile
        if forceKeepOpen {
            effectiveProfile.releaseBehavior = .keepOpenUntilConfirmed
        }

        let tracker = TaskbarWindowTracker.shared
        let prefs = AltTabPreferences.shared
        let mouseScreen = tracker.screenDescriptorUnderMouse()
        let mainScreen = tracker.connectedScreens.first

        sessionFrontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        sessionMouseScreenID = mouseScreen?.id
        sessionMainScreenID = mainScreen?.id
        sessionTargetScreenFrameCocoa = {
            switch prefs.hudScreenMode {
            case .mainScreenOnly:
                return mainScreen?.frameCocoa ?? NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            case .activeMouseScreen, .allScreens:
                return mouseScreen?.frameCocoa ?? mainScreen?.frameCocoa ?? NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            }
        }()

        activeProfile = effectiveProfile
        searchQuery = ""
        isSearchActive = prefs.showSearchBar || forceKeepOpen
        isSwitcherOpen = true

        refilterCurrentSession(preserveSelectionID: nil)
        selectedIndex = AltTabLayoutEngine.initialSelectionIndex(windowCount: displayedWindows.count, reverse: reverse)

        // Mostrar HUD inmediatamente (< 16 ms) con los datos y miniaturas ya en caché
        AltTabSwitcherPanelController.shared.show(
            metrics: layoutMetrics,
            targetScreenFrameCocoa: sessionTargetScreenFrameCocoa,
            activateForSearch: isSearchActive
        )

        presentFullSizePreviewForSelection()

        // Refrescar miniaturas visibles en paralelo (acotado a 4 concurrentes) sin bloquear la UI
        let refreshItems = displayedWindows.map { (windowID: $0.windowID, isMinimized: $0.isMinimized) }
        batchThumbnailTask?.cancel()
        batchThumbnailTask = Task {
            await TaskbarThumbnailService.shared.refreshThumbnailsBatch(
                items: refreshItems,
                maxDimension: max(280, layoutMetrics.cellWidth * 1.25),
                maxConcurrency: 4
            )
        }
    }

    public func refilterCurrentSession(preserveSelectionID: String?) {
        guard let profile = activeProfile else { return }
        let prefs = AltTabPreferences.shared
        let all = TaskbarWindowTracker.shared.allWindowsAcrossSpaces

        let filtered = AltTabLayoutEngine.filteredWindows(
            from: all,
            profile: profile,
            frontmostPID: sessionFrontmostPID,
            activeMouseScreenID: sessionMouseScreenID,
            mainScreenID: sessionMainScreenID,
            excludedBundleIDs: prefs.excludedBundleIDs,
            searchQuery: searchQuery
        )

        displayedWindows = filtered

        if let preserveSelectionID,
           let matchedIdx = filtered.firstIndex(where: { $0.id == preserveSelectionID }) {
            selectedIndex = matchedIdx
        } else if selectedIndex >= filtered.count {
            selectedIndex = max(0, filtered.count - 1)
        }

        layoutMetrics = AltTabLayoutEngine.computeMetrics(
            windowCount: filtered.count,
            style: prefs.displayStyle,
            autoSize: prefs.autoSizeEnabled,
            manualThumbnailWidth: CGFloat(prefs.manualThumbnailWidth),
            screenSize: sessionTargetScreenFrameCocoa.size,
            showSearchBar: isSearchActive || prefs.showSearchBar
        )

        if isSwitcherOpen {
            AltTabSwitcherPanelController.shared.updateFrame(
                metrics: layoutMetrics,
                targetScreenFrameCocoa: sessionTargetScreenFrameCocoa
            )
            presentFullSizePreviewForSelection()
        }
    }

    public func stepSelection(reverse: Bool) {
        guard !displayedWindows.isEmpty else { return }
        let count = displayedWindows.count
        if reverse {
            selectedIndex = (selectedIndex - 1 + count) % count
        } else {
            selectedIndex = (selectedIndex + 1) % count
        }
        presentFullSizePreviewForSelection()
    }

    public func navigateGrid(direction: AltTabNavigationDirection) {
        guard !displayedWindows.isEmpty else { return }
        let count = displayedWindows.count
        let cols = max(1, layoutMetrics.columns)

        switch direction {
        case .left:
            selectedIndex = (selectedIndex - 1 + count) % count
        case .right:
            selectedIndex = (selectedIndex + 1) % count
        case .down:
            let next = selectedIndex + cols
            selectedIndex = next < count ? next : (selectedIndex % cols)
        case .up:
            let prev = selectedIndex - cols
            if prev >= 0 {
                selectedIndex = prev
            } else {
                let col = selectedIndex % cols
                var lastInCol = col
                while lastInCol + cols < count {
                    lastInCol += cols
                }
                selectedIndex = min(lastInCol, count - 1)
            }
        }
        presentFullSizePreviewForSelection()
    }

    public func selectWindow(at index: Int, confirmImmediately: Bool = false) {
        guard index >= 0, index < displayedWindows.count else { return }
        selectedIndex = index
        if confirmImmediately {
            confirmSelection()
        } else {
            presentFullSizePreviewForSelection()
        }
    }

    public func activateInlineSearch() {
        guard isSwitcherOpen else { return }
        isSearchActive = true
        refilterCurrentSession(preserveSelectionID: selectedWindow?.id)
        AltTabSwitcherPanelController.shared.makeKeyForSearch()
    }

    public func confirmSelection() {
        let target = selectedWindow
        closeSwitcherOverlays()
        if let target {
            TaskbarWindowTracker.shared.focusWindow(target)
        }
    }

    public func cancelSwitcher() {
        closeSwitcherOverlays()
    }

    private func closeSwitcherOverlays() {
        batchThumbnailTask?.cancel()
        batchThumbnailTask = nil
        isSwitcherOpen = false
        isSearchActive = false
        searchQuery = ""
        activeProfile = nil
        AltTabFullPreviewPanelController.shared.hideImmediately()
        AltTabSwitcherPanelController.shared.hide()

        // Si se había abierto el modo de prueba con AltTab desactivado, soltar el consumidor temporal
        if !AltTabPreferences.shared.isEnabled {
            TaskbarWindowTracker.shared.releaseMonitoring(for: .altTab)
        }
    }

    // MARK: - Acciones Rápidas Directas desde el Selector (Teclado o Botones Hover)

    public func closeSelectedWindow() {
        guard let target = selectedWindow else { return }
        closeWindowFromSwitcher(target)
    }

    public func closeWindowFromSwitcher(_ item: TaskbarWindowItem) {
        TaskbarWindowTracker.shared.closeWindow(item)
        displayedWindows.removeAll { $0.id == item.id }
        if displayedWindows.isEmpty {
            cancelSwitcher()
            return
        }
        if selectedIndex >= displayedWindows.count {
            selectedIndex = displayedWindows.count - 1
        }
        recomputeMetricsAndPreview()
    }

    public func minimizeSelectedWindow() {
        guard let target = selectedWindow else { return }
        minimizeWindowFromSwitcher(target)
    }

    public func minimizeWindowFromSwitcher(_ item: TaskbarWindowItem) {
        TaskbarWindowTracker.shared.minimizeWindow(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            guard let self, self.isSwitcherOpen else { return }
            self.refilterCurrentSession(preserveSelectionID: item.id)
        }
    }

    public func hideSelectedWindowApp() {
        guard let target = selectedWindow else { return }
        TaskbarWindowTracker.shared.hideApplication(pid: target.pid)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            guard let self, self.isSwitcherOpen else { return }
            self.refilterCurrentSession(preserveSelectionID: target.id)
        }
    }

    public func quitSelectedWindowApp() {
        guard let target = selectedWindow else { return }
        TaskbarWindowTracker.shared.quitApplication(pid: target.pid, force: false)
        displayedWindows.removeAll { $0.pid == target.pid }
        if displayedWindows.isEmpty {
            cancelSwitcher()
            return
        }
        if selectedIndex >= displayedWindows.count {
            selectedIndex = displayedWindows.count - 1
        }
        recomputeMetricsAndPreview()
    }

    public func toggleFullScreenSelectedWindow() {
        guard let target = selectedWindow else { return }
        toggleFullScreenFromSwitcher(target)
    }

    public func toggleFullScreenFromSwitcher(_ item: TaskbarWindowItem) {
        TaskbarWindowTracker.shared.toggleFullScreen(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.isSwitcherOpen else { return }
            self.refilterCurrentSession(preserveSelectionID: item.id)
        }
    }

    private func recomputeMetricsAndPreview() {
        let prefs = AltTabPreferences.shared
        layoutMetrics = AltTabLayoutEngine.computeMetrics(
            windowCount: displayedWindows.count,
            style: prefs.displayStyle,
            autoSize: prefs.autoSizeEnabled,
            manualThumbnailWidth: CGFloat(prefs.manualThumbnailWidth),
            screenSize: sessionTargetScreenFrameCocoa.size,
            showSearchBar: isSearchActive || prefs.showSearchBar
        )
        AltTabSwitcherPanelController.shared.updateFrame(
            metrics: layoutMetrics,
            targetScreenFrameCocoa: sessionTargetScreenFrameCocoa
        )
        presentFullSizePreviewForSelection()
    }

    private func presentFullSizePreviewForSelection() {
        guard isSwitcherOpen,
              AltTabPreferences.shared.showFullSizePreview,
              let target = selectedWindow else {
            AltTabFullPreviewPanelController.shared.hideImmediately()
            return
        }

        AltTabFullPreviewPanelController.shared.schedulePreview(
            for: target,
            delayMs: AltTabPreferences.shared.fullSizePreviewDelayMs,
            fallbackScreenFrameCocoa: sessionTargetScreenFrameCocoa
        )
    }
}
