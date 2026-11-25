import AppKit
import Foundation
import Observation

/// Descubre, indexa alfabéticamente y cachea todas las aplicaciones instaladas en macOS para el Menú Inicio
/// (`/Applications`, `/System/Applications`, `/System/Applications/Utilities`, `~/Applications` y Finder).
@MainActor
@Observable
public final class TaskbarAppCatalogService {

    public static let shared = TaskbarAppCatalogService()

    public private(set) var installedApps: [TaskbarInstalledApp] = []
    public private(set) var isScanning: Bool = false

    private var iconCache: [String: NSImage] = [:]
    private var lastScanDate: Date = .distantPast
    private var activeScanTask: Task<Void, Never>?

    private init() {}

    /// Escanea las carpetas estándar de aplicaciones de macOS si no se escaneó recientemente (o si `force == true`).
    public func refreshCatalogIfNeeded(force: Bool = false) {
        if !force && !installedApps.isEmpty && Date().timeIntervalSince(lastScanDate) < 30 {
            return
        }
        activeScanTask?.cancel()
        isScanning = true
        activeScanTask = Task {
            let discovered = await Task.detached(priority: .userInitiated) {
                Self.scanInstalledAppsOffMainThread()
            }.value
            guard !Task.isCancelled else { return }
            self.installedApps = discovered
            self.lastScanDate = Date()
            self.isScanning = false
        }
    }

    /// Limpia el caché del ícono propio de `MacFileExplorer` cuando el usuario cambia el ícono de la app.
    public func invalidateSelfIconCache() {
        let ownPath = Bundle.main.bundleURL.standardizedFileURL.path(percentEncoded: false)
        iconCache.removeValue(forKey: ownPath)
        iconCache = iconCache.filter { !$0.key.lowercased().hasSuffix("/macfileexplorer.app") }
    }

    /// Devuelve el ícono en caché de una aplicación (con tamaño óptimo y renderizado nítido).
    public func icon(forAppAt url: URL) -> NSImage {
        let key = url.standardizedFileURL.path(percentEncoded: false)
        if isOwnApplication(bundleIdentifier: "", url: url),
           let custom = FileIconProvider.shared.currentAppIcon {
            let sized = (custom.copy() as? NSImage) ?? custom
            sized.size = NSSize(width: 64, height: 64)
            return sized
        }
        if let cached = iconCache[key] {
            return cached
        }
        let img = NSWorkspace.shared.icon(forFile: key)
        img.size = NSSize(width: 64, height: 64)
        iconCache[key] = img
        return img
    }

    public func icon(forBundleIdentifier bundleID: String, fallbackURL: URL?) -> NSImage {
        if isOwnApplication(bundleIdentifier: bundleID, url: fallbackURL),
           let custom = FileIconProvider.shared.currentAppIcon {
            let sized = (custom.copy() as? NSImage) ?? custom
            sized.size = NSSize(width: 64, height: 64)
            return sized
        }
        if let fallbackURL {
            return icon(forAppAt: fallbackURL)
        }
        if !bundleID.isEmpty, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return icon(forAppAt: url)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }

    private func isOwnApplication(bundleIdentifier: String, url: URL?) -> Bool {
        let ownBID = Bundle.main.bundleIdentifier ?? "com.macfileexplorer.app"
        if !bundleIdentifier.isEmpty, bundleIdentifier.caseInsensitiveCompare(ownBID) == .orderedSame {
            return true
        }
        if let url {
            let normalized = url.standardizedFileURL.path(percentEncoded: false)
            let ownPath = Bundle.main.bundleURL.standardizedFileURL.path(percentEncoded: false)
            if normalized.caseInsensitiveCompare(ownPath) == .orderedSame
                || normalized.lowercased().hasSuffix("/macfileexplorer.app") {
                return true
            }
        }
        return false
    }

    /// Devuelve la lista de apps recientes válidas (resueltas contra el catálogo o el disco).
    public func recentApps(limit: Int = 8) -> [TaskbarInstalledApp] {
        let catalogByPath = Dictionary(
            installedApps.map { ($0.bundleURL.standardizedFileURL.path(percentEncoded: false).lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var results: [TaskbarInstalledApp] = []
        let fm = FileManager.default
        for path in TaskbarPreferences.shared.recentAppPaths {
            if results.count >= limit { break }
            let normalized = URL(fileURLWithPath: path).standardizedFileURL
            let lowerPath = normalized.path(percentEncoded: false).lowercased()
            if let existing = catalogByPath[lowerPath] {
                results.append(existing)
            } else if fm.fileExists(atPath: normalized.path(percentEncoded: false)) {
                let bundle = Bundle(url: normalized)
                let bundleID = bundle?.bundleIdentifier ?? ""
                let name = Self.displayName(forAppAt: normalized, bundle: bundle)
                results.append(
                    TaskbarInstalledApp(
                        bundleIdentifier: bundleID,
                        name: name,
                        bundleURL: normalized
                    )
                )
            }
        }
        return results
    }

    /// Importa en modo solo lectura las aplicaciones fijadas actualmente en el Dock de macOS.
    public func readCurrentMacOSDockApps() -> [TaskbarPinnedApp] {
        guard let persistentApps = CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString) as? [[String: Any]] else {
            return []
        }

        var imported: [TaskbarPinnedApp] = []
        var seen = Set<String>()
        let fm = FileManager.default

        for entry in persistentApps {
            guard let tileData = entry["tile-data"] as? [String: Any],
                  let fileData = tileData["file-data"] as? [String: Any],
                  let urlString = fileData["_CFURLString"] as? String,
                  let url = URL(string: urlString) else {
                continue
            }
            let appURL = url.standardizedFileURL
            let path = appURL.path(percentEncoded: false)
            guard path.hasSuffix(".app"), fm.fileExists(atPath: path) else { continue }

            let bundle = Bundle(url: appURL)
            let bundleID = bundle?.bundleIdentifier ?? ""
            let dedupKey = (bundleID.isEmpty ? path : bundleID).lowercased()
            guard !seen.contains(dedupKey) else { continue }
            seen.insert(dedupKey)

            let name = Self.displayName(forAppAt: appURL, bundle: bundle)
            imported.append(TaskbarPinnedApp(bundleIdentifier: bundleID, bundlePath: path, displayName: name))
        }
        return imported
    }

    // MARK: - Escaneo en Segundo Plano

    private nonisolated static func scanInstalledAppsOffMainThread() -> [TaskbarInstalledApp] {
        let fm = FileManager.default
        let homeApps = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        let roots: [(url: URL, isUtility: Bool)] = [
            (URL(fileURLWithPath: "/Applications", isDirectory: true), false),
            (URL(fileURLWithPath: "/System/Applications", isDirectory: true), false),
            (URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true), true),
            (homeApps, false),
            (homeApps.appendingPathComponent("Chrome Apps.localized", isDirectory: true), false),
            (homeApps.appendingPathComponent("Edge Apps.localized", isDirectory: true), false),
            (homeApps.appendingPathComponent("Brave Browser Apps.localized", isDirectory: true), false),
            (homeApps.appendingPathComponent("Arc Apps.localized", isDirectory: true), false)
        ]

        var collected: [TaskbarInstalledApp] = []
        var seenKeys = Set<String>()

        func considerApp(at url: URL, isUtility: Bool) {
            let standardized = url.standardizedFileURL
            guard standardized.pathExtension.caseInsensitiveCompare("app") == .orderedSame else { return }
            let bundle = Bundle(url: standardized)
            let bundleID = bundle?.bundleIdentifier ?? ""
            let key = (bundleID.isEmpty ? standardized.path(percentEncoded: false) : bundleID).lowercased()
            guard !seenKeys.contains(key) else { return }
            seenKeys.insert(key)

            let name = displayName(forAppAt: standardized, bundle: bundle)
            collected.append(
                TaskbarInstalledApp(
                    bundleIdentifier: bundleID,
                    name: name,
                    bundleURL: standardized,
                    isSystemUtility: isUtility
                )
            )
        }

        // Incluir siempre Finder
        let finderURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        if fm.fileExists(atPath: finderURL.path(percentEncoded: false)) {
            considerApp(at: finderURL, isUtility: false)
        }

        // Incluir el propio MacFileExplorer si estamos corriendo como .app
        if Bundle.main.bundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
            considerApp(at: Bundle.main.bundleURL, isUtility: false)
        }

        for root in roots {
            guard fm.fileExists(atPath: root.url.path(percentEncoded: false)),
                  let entries = try? fm.contentsOfDirectory(
                    at: root.url,
                    includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .isHiddenKey],
                    options: [.skipsHiddenFiles]
                  ) else {
                continue
            }

            for entry in entries {
                if entry.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                    considerApp(at: entry, isUtility: root.isUtility)
                } else {
                    // Revisar 1 subnivel para carpetas de suites (ej. /Applications/Utilities, /Applications/Adobe...)
                    let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                    if values?.isDirectory == true && values?.isPackage != true,
                       let subEntries = try? fm.contentsOfDirectory(
                        at: entry,
                        includingPropertiesForKeys: [.isPackageKey],
                        options: [.skipsHiddenFiles]
                       ) {
                        for sub in subEntries where sub.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                            considerApp(at: sub, isUtility: root.isUtility || entry.lastPathComponent == "Utilities")
                        }
                    }
                }
            }
        }

        return collected.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private nonisolated static func displayName(forAppAt url: URL, bundle: Bundle?) -> String {
        if let localized = bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String {
            let cleaned = TaskbarStringSanitizer.sanitizeDisplayName(localized)
            if !cleaned.isEmpty { return cleaned }
        }
        if let display = bundle?.infoDictionary?["CFBundleDisplayName"] as? String {
            let cleaned = TaskbarStringSanitizer.sanitizeDisplayName(display)
            if !cleaned.isEmpty { return cleaned }
        }
        let fmName = FileManager.default.displayName(atPath: url.path(percentEncoded: false))
        let strippedExt = fmName.lowercased().hasSuffix(".app") ? String(fmName.dropLast(4)) : fmName
        let cleaned = TaskbarStringSanitizer.sanitizeDisplayName(strippedExt)
        return cleaned.isEmpty ? strippedExt : cleaned
    }
}
