import AppKit
import CoreAudio
import Foundation
import SwiftUI

// MARK: - Color Dominante (Sendable + Equatable)

/// Representa un color RGB normalizado (`0.0...1.0`) extraído de la carátula o del color de marca de la fuente.
/// Expone `.r`, `.g`, `.b` junto con conversiones directas a SwiftUI (`swiftUIColor`) y AppKit (`nsColor`).
public struct NotchRGBColor: Equatable, Hashable, Codable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = min(max(r, 0.0), 1.0)
        self.g = min(max(g, 0.0), 1.0)
        self.b = min(max(b, 0.0), 1.0)
    }

    public var tuple: (r: Double, g: Double, b: Double) {
        (r: r, g: g, b: b)
    }

    public var swiftUIColor: Color {
        Color(red: r, green: g, blue: b)
    }

    public var nsColor: NSColor {
        NSColor(calibratedRed: r, green: g, blue: b, alpha: 1.0)
    }

    public init(nsColor: NSColor) {
        let converted = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.init(
            r: Double(converted.redComponent),
            g: Double(converted.greenComponent),
            b: Double(converted.blueComponent)
        )
    }

    public static let defaultAccent = NotchRGBColor(r: 0.96, g: 0.24, b: 0.36)

    /// Paleta curada de colores de acento rápidos para personalizar el Notch en 1 clic.
    public static let presetPalette: [(id: String, nameES: String, nameEN: String, color: NotchRGBColor)] = [
        ("crimson", "Carmesí", "Crimson", NotchRGBColor(r: 0.98, g: 0.22, b: 0.38)),
        ("violet", "Violeta Neón", "Neon Violet", NotchRGBColor(r: 0.66, g: 0.36, b: 0.99)),
        ("cobalt", "Azul Eléctrico", "Electric Blue", NotchRGBColor(r: 0.22, g: 0.58, b: 1.00)),
        ("cyan", "Cian", "Cyan", NotchRGBColor(r: 0.14, g: 0.80, b: 0.94)),
        ("emerald", "Esmeralda", "Emerald", NotchRGBColor(r: 0.14, g: 0.80, b: 0.45)),
        ("amber", "Ámbar Dorado", "Amber Gold", NotchRGBColor(r: 0.99, g: 0.68, b: 0.16)),
        ("coral", "Coral", "Coral", NotchRGBColor(r: 1.00, g: 0.42, b: 0.28)),
        ("pearl", "Blanco Perla", "Pearl White", NotchRGBColor(r: 0.92, g: 0.94, b: 0.98))
    ]
}

// MARK: - Fuente de Reproducción y Modos de Repetición

/// Modo de repetición de la reproducción actual.
public enum NotchRepeatMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case off
    case all
    case one

    public var id: String { rawValue }

    public var isActive: Bool {
        self != .off
    }

    public var symbolName: String {
        switch self {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .off: return loc.text(es: "Sin repetición", en: "Repeat Off")
        case .all: return loc.text(es: "Repetir lista", en: "Repeat All")
        case .one: return loc.text(es: "Repetir canción", en: "Repeat One")
        }
    }
}

/// Aplicación o fuente de origen de la pista actualmente en reproducción.
public enum NotchMediaSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case youtubeMusic
    case spotify
    case appleMusic
    case browser
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .youtubeMusic: return "YouTube Music"
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        case .browser: return "Browser"
        case .other: return "Media"
        }
    }

    @MainActor
    public func localizedDisplayName(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .youtubeMusic: return "YouTube Music"
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        case .browser: return loc.text(es: "Navegador", en: "Browser")
        case .other: return loc.text(es: "Multimedia", en: "Media")
        }
    }

    public var symbolName: String {
        switch self {
        case .youtubeMusic: return "play.circle.fill"
        case .spotify: return "dot.radiowaves.left.and.right"
        case .appleMusic: return "music.note"
        case .browser: return "globe"
        case .other: return "music.quarternote.3"
        }
    }

    public var brandAccentColor: NotchRGBColor {
        switch self {
        case .youtubeMusic: return NotchRGBColor(r: 0.99, g: 0.14, b: 0.24)
        case .spotify: return NotchRGBColor(r: 0.11, g: 0.73, b: 0.33)
        case .appleMusic: return NotchRGBColor(r: 0.98, g: 0.18, b: 0.33)
        case .browser: return NotchRGBColor(r: 0.34, g: 0.56, b: 0.98)
        case .other: return NotchRGBColor(r: 0.62, g: 0.44, b: 0.98)
        }
    }

    public var swiftUIAccentColor: Color {
        brandAccentColor.swiftUIColor
    }

    /// Devuelve el ícono real de la aplicación instalada en macOS (cacheado en memoria en el hilo principal).
    @MainActor
    public func appIcon(bundleID: String? = nil) -> NSImage? {
        NotchSourceIconCache.icon(for: self, bundleID: bundleID)
    }

    /// Resuelve la URL local de la app `.app` instalada en macOS para esta fuente musical (si existe).
    @MainActor
    public func resolveInstalledAppURL(bundleID: String? = nil) -> URL? {
        NotchSourceIconCache.resolveApplicationURL(for: self, bundleID: bundleID)
    }
}

/// Acceso rápido para volver a abrir la última app reproducida u otra app musical instalada cuando no suena música.
public struct NotchQuickLaunchApp: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let source: NotchMediaSource
    public let bundleID: String?
    public let appURL: URL?
    public let fallbackWebURL: URL?
    public let isLastPlayed: Bool
    public let lastTrackSubtitle: String?

    public init(
        id: String,
        name: String,
        source: NotchMediaSource,
        bundleID: String? = nil,
        appURL: URL? = nil,
        fallbackWebURL: URL? = nil,
        isLastPlayed: Bool = false,
        lastTrackSubtitle: String? = nil
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.bundleID = bundleID
        self.appURL = appURL
        self.fallbackWebURL = fallbackWebURL
        self.isLastPlayed = isLastPlayed
        self.lastTrackSubtitle = lastTrackSubtitle
    }
}

@MainActor
private enum NotchSourceIconCache {
    private static var cache: [String: NSImage] = [:]
    private static var missingKeys: Set<String> = []

    static func resolveApplicationURL(for source: NotchMediaSource, bundleID: String?) -> URL? {
        let workspace = NSWorkspace.shared
        if let bundleID, !bundleID.isEmpty,
           let url = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            return url
        }

        switch source {
        case .youtubeMusic:
            let ytmBundleIDs = [
                "com.google.Chrome.app.cinhimbnkkaeohfgghhklpknlkffjgod",
                "com.github.th-ch.youtube-music",
                "com.pear-devs.pear-desktop",
                "app.ytmdesktop.ytmdesktop"
            ]
            for bid in ytmBundleIDs {
                if let url = workspace.urlForApplication(withBundleIdentifier: bid) {
                    return url
                }
            }
            let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
            let candidatePaths = [
                "\(home)/Applications/Chrome Apps.localized/YouTube Music.app",
                "\(home)/Applications/YouTube Music.app",
                "/Applications/YouTube Music.app",
                "/Applications/Pear Desktop.app"
            ]
            for path in candidatePaths where FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
            return nil
        case .spotify:
            return workspace.urlForApplication(withBundleIdentifier: "com.spotify.client")
        case .appleMusic:
            return workspace.urlForApplication(withBundleIdentifier: "com.apple.Music")
        case .browser:
            for bid in ["com.google.Chrome", "com.apple.Safari", "com.brave.Browser", "company.thebrowser.Browser", "com.microsoft.edgemac"] {
                if let url = workspace.urlForApplication(withBundleIdentifier: bid) {
                    return url
                }
            }
            return nil
        case .other:
            return nil
        }
    }

    static func icon(for source: NotchMediaSource, bundleID: String?) -> NSImage? {
        let key = "\(source.rawValue)::\(bundleID ?? "")"
        if let cached = cache[key] {
            return cached
        }
        if missingKeys.contains(key) {
            return nil
        }

        guard let url = resolveApplicationURL(for: source, bundleID: bundleID) else {
            missingKeys.insert(key)
            return nil
        }

        let image = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        cache[key] = image
        return image
    }
}

// MARK: - Modelo Principal de Pista en Reproducción

/// Instantánea inmutable y `Sendable` de la canción en reproducción para el reproductor Notch.
public struct NotchTrackInfo: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval
    public var elapsedTime: TimeInterval
    public var isPlaying: Bool
    public var playbackRate: Double
    public var artworkData: Data?
    public var dominantColor: NotchRGBColor
    public var sourceApp: NotchMediaSource
    public var sourceBundleID: String?
    public var sourceAppName: String
    public var supportsSeeking: Bool
    public var supportsShuffleRepeat: Bool
    public var isShuffling: Bool
    public var repeatMode: NotchRepeatMode
    public var isLiked: Bool?
    public var lastUpdatedAt: Date

    public init(
        id: String,
        title: String,
        artist: String,
        album: String = "",
        duration: TimeInterval = 0,
        elapsedTime: TimeInterval = 0,
        isPlaying: Bool,
        playbackRate: Double = 1.0,
        artworkData: Data? = nil,
        dominantColor: NotchRGBColor? = nil,
        sourceApp: NotchMediaSource,
        sourceBundleID: String? = nil,
        sourceAppName: String? = nil,
        supportsSeeking: Bool = false,
        supportsShuffleRepeat: Bool = false,
        isShuffling: Bool = false,
        repeatMode: NotchRepeatMode = .off,
        isLiked: Bool? = nil,
        lastUpdatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = max(0, duration)
        self.elapsedTime = max(0, elapsedTime)
        self.isPlaying = isPlaying
        self.playbackRate = playbackRate
        self.artworkData = artworkData
        self.dominantColor = dominantColor ?? sourceApp.brandAccentColor
        self.sourceApp = sourceApp
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName ?? sourceApp.displayName
        self.supportsSeeking = supportsSeeking
        self.supportsShuffleRepeat = supportsShuffleRepeat
        self.isShuffling = isShuffling
        self.repeatMode = repeatMode
        self.isLiked = isLiked
        self.lastUpdatedAt = lastUpdatedAt
    }

    /// Decodifica la carátula en una `NSImage` cuando se necesita bajo demanda.
    /// Para renderizado frecuente en SwiftUI, preferir `NotchMediaService.shared.currentArtworkImage` (cacheada).
    public func makeArtworkImage() -> NSImage? {
        guard let artworkData, !artworkData.isEmpty else { return nil }
        return NSImage(data: artworkData)
    }

    /// Calcula el tiempo transcurrido interpolado suavemente en tiempo real usando `lastUpdatedAt` y `playbackRate`.
    public func interpolatedElapsedTime(at date: Date = Date()) -> TimeInterval {
        let base = max(0, elapsedTime)
        guard isPlaying, playbackRate > 0 else {
            return duration > 0 ? min(base, duration) : base
        }
        let delta = max(0, date.timeIntervalSince(lastUpdatedAt)) * playbackRate
        let raw = base + delta
        return duration > 0 ? min(raw, duration) : raw
    }

    /// Progreso normalizado (`0.0...1.0`) en el instante indicado.
    public func progress(at date: Date = Date()) -> Double {
        guard duration > 0.5 else { return 0 }
        return min(max(interpolatedElapsedTime(at: date) / duration, 0), 1)
    }

    /// Indica si la fuente informó una duración válida para mostrar barra de progreso / scrubber.
    public var hasKnownDuration: Bool {
        duration > 0.5
    }

    /// Clave normalizada para cachés de letras sincronizadas y carátulas.
    public var trackLookupKey: String {
        let normTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(normTitle)::\(normArtist)"
    }

    /// Subtítulo limpio para mostrar debajo del título (`Artista`, `Artista · Álbum`, `Álbum` o app fuente).
    public var displaySubtitle: String {
        displaySubtitle(includeAlbum: false)
    }

    public func displaySubtitle(includeAlbum: Bool) -> String {
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        if includeAlbum && !trimmedAlbum.isEmpty {
            let albumMatchesArtist = !trimmedArtist.isEmpty && trimmedAlbum.caseInsensitiveCompare(trimmedArtist) == .orderedSame
            let albumMatchesTitle = !trimmedTitle.isEmpty && trimmedAlbum.caseInsensitiveCompare(trimmedTitle) == .orderedSame
            if !trimmedArtist.isEmpty {
                return (albumMatchesArtist || albumMatchesTitle) ? trimmedArtist : "\(trimmedArtist) · \(trimmedAlbum)"
            }
            return trimmedAlbum
        }

        if !trimmedArtist.isEmpty {
            return trimmedArtist
        }
        if includeAlbum && !trimmedAlbum.isEmpty {
            return trimmedAlbum
        }
        return sourceAppName
    }

    /// Texto combinado `Título — Artista` ideal para anuncios y píldora compacta.
    public var formattedTitleAndArtist: String {
        artist.isEmpty ? title : "\(title) — \(artist)"
    }

    /// Formatea segundos en `m:ss` o `h:mm:ss`.
    public static func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, !seconds.isNaN, seconds >= 0 else {
            return "0:00"
        }
        let totalSeconds = Int(seconds.rounded(.down))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Enumeraciones de Preferencias del Notch

/// Estilo visual de la carátula en la píldora colapsada del Notch.
public enum NotchArtworkStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case circleWithRing
    case roundedSquare

    public var id: String { rawValue }

    public var symbolName: String {
        switch self {
        case .circleWithRing: return "record.circle"
        case .roundedSquare: return "square.fill"
        }
    }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .circleWithRing:
            return loc.text(es: "Circular con anillo de progreso", en: "Circle with Progress Ring")
        case .roundedSquare:
            return loc.text(es: "Cuadrada redondeada", en: "Rounded Square")
        }
    }

    @MainActor
    public func localizedShortTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .circleWithRing:
            return loc.text(es: "Circular con anillo", en: "Circle with Ring")
        case .roundedSquare:
            return loc.text(es: "Cuadrada redondeada", en: "Rounded Square")
        }
    }
}

/// Pantallas en las que se mostrará el reproductor Notch.
public enum NotchDisplayMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case notchDisplayOnly
    case primaryDisplay
    case allDisplays

    public var id: String { rawValue }

    public var symbolName: String {
        switch self {
        case .notchDisplayOnly: return "laptopcomputer"
        case .primaryDisplay: return "display"
        case .allDisplays: return "display.2"
        }
    }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .notchDisplayOnly:
            return loc.text(es: "Solo pantalla con Notch", en: "Notch Display Only")
        case .primaryDisplay:
            return loc.text(es: "Solo pantalla principal", en: "Primary Display Only")
        case .allDisplays:
            return loc.text(es: "Todas las pantallas", en: "All Displays")
        }
    }
}

/// Modo de activación para desplegar el panel expandido del Notch.
public enum NotchExpandTrigger: String, CaseIterable, Identifiable, Codable, Sendable {
    case hoverAndClick
    case clickOnly

    public var id: String { rawValue }

    public var symbolName: String {
        switch self {
        case .hoverAndClick: return "cursorarrow.motionlines"
        case .clickOnly: return "cursorarrow.click"
        }
    }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .hoverAndClick:
            return loc.text(es: "Al pasar el puntero o hacer clic", en: "Hover and Click")
        case .clickOnly:
            return loc.text(es: "Solo al hacer clic", en: "Click Only")
        }
    }
}

/// Escala visual de la píldora y el panel del Notch.
public enum NotchPillSize: String, CaseIterable, Identifiable, Codable, Sendable {
    case compact
    case normal
    case spacious

    public var id: String { rawValue }

    public var symbolName: String {
        switch self {
        case .compact: return "rectangle.compress.vertical"
        case .normal: return "rectangle"
        case .spacious: return "rectangle.expand.vertical"
        }
    }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .compact: return loc.text(es: "Compacto", en: "Compact")
        case .normal: return loc.text(es: "Normal", en: "Normal")
        case .spacious: return loc.text(es: "Amplio", en: "Spacious")
        }
    }

    /// Ancho extra por lado en la píldora colapsada (alas izquierda/derecha).
    public var collapsedWingWidth: CGFloat {
        switch self {
        case .compact: return 38
        case .normal: return 48
        case .spacious: return 58
        }
    }

    /// Tamaño de carátula en el estado colapsado.
    public var collapsedArtworkSize: CGFloat {
        switch self {
        case .compact: return 20
        case .normal: return 22
        case .spacious: return 25
        }
    }

    /// Dimensiones sugeridas para el panel expandido compacto (2 columnas sin letras).
    public var expandedCompactSize: CGSize {
        switch self {
        case .compact: return CGSize(width: 392, height: 184)
        case .normal: return CGSize(width: 426, height: 196)
        case .spacious: return CGSize(width: 462, height: 210)
        }
    }

    /// Dimensiones sugeridas para el panel expandido con letras sincronizadas (vista dividida).
    public var expandedLyricsSize: CGSize {
        switch self {
        case .compact: return CGSize(width: 560, height: 224)
        case .normal: return CGSize(width: 610, height: 242)
        case .spacious: return CGSize(width: 656, height: 262)
        }
    }
}

/// Modo de color de acento del reproductor Notch.
public enum NotchAccentColorMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case dynamicArtwork
    case sourceBrand
    case custom

    public var id: String { rawValue }

    public var symbolName: String {
        switch self {
        case .dynamicArtwork: return "sparkles"
        case .sourceBrand: return "music.note"
        case .custom: return "paintpalette.fill"
        }
    }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .dynamicArtwork: return loc.text(es: "Carátula (auto)", en: "Album Art (Auto)")
        case .sourceBrand: return loc.text(es: "Color de la app", en: "App Brand Color")
        case .custom: return loc.text(es: "Personalizado", en: "Custom Color")
        }
    }
}

/// Curva / personalidad de animación para expansión, contracción y transiciones del Notch.
public enum NotchAnimationStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case bouncySpring
    case smoothFluid
    case crispSnappy
    case gentleEase

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .bouncySpring: return loc.text(es: "Elástico", en: "Bouncy")
        case .smoothFluid: return loc.text(es: "Fluido", en: "Fluid")
        case .crispSnappy: return loc.text(es: "Preciso", en: "Snappy")
        case .gentleEase: return loc.text(es: "Suave", en: "Gentle")
        }
    }

    @MainActor
    public func localizedDescription(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .bouncySpring: return loc.text(es: "Rebote expresivo estilo Isla Dinámica.", en: "Playful Dynamic Island bounce.")
        case .smoothFluid: return loc.text(es: "Resorte equilibrado y natural (recomendado).", en: "Balanced natural spring (recommended).")
        case .crispSnappy: return loc.text(es: "Respuesta directa casi sin rebote.", en: "Tight direct response with minimal bounce.")
        case .gentleEase: return loc.text(es: "Deslizamiento progresivo clásico sin rebote.", en: "Classic smooth ease-in-out with zero bounce.")
        }
    }

    /// Construye la `Animation` SwiftUI aplicando el estilo y el multiplicador de velocidad (`0.5...2.0`).
    public func makeAnimation(baseResponse: Double = 0.36, speedMultiplier: Double = 1.0) -> Animation {
        let safeSpeed = min(max(speedMultiplier, 0.5), 2.0)
        let scaled = max(0.10, baseResponse / safeSpeed)
        switch self {
        case .bouncySpring:
            return .spring(response: scaled * 1.06, dampingFraction: 0.64, blendDuration: 0.08)
        case .smoothFluid:
            return .spring(response: scaled, dampingFraction: 0.79, blendDuration: 0.10)
        case .crispSnappy:
            return .spring(response: scaled * 0.80, dampingFraction: 0.93, blendDuration: 0.06)
        case .gentleEase:
            return .easeInOut(duration: scaled * 0.95)
        }
    }
}

/// Estilo visual del ecualizador animado en tiempo real del Notch.
public enum NotchVisualizerStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case classicBars
    case waveformMirror
    case bouncingDots
    case pulseRing

    public var id: String { rawValue }

    public var symbolName: String {
        switch self {
        case .classicBars: return "chart.bar.fill"
        case .waveformMirror: return "waveform"
        case .bouncingDots: return "ellipsis"
        case .pulseRing: return "circle.circle.fill"
        }
    }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .classicBars: return loc.text(es: "Barras", en: "Bars")
        case .waveformMirror: return loc.text(es: "Onda", en: "Wave")
        case .bouncingDots: return loc.text(es: "Puntos", en: "Dots")
        case .pulseRing: return loc.text(es: "Pulso", en: "Pulse")
        }
    }
}

/// Escala tipográfica del panel de letras sincronizadas tipo karaoke.
public enum NotchLyricsFontSize: String, CaseIterable, Identifiable, Codable, Sendable {
    case compact
    case normal
    case large

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .compact: return loc.text(es: "Compacto", en: "Compact")
        case .normal: return loc.text(es: "Normal", en: "Normal")
        case .large: return loc.text(es: "Grande", en: "Large")
        }
    }

    public var activeFontSize: CGFloat {
        switch self {
        case .compact: return 12.2
        case .normal: return 13.5
        case .large: return 15.2
        }
    }

    public var inactiveFontSize: CGFloat {
        switch self {
        case .compact: return 11.0
        case .normal: return 12.2
        case .large: return 13.4
        }
    }

    public var lineSpacing: CGFloat {
        switch self {
        case .compact: return 7
        case .normal: return 9
        case .large: return 11
        }
    }
}

// MARK: - Letras Sincronizadas

/// Una línea de letra sincronizada con marca de tiempo (formato LRC).
public struct NotchLyricLine: Identifiable, Equatable, Hashable, Codable, Sendable {
    public let id: String
    public let time: TimeInterval
    public let text: String

    public init(id: String, time: TimeInterval, text: String) {
        self.id = id
        self.time = time
        self.text = text
    }
}

/// Estado de carga y disponibilidad de letras para la canción actual.
public enum NotchLyricsState: Equatable, Sendable {
    case idle
    case loading
    case synced([NotchLyricLine])
    case plain([String])
    case instrumental
    case unavailable

    public var hasDisplayableContent: Bool {
        switch self {
        case .synced(let lines): return !lines.isEmpty
        case .plain(let lines): return !lines.isEmpty
        case .instrumental: return true
        case .idle, .loading, .unavailable: return false
        }
    }
}

// MARK: - Dispositivos de Salida de Audio (CoreAudio)

/// Dispositivo de salida de audio CoreAudio disponible para cambio rápido en 1 clic.
public struct NotchAudioOutputDevice: Identifiable, Equatable, Hashable, Sendable {
    public let id: AudioDeviceID
    public let uid: String
    public let name: String
    public let isDefault: Bool
    public let transportType: String
    public let systemImage: String

    public init(
        id: AudioDeviceID,
        uid: String,
        name: String,
        isDefault: Bool,
        transportType: String,
        systemImage: String
    ) {
        self.id = id
        self.uid = uid
        self.name = name
        self.isDefault = isDefault
        self.transportType = transportType
        self.systemImage = systemImage
    }
}

// MARK: - Estado de Conexión de Fuentes Multimedia

/// Diagnóstico liviano del estado de las fuentes de música para mostrar en Configuración de Notch.
public struct NotchMediaConnectionStatus: Equatable, Sendable {
    public var isYTMDesktopAPIReachable: Bool
    public var hasMediaRemoteData: Bool
    public var isSpotifyRunning: Bool
    public var isAppleMusicRunning: Bool
    public var isYouTubeMusicPWARunning: Bool
    public var isChromeRunning: Bool
    public var isSafariRunning: Bool
    public var activeBackendName: String

    public init(
        isYTMDesktopAPIReachable: Bool = false,
        hasMediaRemoteData: Bool = false,
        isSpotifyRunning: Bool = false,
        isAppleMusicRunning: Bool = false,
        isYouTubeMusicPWARunning: Bool = false,
        isChromeRunning: Bool = false,
        isSafariRunning: Bool = false,
        activeBackendName: String = ""
    ) {
        self.isYTMDesktopAPIReachable = isYTMDesktopAPIReachable
        self.hasMediaRemoteData = hasMediaRemoteData
        self.isSpotifyRunning = isSpotifyRunning
        self.isAppleMusicRunning = isAppleMusicRunning
        self.isYouTubeMusicPWARunning = isYouTubeMusicPWARunning
        self.isChromeRunning = isChromeRunning
        self.isSafariRunning = isSafariRunning
        self.activeBackendName = activeBackendName
    }
}
