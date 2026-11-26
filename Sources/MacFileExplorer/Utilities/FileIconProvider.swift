import AppKit
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Variantes seleccionables del ícono oficial de `MacFileExplorer` en macOS (Dock, `⌘+Tab`, Barra de tareas, AltTab y ventanas).
public enum MacFileExplorerAppIcon: String, CaseIterable, Identifiable, Codable, Sendable {
    case classic
    case macosNative
    case monoDark
    case monoLight
    case glassLayers

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .classic: return loc.text(es: "Clásico", en: "Classic")
        case .macosNative: return loc.text(es: "Estilo macOS", en: "macOS Style")
        case .monoDark: return loc.text(es: "Mono Oscuro", en: "Dark Mono")
        case .monoLight: return loc.text(es: "Mono Claro", en: "Light Mono")
        case .glassLayers: return loc.text(es: "Capas Cristal", en: "Glass Layers")
        }
    }

    @MainActor
    public func localizedSubtitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .classic: return loc.text(es: "Original a color", en: "Original color")
        case .macosNative: return loc.text(es: "Azul nativo Apple", en: "Native Apple blue")
        case .monoDark: return loc.text(es: "Blanco sobre negro", en: "White on obsidian")
        case .monoLight: return loc.text(es: "Negro sobre blanco", en: "Black on ceramic")
        case .glassLayers: return loc.text(es: "Cristal nocturno", en: "Midnight glass")
        }
    }

    public var menuSymbolName: String {
        switch self {
        case .classic: return "folder.fill"
        case .macosNative: return "macwindow"
        case .monoDark: return "moon.fill"
        case .monoLight: return "sun.max.fill"
        case .glassLayers: return "square.2.layers.3d.top.filled"
        }
    }

    public var resourceBaseName: String? {
        switch self {
        case .classic: return nil
        case .macosNative: return "AppIcon-MacOS"
        case .monoDark: return "AppIcon-MonoDark"
        case .monoLight: return "AppIcon-MonoLight"
        case .glassLayers: return "AppIcon-GlassLayers"
        }
    }
}

/// Caché en memoria (`@MainActor` + `@Observable`) de iconos del sistema y proveedor del icono de la aplicación
/// con soporte para 5 diseños seleccionables (Clásico Light/Dark + 4 variantes modernas estilo macOS/Start Button).
@MainActor
@Observable
public final class FileIconProvider {

    public static let shared = FileIconProvider()

    private static let selectedAppIconDefaultsKey = "com.macfileexplorer.selectedAppIcon"

    private let cache = NSCache<NSString, NSImage>()
    private var cachedLightAppIcon: NSImage?
    private var cachedDarkAppIcon: NSImage?
    private var cachedResourceImages: [String: NSImage] = [:]

    /// Estilo de ícono de la aplicación actualmente elegido por el usuario (persistido entre reinicios).
    public var selectedAppIcon: MacFileExplorerAppIcon {
        didSet {
            guard selectedAppIcon != oldValue else { return }
            UserDefaults.standard.set(selectedAppIcon.rawValue, forKey: Self.selectedAppIconDefaultsKey)
            applySelectedAppIconToSystem()
        }
    }

    private init() {
        cache.countLimit = 1024
        if let raw = UserDefaults.standard.string(forKey: Self.selectedAppIconDefaultsKey),
           let stored = MacFileExplorerAppIcon(rawValue: raw) {
            selectedAppIcon = stored
        } else {
            selectedAppIcon = .monoDark
        }
        cachedLightAppIcon = loadBundledImage(named: "AppIcon-Light")
        cachedDarkAppIcon = loadBundledImage(named: "AppIcon-Dark")
    }

    /// Carga y cachea una imagen PNG empaquetada en los recursos de la app (`Contents/Resources` o `Bundle.module`).
    public func bundledResourceImage(named name: String) -> NSImage? {
        if let cached = cachedResourceImages[name] {
            return cached
        }
        var found: NSImage?
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            found = image
        } else if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("\(name).png"),
                  FileManager.default.fileExists(atPath: resourceURL.path(percentEncoded: false)),
                  let image = NSImage(contentsOf: resourceURL) {
            found = image
        } else if let subBundleURL = Bundle.main.resourceURL?.appendingPathComponent("MacFileExplorer_MacFileExplorer.bundle"),
                  let subBundle = Bundle(url: subBundleURL),
                  let url = subBundle.url(forResource: name, withExtension: "png"),
                  let image = NSImage(contentsOf: url) {
            found = image
        } else if let url = Bundle.module.url(forResource: name, withExtension: "png"),
                  let image = NSImage(contentsOf: url) {
            found = image
        }
        if let found {
            cachedResourceImages[name] = found
        }
        return found
    }

    /// Devuelve la imagen de vista previa para cualquiera de los 5 íconos seleccionables.
    public func previewImage(for style: MacFileExplorerAppIcon, colorScheme: ColorScheme = .dark) -> NSImage? {
        if let resourceName = style.resourceBaseName,
           let custom = bundledResourceImage(named: resourceName) {
            return custom
        }
        switch colorScheme {
        case .dark:
            return cachedDarkAppIcon ?? cachedLightAppIcon
        case .light:
            return cachedLightAppIcon ?? cachedDarkAppIcon
        @unknown default:
            return cachedLightAppIcon ?? cachedDarkAppIcon
        }
    }

    /// Obtiene el icono activo de la aplicación adaptado al esquema de color de SwiftUI (Claro u Oscuro).
    public func appIcon(for colorScheme: ColorScheme) -> NSImage? {
        previewImage(for: selectedAppIcon, colorScheme: colorScheme)
    }

    /// Obtiene el icono activo de la aplicación detectando la apariencia efectiva actual de `NSApp` (Claro u Oscuro).
    public var currentAppIcon: NSImage? {
        let isDark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return previewImage(for: selectedAppIcon, colorScheme: isDark ? .dark : .light)
    }

    /// Aplica inmediatamente el ícono elegido en el Dock de macOS, `⌘+Tab`, Barra de tareas y AltTab.
    public func applySelectedAppIconToSystem() {
        if let icon = currentAppIcon {
            NSApplication.shared.applicationIconImage = icon
        }
        TaskbarAppCatalogService.shared.invalidateSelfIconCache()
    }

    /// Actualiza dinámicamente el icono del Dock de macOS según el tema activo (Claro / Oscuro) y la preferencia elegida.
    public func syncApplicationDockIcon(for colorScheme: ColorScheme) {
        if let icon = appIcon(for: colorScheme) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    /// Obtiene el icono estándar (básico) para un `FileItem` con el tamaño en puntos solicitado.
    public func icon(for item: FileItem, size: CGFloat = 20) -> NSImage {
        if !item.isNavigableFolder && !item.isPackage && item.fileExtension.lowercased() == "pdf" {
            return pdfFileIcon(size: size)
        }

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

    /// Obtiene el icono para una ruta de archivo arbitraria (mostrando el ícono rojo de PDF para archivos `.pdf`).
    public func icon(forFilePath path: String, size: CGFloat = 20) -> NSImage {
        let url = URL(fileURLWithPath: path)
        if url.pathExtension.lowercased() == "pdf" {
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            if !exists || !isDir.boolValue {
                return pdfFileIcon(size: size)
            }
        }
        let rawIcon = NSWorkspace.shared.icon(forFile: path)
        let sizedIcon = (rawIcon.copy() as? NSImage) ?? rawIcon
        sizedIcon.size = NSSize(width: size, height: size)
        return sizedIcon
    }

    /// Obtiene el icono representativo de la aplicación predeterminada asociada a la extensión del archivo (cacheado por extensión).
    public func appIcon(for item: FileItem, size: CGFloat = 20) -> NSImage {
        guard !item.isNavigableFolder && !item.isPackage && !item.fileExtension.isEmpty else {
            return icon(for: item, size: size)
        }

        let ext = item.fileExtension.lowercased()
        if ext == "pdf" {
            return pdfFileIcon(size: size)
        }

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

    /// Genera y cachea un ícono rojo vectorial estilo Acrobat Reader para archivos `.pdf`,
    /// siguiendo la grilla macOS HIG para alinearse exactamente con el resto de íconos de aplicaciones
    /// y distinguir instantáneamente los PDF de imágenes que también usan Vista Previa (Preview).
    public func pdfFileIcon(size: CGFloat = 20) -> NSImage {
        let clampedSize = max(12, size)
        let key = "customPDF::\(Int(clampedSize.rounded()))"
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        let image = NSImage(size: NSSize(width: clampedSize, height: clampedSize), flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let s = min(rect.width, rect.height)
            ctx.saveGState()
            ctx.setAllowsAntialiasing(true)
            ctx.setShouldAntialias(true)

            // Grilla squircle estándar de íconos de apps de macOS (~81% del lienzo)
            let inset = s * 0.095
            let cardRect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
            let cornerRadius = cardRect.width * 0.225
            let cardPath = CGPath(roundedRect: cardRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

            // 1. Sombra suave inferior acorde a íconos nativos de macOS
            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: s * 0.025),
                blur: s * 0.045,
                color: NSColor(calibratedWhite: 0, alpha: 0.34).cgColor
            )
            ctx.setFillColor(NSColor(srgbRed: 0.84, green: 0.07, blue: 0.07, alpha: 1.0).cgColor)
            ctx.addPath(cardPath)
            ctx.fillPath()
            ctx.restoreGState()

            // 2. Degradado rojo carmesí vibrante estilo Acrobat Reader dentro del squircle
            ctx.saveGState()
            ctx.addPath(cardPath)
            ctx.clip()

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let baseColors: [CGColor] = [
                NSColor(srgbRed: 0.965, green: 0.185, blue: 0.145, alpha: 1.0).cgColor,
                NSColor(srgbRed: 0.875, green: 0.070, blue: 0.070, alpha: 1.0).cgColor,
                NSColor(srgbRed: 0.675, green: 0.025, blue: 0.040, alpha: 1.0).cgColor
            ]
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: baseColors as CFArray, locations: [0.0, 0.52, 1.0]) {
                ctx.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: cardRect.midX, y: cardRect.minY),
                    end: CGPoint(x: cardRect.midX, y: cardRect.maxY),
                    options: []
                )
            }

            // Brillo especular superior sutil
            let glossColors: [CGColor] = [
                NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.19).cgColor,
                NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.0).cgColor
            ]
            if let gloss = CGGradient(colorsSpace: colorSpace, colors: glossColors as CFArray, locations: [0.0, 1.0]) {
                ctx.drawLinearGradient(
                    gloss,
                    start: CGPoint(x: cardRect.midX, y: cardRect.minY),
                    end: CGPoint(x: cardRect.midX, y: cardRect.minY + cardRect.height * 0.40),
                    options: []
                )
            }

            // 3. Emblema blanco de lazo trefoil estilo PDF / Acrobat centrado visualmente
            let yOffset: CGFloat = 0.02
            func rpt(_ nx: CGFloat, _ ny: CGFloat) -> CGPoint {
                CGPoint(
                    x: cardRect.minX + nx * cardRect.width,
                    y: cardRect.minY + (ny + yOffset) * cardRect.height
                )
            }

            let ribbon = CGMutablePath()
            ribbon.move(to: rpt(0.455, 0.365))
            ribbon.addCurve(
                to: rpt(0.515, 0.165),
                control1: rpt(0.500, 0.270),
                control2: rpt(0.555, 0.195)
            )
            ribbon.addCurve(
                to: rpt(0.460, 0.365),
                control1: rpt(0.460, 0.130),
                control2: rpt(0.435, 0.245)
            )
            ribbon.addCurve(
                to: rpt(0.765, 0.650),
                control1: rpt(0.495, 0.490),
                control2: rpt(0.625, 0.640)
            )
            ribbon.addCurve(
                to: rpt(0.690, 0.545),
                control1: rpt(0.875, 0.660),
                control2: rpt(0.845, 0.530)
            )
            ribbon.addCurve(
                to: rpt(0.205, 0.725),
                control1: rpt(0.470, 0.565),
                control2: rpt(0.235, 0.615)
            )
            ribbon.addCurve(
                to: rpt(0.325, 0.725),
                control1: rpt(0.160, 0.825),
                control2: rpt(0.265, 0.835)
            )
            ribbon.addCurve(
                to: rpt(0.455, 0.365),
                control1: rpt(0.385, 0.615),
                control2: rpt(0.425, 0.475)
            )

            // Refuerzo de grosor en tamaños pequeños (<= 24 pt) para máxima nitidez en vista Lista
            let strokeFactor: CGFloat = (s <= 24) ? 0.080 : 0.065

            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: cardRect.height * 0.02),
                blur: cardRect.height * 0.04,
                color: NSColor(srgbRed: 0.35, green: 0.0, blue: 0.0, alpha: 0.45).cgColor
            )
            ctx.addPath(ribbon)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(cardRect.width * strokeFactor)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.strokePath()
            ctx.restoreGState()

            // Borde interno sutil característico de íconos macOS
            ctx.addPath(cardPath)
            ctx.setStrokeColor(NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.16).cgColor)
            ctx.setLineWidth(max(0.6, s * 0.016))
            ctx.strokePath()

            ctx.restoreGState()
            ctx.restoreGState()
            return true
        }

        cache.setObject(image, forKey: key as NSString)
        return image
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
        if let found = bundledResourceImage(named: name) {
            return found
        }
        // Respaldo final en AppIcon.icns si se solicita un icono general
        if let icnsURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: icnsURL) {
            return image
        }
        return nil
    }
}
