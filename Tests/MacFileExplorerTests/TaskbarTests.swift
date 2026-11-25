import CoreGraphics
import Foundation
import XCTest
@testable import MacFileExplorer

final class TaskbarTests: XCTestCase {

    // MARK: - Helpers

    private func makeWindow(
        id: String,
        windowID: CGWindowID,
        pid: pid_t,
        bundleID: String,
        appName: String,
        title: String,
        frameAX: CGRect = CGRect(x: 100, y: 100, width: 900, height: 600),
        screenID: String = "screen-main",
        isFocused: Bool = false,
        isMinimized: Bool = false,
        isFullScreen: Bool = false
    ) -> TaskbarWindowItem {
        TaskbarWindowItem(
            id: id,
            windowID: windowID,
            pid: pid,
            bundleIdentifier: bundleID,
            appName: appName,
            appBundleURL: nil,
            title: title,
            frameAX: frameAX,
            screenID: screenID,
            isFocused: isFocused,
            isMinimized: isMinimized,
            isAppHidden: false,
            isFullScreen: isFullScreen
        )
    }

    // MARK: - 1. Motor de Ordenamiento, Espacios y Agrupación

    func testWindowOrderEnginePreservesOrderAcrossSpaceSwitchesAndReordering() {
        var engine = TaskbarWindowOrderEngine()
        let w1 = makeWindow(id: "1-101", windowID: 101, pid: 1, bundleID: "com.apple.Safari", appName: "Safari", title: "Docs")
        let w2 = makeWindow(id: "2-201", windowID: 201, pid: 2, bundleID: "com.apple.Terminal", appName: "Terminal", title: "zsh")
        let w3 = makeWindow(id: "1-102", windowID: 102, pid: 1, bundleID: "com.apple.Safari", appName: "Safari", title: "GitHub")

        let initial = engine.orderedWindows(from: [w1, w2, w3], groupByApp: false, liveWindowIDsAcrossAllSpaces: ["1-101", "2-201", "1-102"])
        XCTAssertEqual(initial.map(\.id), ["1-101", "2-201", "1-102"])

        // Drag-and-drop manual: mover w3 al principio
        engine.moveWindow(sourceID: "1-102", toTargetID: "1-101", visibleWindows: initial, groupByApp: false)
        let afterDrag = engine.orderedWindows(from: [w1, w2, w3], groupByApp: false, liveWindowIDsAcrossAllSpaces: ["1-101", "2-201", "1-102"])
        XCTAssertEqual(afterDrag.map(\.id), ["1-102", "1-101", "2-201"])

        // Cambio a otro Space donde solo está w2, manteniendo vivos todos los IDs globales
        let otherSpace = engine.orderedWindows(from: [w2], groupByApp: false, liveWindowIDsAcrossAllSpaces: ["1-101", "2-201", "1-102"])
        XCTAssertEqual(otherSpace.map(\.id), ["2-201"])

        // Al volver al Space original, los botones conservan exactamente su posición previa (no saltan al final)
        let backToOriginal = engine.orderedWindows(from: [w1, w2, w3], groupByApp: false, liveWindowIDsAcrossAllSpaces: ["1-101", "2-201", "1-102"])
        XCTAssertEqual(backToOriginal.map(\.id), ["1-102", "1-101", "2-201"])
    }

    func testWindowOrderEngineGroupsWindowsByAppWhenEnabled() {
        var engine = TaskbarWindowOrderEngine()
        let safari1 = makeWindow(id: "1-10", windowID: 10, pid: 1, bundleID: "com.apple.Safari", appName: "Safari", title: "A")
        let term1 = makeWindow(id: "2-20", windowID: 20, pid: 2, bundleID: "com.apple.Terminal", appName: "Terminal", title: "B")
        let safari2 = makeWindow(id: "1-11", windowID: 11, pid: 1, bundleID: "com.apple.Safari", appName: "Safari", title: "C")

        _ = engine.orderedWindows(from: [safari1, term1], groupByApp: true, liveWindowIDsAcrossAllSpaces: ["1-10", "2-20"])
        let withSecondSafari = engine.orderedWindows(
            from: [safari1, term1, safari2],
            groupByApp: true,
            liveWindowIDsAcrossAllSpaces: ["1-10", "2-20", "1-11"]
        )

        XCTAssertEqual(withSecondSafari.map(\.id), ["1-10", "1-11", "2-20"])
    }

    // MARK: - 2. Geometría Multimonitor y Auto-Redimensionamiento

    func testCocoaToAXConversionAndMultiMonitorAssignment() {
        let primaryHeight: CGFloat = 1080
        let screenMain = TaskbarScreenDescriptor(
            id: "main",
            displayID: 1,
            localizedName: "Main",
            frameCocoa: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            frameAX: TaskbarGeometry.cocoaRectToAX(CGRect(x: 0, y: 0, width: 1920, height: 1080), primaryScreenHeight: primaryHeight),
            isMain: true
        )
        let screenRight = TaskbarScreenDescriptor(
            id: "right",
            displayID: 2,
            localizedName: "Right",
            frameCocoa: CGRect(x: 1920, y: 0, width: 2560, height: 1440),
            frameAX: TaskbarGeometry.cocoaRectToAX(CGRect(x: 1920, y: 0, width: 2560, height: 1440), primaryScreenHeight: primaryHeight),
            isMain: false
        )

        XCTAssertEqual(screenMain.frameAX, CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(screenRight.frameAX, CGRect(x: 1920, y: -360, width: 2560, height: 1440))

        // Ventana mayormente en el monitor derecho
        let rightWinFrame = CGRect(x: 1850, y: 50, width: 900, height: 600)
        XCTAssertEqual(TaskbarGeometry.assignScreenID(forWindowFrameAX: rightWinFrame, screens: [screenMain, screenRight]), "right")

        // Ventana claramente en el monitor principal
        let mainWinFrame = CGRect(x: 200, y: 100, width: 800, height: 600)
        XCTAssertEqual(TaskbarGeometry.assignScreenID(forWindowFrameAX: mainWinFrame, screens: [screenMain, screenRight]), "main")
    }

    func testOverlapResizerAdjustsOverlappingWindowAndIgnoresFullScreen() {
        let screenAX = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let barHeight: CGFloat = 42

        // Ventana que se extiende hasta y=1080 (tapa los 42px de la barra)
        let overlapping = CGRect(x: 100, y: 80, width: 1200, height: 1000)
        let adjusted = TaskbarGeometry.adjustedFrameAvoidingTaskbar(
            windowFrameAX: overlapping,
            screenFrameAX: screenAX,
            barHeight: barHeight,
            isFullScreen: false,
            isMinimized: false
        )
        XCTAssertNotNil(adjusted)
        XCTAssertEqual(adjusted?.maxY ?? 0, 1038, accuracy: 1.0)
        XCTAssertEqual(adjusted?.origin.y ?? 0, 80, accuracy: 1.0)

        // Ventana que ya respeta la barra -> no tocar
        let safeWindow = CGRect(x: 100, y: 80, width: 1200, height: 900)
        XCTAssertNil(TaskbarGeometry.adjustedFrameAvoidingTaskbar(
            windowFrameAX: safeWindow,
            screenFrameAX: screenAX,
            barHeight: barHeight,
            isFullScreen: false,
            isMinimized: false
        ))

        // Ventana en pantalla completa -> nunca tocar
        XCTAssertNil(TaskbarGeometry.adjustedFrameAvoidingTaskbar(
            windowFrameAX: screenAX,
            screenFrameAX: screenAX,
            barHeight: barHeight,
            isFullScreen: true,
            isMinimized: false
        ))
    }

    // MARK: - 3. Preferencias de Fábrica (Desactivada y Dock Intacto)

    @MainActor
    func testTaskbarPreferencesFactoryDefaultsAreDisabledWithUnchangedDock() {
        let suiteName = "com.macfileexplorer.tests.taskbar.\(UUID().uuidString)"
        guard let testDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        let prefs = TaskbarPreferences(defaults: testDefaults)
        XCTAssertFalse(prefs.isEnabled, "La barra de tareas debe iniciar desactivada por defecto")
        XCTAssertFalse(prefs.startEnabledByDefault, "El inicio por defecto debe venir apagado de fábrica")
        XCTAssertEqual(prefs.dockMode, .unchanged, "El Dock original de macOS debe quedar sin cambios por defecto")
        XCTAssertEqual(prefs.displayMode, .allDisplays)
        XCTAssertEqual(prefs.windowScopeMode, .perDisplay)
        XCTAssertTrue(prefs.syncWithActiveSpace)

        // Validar clamping de límites visuales
        prefs.barHeight = 10
        XCTAssertEqual(prefs.barHeight, TaskbarPreferences.minBarHeight)
        prefs.barHeight = 200
        XCTAssertEqual(prefs.barHeight, TaskbarPreferences.maxBarHeight)

        prefs.opacity = 0.05
        XCTAssertEqual(prefs.opacity, TaskbarPreferences.minOpacity)

        // Validar persistencia de startEnabledByDefault al reiniciar instancia
        prefs.startEnabledByDefault = true
        let reloaded = TaskbarPreferences(defaults: testDefaults)
        XCTAssertTrue(reloaded.startEnabledByDefault)
        XCTAssertTrue(reloaded.isEnabled)
    }

    // MARK: - 4. Filtrado del Menú Inicio

    func testStartMenuFilterMatchesDiacriticInsensitiveAndPrioritizesPrefix() {
        let apps = [
            TaskbarInstalledApp(bundleIdentifier: "com.apple.Music", name: "Música", bundleURL: URL(fileURLWithPath: "/System/Applications/Music.app")),
            TaskbarInstalledApp(bundleIdentifier: "com.example.Audio", name: "Editor de Musica Pro", bundleURL: URL(fileURLWithPath: "/Applications/Editor.app")),
            TaskbarInstalledApp(bundleIdentifier: "com.apple.Safari", name: "Safari", bundleURL: URL(fileURLWithPath: "/Applications/Safari.app"))
        ]

        let results = TaskbarStartMenuFilter.filter(apps: apps, query: "musica")
        XCTAssertEqual(results.map(\.name), ["Música", "Editor de Musica Pro"])
        XCTAssertEqual(apps[0].sectionLetter, "M")

        // Validar limpieza de marcas Unicode invisibles (como `\u{200E}` en WhatsApp) y detección PWA
        let whatsapp = TaskbarInstalledApp(
            bundleIdentifier: "net.whatsapp.WhatsApp",
            name: "\u{200E}WhatsApp",
            bundleURL: URL(fileURLWithPath: "/Applications/WhatsApp.app")
        )
        XCTAssertEqual(TaskbarStringSanitizer.sanitizeDisplayName(whatsapp.name), "WhatsApp")
        XCTAssertEqual(whatsapp.sectionLetter, "W")
        XCTAssertEqual(TaskbarStartMenuFilter.filter(apps: [whatsapp], query: "whatsapp").count, 1)
        XCTAssertTrue(TaskbarStringSanitizer.isWebAppPWA(
            bundleIdentifier: "com.google.Chrome.app.ikhbelfjcfmehjillhgijieickendaem",
            bundleURL: URL(fileURLWithPath: "/Users/test/Applications/Chrome Apps.localized/Jira.app")
        ))
        XCTAssertFalse(TaskbarStringSanitizer.isWebAppPWA(
            bundleIdentifier: "com.apple.finder",
            bundleURL: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        ))
    }

    // MARK: - 5. Respaldo y Restauración Segura del Dock

    func testDockManagerOperationsAndEmergencyFactoryRestore() throws {
        let backup = TaskbarDockBackupSnapshot(
            orientation: "bottom",
            autohide: false,
            autohideDelay: nil,
            autohideTimeModifier: nil
        )

        // Codable round-trip
        let data = try JSONEncoder().encode(backup)
        let decoded = try JSONDecoder().decode(TaskbarDockBackupSnapshot.self, from: data)
        XCTAssertEqual(decoded.orientation, "bottom")
        XCTAssertEqual(decoded.autohide, false)
        XCTAssertNil(decoded.autohideDelay)

        // Modo unchanged nunca ejecuta operaciones sobre com.apple.dock
        XCTAssertTrue(TaskbarDockManager.operations(for: .unchanged, backup: backup).isEmpty)

        // Modo fullyHidden escribe autohide + delay extremo
        let hiddenOps = TaskbarDockManager.operations(for: .fullyHidden, backup: backup)
        XCTAssertTrue(hiddenOps.contains(.writeBool(key: "autohide", value: true)))
        XCTAssertTrue(hiddenOps.contains(.writeFloat(key: "autohide-delay", value: 1000.0)))

        // Restaurar desde backup devuelve exactamente orientation=bottom, autohide=false y elimina keys artificiales
        let restoreOps = TaskbarDockManager.restoreOperations(from: backup)
        XCTAssertEqual(restoreOps, [
            .writeString(key: "orientation", value: "bottom"),
            .writeBool(key: "autohide", value: false),
            .deleteKey(key: "autohide-delay"),
            .deleteKey(key: "autohide-time-modifier")
        ])

        // Restauración de emergencia a valores de fábrica
        XCTAssertEqual(TaskbarDockManager.factoryDefaultMacOSDockOperations(), [
            .writeString(key: "orientation", value: "bottom"),
            .writeBool(key: "autohide", value: false),
            .deleteKey(key: "autohide-delay"),
            .deleteKey(key: "autohide-time-modifier")
        ])
    }

    // MARK: - 6. Deduplicación de Pestañas Nativas Minimizadas (Fork, Finder, Terminal, etc.)

    func testTabGroupDeduplicatorCollapsesMinimizedTabsToActiveTabAndKeepsSeparateWindows() {
        let sharedFrame = CGRect(x: 0, y: 33, width: 1512, height: 898)

        // Escenario A: Fork minimizado con 5 pestañas donde solo la activa tiene Space asignado (`hasSpaceMembership == true`)
        let forkActiveTab = TaskbarWindowItem(id: "80129-6956", windowID: 6956, pid: 80129, bundleIdentifier: "com.DanPristupov.Fork", appName: "Fork", appBundleURL: nil, title: "shrpa_seller", frameAX: sharedFrame, screenID: "main", isFocused: false, isMinimized: true, isAppHidden: false, isFullScreen: false, spaceIndex: 1, isOnActiveSpace: true, hasSpaceMembership: true, lastFocusedOrder: 90)
        let forkTab2 = TaskbarWindowItem(id: "80129-6958", windowID: 6958, pid: 80129, bundleIdentifier: "com.DanPristupov.Fork", appName: "Fork", appBundleURL: nil, title: "shrpa_logistic", frameAX: sharedFrame, screenID: "main", isFocused: false, isMinimized: true, isAppHidden: false, isFullScreen: false, spaceIndex: nil, isOnActiveSpace: false, hasSpaceMembership: false, lastFocusedOrder: 10)
        let forkTab3 = TaskbarWindowItem(id: "80129-6959", windowID: 6959, pid: 80129, bundleIdentifier: "com.DanPristupov.Fork", appName: "Fork", appBundleURL: nil, title: "e-middleware", frameAX: sharedFrame, screenID: "main", isFocused: false, isMinimized: true, isAppHidden: false, isFullScreen: false, spaceIndex: nil, isOnActiveSpace: false, hasSpaceMembership: false, lastFocusedOrder: 10)

        let dedupA = TaskbarTabGroupDeduplicator.deduplicate([forkTab2, forkActiveTab, forkTab3])
        XCTAssertEqual(dedupA.map(\.id), ["80129-6956"])

        // Escenario B: Todas las pestañas minimizadas reportan `hasSpaceMembership == false` -> elige la de mayor MRU (`shrpa_seller`)
        let forkNoSpaceActive = TaskbarWindowItem(id: "80129-6956", windowID: 6956, pid: 80129, bundleIdentifier: "com.DanPristupov.Fork", appName: "Fork", appBundleURL: nil, title: "shrpa_seller", frameAX: sharedFrame, screenID: "main", isFocused: false, isMinimized: true, isAppHidden: false, isFullScreen: false, spaceIndex: nil, isOnActiveSpace: false, hasSpaceMembership: false, lastFocusedOrder: 95)
        let dedupB = TaskbarTabGroupDeduplicator.deduplicate([forkTab2, forkNoSpaceActive, forkTab3])
        XCTAssertEqual(dedupB.map(\.id), ["80129-6956"])

        // Escenario C: Dos ventanas abiertas reales de Chrome apiladas en el mismo frame (ambas con Space) -> se conservan las 2
        let chrome1 = TaskbarWindowItem(id: "483-3279", windowID: 3279, pid: 483, bundleIdentifier: "com.google.Chrome", appName: "Google Chrome", appBundleURL: nil, title: "Win 1", frameAX: sharedFrame, screenID: "main", isFocused: true, isMinimized: false, isAppHidden: false, isFullScreen: false, spaceIndex: 1, isOnActiveSpace: true, hasSpaceMembership: true, lastFocusedOrder: 100)
        let chrome2 = TaskbarWindowItem(id: "483-3280", windowID: 3280, pid: 483, bundleIdentifier: "com.google.Chrome", appName: "Google Chrome", appBundleURL: nil, title: "Win 2", frameAX: sharedFrame, screenID: "main", isFocused: false, isMinimized: false, isAppHidden: false, isFullScreen: false, spaceIndex: 1, isOnActiveSpace: true, hasSpaceMembership: true, lastFocusedOrder: 80)
        let dedupC = TaskbarTabGroupDeduplicator.deduplicate([chrome1, chrome2])
        XCTAssertEqual(dedupC.map(\.id), ["483-3279", "483-3280"])
    }

    // MARK: - 7. 8 Animaciones del Menú Inicio y Duración / Modo Instantáneo 0 ms

    @MainActor
    func testStartMenuAnimationsAndInstantZeroDelayPreferences() {
        let all = TaskbarStartMenuAnimation.allCases
        XCTAssertEqual(all.count, 8, "Deben existir exactamente 8 animaciones del Menú Inicio")
        XCTAssertEqual(all.filter { $0.category == .classic }.count, 4, "4 estilos clásicos iguales a la barra")
        XCTAssertEqual(all.filter { $0.category == .professional }.count, 2, "2 estilos profesionales")
        XCTAssertEqual(all.filter { $0.category == .fun }.count, 2, "2 estilos divertidos")

        let loc = LocalizationManager.shared
        let originalLang = loc.language
        defer { loc.language = originalLang }

        for style in all {
            // Al completar la animación (progress = 1.0), toda animación debe asentarse exactamente en .identity
            let finalFrame = style.evaluate(progress: 1.0)
            XCTAssertEqual(finalFrame, .identity, "La animación \(style.rawValue) debe finalizar en .identity")

            // En el inicio y en mitad del despliegue todos los valores deben ser finitos y no triviales
            let startFrame = style.evaluate(progress: 0.0)
            let midFrame = style.evaluate(progress: 0.45)
            XCTAssertNotEqual(startFrame, .identity, "La animación \(style.rawValue) debe arrancar distinta a .identity")
            XCTAssertTrue(midFrame.opacity.isFinite && midFrame.scaleX.isFinite && midFrame.scaleY.isFinite)
            XCTAssertTrue(midFrame.offsetX.isFinite && midFrame.offsetY.isFinite && midFrame.rotationX.isFinite && midFrame.rotationZ.isFinite)
            XCTAssertTrue(midFrame.blurRadius.isFinite && midFrame.clipTopFraction.isFinite)

            // Localización ES y EN no vacía
            loc.language = .spanish
            XCTAssertFalse(style.localizedTitle(using: loc).isEmpty)
            XCTAssertFalse(style.localizedSubtitle(using: loc).isEmpty)
            loc.language = .english
            XCTAssertFalse(style.localizedTitle(using: loc).isEmpty)
            XCTAssertFalse(style.localizedSubtitle(using: loc).isEmpty)
        }

        // Rasgos distintivos de los estilos nuevos (2 profesionales + 2 divertidos + 3D)
        XCTAssertGreaterThan(TaskbarStartMenuAnimation.executiveCurtain.evaluate(progress: 0.0).clipTopFraction, 0.8)
        let spotlightStart = TaskbarStartMenuAnimation.spotlightFocus.evaluate(progress: 0.0)
        XCTAssertGreaterThan(spotlightStart.blurRadius, 4.0)
        XCTAssertGreaterThan(spotlightStart.scaleX, 1.03)
        XCTAssertGreaterThan(abs(TaskbarStartMenuAnimation.twirlGenie.evaluate(progress: 0.25).rotationZ), 1.0)
        XCTAssertGreaterThan(abs(TaskbarStartMenuAnimation.flipReveal.evaluate(progress: 0.0).rotationX), 15.0)
        let jellyMid = TaskbarStartMenuAnimation.jellyBounce.evaluate(progress: 0.35)
        XCTAssertNotEqual(jellyMid.scaleX, jellyMid.scaleY, "Gelatina debe aplicar squash & stretch asimétrico")

        // Persistencia aislada, clamping y soporte real de 0 ms instantáneo
        let suiteName = "com.macfileexplorer.tests.startmenu.\(UUID().uuidString)"
        guard let testDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        let prefs = TaskbarPreferences(defaults: testDefaults)
        XCTAssertEqual(prefs.startMenuAnimation, .riseFromBar)
        XCTAssertEqual(prefs.startMenuAnimationDuration, TaskbarPreferences.defaultStartMenuAnimationDuration, accuracy: 0.0001)

        // Elegir 0 ms (instantáneo) debe guardarse exactamente en 0.0 y persistir tras recargar
        prefs.startMenuAnimation = .twirlGenie
        prefs.startMenuAnimationDuration = 0.0
        XCTAssertEqual(prefs.startMenuAnimationDuration, 0.0, accuracy: 0.0001)

        let reloadedInstant = TaskbarPreferences(defaults: testDefaults)
        XCTAssertEqual(reloadedInstant.startMenuAnimation, .twirlGenie)
        XCTAssertEqual(reloadedInstant.startMenuAnimationDuration, 0.0, accuracy: 0.0001, "0 ms instantáneo debe persistir sin volver al default")

        // Clamping de extremos
        reloadedInstant.startMenuAnimationDuration = -0.25
        XCTAssertEqual(reloadedInstant.startMenuAnimationDuration, 0.0, accuracy: 0.0001)
        reloadedInstant.startMenuAnimationDuration = 2.0
        XCTAssertEqual(reloadedInstant.startMenuAnimationDuration, TaskbarPreferences.maxStartMenuAnimationDuration, accuracy: 0.0001)

        // Restablecer valores visuales vuelve al default
        reloadedInstant.resetVisualDefaults()
        XCTAssertEqual(reloadedInstant.startMenuAnimation, .riseFromBar)
        XCTAssertEqual(reloadedInstant.startMenuAnimationDuration, TaskbarPreferences.defaultStartMenuAnimationDuration, accuracy: 0.0001)
    }
}
