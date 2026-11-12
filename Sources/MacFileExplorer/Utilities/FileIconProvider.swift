import AppKit
import SwiftUI
import Foundation
import UniformTypeIdentifiers

/// Caché en memoria (`@MainActor`) de iconos del sistema y proveedor del icono oficial de la aplicación
/// con soporte dinámico para modo Claro (`AppIcon-Light.png`) y modo Oscuro (`AppIcon-Dark.png`).
@MainActor
public final class FileIconProvider {

    public static let shared = FileIconProvider()

    private let cache = NSCache<NSString, NSImage>()
    private var cachedLightAppIcon: NSImage?
    private var cachedDarkAppIcon: NSImage?

    private init() {
        cache.countLimit = 1024
        cachedLightAppIcon = loadBundledImage(named: "AppIcon-Light")
        cachedDarkAppIcon = loadBundledImage(named: "AppIcon-Dark")
    }

    /// Obtiene el icono de la aplicación adaptado al esquema de color de SwiftUI (Claro u Oscuro).
    public func appIcon(for colorScheme: ColorScheme) -> NSImage? {
        switch colorScheme {
        case .dark:
            return cachedDarkAppIcon ?? cachedLightAppIcon
        case .light:
            return cachedLightAppIcon ?? cachedDarkAppIcon
        @unknown default:
            return cachedLightAppIcon
        }
    }

    /// Obtiene el icono de la aplicación detectando la apariencia efectiva actual de `NSApp` (Claro u Oscuro).
    public var currentAppIcon: NSImage? {
        let isDark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? (cachedDarkAppIcon ?? cachedLightAppIcon) : (cachedLightAppIcon ?? cachedDarkAppIcon)
    }

    /// Actualiza dinámicamente el icono del Dock de macOS según el tema activo (Claro / Oscuro).
    public func syncApplicationDockIcon(for colorScheme: ColorScheme) {
        if let icon = appIcon(for: colorScheme) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    /// Obtiene el icono estándar (básico) para un `FileItem` con el tamaño en puntos solicitado.
    public func icon(for item: FileItem, size: CGFloat = 20) -> NSImage {
        let key: String
        if item.isNavigableFolder {
            key = "folder::\(item.url.path(percentEncoded: false))::\(Int(size))"
        } else if !item.fileExtension.isEmpty && !item.isPackage {
            key = "ext::\(item.fileExtension)::\(Int(size))"
        } else {
            key = "path::\(item.url.path(percentEncoded: false))::\(Int(size))"
        }

        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        let rawIcon = NSWorkspace.shared.icon(forFile: item.url.path(percentEncoded: false))
        let sizedIcon = (rawIcon.copy() as? NSImage) ?? rawIcon
        sizedIcon.size = NSSize(width: size, height: size)
        cache.setObject(sizedIcon, forKey: key as NSString)
        return sizedIcon
    }

    /// Obtiene el icono representativo de la aplicación predeterminada asociada a la extensión del archivo (cacheado por extensión).
    public func appIcon(for item: FileItem, size: CGFloat = 20) -> NSImage {
        guard !item.isNavigableFolder && !item.isPackage && !item.fileExtension.isEmpty else {
            return icon(for: item, size: size)
        }

        let ext = item.fileExtension.lowercased()
        let key = "appIcon::\(ext)::\(Int(size))"
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        let resolvedAppURL: URL? =
            UTType(filenameExtension: ext).flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
            ?? NSWorkspace.shared.urlForApplication(toOpen: item.url)

        let resultIcon: NSImage
        if let resolvedAppURL {
            let rawIcon = NSWorkspace.shared.icon(forFile: resolvedAppURL.path(percentEncoded: false))
            let sized = (rawIcon.copy() as? NSImage) ?? rawIcon
            sized.size = NSSize(width: size, height: size)
            resultIcon = sized
        } else {
            resultIcon = icon(for: item, size: size)
        }

        cache.setObject(resultIcon, forKey: key as NSString)
        return resultIcon
    }

    /// Devuelve el icono base para una fila de la vista Lista según el `ListIconDisplayMode` activo.
    public func listIcon(for item: FileItem, mode: ListIconDisplayMode, size: CGFloat = 20) -> NSImage {
        switch mode {
        case .basic:
            return icon(for: item, size: size)
        case .appIcon, .thumbnail:
            return appIcon(for: item, size: size)
        }
    }

    // MARK: - Carga Segura de Recursos del Bundle (.app y SwiftPM)

    private func loadBundledImage(named name: String) -> NSImage? {
        // 1. Buscar primero en Bundle.main (MacFileExplorer.app/Contents/Resources/)
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("\(name).png"),
           FileManager.default.fileExists(atPath: resourceURL.path(percentEncoded: false)),
           let image = NSImage(contentsOf: resourceURL) {
            return image
        }
        // 2. Buscar en el sub-bundle generado por SwiftPM dentro de Contents/Resources
        if let subBundleURL = Bundle.main.resourceURL?.appendingPathComponent("MacFileExplorer_MacFileExplorer.bundle"),
           let subBundle = Bundle(url: subBundleURL),
           let url = subBundle.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        // 3. Buscar en AppIcon.icns si se solicita un icono general
        if let icnsURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: icnsURL) {
            return image
        }
        return nil
    }
}
