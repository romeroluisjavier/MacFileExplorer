import AppKit
import CoreGraphics
import SwiftUI

// MARK: - Geometría del Monitor y Estados de Presentación del Notch

/// Geometría exacta de la pantalla incluyendo muesca física (`NSScreen.safeAreaInsets` y áreas auxiliares).
public struct NotchDisplayGeometry: Equatable, Sendable {
    public let displayID: String
    public let localizedName: String
    public let screenFrame: CGRect
    public let visibleFrame: CGRect
    public let hasHardwareNotch: Bool
    public let physicalNotchWidth: CGFloat
    public let physicalNotchHeight: CGFloat
    public let menuBarHeight: CGFloat

    public init(
        displayID: String,
        localizedName: String,
        screenFrame: CGRect,
        visibleFrame: CGRect,
        hasHardwareNotch: Bool,
        physicalNotchWidth: CGFloat,
        physicalNotchHeight: CGFloat,
        menuBarHeight: CGFloat
    ) {
        self.displayID = displayID
        self.localizedName = localizedName
        self.screenFrame = screenFrame
        self.visibleFrame = visibleFrame
        self.hasHardwareNotch = hasHardwareNotch
        self.physicalNotchWidth = physicalNotchWidth
        self.physicalNotchHeight = physicalNotchHeight
        self.menuBarHeight = menuBarHeight
    }

    @MainActor
    public static func detect(for screen: NSScreen, index: Int) -> NotchDisplayGeometry {
        let screenNumber = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        let displayID = screenNumber.map { String($0) } ?? "display-\(index)"
        let frame = screen.frame
        let visible = screen.visibleFrame
        let topSafe = screen.safeAreaInsets.top
        let hasNotch = topSafe > 0.5

        let notchWidth: CGFloat
        let notchHeight: CGFloat
        if hasNotch {
            let leftWidth = screen.auxiliaryTopLeftArea?.width ?? 0
            let rightWidth = screen.auxiliaryTopRightArea?.width ?? 0
            if leftWidth > 0 && rightWidth > 0 {
                let raw = frame.width - leftWidth - rightWidth
                notchWidth = min(max(round(raw), 144), 256)
            } else {
                notchWidth = 196
            }
            notchHeight = max(round(topSafe), 32)
        } else {
            notchWidth = 0
            notchHeight = 0
        }

        let rawMenuHeight = frame.maxY - visible.maxY
        let menuBarHeight: CGFloat = (rawMenuHeight >= 20 && rawMenuHeight <= 60) ? round(rawMenuHeight) : 25

        return NotchDisplayGeometry(
            displayID: displayID,
            localizedName: screen.localizedName,
            screenFrame: frame,
            visibleFrame: visible,
            hasHardwareNotch: hasNotch,
            physicalNotchWidth: notchWidth,
            physicalNotchHeight: notchHeight,
            menuBarHeight: menuBarHeight
        )
    }

    /// Si el monitor no tiene notch físico, el reproductor se presenta como Isla Dinámica flotante 6 pt debajo del menú.
    public var isFloatingIsland: Bool {
        !hasHardwareNotch
    }
}

/// Fase visual animada del reproductor Notch (morfing continuo en 120 Hz dentro del mismo `NSPanel`).
public enum NotchPresentationPhase: Equatable, Sendable {
    case hidden
    case collapsed
    case peeking
    case expandedCompact
    case expandedLyrics

    public var isExpanded: Bool {
        self == .expandedCompact || self == .expandedLyrics
    }
}

/// Métricas calculadas de la silueta visible actual (usadas tanto por SwiftUI como por el hit-testing exacto).
public struct NotchSilhouetteMetrics: Equatable, Sendable {
    public let width: CGFloat
    public let height: CGFloat
    public let topFlareRadius: CGFloat
    public let bottomCornerRadius: CGFloat
    public let topSafeInset: CGFloat

    @MainActor
    public static func compute(
        phase: NotchPresentationPhase,
        geometry: NotchDisplayGeometry,
        prefs: NotchPreferences,
        hasActiveTrack: Bool,
        activeFeedback: NotchTransientFeedback = .none
    ) -> NotchSilhouetteMetrics {
        let isFloating = geometry.isFloatingIsland
        let pillSize = prefs.pillSize

        switch phase {
        case .hidden:
            if isFloating {
                return NotchSilhouetteMetrics(
                    width: 96,
                    height: 6,
                    topFlareRadius: 0,
                    bottomCornerRadius: 3,
                    topSafeInset: 0
                )
            }
            return NotchSilhouetteMetrics(
                width: max(geometry.physicalNotchWidth, 160),
                height: max(geometry.physicalNotchHeight, 32),
                topFlareRadius: 10,
                bottomCornerRadius: 10,
                topSafeInset: geometry.physicalNotchHeight
            )

        case .collapsed:
            if isFloating {
                let showTitle = prefs.showTrackTitleInCollapsedPill && hasActiveTrack
                let width: CGFloat
                switch pillSize {
                case .compact: width = showTitle ? 236 : 124
                case .normal: width = showTitle ? 268 : 138
                case .spacious: width = showTitle ? 302 : 152
                }
                let height: CGFloat = pillSize == .spacious ? 40 : (pillSize == .compact ? 34 : 37)
                return NotchSilhouetteMetrics(
                    width: width,
                    height: height,
                    topFlareRadius: 0,
                    bottomCornerRadius: height * 0.5,
                    topSafeInset: 0
                )
            } else {
                let flare: CGFloat = 11
                let wing = pillSize.collapsedWingWidth
                let width = geometry.physicalNotchWidth + wing * 2 + flare * 2
                let height = max(geometry.physicalNotchHeight, 34)
                return NotchSilhouetteMetrics(
                    width: width,
                    height: height,
                    topFlareRadius: flare,
                    bottomCornerRadius: 13,
                    topSafeInset: geometry.physicalNotchHeight
                )
            }

        case .peeking:
            if activeFeedback.isSidewaysPeeking {
                if isFloating {
                    let height: CGFloat = pillSize == .spacious ? 40 : (pillSize == .compact ? 34 : 37)
                    let width: CGFloat = pillSize == .spacious ? 378 : (pillSize == .compact ? 318 : 348)
                    return NotchSilhouetteMetrics(
                        width: width,
                        height: height,
                        topFlareRadius: 0,
                        bottomCornerRadius: height * 0.5,
                        topSafeInset: 0
                    )
                } else {
                    let flare: CGFloat = 13
                    let extraPerSide: CGFloat = activeFeedback.isPauseFeedback ? 52 : 76
                    let wing = pillSize.collapsedWingWidth + extraPerSide
                    let maxAllowed = max(geometry.physicalNotchWidth + 140, min(geometry.screenFrame.width - 40, 560))
                    let width = min(maxAllowed, geometry.physicalNotchWidth + wing * 2 + flare * 2)
                    let height = max(geometry.physicalNotchHeight, 34)
                    return NotchSilhouetteMetrics(
                        width: width,
                        height: height,
                        topFlareRadius: flare,
                        bottomCornerRadius: 14,
                        topSafeInset: geometry.physicalNotchHeight
                    )
                }
            } else if isFloating {
                let width: CGFloat = activeFeedback.isPauseFeedback
                    ? (pillSize == .spacious ? 316 : (pillSize == .compact ? 266 : 290))
                    : (pillSize == .spacious ? 348 : (pillSize == .compact ? 298 : 324))
                let height: CGFloat = activeFeedback.isPauseFeedback ? 48 : 54
                return NotchSilhouetteMetrics(
                    width: width,
                    height: height,
                    topFlareRadius: 0,
                    bottomCornerRadius: activeFeedback.isPauseFeedback ? 20 : 22,
                    topSafeInset: 0
                )
            } else {
                let flare: CGFloat = 14
                let minNotchSpan = geometry.physicalNotchWidth + pillSize.collapsedWingWidth * 2 + flare * 2
                let targetWidth = max(minNotchSpan, activeFeedback.isPauseFeedback ? 308 : (pillSize == .spacious ? 364 : 334))
                let extraDrop: CGFloat = activeFeedback.isPauseFeedback ? 30 : 36
                let height = max(geometry.physicalNotchHeight, 34) + extraDrop
                return NotchSilhouetteMetrics(
                    width: targetWidth,
                    height: height,
                    topFlareRadius: flare,
                    bottomCornerRadius: 18,
                    topSafeInset: geometry.physicalNotchHeight
                )
            }

        case .expandedCompact:
            let base = pillSize.expandedCompactSize
            if isFloating {
                return NotchSilhouetteMetrics(
                    width: base.width,
                    height: base.height - 16,
                    topFlareRadius: 0,
                    bottomCornerRadius: 26,
                    topSafeInset: 10
                )
            } else {
                let flare: CGFloat = 18
                let topSafe = max(geometry.physicalNotchHeight + 6, 38)
                return NotchSilhouetteMetrics(
                    width: base.width + flare * 2,
                    height: base.height + max(0, topSafe - 24),
                    topFlareRadius: flare,
                    bottomCornerRadius: 24,
                    topSafeInset: topSafe
                )
            }

        case .expandedLyrics:
            let base = pillSize.expandedLyricsSize
            if isFloating {
                return NotchSilhouetteMetrics(
                    width: base.width,
                    height: base.height - 16,
                    topFlareRadius: 0,
                    bottomCornerRadius: 26,
                    topSafeInset: 10
                )
            } else {
                let flare: CGFloat = 18
                let topSafe = max(geometry.physicalNotchHeight + 6, 38)
                return NotchSilhouetteMetrics(
                    width: base.width + flare * 2,
                    height: base.height + max(0, topSafe - 24),
                    topFlareRadius: flare,
                    bottomCornerRadius: 26,
                    topSafeInset: topSafe
                )
            }
        }
    }
}

// MARK: - NSPanel Transparente y No-Activable para el Reproductor Notch

/// Panel flotante sin bordes que nunca roba el foco (`canBecomeKey = false`, `.nonactivatingPanel`),
/// situado sobre la barra de menús y el notch físico. Su tamaño de ventana permanece estable para
/// lograr animaciones ProMotion de 120 Hz con cero tirones de redimensionado de ventana.
@MainActor
public final class NotchOverlayPanel: NSPanel {
    public let displayID: String

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    public init(displayID: String, contentRect: NSRect) {
        self.displayID = displayID
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.becomesKeyOnlyIfNeeded = true
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isReleasedWhenClosed = false
        self.tabbingMode = .disallowed
        self.acceptsMouseMovedEvents = true
        self.ignoresMouseEvents = true
        self.appearance = NSAppearance(named: .darkAqua)
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    }
}

// MARK: - Vista Raíz del Panel Notch (Colapsado ↔ Anuncio de Pista ↔ Expandido ↔ Letras)

public struct NotchOverlayPanelView: View {
    public let displayID: String
    public let geometry: NotchDisplayGeometry

    @Bindable private var manager = NotchManager.shared
    @Bindable private var media = NotchMediaService.shared
    @Bindable private var calService = NotchCalendarService.shared
    @Bindable private var prefs = NotchPreferences.shared
    @Bindable private var loc = LocalizationManager.shared

    public init(displayID: String, geometry: NotchDisplayGeometry) {
        self.displayID = displayID
        self.geometry = geometry
    }

    private var phase: NotchPresentationPhase {
        manager.phase(for: displayID)
    }

    private var track: NotchTrackInfo? {
        media.currentTrack
    }

    private var accentColor: Color {
        prefs.resolvedAccentColor(for: track)
    }

    private var metrics: NotchSilhouetteMetrics {
        NotchSilhouetteMetrics.compute(
            phase: phase,
            geometry: geometry,
            prefs: prefs,
            hasActiveTrack: track != nil,
            activeFeedback: manager.activeFeedback
        )
    }

    private var isColorFlashFeedback: Bool {
        if case .trackChanged(.colorFlash, _) = manager.activeFeedback { return true }
        return false
    }

    private var isColorDimPulseFeedback: Bool {
        if case .paused(.colorDimPulse, _) = manager.activeFeedback { return true }
        return false
    }

    private var isSkipIconSwapFeedback: Bool {
        switch manager.activeFeedback {
        case .trackChanged(.skipIconSwap, _), .trackChanged(.slideNudge, _):
            return true
        default:
            return false
        }
    }

    private var isPauseIconPopFeedback: Bool {
        if case .paused(.pauseIconPop, _) = manager.activeFeedback { return true }
        return false
    }

    private var feedbackPulseRimColor: Color? {
        if isColorFlashFeedback {
            return accentColor
        }
        if isColorDimPulseFeedback {
            return Color.white.opacity(0.75)
        }
        return nil
    }

    private var morphAnimation: Animation? {
        prefs.resolvedAnimation(baseResponse: 0.36)
    }

    public var body: some View {
        let currentMetrics = metrics
        let isFloating = geometry.isFloatingIsland
        let shape = OrganicNotchShape(
            topFlareRadius: currentMetrics.topFlareRadius,
            bottomCornerRadius: currentMetrics.bottomCornerRadius,
            isFloatingIsland: isFloating
        )

        ZStack(alignment: .top) {
            Color.clear

            if phase != .hidden {
                ZStack(alignment: .top) {
                    // Fondo OLED negro + brillo radial ambiental + contorno especular
                    let baseGlow = prefs.effectiveGlowStrength(isExpanded: phase.isExpanded)
                    let boostedGlow: Double = isColorFlashFeedback
                        ? min(0.95, max(0.68, baseGlow * 2.1))
                        : (isColorDimPulseFeedback ? min(0.68, max(0.45, baseGlow * 1.45)) : baseGlow)

                    NotchAmbientBackdropView(
                        accentColor: isColorDimPulseFeedback ? Color.white.opacity(0.85) : accentColor,
                        topFlareRadius: currentMetrics.topFlareRadius,
                        bottomCornerRadius: currentMetrics.bottomCornerRadius,
                        isFloatingIsland: isFloating,
                        showAmbientGlow: prefs.showAmbientArtworkGlow || isColorFlashFeedback || isColorDimPulseFeedback,
                        glowStrength: boostedGlow,
                        backgroundOpacity: prefs.backgroundOpacity,
                        isExpanded: phase.isExpanded || isColorFlashFeedback
                    )

                    if let rimColor = feedbackPulseRimColor {
                        OrganicNotchRimShape(
                            topFlareRadius: currentMetrics.topFlareRadius,
                            bottomCornerRadius: currentMetrics.bottomCornerRadius,
                            isFloatingIsland: isFloating
                        )
                        .stroke(rimColor.opacity(isColorFlashFeedback ? 0.92 : 0.65), lineWidth: isColorFlashFeedback ? 1.8 : 1.3)
                        .shadow(color: rimColor.opacity(0.70), radius: 6)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                    }

                    // Contenido correspondiente a la fase activa
                    Group {
                        switch phase {
                        case .collapsed:
                            collapsedContentView(metrics: currentMetrics)
                                .transition(.opacity)

                        case .peeking:
                            peekingAnnouncementView(metrics: currentMetrics)
                                .transition(.opacity.combined(with: .move(edge: .top)))

                        case .expandedCompact, .expandedLyrics:
                            NotchExpandedContentView(
                                track: track,
                                artworkImage: media.currentArtworkImage,
                                topSafeInset: currentMetrics.topSafeInset,
                                horizontalInset: isFloating ? 16 : (currentMetrics.topFlareRadius + 14),
                                isLyricsPaneOpen: phase == .expandedLyrics,
                                isPinnedOpen: manager.isPinnedOpen,
                                onToggleLyrics: {
                                    manager.toggleLyricsPane(for: displayID)
                                },
                                onTogglePin: {
                                    manager.togglePinned()
                                },
                                onOpenSettings: {
                                    NotchSettingsWindowController.shared.show()
                                },
                                onClose: {
                                    manager.setEnabled(false)
                                }
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))

                        case .hidden:
                            EmptyView()
                        }
                    }
                }
                .frame(width: currentMetrics.width, height: currentMetrics.height, alignment: .top)
                .clipShape(shape)
                .contentShape(shape)
                .shadow(
                    color: Color.black.opacity(phase.isExpanded ? 0.62 : (isFloating ? 0.50 : 0.34)),
                    radius: phase.isExpanded ? 24 : (isFloating ? 14 : 8),
                    x: 0,
                    y: phase.isExpanded ? 12 : (isFloating ? 6 : 4)
                )
                .shadow(
                    color: (prefs.showAmbientArtworkGlow || isColorFlashFeedback || isColorDimPulseFeedback)
                        ? accentColor.opacity(
                            isColorFlashFeedback
                                ? 0.72
                                : (isColorDimPulseFeedback ? 0.42 : ((phase.isExpanded ? 0.36 : (isFloating ? 0.30 : 0.18)) * prefs.ambientGlowIntensity))
                        )
                        : .clear,
                    radius: isColorFlashFeedback ? 20 : (phase.isExpanded ? 18 : 10),
                    x: 0,
                    y: 4
                )
                .scaleEffect(
                    x: manager.pauseSqueezeActive ? 0.93 : 1.0,
                    y: manager.pauseSqueezeActive ? 0.90 : 1.0,
                    anchor: .top
                )
                .offset(x: manager.swipeNudgeOffset(for: displayID))
                .onTapGesture {
                    if !phase.isExpanded {
                        manager.expand(displayID: displayID)
                    }
                }
                .transition(
                    prefs.enableAnimations
                        ? .opacity.combined(with: .scale(scale: 0.85, anchor: .top))
                        : .identity
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(morphAnimation, value: phase)
        .animation(morphAnimation, value: currentMetrics)
        .animation(morphAnimation, value: manager.activeFeedback)
        .animation(
            prefs.enableAnimations ? .spring(response: 0.24, dampingFraction: 0.58) : nil,
            value: manager.pauseSqueezeActive
        )
        .animation(
            prefs.enableAnimations ? .spring(response: 0.28, dampingFraction: 0.62) : nil,
            value: manager.swipeNudgeOffset(for: displayID)
        )
    }

    // MARK: - Estado Colapsado (Alas del Notch Físico o Píldora Isla Dinámica)

    @ViewBuilder
    private func collapsedContentView(metrics: NotchSilhouetteMetrics) -> some View {
        let isPlaying = track?.isPlaying ?? false

        TimelineView(.animation(minimumInterval: 0.5, paused: !isPlaying)) { context in
            let progress = track?.progress(at: context.date) ?? 0

            if geometry.isFloatingIsland {
                floatingCollapsedPill(progress: progress)
            } else {
                notchedCollapsedWings(metrics: metrics, progress: progress)
            }
        }
    }

    /// En MacBooks con notch físico: ala izquierda con carátula + centro negro sobre cámara + ala derecha con ecualizador.
    private func notchedCollapsedWings(metrics: NotchSilhouetteMetrics, progress: Double) -> some View {
        let wingWidth = prefs.pillSize.collapsedWingWidth
        let artSize = prefs.pillSize.collapsedArtworkSize

        return HStack(spacing: 0) {
            // Ala izquierda: carátula (si está activada) o ícono limpio de la app musical
            ZStack {
                if let track {
                    if prefs.showAlbumArtwork {
                        NotchAlbumArtBadgeView(
                            artworkImage: media.currentArtworkImage,
                            trackID: track.id,
                            accentColor: accentColor,
                            progress: progress,
                            style: prefs.artworkStyle,
                            size: artSize,
                            isPlaying: track.isPlaying,
                            enableAnimations: prefs.enableAnimations,
                            showProgressRing: prefs.artworkStyle == .circleWithRing,
                            fallbackSymbol: track.sourceApp.symbolName
                        )
                    } else {
                        collapsedSourceSymbolGlyph(source: track.sourceApp, size: artSize)
                    }
                } else {
                    idleNotchLeftGlyph(size: artSize)
                }
            }
            .frame(width: wingWidth, height: metrics.height, alignment: .center)

            // Hueco central exactamente del ancho de la cámara física (negro puro, nada queda tapado)
            Color.clear
                .frame(width: geometry.physicalNotchWidth, height: metrics.height)

            // Ala derecha: alerta de Meet inminente, ecualizador animado, símbolo de pausa («⏸») o ícono «≫»
            ZStack {
                if prefs.calendarEnabled,
                   prefs.calendarMusicCoexistenceMode != .manualTabOnly,
                   let alertEvent = calService.activeAlertEvent {
                    HStack(spacing: 3) {
                        Image(systemName: alertEvent.hasMeetingLink ? "video.fill" : "calendar")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(Color(red: 0.25, green: 0.92, blue: 0.54))
                        Text(alertEvent.isOngoingNow ? "LIVE" : "\(max(1, alertEvent.minutesUntilStart()))m")
                            .font(.system(size: 9, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(red: 0.12, green: 0.68, blue: 0.38).opacity(0.42)))
                } else if let track {
                    collapsedRightIndicatorView(track: track)
                } else if prefs.calendarEnabled, let nextEv = calService.nextUpcomingEvent {
                    HStack(spacing: 3) {
                        Image(systemName: "calendar")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color(red: 0.42, green: 0.72, blue: 1.0))
                        Text(nextEv.formattedStartTime)
                            .font(.system(size: 9, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                } else {
                    NotchEqualizerVisualizerView(
                        isPlaying: false,
                        accentColor: Color.white.opacity(0.65),
                        barCount: 4,
                        barWidth: 2.3,
                        barSpacing: 2.0,
                        maxHeight: 11,
                        enableAnimations: false,
                        style: prefs.visualizerStyle,
                        speedMultiplier: prefs.animationSpeed
                    )
                }
            }
            .frame(width: wingWidth, height: metrics.height, alignment: .center)
        }
        .padding(.horizontal, metrics.topFlareRadius)
        .frame(width: metrics.width, height: metrics.height)
    }

    /// En pantallas sin notch físico: píldora orgánica flotante estilo Dynamic Island (`[Carátula] Título [Ecualizador]`).
    private func floatingCollapsedPill(progress: Double) -> some View {
        let artSize = prefs.pillSize.collapsedArtworkSize + 1

        return HStack(spacing: 10) {
            if let track {
                if prefs.showAlbumArtwork {
                    NotchAlbumArtBadgeView(
                        artworkImage: media.currentArtworkImage,
                        trackID: track.id,
                        accentColor: accentColor,
                        progress: progress,
                        style: prefs.artworkStyle,
                        size: artSize,
                        isPlaying: track.isPlaying,
                        enableAnimations: prefs.enableAnimations,
                        showProgressRing: prefs.artworkStyle == .circleWithRing,
                        fallbackSymbol: track.sourceApp.symbolName
                    )
                    .fixedSize()
                    .layoutPriority(2)
                } else {
                    collapsedSourceSymbolGlyph(source: track.sourceApp, size: artSize)
                        .fixedSize()
                        .layoutPriority(2)
                }

                if prefs.showTrackTitleInCollapsedPill {
                    NotchMarqueeTextView(
                        text: track.formattedTitleAndArtist,
                        font: .system(size: 12, weight: .semibold),
                        color: Color.white.opacity(0.95),
                        enableMarquee: prefs.enableMarqueeTitle,
                        alignment: .leading,
                        speed: prefs.scaledMarqueeSpeed(26),
                        pauseDuration: 2.0
                    )
                    .frame(minWidth: 0, maxWidth: .infinity)
                } else {
                    Spacer(minLength: 4)
                }

                if prefs.showVisualizerBars || isSkipIconSwapFeedback || manager.activeFeedback.isPauseFeedback || (!track.isPlaying && prefs.showPauseIconWhenPaused) {
                    collapsedRightIndicatorView(track: track)
                        .fixedSize()
                        .layoutPriority(2)
                }
            } else {
                idleNotchLeftGlyph(size: artSize - 2)
                    .fixedSize()
                Text("Notch")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.74))
                Spacer(minLength: 4)
                NotchEqualizerVisualizerView(
                    isPlaying: false,
                    accentColor: Color.white.opacity(0.60),
                    barCount: 4,
                    barWidth: 2.2,
                    barSpacing: 2.0,
                    maxHeight: 10,
                    enableAnimations: false,
                    style: prefs.visualizerStyle,
                    speedMultiplier: prefs.animationSpeed
                )
                .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func collapsedSourceSymbolGlyph(source: NotchMediaSource, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(accentColor.opacity(0.22))
                .overlay(Circle().stroke(accentColor.opacity(0.45), lineWidth: 0.75))
            Image(systemName: source.symbolName)
                .font(.system(size: max(9.5, size * 0.48), weight: .bold))
                .foregroundStyle(accentColor)
        }
        .frame(width: size, height: size)
    }

    private func idleNotchLeftGlyph(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.10))
                .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 0.7))
            Image(systemName: "music.note")
                .font(.system(size: max(9.5, size * 0.44), weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.72))
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func collapsedRightIndicatorView(track: NotchTrackInfo) -> some View {
        let showSkip = isSkipIconSwapFeedback
        let showPause = !showSkip && (
            manager.activeFeedback.isPauseFeedback ||
            (!track.isPlaying && prefs.showPauseIconWhenPaused)
        )

        ZStack {
            if showSkip {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.24))
                        .frame(width: 21, height: 21)
                    Image(systemName: "forward.fill")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(accentColor)
                        .shadow(color: accentColor.opacity(0.75), radius: 4)
                }
                .id("notch-right-skip")
                .transition(.scale(scale: 0.55).combined(with: .opacity))
            } else if showPause {
                ZStack {
                    if isPauseIconPopFeedback {
                        Circle()
                            .fill(accentColor.opacity(0.22))
                            .overlay(
                                Circle()
                                    .stroke(accentColor.opacity(0.70), lineWidth: 1.1)
                            )
                            .frame(width: 21, height: 21)
                    }
                    Image(systemName: "pause.fill")
                        .font(.system(size: isPauseIconPopFeedback ? 10.5 : 11, weight: .bold))
                        .foregroundStyle(isPauseIconPopFeedback ? accentColor : Color.white.opacity(0.88))
                        .shadow(color: accentColor.opacity(isPauseIconPopFeedback ? 0.65 : 0.25), radius: isPauseIconPopFeedback ? 4 : 2)
                }
                .id(isPauseIconPopFeedback ? "notch-right-pause-pop" : "notch-right-pause")
                .transition(.scale(scale: 0.60).combined(with: .opacity))
            } else if prefs.showVisualizerBars {
                NotchEqualizerVisualizerView(
                    isPlaying: track.isPlaying,
                    accentColor: accentColor,
                    barCount: 4,
                    barWidth: 2.5,
                    barSpacing: 2.1,
                    maxHeight: 14,
                    enableAnimations: prefs.enableAnimations,
                    style: prefs.visualizerStyle,
                    speedMultiplier: prefs.animationSpeed
                )
                .id("notch-right-waves")
                .transition(.scale(scale: 0.72).combined(with: .opacity))
            } else {
                Image(systemName: track.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accentColor.opacity(0.92))
                    .id("notch-right-static")
                    .transition(.opacity)
            }
        }
        .animation(prefs.resolvedAnimation(baseResponse: 0.28), value: showSkip)
        .animation(prefs.resolvedAnimation(baseResponse: 0.28), value: showPause)
        .animation(prefs.resolvedAnimation(baseResponse: 0.26), value: isPauseIconPopFeedback)
    }

    // MARK: - Estado de Anuncio de Nueva Canción y Pausa ("Peeking")

    @ViewBuilder
    private func peekingAnnouncementView(metrics: NotchSilhouetteMetrics) -> some View {
        if manager.activeFeedback.isSidewaysPeeking {
            sidewaysPeekingView(metrics: metrics)
        } else {
            dropDownPeekingView(metrics: metrics)
        }
    }

    /// Modo «Ensancharse lateralmente»: mantiene exactamente la altura colapsada y abre a los costados.
    private func sidewaysPeekingView(metrics: NotchSilhouetteMetrics) -> some View {
        let isFloating = geometry.isFloatingIsland
        let isPausedNotice = manager.activeFeedback.isPauseFeedback
        let artSize = prefs.pillSize.collapsedArtworkSize

        return Group {
            if isFloating {
                HStack(spacing: 10) {
                    if let track {
                        if prefs.showAlbumArtwork {
                            NotchAlbumArtBadgeView(
                                artworkImage: media.currentArtworkImage,
                                trackID: track.id,
                                accentColor: accentColor,
                                progress: media.liveProgress(),
                                style: prefs.artworkStyle,
                                size: artSize + 1,
                                isPlaying: isPausedNotice ? false : track.isPlaying,
                                enableAnimations: prefs.enableAnimations,
                                showProgressRing: prefs.artworkStyle == .circleWithRing,
                                fallbackSymbol: track.sourceApp.symbolName
                            )
                            .fixedSize()
                        } else {
                            collapsedSourceSymbolGlyph(source: track.sourceApp, size: artSize + 1)
                                .fixedSize()
                        }

                        if isPausedNotice {
                            HStack(spacing: 6) {
                                Text(loc.text(es: "En pausa", en: "Paused"))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(accentColor)
                                Text("·")
                                    .foregroundStyle(.white.opacity(0.45))
                                Text(track.title)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.92))
                                    .lineLimit(1)
                            }
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        } else {
                            NotchMarqueeTextView(
                                text: track.formattedTitleAndArtist,
                                font: .system(size: 12, weight: .bold),
                                color: .white,
                                enableMarquee: prefs.enableMarqueeTitle,
                                alignment: .leading,
                                speed: prefs.scaledMarqueeSpeed(28),
                                pauseDuration: 0.6
                            )
                            .frame(minWidth: 0, maxWidth: .infinity)
                        }

                        collapsedRightIndicatorView(track: track)
                            .fixedSize()
                    }
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let sideWingWidth = max(48, (metrics.width - geometry.physicalNotchWidth - metrics.topFlareRadius * 2) * 0.5)
                HStack(spacing: 0) {
                    // Ala izquierda expandida: carátula + título de la canción (o estado)
                    HStack(spacing: 7) {
                        if let track {
                            if prefs.showAlbumArtwork {
                                NotchAlbumArtBadgeView(
                                    artworkImage: media.currentArtworkImage,
                                    trackID: track.id,
                                    accentColor: accentColor,
                                    progress: media.liveProgress(),
                                    style: prefs.artworkStyle,
                                    size: artSize,
                                    isPlaying: isPausedNotice ? false : track.isPlaying,
                                    enableAnimations: prefs.enableAnimations,
                                    showProgressRing: prefs.artworkStyle == .circleWithRing,
                                    fallbackSymbol: track.sourceApp.symbolName
                                )
                                .fixedSize()
                            } else {
                                collapsedSourceSymbolGlyph(source: track.sourceApp, size: artSize)
                                    .fixedSize()
                            }

                            Text(isPausedNotice ? loc.text(es: "En pausa", en: "Paused") : track.title)
                                .font(.system(size: 11.2, weight: .semibold))
                                .foregroundStyle(isPausedNotice ? accentColor : .white)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 4)
                    .frame(width: sideWingWidth, height: metrics.height, alignment: .leading)

                    // Zona central sobre la cámara física
                    Color.clear
                        .frame(width: geometry.physicalNotchWidth, height: metrics.height)

                    // Ala derecha expandida: artista/estado + indicador (ondas / «≫» / «⏸»)
                    HStack(spacing: 7) {
                        if let track {
                            Text(isPausedNotice ? track.title : track.displaySubtitle(includeAlbum: false))
                                .font(.system(size: 10.8, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.68))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)

                            collapsedRightIndicatorView(track: track)
                                .fixedSize()
                        }
                    }
                    .padding(.leading, 4)
                    .padding(.trailing, 8)
                    .frame(width: sideWingWidth, height: metrics.height, alignment: .trailing)
                }
                .padding(.horizontal, metrics.topFlareRadius)
                .frame(width: metrics.width, height: metrics.height)
            }
        }
    }

    /// Modo «Desplegar hacia abajo»: baja suavemente debajo del Notch mostrando el aviso y vuelve arriba.
    private func dropDownPeekingView(metrics: NotchSilhouetteMetrics) -> some View {
        let isFloating = geometry.isFloatingIsland
        let isPausedNotice = manager.activeFeedback.isPauseFeedback

        return VStack(spacing: 0) {
            if !isFloating {
                // Zona física de la cámara despejada
                Color.clear
                    .frame(height: max(geometry.physicalNotchHeight, 32))
            }

            if let track {
                HStack(spacing: 10) {
                    if prefs.showAlbumArtwork {
                        NotchAlbumArtBadgeView(
                            artworkImage: media.currentArtworkImage,
                            trackID: track.id,
                            accentColor: accentColor,
                            progress: media.liveProgress(),
                            style: prefs.artworkStyle,
                            size: isFloating ? (isPausedNotice ? 28 : 32) : (isPausedNotice ? 22 : 26),
                            isPlaying: isPausedNotice ? false : track.isPlaying,
                            enableAnimations: prefs.enableAnimations,
                            showProgressRing: prefs.artworkStyle == .circleWithRing,
                            fallbackSymbol: track.sourceApp.symbolName
                        )
                    } else {
                        collapsedSourceSymbolGlyph(source: track.sourceApp, size: isFloating ? 28 : 24)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        NotchMarqueeTextView(
                            text: track.title,
                            font: .system(size: isPausedNotice ? 11.5 : 12, weight: .bold),
                            color: .white,
                            enableMarquee: prefs.enableMarqueeTitle && !isPausedNotice,
                            alignment: .leading,
                            speed: prefs.scaledMarqueeSpeed(28)
                        )
                        .frame(height: 15)

                        if isPausedNotice {
                            HStack(spacing: 4) {
                                Image(systemName: "pause.fill")
                                    .font(.system(size: 8.5, weight: .bold))
                                Text(loc.text(es: "Reproducción en pausa", en: "Playback paused"))
                                    .font(.system(size: 10.2, weight: .semibold))
                            }
                            .foregroundStyle(accentColor.opacity(0.95))
                            .lineLimit(1)
                        } else {
                            Text(track.displaySubtitle(includeAlbum: prefs.showAlbumName))
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.66))
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 4)

                    if prefs.showVisualizerBars || isPausedNotice {
                        collapsedRightIndicatorView(track: track)
                    }
                }
                .padding(.horizontal, isFloating ? 13 : (metrics.topFlareRadius + 12))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }
}
