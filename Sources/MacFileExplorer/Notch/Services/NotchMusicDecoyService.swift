import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

/// Modelo ligero de reproductor alternativo sugerido para abrir al presionar la tecla ▶ Play.
public struct NotchDecoyRedirectAppOption: Identifiable, Equatable, Sendable {
    public let name: String
    public let path: String

    public var id: String { path }

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

/// Controlador nativo integrado de **Music Decoy** dentro del módulo **Notch** de `MacFileExplorer`.
///
/// Inspirado en `FuzzyIdeas/MusicDecoy`:
/// - Ejecuta el helper oculto `Contents/Helpers/MacFileExplorerMusicDecoy.app` (con bundle ID `com.apple.Music`
///   y `LSBackgroundOnly = true`, 0% CPU, sin ícono en el Dock ni barra de menús).
/// - Como macOS (`rcd`) detecta un proceso con bundle ID `com.apple.Music` activo en segundo plano,
///   deja de abrir Apple Music automáticamente al presionar ▶ Play o conectar auriculares Bluetooth.
/// - Opcionalmente redirige la tecla ▶ Play a otro reproductor elegido por el usuario (YouTube Music, Spotify, etc.).
/// - Se detiene automáticamente al desactivar la opción o al cerrar `MacFileExplorer`.
@MainActor
@Observable
public final class NotchMusicDecoyService {

    public static let shared = NotchMusicDecoyService()

    public nonisolated static let helperBundleName = "MacFileExplorerMusicDecoy.app"
    public nonisolated static let helperExecutableName = "MacFileExplorerMusicDecoy"
    public nonisolated static let helperDisplayName = "MacFileExplorer Music Decoy"
    public nonisolated static let realAppleMusicPath = "/System/Applications/Music.app"
    public nonisolated static let webURLPrefix = "url:"
    public nonisolated static let youtubeMusicWebTarget = "url:https://music.youtube.com"
    public nonisolated static let systemAppleMusicSelectionTag = "__system_apple_music__"

    private static let sharedSuiteName = "com.macfileexplorer.musicdecoy"
    private static let sharedMediaAppPathKey = "mediaAppPath"
    private static let configChangedNotification = Notification.Name("com.macfileexplorer.musicdecoy.configChanged")
    private static let terminateNotification = Notification.Name("com.macfileexplorer.musicdecoy.terminate")

    public private(set) var isDecoyRunning: Bool = false
    public private(set) var isRealAppleMusicRunning: Bool = false
    public private(set) var lastErrorMessage: String?

    private var isInstalled = false
    private var launchObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?

    private init() {}

    // MARK: - Detección Precisa de Procesos (Decoy vs Apple Music Real)

    /// Devuelve `true` únicamente si `app` corresponde a nuestro helper Music Decoy embebido.
    public nonisolated static func isDecoyProcess(_ app: NSRunningApplication) -> Bool {
        if app.executableURL?.lastPathComponent == helperExecutableName {
            return true
        }
        if app.bundleURL?.lastPathComponent == helperBundleName {
            return true
        }
        if app.localizedName == helperDisplayName {
            return true
        }
        return false
    }

    /// Devuelve `true` únicamente si `app` es la aplicación real de Apple Music del sistema (excluyendo nuestro decoy).
    public nonisolated static func isRealAppleMusicProcess(_ app: NSRunningApplication) -> Bool {
        guard !app.isTerminated, app.bundleIdentifier == "com.apple.Music" else {
            return false
        }
        if isDecoyProcess(app) {
            return false
        }
        if let bundlePath = app.bundleURL?.path(percentEncoded: false),
           bundlePath.localizedCaseInsensitiveContains("Music Decoy") {
            return false
        }
        return true
    }

    // MARK: - Ciclo de Vida y Observadores

    public func installIfNeeded() {
        guard !isInstalled else { return }
        isInstalled = true

        refreshStatus()

        let wsCenter = NSWorkspace.shared.notificationCenter
        launchObserver = wsCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatus()
            }
        }
        terminateObserver = wsCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatus()
            }
        }
    }

    /// Actualiza en vivo si el decoy o el Apple Music real están ejecutándose.
    public func refreshStatus() {
        let running = NSWorkspace.shared.runningApplications
        isDecoyRunning = running.contains { !$0.isTerminated && Self.isDecoyProcess($0) }
        isRealAppleMusicRunning = running.contains { Self.isRealAppleMusicProcess($0) }
    }

    /// Sincroniza el estado del helper Music Decoy con `NotchPreferences.shared`.
    public func syncWithPreferences() {
        installIfNeeded()
        let prefs = NotchPreferences.shared
        writeSharedRedirectPath(prefs.musicDecoyRedirectAppPath)

        if prefs.blockAppleMusicAutoLaunch {
            startDecoyIfNeeded()
        } else {
            stop()
        }
    }

    /// Actualiza en vivo la aplicación alternativa a abrir al presionar ▶ Play sin reiniciar el helper.
    public func syncRedirectAppPreference(_ appPath: String) {
        writeSharedRedirectPath(appPath)
        DistributedNotificationCenter.default().postNotificationName(
            Self.configChangedNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    /// Detiene únicamente nuestro helper Music Decoy (nunca cierra el Apple Music real del usuario).
    public func stop() {
        DistributedNotificationCenter.default().postNotificationName(
            Self.terminateNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )

        for app in NSWorkspace.shared.runningApplications where !app.isTerminated && Self.isDecoyProcess(app) {
            if !app.terminate() {
                app.forceTerminate()
            }
        }

        lastErrorMessage = nil
        refreshStatus()

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            self?.refreshStatus()
        }
    }

    /// Cierra Apple Music si estaba abierto y activa el bloqueador inmediatamente.
    public func quitRealAppleMusicAndActivateDecoy() {
        for app in NSWorkspace.shared.runningApplications where Self.isRealAppleMusicProcess(app) {
            app.terminate()
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard let self else { return }
            self.refreshStatus()
            if NotchPreferences.shared.blockAppleMusicAutoLaunch {
                self.startDecoyIfNeeded()
            }
        }
    }

    /// Desactiva el bloqueador y abre Apple Music normalmente en 1 clic cuando el usuario sí quiere usarlo.
    public func openAppleMusicTemporarily() {
        NotchPreferences.shared.blockAppleMusicAutoLaunch = false
        stop()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            let url = URL(fileURLWithPath: Self.realAppleMusicPath)
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
        }
    }

    // MARK: - Reproductores Alternativos Instalados + Selector de App

    /// Detecta apps de música populares instaladas en el Mac para ofrecerlas en 1 clic como destino de la tecla ▶ Play.
    public func availableRedirectApps() -> [NotchDecoyRedirectAppOption] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let candidates: [(name: String, paths: [String])] = [
            (
                "YouTube Music",
                [
                    "\(home)/Applications/Chrome Apps.localized/YouTube Music.app",
                    "\(home)/Applications/YouTube Music.app",
                    "/Applications/YouTube Music.app",
                    "/Applications/Pear Desktop.app"
                ]
            ),
            ("Spotify", ["/Applications/Spotify.app", "\(home)/Applications/Spotify.app"]),
            ("VLC", ["/Applications/VLC.app"]),
            ("Tidal", ["/Applications/TIDAL.app"]),
            ("Plexamp", ["/Applications/Plexamp.app"]),
            ("Swinsian", ["/Applications/Swinsian.app"]),
            ("IINA", ["/Applications/IINA.app"])
        ]

        var results: [NotchDecoyRedirectAppOption] = []
        var seenPaths: Set<String> = []
        for candidate in candidates {
            if let existing = candidate.paths.first(where: { fm.fileExists(atPath: $0) }),
               seenPaths.insert(existing).inserted {
                results.append(NotchDecoyRedirectAppOption(name: candidate.name, path: existing))
            }
        }

        // Siempre incluir YouTube Music (Web) como opción lista para usar incluso sin app/PWA instalada.
        let loc = LocalizationManager.shared
        let webOptionName = loc.text(es: "YouTube Music (Web)", en: "YouTube Music (Web)")
        if seenPaths.insert(Self.youtubeMusicWebTarget).inserted {
            results.append(NotchDecoyRedirectAppOption(name: webOptionName, path: Self.youtubeMusicWebTarget))
        }

        // Si el usuario eligió una app personalizada que no está en la lista sugerida, incluirla también.
        let customPath = NotchPreferences.shared.musicDecoyRedirectAppPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !customPath.isEmpty,
           !customPath.hasPrefix(Self.webURLPrefix),
           fm.fileExists(atPath: customPath),
           !seenPaths.contains(customPath) {
            let displayName = URL(fileURLWithPath: customPath).deletingPathExtension().lastPathComponent
            results.append(NotchDecoyRedirectAppOption(name: displayName, path: customPath))
        }

        return results
    }

    /// Aplica una selección unificada de «Reproductor al presionar ▶ Play» (activa automáticamente el bloqueador si no es Apple Music).
    public func applyPlayKeyTargetSelection(_ tag: String) {
        let prefs = NotchPreferences.shared
        if tag == Self.systemAppleMusicSelectionTag {
            prefs.musicDecoyRedirectAppPath = ""
            prefs.blockAppleMusicAutoLaunch = false
            return
        }
        prefs.musicDecoyRedirectAppPath = tag
        if !prefs.blockAppleMusicAutoLaunch {
            prefs.blockAppleMusicAutoLaunch = true
        } else {
            syncRedirectAppPreference(tag)
        }
    }

    /// Devuelve el tag actualmente activo para el selector unificado de «Reproductor al presionar ▶ Play».
    public var currentPlayKeySelectionTag: String {
        let prefs = NotchPreferences.shared
        guard prefs.blockAppleMusicAutoLaunch else {
            return Self.systemAppleMusicSelectionTag
        }
        return prefs.musicDecoyRedirectAppPath
    }

    /// Prueba manualmente la apertura del reproductor configurado para la tecla ▶ Play.
    public func testConfiguredRedirectApp() {
        let target = NotchPreferences.shared.musicDecoyRedirectAppPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        if target.hasPrefix(Self.webURLPrefix) {
            let rawURL = String(target.dropFirst(Self.webURLPrefix.count))
            if let url = URL(string: rawURL) {
                NSWorkspace.shared.open(url)
            }
        } else if FileManager.default.fileExists(atPath: target) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: target), configuration: config, completionHandler: nil)
        }
    }

    /// Abre un diálogo nativo para elegir cualquier aplicación `.app` que abrir al presionar ▶ Play.
    public func chooseCustomRedirectApp() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        let loc = LocalizationManager.shared
        panel.prompt = loc.text(es: "Elegir", en: "Choose")
        panel.message = loc.text(
            es: "Elegí qué reproductor querés abrir al presionar la tecla ▶ Play.",
            en: "Choose which music app to open when pressing the ▶ Play key."
        )

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return nil
        }

        let selectedPath = selectedURL.path(percentEncoded: false)
        // Evitar elegir Apple Music real o nuestro propio helper como destino.
        if selectedPath == Self.realAppleMusicPath || selectedPath.hasSuffix(Self.helperBundleName) {
            return nil
        }
        return selectedPath
    }

    // MARK: - Lanzamiento del Helper Embebido

    private func startDecoyIfNeeded() {
        refreshStatus()
        if isDecoyRunning {
            syncRedirectAppPreference(NotchPreferences.shared.musicDecoyRedirectAppPath)
            lastErrorMessage = nil
            return
        }

        guard let helperURL = resolveHelperAppURL() else {
            lastErrorMessage = LocalizationManager.shared.text(
                es: "Helper Music Decoy no encontrado dentro del paquete MacFileExplorer.app.",
                en: "Music Decoy helper was not found inside the MacFileExplorer.app bundle."
            )
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true
        config.addsToRecentItems = false
        config.createsNewApplicationInstance = true

        NSWorkspace.shared.openApplication(at: helperURL, configuration: config) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.lastErrorMessage = error.localizedDescription
                } else {
                    self.lastErrorMessage = nil
                }
                self.refreshStatus()
            }
        }
    }

    private func resolveHelperAppURL() -> URL? {
        let fm = FileManager.default
        let bundleURL = Bundle.main.bundleURL

        let embedded = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent(Self.helperBundleName, isDirectory: true)
        if fm.fileExists(atPath: embedded.path(percentEncoded: false)) {
            return embedded
        }

        // Fallback para ejecución en desarrollo desde el repositorio
        let cwdFallback = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("MacFileExplorer.app/Contents/Helpers/\(Self.helperBundleName)", isDirectory: true)
        if fm.fileExists(atPath: cwdFallback.path(percentEncoded: false)) {
            return cwdFallback
        }

        return nil
    }

    private func writeSharedRedirectPath(_ rawPath: String) {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let suite = UserDefaults(suiteName: Self.sharedSuiteName)
        if trimmed.isEmpty {
            suite?.removeObject(forKey: Self.sharedMediaAppPathKey)
        } else {
            suite?.set(trimmed, forKey: Self.sharedMediaAppPathKey)
        }
    }
}
