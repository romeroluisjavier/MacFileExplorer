import Foundation
import ImageIO

/// Modo principal de transformación para el Renombrado Masivo.
public enum BulkRenameMode: String, CaseIterable, Identifiable, Sendable {
    case regexReplace
    case sequentialNumbering
    case exifDate
    case caseTransform

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .regexReplace: return "textformat.abc.dottedunderline"
        case .sequentialNumbering: return "number.square"
        case .exifDate: return "calendar.badge.clock"
        case .caseTransform: return "textformat"
        }
    }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .regexReplace:
            return loc.text(es: "Buscar / Regex", en: "Find / Regex")
        case .sequentialNumbering:
            return loc.text(es: "Numeración", en: "Numbering")
        case .exifDate:
            return loc.text(es: "Fecha EXIF", en: "EXIF Date")
        case .caseTransform:
            return loc.text(es: "Mayúsculas", en: "Case")
        }
    }
}

/// Transformación de mayúsculas y minúsculas aplicable al nombre.
public enum BulkRenameCaseOption: String, CaseIterable, Identifiable, Sendable {
    case unchanged
    case lowercase
    case uppercase
    case titleCase

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .unchanged: return loc.text(es: "Sin cambios", en: "Unchanged")
        case .lowercase: return loc.text(es: "minúsculas", en: "lowercase")
        case .uppercase: return loc.text(es: "MAYÚSCULAS", en: "UPPERCASE")
        case .titleCase: return loc.text(es: "Tipo Título", en: "Title Case")
        }
    }
}

/// Ubicación de la fecha EXIF / archivo dentro del nuevo nombre.
public enum BulkRenameDatePlacement: String, CaseIterable, Identifiable, Sendable {
    case prefix
    case suffix
    case replaceName

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .prefix: return loc.text(es: "Prefijo (Fecha_Nombre)", en: "Prefix (Date_Name)")
        case .suffix: return loc.text(es: "Sufijo (Nombre_Fecha)", en: "Suffix (Name_Date)")
        case .replaceName: return loc.text(es: "Reemplazar nombre", en: "Replace name")
        }
    }
}

/// Configuración completa del renombrado masivo.
public struct BulkRenameConfiguration: Equatable, Sendable {
    public var mode: BulkRenameMode = .regexReplace

    // Buscar / Reemplazar + Regex
    public var findPattern: String = ""
    public var replacePattern: String = ""
    public var useRegex: Bool = true
    public var caseSensitive: Bool = false
    public var applyToExtension: Bool = false

    // Numeración secuencial
    public var numberingPrefix: String = ""
    public var numberingSuffix: String = ""
    public var preserveOriginalNameInNumbering: Bool = true
    public var startNumber: Int = 1
    public var step: Int = 1
    public var zeroPadding: Int = 3
    public var numberingSeparator: String = "_"

    // Fecha EXIF / archivo
    public var dateFormat: String = "yyyy-MM-dd_HH-mm-ss"
    public var datePlacement: BulkRenameDatePlacement = .prefix
    public var dateSeparator: String = "_"
    public var fallbackToFileDate: Bool = true

    // Mayúsculas / Minúsculas
    public var caseOption: BulkRenameCaseOption = .unchanged

    public init() {}
}

/// Elemento individual de vista previa en tiempo real para el Renombrado Masivo.
public struct BulkRenamePreviewItem: Identifiable, Equatable, Sendable {
    public let id: URL
    public let originalName: String
    public let proposedName: String
    public let isDirectory: Bool
    public let conflictMessage: String?

    public var hasChange: Bool {
        proposedName != originalName
    }

    public var isValidToApply: Bool {
        hasChange && conflictMessage == nil
    }
}

/// Motor de renombrado masivo con soporte para expresiones regulares, numeración secuencial,
/// fechas de metadatos EXIF (`ImageIO`) y detección de colisiones en tiempo real.
public enum BulkRenameService {

    /// Extrae la fecha original de metadatos EXIF (`DateTimeOriginal` / `DateTimeDigitized` / TIFF `DateTime`)
    /// usando `ImageIO`, o recurre a la fecha de creación/modificación del archivo si `fallbackToFileDate` es `true`.
    public static func extractDate(for url: URL, fallbackToFileDate: Bool = true) -> Date? {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            let exifFormatter = DateFormatter()
            exifFormatter.locale = Locale(identifier: "en_US_POSIX")
            exifFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"

            if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                if let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
                   let parsed = exifFormatter.date(from: raw) {
                    return parsed
                }
                if let raw = exif[kCGImagePropertyExifDateTimeDigitized] as? String,
                   let parsed = exifFormatter.date(from: raw) {
                    return parsed
                }
            }
            if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
               let raw = tiff[kCGImagePropertyTIFFDateTime] as? String,
               let parsed = exifFormatter.date(from: raw) {
                return parsed
            }
        }

        guard fallbackToFileDate else { return nil }
        if let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]) {
            return values.creationDate ?? values.contentModificationDate
        }
        return nil
    }

    /// Genera la vista previa en tiempo real para todos los elementos seleccionados, validando regex y colisiones.
    @MainActor
    public static func generatePreview(
        for items: [FileItem],
        configuration: BulkRenameConfiguration,
        existingSiblingNames: Set<String>,
        exifDateCache: [URL: Date] = [:],
        using loc: LocalizationManager = .shared
    ) -> (previews: [BulkRenamePreviewItem], regexError: String?) {
        var compiledRegex: NSRegularExpression? = nil
        var regexError: String? = nil

        if configuration.mode == .regexReplace && configuration.useRegex && !configuration.findPattern.isEmpty {
            var options: NSRegularExpression.Options = []
            if !configuration.caseSensitive {
                options.insert(.caseInsensitive)
            }
            do {
                compiledRegex = try NSRegularExpression(pattern: configuration.findPattern, options: options)
            } catch {
                regexError = error.localizedDescription
            }
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = configuration.dateFormat.isEmpty ? "yyyy-MM-dd_HH-mm-ss" : configuration.dateFormat

        let selectedOriginalNamesLower = Set(items.map { $0.name.lowercased() })
        let nonSelectedSiblingsLower = Set(
            existingSiblingNames
                .map { $0.lowercased() }
                .filter { !selectedOriginalNamesLower.contains($0) }
        )

        var rawProposals: [(item: FileItem, proposedName: String)] = []
        rawProposals.reserveCapacity(items.count)

        for (index, item) in items.enumerated() {
            let (baseName, ext) = splitNameAndExtension(item.name, isDirectory: item.isNavigableFolder)
            let targetInput = configuration.applyToExtension ? item.name : baseName

            var transformed: String
            switch configuration.mode {
            case .regexReplace:
                if regexError != nil || configuration.findPattern.isEmpty {
                    transformed = targetInput
                } else if let compiledRegex {
                    let range = NSRange(targetInput.startIndex..., in: targetInput)
                    transformed = compiledRegex.stringByReplacingMatches(
                        in: targetInput,
                        options: [],
                        range: range,
                        withTemplate: configuration.replacePattern
                    )
                } else {
                    let compareOpts: String.CompareOptions = configuration.caseSensitive ? [] : [.caseInsensitive]
                    transformed = targetInput.replacingOccurrences(
                        of: configuration.findPattern,
                        with: configuration.replacePattern,
                        options: compareOpts
                    )
                }

            case .sequentialNumbering:
                let numberValue = configuration.startNumber + (index * max(1, configuration.step))
                let padded = String(format: "%0\(max(1, configuration.zeroPadding))d", numberValue)
                if configuration.preserveOriginalNameInNumbering {
                    let sep = baseName.isEmpty ? "" : configuration.numberingSeparator
                    transformed = "\(configuration.numberingPrefix)\(baseName)\(sep)\(padded)\(configuration.numberingSuffix)"
                } else {
                    transformed = "\(configuration.numberingPrefix)\(padded)\(configuration.numberingSuffix)"
                }

            case .exifDate:
                let resolvedDate = exifDateCache[item.url]
                    ?? extractDate(for: item.url, fallbackToFileDate: configuration.fallbackToFileDate)
                if let resolvedDate {
                    let dateStr = dateFormatter.string(from: resolvedDate)
                    switch configuration.datePlacement {
                    case .prefix:
                        transformed = "\(dateStr)\(configuration.dateSeparator)\(baseName)"
                    case .suffix:
                        transformed = "\(baseName)\(configuration.dateSeparator)\(dateStr)"
                    case .replaceName:
                        transformed = dateStr
                    }
                } else {
                    transformed = targetInput
                }

            case .caseTransform:
                transformed = applyCase(configuration.caseOption, to: targetInput)
            }

            if configuration.mode != .caseTransform && configuration.caseOption != .unchanged {
                transformed = applyCase(configuration.caseOption, to: transformed)
            }

            let finalName: String
            if configuration.applyToExtension || ext.isEmpty {
                finalName = transformed
            } else {
                finalName = "\(transformed).\(ext)"
            }
            rawProposals.append((item: item, proposedName: finalName))
        }

        // Contar colisiones dentro del mismo lote
        var proposedCounts: [String: Int] = [:]
        for entry in rawProposals {
            proposedCounts[entry.proposedName.lowercased(), default: 0] += 1
        }

        let previews: [BulkRenamePreviewItem] = rawProposals.map { entry in
            let name = entry.proposedName
            let lower = name.lowercased()
            var conflict: String? = nil

            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                conflict = loc.text(es: "Nombre vacío", en: "Empty name")
            } else if name.contains("/") || name.contains(":") {
                conflict = loc.text(es: "Carácter no permitido (/ o :)", en: "Invalid character (/ or :)")
            } else if (proposedCounts[lower] ?? 0) > 1 {
                conflict = loc.text(es: "Nombre duplicado en el lote", en: "Duplicate name in batch")
            } else if name != entry.item.name && nonSelectedSiblingsLower.contains(lower) {
                conflict = loc.text(es: "Ya existe en la carpeta", en: "Already exists in folder")
            }

            return BulkRenamePreviewItem(
                id: entry.item.url,
                originalName: entry.item.name,
                proposedName: name,
                isDirectory: entry.item.isNavigableFolder,
                conflictMessage: conflict
            )
        }

        return (previews, regexError)
    }

    private static func splitNameAndExtension(_ fullName: String, isDirectory: Bool) -> (base: String, ext: String) {
        if isDirectory {
            return (fullName, "")
        }
        let ns = fullName as NSString
        let ext = ns.pathExtension
        if ext.isEmpty {
            return (fullName, "")
        }
        let base = ns.deletingPathExtension
        return (base, ext)
    }

    private static func applyCase(_ option: BulkRenameCaseOption, to text: String) -> String {
        switch option {
        case .unchanged: return text
        case .lowercase: return text.lowercased()
        case .uppercase: return text.uppercased()
        case .titleCase: return text.localizedCapitalized
        }
    }
}
