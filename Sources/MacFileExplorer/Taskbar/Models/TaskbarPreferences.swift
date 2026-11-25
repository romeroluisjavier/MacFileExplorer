import AppKit
import Foundation
import Observation

/// Preferencias reactivas y persistentes de la Barra de tareas estilo Windows integrada en `MacFileExplorer`.
///
/// Reglas de seguridad y valores de fábrica:
/// - Arranca completamente desactivada por defecto (`isEnabled = false`, `startEnabledByDefault = false`).
/// - El Dock original de macOS permanece activo y sin cambios por defecto (`dockMode = .unchanged`).
/// - Permite elegir desde Configuración si debe arrancar activada o desactivada por defecto al iniciar `MacFileExplorer`.
@MainActor
@Observable
public final class TaskbarPreferences {

    public static let shared = TaskbarPreferences()

    public static let minBarHeight: Double = 32
    public static let maxBarHeight: Double = 64
    public static let defaultBarHeight: Double = 42

    public static let minFontSize: Double = 10
    public static let maxFontSize: Double = 18
    public static let defaultFontSize: Double = 12.5

    public static let minOpacity: Double = 0.25
    public static let maxOpacity: Double = 1.0
    public static let defaultOpacity: Double = 0.80

    public static let minHoverDelay: Double = 0.10
    public static let maxHoverDelay: Double = 1.00
    public static let defaultHoverDelay: Double = 0.30

    public static let defaultExcludedSystemBundleIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.WindowManager",
        "com.apple.SystemUIServer",
        "com.apple.loginwindow",
        "com.apple.screencaptureui",
        "com.apple.PressAndHold",
        "com.apple.inputmethod.EmojiFunctionRowItem"
    ]

    private let defaults: UserDefaults
    private var isBootstrapping = false

    private enum Keys {
        static let startEnabledByDefault = "com.macfileexplorer.taskbar.startEnabledByDefault"
        static let hasCompletedSetup = "com.macfileexplorer.taskbar.hasCompletedSetup"
        static let barHeight = "com.macfileexplorer.taskbar.barHeight"
        static let fontSize = "com.macfileexplorer.taskbar.fontSize"
        static let opacity = "com.macfileexplorer.taskbar.opacity"
        static let themeMode = "com.macfileexplorer.taskbar.themeMode"
        static let startButtonIcon = "com.macfileexplorer.taskbar.startButtonIcon"
        static let alignment = "com.macfileexplorer.taskbar.alignment"
        static let showWindowTitles = "com.macfileexplorer.taskbar.showWindowTitles"
        static let showMinimizedIndicator = "com.macfileexplorer.taskbar.showMinimizedIndicator"
        static let showNotificationBadges = "com.macfileexplorer.taskbar.showNotificationBadges"
        static let notificationAnimation = "com.macfileexplorer.taskbar.notificationAnimation"
        static let notificationAnimationCadence = "com.macfileexplorer.taskbar.notificationAnimationCadence"
        static let groupWindowsByApp = "com.macfileexplorer.taskbar.groupWindowsByApp"
        static let showWindowlessRunningApps = "com.macfileexplorer.taskbar.showWindowlessRunningApps"
        static let showHoverPreviews = "com.macfileexplorer.taskbar.showHoverPreviews"
        static let hoverPreviewDelay = "com.macfileexplorer.taskbar.hoverPreviewDelay"
        static let thumbnailSize = "com.macfileexplorer.taskbar.thumbnailSize"
        static let hoverPreviewAnimation = "com.macfileexplorer.taskbar.hoverPreviewAnimation"
        static let showTitleInThumbnail = "com.macfileexplorer.taskbar.showTitleInThumbnail"
        static let clickFocusedAction = "com.macfileexplorer.taskbar.clickFocusedAction"
        static let middleClickClosesWindow = "com.macfileexplorer.taskbar.middleClickClosesWindow"
        static let autoResizeOverlappingWindows = "com.macfileexplorer.taskbar.autoResizeOverlappingWindows"
        static let displayMode = "com.macfileexplorer.taskbar.displayMode"
        static let windowScopeMode = "com.macfileexplorer.taskbar.windowScopeMode"
        static let syncWithActiveSpace = "com.macfileexplorer.taskbar.syncWithActiveSpace"
        static let dockMode = "com.macfileexplorer.taskbar.dockMode"
        static let dockBackupSnapshot = "com.macfileexplorer.taskbar.dockBackupSnapshot"
        static let pinnedApps = "com.macfileexplorer.taskbar.pinnedApps"
        static let excludedBundleIDs = "com.macfileexplorer.taskbar.excludedBundleIDs"
        static let hiddenDisplayIDs = "com.macfileexplorer.taskbar.hiddenDisplayIDs"
        static let recentAppPaths = "com.macfileexplorer.taskbar.recentAppPaths"
    }

    /// Callback invocado al cambiar estado o preferencias (conectado por `TaskbarManager`).
    public var onEnabledChanged: ((Bool) -> Void)?
    public var onAppearanceOrLayoutChanged: (() -> Void)?
    public var onWindowFilteringChanged: (() -> Void)?

    // MARK: - Estado Principal

    /// Estado activo de la barra de tareas en la sesión actual (arranca igual a `startEnabledByDefault`, que es `false` de fábrica).
    public var isEnabled: Bool {
        didSet {
            guard !isBootstrapping, isEnabled != oldValue else { return }
            onEnabledChanged?(isEnabled)
            StatusBarManager.shared.refreshTooltipAndMenu()
        }
    }

    /// Define si la barra de tareas debe arrancar activada o desactivada por defecto al abrir `MacFileExplorer`.
    /// De fábrica es `false` (todo desactivado y Dock original intacto).
    public var startEnabledByDefault: Bool {
        didSet {
            guard !isBootstrapping, startEnabledByDefault != oldValue else { return }
            defaults.set(startEnabledByDefault, forKey: Keys.startEnabledByDefault)
        }
    }

    /// Indica si el usuario ya revisó el asistente inicial de permisos.
    public var hasCompletedSetup: Bool {
        didSet {
            guard !isBootstrapping, hasCompletedSetup != oldValue else { return }
            defaults.set(hasCompletedSetup, forKey: Keys.hasCompletedSetup)
        }
    }

    // MARK: - Apariencia Visual

    public var barHeight: Double {
        didSet {
            let clamped = min(max(barHeight, Self.minBarHeight), Self.maxBarHeight)
            if clamped != barHeight {
                barHeight = clamped
                return
            }
            guard !isBootstrapping, clamped != oldValue else { return }
            defaults.set(clamped, forKey: Keys.barHeight)
            onAppearanceOrLayoutChanged?()
        }
    }

    public var fontSize: Double {
        didSet {
            let clamped = min(max(fontSize, Self.minFontSize), Self.maxFontSize)
            if clamped != fontSize {
                fontSize = clamped
                return
            }
            guard !isBootstrapping, clamped != oldValue else { return }
            defaults.set(clamped, forKey: Keys.fontSize)
            onAppearanceOrLayoutChanged?()
        }
    }

    public var opacity: Double {
        didSet {
            let clamped = min(max(opacity, Self.minOpacity), Self.maxOpacity)
            if clamped != opacity {
                opacity = clamped
                return
            }
            guard !isBootstrapping, clamped != oldValue else { return }
            defaults.set(clamped, forKey: Keys.opacity)
            onAppearanceOrLayoutChanged?()
        }
    }

    public var themeMode: TaskbarThemeMode {
        didSet {
            guard !isBootstrapping, themeMode != oldValue else { return }
            defaults.set(themeMode.rawValue, forKey: Keys.themeMode)
            onAppearanceOrLayoutChanged?()
        }
    }

    public var startButtonIcon: TaskbarStartButtonIcon {
        didSet {
            guard !isBootstrapping, startButtonIcon != oldValue else { return }
            defaults.set(startButtonIcon.rawValue, forKey: Keys.startButtonIcon)
            onAppearanceOrLayoutChanged?()
        }
    }

    public var alignment: TaskbarAlignment {
        didSet {
            guard !isBootstrapping, alignment != oldValue else { return }
            defaults.set(alignment.rawValue, forKey: Keys.alignment)
            onAppearanceOrLayoutChanged?()
        }
    }

    public var showWindowTitles: Bool {
        didSet {
            guard !isBootstrapping, showWindowTitles != oldValue else { return }
            defaults.set(showWindowTitles, forKey: Keys.showWindowTitles)
            onAppearanceOrLayoutChanged?()
        }
    }

    public var showMinimizedIndicator: Bool {
        didSet {
            guard !isBootstrapping, showMinimizedIndicator != oldValue else { return }
            defaults.set(showMinimizedIndicator, forKey: Keys.showMinimizedIndicator)
            onAppearanceOrLayoutChanged?()
        }
    }

    public var showNotificationBadges: Bool {
        didSet {
            guard !isBootstrapping, showNotificationBadges != oldValue else { return }
            defaults.set(showNotificationBadges, forKey: Keys.showNotificationBadges)
            onWindowFilteringChanged?()
        }
    }

    public var notificationAnimation: TaskbarNotificationAnimation {
        didSet {
            guard !isBootstrapping, notificationAnimation != oldValue else { return }
            defaults.set(notificationAnimation.rawValue, forKey: Keys.notificationAnimation)
            onAppearanceOrLayoutChanged?()
        }
    }

    public var notificationAnimationCadence: TaskbarNotificationAnimationCadence {
        didSet {
            guard !isBootstrapping, notificationAnimationCadence != oldValue else { return }
            defaults.set(notificationAnimationCadence.rawValue, forKey: Keys.notificationAnimationCadence)
            onAppearanceOrLayoutChanged?()
        }
    }

    // MARK: - Comportamiento y Vista Previa

    public var groupWindowsByApp: Bool {
        didSet {
            guard !isBootstrapping, groupWindowsByApp != oldValue else { return }
            defaults.set(groupWindowsByApp, forKey: Keys.groupWindowsByApp)
            onWindowFilteringChanged?()
        }
    }

    /// Muestra en la barra las apps abiertas en macOS que no tienen ventanas abiertas (ej. VS Code tras cerrar la última ventana),
    /// igual que el Dock original de macOS (salvo Finder y las apps que ya estén fijadas).
    public var showWindowlessRunningApps: Bool {
        didSet {
            guard !isBootstrapping, showWindowlessRunningApps != oldValue else { return }
            defaults.set(showWindowlessRunningApps, forKey: Keys.showWindowlessRunningApps)
            onWindowFilteringChanged?()
        }
    }

    public var showHoverPreviews: Bool {
        didSet {
            guard !isBootstrapping, showHoverPreviews != oldValue else { return }
            defaults.set(showHoverPreviews, forKey: Keys.showHoverPreviews)
        }
    }

    public var hoverPreviewDelay: Double {
        didSet {
            let clamped = min(max(hoverPreviewDelay, Self.minHoverDelay), Self.maxHoverDelay)
            if clamped != hoverPreviewDelay {
                hoverPreviewDelay = clamped
                return
            }
            guard !isBootstrapping, clamped != oldValue else { return }
            defaults.set(clamped, forKey: Keys.hoverPreviewDelay)
        }
    }

    public var thumbnailSize: TaskbarThumbnailSize {
        didSet {
            guard !isBootstrapping, thumbnailSize != oldValue else { return }
            defaults.set(thumbnailSize.rawValue, forKey: Keys.thumbnailSize)
        }
    }

    public var hoverPreviewAnimation: TaskbarHoverPreviewAnimation {
        didSet {
            guard !isBootstrapping, hoverPreviewAnimation != oldValue else { return }
            defaults.set(hoverPreviewAnimation.rawValue, forKey: Keys.hoverPreviewAnimation)
        }
    }

    public var showTitleInThumbnail: Bool {
        didSet {
            guard !isBootstrapping, showTitleInThumbnail != oldValue else { return }
            defaults.set(showTitleInThumbnail, forKey: Keys.showTitleInThumbnail)
        }
    }

    public var clickFocusedAction: TaskbarFocusedClickAction {
        didSet {
            guard !isBootstrapping, clickFocusedAction != oldValue else { return }
            defaults.set(clickFocusedAction.rawValue, forKey: Keys.clickFocusedAction)
        }
    }

    public var middleClickClosesWindow: Bool {
        didSet {
            guard !isBootstrapping, middleClickClosesWindow != oldValue else { return }
            defaults.set(middleClickClosesWindow, forKey: Keys.middleClickClosesWindow)
        }
    }

    public var autoResizeOverlappingWindows: Bool {
        didSet {
            guard !isBootstrapping, autoResizeOverlappingWindows != oldValue else { return }
            defaults.set(autoResizeOverlappingWindows, forKey: Keys.autoResizeOverlappingWindows)
            onWindowFilteringChanged?()
        }
    }

    // MARK: - Monitores, Espacios y Dock

    public var displayMode: TaskbarDisplayMode {
        didSet {
            guard !isBootstrapping, displayMode != oldValue else { return }
            defaults.set(displayMode.rawValue, forKey: Keys.displayMode)
            onAppearanceOrLayoutChanged?()
        }
    }

    public var windowScopeMode: TaskbarWindowScopeMode {
        didSet {
            guard !isBootstrapping, windowScopeMode != oldValue else { return }
            defaults.set(windowScopeMode.rawValue, forKey: Keys.windowScopeMode)
            onWindowFilteringChanged?()
        }
    }

    public var syncWithActiveSpace: Bool {
        didSet {
            guard !isBootstrapping, syncWithActiveSpace != oldValue else { return }
            defaults.set(syncWithActiveSpace, forKey: Keys.syncWithActiveSpace)
            onWindowFilteringChanged?()
        }
    }

    /// Modo de gestión del Dock de macOS. Siempre `.unchanged` por defecto hasta que el usuario lo cambie explícitamente.
    public var dockMode: TaskbarDockMode {
        didSet {
            guard !isBootstrapping, dockMode != oldValue else { return }
            defaults.set(dockMode.rawValue, forKey: Keys.dockMode)
        }
    }

    // MARK: - Colecciones Persistentes

    public var pinnedApps: [TaskbarPinnedApp] {
        didSet {
            guard !isBootstrapping, pinnedApps != oldValue else { return }
            if let data = try? JSONEncoder().encode(pinnedApps) {
                defaults.set(data, forKey: Keys.pinnedApps)
            }
            onAppearanceOrLayoutChanged?()
        }
    }

    public var excludedBundleIDs: [String] {
        didSet {
            guard !isBootstrapping, excludedBundleIDs != oldValue else { return }
            defaults.set(excludedBundleIDs, forKey: Keys.excludedBundleIDs)
            onWindowFilteringChanged?()
        }
    }

    public var hiddenDisplayIDs: Set<String> {
        didSet {
            guard !isBootstrapping, hiddenDisplayIDs != oldValue else { return }
            defaults.set(Array(hiddenDisplayIDs), forKey: Keys.hiddenDisplayIDs)
            onAppearanceOrLayoutChanged?()
        }
    }

    public var recentAppPaths: [String] {
        didSet {
            guard !isBootstrapping, recentAppPaths != oldValue else { return }
            defaults.set(recentAppPaths, forKey: Keys.recentAppPaths)
        }
    }

    // MARK: - Inicialización

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isBootstrapping = true

        let savedStartByDefault = defaults.object(forKey: Keys.startEnabledByDefault) as? Bool ?? false
        self.startEnabledByDefault = savedStartByDefault
        self.isEnabled = savedStartByDefault
        self.hasCompletedSetup = defaults.bool(forKey: Keys.hasCompletedSetup)

        let savedHeight = defaults.object(forKey: Keys.barHeight) as? Double ?? Self.defaultBarHeight
        self.barHeight = min(max(savedHeight, Self.minBarHeight), Self.maxBarHeight)

        let savedFont = defaults.object(forKey: Keys.fontSize) as? Double ?? Self.defaultFontSize
        self.fontSize = min(max(savedFont, Self.minFontSize), Self.maxFontSize)

        let savedOpacity = defaults.object(forKey: Keys.opacity) as? Double ?? Self.defaultOpacity
        self.opacity = min(max(savedOpacity, Self.minOpacity), Self.maxOpacity)

        self.themeMode = (defaults.string(forKey: Keys.themeMode).flatMap(TaskbarThemeMode.init(rawValue:))) ?? .system
        self.startButtonIcon = (defaults.string(forKey: Keys.startButtonIcon).flatMap(TaskbarStartButtonIcon.init(rawValue:))) ?? .windowsGrid
        self.alignment = (defaults.string(forKey: Keys.alignment).flatMap(TaskbarAlignment.init(rawValue:))) ?? .left
        self.showWindowTitles = defaults.object(forKey: Keys.showWindowTitles) as? Bool ?? true
        self.showMinimizedIndicator = defaults.object(forKey: Keys.showMinimizedIndicator) as? Bool ?? true
        self.showNotificationBadges = defaults.object(forKey: Keys.showNotificationBadges) as? Bool ?? true
        self.notificationAnimation = (defaults.string(forKey: Keys.notificationAnimation).flatMap(TaskbarNotificationAnimation.init(rawValue:))) ?? .bounce
        self.notificationAnimationCadence = (defaults.string(forKey: Keys.notificationAnimationCadence).flatMap(TaskbarNotificationAnimationCadence.init(rawValue:))) ?? .periodic

        self.groupWindowsByApp = defaults.object(forKey: Keys.groupWindowsByApp) as? Bool ?? false
        self.showWindowlessRunningApps = defaults.object(forKey: Keys.showWindowlessRunningApps) as? Bool ?? true
        self.showHoverPreviews = defaults.object(forKey: Keys.showHoverPreviews) as? Bool ?? true

        let savedDelay = defaults.object(forKey: Keys.hoverPreviewDelay) as? Double ?? Self.defaultHoverDelay
        self.hoverPreviewDelay = min(max(savedDelay, Self.minHoverDelay), Self.maxHoverDelay)

        self.thumbnailSize = (defaults.string(forKey: Keys.thumbnailSize).flatMap(TaskbarThumbnailSize.init(rawValue:))) ?? .medium
        self.hoverPreviewAnimation = (defaults.string(forKey: Keys.hoverPreviewAnimation).flatMap(TaskbarHoverPreviewAnimation.init(rawValue:))) ?? .fadeLift
        self.showTitleInThumbnail = defaults.object(forKey: Keys.showTitleInThumbnail) as? Bool ?? true
        self.clickFocusedAction = (defaults.string(forKey: Keys.clickFocusedAction).flatMap(TaskbarFocusedClickAction.init(rawValue:))) ?? .minimizeWindow
        self.middleClickClosesWindow = defaults.object(forKey: Keys.middleClickClosesWindow) as? Bool ?? true
        self.autoResizeOverlappingWindows = defaults.object(forKey: Keys.autoResizeOverlappingWindows) as? Bool ?? true

        self.displayMode = (defaults.string(forKey: Keys.displayMode).flatMap(TaskbarDisplayMode.init(rawValue:))) ?? .allDisplays
        self.windowScopeMode = (defaults.string(forKey: Keys.windowScopeMode).flatMap(TaskbarWindowScopeMode.init(rawValue:))) ?? .perDisplay
        self.syncWithActiveSpace = defaults.object(forKey: Keys.syncWithActiveSpace) as? Bool ?? true
        self.dockMode = (defaults.string(forKey: Keys.dockMode).flatMap(TaskbarDockMode.init(rawValue:))) ?? .unchanged

        if let pinnedData = defaults.data(forKey: Keys.pinnedApps),
           let decoded = try? JSONDecoder().decode([TaskbarPinnedApp].self, from: pinnedData) {
            self.pinnedApps = decoded
        } else {
            self.pinnedApps = Self.makeInitialDefaultPinnedApps()
        }

        self.excludedBundleIDs = defaults.stringArray(forKey: Keys.excludedBundleIDs) ?? []
        self.hiddenDisplayIDs = Set(defaults.stringArray(forKey: Keys.hiddenDisplayIDs) ?? [])
        self.recentAppPaths = defaults.stringArray(forKey: Keys.recentAppPaths) ?? []

        self.isBootstrapping = false
    }

    // MARK: - Helpers de Apps Fijadas, Excluidas y Recientes

    private static func makeInitialDefaultPinnedApps() -> [TaskbarPinnedApp] {
        var result: [TaskbarPinnedApp] = []
        let candidates: [(bundleID: String, path: String, name: String)] = [
            ("com.apple.finder", "/System/Library/CoreServices/Finder.app", "Finder"),
            ("com.apple.Safari", "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app", "Safari"),
            ("com.apple.Safari", "/Applications/Safari.app", "Safari"),
            ("com.apple.Terminal", "/System/Applications/Utilities/Terminal.app", "Terminal")
        ]
        var seen = Set<String>()
        for c in candidates {
            guard !seen.contains(c.bundleID), FileManager.default.fileExists(atPath: c.path) else { continue }
            seen.insert(c.bundleID)
            result.append(TaskbarPinnedApp(bundleIdentifier: c.bundleID, bundlePath: c.path, displayName: c.name))
        }
        return result
    }

    public func isPinned(bundleIdentifier: String, bundlePath: String? = nil) -> Bool {
        let lowerID = bundleIdentifier.lowercased()
        let lowerPath = bundlePath?.lowercased()
        return pinnedApps.contains { pinned in
            if !lowerID.isEmpty && pinned.bundleIdentifier.lowercased() == lowerID {
                return true
            }
            if let lowerPath, !lowerPath.isEmpty && pinned.bundlePath.lowercased() == lowerPath {
                return true
            }
            return false
        }
    }

    public func pinApp(bundleIdentifier: String, bundleURL: URL, displayName: String) {
        let path = bundleURL.standardizedFileURL.path(percentEncoded: false)
        guard !isPinned(bundleIdentifier: bundleIdentifier, bundlePath: path) else { return }
        pinnedApps.append(
            TaskbarPinnedApp(
                bundleIdentifier: bundleIdentifier,
                bundlePath: path,
                displayName: displayName
            )
        )
    }

    public func unpinApp(bundleIdentifier: String, bundlePath: String? = nil) {
        let lowerID = bundleIdentifier.lowercased()
        let lowerPath = bundlePath?.lowercased()
        pinnedApps.removeAll { pinned in
            (!lowerID.isEmpty && pinned.bundleIdentifier.lowercased() == lowerID) ||
            (lowerPath != nil && pinned.bundlePath.lowercased() == lowerPath)
        }
    }

    public func movePinnedApp(sourceID: String, toTargetID targetID: String) {
        guard sourceID != targetID,
              let fromIndex = pinnedApps.firstIndex(where: { $0.id == sourceID }),
              let toIndex = pinnedApps.firstIndex(where: { $0.id == targetID }) else {
            return
        }
        var updated = pinnedApps
        let item = updated.remove(at: fromIndex)
        updated.insert(item, at: toIndex)
        pinnedApps = updated
    }

    public func isAppExcluded(bundleIdentifier: String) -> Bool {
        guard !bundleIdentifier.isEmpty else { return false }
        if Self.defaultExcludedSystemBundleIDs.contains(bundleIdentifier) {
            return true
        }
        return excludedBundleIDs.contains { $0.caseInsensitiveCompare(bundleIdentifier) == .orderedSame }
    }

    public func excludeApp(bundleIdentifier: String) {
        let trimmed = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !excludedBundleIDs.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        excludedBundleIDs.append(trimmed)
    }

    public func removeExcludedApp(bundleIdentifier: String) {
        excludedBundleIDs.removeAll { $0.caseInsensitiveCompare(bundleIdentifier) == .orderedSame }
    }

    public func recordRecentApp(bundleURL: URL) {
        let path = bundleURL.standardizedFileURL.path(percentEncoded: false)
        guard path.hasSuffix(".app"), FileManager.default.fileExists(atPath: path) else { return }
        var updated = recentAppPaths.filter { $0.caseInsensitiveCompare(path) != .orderedSame }
        updated.insert(path, at: 0)
        if updated.count > 12 {
            updated = Array(updated.prefix(12))
        }
        recentAppPaths = updated
    }

    public func setDisplayHidden(_ hidden: Bool, displayID: String) {
        if hidden {
            hiddenDisplayIDs.insert(displayID)
        } else {
            hiddenDisplayIDs.remove(displayID)
        }
    }

    public func showAllHiddenDisplays() {
        hiddenDisplayIDs.removeAll()
    }

    // MARK: - Respaldo Persistente del Dock Original de macOS

    public func loadDockBackupSnapshot() -> TaskbarDockBackupSnapshot? {
        guard let data = defaults.data(forKey: Keys.dockBackupSnapshot) else { return nil }
        return try? JSONDecoder().decode(TaskbarDockBackupSnapshot.self, from: data)
    }

    public func saveDockBackupSnapshot(_ snapshot: TaskbarDockBackupSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Keys.dockBackupSnapshot)
        }
    }

    public func resetVisualDefaults() {
        barHeight = Self.defaultBarHeight
        fontSize = Self.defaultFontSize
        opacity = Self.defaultOpacity
        themeMode = .system
        startButtonIcon = .windowsGrid
        alignment = .left
        showWindowTitles = true
        showMinimizedIndicator = true
        showNotificationBadges = true
        notificationAnimation = .bounce
        notificationAnimationCadence = .periodic
        hoverPreviewDelay = Self.defaultHoverDelay
        thumbnailSize = .medium
        hoverPreviewAnimation = .fadeLift
        showTitleInThumbnail = true
    }
}
