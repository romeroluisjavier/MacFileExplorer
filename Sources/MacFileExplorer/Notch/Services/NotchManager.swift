import AppKit
import CoreGraphics
import Foundation
import Observation
import SwiftUI

/// Orquestador central del reproductor **Notch** estilo Notchy en `MacFileExplorer`.
///
/// Responsabilidades:
/// - Detecta la geometría real del hardware notch (`NSScreen.safeAreaInsets` y áreas auxiliares) en cada monitor.
/// - Mantiene un único `NSPanel` transparente y no activable por pantalla elegible (tamaño estable -> animaciones
///   ProMotion de 120 Hz sin tirones al transformar colapsado ↔ anuncio ↔ expandido ↔ letras).
/// - Gestiona hit-testing exacto de la silueta visible para que cualquier clic fuera del Notch pase directamente
///   a la barra de menús y aplicaciones detrás sin interferir ni robar foco.
/// - Soporta expansión por hover/clic, anuncio automático al cambiar de pista, deslizamiento horizontal para
///   cambiar de canción, ocultamiento inteligente en pausa y ocultamiento automático en apps de pantalla completa.
/// - Registra sus `ownedWindowNumbers` en `TaskbarWindowTracker` para no aparecer jamás en la Barra de tareas ni AltTab.
@MainActor
@Observable
public final class NotchManager {

    public static let shared = NotchManager()

    // MARK: - Estado Observable Público

    public private(set) var connectedDisplays: [NotchDisplayGeometry] = []
    public private(set) var isPinnedOpen: Bool = false
    public private(set) var prefersLyricsOpen: Bool = false
    public private(set) var activeFeedback: NotchTransientFeedback = .none
    public private(set) var pauseSqueezeActive: Bool = false
    /// Propiedad almacenada para evitar que transiciones no-expandidas (ej. `.collapsed` ↔ `.peeking` ↔ `.hidden`)
    /// invaliden el menú superior `CommandMenu("Notch")` y cierren submenús abiertos.
    public private(set) var isAnyPanelExpanded: Bool = false

    private var phaseByDisplayID: [String: NotchPresentationPhase] = [:] {
        didSet {
            let expanded = phaseByDisplayID.values.contains(where: \.isExpanded)
            if isAnyPanelExpanded != expanded {
                isAnyPanelExpanded = expanded
            }
        }
    }
    private var swipeNudgeByDisplayID: [String: CGFloat] = [:]

    // MARK: - Infraestructura Interna

    private var panelsByDisplayID: [String: NotchOverlayPanel] = [:]
    private var geometryByDisplayID: [String: NotchDisplayGeometry] = [:]
    private var fullScreenDisplayIDs: Set<String> = []

    private var isInstalled = false
    private var isSyncingEnabled = false

    private var hoverExpandTaskByDisplayID: [String: Task<Void, Never>] = [:]
    private var hoverCollapseTaskByDisplayID: [String: Task<Void, Never>] = [:]
    private var peekDismissTask: Task<Void, Never>?
    private var squeezeResetTask: Task<Void, Never>?
    private var pausedAutoHideTask: Task<Void, Never>?
    private var swipeResetTasks: [String: Task<Void, Never>] = [:]

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var screenParamsObserver: NSObjectProtocol?
    private var activeSpaceObserver: NSObjectProtocol?
    private var activeAppObserver: NSObjectProtocol?
    private var fullScreenPollTask: Task<Void, Never>?
    private var antiAppNapActivity: NSObjectProtocol?

    private var accumulatedSwipeX: CGFloat = 0
    private var lastSwipeTriggeredAt: Date = .distantPast
    private var lastHoveredDisplayID: String?

    private init() {}

    // MARK: - Consultas de Estado para Vistas y Menús

    public var ownedWindowNumbers: Set<Int> {
        Set(panelsByDisplayID.values.map(\.windowNumber))
    }

    public func phase(for displayID: String) -> NotchPresentationPhase {
        phaseByDisplayID[displayID] ?? .collapsed
    }

    public func swipeNudgeOffset(for displayID: String) -> CGFloat {
        swipeNudgeByDisplayID[displayID] ?? 0
    }

    // MARK: - Instalación y Ciclo de Vida

    public func installIfNeeded() {
        guard !isInstalled else { return }
        isInstalled = true

        refreshDisplayGeometries()

        let prefs = NotchPreferences.shared
        prefs.onEnabledChanged = { [weak self] enabled in
            self?.applyEnabledState(enabled)
        }
        prefs.onAppearanceOrLayoutChanged = { [weak self] in
            self?.handlePreferencesChanged()
        }

        NotchMediaService.shared.onTrackChanged = { [weak self] newTrack in
            self?.handleTrackChanged(newTrack)
        }
        NotchMediaService.shared.onPlaybackStateChanged = { [weak self] isPlaying, track in
            self?.handlePlaybackStateChanged(isPlaying: isPlaying, track: track)
        }

        TaskbarWindowTracker.shared.registerOwnedWindowNumbersProvider(key: "notch") { [weak self] in
            self?.ownedWindowNumbers ?? []
        }

        NotchMusicDecoyService.shared.installIfNeeded()
        NotchMusicDecoyService.shared.syncWithPreferences()

        if prefs.isEnabled {
            applyEnabledState(true)
        }
    }

    /// Activa o desactiva el reproductor Notch desde menús o Configuración.
    public func setEnabled(_ enabled: Bool) {
        let prefs = NotchPreferences.shared
        if prefs.isEnabled != enabled {
            isSyncingEnabled = true
            prefs.isEnabled = enabled
            isSyncingEnabled = false
        }
        applyEnabledState(enabled)
    }

    private func applyEnabledState(_ enabled: Bool) {
        guard !isSyncingEnabled else { return }

        if enabled {
            beginAntiAppNapIfNeeded()
            refreshDisplayGeometries()
            NotchMediaService.shared.startMonitoring()
            installObserversAndMonitors()
            refreshFullScreenDisplays()
            rebuildPanels()
            evaluatePausedAutoHideSchedule()
            NotchAudioEqualizerEngine.shared.syncWithPreferences()
            NotchCalendarService.shared.startMonitoringIfNeeded()
        } else {
            isPinnedOpen = false
            NotchAudioEqualizerEngine.shared.stop()
            NotchCalendarService.shared.stopMonitoring()
            cancelAllTransientTasks()
            removeObserversAndMonitors()
            destroyAllPanels()
            NotchMediaService.shared.stopDemoPreview()
            NotchMediaService.shared.stopMonitoring()
            endAntiAppNapIfNeeded()
        }

        StatusBarManager.shared.refreshTooltipAndMenu()
    }

    /// Invocado antes de cerrar `MacFileExplorer` para liberar monitores, temporizadores y paneles.
    public func prepareForTermination() {
        NotchAudioEqualizerEngine.shared.stop()
        NotchCalendarService.shared.stopMonitoring()
        NotchMusicDecoyService.shared.stop()
        cancelAllTransientTasks()
        removeObserversAndMonitors()
        destroyAllPanels()
        NotchMediaService.shared.stopDemoPreview()
        NotchMediaService.shared.stopMonitoring()
        endAntiAppNapIfNeeded()
    }

    // MARK: - Acciones Públicas Interactivas (Menú Superior, Configuración y Vista)

    public func expand(displayID: String? = nil, showLyrics: Bool? = nil) {
        guard NotchPreferences.shared.isEnabled else { return }
        guard let targetID = resolveTargetDisplayID(preferred: displayID) else { return }

        cancelHoverTasks(for: targetID)
        clearTransientFeedback(collapsePeeking: false)

        let useLyrics: Bool
        if let showLyrics {
            useLyrics = showLyrics && NotchPreferences.shared.showSyncedLyrics
            prefersLyricsOpen = useLyrics
        } else {
            useLyrics = prefersLyricsOpen && NotchPreferences.shared.showSyncedLyrics && NotchMediaService.shared.hasActiveTrack
        }

        let targetPhase: NotchPresentationPhase = useLyrics ? .expandedLyrics : .expandedCompact
        setPhase(targetPhase, for: targetID)

        if useLyrics, let track = NotchMediaService.shared.currentTrack {
            NotchLyricsAndAudioService.shared.updateLyrics(for: track)
        }
        syncMousePassThrough(at: NSEvent.mouseLocation)
    }

    public func collapse(displayID: String? = nil, forceUnpin: Bool = false) {
        if forceUnpin {
            isPinnedOpen = false
        }
        if let displayID {
            cancelHoverTasks(for: displayID)
            setPhase(restingCollapsedPhase(), for: displayID)
        } else {
            for id in panelsByDisplayID.keys {
                cancelHoverTasks(for: id)
                setPhase(restingCollapsedPhase(), for: id)
            }
        }
        syncMousePassThrough(at: NSEvent.mouseLocation)
    }

    public func toggleExpanded(displayID: String? = nil) {
        guard NotchPreferences.shared.isEnabled else {
            setEnabled(true)
            expand(displayID: displayID)
            return
        }
        if isAnyPanelExpanded {
            collapse(displayID: displayID, forceUnpin: true)
        } else {
            expand(displayID: displayID)
        }
    }

    public func toggleLyricsPane(for displayID: String) {
        let prefs = NotchPreferences.shared
        guard prefs.showSyncedLyrics else { return }
        let current = phase(for: displayID)
        if current == .expandedLyrics {
            prefersLyricsOpen = false
            setPhase(.expandedCompact, for: displayID)
        } else {
            prefersLyricsOpen = true
            setPhase(.expandedLyrics, for: displayID)
            if let track = NotchMediaService.shared.currentTrack {
                NotchLyricsAndAudioService.shared.updateLyrics(for: track)
            }
        }
        syncMousePassThrough(at: NSEvent.mouseLocation)
    }

    public func togglePinned() {
        isPinnedOpen.toggle()
    }

    /// Dispara la animación superior del Notch al acercarse una reunión / Meet según la configuración elegida.
    public func triggerCalendarMeetingAlert(for event: NotchCalendarEvent) {
        let prefs = NotchPreferences.shared
        guard prefs.isEnabled && prefs.calendarEnabled else { return }
        guard prefs.calendarMusicCoexistenceMode != .manualTabOnly else { return }

        // Despertar paneles si estaban ocultos por pausa
        for (id, current) in phaseByDisplayID where current == .hidden {
            setPhase(.collapsed, for: id)
        }

        switch prefs.calendarAlertAnimationStyle {
        case .dropDownBanner, .liquidCascade, .cyberScanDrop, .warpPortalDrop, .auroraCurtainDrop:
            if !isAnyPanelExpanded {
                expand(displayID: nil, showLyrics: false)
                peekDismissTask?.cancel()
                peekDismissTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(7.5))
                    guard !Task.isCancelled, let self, !self.isPinnedOpen else { return }
                    self.collapse(forceUnpin: false)
                }
            }
        case .expandSideways:
            previewTrackChangeFeedback(style: .expandSideways)
        case .greenMeetPulse, .subtleGlow:
            previewTrackChangeFeedback(style: .colorFlash)
        case .none:
            break
        }
        syncMousePassThrough(at: NSEvent.mouseLocation)
    }

    /// Alterna el modo Demo y asegura que el usuario vea el Notch inmediatamente (activándolo si estaba apagado).
    public func toggleDemoPreviewAndReveal() {
        let media = NotchMediaService.shared
        if media.isDemoMode {
            media.stopDemoPreview()
            return
        }
        if !NotchPreferences.shared.isEnabled {
            setEnabled(true)
        }
        media.startDemoPreview()
        if let targetID = resolveTargetDisplayID(preferred: nil) {
            expand(displayID: targetID, showLyrics: false)
        }
    }

    public func refreshLocalizedUI() {
        guard NotchPreferences.shared.isEnabled else { return }
        // Las vistas SwiftUI observan `LocalizationManager.shared` directamente; refrescamos ventanas de ajustes también.
        NotchSettingsWindowController.shared.refreshLocalizedTitle()
    }

    // MARK: - Gestión de Monitores y Paneles Estables

    public func refreshDisplayGeometries() {
        let detected = NSScreen.screens.enumerated().map { idx, screen in
            NotchDisplayGeometry.detect(for: screen, index: idx)
        }
        connectedDisplays = detected
    }

    public func eligibleDisplays() -> [NotchDisplayGeometry] {
        let all = connectedDisplays
        guard !all.isEmpty else { return [] }

        switch NotchPreferences.shared.displayMode {
        case .notchDisplayOnly:
            let notched = all.filter(\.hasHardwareNotch)
            if !notched.isEmpty {
                return notched
            }
            // Si el Mac no tiene notch físico, usar la pantalla principal en modo Isla Dinámica flotante
            return [all[0]]
        case .primaryDisplay:
            return [all[0]]
        case .allDisplays:
            return all
        }
    }

    public func rebuildPanels() {
        guard NotchPreferences.shared.isEnabled else {
            destroyAllPanels()
            return
        }

        refreshDisplayGeometries()
        let targets = eligibleDisplays()
        let targetIDs = Set(targets.map(\.displayID))

        // Retirar paneles de monitores desconectados o excluidos
        for (id, panel) in panelsByDisplayID where !targetIDs.contains(id) {
            cancelHoverTasks(for: id)
            panel.orderOut(nil)
            panel.close()
            panelsByDisplayID.removeValue(forKey: id)
            geometryByDisplayID.removeValue(forKey: id)
            phaseByDisplayID.removeValue(forKey: id)
            swipeNudgeByDisplayID.removeValue(forKey: id)
        }

        for geo in targets {
            let panelFrame = stablePanelFrame(for: geo)
            let previousGeo = geometryByDisplayID[geo.displayID]
            geometryByDisplayID[geo.displayID] = geo

            if phaseByDisplayID[geo.displayID] == nil {
                phaseByDisplayID[geo.displayID] = restingCollapsedPhase()
            }

            let panel: NotchOverlayPanel
            if let existing = panelsByDisplayID[geo.displayID] {
                panel = existing
                if previousGeo != geo {
                    let rootView = NotchOverlayPanelView(displayID: geo.displayID, geometry: geo)
                    let hosting = NSHostingView(rootView: rootView)
                    hosting.autoresizingMask = [.width, .height]
                    panel.contentView = hosting
                }
            } else {
                let created = NotchOverlayPanel(displayID: geo.displayID, contentRect: panelFrame)
                let rootView = NotchOverlayPanelView(displayID: geo.displayID, geometry: geo)
                let hosting = NSHostingView(rootView: rootView)
                hosting.autoresizingMask = [.width, .height]
                created.contentView = hosting
                panelsByDisplayID[geo.displayID] = created
                panel = created
            }

            if panel.frame != panelFrame {
                panel.setFrame(panelFrame, display: true)
            }

            applyVisibilityForFullScreen(panel: panel, displayID: geo.displayID)
        }

        syncMousePassThrough(at: NSEvent.mouseLocation)
    }

    private func stablePanelFrame(for geo: NotchDisplayGeometry) -> NSRect {
        let maxLyrics = NotchPillSize.spacious.expandedLyricsSize
        let width: CGFloat = min(geo.screenFrame.width, maxLyrics.width + 88)
        let height: CGFloat = maxLyrics.height + max(geo.physicalNotchHeight, 38) + 56

        let originX = round(geo.screenFrame.midX - width * 0.5)
        let topY: CGFloat = geo.isFloatingIsland
            ? round(geo.screenFrame.maxY - geo.menuBarHeight - 6)
            : round(geo.screenFrame.maxY)
        let originY = topY - height

        return NSRect(x: originX, y: originY, width: width, height: height)
    }

    private func applyVisibilityForFullScreen(panel: NotchOverlayPanel, displayID: String) {
        let shouldHide = NotchPreferences.shared.hideInFullScreen && fullScreenDisplayIDs.contains(displayID)
        if shouldHide {
            if panel.isVisible {
                panel.orderOut(nil)
            }
        } else {
            if !panel.isVisible {
                panel.orderFrontRegardless()
            }
        }
    }

    private func destroyAllPanels() {
        for (_, panel) in panelsByDisplayID {
            panel.orderOut(nil)
            panel.close()
        }
        panelsByDisplayID.removeAll()
        geometryByDisplayID.removeAll()
        phaseByDisplayID.removeAll()
        swipeNudgeByDisplayID.removeAll()
    }

    // MARK: - Reacción a Cambios de Pista y Preferencias

    private func handlePreferencesChanged() {
        guard NotchPreferences.shared.isEnabled else { return }
        if !NotchPreferences.shared.showSyncedLyrics {
            prefersLyricsOpen = false
            for (id, current) in phaseByDisplayID where current == .expandedLyrics {
                phaseByDisplayID[id] = .expandedCompact
            }
        }
        rebuildPanels()
        evaluatePausedAutoHideSchedule()
    }

    /// Ejecuta una vista previa en vivo del estilo actual de cambio de canción sobre el Notch real (si está activo).
    public func previewTrackChangeFeedback(style: NotchTrackChangeStyle? = nil) {
        guard NotchPreferences.shared.isEnabled else { return }
        if isAnyPanelExpanded {
            collapse(forceUnpin: true)
        }
        for (id, current) in phaseByDisplayID where current == .hidden {
            setPhase(.collapsed, for: id)
        }
        triggerTrackChangeFeedback(style: style ?? NotchPreferences.shared.trackChangeStyle)
    }

    /// Ejecuta una vista previa en vivo de la animación de pausa sobre el Notch real (si está activo).
    public func previewPauseFeedback(style: NotchPauseAnimationStyle? = nil) {
        guard NotchPreferences.shared.isEnabled else { return }
        if isAnyPanelExpanded {
            collapse(forceUnpin: true)
        }
        for (id, current) in phaseByDisplayID where current == .hidden {
            setPhase(.collapsed, for: id)
        }
        triggerPauseFeedback(style: style ?? NotchPreferences.shared.pauseAnimationStyle)
    }

    private func clearTransientFeedback(collapsePeeking: Bool) {
        peekDismissTask?.cancel()
        peekDismissTask = nil
        squeezeResetTask?.cancel()
        squeezeResetTask = nil
        pauseSqueezeActive = false
        activeFeedback = .none
        if collapsePeeking {
            for (id, current) in phaseByDisplayID where current == .peeking {
                setPhase(restingCollapsedPhase(), for: id)
            }
            syncMousePassThrough(at: NSEvent.mouseLocation)
        }
    }

    private func triggerTrackChangeFeedback(style: NotchTrackChangeStyle) {
        guard !isAnyPanelExpanded else { return }
        let speedScale = 1.0 / min(max(NotchPreferences.shared.animationSpeed, 0.5), 2.0)

        peekDismissTask?.cancel()
        squeezeResetTask?.cancel()
        pauseSqueezeActive = false

        let token = UUID()
        activeFeedback = .trackChanged(style, token: token)

        if style.usesPeekingSilhouette {
            for id in panelsByDisplayID.keys {
                if phase(for: id) == .collapsed || phase(for: id) == .peeking {
                    setPhase(.peeking, for: id)
                }
            }
            syncMousePassThrough(at: NSEvent.mouseLocation)
        } else {
            for (id, current) in phaseByDisplayID where current == .peeking {
                setPhase(.collapsed, for: id)
            }
            if style == .slideNudge {
                for id in panelsByDisplayID.keys {
                    triggerSwipeNudge(for: id, deltaX: 11)
                }
            }
            syncMousePassThrough(at: NSEvent.mouseLocation)
        }

        let baseDurationSec: Double
        switch style {
        case .dropDown, .expandSideways:
            baseDurationSec = 2.6
        case .skipIconSwap:
            baseDurationSec = 2.0
        case .colorFlash:
            baseDurationSec = 1.8
        case .slideNudge:
            baseDurationSec = 1.6
        }
        let durationNs = UInt64(max(0.85, baseDurationSec * min(max(speedScale, 0.65), 1.45)) * 1_000_000_000)

        peekDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: durationNs)
            guard !Task.isCancelled, let self else { return }
            if case .trackChanged(_, let activeToken) = self.activeFeedback, activeToken == token {
                self.activeFeedback = .none
            }
            for (id, current) in self.phaseByDisplayID where current == .peeking {
                self.setPhase(self.restingCollapsedPhase(), for: id)
            }
            self.syncMousePassThrough(at: NSEvent.mouseLocation)
        }
    }

    private func triggerPauseFeedback(style: NotchPauseAnimationStyle) {
        guard !isAnyPanelExpanded else { return }
        let speedScale = 1.0 / min(max(NotchPreferences.shared.animationSpeed, 0.5), 2.0)

        peekDismissTask?.cancel()
        squeezeResetTask?.cancel()
        pauseSqueezeActive = false

        let token = UUID()
        activeFeedback = .paused(style, token: token)

        if style.usesPeekingSilhouette {
            for id in panelsByDisplayID.keys {
                if phase(for: id) == .collapsed || phase(for: id) == .peeking {
                    setPhase(.peeking, for: id)
                }
            }
            syncMousePassThrough(at: NSEvent.mouseLocation)
        } else {
            for (id, current) in phaseByDisplayID where current == .peeking {
                setPhase(.collapsed, for: id)
            }
            if style == .gentleSqueeze && NotchPreferences.shared.enableAnimations {
                pauseSqueezeActive = true
                let squeezeNs = UInt64(max(0.14, 0.24 * speedScale) * 1_000_000_000)
                squeezeResetTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: squeezeNs)
                    guard !Task.isCancelled, let self else { return }
                    self.pauseSqueezeActive = false
                }
            }
            syncMousePassThrough(at: NSEvent.mouseLocation)
        }

        let baseDurationSec: Double
        switch style {
        case .dropDown, .expandSideways:
            baseDurationSec = 1.9
        case .colorDimPulse:
            baseDurationSec = 1.5
        case .pauseIconPop:
            baseDurationSec = 1.4
        case .gentleSqueeze:
            baseDurationSec = 1.1
        }
        let durationNs = UInt64(max(0.75, baseDurationSec * min(max(speedScale, 0.65), 1.45)) * 1_000_000_000)

        peekDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: durationNs)
            guard !Task.isCancelled, let self else { return }
            if case .paused(_, let activeToken) = self.activeFeedback, activeToken == token {
                self.activeFeedback = .none
            }
            for (id, current) in self.phaseByDisplayID where current == .peeking {
                self.setPhase(self.restingCollapsedPhase(), for: id)
            }
            self.syncMousePassThrough(at: NSEvent.mouseLocation)
        }
    }

    private func handlePlaybackStateChanged(isPlaying: Bool, track: NotchTrackInfo) {
        guard NotchPreferences.shared.isEnabled else { return }
        evaluatePausedAutoHideSchedule()

        if isPlaying {
            if activeFeedback.isPauseFeedback {
                clearTransientFeedback(collapsePeeking: true)
            }
            return
        }

        guard NotchPreferences.shared.animateOnPause else { return }
        guard !isAnyPanelExpanded else { return }
        for (id, current) in phaseByDisplayID where current == .hidden {
            setPhase(.collapsed, for: id)
        }
        triggerPauseFeedback(style: NotchPreferences.shared.pauseAnimationStyle)
    }

    private func handleTrackChanged(_ newTrack: NotchTrackInfo?) {
        guard NotchPreferences.shared.isEnabled else { return }

        evaluatePausedAutoHideSchedule()

        guard let newTrack else {
            clearTransientFeedback(collapsePeeking: false)
            if NotchPreferences.shared.hideWhenPaused && !isPinnedOpen {
                for (id, current) in phaseByDisplayID where !current.isExpanded {
                    setPhase(.hidden, for: id)
                }
            }
            return
        }

        if NotchPreferences.shared.showSyncedLyrics {
            NotchLyricsAndAudioService.shared.updateLyrics(for: newTrack)
        }

        // Asegurar visibilidad al reanudar o cambiar canción
        for (id, current) in phaseByDisplayID where current == .hidden {
            setPhase(.collapsed, for: id)
        }

        // Aviso visual configurable al cambiar de tema ("Announce New Tracks")
        guard NotchPreferences.shared.announceNewTracks else { return }
        guard !isAnyPanelExpanded else { return }
        triggerTrackChangeFeedback(style: NotchPreferences.shared.trackChangeStyle)
    }

    private func restingCollapsedPhase() -> NotchPresentationPhase {
        let prefs = NotchPreferences.shared
        let media = NotchMediaService.shared
        guard prefs.hideWhenPaused else { return .collapsed }
        if media.isPlaying { return .collapsed }
        if media.currentTrack == nil { return .hidden }
        if let pausedSince = media.pausedSince,
           Date().timeIntervalSince(pausedSince) >= prefs.hideWhenPausedDelay {
            return .hidden
        }
        return .collapsed
    }

    private func evaluatePausedAutoHideSchedule() {
        pausedAutoHideTask?.cancel()
        pausedAutoHideTask = nil

        let prefs = NotchPreferences.shared
        let media = NotchMediaService.shared
        guard prefs.isEnabled else { return }

        if !prefs.hideWhenPaused || media.isPlaying {
            for (id, current) in phaseByDisplayID where current == .hidden {
                setPhase(.collapsed, for: id)
            }
            return
        }

        if media.currentTrack == nil {
            for (id, current) in phaseByDisplayID where !current.isExpanded && !isPinnedOpen {
                setPhase(.hidden, for: id)
            }
            return
        }

        let elapsedPaused = media.pausedSince.map { Date().timeIntervalSince($0) } ?? 0
        let remaining = max(0, prefs.hideWhenPausedDelay - elapsedPaused)

        if remaining <= 0.05 {
            for (id, current) in phaseByDisplayID where !current.isExpanded && !isPinnedOpen {
                setPhase(.hidden, for: id)
            }
            return
        }

        pausedAutoHideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            guard NotchPreferences.shared.hideWhenPaused, !NotchMediaService.shared.isPlaying else { return }
            for (id, current) in self.phaseByDisplayID where !current.isExpanded && !self.isPinnedOpen {
                self.setPhase(.hidden, for: id)
            }
            self.syncMousePassThrough(at: NSEvent.mouseLocation)
        }
    }

    // MARK: - Hit-Testing Preciso, Hover, Clic Exterior y Deslizamiento (Swipe)

    private func activeScreenRect(for displayID: String, extraPadding: CGFloat = 0) -> CGRect? {
        guard let panel = panelsByDisplayID[displayID],
              let geo = geometryByDisplayID[displayID],
              panel.isVisible else {
            return nil
        }

        let currentPhase = phase(for: displayID)
        if currentPhase == .hidden {
            // Pequeña zona superior de reactivación si el usuario lleva el cursor justo al notch
            if geo.hasHardwareNotch {
                let w = geo.physicalNotchWidth + 24
                let h = max(geo.physicalNotchHeight, 32)
                return CGRect(
                    x: panel.frame.midX - w * 0.5,
                    y: panel.frame.maxY - h,
                    width: w,
                    height: h
                )
            }
            return nil
        }

        let metrics = NotchSilhouetteMetrics.compute(
            phase: currentPhase,
            geometry: geo,
            prefs: NotchPreferences.shared,
            hasActiveTrack: NotchMediaService.shared.hasActiveTrack,
            activeFeedback: activeFeedback
        )

        let width = metrics.width + extraPadding * 2
        let height = metrics.height + extraPadding
        return CGRect(
            x: panel.frame.midX - width * 0.5,
            y: panel.frame.maxY - height,
            width: width,
            height: height
        )
    }

    private func syncMousePassThrough(at mouseLocation: NSPoint) {
        for (id, panel) in panelsByDisplayID {
            guard panel.isVisible else {
                panel.ignoresMouseEvents = true
                continue
            }
            let currentPhase = phase(for: id)
            if currentPhase == .hidden {
                panel.ignoresMouseEvents = true
                continue
            }
            let rect = activeScreenRect(for: id, extraPadding: currentPhase.isExpanded ? 4 : 2)
            let inside = rect?.contains(mouseLocation) ?? false
            let shouldIgnore = !inside
            if panel.ignoresMouseEvents != shouldIgnore {
                panel.ignoresMouseEvents = shouldIgnore
            }
        }
    }

    private func handleMouseMoved(at mouseLocation: NSPoint) {
        let prefs = NotchPreferences.shared
        guard prefs.isEnabled else { return }

        var matchedDisplayID: String?

        for (id, panel) in panelsByDisplayID {
            guard panel.isVisible else {
                panel.ignoresMouseEvents = true
                continue
            }

            let currentPhase = phase(for: id)
            let hoverPadding: CGFloat = currentPhase.isExpanded ? 12 : 4
            let rect = activeScreenRect(for: id, extraPadding: hoverPadding)
            let isInside = rect?.contains(mouseLocation) ?? false

            // Pasar clics de largo inmediatamente si el cursor no está sobre la silueta activa
            let exactRect = activeScreenRect(for: id, extraPadding: currentPhase.isExpanded ? 4 : 2)
            let shouldAcceptClicks = (currentPhase != .hidden) && (exactRect?.contains(mouseLocation) ?? false)
            if panel.ignoresMouseEvents == shouldAcceptClicks {
                panel.ignoresMouseEvents = !shouldAcceptClicks
            }

            if isInside {
                matchedDisplayID = id
                cancelCollapseTask(for: id)

                if prefs.expandTrigger == .hoverAndClick && !currentPhase.isExpanded {
                    scheduleHoverExpand(for: id, delay: prefs.hoverExpandDelay)
                }
            } else {
                cancelExpandTask(for: id)

                if currentPhase.isExpanded && !isPinnedOpen {
                    scheduleHoverCollapse(for: id)
                }
            }
        }

        if lastHoveredDisplayID != matchedDisplayID {
            lastHoveredDisplayID = matchedDisplayID
            accumulatedSwipeX = 0
        }
    }

    private func handleGlobalLeftMouseDown(at mouseLocation: NSPoint) {
        guard NotchPreferences.shared.isEnabled, !isPinnedOpen else { return }
        for (id, currentPhase) in phaseByDisplayID where currentPhase.isExpanded {
            let rect = activeScreenRect(for: id, extraPadding: 6)
            if rect?.contains(mouseLocation) != true {
                collapse(displayID: id, forceUnpin: false)
            }
        }
    }

    private func handleScrollWheel(event: NSEvent) {
        let prefs = NotchPreferences.shared
        guard prefs.isEnabled, prefs.enableSwipeToSkip else { return }
        guard NotchMediaService.shared.hasActiveTrack else { return }

        let mouseLoc = NSEvent.mouseLocation
        guard let targetID = panelsByDisplayID.keys.first(where: { id in
            let p = phase(for: id)
            guard p == .collapsed || p == .peeking else { return false }
            return activeScreenRect(for: id, extraPadding: 6)?.contains(mouseLoc) == true
        }) else {
            return
        }

        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        guard abs(dx) > abs(dy), abs(dx) > 1.2 else { return }

        let now = Date()
        guard now.timeIntervalSince(lastSwipeTriggeredAt) >= 0.45 else { return }

        accumulatedSwipeX += dx
        let threshold: CGFloat = 24
        if accumulatedSwipeX <= -threshold {
            accumulatedSwipeX = 0
            lastSwipeTriggeredAt = now
            NotchMediaService.shared.nextTrack()
            triggerSwipeNudge(for: targetID, deltaX: -12)
        } else if accumulatedSwipeX >= threshold {
            accumulatedSwipeX = 0
            lastSwipeTriggeredAt = now
            NotchMediaService.shared.previousTrack()
            triggerSwipeNudge(for: targetID, deltaX: 12)
        }
    }

    private func triggerSwipeNudge(for displayID: String, deltaX: CGFloat) {
        guard NotchPreferences.shared.enableAnimations else { return }
        swipeResetTasks[displayID]?.cancel()
        swipeNudgeByDisplayID[displayID] = deltaX
        swipeResetTasks[displayID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled, let self else { return }
            self.swipeNudgeByDisplayID[displayID] = 0
        }
    }

    private func scheduleHoverExpand(for displayID: String, delay: Double) {
        guard hoverExpandTaskByDisplayID[displayID] == nil else { return }
        let delayNs = UInt64(max(0.05, delay) * 1_000_000_000)
        hoverExpandTaskByDisplayID[displayID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled, let self else { return }
            self.hoverExpandTaskByDisplayID[displayID] = nil
            guard NotchPreferences.shared.isEnabled else { return }
            let mouseLoc = NSEvent.mouseLocation
            if self.activeScreenRect(for: displayID, extraPadding: 6)?.contains(mouseLoc) == true {
                self.expand(displayID: displayID)
            }
        }
    }

    private func scheduleHoverCollapse(for displayID: String) {
        guard hoverCollapseTaskByDisplayID[displayID] == nil else { return }
        hoverCollapseTaskByDisplayID[displayID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 240_000_000)
            guard !Task.isCancelled, let self else { return }
            self.hoverCollapseTaskByDisplayID[displayID] = nil
            guard !self.isPinnedOpen else { return }
            let mouseLoc = NSEvent.mouseLocation
            if self.activeScreenRect(for: displayID, extraPadding: 10)?.contains(mouseLoc) != true {
                self.collapse(displayID: displayID, forceUnpin: false)
            }
        }
    }

    // MARK: - Detección de Pantalla Completa por Monitor

    private func refreshFullScreenDisplays() {
        var detected = TaskbarWindowTracker.shared.fullScreenDisplayIDs

        // Detección liviana propia para cuando Taskbar/AltTab no están activos
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        if let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 900
            for info in rawList {
                let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
                guard layer == 0 else { continue }
                let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
                guard pid != ownPID else { continue }
                let ownerName = (info[kCGWindowOwnerName as String] as? String) ?? ""
                if ownerName == "Window Server" || ownerName == "Dock" || ownerName == "Finder" {
                    continue
                }
                guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                      let cgBounds = CGRect(dictionaryRepresentation: boundsDict),
                      cgBounds.width >= 300, cgBounds.height >= 200 else {
                    continue
                }

                // Convertir CG (origen arriba-izquierda) a Cocoa (origen abajo-izquierda)
                let cocoaY = primaryHeight - cgBounds.origin.y - cgBounds.height
                let cocoaRect = CGRect(x: cgBounds.origin.x, y: cocoaY, width: cgBounds.width, height: cgBounds.height)

                for geo in connectedDisplays {
                    let coversWidth = cocoaRect.width >= geo.screenFrame.width - 2
                    let coversHeight = cocoaRect.height >= geo.screenFrame.height - 2
                    let matchesOrigin = abs(cocoaRect.minX - geo.screenFrame.minX) <= 4 &&
                        abs(cocoaRect.minY - geo.screenFrame.minY) <= 4
                    if coversWidth && coversHeight && matchesOrigin {
                        detected.insert(geo.displayID)
                    }
                }
            }
        }

        if detected != fullScreenDisplayIDs {
            fullScreenDisplayIDs = detected
            for (id, panel) in panelsByDisplayID {
                applyVisibilityForFullScreen(panel: panel, displayID: id)
            }
        }
    }

    // MARK: - Instalación y Limpieza de Monitores y Observadores

    private func installObserversAndMonitors() {
        if globalMouseMonitor == nil {
            globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDown, .scrollWheel]
            ) { [weak self] event in
                let eventType = event.type
                let mouseLoc = NSEvent.mouseLocation
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch eventType {
                    case .mouseMoved:
                        self.handleMouseMoved(at: mouseLoc)
                    case .leftMouseDown:
                        self.handleGlobalLeftMouseDown(at: mouseLoc)
                    case .scrollWheel:
                        self.handleScrollWheel(event: event)
                    default:
                        break
                    }
                }
            }
        }

        if localMouseMonitor == nil {
            localMouseMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDown, .scrollWheel]
            ) { [weak self] event in
                guard let self else { return event }
                switch event.type {
                case .mouseMoved:
                    // Evitar disparar expansión por hover mientras el usuario navega un menú nativo abierto
                    if RunLoop.current.currentMode != .eventTracking {
                        self.handleMouseMoved(at: NSEvent.mouseLocation)
                    }
                case .leftMouseDown:
                    self.handleGlobalLeftMouseDown(at: NSEvent.mouseLocation)
                case .scrollWheel:
                    self.handleScrollWheel(event: event)
                default:
                    break
                }
                return event
            }
        }

        if screenParamsObserver == nil {
            screenParamsObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.rebuildPanels()
                }
            }
        }

        if activeSpaceObserver == nil {
            activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshFullScreenDisplays()
                }
            }
        }

        if activeAppObserver == nil {
            activeAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshFullScreenDisplays()
                }
            }
        }

        if fullScreenPollTask == nil {
            fullScreenPollTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    guard !Task.isCancelled, let self else { break }
                    self.refreshFullScreenDisplays()
                    self.evaluatePausedAutoHideSchedule()
                }
            }
        }
    }

    private func removeObserversAndMonitors() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
        if let observer = screenParamsObserver {
            NotificationCenter.default.removeObserver(observer)
            screenParamsObserver = nil
        }
        if let observer = activeSpaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            activeSpaceObserver = nil
        }
        if let observer = activeAppObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            activeAppObserver = nil
        }
        fullScreenPollTask?.cancel()
        fullScreenPollTask = nil
    }

    private func cancelAllTransientTasks() {
        for task in hoverExpandTaskByDisplayID.values { task.cancel() }
        hoverExpandTaskByDisplayID.removeAll()
        for task in hoverCollapseTaskByDisplayID.values { task.cancel() }
        hoverCollapseTaskByDisplayID.removeAll()
        for task in swipeResetTasks.values { task.cancel() }
        swipeResetTasks.removeAll()
        peekDismissTask?.cancel()
        peekDismissTask = nil
        squeezeResetTask?.cancel()
        squeezeResetTask = nil
        pauseSqueezeActive = false
        activeFeedback = .none
        pausedAutoHideTask?.cancel()
        pausedAutoHideTask = nil
    }

    private func cancelHoverTasks(for displayID: String) {
        cancelExpandTask(for: displayID)
        cancelCollapseTask(for: displayID)
    }

    private func cancelExpandTask(for displayID: String) {
        hoverExpandTaskByDisplayID[displayID]?.cancel()
        hoverExpandTaskByDisplayID[displayID] = nil
    }

    private func cancelCollapseTask(for displayID: String) {
        hoverCollapseTaskByDisplayID[displayID]?.cancel()
        hoverCollapseTaskByDisplayID[displayID] = nil
    }

    private func setPhase(_ newPhase: NotchPresentationPhase, for displayID: String) {
        if phaseByDisplayID[displayID] != newPhase {
            phaseByDisplayID[displayID] = newPhase
        }
    }

    private func resolveTargetDisplayID(preferred: String?) -> String? {
        if let preferred, panelsByDisplayID[preferred] != nil {
            return preferred
        }
        let mouseLoc = NSEvent.mouseLocation
        if let underMouse = geometryByDisplayID.first(where: { $0.value.screenFrame.contains(mouseLoc) })?.key {
            return underMouse
        }
        return panelsByDisplayID.keys.sorted().first
    }

    private func beginAntiAppNapIfNeeded() {
        guard antiAppNapActivity == nil else { return }
        antiAppNapActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "MacFileExplorer Notch Now Playing overlay"
        )
    }

    private func endAntiAppNapIfNeeded() {
        if let token = antiAppNapActivity {
            ProcessInfo.processInfo.endActivity(token)
            antiAppNapActivity = nil
        }
    }
}
