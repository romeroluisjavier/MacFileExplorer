import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import CoreServices
import Darwin
import Foundation
import ImageIO
import Observation

// MARK: - Puente Dinámico Seguro para MediaRemote.framework

private final class NotchMediaRemoteBridge: @unchecked Sendable {

    static let shared = NotchMediaRemoteBridge()

    struct Snapshot: Sendable {
        let title: String
        let artist: String
        let album: String
        let duration: TimeInterval
        let elapsedTime: TimeInterval
        let isPlaying: Bool
        let playbackRate: Double
        let artworkData: Data?
        let bundleID: String?
        let appName: String?
        let lastUpdatedAt: Date
    }

    enum Command: UInt32, Sendable {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    private typealias GetNowPlayingInfoFn = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
    private typealias GetIsPlayingFn = @convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void
    private typealias GetClientFn = @convention(c) (DispatchQueue, @escaping @convention(block) (AnyObject?) -> Void) -> Void
    private typealias GetPIDFn = @convention(c) (DispatchQueue, @escaping @convention(block) (Int32) -> Void) -> Void
    private typealias ClientGetStringFn = @convention(c) (AnyObject) -> CFString?
    private typealias SendCommandFn = @convention(c) (UInt32, CFDictionary?) -> Bool
    private typealias SetElapsedTimeFn = @convention(c) (Double) -> Void

    private let handle: UnsafeMutableRawPointer?
    private let getInfoFn: GetNowPlayingInfoFn?
    private let getIsPlayingFn: GetIsPlayingFn?
    private let getClientFn: GetClientFn?
    private let getPIDFn: GetPIDFn?
    private let clientBundleIDFn: ClientGetStringFn?
    private let clientDisplayNameFn: ClientGetStringFn?
    private let sendCommandFn: SendCommandFn?
    private let setElapsedTimeFn: SetElapsedTimeFn?
    private let callbackQueue = DispatchQueue(label: "com.macfileexplorer.notch.mediaremote", qos: .utility)

    var isAvailable: Bool {
        getInfoFn != nil
    }

    private init() {
        let h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
        self.handle = h
        guard let h else {
            self.getInfoFn = nil
            self.getIsPlayingFn = nil
            self.getClientFn = nil
            self.getPIDFn = nil
            self.clientBundleIDFn = nil
            self.clientDisplayNameFn = nil
            self.sendCommandFn = nil
            self.setElapsedTimeFn = nil
            return
        }

        self.getInfoFn = dlsym(h, "MRMediaRemoteGetNowPlayingInfo").map { unsafeBitCast($0, to: GetNowPlayingInfoFn.self) }
        self.getIsPlayingFn = dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying").map { unsafeBitCast($0, to: GetIsPlayingFn.self) }
        self.getClientFn = dlsym(h, "MRMediaRemoteGetNowPlayingClient").map { unsafeBitCast($0, to: GetClientFn.self) }
        self.getPIDFn = dlsym(h, "MRMediaRemoteGetNowPlayingApplicationPID").map { unsafeBitCast($0, to: GetPIDFn.self) }
        self.clientBundleIDFn = dlsym(h, "MRNowPlayingClientGetBundleIdentifier").map { unsafeBitCast($0, to: ClientGetStringFn.self) }
        self.clientDisplayNameFn = dlsym(h, "MRNowPlayingClientGetDisplayName").map { unsafeBitCast($0, to: ClientGetStringFn.self) }
        self.sendCommandFn = dlsym(h, "MRMediaRemoteSendCommand").map { unsafeBitCast($0, to: SendCommandFn.self) }
        self.setElapsedTimeFn = dlsym(h, "MRMediaRemoteSetElapsedTime").map { unsafeBitCast($0, to: SetElapsedTimeFn.self) }
    }

    func fetchSnapshot() async -> Snapshot? {
        guard let getInfoFn else { return nil }

        async let infoResult: RawInfo? = withCheckedContinuation { continuation in
            getInfoFn(callbackQueue) { dict in
                guard let nsDict = dict as? [String: Any], !nsDict.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                let title = (nsDict["kMRMediaRemoteNowPlayingInfoTitle"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !title.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                let artist = (nsDict["kMRMediaRemoteNowPlayingInfoArtist"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let album = (nsDict["kMRMediaRemoteNowPlayingInfoAlbum"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let duration = (nsDict["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?.doubleValue ?? 0
                let elapsed = (nsDict["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)?.doubleValue ?? 0
                let rate = (nsDict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue ?? 0
                let timestamp = (nsDict["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date) ?? Date()
                let artworkData = nsDict["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data

                continuation.resume(returning: RawInfo(
                    title: title,
                    artist: artist,
                    album: album,
                    duration: duration,
                    elapsedTime: elapsed,
                    playbackRate: rate,
                    timestamp: timestamp,
                    artworkData: artworkData
                ))
            }
        }

        guard let info = await infoResult else { return nil }

        let playing: Bool
        if let getIsPlayingFn {
            playing = await withCheckedContinuation { continuation in
                getIsPlayingFn(callbackQueue) { isPlaying in
                    continuation.resume(returning: isPlaying)
                }
            }
        } else {
            playing = info.playbackRate > 0.01
        }

        let clientMeta = await fetchClientMetadata()

        return Snapshot(
            title: info.title,
            artist: info.artist,
            album: info.album,
            duration: info.duration,
            elapsedTime: info.elapsedTime,
            isPlaying: playing,
            playbackRate: playing ? max(info.playbackRate, 1.0) : 0.0,
            artworkData: info.artworkData,
            bundleID: clientMeta.bundleID,
            appName: clientMeta.displayName,
            lastUpdatedAt: info.timestamp
        )
    }

    @discardableResult
    func sendCommand(_ command: Command) -> Bool {
        guard let sendCommandFn else { return false }
        return sendCommandFn(command.rawValue, nil)
    }

    func setElapsedTime(_ seconds: TimeInterval) -> Bool {
        let clamped = max(0, seconds)
        if let setElapsedTimeFn {
            setElapsedTimeFn(clamped)
            return true
        }
        if let sendCommandFn {
            let options: NSDictionary = [
                "kMRMediaRemoteOptionPlaybackPosition": NSNumber(value: clamped)
            ]
            return sendCommandFn(24, options)
        }
        return false
    }

    private struct RawInfo: Sendable {
        let title: String
        let artist: String
        let album: String
        let duration: TimeInterval
        let elapsedTime: TimeInterval
        let playbackRate: Double
        let timestamp: Date
        let artworkData: Data?
    }

    private func fetchClientMetadata() async -> (bundleID: String?, displayName: String?) {
        if let getClientFn, let bundleFn = clientBundleIDFn {
            let result: (String?, String?) = await withCheckedContinuation { continuation in
                let displayFn = self.clientDisplayNameFn
                getClientFn(callbackQueue) { client in
                    guard let client else {
                        continuation.resume(returning: (nil, nil))
                        return
                    }
                    let bid = bundleFn(client) as String?
                    let name = displayFn?(client) as String?
                    continuation.resume(returning: (bid, name))
                }
            }
            if result.0 != nil || result.1 != nil {
                return result
            }
        }

        if let getPIDFn {
            let pid: Int32 = await withCheckedContinuation { continuation in
                getPIDFn(callbackQueue) { value in
                    continuation.resume(returning: value)
                }
            }
            if pid > 0 {
                return await MainActor.run {
                    if let app = NSRunningApplication(processIdentifier: pid) {
                        return (app.bundleIdentifier, app.localizedName)
                    }
                    return (nil, nil)
                }
            }
        }

        return (nil, nil)
    }
}

// MARK: - Motor Principal de Detección y Control Multimedia para Notch

/// Servicio reactivo (`@MainActor @Observable`) encargado de detectar qué se está reproduciendo
/// (YouTube Music Desktop API, MediaRemote, Spotify, Apple Music, YouTube Music en Chrome PWA / navegadores)
/// y controlar la reproducción sin bloquear jamás el hilo principal ni abrir aplicaciones cerradas.
@MainActor
@Observable
public final class NotchMediaService {

    public static let shared = NotchMediaService()

    // MARK: - Estado Observable Público

    public private(set) var currentTrack: NotchTrackInfo?
    public private(set) var currentArtworkImage: NSImage?
    public private(set) var isDemoMode: Bool = false
    public private(set) var isMonitoring: Bool = false
    public private(set) var pausedSince: Date?
    public private(set) var lastTrackChangeAt: Date?
    public private(set) var connectionStatus = NotchMediaConnectionStatus()

    /// Callback disparado cuando cambia el `id` de la canción (ideal para el anuncio de nueva canción en `NotchManager`).
    public var onTrackChanged: ((NotchTrackInfo?) -> Void)?

    public var hasActiveTrack: Bool {
        currentTrack != nil
    }

    public var isPlaying: Bool {
        currentTrack?.isPlaying ?? false
    }

    // MARK: - Interpolación en Vivo del Progreso

    /// Devuelve el tiempo transcurrido interpolado suavemente para `TimelineView` / scrubber / letras.
    public func liveElapsedTime(at date: Date = Date()) -> TimeInterval {
        currentTrack?.interpolatedElapsedTime(at: date) ?? 0
    }

    /// Devuelve el progreso normalizado (`0.0...1.0`) interpolado suavemente en tiempo real.
    public func liveProgress(at date: Date = Date()) -> Double {
        currentTrack?.progress(at: date) ?? 0
    }

    // MARK: - Tipos Internos y Estado Privado

    private enum ActiveBackend: String, Sendable {
        case none
        case demo
        case ytmDesktopAPI
        case mediaRemote
        case spotifyAppleScript
        case appleMusicAppleScript
        case browserWindowFallback
    }

    private struct RunningAppInfo: Sendable {
        let pid: pid_t
        let bundleID: String
        let localizedName: String
    }

    private struct EnrichedMetadata: Sendable {
        let artist: String?
        let album: String?
        let duration: TimeInterval?
        let artworkData: Data?
        let dominantColor: NotchRGBColor?
    }

    private struct PollOutcome: Sendable {
        let track: NotchTrackInfo?
        let backend: ActiveBackend
        let status: NotchMediaConnectionStatus
        let newlyDeniedAutomationBundleIDs: [String]
        let detectedVideoID: String?
        let resolvedVideoIDByTrackKey: [String: String]
    }

    private var activeBackend: ActiveBackend = .none
    private var pollingTask: Task<Void, Never>?
    private var demoAutoAdvanceTask: Task<Void, Never>?
    private var metadataEnrichmentTask: Task<Void, Never>?
    private var demoTrackIndex: Int = 0
    private var lastArtworkDataHash: Int?
    private var lastYTMProbeFailedAt: Date?
    private var lastOptimisticToggleAt: Date?
    private var lastOptimisticSeekAt: Date?
    private var browserUserForcedPause: Bool?
    private var browserAudioSilenceSince: Date?
    private var deniedAutomationBundleIDs: Set<String> = []

    // Cachés en memoria para evitar tráfico de red repetitivo
    private var artworkURLCache: [String: Data] = [:]
    private var trackVideoIDCache: [String: String] = [:]
    private var attemptedYouTubeArtworkVideoIDs: Set<String> = []
    private var lastTrackIDAndVideoID: (trackID: String, videoID: String)?
    private var iTunesEnrichmentCache: [String: EnrichedMetadata] = [:]
    private var dominantColorCache: [String: NotchRGBColor] = [:]
    private var demoArtworkCache: [String: Data] = [:]

    private nonisolated static let localAPISession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 0.45
        config.timeoutIntervalForResource = 0.85
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private nonisolated static let remoteAssetSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6.0
        config.timeoutIntervalForResource = 10.0
        return URLSession(configuration: config)
    }()

    private nonisolated static let ytmPWABundleID = "com.google.Chrome.app.cinhimbnkkaeohfgghhklpknlkffjgod"
    private nonisolated static let ytmDesktopBundleIDs: Set<String> = [
        "com.github.th-ch.youtube-music",
        "com.pear-devs.pear-desktop",
        "app.ytmdesktop.ytmdesktop"
    ]
    private nonisolated static let browserBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.apple.Safari",
        "com.brave.Browser",
        "company.thebrowser.Browser",
        "com.microsoft.edgemac"
    ]

    private init() {}

    // MARK: - Ciclo de Vida de Monitoreo

    /// Inicia el monitoreo periódico en segundo plano y la escucha de dispositivos CoreAudio.
    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        NotchLyricsAndAudioService.shared.startAudioDeviceMonitoring()
        restartPollingLoop()
    }

    /// Detiene el monitoreo periódico y limpia tareas pendientes (sin cerrar aplicaciones del usuario).
    public func stopMonitoring() {
        isMonitoring = false
        pollingTask?.cancel()
        pollingTask = nil
        metadataEnrichmentTask?.cancel()
        metadataEnrichmentTask = nil
        NotchLyricsAndAudioService.shared.stopAudioDeviceMonitoring()
    }

    /// Fuerza un refresco inmediato de la pista actual fuera de ciclo.
    public func refreshNow() {
        guard !isDemoMode else { return }
        lastYTMProbeFailedAt = nil
        Task { [weak self] in
            await self?.runSinglePollCycle()
        }
    }

    // MARK: - Modo Demo / Vista Previa Interactiva

    /// Activa el modo de vista previa interactiva con 3 canciones demo, carátulas vibrantes y letras sincronizadas.
    public func startDemoPreview() {
        isDemoMode = true
        activeBackend = .demo
        demoTrackIndex = 0
        applyDemoTrack(at: demoTrackIndex, isPlaying: true, resetToShowcasePosition: true)
        startDemoAutoAdvanceLoop()
    }

    /// Sale del modo de vista previa y retoma la detección real de música si el monitoreo está activo.
    public func stopDemoPreview() {
        guard isDemoMode else { return }
        isDemoMode = false
        demoAutoAdvanceTask?.cancel()
        demoAutoAdvanceTask = nil
        activeBackend = .none
        applyResolvedTrack(nil, backend: .none)
        if isMonitoring {
            refreshNow()
        }
    }

    /// Alterna el modo de vista previa interactiva.
    public func toggleDemoPreview() {
        if isDemoMode {
            stopDemoPreview()
        } else {
            startDemoPreview()
        }
    }

    // MARK: - Controles de Transporte Multimedia

    public func togglePlayPause() {
        if isDemoMode {
            guard var track = currentTrack else { return }
            let now = Date()
            track.elapsedTime = track.interpolatedElapsedTime(at: now)
            track.isPlaying.toggle()
            track.playbackRate = track.isPlaying ? 1.0 : 0.0
            track.lastUpdatedAt = now
            applyResolvedTrack(track, backend: .demo, forceUpdate: true)
            return
        }

        let targetPlaying = !(currentTrack?.isPlaying ?? false)
        optimisticallyUpdatePlaybackState(isPlaying: targetPlaying)

        let backend = activeBackend
        let port = NotchPreferences.shared.youtubeMusicAPIPort

        switch backend {
        case .ytmDesktopAPI:
            Task.detached(priority: .userInitiated) {
                let ok = await Self.postYTMCommand(port: port, paths: ["/api/v1/toggle-play", "/api/v1/play-pause"])
                if !ok {
                    await MainActor.run { Self.sendMediaKey(.playPause) }
                }
                await self.schedulePostActionRefresh()
            }
        case .spotifyAppleScript:
            guard isApplicationRunning(bundleID: "com.spotify.client") else { return }
            Task.detached(priority: .userInitiated) {
                _ = await Self.runAppleScript("""
                if application id "com.spotify.client" is running then
                    tell application id "com.spotify.client" to playpause
                end if
                """)
                await self.schedulePostActionRefresh()
            }
        case .appleMusicAppleScript:
            guard isApplicationRunning(bundleID: "com.apple.Music") else { return }
            Task.detached(priority: .userInitiated) {
                _ = await Self.runAppleScript("""
                if application id "com.apple.Music" is running then
                    tell application id "com.apple.Music" to playpause
                end if
                """)
                await self.schedulePostActionRefresh()
            }
        case .mediaRemote, .browserWindowFallback, .none:
            browserUserForcedPause = !targetPlaying
            if !NotchMediaRemoteBridge.shared.sendCommand(.togglePlayPause) {
                Self.sendMediaKey(.playPause)
            }
            Task { [weak self] in
                await self?.schedulePostActionRefresh()
            }
        case .demo:
            break
        }
    }

    public func play() {
        guard currentTrack?.isPlaying != true else { return }
        togglePlayPause()
    }

    public func pause() {
        guard currentTrack?.isPlaying == true else { return }
        togglePlayPause()
    }

    public func nextTrack() {
        if isDemoMode {
            demoTrackIndex = (demoTrackIndex + 1) % Self.demoCatalog.count
            applyDemoTrack(at: demoTrackIndex, isPlaying: true, resetToShowcasePosition: true)
            return
        }

        let backend = activeBackend
        let port = NotchPreferences.shared.youtubeMusicAPIPort
        browserUserForcedPause = nil

        switch backend {
        case .ytmDesktopAPI:
            Task.detached(priority: .userInitiated) {
                let ok = await Self.postYTMCommand(port: port, paths: ["/api/v1/next"])
                if !ok {
                    await MainActor.run { Self.sendMediaKey(.next) }
                }
                await self.schedulePostActionRefresh(delayMs: 320)
            }
        case .spotifyAppleScript:
            guard isApplicationRunning(bundleID: "com.spotify.client") else { return }
            Task.detached(priority: .userInitiated) {
                _ = await Self.runAppleScript("""
                if application id "com.spotify.client" is running then
                    tell application id "com.spotify.client" to next track
                end if
                """)
                await self.schedulePostActionRefresh(delayMs: 320)
            }
        case .appleMusicAppleScript:
            guard isApplicationRunning(bundleID: "com.apple.Music") else { return }
            Task.detached(priority: .userInitiated) {
                _ = await Self.runAppleScript("""
                if application id "com.apple.Music" is running then
                    tell application id "com.apple.Music" to next track
                end if
                """)
                await self.schedulePostActionRefresh(delayMs: 320)
            }
        case .mediaRemote, .browserWindowFallback, .none:
            if !NotchMediaRemoteBridge.shared.sendCommand(.nextTrack) {
                Self.sendMediaKey(.next)
            }
            Task { [weak self] in
                await self?.schedulePostActionRefresh(delayMs: 380)
            }
        case .demo:
            break
        }
    }

    public func previousTrack() {
        if isDemoMode {
            demoTrackIndex = (demoTrackIndex - 1 + Self.demoCatalog.count) % Self.demoCatalog.count
            applyDemoTrack(at: demoTrackIndex, isPlaying: true, resetToShowcasePosition: true)
            return
        }

        let backend = activeBackend
        let port = NotchPreferences.shared.youtubeMusicAPIPort
        browserUserForcedPause = nil

        switch backend {
        case .ytmDesktopAPI:
            Task.detached(priority: .userInitiated) {
                let ok = await Self.postYTMCommand(port: port, paths: ["/api/v1/previous"])
                if !ok {
                    await MainActor.run { Self.sendMediaKey(.previous) }
                }
                await self.schedulePostActionRefresh(delayMs: 320)
            }
        case .spotifyAppleScript:
            guard isApplicationRunning(bundleID: "com.spotify.client") else { return }
            Task.detached(priority: .userInitiated) {
                _ = await Self.runAppleScript("""
                if application id "com.spotify.client" is running then
                    tell application id "com.spotify.client" to previous track
                end if
                """)
                await self.schedulePostActionRefresh(delayMs: 320)
            }
        case .appleMusicAppleScript:
            guard isApplicationRunning(bundleID: "com.apple.Music") else { return }
            Task.detached(priority: .userInitiated) {
                _ = await Self.runAppleScript("""
                if application id "com.apple.Music" is running then
                    tell application id "com.apple.Music" to previous track
                end if
                """)
                await self.schedulePostActionRefresh(delayMs: 320)
            }
        case .mediaRemote, .browserWindowFallback, .none:
            if !NotchMediaRemoteBridge.shared.sendCommand(.previousTrack) {
                Self.sendMediaKey(.previous)
            }
            Task { [weak self] in
                await self?.schedulePostActionRefresh(delayMs: 380)
            }
        case .demo:
            break
        }
    }

    public func seek(to seconds: TimeInterval) {
        guard var track = currentTrack else { return }
        let clamped = track.duration > 0 ? min(max(0, seconds), track.duration) : max(0, seconds)

        track.elapsedTime = clamped
        track.lastUpdatedAt = Date()
        lastOptimisticSeekAt = Date()
        currentTrack = track

        if isDemoMode { return }

        let backend = activeBackend
        let port = NotchPreferences.shared.youtubeMusicAPIPort

        switch backend {
        case .ytmDesktopAPI:
            let payload: [String: Any] = ["seconds": Int(clamped.rounded())]
            let body = try? JSONSerialization.data(withJSONObject: payload)
            Task.detached(priority: .userInitiated) {
                _ = await Self.postYTMCommand(port: port, paths: ["/api/v1/seek-to"], body: body)
                await self.schedulePostActionRefresh(delayMs: 280)
            }
        case .spotifyAppleScript:
            guard isApplicationRunning(bundleID: "com.spotify.client") else { return }
            let pos = String(format: "%.2f", clamped)
            Task.detached(priority: .userInitiated) {
                _ = await Self.runAppleScript("""
                if application id "com.spotify.client" is running then
                    tell application id "com.spotify.client" to set player position to \(pos)
                end if
                """)
                await self.schedulePostActionRefresh(delayMs: 280)
            }
        case .appleMusicAppleScript:
            guard isApplicationRunning(bundleID: "com.apple.Music") else { return }
            let pos = String(format: "%.2f", clamped)
            Task.detached(priority: .userInitiated) {
                _ = await Self.runAppleScript("""
                if application id "com.apple.Music" is running then
                    tell application id "com.apple.Music" to set player position to \(pos)
                end if
                """)
                await self.schedulePostActionRefresh(delayMs: 280)
            }
        case .mediaRemote, .browserWindowFallback:
            _ = NotchMediaRemoteBridge.shared.setElapsedTime(clamped)
            Task { [weak self] in
                await self?.schedulePostActionRefresh(delayMs: 320)
            }
        case .none, .demo:
            break
        }
    }

    public func toggleShuffle() {
        guard var track = currentTrack else { return }
        track.isShuffling.toggle()
        currentTrack = track

        if isDemoMode { return }

        let backend = activeBackend
        let port = NotchPreferences.shared.youtubeMusicAPIPort
        let nextShuffle = track.isShuffling

        switch backend {
        case .ytmDesktopAPI:
            Task.detached(priority: .userInitiated) {
                _ = await Self.postYTMCommand(port: port, paths: ["/api/v1/shuffle"])
                await self.schedulePostActionRefresh(delayMs: 300)
            }
        case .spotifyAppleScript:
            guard isApplicationRunning(bundleID: "com.spotify.client") else { return }
            let flag = nextShuffle ? "true" : "false"
            Task.detached(priority: .userInitiated) {
                _ = await Self.runAppleScript("""
                if application id "com.spotify.client" is running then
                    tell application id "com.spotify.client" to set shuffling to \(flag)
                end if
                """)
                await self.schedulePostActionRefresh(delayMs: 300)
            }
        case .appleMusicAppleScript:
            guard isApplicationRunning(bundleID: "com.apple.Music") else { return }
            let flag = nextShuffle ? "true" : "false"
            Task.detached(priority: .userInitiated) {
                _ = await Self.runAppleScript("""
                if application id "com.apple.Music" is running then
                    tell application id "com.apple.Music" to set shuffle enabled to \(flag)
                end if
                """)
                await self.schedulePostActionRefresh(delayMs: 300)
            }
        case .mediaRemote, .browserWindowFallback, .none, .demo:
            break
        }
    }

    public func cycleRepeatMode() {
        guard var track = currentTrack else { return }
        let nextMode: NotchRepeatMode
        switch track.repeatMode {
        case .off: nextMode = .all
        case .all: nextMode = .one
        case .one: nextMode = .off
        }
        track.repeatMode = nextMode
        currentTrack = track

        if isDemoMode { return }

        let backend = activeBackend
        let port = NotchPreferences.shared.youtubeMusicAPIPort

        switch backend {
        case .ytmDesktopAPI:
            let body = try? JSONSerialization.data(withJSONObject: ["iteration": 1])
            Task.detached(priority: .userInitiated) {
                _ = await Self.postYTMCommand(port: port, paths: ["/api/v1/switch-repeat", "/api/v1/repeat"], body: body)
                await self.schedulePostActionRefresh(delayMs: 300)
            }
        case .spotifyAppleScript:
            guard isApplicationRunning(bundleID: "com.spotify.client") else { return }
            let repeatingFlag = nextMode != .off ? "true" : "false"
            Task.detached(priority: .userInitiated) {
                _ = await Self.runAppleScript("""
                if application id "com.spotify.client" is running then
                    tell application id "com.spotify.client" to set repeating to \(repeatingFlag)
                end if
                """)
                await self.schedulePostActionRefresh(delayMs: 300)
            }
        case .appleMusicAppleScript:
            guard isApplicationRunning(bundleID: "com.apple.Music") else { return }
            let appleMode: String
            switch nextMode {
            case .off: appleMode = "off"
            case .all: appleMode = "all"
            case .one: appleMode = "one"
            }
            Task.detached(priority: .userInitiated) {
                _ = await Self.runAppleScript("""
                if application id "com.apple.Music" is running then
                    tell application id "com.apple.Music" to set song repeat to \(appleMode)
                end if
                """)
                await self.schedulePostActionRefresh(delayMs: 300)
            }
        case .mediaRemote, .browserWindowFallback, .none, .demo:
            break
        }
    }

    public func toggleLike() {
        guard var track = currentTrack else { return }
        let nextLiked = !(track.isLiked ?? false)
        track.isLiked = nextLiked
        currentTrack = track

        if isDemoMode { return }

        let backend = activeBackend
        let port = NotchPreferences.shared.youtubeMusicAPIPort

        switch backend {
        case .ytmDesktopAPI:
            Task.detached(priority: .userInitiated) {
                _ = await Self.postYTMCommand(port: port, paths: ["/api/v1/like"])
                await self.schedulePostActionRefresh(delayMs: 320)
            }
        case .appleMusicAppleScript:
            guard isApplicationRunning(bundleID: "com.apple.Music") else { return }
            let flag = nextLiked ? "true" : "false"
            Task.detached(priority: .userInitiated) {
                _ = await Self.runAppleScript("""
                if application id "com.apple.Music" is running then
                    tell application id "com.apple.Music"
                        try
                            set favorited of current track to \(flag)
                        end try
                    end tell
                end if
                """)
            }
        case .spotifyAppleScript, .mediaRemote, .browserWindowFallback, .none, .demo:
            break
        }
    }

    private func isApplicationRunning(bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleID && !$0.isTerminated
        }
    }

    /// Trae al frente la aplicación de música que está reproduciendo actualmente (o reabre la última usada si no suena nada).
    public func openSourceApp() {
        guard let track = currentTrack else {
            if let primary = quickLaunchApps().first {
                launchQuickApp(primary)
            }
            return
        }
        if isDemoMode { return }

        if let bundleID = track.sourceBundleID,
           let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID && !$0.isTerminated }) {
            running.activate(options: [])
            return
        }

        let candidates: [String]
        switch track.sourceApp {
        case .youtubeMusic:
            candidates = [
                Self.ytmPWABundleID,
                "com.github.th-ch.youtube-music",
                "com.pear-devs.pear-desktop",
                "com.google.Chrome"
            ]
        case .spotify:
            candidates = ["com.spotify.client"]
        case .appleMusic:
            candidates = ["com.apple.Music"]
        case .browser:
            candidates = ["com.google.Chrome", "com.apple.Safari", "com.brave.Browser", "company.thebrowser.Browser"]
        case .other:
            candidates = []
        }

        for bid in candidates {
            if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bid && !$0.isTerminated }) {
                running.activate(options: [])
                return
            }
        }
    }

    /// Devuelve hasta 3 apps musicales listas para reabrir cuando no hay nada reproduciéndose,
    /// priorizando siempre el último reproductor utilizado (ej. YouTube Music).
    public func quickLaunchApps() -> [NotchQuickLaunchApp] {
        let prefs = NotchPreferences.shared
        var items: [NotchQuickLaunchApp] = []
        var addedSources: Set<NotchMediaSource> = []

        func makeSubtitle() -> String? {
            guard let title = prefs.lastPlayedTrackTitle, !title.isEmpty else { return nil }
            if let artist = prefs.lastPlayedTrackArtist, !artist.isEmpty {
                return "\(title) — \(artist)"
            }
            return title
        }

        // 1. Última app reproducida (siempre primera y destacada).
        if let lastSource = prefs.lastPlayedSource {
            let resolvedURL = lastSource.resolveInstalledAppURL(bundleID: prefs.lastPlayedBundleID)
            let fallbackWeb: URL? = {
                if let savedURL = prefs.lastPlayedTrackURL, let u = URL(string: savedURL) {
                    return u
                }
                return lastSource == .youtubeMusic ? URL(string: "https://music.youtube.com") : nil
            }()
            if resolvedURL != nil || fallbackWeb != nil {
                let name = (prefs.lastPlayedAppName?.isEmpty == false ? prefs.lastPlayedAppName! : lastSource.displayName)
                items.append(
                    NotchQuickLaunchApp(
                        id: "last::\(lastSource.rawValue)",
                        name: name,
                        source: lastSource,
                        bundleID: prefs.lastPlayedBundleID,
                        appURL: resolvedURL,
                        fallbackWebURL: fallbackWeb,
                        isLastPlayed: true,
                        lastTrackSubtitle: makeSubtitle()
                    )
                )
                addedSources.insert(lastSource)
            }
        }

        // 2. YouTube Music (PWA / Desktop app instalada o acceso directo web).
        if !addedSources.contains(.youtubeMusic) {
            let ytmURL = NotchMediaSource.youtubeMusic.resolveInstalledAppURL()
            items.append(
                NotchQuickLaunchApp(
                    id: "quick::youtubeMusic",
                    name: "YouTube Music",
                    source: .youtubeMusic,
                    bundleID: Self.ytmPWABundleID,
                    appURL: ytmURL,
                    fallbackWebURL: URL(string: "https://music.youtube.com"),
                    isLastPlayed: false
                )
            )
            addedSources.insert(.youtubeMusic)
        }

        // 3. Spotify (solo si está instalado en el Mac).
        if !addedSources.contains(.spotify),
           let spotifyURL = NotchMediaSource.spotify.resolveInstalledAppURL(bundleID: "com.spotify.client") {
            items.append(
                NotchQuickLaunchApp(
                    id: "quick::spotify",
                    name: "Spotify",
                    source: .spotify,
                    bundleID: "com.spotify.client",
                    appURL: spotifyURL,
                    isLastPlayed: false
                )
            )
            addedSources.insert(.spotify)
        }

        // 4. Apple Music (si está instalado y todavía hay lugar entre los 3 accesos).
        if items.count < 3,
           !addedSources.contains(.appleMusic),
           let musicURL = NotchMediaSource.appleMusic.resolveInstalledAppURL(bundleID: "com.apple.Music") {
            items.append(
                NotchQuickLaunchApp(
                    id: "quick::appleMusic",
                    name: "Apple Music",
                    source: .appleMusic,
                    bundleID: "com.apple.Music",
                    appURL: musicURL,
                    isLastPlayed: false
                )
            )
            addedSources.insert(.appleMusic)
        }

        return Array(items.prefix(3))
    }

    /// Abre o trae al frente el reproductor elegido desde el estado en espera del Notch.
    public func launchQuickApp(_ target: NotchQuickLaunchApp) {
        if let appURL = target.appURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in }
        } else if let webURL = target.fallbackWebURL {
            NSWorkspace.shared.open(webURL)
        }

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self?.refreshNow()
        }
    }

    // MARK: - Bucle de Polling Asincrónico (Zero Main-Thread IPC)

    private func restartPollingLoop() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                if !self.isDemoMode {
                    await self.runSinglePollCycle()
                }
                let intervalNs: UInt64 = (self.currentTrack?.isPlaying == true) ? 1_200_000_000 : 1_800_000_000
                try? await Task.sleep(nanoseconds: intervalNs)
            }
        }
    }

    private func schedulePostActionRefresh(delayMs: UInt64 = 240) async {
        try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
        guard !isDemoMode else { return }
        await runSinglePollCycle()
    }

    private func runSinglePollCycle() async {
        guard !isDemoMode else { return }

        let runningApps: [RunningAppInfo] = NSWorkspace.shared.runningApplications.compactMap { app in
            guard !app.isTerminated, let bid = app.bundleIdentifier else { return nil }
            return RunningAppInfo(
                pid: app.processIdentifier,
                bundleID: bid,
                localizedName: app.localizedName ?? ""
            )
        }

        let port = NotchPreferences.shared.youtubeMusicAPIPort
        let deniedSnapshot = deniedAutomationBundleIDs
        let shouldProbeYTMAPI: Bool = {
            let hasYTMDesktopRunning = runningApps.contains { Self.ytmDesktopBundleIDs.contains($0.bundleID) }
            if hasYTMDesktopRunning { return true }
            guard let failedAt = lastYTMProbeFailedAt else { return true }
            return Date().timeIntervalSince(failedAt) >= 6.0
        }()
        let previousTrack = currentTrack
        let previousArtworkCache = artworkURLCache
        let previousVideoIDCache = trackVideoIDCache
        let previousTrackAndVideo = lastTrackIDAndVideoID
        let forcedBrowserPause = browserUserForcedPause
        let silenceSince = browserAudioSilenceSince
        let optimisticToggleAt = lastOptimisticToggleAt

        let outcome = await Task.detached(priority: .utility) {
            await Self.performPollWork(
                runningApps: runningApps,
                ytmPort: port,
                shouldProbeYTMAPI: shouldProbeYTMAPI,
                deniedAutomationBundleIDs: deniedSnapshot,
                previousTrack: previousTrack,
                artworkURLCache: previousArtworkCache,
                trackVideoIDCache: previousVideoIDCache,
                previousTrackAndVideo: previousTrackAndVideo,
                forcedBrowserPause: forcedBrowserPause,
                browserAudioSilenceSince: silenceSince,
                lastOptimisticToggleAt: optimisticToggleAt
            )
        }.value

        guard !isDemoMode else { return }

        if !outcome.newlyDeniedAutomationBundleIDs.isEmpty {
            deniedAutomationBundleIDs.formUnion(outcome.newlyDeniedAutomationBundleIDs)
        }

        if !outcome.resolvedVideoIDByTrackKey.isEmpty {
            if trackVideoIDCache.count > 120 {
                trackVideoIDCache.removeAll(keepingCapacity: true)
            }
            for (k, v) in outcome.resolvedVideoIDByTrackKey {
                trackVideoIDCache[k] = v
            }
        }

        if shouldProbeYTMAPI {
            lastYTMProbeFailedAt = outcome.status.isYTMDesktopAPIReachable ? nil : Date()
        }

        // Actualizar temporizador de silencio para fallback de navegador/PWA
        if outcome.backend == .browserWindowFallback {
            if NotchLyricsAndAudioService.isDefaultOutputDeviceRunningAudio() {
                browserAudioSilenceSince = nil
                if browserUserForcedPause == true {
                    browserUserForcedPause = nil
                }
            } else if browserAudioSilenceSince == nil {
                browserAudioSilenceSince = Date()
            }
        } else {
            browserAudioSilenceSince = nil
            browserUserForcedPause = nil
        }

        connectionStatus = outcome.status
        applyResolvedTrack(
            outcome.track,
            backend: outcome.backend,
            detectedVideoID: outcome.detectedVideoID
        )
    }

    private func applyResolvedTrack(
        _ incoming: NotchTrackInfo?,
        backend: ActiveBackend,
        forceUpdate: Bool = false,
        detectedVideoID: String? = nil
    ) {
        let previous = currentTrack
        activeBackend = backend

        guard var next = incoming else {
            if previous != nil {
                currentTrack = nil
                currentArtworkImage = nil
                lastArtworkDataHash = nil
                lastTrackIDAndVideoID = nil
                pausedSince = nil
                NotchLyricsAndAudioService.shared.clearLyrics()
                onTrackChanged?(nil)
            }
            return
        }

        let isSameTrack = previous?.id == next.id

        // Si ya tenemos en caché la carátula exacta de YouTube para este videoId, aplicarla de inmediato.
        if next.artworkData == nil,
           let vid = detectedVideoID,
           let cachedYTArt = artworkURLCache["ytimg::\(vid)"] {
            next.artworkData = cachedYTArt
            next.dominantColor = NotchDominantColorExtractor.extractVibrantColor(
                from: cachedYTArt,
                fallback: next.sourceApp.brandAccentColor
            )
        }

        // Conservar carátula / color / metadatos enriquecidos si la encuesta entrante aún no los trae.
        if isSameTrack, let prev = previous {
            if next.artworkData == nil, let prevData = prev.artworkData {
                next.artworkData = prevData
                next.dominantColor = prev.dominantColor
            }
            if next.artist.isEmpty, !prev.artist.isEmpty {
                next.artist = prev.artist
            }
            if next.album.isEmpty, !prev.album.isEmpty {
                next.album = prev.album
            }
            if !next.hasKnownDuration, prev.hasKnownDuration {
                next.duration = prev.duration
            }

            // Evitar rebote visual con una encuesta en vuelo justo después de hacer clic/arrastrar la barra de avance.
            if !forceUpdate,
               let seekAt = lastOptimisticSeekAt,
               Date().timeIntervalSince(seekAt) < 0.95 {
                let expected = prev.interpolatedElapsedTime(at: next.lastUpdatedAt)
                if abs(next.elapsedTime - expected) > 2.5 {
                    next.elapsedTime = expected
                }
            }

            // Evitar micro-saltos hacia atrás (< 0.9s) en fuentes con resolución de 1 segundo mientras reproduce.
            if !forceUpdate, next.isPlaying, prev.isPlaying {
                let expected = prev.interpolatedElapsedTime(at: next.lastUpdatedAt)
                let diff = next.elapsedTime - expected
                if diff < 0 && diff > -0.95 {
                    next.elapsedTime = expected
                }
            }
        } else if next.artworkData == nil, let cached = iTunesEnrichmentCache[next.trackLookupKey] {
            if let data = cached.artworkData {
                next.artworkData = data
            }
            if let color = cached.dominantColor {
                next.dominantColor = color
            }
            if next.artist.isEmpty, let artist = cached.artist {
                next.artist = artist
            }
            if next.album.isEmpty, let album = cached.album {
                next.album = album
            }
            if !next.hasKnownDuration, let duration = cached.duration, duration > 0 {
                next.duration = duration
            }
        }

        if let vid = detectedVideoID, !vid.isEmpty {
            lastTrackIDAndVideoID = (trackID: next.id, videoID: vid)
        } else if !isSameTrack {
            lastTrackIDAndVideoID = nil
        }

        // Cachear extracción de color dominante y decodificación de `NSImage` en MainActor.
        if let artData = next.artworkData, !artData.isEmpty {
            let hash = artData.hashValue
            let colorKey = "\(next.id)::\(hash)"
            if let cachedColor = dominantColorCache[colorKey] {
                next.dominantColor = cachedColor
            } else if next.dominantColor == next.sourceApp.brandAccentColor {
                let extracted = NotchDominantColorExtractor.extractVibrantColor(
                    from: artData,
                    fallback: next.sourceApp.brandAccentColor
                )
                dominantColorCache[colorKey] = extracted
                next.dominantColor = extracted
            }

            if lastArtworkDataHash != hash || currentArtworkImage == nil {
                currentArtworkImage = NSImage(data: artData)
                lastArtworkDataHash = hash
            }
        } else {
            if currentArtworkImage != nil {
                currentArtworkImage = nil
                lastArtworkDataHash = nil
            }
        }

        // Rastrear cuándo pasó a pausa (para `hideWhenPaused` + `hideWhenPausedDelay`).
        if next.isPlaying {
            pausedSince = nil
        } else if pausedSince == nil {
            pausedSince = Date()
        }

        currentTrack = next

        if backend != .demo {
            NotchPreferences.shared.recordLastPlayed(track: next, videoId: detectedVideoID)
        }

        if !isSameTrack {
            lastTrackChangeAt = Date()
            NotchLyricsAndAudioService.shared.updateLyrics(for: next)
            onTrackChanged?(next)

            // Prioridad 1: carátula exacta de YouTube por videoId; fallback estricto: iTunes Search.
            if next.artworkData == nil || next.artist.isEmpty || !next.hasKnownDuration {
                triggerTrackEnrichmentIfNeeded(for: next, videoId: detectedVideoID)
            }
        } else if let vid = detectedVideoID,
                  !vid.isEmpty,
                  artworkURLCache["ytimg::\(vid)"] == nil,
                  !attemptedYouTubeArtworkVideoIDs.contains(vid) {
            // Si el videoId llegó un ciclo después del cambio de pista (o al abrir la vista del reproductor), traer la carátula exacta de YouTube.
            triggerTrackEnrichmentIfNeeded(for: next, videoId: vid)
        }
    }

    private func optimisticallyUpdatePlaybackState(isPlaying: Bool) {
        guard var track = currentTrack else { return }
        let now = Date()
        lastOptimisticToggleAt = now
        track.elapsedTime = track.interpolatedElapsedTime(at: now)
        track.isPlaying = isPlaying
        track.playbackRate = isPlaying ? 1.0 : 0.0
        track.lastUpdatedAt = now
        pausedSince = isPlaying ? nil : now
        currentTrack = track
    }

    // MARK: - Enriquecimiento de Carátula Exacta (YouTube Thumbnail + oEmbed + iTunes Estricto)

    private func triggerTrackEnrichmentIfNeeded(for track: NotchTrackInfo, videoId: String?) {
        let lookupKey = track.trackLookupKey
        let hasCachedYTArt = videoId.flatMap { artworkURLCache["ytimg::\($0)"] } != nil
        if videoId == nil && iTunesEnrichmentCache[lookupKey] != nil {
            return
        }
        if hasCachedYTArt && !track.artist.isEmpty && track.hasKnownDuration {
            return
        }
        if let vid = videoId, !vid.isEmpty {
            attemptedYouTubeArtworkVideoIDs.insert(vid)
        }

        metadataEnrichmentTask?.cancel()
        let trackID = track.id
        let title = track.title
        let artist = track.artist
        let album = track.album
        let needsArtwork = track.artworkData == nil || (videoId != nil && !hasCachedYTArt)
        let needsArtist = track.artist.isEmpty
        let needsDuration = !track.hasKnownDuration
        let fallbackColor = track.sourceApp.brandAccentColor

        metadataEnrichmentTask = Task.detached(priority: .utility) { [trackID, lookupKey, title, artist, album, videoId, needsArtwork, needsArtist, needsDuration, fallbackColor] in
            var resolvedArtwork: Data?
            var resolvedColor: NotchRGBColor?
            var resolvedArtist: String?
            var resolvedAlbum: String?
            var resolvedDuration: TimeInterval?

            // 1. Si tenemos videoId real de YouTube Music, descargar EXACTAMENTE la imagen que muestra YouTube Music
            //    y recortar franjas laterales/superiores (letterbox/pillarbox) para obtener la carátula cuadrada HD.
            if let vid = videoId, !vid.isEmpty {
                if needsArtwork, let ytArt = await Self.fetchYouTubeThumbnailArtwork(videoId: vid) {
                    resolvedArtwork = ytArt
                    resolvedColor = NotchDominantColorExtractor.extractVibrantColor(
                        from: ytArt,
                        fallback: fallbackColor
                    )
                    await MainActor.run {
                        NotchMediaService.shared.cacheArtworkData(ytArt, forURL: "ytimg::\(vid)")
                    }
                }
                if needsArtist, let oembedArtist = await Self.fetchYouTubeOEmbedArtist(videoId: vid) {
                    resolvedArtist = oembedArtist
                }
            }

            // 2. Solo si aún falta carátula, artista o duración, consultar iTunes con coincidencia ESTRICTA
            //    (nunca devolver una canción ajena si no coincide el título/artista).
            let stillNeedsArt = needsArtwork && resolvedArtwork == nil
            let stillNeedsArtist = needsArtist && (resolvedArtist ?? "").isEmpty
            if stillNeedsArt || stillNeedsArtist || needsDuration {
                let effectiveArtist = resolvedArtist ?? artist
                let iTunes = await Self.fetchITunesEnrichment(
                    title: title,
                    artist: effectiveArtist,
                    album: album,
                    fallbackColor: fallbackColor,
                    fetchArtwork: stillNeedsArt
                )
                if stillNeedsArt, let art = iTunes.artworkData {
                    resolvedArtwork = art
                    resolvedColor = iTunes.dominantColor
                }
                if stillNeedsArtist, let a = iTunes.artist, !a.isEmpty {
                    resolvedArtist = a
                }
                if album.isEmpty, let alb = iTunes.album, !alb.isEmpty {
                    resolvedAlbum = alb
                }
                if needsDuration, let dur = iTunes.duration, dur > 1 {
                    resolvedDuration = dur
                }
            }

            guard !Task.isCancelled else { return }

            let enriched = EnrichedMetadata(
                artist: resolvedArtist,
                album: resolvedAlbum,
                duration: resolvedDuration,
                artworkData: resolvedArtwork,
                dominantColor: resolvedColor
            )

            await MainActor.run {
                let service = NotchMediaService.shared
                if videoId == nil {
                    service.iTunesEnrichmentCache[lookupKey] = enriched
                }
                guard !service.isDemoMode, var active = service.currentTrack, active.id == trackID else {
                    return
                }
                var updated = false
                if let art = enriched.artworkData, (active.artworkData == nil || videoId != nil) {
                    active.artworkData = art
                    if let color = enriched.dominantColor {
                        active.dominantColor = color
                    }
                    service.currentArtworkImage = NSImage(data: art)
                    service.lastArtworkDataHash = art.hashValue
                    updated = true
                }
                if active.artist.isEmpty, let enrichedArtist = enriched.artist, !enrichedArtist.isEmpty {
                    active.artist = enrichedArtist
                    updated = true
                }
                if active.album.isEmpty, let enrichedAlbum = enriched.album, !enrichedAlbum.isEmpty {
                    active.album = enrichedAlbum
                    updated = true
                }
                if !active.hasKnownDuration, let dur = enriched.duration, dur > 1 {
                    active.duration = dur
                    updated = true
                }
                if updated {
                    service.currentTrack = active
                    // Si recién descubrimos el artista para una canción del navegador, refrescar letras LRCLIB.
                    if artist.isEmpty, !active.artist.isEmpty {
                        NotchLyricsAndAudioService.shared.updateLyrics(for: active)
                    }
                }
            }
        }
    }

    private struct YouTubeOEmbedResponse: Decodable, Sendable {
        let title: String?
        let author_name: String?
    }

    private nonisolated static func fetchYouTubeOEmbedArtist(videoId: String) async -> String? {
        var comps = URLComponents(string: "https://www.youtube.com/oembed")
        comps?.queryItems = [
            URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=\(videoId)"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = comps?.url else { return nil }
        do {
            let (data, response) = try await remoteAssetSession.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(YouTubeOEmbedResponse.self, from: data)
            guard var author = decoded.author_name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !author.isEmpty else {
                return nil
            }
            for suffix in [" - Topic", " – Topic", "VEVO"] {
                if author.hasSuffix(suffix) {
                    author = String(author.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return author.isEmpty ? nil : author
        } catch {
            return nil
        }
    }

    /// Descarga la miniatura oficial de YouTube Music para `videoId` y recorta automáticamente
    /// los bordes letterbox/pillarbox para entregar la carátula cuadrada exacta.
    private nonisolated static func fetchYouTubeThumbnailArtwork(videoId: String) async -> Data? {
        let variants = ["maxresdefault.jpg", "sddefault.jpg", "hqdefault.jpg"]
        for variant in variants {
            guard let url = URL(string: "https://i.ytimg.com/vi/\(videoId)/\(variant)") else { continue }
            guard let (rawData, response) = try? await remoteAssetSession.data(from: url),
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  rawData.count > 2_000 else {
                continue
            }
            // Verificar que no sea el placeholder gris de 120×90 que devuelve YouTube cuando no existe maxres.
            guard let source = CGImageSourceCreateWithData(rawData as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  cgImage.width >= 300,
                  cgImage.height >= 200 else {
                continue
            }
            return cropYouTubeArtworkToSquare(cgImage) ?? rawData
        }
        return nil
    }

    /// Recorta franjas negras/sólidas (letterbox superior/inferior en `hqdefault`/`sddefault` y
    /// pillarbox lateral en Art Tracks 16:9 `maxresdefault`) y centra un cuadrado nítido.
    private nonisolated static func cropYouTubeArtworkToSquare(_ image: CGImage) -> Data? {
        let width = image.width
        let height = image.height
        guard width >= 64, height >= 64 else { return nil }

        var cropRect = CGRect(x: 0, y: 0, width: width, height: height)

        // Detectar franjas uniformes arriba y abajo (típicas de 4:3 `sddefault`/`hqdefault`, 12.5% cada borde).
        if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) {
            let sampleW = min(width, 160)
            let sampleH = min(height, 120)
            var pixels = [UInt8](repeating: 0, count: sampleW * sampleH * 4)
            if let ctx = CGContext(
                data: &pixels,
                width: sampleW,
                height: sampleH,
                bitsPerComponent: 8,
                bytesPerRow: sampleW * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) {
                ctx.interpolationQuality = .low
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: sampleW, height: sampleH))

                func isUniformDarkBarRow(_ y: Int) -> Bool {
                    var maxDiff = 0
                    var sumLum = 0
                    let baseIdx = (y * sampleW + sampleW / 2) * 4
                    let refR = Int(pixels[baseIdx])
                    let refG = Int(pixels[baseIdx + 1])
                    let refB = Int(pixels[baseIdx + 2])
                    let startX = sampleW / 6
                    let endX = sampleW - sampleW / 6
                    var count = 0
                    for x in stride(from: startX, to: endX, by: 2) {
                        let i = (y * sampleW + x) * 4
                        let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
                        let diff = abs(r - refR) + abs(g - refG) + abs(b - refB)
                        if diff > maxDiff { maxDiff = diff }
                        sumLum += (r + g + b) / 3
                        count += 1
                    }
                    guard count > 0 else { return false }
                    let avgLum = sumLum / count
                    return maxDiff <= 18 && avgLum <= 24
                }

                let maxTrimY = Int(Double(sampleH) * 0.20)
                var topTrim = 0
                while topTrim < maxTrimY && isUniformDarkBarRow(topTrim) {
                    topTrim += 1
                }
                var bottomTrim = 0
                while bottomTrim < maxTrimY && isUniformDarkBarRow(sampleH - 1 - bottomTrim) {
                    bottomTrim += 1
                }

                // Solo aplicar recorte vertical si ambos bordes tienen franja letterbox simétrica (típico 4:3 de YouTube).
                if topTrim >= 4 && bottomTrim >= 4 && abs(topTrim - bottomTrim) <= 6 {
                    let scaleY = Double(height) / Double(sampleH)
                    let trimTopPx = Int((Double(topTrim) * scaleY).rounded())
                    let trimBotPx = Int((Double(bottomTrim) * scaleY).rounded())
                    let newH = height - trimTopPx - trimBotPx
                    if newH >= height / 2 {
                        cropRect = CGRect(x: 0, y: trimTopPx, width: width, height: newH)
                    }
                }
            }
        }

        // Recortar al cuadrado centrado (para Art Tracks 1280×720 esto captura exactamente el cuadrado 720×720).
        let side = min(cropRect.width, cropRect.height)
        let squareRect = CGRect(
            x: floor(cropRect.minX + (cropRect.width - side) / 2.0),
            y: floor(cropRect.minY + (cropRect.height - side) / 2.0),
            width: floor(side),
            height: floor(side)
        )

        guard let cropped = image.cropping(to: squareRect) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cropped)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
    }

    private struct ITunesSearchResponse: Decodable, Sendable {
        let results: [ITunesTrack]
    }

    private struct ITunesTrack: Decodable, Sendable {
        let trackName: String?
        let artistName: String?
        let collectionName: String?
        let artworkUrl100: String?
        let trackTimeMillis: Double?
    }

    private nonisolated static func fetchITunesEnrichment(
        title: String,
        artist: String,
        album: String = "",
        fallbackColor: NotchRGBColor,
        fetchArtwork: Bool = true
    ) async -> EnrichedMetadata {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            return EnrichedMetadata(artist: nil, album: nil, duration: nil, artworkData: nil, dominantColor: nil)
        }

        var queryTerms: [String] = []
        if !cleanArtist.isEmpty && !cleanAlbum.isEmpty {
            queryTerms.append("\(cleanTitle) \(cleanArtist) \(cleanAlbum)")
        }
        if !cleanArtist.isEmpty {
            queryTerms.append("\(cleanTitle) \(cleanArtist)")
        }
        queryTerms.append(cleanTitle)

        var matchedTrack: ITunesTrack?
        for term in queryTerms {
            var comps = URLComponents(string: "https://itunes.apple.com/search")
            comps?.queryItems = [
                URLQueryItem(name: "term", value: term),
                URLQueryItem(name: "country", value: "US"),
                URLQueryItem(name: "media", value: "music"),
                URLQueryItem(name: "entity", value: "song"),
                URLQueryItem(name: "limit", value: "8")
            ]
            guard let url = comps?.url else { continue }
            do {
                let (data, response) = try await remoteAssetSession.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
                let decoded = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
                if let best = pickBestITunesMatch(
                    decoded.results,
                    title: cleanTitle,
                    artist: cleanArtist,
                    album: cleanAlbum
                ) {
                    matchedTrack = best
                    break
                }
            } catch {
                continue
            }
        }

        guard let match = matchedTrack else {
            return EnrichedMetadata(artist: nil, album: nil, duration: nil, artworkData: nil, dominantColor: nil)
        }

        var artworkData: Data?
        var dominant: NotchRGBColor?
        if fetchArtwork, let urlStr = match.artworkUrl100 {
            let highResStr = urlStr.replacingOccurrences(of: "100x100bb", with: "600x600bb")
            if let artURL = URL(string: highResStr) ?? URL(string: urlStr),
               let (imgData, resp) = try? await remoteAssetSession.data(from: artURL),
               let http = resp as? HTTPURLResponse,
               http.statusCode == 200,
               !imgData.isEmpty {
                artworkData = imgData
                dominant = NotchDominantColorExtractor.extractVibrantColor(from: imgData, fallback: fallbackColor)
            }
        }

        let durationSec = match.trackTimeMillis.map { $0 / 1000.0 }
        return EnrichedMetadata(
            artist: match.artistName,
            album: match.collectionName,
            duration: durationSec,
            artworkData: artworkData,
            dominantColor: dominant
        )
    }

    private nonisolated static func normalizeSearchString(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func pickBestITunesMatch(
        _ candidates: [ITunesTrack],
        title: String,
        artist: String,
        album: String = ""
    ) -> ITunesTrack? {
        guard !candidates.isEmpty else { return nil }
        let normTitle = normalizeSearchString(title)
        let normArtist = normalizeSearchString(artist)
        let normAlbum = normalizeSearchString(album)
        guard !normTitle.isEmpty else { return nil }

        let titleTokens = Set(normTitle.split(separator: " ").map(String.init).filter { $0.count >= 2 })

        let scored: [(ITunesTrack, Int)] = candidates.compactMap { item in
            let itemTitle = normalizeSearchString(item.trackName ?? "")
            let itemArtist = normalizeSearchString(item.artistName ?? "")
            let itemAlbum = normalizeSearchString(item.collectionName ?? "")
            guard !itemTitle.isEmpty else { return nil }

            var titleScore = 0
            if itemTitle == normTitle {
                titleScore = 60
            } else if itemTitle.contains(normTitle) || normTitle.contains(itemTitle) {
                titleScore = 36
            } else if !titleTokens.isEmpty {
                let itemTokens = Set(itemTitle.split(separator: " ").map(String.init))
                let overlap = titleTokens.intersection(itemTokens).count
                let ratio = Double(overlap) / Double(titleTokens.count)
                if ratio >= 0.65 {
                    titleScore = 28
                }
            }

            // Nunca aceptar un candidato cuyo título no coincida mínimamente.
            guard titleScore >= 28 else { return nil }

            var artistScore = 0
            if !normArtist.isEmpty {
                if itemArtist == normArtist {
                    artistScore = 50
                } else if itemArtist.contains(normArtist) || normArtist.contains(itemArtist) {
                    artistScore = 30
                } else {
                    return nil
                }
            }

            var albumScore = 0
            if !normAlbum.isEmpty && !itemAlbum.isEmpty {
                if itemAlbum == normAlbum {
                    albumScore = 25
                } else if itemAlbum.contains(normAlbum) || normAlbum.contains(itemAlbum) {
                    albumScore = 15
                }
            }

            let artBonus = item.artworkUrl100 != nil ? 5 : 0
            return (item, titleScore + artistScore + albumScore + artBonus)
        }

        return scored.max(by: { $0.1 < $1.1 })?.0
    }

    // MARK: - Pipeline de Detección Multi-Fuente (Background)

    private nonisolated static func performPollWork(
        runningApps: [RunningAppInfo],
        ytmPort: Int,
        shouldProbeYTMAPI: Bool,
        deniedAutomationBundleIDs: Set<String>,
        previousTrack: NotchTrackInfo?,
        artworkURLCache: [String: Data],
        trackVideoIDCache: [String: String],
        previousTrackAndVideo: (trackID: String, videoID: String)?,
        forcedBrowserPause: Bool?,
        browserAudioSilenceSince: Date?,
        lastOptimisticToggleAt: Date?
    ) async -> PollOutcome {
        let isSpotifyRunning = runningApps.contains { $0.bundleID == "com.spotify.client" }
        let isAppleMusicRunning = runningApps.contains { $0.bundleID == "com.apple.Music" }
        let isYTMPWARunning = runningApps.contains {
            $0.bundleID == ytmPWABundleID || $0.localizedName.caseInsensitiveCompare("YouTube Music") == .orderedSame
        }
        let isChromeRunning = runningApps.contains { $0.bundleID == "com.google.Chrome" }
        let isSafariRunning = runningApps.contains { $0.bundleID == "com.apple.Safari" }

        var newlyDenied: [String] = []
        var isYTMReachable = false
        var hasMRData = false

        // 1. Prioridad 1: YouTube Music Desktop App Local API (th-ch/youtube-music / pear-desktop).
        if shouldProbeYTMAPI {
            if let ytmTrack = await pollYTMDesktopAPI(port: ytmPort, artworkURLCache: artworkURLCache) {
                isYTMReachable = true
                return PollOutcome(
                    track: ytmTrack,
                    backend: .ytmDesktopAPI,
                    status: NotchMediaConnectionStatus(
                        isYTMDesktopAPIReachable: true,
                        hasMediaRemoteData: false,
                        isSpotifyRunning: isSpotifyRunning,
                        isAppleMusicRunning: isAppleMusicRunning,
                        isYouTubeMusicPWARunning: isYTMPWARunning,
                        isChromeRunning: isChromeRunning,
                        isSafariRunning: isSafariRunning,
                        activeBackendName: "YouTube Music Desktop API"
                    ),
                    newlyDeniedAutomationBundleIDs: newlyDenied,
                    detectedVideoID: nil,
                    resolvedVideoIDByTrackKey: [:]
                )
            }
        }

        // 2. Prioridad 2: MediaRemote.framework nativo (cubre Safari, Chrome, YTM PWA, Apple Music, Spotify cuando macOS lo permite).
        if let mrSnapshot = await NotchMediaRemoteBridge.shared.fetchSnapshot() {
            hasMRData = true
            let source = classifySource(bundleID: mrSnapshot.bundleID, appName: mrSnapshot.appName)
            let normalizedID = "mr::\(mrSnapshot.bundleID ?? source.rawValue)::\(mrSnapshot.title.lowercased())::\(mrSnapshot.artist.lowercased())"
            let dominant = NotchDominantColorExtractor.extractVibrantColor(
                from: mrSnapshot.artworkData,
                fallback: source.brandAccentColor
            )
            let track = NotchTrackInfo(
                id: normalizedID,
                title: mrSnapshot.title,
                artist: mrSnapshot.artist,
                album: mrSnapshot.album,
                duration: mrSnapshot.duration,
                elapsedTime: mrSnapshot.elapsedTime,
                isPlaying: mrSnapshot.isPlaying,
                playbackRate: mrSnapshot.playbackRate,
                artworkData: mrSnapshot.artworkData,
                dominantColor: dominant,
                sourceApp: source,
                sourceBundleID: mrSnapshot.bundleID,
                sourceAppName: mrSnapshot.appName ?? source.displayName,
                supportsSeeking: mrSnapshot.duration > 1,
                supportsShuffleRepeat: false,
                isShuffling: false,
                repeatMode: .off,
                isLiked: nil,
                lastUpdatedAt: mrSnapshot.lastUpdatedAt
            )
            return PollOutcome(
                track: track,
                backend: .mediaRemote,
                status: NotchMediaConnectionStatus(
                    isYTMDesktopAPIReachable: isYTMReachable,
                    hasMediaRemoteData: true,
                    isSpotifyRunning: isSpotifyRunning,
                    isAppleMusicRunning: isAppleMusicRunning,
                    isYouTubeMusicPWARunning: isYTMPWARunning,
                    isChromeRunning: isChromeRunning,
                    isSafariRunning: isSafariRunning,
                    activeBackendName: "macOS MediaRemote"
                ),
                newlyDeniedAutomationBundleIDs: newlyDenied,
                detectedVideoID: nil,
                resolvedVideoIDByTrackKey: [:]
            )
        }

        // 3. Prioridad 3: Spotify (solo si está abierto en NSWorkspace — NUNCA lo lanza).
        if isSpotifyRunning && !deniedAutomationBundleIDs.contains("com.spotify.client") {
            let spotifyResult = await pollSpotify(artworkURLCache: artworkURLCache)
            if spotifyResult.permissionDenied {
                newlyDenied.append("com.spotify.client")
            } else if let track = spotifyResult.track {
                return PollOutcome(
                    track: track,
                    backend: .spotifyAppleScript,
                    status: NotchMediaConnectionStatus(
                        isYTMDesktopAPIReachable: isYTMReachable,
                        hasMediaRemoteData: hasMRData,
                        isSpotifyRunning: true,
                        isAppleMusicRunning: isAppleMusicRunning,
                        isYouTubeMusicPWARunning: isYTMPWARunning,
                        isChromeRunning: isChromeRunning,
                        isSafariRunning: isSafariRunning,
                        activeBackendName: "Spotify"
                    ),
                    newlyDeniedAutomationBundleIDs: newlyDenied,
                    detectedVideoID: nil,
                    resolvedVideoIDByTrackKey: [:]
                )
            }
        }

        // 4. Prioridad 4: Apple Music (solo si Music.app está abierto — NUNCA lo lanza).
        if isAppleMusicRunning && !deniedAutomationBundleIDs.contains("com.apple.Music") {
            let musicResult = await pollAppleMusic()
            if musicResult.permissionDenied {
                newlyDenied.append("com.apple.Music")
            } else if let track = musicResult.track {
                return PollOutcome(
                    track: track,
                    backend: .appleMusicAppleScript,
                    status: NotchMediaConnectionStatus(
                        isYTMDesktopAPIReachable: isYTMReachable,
                        hasMediaRemoteData: hasMRData,
                        isSpotifyRunning: isSpotifyRunning,
                        isAppleMusicRunning: true,
                        isYouTubeMusicPWARunning: isYTMPWARunning,
                        isChromeRunning: isChromeRunning,
                        isSafariRunning: isSafariRunning,
                        activeBackendName: "Apple Music"
                    ),
                    newlyDeniedAutomationBundleIDs: newlyDenied,
                    detectedVideoID: nil,
                    resolvedVideoIDByTrackKey: [:]
                )
            }
        }

        // 5. Prioridad 5: YouTube Music en Chrome PWA (`YouTube Music.app`) y navegadores (AX Player Bar / pestañas / CGWindowList).
        if let browserResult = await pollYouTubeMusicInBrowsers(
            runningApps: runningApps,
            previousTrack: previousTrack,
            artworkURLCache: artworkURLCache,
            trackVideoIDCache: trackVideoIDCache,
            previousTrackAndVideo: previousTrackAndVideo,
            forcedBrowserPause: forcedBrowserPause,
            browserAudioSilenceSince: browserAudioSilenceSince,
            lastOptimisticToggleAt: lastOptimisticToggleAt
        ) {
            return PollOutcome(
                track: browserResult.track,
                backend: .browserWindowFallback,
                status: NotchMediaConnectionStatus(
                    isYTMDesktopAPIReachable: isYTMReachable,
                    hasMediaRemoteData: hasMRData,
                    isSpotifyRunning: isSpotifyRunning,
                    isAppleMusicRunning: isAppleMusicRunning,
                    isYouTubeMusicPWARunning: isYTMPWARunning,
                    isChromeRunning: isChromeRunning,
                    isSafariRunning: isSafariRunning,
                    activeBackendName: browserResult.backendLabel
                ),
                newlyDeniedAutomationBundleIDs: newlyDenied,
                detectedVideoID: browserResult.videoId,
                resolvedVideoIDByTrackKey: browserResult.videoIDMapping
            )
        }

        return PollOutcome(
            track: nil,
            backend: .none,
            status: NotchMediaConnectionStatus(
                isYTMDesktopAPIReachable: isYTMReachable,
                hasMediaRemoteData: hasMRData,
                isSpotifyRunning: isSpotifyRunning,
                isAppleMusicRunning: isAppleMusicRunning,
                isYouTubeMusicPWARunning: isYTMPWARunning,
                isChromeRunning: isChromeRunning,
                isSafariRunning: isSafariRunning,
                activeBackendName: ""
            ),
            newlyDeniedAutomationBundleIDs: newlyDenied,
            detectedVideoID: nil,
            resolvedVideoIDByTrackKey: [:]
        )
    }

    // MARK: - Backend 1: YouTube Music Desktop API (th-ch / pear-desktop)

    private struct YTMSongResponse: Decodable, Sendable {
        let title: String?
        let artist: String?
        let album: String?
        let imageSrc: String?
        let songDuration: Double?
        let elapsedSeconds: Double?
        let isPaused: Bool?
        let videoId: String?
        let url: String?
        let isLike: Bool?
        let liked: Bool?
        let likeStatus: String?
    }

    private struct YTMShuffleResponse: Decodable, Sendable {
        let state: Bool?
    }

    private struct YTMRepeatResponse: Decodable, Sendable {
        let mode: String?
    }

    private nonisolated static func pollYTMDesktopAPI(
        port: Int,
        artworkURLCache: [String: Data]
    ) async -> NotchTrackInfo? {
        guard let url = URL(string: "http://127.0.0.1:\(port)/api/v1/song") else { return nil }
        do {
            let (data, response) = try await localAPISession.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            let song = try JSONDecoder().decode(YTMSongResponse.self, from: data)
            let title = (song.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }

            let artist = (song.artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let album = (song.album ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let isPlaying = !(song.isPaused ?? false)
            let duration = song.songDuration ?? 0
            let elapsed = song.elapsedSeconds ?? 0

            var artworkData: Data?
            if let imgStr = song.imageSrc, !imgStr.isEmpty {
                if let cached = artworkURLCache[imgStr] {
                    artworkData = cached
                } else if let imgURL = URL(string: imgStr),
                          let (imgBytes, imgResp) = try? await remoteAssetSession.data(from: imgURL),
                          let imgHTTP = imgResp as? HTTPURLResponse,
                          imgHTTP.statusCode == 200,
                          !imgBytes.isEmpty {
                    artworkData = imgBytes
                    await MainActor.run {
                        NotchMediaService.shared.cacheArtworkData(imgBytes, forURL: imgStr)
                    }
                }
            }

            // Consultar estado opcional de shuffle/repeat sin fallar si el servidor no lo expone.
            var isShuffling = false
            if let shuffleURL = URL(string: "http://127.0.0.1:\(port)/api/v1/shuffle"),
               let (sData, sResp) = try? await localAPISession.data(from: shuffleURL),
               let sHTTP = sResp as? HTTPURLResponse, sHTTP.statusCode == 200,
               let decoded = try? JSONDecoder().decode(YTMShuffleResponse.self, from: sData) {
                isShuffling = decoded.state ?? false
            }

            var repeatMode: NotchRepeatMode = .off
            if let repeatURL = URL(string: "http://127.0.0.1:\(port)/api/v1/repeat-mode"),
               let (rData, rResp) = try? await localAPISession.data(from: repeatURL),
               let rHTTP = rResp as? HTTPURLResponse, rHTTP.statusCode == 200,
               let decoded = try? JSONDecoder().decode(YTMRepeatResponse.self, from: rData),
               let modeStr = decoded.mode?.uppercased() {
                if modeStr == "ONE" { repeatMode = .one }
                else if modeStr == "ALL" { repeatMode = .all }
            }

            let liked: Bool?
            if let isLike = song.isLike {
                liked = isLike
            } else if let isLiked = song.liked {
                liked = isLiked
            } else if let status = song.likeStatus?.uppercased() {
                liked = (status == "LIKE")
            } else {
                liked = nil
            }

            let dominant = NotchDominantColorExtractor.extractVibrantColor(
                from: artworkData,
                fallback: NotchMediaSource.youtubeMusic.brandAccentColor
            )

            let trackID = "ytm::\(song.videoId ?? "\(title.lowercased())::\(artist.lowercased())")"
            return NotchTrackInfo(
                id: trackID,
                title: title,
                artist: artist,
                album: album,
                duration: duration,
                elapsedTime: elapsed,
                isPlaying: isPlaying,
                playbackRate: isPlaying ? 1.0 : 0.0,
                artworkData: artworkData,
                dominantColor: dominant,
                sourceApp: .youtubeMusic,
                sourceBundleID: "com.github.th-ch.youtube-music",
                sourceAppName: "YouTube Music",
                supportsSeeking: duration > 1,
                supportsShuffleRepeat: true,
                isShuffling: isShuffling,
                repeatMode: repeatMode,
                isLiked: liked,
                lastUpdatedAt: Date()
            )
        } catch {
            return nil
        }
    }

    private nonisolated static func postYTMCommand(
        port: Int,
        paths: [String],
        body: Data? = nil
    ) async -> Bool {
        for path in paths {
            guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            if let body {
                req.httpBody = body
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            if let (_, response) = try? await localAPISession.data(for: req),
               let http = response as? HTTPURLResponse,
               (200...299).contains(http.statusCode) {
                return true
            }
        }
        return false
    }

    // MARK: - Backend 3: Spotify AppleScript (Solo si Spotify está abierto)

    private struct ScriptPollResult: Sendable {
        let track: NotchTrackInfo?
        let permissionDenied: Bool
    }

    private nonisolated static func pollSpotify(artworkURLCache: [String: Data]) async -> ScriptPollResult {
        let script = """
        tell application id "com.spotify.client"
            set pState to player state as string
            if pState is "stopped" then return ""
            set tName to name of current track
            set tArtist to artist of current track
            set tAlbum to album of current track
            set tDur to duration of current track
            set tPos to player position
            set tArt to artwork url of current track
            set tShuf to shuffling
            set tRep to repeating
            set tID to id of current track
            set sep to character id 31
            return pState & sep & tName & sep & tArtist & sep & tAlbum & sep & (tDur as string) & sep & (tPos as string) & sep & tArt & sep & (tShuf as string) & sep & (tRep as string) & sep & tID
        end tell
        """

        let result = await runAppleScript(script)
        if result.permissionDenied {
            return ScriptPollResult(track: nil, permissionDenied: true)
        }
        guard let output = result.output, !output.isEmpty else {
            return ScriptPollResult(track: nil, permissionDenied: false)
        }

        let parts = output.components(separatedBy: "\u{1F}")
        guard parts.count >= 10 else {
            return ScriptPollResult(track: nil, permissionDenied: false)
        }

        let stateStr = parts[0].lowercased()
        let title = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return ScriptPollResult(track: nil, permissionDenied: false) }

        let artist = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let album = parts[3].trimmingCharacters(in: .whitespacesAndNewlines)
        let rawDuration = parseLocaleDouble(parts[4]) ?? 0
        // Spotify reporta duration en milisegundos (e.g. 200040).
        let duration = rawDuration > 10_000 ? (rawDuration / 1000.0) : rawDuration
        let elapsed = parseLocaleDouble(parts[5]) ?? 0
        let artworkURLString = parts[6].trimmingCharacters(in: .whitespacesAndNewlines)
        let isShuffling = parts[7].lowercased() == "true"
        let isRepeating = parts[8].lowercased() == "true"
        let spotifyID = parts[9].trimmingCharacters(in: .whitespacesAndNewlines)
        let isPlaying = stateStr == "playing"

        var artworkData: Data?
        if !artworkURLString.isEmpty {
            if let cached = artworkURLCache[artworkURLString] {
                artworkData = cached
            } else if let url = URL(string: artworkURLString),
                      let (bytes, resp) = try? await remoteAssetSession.data(from: url),
                      let http = resp as? HTTPURLResponse,
                      http.statusCode == 200,
                      !bytes.isEmpty {
                artworkData = bytes
                await MainActor.run {
                    NotchMediaService.shared.cacheArtworkData(bytes, forURL: artworkURLString)
                }
            }
        }

        let dominant = NotchDominantColorExtractor.extractVibrantColor(
            from: artworkData,
            fallback: NotchMediaSource.spotify.brandAccentColor
        )

        let track = NotchTrackInfo(
            id: "spotify::\(spotifyID.isEmpty ? "\(title.lowercased())::\(artist.lowercased())" : spotifyID)",
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            elapsedTime: elapsed,
            isPlaying: isPlaying,
            playbackRate: isPlaying ? 1.0 : 0.0,
            artworkData: artworkData,
            dominantColor: dominant,
            sourceApp: .spotify,
            sourceBundleID: "com.spotify.client",
            sourceAppName: "Spotify",
            supportsSeeking: duration > 1,
            supportsShuffleRepeat: true,
            isShuffling: isShuffling,
            repeatMode: isRepeating ? .all : .off,
            isLiked: nil,
            lastUpdatedAt: Date()
        )
        return ScriptPollResult(track: track, permissionDenied: false)
    }

    // MARK: - Backend 4: Apple Music AppleScript (Solo si Music.app está abierto)

    private nonisolated static func pollAppleMusic() async -> ScriptPollResult {
        let script = """
        tell application id "com.apple.Music"
            set pState to player state as string
            if pState is "stopped" then return ""
            set tName to name of current track
            set tArtist to artist of current track
            set tAlbum to album of current track
            set tDur to duration of current track
            set tPos to player position
            set tShuf to shuffle enabled
            set tRep to song repeat as string
            set tID to persistent ID of current track
            set tFav to ""
            try
                set tFav to (favorited of current track) as string
            end try
            set sep to character id 31
            return pState & sep & tName & sep & tArtist & sep & tAlbum & sep & (tDur as string) & sep & (tPos as string) & sep & (tShuf as string) & sep & tRep & sep & tID & sep & tFav
        end tell
        """

        let result = await runAppleScript(script)
        if result.permissionDenied {
            return ScriptPollResult(track: nil, permissionDenied: true)
        }
        guard let output = result.output, !output.isEmpty else {
            return ScriptPollResult(track: nil, permissionDenied: false)
        }

        let parts = output.components(separatedBy: "\u{1F}")
        guard parts.count >= 10 else {
            return ScriptPollResult(track: nil, permissionDenied: false)
        }

        let stateStr = parts[0].lowercased()
        let title = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return ScriptPollResult(track: nil, permissionDenied: false) }

        let artist = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let album = parts[3].trimmingCharacters(in: .whitespacesAndNewlines)
        let duration = parseLocaleDouble(parts[4]) ?? 0
        let elapsed = parseLocaleDouble(parts[5]) ?? 0
        let isShuffling = parts[6].lowercased() == "true"
        let repStr = parts[7].lowercased()
        let repeatMode: NotchRepeatMode = repStr == "one" ? .one : (repStr == "all" ? .all : .off)
        let persistentID = parts[8].trimmingCharacters(in: .whitespacesAndNewlines)
        let favStr = parts[9].lowercased()
        let isLiked: Bool? = favStr == "true" ? true : (favStr == "false" ? false : nil)
        let isPlaying = stateStr == "playing"

        let track = NotchTrackInfo(
            id: "applemusic::\(persistentID.isEmpty ? "\(title.lowercased())::\(artist.lowercased())" : persistentID)",
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            elapsedTime: elapsed,
            isPlaying: isPlaying,
            playbackRate: isPlaying ? 1.0 : 0.0,
            artworkData: nil,
            dominantColor: NotchMediaSource.appleMusic.brandAccentColor,
            sourceApp: .appleMusic,
            sourceBundleID: "com.apple.Music",
            sourceAppName: "Apple Music",
            supportsSeeking: duration > 1,
            supportsShuffleRepeat: true,
            isShuffling: isShuffling,
            repeatMode: repeatMode,
            isLiked: isLiked,
            lastUpdatedAt: Date()
        )
        return ScriptPollResult(track: track, permissionDenied: false)
    }

    // MARK: - Backend 5: YouTube Music en Chrome PWA y Navegadores (AX Player Bar + Pestañas + Sin Spam de Permisos)

    private struct BrowserDetectedTrack: Sendable {
        let title: String
        let artist: String
        let album: String
        let elapsedTime: TimeInterval?
        let duration: TimeInterval?
        let isPlaying: Bool?
        let repeatMode: NotchRepeatMode
        let videoId: String?
        let source: NotchMediaSource
        let bundleID: String
        let appName: String
        let fromAXPlayerBar: Bool
    }

    private struct BrowserPollResult: Sendable {
        let track: NotchTrackInfo
        let videoId: String?
        let videoIDMapping: [String: String]
        let backendLabel: String
    }

    private nonisolated static func pollYouTubeMusicInBrowsers(
        runningApps: [RunningAppInfo],
        previousTrack: NotchTrackInfo?,
        artworkURLCache: [String: Data],
        trackVideoIDCache: [String: String],
        previousTrackAndVideo: (trackID: String, videoID: String)?,
        forcedBrowserPause: Bool?,
        browserAudioSilenceSince: Date?,
        lastOptimisticToggleAt: Date?
    ) async -> BrowserPollResult? {
        let candidateApps = runningApps.filter { app in
            app.bundleID == ytmPWABundleID ||
            app.localizedName.caseInsensitiveCompare("YouTube Music") == .orderedSame ||
            browserBundleIDs.contains(app.bundleID)
        }
        guard !candidateApps.isEmpty else { return nil }

        // Ordenar priorizando la PWA dedicada `YouTube Music.app` antes que navegadores generales.
        let orderedApps = candidateApps.sorted { lhs, rhs in
            let lIsPWA = lhs.bundleID == ytmPWABundleID || lhs.localizedName.caseInsensitiveCompare("YouTube Music") == .orderedSame
            let rIsPWA = rhs.bundleID == ytmPWABundleID || rhs.localizedName.caseInsensitiveCompare("YouTube Music") == .orderedSame
            return lIsPWA && !rIsPWA
        }

        var detected: BrowserDetectedTrack?

        // A) Inspección directa de la barra de reproducción de YouTube Music vía Accessibility (`AXToolbar` / `ytmusic-player-bar`).
        //    Entrega exactamente: título de la canción, artista, álbum, tiempo transcurrido/duración real, play/pause real y `videoId`.
        if AXIsProcessTrusted() {
            for app in orderedApps {
                if let playerBarTrack = inspectYouTubeMusicAXPlayerBar(app: app) {
                    detected = playerBarTrack
                    break
                }
            }
        }

        // B) Inspección silenciosa de pestañas en Chrome / Safari / Brave / Arc / Edge (incluye la PWA de Chrome aunque esté minimizada)
        //    SOLO si Automatización ya está autorizada (sin cuadros de diálogo).
        if detected == nil {
            for app in orderedApps where browserBundleIDs.contains(app.bundleID) {
                guard isAutomationAlreadyAuthorized(forBundleID: app.bundleID) else { continue }
                if let tabHit = await inspectAuthorizedBrowserForYouTubeMusic(app: app) {
                    detected = tabHit
                    break
                }
            }
        }

        // C) Fallback de títulos de ventana vía Accessibility (solo si no hubo Player Bar ni pestaña autorizada).
        if detected == nil && AXIsProcessTrusted() {
            for app in orderedApps {
                let titles = readAXWindowTitles(pid: app.pid)
                for rawTitle in titles {
                    if let parsed = parseYouTubeMusicWindowTitle(
                        rawTitle,
                        bundleID: app.bundleID,
                        appName: app.localizedName
                    ) {
                        detected = parsed
                        break
                    }
                }
                if detected != nil { break }
            }
        }

        // D) Respaldo vía CGWindowListCopyWindowInfo (sin diálogos).
        if detected == nil,
           let windowList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            let pidLookup = Dictionary(uniqueKeysWithValues: orderedApps.map { ($0.pid, $0) })
            for win in windowList {
                guard let layer = win[kCGWindowLayer as String] as? Int, layer == 0,
                      let ownerPID = (win[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                      let app = pidLookup[ownerPID],
                      let title = win[kCGWindowName as String] as? String,
                      !title.isEmpty else {
                    continue
                }
                if let parsed = parseYouTubeMusicWindowTitle(
                    title,
                    bundleID: app.bundleID,
                    appName: app.localizedName
                ) {
                    detected = parsed
                    break
                }
            }
        }

        guard let found = detected else { return nil }

        let trackID = "browser::\(found.bundleID)::\(found.title.lowercased())::\(found.artist.lowercased())"
        let isSameTrack = previousTrack?.id == trackID
        let lookupKey = "\(found.title.lowercased())::\(found.artist.lowercased())"

        // Resolver `videoId`: evitar asociar un `videoId` obsoleto de la canción anterior durante los ~200 ms de transición de URL.
        var resolvedVideoID: String?
        if let rawVid = found.videoId, !rawVid.isEmpty {
            if !isSameTrack,
               let prevPair = previousTrackAndVideo,
               prevPair.trackID != trackID,
               prevPair.videoID == rawVid {
                // La URL de Chrome aún conserva el videoId de la canción anterior; esperar al próximo ciclo.
                resolvedVideoID = trackVideoIDCache[lookupKey]
            } else {
                resolvedVideoID = rawVid
            }
        } else {
            resolvedVideoID = trackVideoIDCache[lookupKey]
        }

        var videoMapping: [String: String] = [:]
        if let vid = resolvedVideoID, !vid.isEmpty {
            videoMapping[lookupKey] = vid
        }

        // Estado de reproducción: priorizar el botón real Play/Pause de YouTube Music (con breve ventana de gracia tras un clic optimista).
        let isPlaying: Bool
        let withinOptimisticGrace = lastOptimisticToggleAt.map { Date().timeIntervalSince($0) < 0.9 } ?? false
        if withinOptimisticGrace, let prev = previousTrack {
            isPlaying = prev.isPlaying
        } else if let axPlaying = found.isPlaying {
            isPlaying = axPlaying
        } else {
            let audioRunning = NotchLyricsAndAudioService.isDefaultOutputDeviceRunningAudio()
            if let forcedPause = forcedBrowserPause {
                isPlaying = !forcedPause
            } else if audioRunning {
                isPlaying = true
            } else if let silenceSince = browserAudioSilenceSince, Date().timeIntervalSince(silenceSince) >= 1.8 {
                isPlaying = false
            } else {
                isPlaying = previousTrack?.isPlaying ?? true
            }
        }

        let duration: TimeInterval
        if let exactDur = found.duration, exactDur > 1 {
            duration = exactDur
        } else if isSameTrack {
            duration = previousTrack?.duration ?? 0
        } else {
            duration = 0
        }

        let elapsed: TimeInterval
        if let exactElapsed = found.elapsedTime {
            elapsed = exactElapsed
        } else if isSameTrack, let prev = previousTrack {
            elapsed = prev.interpolatedElapsedTime(at: Date())
        } else {
            elapsed = 0
        }

        // Si ya tenemos en caché la carátula exacta de YouTube para este `videoId`, usarla al instante.
        let cachedArtwork: Data?
        if let vid = resolvedVideoID, let cached = artworkURLCache["ytimg::\(vid)"] {
            cachedArtwork = cached
        } else if isSameTrack {
            cachedArtwork = previousTrack?.artworkData
        } else {
            cachedArtwork = nil
        }

        let dominantColor: NotchRGBColor
        if let art = cachedArtwork, isSameTrack, let prevColor = previousTrack?.dominantColor, art == previousTrack?.artworkData {
            dominantColor = prevColor
        } else if let art = cachedArtwork {
            dominantColor = NotchDominantColorExtractor.extractVibrantColor(
                from: art,
                fallback: found.source.brandAccentColor
            )
        } else {
            dominantColor = found.source.brandAccentColor
        }

        let track = NotchTrackInfo(
            id: trackID,
            title: found.title,
            artist: found.artist,
            album: found.album,
            duration: duration,
            elapsedTime: elapsed,
            isPlaying: isPlaying,
            playbackRate: isPlaying ? 1.0 : 0.0,
            artworkData: cachedArtwork,
            dominantColor: dominantColor,
            sourceApp: found.source,
            sourceBundleID: found.bundleID,
            sourceAppName: found.source == .youtubeMusic ? "YouTube Music" : found.appName,
            supportsSeeking: duration > 1,
            supportsShuffleRepeat: false,
            isShuffling: false,
            repeatMode: found.repeatMode,
            isLiked: nil,
            lastUpdatedAt: Date()
        )

        return BrowserPollResult(
            track: track,
            videoId: resolvedVideoID,
            videoIDMapping: videoMapping,
            backendLabel: found.fromAXPlayerBar ? "YouTube Music (Player Bar)" : "YouTube Music (Browser / PWA)"
        )
    }

    // MARK: - Inspector AX Directo de la Barra de Reproducción de YouTube Music

    private nonisolated static func axAttr(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private nonisolated static func axString(_ element: AXUIElement, _ attribute: String) -> String {
        (axAttr(element, attribute) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private nonisolated static func axURLString(_ element: AXUIElement) -> String? {
        guard let raw = axAttr(element, "AXURL") else { return nil }
        if let url = raw as? URL {
            return url.absoluteString
        }
        if let str = raw as? String, !str.isEmpty {
            return str
        }
        return nil
    }

    private nonisolated static func findAXWebArea(in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        guard depth <= 8 else { return nil }
        if axString(element, kAXRoleAttribute) == "AXWebArea" {
            return element
        }
        guard let children = axAttr(element, kAXChildrenAttribute) as? [AXUIElement] else {
            return nil
        }
        for child in children {
            if let found = findAXWebArea(in: child, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    private nonisolated static func findYTMPlayerToolbar(in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        guard depth <= 6 else { return nil }
        if axString(element, kAXRoleAttribute) == "AXToolbar" {
            let classes = (axAttr(element, "AXDOMClassList") as? [String] ?? [])
                .joined(separator: " ")
                .lowercased()
            let title = axString(element, kAXTitleAttribute).lowercased()
            let desc = axString(element, kAXDescriptionAttribute).lowercased()
            if classes.contains("ytmusic-player-bar") ||
                classes.contains("ytmusic-app") ||
                title.contains("player") ||
                desc.contains("player") ||
                title.contains("reproductor") ||
                desc.contains("reproductor") ||
                title.contains("lecteur") ||
                title.contains("wiedergabe") {
                return element
            }
        }
        guard let children = axAttr(element, kAXChildrenAttribute) as? [AXUIElement] else {
            return nil
        }
        // Recorrer desde el final porque `<ytmusic-player-bar>` siempre está al pie del DOM (~1 ms).
        for child in children.reversed() {
            if let found = findYTMPlayerToolbar(in: child, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    private nonisolated static func inspectYouTubeMusicAXPlayerBar(app: RunningAppInfo) -> BrowserDetectedTrack? {
        let isYTMPWA = app.bundleID == ytmPWABundleID ||
            app.localizedName.caseInsensitiveCompare("YouTube Music") == .orderedSame
        let axApp = AXUIElementCreateApplication(app.pid)
        guard let windows = axAttr(axApp, kAXWindowsAttribute) as? [AXUIElement], !windows.isEmpty else {
            return nil
        }

        for win in windows {
            guard let webArea = findAXWebArea(in: win) else { continue }
            let webURL = axURLString(webArea) ?? ""
            let isYTMURL = webURL.lowercased().contains("music.youtube.com")
            guard isYTMURL || isYTMPWA else { continue }

            guard let playerBar = findYTMPlayerToolbar(in: webArea) else { continue }
            guard let parsed = parseYTMPlayerToolbar(
                playerBar,
                pageURL: webURL,
                bundleID: app.bundleID,
                appName: isYTMPWA ? "YouTube Music" : app.localizedName
            ) else {
                continue
            }
            return parsed
        }
        return nil
    }

    private nonisolated static func parseYTMPlayerToolbar(
        _ toolbar: AXUIElement,
        pageURL: String,
        bundleID: String,
        appName: String
    ) -> BrowserDetectedTrack? {
        var songTitle = ""
        var artistLinks: [String] = []
        var albumLink = ""
        var bylineFallback = ""
        var timePair: (elapsed: TimeInterval, duration: TimeInterval)?
        var progressBarFallback: (elapsed: TimeInterval, duration: TimeInterval)?
        var isPlaying: Bool?
        var repeatMode: NotchRepeatMode = .off

        func walk(_ el: AXUIElement, depth: Int, inLeftControls: Bool, inRightControls: Bool) {
            guard depth <= 9 else { return }
            let role = axString(el, kAXRoleAttribute)
            let domID = axString(el, "AXDOMIdentifier")
            let title = axString(el, kAXTitleAttribute)
            let desc = axString(el, kAXDescriptionAttribute)
            let valueStr = axString(el, kAXValueAttribute)

            let nowLeft = inLeftControls || domID == "left-controls"
            let nowRight = inRightControls || domID == "right-controls"

            // 1. Estado Play / Pause real desde `play-pause-button`
            if domID == "play-pause-button" {
                let label = (title.isEmpty ? desc : title).lowercased()
                if let parsedPlay = interpretPlayPauseLabel(label) {
                    isPlaying = parsedPlay
                }
            } else if nowLeft && role == "AXButton" && isPlaying == nil {
                let label = (title.isEmpty ? desc : title).lowercased()
                if let parsedPlay = interpretPlayPauseLabel(label) {
                    isPlaying = parsedPlay
                }
            }

            // 2. Tiempo transcurrido / duración exactos (`3:14 / 6:14`)
            if role == "AXStaticText" && timePair == nil {
                if let parsed = parseSlashTimePair(valueStr) {
                    timePair = parsed
                }
            } else if domID == "progress-bar" && progressBarFallback == nil {
                let raw = valueStr.isEmpty ? axString(el, "AXValueDescription") : valueStr
                if let parsed = parseVerboseProgressDuration(raw) {
                    progressBarFallback = parsed
                }
            }

            // 3. Título exacto de la canción (encabezado del centro de la barra de reproducción)
            if role == "AXHeading" && !nowLeft && !nowRight && songTitle.isEmpty {
                if !title.isEmpty {
                    songTitle = title
                } else if let kids = axAttr(el, kAXChildrenAttribute) as? [AXUIElement] {
                    for kid in kids {
                        let txt = axString(kid, kAXValueAttribute)
                        if !txt.isEmpty {
                            songTitle = txt
                            break
                        }
                    }
                }
            }

            // 4. Artista y Álbum exactos desde el grupo central (links `/channel/` = artista, `/browse/MPRE` = álbum)
            if !nowLeft && !nowRight {
                if role == "AXLink" {
                    let linkText = !title.isEmpty ? title : (!desc.isEmpty ? desc : valueStr)
                    let linkURL = (axURLString(el) ?? "").lowercased()
                    if !linkText.isEmpty {
                        if linkURL.contains("/channel/") {
                            if !artistLinks.contains(linkText) {
                                artistLinks.append(linkText)
                            }
                        } else if linkURL.contains("/browse/mpre") && albumLink.isEmpty {
                            albumLink = linkText
                        }
                    }
                } else if role == "AXGroup" && bylineFallback.isEmpty {
                    let candidate = !title.isEmpty ? title : desc
                    if candidate.contains(" • ") || candidate.contains(" · ") {
                        bylineFallback = candidate
                    }
                }
            }

            // 5. Modo de repetición desde `right-controls`
            if nowRight && role == "AXButton" {
                let label = (title.isEmpty ? desc : title).lowercased()
                if label.contains("repeat") || label.contains("repetir") {
                    if label.contains("one") || label.contains("una") || label.contains(" 1") {
                        repeatMode = .one
                    } else if label.contains("all") || label.contains("todo") || label.contains("todas") {
                        repeatMode = .all
                    } else if label.contains("off") || label.contains("desactiv") {
                        repeatMode = .off
                    }
                }
            }

            if let kids = axAttr(el, kAXChildrenAttribute) as? [AXUIElement] {
                for kid in kids {
                    walk(kid, depth: depth + 1, inLeftControls: nowLeft, inRightControls: nowRight)
                }
            }
        }

        walk(toolbar, depth: 0, inLeftControls: false, inRightControls: false)

        let cleanTitle = stripPlaybackDecorations(songTitle)
        guard !cleanTitle.isEmpty, cleanTitle.lowercased() != "youtube music" else {
            return nil
        }

        var artist = artistLinks.joined(separator: ", ")
        var album = albumLink

        if (artist.isEmpty || album.isEmpty) && !bylineFallback.isEmpty {
            let separator = bylineFallback.contains(" • ") ? " • " : " · "
            let parts = bylineFallback
                .components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if artist.isEmpty, let first = parts.first {
                artist = first
            }
            if album.isEmpty, parts.count >= 2 {
                let candidateAlbum = parts[1]
                if !isYearOrViewCountToken(candidateAlbum) {
                    album = candidateAlbum
                }
            }
        }

        let resolvedTime = timePair ?? progressBarFallback
        let videoId = extractYouTubeVideoID(from: pageURL)

        return BrowserDetectedTrack(
            title: cleanTitle,
            artist: artist,
            album: album,
            elapsedTime: resolvedTime?.elapsed,
            duration: resolvedTime?.duration,
            isPlaying: isPlaying,
            repeatMode: repeatMode,
            videoId: videoId,
            source: .youtubeMusic,
            bundleID: bundleID,
            appName: appName,
            fromAXPlayerBar: true
        )
    }

    private nonisolated static func interpretPlayPauseLabel(_ lowercasedLabel: String) -> Bool? {
        guard !lowercasedLabel.isEmpty else { return nil }
        // Cuando YouTube Music está reproduciendo, el botón ofrece "Pause" / "Pausar".
        let pauseWords = ["pause", "pausa", "pausar", "suspendre", "anhalten", "pausieren", "mettere in pausa", "一時停止", "일시중지", "暂停"]
        for word in pauseWords {
            if lowercasedLabel == word || lowercasedLabel.hasPrefix(word + " ") || lowercasedLabel.contains(" " + word) {
                return true
            }
        }
        // Cuando está en pausa, el botón ofrece "Play" / "Reproducir".
        let playWords = ["play", "reproducir", "reproduzir", "lire", "abspielen", "riproduci", "再生", "재생", "播放"]
        for word in playWords {
            if lowercasedLabel == word || lowercasedLabel.hasPrefix(word + " ") {
                return false
            }
        }
        return nil
    }

    private nonisolated static func parseSlashTimePair(_ text: String) -> (elapsed: TimeInterval, duration: TimeInterval)? {
        guard text.contains("/") else { return nil }
        let parts = text.split(separator: "/").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 2,
              let elapsed = parseColonDuration(parts[0]),
              let duration = parseColonDuration(parts[1]),
              duration > 0 else {
            return nil
        }
        return (elapsed, duration)
    }

    private nonisolated static func parseColonDuration(_ text: String) -> TimeInterval? {
        let comps = text.split(separator: ":").compactMap { Double($0) }
        switch comps.count {
        case 2:
            return comps[0] * 60.0 + comps[1]
        case 3:
            return comps[0] * 3600.0 + comps[1] * 60.0 + comps[2]
        default:
            return nil
        }
    }

    private nonisolated static func parseVerboseProgressDuration(_ text: String) -> (elapsed: TimeInterval, duration: TimeInterval)? {
        // Ej: "3 Minutes 14 Seconds of 6 Minutes 14 Seconds"
        let lower = text.lowercased()
        let splitTokens = [" of ", " de "]
        for token in splitTokens {
            if let range = lower.range(of: token) {
                let left = String(lower[..<range.lowerBound])
                let right = String(lower[range.upperBound...])
                if let e = parseWordsToSeconds(left), let d = parseWordsToSeconds(right), d > 0 {
                    return (e, d)
                }
            }
        }
        return nil
    }

    private nonisolated static func parseWordsToSeconds(_ fragment: String) -> TimeInterval? {
        let pattern = #"(\d+)\s*(hour|hora|minute|minuto|second|segundo)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let ns = fragment as NSString
        let matches = regex.matches(in: fragment, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return nil }
        var total: TimeInterval = 0
        for m in matches where m.numberOfRanges >= 3 {
            let val = Double(ns.substring(with: m.range(at: 1))) ?? 0
            let unit = ns.substring(with: m.range(at: 2)).lowercased()
            if unit.hasPrefix("h") { total += val * 3600 }
            else if unit.hasPrefix("m") { total += val * 60 }
            else { total += val }
        }
        return total
    }

    private nonisolated static func isYearOrViewCountToken(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count == 4, let year = Int(trimmed), (1900...2100).contains(year) {
            return true
        }
        let lower = trimmed.lowercased()
        return lower.contains("view") || lower.contains("vista") || lower.contains("play") || lower.contains("reproduccion")
    }

    private nonisolated static func extractYouTubeVideoID(from urlString: String) -> String? {
        guard !urlString.isEmpty,
              let comps = URLComponents(string: urlString),
              let host = comps.host?.lowercased(),
              host.contains("youtube.com") || host.contains("youtu.be") else {
            return nil
        }
        if let v = comps.queryItems?.first(where: { $0.name == "v" })?.value,
           v.count >= 8 && v.count <= 16 {
            return v
        }
        return nil
    }

    private nonisolated static func stripPlaybackDecorations(_ text: String) -> String {
        let removable: Set<Character> = [
            "▶", "▸", "►", "♫", "♪", "•", "·",
            "🔊", "🔉", "🔈", "🔇", "🎵", "🎶", "🎧", "⏯", "⏸"
        ]
        var scalars = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = scalars.first, removable.contains(first) || first.isWhitespace {
            scalars.removeFirst()
        }
        while let last = scalars.last, removable.contains(last) || last.isWhitespace {
            scalars.removeLast()
        }
        return scalars.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func readAXWindowTitles(pid: pid_t) -> [String] {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return []
        }
        var titles: [String] = []
        for win in windows {
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef) == .success,
               let title = titleRef as? String,
               !title.isEmpty {
                titles.append(title)
            }
        }
        return titles
    }

    private nonisolated static func parseYouTubeMusicWindowTitle(
        _ rawTitle: String,
        bundleID: String,
        appName: String,
        videoId: String? = nil
    ) -> BrowserDetectedTrack? {
        var cleaned = stripPlaybackDecorations(rawTitle)
        guard !cleaned.isEmpty else { return nil }

        let isYTMPWA = bundleID == ytmPWABundleID || appName.caseInsensitiveCompare("YouTube Music") == .orderedSame

        // Quitar sufijos de navegador (Chrome / Brave / Edge / Arc).
        let browserSuffixes = [
            " - Google Chrome",
            " – Google Chrome",
            " - Brave",
            " - Microsoft Edge",
            " - Arc",
            " - Safari"
        ]
        for suffix in browserSuffixes {
            if cleaned.hasSuffix(suffix) {
                cleaned = String(cleaned.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Verificar si corresponde a YouTube Music.
        let ytmSuffixes = [" - YouTube Music", " – YouTube Music", " | YouTube Music"]
        var matchedYTM = false
        for suffix in ytmSuffixes {
            if cleaned.hasSuffix(suffix) {
                cleaned = String(cleaned.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                matchedYTM = true
                break
            }
        }

        if !matchedYTM && !isYTMPWA {
            return nil
        }

        // Quitar símbolos y emojis de reproducción/altavoz al inicio y al final (`🔊`, `▶`, `♫`, etc.).
        cleaned = stripPlaybackDecorations(cleaned)
        guard !cleaned.isEmpty else { return nil }

        // Ignorar pantallas de navegación genéricas de YouTube Music (sin canción activa).
        let ignoredScreens: Set<String> = [
            "youtube music",
            "music",
            "home",
            "inicio",
            "explore",
            "explorar",
            "library",
            "biblioteca",
            "search",
            "buscar",
            "samples",
            "muestras",
            "upgrade",
            "actualizar"
        ]
        if ignoredScreens.contains(cleaned.lowercased()) {
            return nil
        }

        // Intentar separar `Artista - Canción` o `Canción • Artista`.
        let (title, artist) = splitSongAndArtist(from: cleaned)
        let finalTitle = stripPlaybackDecorations(title)
        guard !finalTitle.isEmpty, !ignoredScreens.contains(finalTitle.lowercased()) else { return nil }

        return BrowserDetectedTrack(
            title: finalTitle,
            artist: artist,
            album: "",
            elapsedTime: nil,
            duration: nil,
            isPlaying: nil,
            repeatMode: .off,
            videoId: videoId,
            source: .youtubeMusic,
            bundleID: bundleID,
            appName: isYTMPWA ? "YouTube Music" : appName,
            fromAXPlayerBar: false
        )
    }

    private nonisolated static func splitSongAndArtist(from text: String) -> (title: String, artist: String) {
        if let range = text.range(of: " • ") ?? text.range(of: " · ") {
            let left = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !left.isEmpty && !right.isEmpty {
                return (left, right)
            }
        }
        if let range = text.range(of: " - ") ?? text.range(of: " – ") {
            let left = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !left.isEmpty && !right.isEmpty {
                // En YouTube Music / YouTube web el patrón habitual con guion suele ser `Artista - Título`.
                return (right, left)
            }
        }
        return (text, "")
    }

    /// Comprueba sin mostrar alertas si la app ya tiene permiso de Automatización para `bundleID`.
    private nonisolated static func isAutomationAlreadyAuthorized(forBundleID bundleID: String) -> Bool {
        guard let descriptor = NSAppleEventDescriptor(bundleIdentifier: bundleID).aeDesc else {
            return false
        }
        var mutableDesc = descriptor.pointee
        let status = AEDeterminePermissionToAutomateTarget(
            &mutableDesc,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            false
        )
        return status == noErr
    }

    private nonisolated static func inspectAuthorizedBrowserForYouTubeMusic(app: RunningAppInfo) async -> BrowserDetectedTrack? {
        let script: String
        if app.bundleID == "com.apple.Safari" {
            script = """
            tell application id "com.apple.Safari"
                set sep to character id 31
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            set u to URL of t
                            if u contains "music.youtube.com" then
                                return (name of t) & sep & u
                            end if
                        end try
                    end repeat
                end repeat
            end tell
            return ""
            """
        } else {
            script = """
            tell application id "\(app.bundleID)"
                set sep to character id 31
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            set u to URL of t
                            if u contains "music.youtube.com" then
                                return (title of t) & sep & u
                            end if
                        end try
                    end repeat
                end repeat
            end tell
            return ""
            """
        }

        let res = await runAppleScript(script)
        guard let output = res.output, !output.isEmpty else { return nil }
        let parts = output.components(separatedBy: "\u{1F}")
        let rawTitle = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let tabURL = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        guard !rawTitle.isEmpty else { return nil }
        let videoId = extractYouTubeVideoID(from: tabURL)
        return parseYouTubeMusicWindowTitle(
            rawTitle.hasSuffix("YouTube Music") ? rawTitle : "\(rawTitle) - YouTube Music",
            bundleID: app.bundleID,
            appName: app.localizedName,
            videoId: videoId
        )
    }

    // MARK: - Clasificación de Fuentes, Caché y Utilidades

    private func cacheArtworkData(_ data: Data, forURL urlString: String) {
        if artworkURLCache.count > 80 {
            artworkURLCache.removeAll(keepingCapacity: true)
        }
        artworkURLCache[urlString] = data
    }

    private nonisolated static func classifySource(bundleID: String?, appName: String?) -> NotchMediaSource {
        let lowerID = (bundleID ?? "").lowercased()
        let lowerName = (appName ?? "").lowercased()

        if lowerID == ytmPWABundleID.lowercased() ||
            lowerID.contains("youtube-music") ||
            lowerID.contains("ytmdesktop") ||
            lowerID.contains("pear-desktop") ||
            lowerName.contains("youtube music") {
            return .youtubeMusic
        }
        if lowerID.contains("spotify") || lowerName.contains("spotify") {
            return .spotify
        }
        if lowerID == "com.apple.music" || lowerName == "music" || lowerName == "música" {
            return .appleMusic
        }
        if lowerID.contains("chrome") || lowerID.contains("safari") || lowerID.contains("brave") ||
            lowerID.contains("edge") || lowerID.contains("firefox") || lowerID.contains("thebrowser") {
            return .browser
        }
        return .other
    }

    private nonisolated static func parseLocaleDouble(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = Double(trimmed) { return direct }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    // MARK: - Ejecución Asincrónica Segura de AppleScript (Nunca Bloquea MainActor)

    private struct AppleScriptResult: Sendable {
        let output: String?
        let permissionDenied: Bool
    }

    private nonisolated static func runAppleScript(_ source: String, timeoutSeconds: Double = 2.0) async -> AppleScriptResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", source]

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: AppleScriptResult(output: nil, permissionDenied: false))
                    return
                }

                let deadline = Date().addingTimeInterval(timeoutSeconds)
                while process.isRunning && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.025)
                }

                if process.isRunning {
                    process.terminate()
                    continuation.resume(returning: AppleScriptResult(output: nil, permissionDenied: false))
                    return
                }

                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errText = String(data: errData, encoding: .utf8) ?? ""

                if errText.contains("-1743") || errText.localizedCaseInsensitiveContains("not authorized to send apple events") {
                    continuation.resume(returning: AppleScriptResult(output: nil, permissionDenied: true))
                    return
                }

                guard process.terminationStatus == 0 else {
                    continuation.resume(returning: AppleScriptResult(output: nil, permissionDenied: false))
                    return
                }

                let outText = String(data: outData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: AppleScriptResult(output: outText, permissionDenied: false))
            }
        }
    }

    // MARK: - Teclas Multimedia Universales de macOS (NX_KEYTYPE_*)

    private enum MediaKey {
        case playPause
        case next
        case previous

        var nxKeyType: Int32 {
            switch self {
            case .playPause: return 16 // NX_KEYTYPE_PLAY
            case .next: return 17      // NX_KEYTYPE_NEXT
            case .previous: return 18  // NX_KEYTYPE_PREVIOUS
            }
        }
    }

    @MainActor
    private static func sendMediaKey(_ key: MediaKey) {
        postMediaKeyEvent(keyType: key.nxKeyType, isKeyDown: true)
        postMediaKeyEvent(keyType: key.nxKeyType, isKeyDown: false)
    }

    @MainActor
    private static func postMediaKeyEvent(keyType: Int32, isKeyDown: Bool) {
        let modifierRaw: UInt = isKeyDown ? 0x0A00 : 0x0B00
        let data1 = Int((keyType << 16) | (isKeyDown ? 0x0A00 : 0x0B00))
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: modifierRaw),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else {
            return
        }
        event.cgEvent?.post(tap: .cghidEventTap)
    }

    // MARK: - Catálogo y Carátulas Programáticas del Modo Demo

    private struct DemoTrackDefinition {
        let id: String
        let title: String
        let artist: String
        let album: String
        let duration: TimeInterval
        let showcaseElapsed: TimeInterval
        let sourceApp: NotchMediaSource
        let primaryColor: NotchRGBColor
        let secondaryColor: NotchRGBColor
        let accentColor: NotchRGBColor
        let isLiked: Bool
    }

    private static let demoCatalog: [DemoTrackDefinition] = [
        DemoTrackDefinition(
            id: "demo-midnight-pulse",
            title: "Midnight Pulse",
            artist: "Nova & The Echoes",
            album: "Neon Horizons",
            duration: 214,
            showcaseElapsed: 46,
            sourceApp: .youtubeMusic,
            primaryColor: NotchRGBColor(r: 0.96, g: 0.22, b: 0.44),
            secondaryColor: NotchRGBColor(r: 0.36, g: 0.14, b: 0.72),
            accentColor: NotchRGBColor(r: 1.0, g: 0.56, b: 0.28),
            isLiked: true
        ),
        DemoTrackDefinition(
            id: "demo-velvet-skyline",
            title: "Velvet Skyline",
            artist: "Aurelia Sound",
            album: "Afterglow Sessions",
            duration: 198,
            showcaseElapsed: 39,
            sourceApp: .spotify,
            primaryColor: NotchRGBColor(r: 0.12, g: 0.78, b: 0.52),
            secondaryColor: NotchRGBColor(r: 0.08, g: 0.34, b: 0.68),
            accentColor: NotchRGBColor(r: 0.44, g: 0.96, b: 0.82),
            isLiked: true
        ),
        DemoTrackDefinition(
            id: "demo-golden-hour",
            title: "Golden Hour Drift",
            artist: "Solstice Collective",
            album: "Pacific Waves",
            duration: 236,
            showcaseElapsed: 55,
            sourceApp: .appleMusic,
            primaryColor: NotchRGBColor(r: 0.98, g: 0.48, b: 0.20),
            secondaryColor: NotchRGBColor(r: 0.68, g: 0.18, b: 0.52),
            accentColor: NotchRGBColor(r: 1.0, g: 0.82, b: 0.36),
            isLiked: false
        )
    ]

    private func applyDemoTrack(at index: Int, isPlaying: Bool, resetToShowcasePosition: Bool) {
        let def = Self.demoCatalog[index % Self.demoCatalog.count]
        let artworkData: Data
        if let cached = demoArtworkCache[def.id] {
            artworkData = cached
        } else {
            let rendered = Self.renderDemoArtworkPNG(for: def)
            demoArtworkCache[def.id] = rendered
            artworkData = rendered
        }

        let track = NotchTrackInfo(
            id: def.id,
            title: def.title,
            artist: def.artist,
            album: def.album,
            duration: def.duration,
            elapsedTime: resetToShowcasePosition ? def.showcaseElapsed : 0,
            isPlaying: isPlaying,
            playbackRate: isPlaying ? 1.0 : 0.0,
            artworkData: artworkData,
            dominantColor: def.primaryColor,
            sourceApp: def.sourceApp,
            sourceBundleID: nil,
            sourceAppName: def.sourceApp.displayName,
            supportsSeeking: true,
            supportsShuffleRepeat: true,
            isShuffling: false,
            repeatMode: .all,
            isLiked: def.isLiked,
            lastUpdatedAt: Date()
        )
        applyResolvedTrack(track, backend: .demo, forceUpdate: true)
    }

    private func startDemoAutoAdvanceLoop() {
        demoAutoAdvanceTask?.cancel()
        demoAutoAdvanceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, self.isDemoMode, let track = self.currentTrack, track.isPlaying else {
                    continue
                }
                let elapsed = track.interpolatedElapsedTime()
                if track.duration > 1 && elapsed >= track.duration - 0.5 {
                    self.demoTrackIndex = (self.demoTrackIndex + 1) % Self.demoCatalog.count
                    self.applyDemoTrack(at: self.demoTrackIndex, isPlaying: true, resetToShowcasePosition: false)
                }
            }
        }
    }

    /// Genera una carátula artística vectorial nítida (320×320 PNG) en memoria para que el modo Demo luzca impecable sin conexión.
    private static func renderDemoArtworkPNG(for def: DemoTrackDefinition) -> Data {
        let size = 320
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return Data()
        }

        // Fondo degradado diagonal profundo.
        let bgColors = [
            CGColor(red: def.secondaryColor.r * 0.45, green: def.secondaryColor.g * 0.45, blue: def.secondaryColor.b * 0.55, alpha: 1),
            CGColor(red: def.primaryColor.r * 0.85, green: def.primaryColor.g * 0.85, blue: def.primaryColor.b * 0.85, alpha: 1),
            CGColor(red: def.accentColor.r * 0.90, green: def.accentColor.g * 0.90, blue: def.accentColor.b * 0.90, alpha: 1)
        ] as CFArray
        if let grad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 0.58, 1.0]) {
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size, y: size),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        // Halo radial luminoso central.
        let glowColors = [
            CGColor(red: def.accentColor.r, green: def.accentColor.g, blue: def.accentColor.b, alpha: 0.72),
            CGColor(red: def.primaryColor.r, green: def.primaryColor.g, blue: def.primaryColor.b, alpha: 0.25),
            CGColor(red: 0, green: 0, blue: 0, alpha: 0)
        ] as CFArray
        if let radial = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 0.5, 1.0]) {
            ctx.drawRadialGradient(
                radial,
                startCenter: CGPoint(x: 205, y: 215),
                startRadius: 8,
                endCenter: CGPoint(x: 170, y: 170),
                endRadius: 190,
                options: []
            )
        }

        // Disco vinilo translúcido + anillos concéntricos minimalistas.
        let center = CGPoint(x: 160, y: 160)
        ctx.setFillColor(CGColor(red: 0.06, green: 0.06, blue: 0.09, alpha: 0.52))
        ctx.fillEllipse(in: CGRect(x: center.x - 102, y: center.y - 102, width: 204, height: 204))

        for radius in stride(from: 94.0, through: 44.0, by: -12.0) {
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.14))
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }

        // Etiqueta central luminosa del disco.
        ctx.setFillColor(CGColor(red: def.accentColor.r, green: def.accentColor.g, blue: def.accentColor.b, alpha: 0.92))
        ctx.fillEllipse(in: CGRect(x: center.x - 32, y: center.y - 32, width: 64, height: 64))
        ctx.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.11, alpha: 0.95))
        ctx.fillEllipse(in: CGRect(x: center.x - 10, y: center.y - 10, width: 20, height: 20))

        // Viñeta sutil para contraste elegante.
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
        ctx.setLineWidth(4)
        ctx.stroke(rect.insetBy(dx: 2, dy: 2))

        guard let cgImage = ctx.makeImage() else { return Data() }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }
}
