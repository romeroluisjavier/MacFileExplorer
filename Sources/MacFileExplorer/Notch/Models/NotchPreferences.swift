import Foundation
import Observation
import SwiftUI

/// Preferencias reactivas y persistentes del reproductor **Notch** (estilo Notchy) integrado en `MacFileExplorer`.
///
/// Sigue la misma convención segura de `TaskbarPreferences` y `AltTabPreferences`:
/// - Arranca desactivado de fábrica (`startEnabledByDefault = false`, `isEnabled = startEnabledByDefault`)
///   para no sorprender al usuario al actualizar, y puede activarse en cualquier momento desde el menú superior `Notch`.
/// - Todas las opciones visuales y de comportamiento se persisten inmediatamente en `UserDefaults`.
@MainActor
@Observable
public final class NotchPreferences {

    public static let shared = NotchPreferences()

    public static let minHoverExpandDelay: Double = 0.05
    public static let maxHoverExpandDelay: Double = 0.60
    public static let defaultHoverExpandDelay: Double = 0.18

    public static let minHideWhenPausedDelay: Double = 5.0
    public static let maxHideWhenPausedDelay: Double = 300.0
    public static let defaultHideWhenPausedDelay: Double = 30.0

    public static let minYouTubeMusicAPIPort: Int = 1024
    public static let maxYouTubeMusicAPIPort: Int = 65535
    public static let defaultYouTubeMusicAPIPort: Int = 26538

    public static let minAnimationSpeed: Double = 0.5
    public static let maxAnimationSpeed: Double = 2.0
    public static let defaultAnimationSpeed: Double = 1.0

    public static let minAmbientGlowIntensity: Double = 0.10
    public static let maxAmbientGlowIntensity: Double = 1.00
    public static let defaultAmbientGlowIntensity: Double = 0.55

    public static let minBackgroundOpacity: Double = 0.70
    public static let maxBackgroundOpacity: Double = 1.00
    public static let defaultBackgroundOpacity: Double = 1.00

    private let defaults: UserDefaults
    private var isBootstrapping = false

    private enum Keys {
        static let startEnabledByDefault = "com.macfileexplorer.notch.startEnabledByDefault"
        static let artworkStyle = "com.macfileexplorer.notch.artworkStyle"
        static let pillSize = "com.macfileexplorer.notch.pillSize"
        static let displayMode = "com.macfileexplorer.notch.displayMode"
        static let expandTrigger = "com.macfileexplorer.notch.expandTrigger"
        static let hoverExpandDelay = "com.macfileexplorer.notch.hoverExpandDelay"
        static let showTrackTitleInCollapsedPill = "com.macfileexplorer.notch.showTrackTitleInCollapsedPill"
        static let enableMarqueeTitle = "com.macfileexplorer.notch.enableMarqueeTitle"
        static let announceNewTracks = "com.macfileexplorer.notch.announceNewTracks"
        static let showVisualizerBars = "com.macfileexplorer.notch.showVisualizerBars"
        static let showAmbientArtworkGlow = "com.macfileexplorer.notch.showAmbientArtworkGlow"
        static let showSyncedLyrics = "com.macfileexplorer.notch.showSyncedLyrics"
        static let hideWhenPaused = "com.macfileexplorer.notch.hideWhenPaused"
        static let hideWhenPausedDelay = "com.macfileexplorer.notch.hideWhenPausedDelay"
        static let hideInFullScreen = "com.macfileexplorer.notch.hideInFullScreen"
        static let enableSwipeToSkip = "com.macfileexplorer.notch.enableSwipeToSkip"
        static let enableAnimations = "com.macfileexplorer.notch.enableAnimations"
        static let youtubeMusicAPIPort = "com.macfileexplorer.notch.youtubeMusicAPIPort"
        // 10 nuevas configuraciones avanzadas de personalización del Notch
        static let accentColorMode = "com.macfileexplorer.notch.accentColorMode"
        static let customAccentColorR = "com.macfileexplorer.notch.customAccentColor.r"
        static let customAccentColorG = "com.macfileexplorer.notch.customAccentColor.g"
        static let customAccentColorB = "com.macfileexplorer.notch.customAccentColor.b"
        static let animationStyle = "com.macfileexplorer.notch.animationStyle"
        static let animationSpeed = "com.macfileexplorer.notch.animationSpeed"
        static let showAlbumArtwork = "com.macfileexplorer.notch.showAlbumArtwork"
        static let showAlbumName = "com.macfileexplorer.notch.showAlbumName"
        static let visualizerStyle = "com.macfileexplorer.notch.visualizerStyle"
        static let ambientGlowIntensity = "com.macfileexplorer.notch.ambientGlowIntensity"
        static let backgroundOpacity = "com.macfileexplorer.notch.backgroundOpacity"
        static let showSourceBadgeOnArtwork = "com.macfileexplorer.notch.showSourceBadgeOnArtwork"
        static let lyricsFontSize = "com.macfileexplorer.notch.lyricsFontSize"
        static let lastPlayedSource = "com.macfileexplorer.notch.lastPlayedSource"
        static let lastPlayedBundleID = "com.macfileexplorer.notch.lastPlayedBundleID"
        static let lastPlayedAppName = "com.macfileexplorer.notch.lastPlayedAppName"
        static let lastPlayedTrackTitle = "com.macfileexplorer.notch.lastPlayedTrackTitle"
        static let lastPlayedTrackArtist = "com.macfileexplorer.notch.lastPlayedTrackArtist"
        static let lastPlayedTrackURL = "com.macfileexplorer.notch.lastPlayedTrackURL"
    }

    /// Callbacks conectados por `NotchManager` para sincronizar paneles y layout al instante.
    public var onEnabledChanged: ((Bool) -> Void)?
    public var onAppearanceOrLayoutChanged: (() -> Void)?

    // MARK: - Estado Principal

    /// Estado activo del reproductor Notch en la sesión actual.
    public var isEnabled: Bool {
        didSet {
            guard !isBootstrapping, isEnabled != oldValue else { return }
            onEnabledChanged?(isEnabled)
            StatusBarManager.shared.refreshTooltipAndMenu()
        }
    }

    /// Define si Notch debe arrancar activado automáticamente al abrir `MacFileExplorer` (`false` de fábrica).
    public var startEnabledByDefault: Bool {
        didSet {
            guard !isBootstrapping, startEnabledByDefault != oldValue else { return }
            defaults.set(startEnabledByDefault, forKey: Keys.startEnabledByDefault)
        }
    }

    // MARK: - Apariencia y Diseño

    public var artworkStyle: NotchArtworkStyle {
        didSet {
            guard !isBootstrapping, artworkStyle != oldValue else { return }
            defaults.set(artworkStyle.rawValue, forKey: Keys.artworkStyle)
            onAppearanceOrLayoutChanged?()
        }
    }

    public var pillSize: NotchPillSize {
        didSet {
            guard !isBootstrapping, pillSize != oldValue else { return }
            defaults.set(pillSize.rawValue, forKey: Keys.pillSize)
            onAppearanceOrLayoutChanged?()
        }
    }

    public var displayMode: NotchDisplayMode {
        didSet {
            guard !isBootstrapping, displayMode != oldValue else { return }
            defaults.set(displayMode.rawValue, forKey: Keys.displayMode)
            onAppearanceOrLayoutChanged?()
        }
    }

    public var expandTrigger: NotchExpandTrigger {
        didSet {
            guard !isBootstrapping, expandTrigger != oldValue else { return }
            defaults.set(expandTrigger.rawValue, forKey: Keys.expandTrigger)
            onAppearanceOrLayoutChanged?()
        }
    }

    public var hoverExpandDelay: Double {
        didSet {
            let clamped = min(max(hoverExpandDelay, Self.minHoverExpandDelay), Self.maxHoverExpandDelay)
            if clamped != hoverExpandDelay {
                hoverExpandDelay = clamped
                return
            }
            guard !isBootstrapping, clamped != oldValue else { return }
            defaults.set(clamped, forKey: Keys.hoverExpandDelay)
        }
    }

    // MARK: - Contenido y Efectos Visuales

    public var showTrackTitleInCollapsedPill: Bool {
        didSet {
            guard !isBootstrapping, showTrackTitleInCollapsedPill != oldValue else { return }
            defaults.set(showTrackTitleInCollapsedPill, forKey: Keys.showTrackTitleInCollapsedPill)
            onAppearanceOrLayoutChanged?()
        }
    }

    public var enableMarqueeTitle: Bool {
        didSet {
            guard !isBootstrapping, enableMarqueeTitle != oldValue else { return }
            defaults.set(enableMarqueeTitle, forKey: Keys.enableMarqueeTitle)
            onAppearanceOrLayoutChanged?()
        }
    }

    public var announceNewTracks: Bool {
        didSet {
            guard !isBootstrapping, announceNewTracks != oldValue else { return }
            defaults.set(announceNewTracks, forKey: Keys.announceNewTracks)
        }
    }

    public var showVisualizerBars: Bool {
        didSet {
            guard !isBootstrapping, showVisualizerBars != oldValue else { return }
            defaults.set(showVisualizerBars, forKey: Keys.showVisualizerBars)
            onAppearanceOrLayoutChanged?()
        }
    }

    public var showAmbientArtworkGlow: Bool {
        didSet {
            guard !isBootstrapping, showAmbientArtworkGlow != oldValue else { return }
            defaults.set(showAmbientArtworkGlow, forKey: Keys.showAmbientArtworkGlow)
            onAppearanceOrLayoutChanged?()
        }
    }

    public var showSyncedLyrics: Bool {
        didSet {
            guard !isBootstrapping, showSyncedLyrics != oldValue else { return }
            defaults.set(showSyncedLyrics, forKey: Keys.showSyncedLyrics)
            onAppearanceOrLayoutChanged?()
            if showSyncedLyrics, let track = NotchMediaService.shared.currentTrack {
                NotchLyricsAndAudioService.shared.updateLyrics(for: track)
            }
        }
    }

    // MARK: - Visibilidad, Gestos y Animaciones

    public var hideWhenPaused: Bool {
        didSet {
            guard !isBootstrapping, hideWhenPaused != oldValue else { return }
            defaults.set(hideWhenPaused, forKey: Keys.hideWhenPaused)
            onAppearanceOrLayoutChanged?()
        }
    }

    public var hideWhenPausedDelay: Double {
        didSet {
            let clamped = min(max(hideWhenPausedDelay, Self.minHideWhenPausedDelay), Self.maxHideWhenPausedDelay)
            if clamped != hideWhenPausedDelay {
                hideWhenPausedDelay = clamped
                return
            }
            guard !isBootstrapping, clamped != oldValue else { return }
            defaults.set(clamped, forKey: Keys.hideWhenPausedDelay)
        }
    }

    public var hideInFullScreen: Bool {
        didSet {
            guard !isBootstrapping, hideInFullScreen != oldValue else { return }
            defaults.set(hideInFullScreen, forKey: Keys.hideInFullScreen)
            onAppearanceOrLayoutChanged?()
        }
    }

    public var enableSwipeToSkip: Bool {
        didSet {
            guard !isBootstrapping, enableSwipeToSkip != oldValue else { return }
            defaults.set(enableSwipeToSkip, forKey: Keys.enableSwipeToSkip)
        }
    }

    public var enableAnimations: Bool {
        didSet {
            guard !isBootstrapping, enableAnimations != oldValue else { return }
            defaults.set(enableAnimations, forKey: Keys.enableAnimations)
            onAppearanceOrLayoutChanged?()
        }
    }

    // MARK: - Personalización Avanzada (10 Opciones de Color, Animación, Carátula y Letras)

    /// 1. Modo de color de acento (`Carátula automática` / `Color de la app` / `Personalizado`).
    public var accentColorMode: NotchAccentColorMode {
        didSet {
            guard !isBootstrapping, accentColorMode != oldValue else { return }
            defaults.set(accentColorMode.rawValue, forKey: Keys.accentColorMode)
            onAppearanceOrLayoutChanged?()
        }
    }

    /// Color personalizado utilizado cuando `accentColorMode == .custom`.
    public var customAccentColor: NotchRGBColor {
        didSet {
            guard !isBootstrapping, customAccentColor != oldValue else { return }
            defaults.set(customAccentColor.r, forKey: Keys.customAccentColorR)
            defaults.set(customAccentColor.g, forKey: Keys.customAccentColorG)
            defaults.set(customAccentColor.b, forKey: Keys.customAccentColorB)
            onAppearanceOrLayoutChanged?()
        }
    }

    /// 2. Tipo / personalidad de animación (`Elástico`, `Fluido`, `Preciso`, `Suave`).
    public var animationStyle: NotchAnimationStyle {
        didSet {
            guard !isBootstrapping, animationStyle != oldValue else { return }
            defaults.set(animationStyle.rawValue, forKey: Keys.animationStyle)
            onAppearanceOrLayoutChanged?()
        }
    }

    /// 3. Velocidad global de las animaciones (`0.5×` a `2.0×`: expansión, ecualizador y marquee).
    public var animationSpeed: Double {
        didSet {
            let clamped = min(max(animationSpeed, Self.minAnimationSpeed), Self.maxAnimationSpeed)
            if clamped != animationSpeed {
                animationSpeed = clamped
                return
            }
            guard !isBootstrapping, clamped != oldValue else { return }
            defaults.set(clamped, forKey: Keys.animationSpeed)
        }
    }

    /// 4. Mostrar u ocultar la tapa del álbum (carátula) tanto en colapsado como expandido.
    public var showAlbumArtwork: Bool {
        didSet {
            guard !isBootstrapping, showAlbumArtwork != oldValue else { return }
            defaults.set(showAlbumArtwork, forKey: Keys.showAlbumArtwork)
            onAppearanceOrLayoutChanged?()
        }
    }

    /// 5. Mostrar u ocultar el nombre del álbum junto al artista cuando esté disponible.
    public var showAlbumName: Bool {
        didSet {
            guard !isBootstrapping, showAlbumName != oldValue else { return }
            defaults.set(showAlbumName, forKey: Keys.showAlbumName)
            onAppearanceOrLayoutChanged?()
        }
    }

    /// 6. Estilo visual del ecualizador animado (`Barras`, `Onda`, `Puntos`, `Pulso`).
    public var visualizerStyle: NotchVisualizerStyle {
        didSet {
            guard !isBootstrapping, visualizerStyle != oldValue else { return }
            defaults.set(visualizerStyle.rawValue, forKey: Keys.visualizerStyle)
            onAppearanceOrLayoutChanged?()
        }
    }

    /// 7. Intensidad del resplandor ambiental (`0.10...1.00`).
    public var ambientGlowIntensity: Double {
        didSet {
            let clamped = min(max(ambientGlowIntensity, Self.minAmbientGlowIntensity), Self.maxAmbientGlowIntensity)
            if clamped != ambientGlowIntensity {
                ambientGlowIntensity = clamped
                return
            }
            guard !isBootstrapping, clamped != oldValue else { return }
            defaults.set(clamped, forKey: Keys.ambientGlowIntensity)
        }
    }

    /// 8. Opacidad del fondo del Notch (`0.70` vidrio oscuro translúcido ↔ `1.00` negro OLED puro).
    public var backgroundOpacity: Double {
        didSet {
            let clamped = min(max(backgroundOpacity, Self.minBackgroundOpacity), Self.maxBackgroundOpacity)
            if clamped != backgroundOpacity {
                backgroundOpacity = clamped
                return
            }
            guard !isBootstrapping, clamped != oldValue else { return }
            defaults.set(clamped, forKey: Keys.backgroundOpacity)
        }
    }

    /// 9. Mostrar la mini-insignia de la app musical (YouTube Music / Spotify / Apple Music) sobre la carátula.
    public var showSourceBadgeOnArtwork: Bool {
        didSet {
            guard !isBootstrapping, showSourceBadgeOnArtwork != oldValue else { return }
            defaults.set(showSourceBadgeOnArtwork, forKey: Keys.showSourceBadgeOnArtwork)
            onAppearanceOrLayoutChanged?()
        }
    }

    /// 10. Tamaño tipográfico de las letras sincronizadas (`Compacto`, `Normal`, `Grande`).
    public var lyricsFontSize: NotchLyricsFontSize {
        didSet {
            guard !isBootstrapping, lyricsFontSize != oldValue else { return }
            defaults.set(lyricsFontSize.rawValue, forKey: Keys.lyricsFontSize)
            onAppearanceOrLayoutChanged?()
        }
    }

    // MARK: - Helpers Visuales Derivados

    /// Resuelve el color de acento activo según `accentColorMode` y la pista actual.
    public func resolvedAccentColor(for track: NotchTrackInfo?) -> Color {
        switch accentColorMode {
        case .dynamicArtwork:
            if let track {
                return track.dominantColor.swiftUIColor
            }
            return lastPlayedSource?.swiftUIAccentColor ?? NotchMediaSource.youtubeMusic.swiftUIAccentColor
        case .sourceBrand:
            if let track {
                return track.sourceApp.swiftUIAccentColor
            }
            return lastPlayedSource?.swiftUIAccentColor ?? NotchMediaSource.youtubeMusic.swiftUIAccentColor
        case .custom:
            return customAccentColor.swiftUIColor
        }
    }

    /// Devuelve la animación SwiftUI configurada por el usuario (o `nil` si las animaciones están apagadas).
    public func resolvedAnimation(baseResponse: Double = 0.36) -> Animation? {
        guard enableAnimations else { return nil }
        return animationStyle.makeAnimation(baseResponse: baseResponse, speedMultiplier: animationSpeed)
    }

    /// Calcula la fuerza real del brillo radial ambiental según el deslizador `ambientGlowIntensity`.
    public func effectiveGlowStrength(isExpanded: Bool) -> Double {
        let base = isExpanded ? 0.56 : 0.36
        return base * ambientGlowIntensity
    }

    /// Escala la velocidad del desplazamiento Marquee según `animationSpeed`.
    public func scaledMarqueeSpeed(_ baseSpeed: CGFloat) -> CGFloat {
        baseSpeed * CGFloat(animationSpeed)
    }

    // MARK: - Integración YouTube Music Desktop API

    public var youtubeMusicAPIPort: Int {
        didSet {
            let clamped = min(max(youtubeMusicAPIPort, Self.minYouTubeMusicAPIPort), Self.maxYouTubeMusicAPIPort)
            if clamped != youtubeMusicAPIPort {
                youtubeMusicAPIPort = clamped
                return
            }
            guard !isBootstrapping, clamped != oldValue else { return }
            defaults.set(clamped, forKey: Keys.youtubeMusicAPIPort)
        }
    }

    // MARK: - Última Reproducción (Para Reabrir al Estar en Espera)

    public private(set) var lastPlayedSource: NotchMediaSource?
    public private(set) var lastPlayedBundleID: String?
    public private(set) var lastPlayedAppName: String?
    public private(set) var lastPlayedTrackTitle: String?
    public private(set) var lastPlayedTrackArtist: String?
    public private(set) var lastPlayedTrackURL: String?

    /// Registra de forma persistente el último reproductor y canción escuchados para ofrecer reabrirlos cuando no suena nada.
    public func recordLastPlayed(track: NotchTrackInfo, videoId: String? = nil) {
        let trimmedTitle = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let nextURL: String?
        if let vid = videoId, !vid.isEmpty {
            nextURL = "https://music.youtube.com/watch?v=\(vid)"
        } else if lastPlayedTrackTitle == trimmedTitle && lastPlayedSource == track.sourceApp {
            nextURL = lastPlayedTrackURL
        } else {
            nextURL = nil
        }

        let changed = lastPlayedSource != track.sourceApp ||
            lastPlayedBundleID != track.sourceBundleID ||
            lastPlayedAppName != track.sourceAppName ||
            lastPlayedTrackTitle != trimmedTitle ||
            lastPlayedTrackArtist != track.artist ||
            lastPlayedTrackURL != nextURL

        guard changed else { return }

        lastPlayedSource = track.sourceApp
        lastPlayedBundleID = track.sourceBundleID
        lastPlayedAppName = track.sourceAppName
        lastPlayedTrackTitle = trimmedTitle
        lastPlayedTrackArtist = track.artist.isEmpty ? nil : track.artist
        lastPlayedTrackURL = nextURL

        defaults.set(track.sourceApp.rawValue, forKey: Keys.lastPlayedSource)
        defaults.set(track.sourceBundleID, forKey: Keys.lastPlayedBundleID)
        defaults.set(track.sourceAppName, forKey: Keys.lastPlayedAppName)
        defaults.set(trimmedTitle, forKey: Keys.lastPlayedTrackTitle)
        defaults.set(lastPlayedTrackArtist, forKey: Keys.lastPlayedTrackArtist)
        defaults.set(nextURL, forKey: Keys.lastPlayedTrackURL)
    }

    // MARK: - Inicialización

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isBootstrapping = true

        let savedStartByDefault = defaults.object(forKey: Keys.startEnabledByDefault) as? Bool ?? false
        self.startEnabledByDefault = savedStartByDefault
        self.isEnabled = savedStartByDefault

        self.artworkStyle = (defaults.string(forKey: Keys.artworkStyle).flatMap(NotchArtworkStyle.init(rawValue:))) ?? .circleWithRing
        self.pillSize = (defaults.string(forKey: Keys.pillSize).flatMap(NotchPillSize.init(rawValue:))) ?? .normal
        self.displayMode = (defaults.string(forKey: Keys.displayMode).flatMap(NotchDisplayMode.init(rawValue:))) ?? .notchDisplayOnly
        self.expandTrigger = (defaults.string(forKey: Keys.expandTrigger).flatMap(NotchExpandTrigger.init(rawValue:))) ?? .hoverAndClick

        let savedHoverDelay = defaults.object(forKey: Keys.hoverExpandDelay) as? Double ?? Self.defaultHoverExpandDelay
        self.hoverExpandDelay = min(max(savedHoverDelay, Self.minHoverExpandDelay), Self.maxHoverExpandDelay)

        self.showTrackTitleInCollapsedPill = defaults.object(forKey: Keys.showTrackTitleInCollapsedPill) as? Bool ?? true
        self.enableMarqueeTitle = defaults.object(forKey: Keys.enableMarqueeTitle) as? Bool ?? true
        self.announceNewTracks = defaults.object(forKey: Keys.announceNewTracks) as? Bool ?? true
        self.showVisualizerBars = defaults.object(forKey: Keys.showVisualizerBars) as? Bool ?? true
        self.showAmbientArtworkGlow = defaults.object(forKey: Keys.showAmbientArtworkGlow) as? Bool ?? true
        self.showSyncedLyrics = defaults.object(forKey: Keys.showSyncedLyrics) as? Bool ?? true

        self.hideWhenPaused = defaults.object(forKey: Keys.hideWhenPaused) as? Bool ?? false
        let savedPausedDelay = defaults.object(forKey: Keys.hideWhenPausedDelay) as? Double ?? Self.defaultHideWhenPausedDelay
        self.hideWhenPausedDelay = min(max(savedPausedDelay, Self.minHideWhenPausedDelay), Self.maxHideWhenPausedDelay)

        self.hideInFullScreen = defaults.object(forKey: Keys.hideInFullScreen) as? Bool ?? true
        self.enableSwipeToSkip = defaults.object(forKey: Keys.enableSwipeToSkip) as? Bool ?? true
        self.enableAnimations = defaults.object(forKey: Keys.enableAnimations) as? Bool ?? true

        let savedPort = defaults.object(forKey: Keys.youtubeMusicAPIPort) as? Int ?? Self.defaultYouTubeMusicAPIPort
        self.youtubeMusicAPIPort = min(max(savedPort, Self.minYouTubeMusicAPIPort), Self.maxYouTubeMusicAPIPort)

        self.accentColorMode = (defaults.string(forKey: Keys.accentColorMode).flatMap(NotchAccentColorMode.init(rawValue:))) ?? .dynamicArtwork
        let savedR = defaults.object(forKey: Keys.customAccentColorR) as? Double ?? NotchRGBColor.defaultAccent.r
        let savedG = defaults.object(forKey: Keys.customAccentColorG) as? Double ?? NotchRGBColor.defaultAccent.g
        let savedB = defaults.object(forKey: Keys.customAccentColorB) as? Double ?? NotchRGBColor.defaultAccent.b
        self.customAccentColor = NotchRGBColor(r: savedR, g: savedG, b: savedB)
        self.animationStyle = (defaults.string(forKey: Keys.animationStyle).flatMap(NotchAnimationStyle.init(rawValue:))) ?? .smoothFluid
        let savedAnimSpeed = defaults.object(forKey: Keys.animationSpeed) as? Double ?? Self.defaultAnimationSpeed
        self.animationSpeed = min(max(savedAnimSpeed, Self.minAnimationSpeed), Self.maxAnimationSpeed)
        self.showAlbumArtwork = defaults.object(forKey: Keys.showAlbumArtwork) as? Bool ?? true
        self.showAlbumName = defaults.object(forKey: Keys.showAlbumName) as? Bool ?? true
        self.visualizerStyle = (defaults.string(forKey: Keys.visualizerStyle).flatMap(NotchVisualizerStyle.init(rawValue:))) ?? .classicBars
        let savedGlow = defaults.object(forKey: Keys.ambientGlowIntensity) as? Double ?? Self.defaultAmbientGlowIntensity
        self.ambientGlowIntensity = min(max(savedGlow, Self.minAmbientGlowIntensity), Self.maxAmbientGlowIntensity)
        let savedBgOpacity = defaults.object(forKey: Keys.backgroundOpacity) as? Double ?? Self.defaultBackgroundOpacity
        self.backgroundOpacity = min(max(savedBgOpacity, Self.minBackgroundOpacity), Self.maxBackgroundOpacity)
        self.showSourceBadgeOnArtwork = defaults.object(forKey: Keys.showSourceBadgeOnArtwork) as? Bool ?? true
        self.lyricsFontSize = (defaults.string(forKey: Keys.lyricsFontSize).flatMap(NotchLyricsFontSize.init(rawValue:))) ?? .normal

        self.lastPlayedSource = defaults.string(forKey: Keys.lastPlayedSource).flatMap(NotchMediaSource.init(rawValue:))
        self.lastPlayedBundleID = defaults.string(forKey: Keys.lastPlayedBundleID)
        self.lastPlayedAppName = defaults.string(forKey: Keys.lastPlayedAppName)
        self.lastPlayedTrackTitle = defaults.string(forKey: Keys.lastPlayedTrackTitle)
        self.lastPlayedTrackArtist = defaults.string(forKey: Keys.lastPlayedTrackArtist)
        self.lastPlayedTrackURL = defaults.string(forKey: Keys.lastPlayedTrackURL)

        self.isBootstrapping = false
    }

    // MARK: - Restablecer Valores por Defecto

    /// Restaura las opciones visuales y de comportamiento a sus valores recomendados sin desactivar la sesión actual.
    public func resetDefaults() {
        artworkStyle = .circleWithRing
        pillSize = .normal
        displayMode = .notchDisplayOnly
        expandTrigger = .hoverAndClick
        hoverExpandDelay = Self.defaultHoverExpandDelay
        showTrackTitleInCollapsedPill = true
        enableMarqueeTitle = true
        announceNewTracks = true
        showVisualizerBars = true
        showAmbientArtworkGlow = true
        showSyncedLyrics = true
        hideWhenPaused = false
        hideWhenPausedDelay = Self.defaultHideWhenPausedDelay
        hideInFullScreen = true
        enableSwipeToSkip = true
        enableAnimations = true
        youtubeMusicAPIPort = Self.defaultYouTubeMusicAPIPort
        accentColorMode = .dynamicArtwork
        customAccentColor = .defaultAccent
        animationStyle = .smoothFluid
        animationSpeed = Self.defaultAnimationSpeed
        showAlbumArtwork = true
        showAlbumName = true
        visualizerStyle = .classicBars
        ambientGlowIntensity = Self.defaultAmbientGlowIntensity
        backgroundOpacity = Self.defaultBackgroundOpacity
        showSourceBadgeOnArtwork = true
        lyricsFontSize = .normal
    }
}
