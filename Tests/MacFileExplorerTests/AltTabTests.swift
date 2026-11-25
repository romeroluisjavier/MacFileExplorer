import CoreGraphics
import Foundation
import XCTest
@testable import MacFileExplorer

final class AltTabTests: XCTestCase {

    private func makeWindow(
        id: String,
        windowID: CGWindowID,
        pid: pid_t,
        bundleID: String,
        appName: String,
        title: String,
        screenID: String = "main",
        isFocused: Bool = false,
        isMinimized: Bool = false,
        isAppHidden: Bool = false,
        spaceIndex: Int? = 1,
        isOnActiveSpace: Bool = true,
        lastFocusedOrder: UInt64 = 1
    ) -> TaskbarWindowItem {
        TaskbarWindowItem(
            id: id,
            windowID: windowID,
            pid: pid,
            bundleIdentifier: bundleID,
            appName: appName,
            appBundleURL: nil,
            title: title,
            frameAX: CGRect(x: 100, y: 100, width: 1000, height: 700),
            screenID: screenID,
            isFocused: isFocused,
            isMinimized: isMinimized,
            isAppHidden: isAppHidden,
            isFullScreen: false,
            badgeLabel: nil,
            spaceIndex: spaceIndex,
            isOnActiveSpace: isOnActiveSpace,
            lastFocusedOrder: lastFocusedOrder
        )
    }

    // MARK: - 1. Perfiles de Atajos y Coincidencia CGEvent

    func testShortcutProfileMatchesNormalReverseAndModifierRelease() throws {
        let defaults = AltTabShortcutProfile.makeDefaultProfiles()
        XCTAssertEqual(defaults.count, 2)

        let primary = defaults[0] // ⌥ ⇥
        XCTAssertEqual(primary.displayString, "⌥ ⇥")
        XCTAssertEqual(primary.triggerKeyCode, 48)

        let normalMatch = primary.matchesKeyDown(keyCode: 48, flags: [.maskAlternate])
        XCTAssertTrue(normalMatch.matched)
        XCTAssertFalse(normalMatch.isReverse)

        let reverseMatch = primary.matchesKeyDown(keyCode: 48, flags: [.maskAlternate, .maskShift])
        XCTAssertTrue(reverseMatch.matched)
        XCTAssertTrue(reverseMatch.isReverse)

        let wrongMod = primary.matchesKeyDown(keyCode: 48, flags: [.maskCommand])
        XCTAssertFalse(wrongMod.matched)

        XCTAssertFalse(primary.areHoldModifiersReleased(currentFlags: [.maskAlternate]))
        XCTAssertTrue(primary.areHoldModifiersReleased(currentFlags: []))

        // Codable round-trip
        let encoded = try JSONEncoder().encode(defaults)
        let decoded = try JSONDecoder().decode([AltTabShortcutProfile].self, from: encoded)
        XCTAssertEqual(decoded, defaults)
    }

    // MARK: - 2. Filtrado por App, Space, Monitor, Estado y Búsqueda

    func testLayoutEngineFilteringAcrossSpacesStatesAndSearch() {
        let w1 = makeWindow(id: "1-1", windowID: 1, pid: 10, bundleID: "com.google.Chrome", appName: "Google Chrome", title: "GitHub PR", screenID: "main", isFocused: true, spaceIndex: 1, isOnActiveSpace: true, lastFocusedOrder: 50)
        let w2 = makeWindow(id: "1-2", windowID: 2, pid: 10, bundleID: "com.google.Chrome", appName: "Google Chrome", title: "Documentación", screenID: "ext", spaceIndex: 2, isOnActiveSpace: false, lastFocusedOrder: 40)
        let w3 = makeWindow(id: "2-3", windowID: 3, pid: 20, bundleID: "net.whatsapp.WhatsApp", appName: "WhatsApp", title: "Chats", screenID: "main", isMinimized: true, spaceIndex: 1, isOnActiveSpace: true, lastFocusedOrder: 30)
        let w4 = makeWindow(id: "3-4", windowID: 4, pid: 30, bundleID: "com.tinyspeck.slackmacgap", appName: "Slack", title: "General", screenID: "main", isAppHidden: true, spaceIndex: 1, isOnActiveSpace: true, lastFocusedOrder: 20)

        let all = [w1, w2, w3, w4]
        var profile = AltTabShortcutProfile.makeDefaultProfiles()[0]

        // Todos incluidos
        let allVisible = AltTabLayoutEngine.filteredWindows(
            from: all,
            profile: profile,
            frontmostPID: 10,
            activeMouseScreenID: "main",
            mainScreenID: "main",
            excludedBundleIDs: [],
            searchQuery: ""
        )
        XCTAssertEqual(allVisible.map(\.id), ["1-1", "1-2", "2-3", "3-4"])

        // Solo Space actual -> excluye w2 (Space 2)
        profile.spacesScope = .activeSpaceOnly
        let activeSpaceOnly = AltTabLayoutEngine.filteredWindows(
            from: all,
            profile: profile,
            frontmostPID: 10,
            activeMouseScreenID: "main",
            mainScreenID: "main",
            excludedBundleIDs: [],
            searchQuery: ""
        )
        XCTAssertEqual(activeSpaceOnly.map(\.id), ["1-1", "2-3", "3-4"])

        // Solo app activa (Chrome) en todos los Spaces
        profile.spacesScope = .allSpaces
        profile.appsScope = .activeAppOnly
        let activeApp = AltTabLayoutEngine.filteredWindows(
            from: all,
            profile: profile,
            frontmostPID: 10,
            activeMouseScreenID: "main",
            mainScreenID: "main",
            excludedBundleIDs: [],
            searchQuery: ""
        )
        XCTAssertEqual(activeApp.map(\.id), ["1-1", "1-2"])

        // Búsqueda insensible a tildes ("documentacion" encuentra "Documentación")
        profile.appsScope = .allApps
        let searched = AltTabLayoutEngine.filteredWindows(
            from: all,
            profile: profile,
            frontmostPID: 10,
            activeMouseScreenID: "main",
            mainScreenID: "main",
            excludedBundleIDs: ["com.tinyspeck.slackmacgap"],
            searchQuery: "documentacion"
        )
        XCTAssertEqual(searched.map(\.id), ["1-2"])
    }

    // MARK: - 3. Selección Inicial MRU y Auto-Tamaño en los 3 Estilos

    func testInitialSelectionAndAutoSizingAcrossAllThreeStyles() {
        XCTAssertEqual(AltTabLayoutEngine.initialSelectionIndex(windowCount: 0, reverse: false), 0)
        XCTAssertEqual(AltTabLayoutEngine.initialSelectionIndex(windowCount: 1, reverse: false), 0)
        XCTAssertEqual(AltTabLayoutEngine.initialSelectionIndex(windowCount: 5, reverse: false), 1)
        XCTAssertEqual(AltTabLayoutEngine.initialSelectionIndex(windowCount: 5, reverse: true), 4)

        let screenSize = CGSize(width: 1512, height: 982)
        let maxAllowedW = screenSize.width * 0.84 + 1

        // Thumbnails: se achican automáticamente cuando suben las ventanas
        let thumbSmallCount = AltTabLayoutEngine.computeMetrics(
            windowCount: 3, style: .thumbnails, autoSize: true, manualThumbnailWidth: 220, screenSize: screenSize
        )
        let thumbManyCount = AltTabLayoutEngine.computeMetrics(
            windowCount: 16, style: .thumbnails, autoSize: true, manualThumbnailWidth: 220, screenSize: screenSize
        )
        XCTAssertGreaterThan(thumbSmallCount.cellWidth, thumbManyCount.cellWidth)
        XCTAssertLessThanOrEqual(thumbManyCount.panelWidth, maxAllowedW)

        // App Icons
        let icons = AltTabLayoutEngine.computeMetrics(
            windowCount: 8, style: .appIcons, autoSize: true, manualThumbnailWidth: 220, screenSize: screenSize
        )
        XCTAssertLessThanOrEqual(icons.panelWidth, maxAllowedW)
        XCTAssertGreaterThanOrEqual(icons.columns, 4)

        // Titles List: siempre 1 columna
        let list = AltTabLayoutEngine.computeMetrics(
            windowCount: 14, style: .titlesList, autoSize: true, manualThumbnailWidth: 220, screenSize: screenSize
        )
        XCTAssertEqual(list.columns, 1)
        XCTAssertEqual(list.rows, 14)
        XCTAssertLessThanOrEqual(list.panelHeight, screenSize.height * 0.78 + 1)
    }

    // MARK: - 4. Preferencias de Fábrica de AltTab

    @MainActor
    func testAltTabPreferencesFactoryDefaultsAndPresets() {
        let suiteName = "com.macfileexplorer.tests.alttab.\(UUID().uuidString)"
        guard let testDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        let prefs = AltTabPreferences(defaults: testDefaults)
        XCTAssertFalse(prefs.isEnabled)
        XCTAssertFalse(prefs.startEnabledByDefault)
        XCTAssertEqual(prefs.displayStyle, .thumbnails)
        XCTAssertTrue(prefs.autoSizeEnabled)
        XCTAssertTrue(prefs.showFullSizePreview)
        XCTAssertEqual(prefs.fullSizePreviewDelayMs, 120)
        XCTAssertEqual(prefs.primaryShortcutDisplay, "⌥ ⇥")

        prefs.setPrimaryShortcutPreset(command: true, option: false, control: false)
        XCTAssertEqual(prefs.primaryShortcutDisplay, "⌘ ⇥")

        prefs.addShortcutProfile()
        XCTAssertEqual(prefs.shortcutProfiles.count, 3)

        prefs.startEnabledByDefault = true
        let reloaded = AltTabPreferences(defaults: testDefaults)
        XCTAssertTrue(reloaded.startEnabledByDefault)
        XCTAssertTrue(reloaded.isEnabled)
        XCTAssertEqual(reloaded.primaryShortcutDisplay, "⌘ ⇥")
    }
}
