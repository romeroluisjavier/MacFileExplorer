import Foundation
import Observation

/// Preferencias reactivas y persistentes del selector de ventanas **AltTab** integrado en `MacFileExplorer`.
///
/// - Arranca desactivado de fábrica (`isEnabled = false`, `startEnabledByDefault = false`), igual que la Barra de tareas.
/// - Permite elegir atajos múltiples, estilo visual, tamaño automático, vista previa a tamaño completo y apps excluidas.
@MainActor
@Observable
public final class AltTabPreferences {

    public static let shared = AltTabPreferences()

    public static let minManualThumbnailWidth: Double = 140
    public static let maxManualThumbnailWidth: Double = 320
    public static let defaultManualThumbnailWidth: Double = 224

    public static let minPreviewDelayMs: Double = 0
    public static let maxPreviewDelayMs: Double = 500
    public static let defaultPreviewDelayMs: Double = 120

    public static let maxShortcutProfiles: Int = 5

    private let defaults: UserDefaults
    private var isBootstrapping = false

    private enum Keys {
        static let startEnabledByDefault = "com.macfileexplorer.alttab.startEnabledByDefault"
        static let displayStyle = "com.macfileexplorer.alttab.displayStyle"
        static let autoSizeEnabled = "com.macfileexplorer.alttab.autoSizeEnabled"
        static let manualThumbnailWidth = "com.macfileexplorer.alttab.manualThumbnailWidth"
        static let themeMode = "com.macfileexplorer.alttab.themeMode"
        static let showFullSizePreview = "com.macfileexplorer.alttab.showFullSizePreview"
        static let fullSizePreviewDelayMs = "com.macfileexplorer.alttab.fullSizePreviewDelayMs"
        static let showSearchBar = "com.macfileexplorer.alttab.showSearchBar"
        static let showSpaceBadges = "com.macfileexplorer.alttab.showSpaceBadges"
        static let showWindowStateBadges = "com.macfileexplorer.alttab.showWindowStateBadges"
        static let showHoverQuickActions = "com.macfileexplorer.alttab.showHoverQuickActions"
        static let hudScreenMode = "com.macfileexplorer.alttab.hudScreenMode"
        static let shortcutProfiles = "com.macfileexplorer.alttab.shortcutProfiles"
        static let excludedBundleIDs = "com.macfileexplorer.alttab.excludedBundleIDs"
    }

    public var onEnabledChanged: ((Bool) -> Void)?
    public var onShortcutsChanged: (() -> Void)?

    // MARK: - Estado Principal

    public var isEnabled: Bool {
        didSet {
            guard !isBootstrapping, isEnabled != oldValue else { return }
            onEnabledChanged?(isEnabled)
            StatusBarManager.shared.refreshTooltipAndMenu()
        }
    }

    public var startEnabledByDefault: Bool {
        didSet {
            guard !isBootstrapping, startEnabledByDefault != oldValue else { return }
            defaults.set(startEnabledByDefault, forKey: Keys.startEnabledByDefault)
        }
    }

    // MARK: - Estilos y Apariencia

    public var displayStyle: AltTabDisplayStyle {
        didSet {
            guard !isBootstrapping, displayStyle != oldValue else { return }
            defaults.set(displayStyle.rawValue, forKey: Keys.displayStyle)
        }
    }

    public var autoSizeEnabled: Bool {
        didSet {
            guard !isBootstrapping, autoSizeEnabled != oldValue else { return }
            defaults.set(autoSizeEnabled, forKey: Keys.autoSizeEnabled)
        }
    }

    public var manualThumbnailWidth: Double {
        didSet {
            let clamped = min(max(manualThumbnailWidth, Self.minManualThumbnailWidth), Self.maxManualThumbnailWidth)
            if clamped != manualThumbnailWidth {
                manualThumbnailWidth = clamped
                return
            }
            guard !isBootstrapping, clamped != oldValue else { return }
            defaults.set(clamped, forKey: Keys.manualThumbnailWidth)
        }
    }

    public var themeMode: TaskbarThemeMode {
        didSet {
            guard !isBootstrapping, themeMode != oldValue else { return }
            defaults.set(themeMode.rawValue, forKey: Keys.themeMode)
        }
    }

    // MARK: - Vista Previa a Tamaño Completo, Etiquetas y Buscador

    public var showFullSizePreview: Bool {
        didSet {
            guard !isBootstrapping, showFullSizePreview != oldValue else { return }
            defaults.set(showFullSizePreview, forKey: Keys.showFullSizePreview)
        }
    }

    public var fullSizePreviewDelayMs: Double {
        didSet {
            let clamped = min(max(fullSizePreviewDelayMs, Self.minPreviewDelayMs), Self.maxPreviewDelayMs)
            if clamped != fullSizePreviewDelayMs {
                fullSizePreviewDelayMs = clamped
                return
            }
            guard !isBootstrapping, clamped != oldValue else { return }
            defaults.set(clamped, forKey: Keys.fullSizePreviewDelayMs)
        }
    }

    public var showSearchBar: Bool {
        didSet {
            guard !isBootstrapping, showSearchBar != oldValue else { return }
            defaults.set(showSearchBar, forKey: Keys.showSearchBar)
        }
    }

    public var showSpaceBadges: Bool {
        didSet {
            guard !isBootstrapping, showSpaceBadges != oldValue else { return }
            defaults.set(showSpaceBadges, forKey: Keys.showSpaceBadges)
        }
    }

    public var showWindowStateBadges: Bool {
        didSet {
            guard !isBootstrapping, showWindowStateBadges != oldValue else { return }
            defaults.set(showWindowStateBadges, forKey: Keys.showWindowStateBadges)
        }
    }

    public var showHoverQuickActions: Bool {
        didSet {
            guard !isBootstrapping, showHoverQuickActions != oldValue else { return }
            defaults.set(showHoverQuickActions, forKey: Keys.showHoverQuickActions)
        }
    }

    public var hudScreenMode: AltTabWindowScopeScreens {
        didSet {
            guard !isBootstrapping, hudScreenMode != oldValue else { return }
            defaults.set(hudScreenMode.rawValue, forKey: Keys.hudScreenMode)
        }
    }

    // MARK: - Perfiles de Atajos y Apps Excluidas

    public var shortcutProfiles: [AltTabShortcutProfile] {
        didSet {
            guard !isBootstrapping, shortcutProfiles != oldValue else { return }
            if let data = try? JSONEncoder().encode(shortcutProfiles) {
                defaults.set(data, forKey: Keys.shortcutProfiles)
            }
            onShortcutsChanged?()
        }
    }

    public var excludedBundleIDs: [String] {
        didSet {
            guard !isBootstrapping, excludedBundleIDs != oldValue else { return }
            defaults.set(excludedBundleIDs, forKey: Keys.excludedBundleIDs)
        }
    }

    // MARK: - Inicialización

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isBootstrapping = true

        let savedStartByDefault = defaults.object(forKey: Keys.startEnabledByDefault) as? Bool ?? false
        self.startEnabledByDefault = savedStartByDefault
        self.isEnabled = savedStartByDefault

        self.displayStyle = (defaults.string(forKey: Keys.displayStyle).flatMap(AltTabDisplayStyle.init(rawValue:))) ?? .thumbnails
        self.autoSizeEnabled = defaults.object(forKey: Keys.autoSizeEnabled) as? Bool ?? true

        let savedThumbW = defaults.object(forKey: Keys.manualThumbnailWidth) as? Double ?? Self.defaultManualThumbnailWidth
        self.manualThumbnailWidth = min(max(savedThumbW, Self.minManualThumbnailWidth), Self.maxManualThumbnailWidth)

        self.themeMode = (defaults.string(forKey: Keys.themeMode).flatMap(TaskbarThemeMode.init(rawValue:))) ?? .system
        self.showFullSizePreview = defaults.object(forKey: Keys.showFullSizePreview) as? Bool ?? true

        let savedDelay = defaults.object(forKey: Keys.fullSizePreviewDelayMs) as? Double ?? Self.defaultPreviewDelayMs
        self.fullSizePreviewDelayMs = min(max(savedDelay, Self.minPreviewDelayMs), Self.maxPreviewDelayMs)

        self.showSearchBar = defaults.object(forKey: Keys.showSearchBar) as? Bool ?? false
        self.showSpaceBadges = defaults.object(forKey: Keys.showSpaceBadges) as? Bool ?? true
        self.showWindowStateBadges = defaults.object(forKey: Keys.showWindowStateBadges) as? Bool ?? true
        self.showHoverQuickActions = defaults.object(forKey: Keys.showHoverQuickActions) as? Bool ?? true
        self.hudScreenMode = (defaults.string(forKey: Keys.hudScreenMode).flatMap(AltTabWindowScopeScreens.init(rawValue:))) ?? .activeMouseScreen

        if let data = defaults.data(forKey: Keys.shortcutProfiles),
           let decoded = try? JSONDecoder().decode([AltTabShortcutProfile].self, from: data),
           !decoded.isEmpty {
            self.shortcutProfiles = decoded
        } else {
            self.shortcutProfiles = AltTabShortcutProfile.makeDefaultProfiles()
        }

        self.excludedBundleIDs = defaults.stringArray(forKey: Keys.excludedBundleIDs) ?? []
        self.isBootstrapping = false
    }

    // MARK: - Helpers de Perfiles y Exclusiones

    public var primaryShortcutDisplay: String {
        shortcutProfiles.first?.displayString ?? "⌥ ⇥"
    }

    public func setPrimaryShortcutPreset(command: Bool, option: Bool, control: Bool) {
        var updated = shortcutProfiles
        if updated.isEmpty {
            updated = AltTabShortcutProfile.makeDefaultProfiles()
        }
        updated[0].holdCommand = command
        updated[0].holdOption = option
        updated[0].holdControl = control
        updated[0].holdShift = false
        updated[0].triggerKeyCode = 48 // Tab
        updated[0].triggerKeyLabel = "⇥"
        updated[0].isEnabled = true
        shortcutProfiles = updated
    }

    public func addShortcutProfile() {
        guard shortcutProfiles.count < Self.maxShortcutProfiles else { return }
        var updated = shortcutProfiles
        updated.append(
            AltTabShortcutProfile(
                name: "Atajo \(updated.count + 1) / Shortcut \(updated.count + 1)",
                isEnabled: true,
                triggerKeyCode: 48,
                triggerKeyLabel: "⇥",
                holdCommand: false,
                holdOption: false,
                holdControl: true,
                holdShift: false,
                appsScope: .allApps,
                spacesScope: .activeSpaceOnly,
                screensScope: .allScreens,
                includeMinimized: true,
                includeHidden: true,
                releaseBehavior: .switchOnModifierRelease
            )
        )
        shortcutProfiles = updated
    }

    public func removeShortcutProfile(id: UUID) {
        guard shortcutProfiles.count > 1 else { return }
        shortcutProfiles.removeAll { $0.id == id }
    }

    public func resetShortcutsToDefaults() {
        shortcutProfiles = AltTabShortcutProfile.makeDefaultProfiles()
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

    public func importExcludedAppsFromTaskbar() {
        for bundleID in TaskbarPreferences.shared.excludedBundleIDs {
            excludeApp(bundleIdentifier: bundleID)
        }
    }
}
