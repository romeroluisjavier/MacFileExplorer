import AppKit
import Foundation

// MARK: - MacFileExplorer Music Decoy Helper (0% CPU)
//
// Inspirado en MusicDecoy (FuzzyIdeas / The Low-Tech Guys):
// - Se empaqueta con CFBundleIdentifier = "com.apple.Music" y LSBackgroundOnly = true.
// - Cuando se presiona la tecla ▶ Play o se conectan auriculares Bluetooth sin ningún
//   reproductor activo, el daemon `rcd` de macOS detecta esta app ejecutándose en segundo
//   plano y le redirige el evento en lugar de abrir Apple Music.
// - Si el usuario eligió un reproductor alternativo (ej. YouTube Music app/PWA, YouTube Music Web
//   o Spotify), lo abre o trae al frente automáticamente; de lo contrario, absorbe el comando en
//   silencio con 0% CPU y sin robar jamás el foco.
// - Se cierra automáticamente si MacFileExplorer finaliza para no dejar procesos huérfanos.

private let kDecoyDefaultsSuite = "com.macfileexplorer.musicdecoy"
private let kMediaAppPathKey = "mediaAppPath"
private let kWebURLPrefix = "url:"
private let kParentBundleID = "com.macfileexplorer.app"
private let kConfigChangedNotification = Notification.Name("com.macfileexplorer.musicdecoy.configChanged")
private let kTerminateNotification = Notification.Name("com.macfileexplorer.musicdecoy.terminate")
private let kDidRedirectNotification = Notification.Name("com.macfileexplorer.musicdecoy.didRedirectPlay")

private func fourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for byte in string.utf8.prefix(4) {
        result = (result << 8) + OSType(byte)
    }
    return result
}

@MainActor
@objc(MusicDecoyApplication)
final class MusicDecoyApplication: NSApplication {
    private let kStoppedState: OSType = fourCharCode("kPSS")
    let startedAt: Date = Date()
    private var lastRedirectTriggeredAt: Date = .distantPast

    /// Propiedad AppleScript `player state` para compatibilidad con VLC / ScriptingBridge.
    @objc var playerState: NSNumber {
        NSNumber(value: kStoppedState)
    }

    func configuredMediaTarget() -> String? {
        let suite = UserDefaults(suiteName: kDecoyDefaultsSuite)
        let raw = suite?.string(forKey: kMediaAppPathKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    func launchConfiguredMediaApp(ignoreStartupGrace: Bool = false) {
        guard let target = configuredMediaTarget() else { return }

        let now = Date()
        if !ignoreStartupGrace && now.timeIntervalSince(startedAt) < 0.85 {
            return
        }
        // Evita doble disparo si macOS envía activación + AppleEvent en el mismo clic de ▶ Play
        guard now.timeIntervalSince(lastRedirectTriggeredAt) >= 1.2 else {
            return
        }
        lastRedirectTriggeredAt = now

        if target.hasPrefix(kWebURLPrefix) {
            let urlString = String(target.dropFirst(kWebURLPrefix.count))
            if let webURL = URL(string: urlString) {
                NSWorkspace.shared.open(webURL)
            }
        } else if FileManager.default.fileExists(atPath: target) {
            let appURL = URL(fileURLWithPath: target)
            // `openApplication` activa la app si ya está abierta (y reabre ventana en Chrome PWAs) o la lanza si estaba cerrada.
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
        }

        // Cede el foco inmediatamente para que el próximo ▶ Play vuelva a disparar activación limpiamente.
        NSApp.deactivate()
        DistributedNotificationCenter.default().postNotificationName(
            kDidRedirectNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    @objc(pause:)
    func pause(_ command: NSScriptCommand?) {}

    @objc(playpause:)
    func playpause(_ command: NSScriptCommand?) {
        launchConfiguredMediaApp(ignoreStartupGrace: true)
    }

    @objc(resume:)
    func resume(_ command: NSScriptCommand?) {}

    @objc(handleStopCommand:)
    func handleStopCommand(_ command: NSScriptCommand?) {}

    @objc func handlePlayPauseAppleEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        launchConfiguredMediaApp(ignoreStartupGrace: true)
    }
}

@MainActor
final class MusicDecoyDelegate: NSObject, NSApplicationDelegate {
    private var parentWatchObserver: NSObjectProtocol?
    private var configObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        updateActivationPolicy()

        let aeManager = NSAppleEventManager.shared()
        let hookClass = AEEventClass(fourCharCode("hook"))
        let appTarget = NSApplication.shared
        aeManager.setEventHandler(
            appTarget,
            andSelector: #selector(MusicDecoyApplication.handlePlayPauseAppleEvent(_:withReplyEvent:)),
            forEventClass: hookClass,
            andEventID: AEEventID(fourCharCode("PlPs"))
        )
        aeManager.setEventHandler(
            appTarget,
            andSelector: #selector(MusicDecoyApplication.handlePlayPauseAppleEvent(_:withReplyEvent:)),
            forEventClass: hookClass,
            andEventID: AEEventID(fourCharCode("Play"))
        )

        configObserver = DistributedNotificationCenter.default().addObserver(
            forName: kConfigChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateActivationPolicy()
            }
        }

        terminateObserver = DistributedNotificationCenter.default().addObserver(
            forName: kTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                NSApp.terminate(nil)
            }
        }

        // Si MacFileExplorer se cierra (normal o inesperadamente), el decoy termina al instante.
        parentWatchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            if app.bundleIdentifier == kParentBundleID || app.executableURL?.lastPathComponent == "MacFileExplorer" {
                let stillRunning = NSWorkspace.shared.runningApplications.contains {
                    !$0.isTerminated && ($0.bundleIdentifier == kParentBundleID || $0.executableURL?.lastPathComponent == "MacFileExplorer")
                }
                if !stillRunning {
                    Task { @MainActor in
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }

    func updateActivationPolicy() {
        let hasRedirectTarget = (NSApp as? MusicDecoyApplication)?.configuredMediaTarget() != nil
        if hasRedirectTarget {
            // Permite que `rcd` nos active al presionar ▶ Play para abrir el reproductor elegido por el usuario.
            NSApp.setActivationPolicy(.accessory)
        } else {
            // Prohibido activarse: absorbe ▶ Play en completo silencio sin robar jamás el foco.
            NSApp.setActivationPolicy(.prohibited)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Con LSBackgroundOnly = true esto solo se dispara cuando hay reproductor configurado y se presionó ▶ Play.
        (NSApp as? MusicDecoyApplication)?.launchConfiguredMediaApp()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        (NSApp as? MusicDecoyApplication)?.launchConfiguredMediaApp()
        return false
    }
}

let app = MusicDecoyApplication.shared
let delegate = MusicDecoyDelegate()
app.delegate = delegate
app.run()
