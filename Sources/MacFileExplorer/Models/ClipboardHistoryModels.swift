import AppKit
import CryptoKit
import Foundation
import Observation

/// Tipo de contenido almacenado en una entrada del historial del portapapeles.
public enum ClipboardItemKind: String, Codable, CaseIterable, Sendable {
    case text
    case image
    case files
    case link

    public var systemImage: String {
        switch self {
        case .text: return "doc.text.fill"
        case .image: return "photo.fill"
        case .files: return "folder.fill"
        case .link: return "link"
        }
    }

    @MainActor
    public func localizedLabel(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .text: return loc.text(es: "Texto", en: "Text")
        case .image: return loc.text(es: "Imagen", en: "Image")
        case .files: return loc.text(es: "Archivos", en: "Files")
        case .link: return loc.text(es: "Enlace", en: "Link")
        }
    }
}

/// Filtro por categoría dentro del buscador del Historial del Portapapeles.
public enum ClipboardHistoryFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case text
    case images
    case files
    case links
    case pinned

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .all: return "tray.full.fill"
        case .text: return "doc.text"
        case .images: return "photo"
        case .files: return "folder"
        case .links: return "link"
        case .pinned: return "pin.fill"
        }
    }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .all: return loc.text(es: "Todos", en: "All")
        case .text: return loc.text(es: "Texto", en: "Text")
        case .images: return loc.text(es: "Imágenes", en: "Images")
        case .files: return loc.text(es: "Archivos", en: "Files")
        case .links: return loc.text(es: "Enlaces", en: "Links")
        case .pinned: return loc.text(es: "Fijados", en: "Pinned")
        }
    }
}

/// Tiempo máximo de retención para los elementos no fijados del historial del portapapeles.
public enum ClipboardRetentionPeriod: String, Codable, CaseIterable, Identifiable, Sendable {
    case oneHour = "1h"
    case twentyFourHours = "24h"
    case sevenDays = "7d"
    case thirtyDays = "30d"
    case ninetyDays = "90d"
    case forever = "forever"

    public var id: String { rawValue }

    /// Intervalo en segundos, o `nil` si se conserva indefinidamente.
    public var timeInterval: TimeInterval? {
        switch self {
        case .oneHour: return 3_600
        case .twentyFourHours: return 86_400
        case .sevenDays: return 7 * 86_400
        case .thirtyDays: return 30 * 86_400
        case .ninetyDays: return 90 * 86_400
        case .forever: return nil
        }
    }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .oneHour:
            return loc.text(es: "1 hora", en: "1 Hour")
        case .twentyFourHours:
            return loc.text(es: "24 horas (1 día)", en: "24 Hours (1 Day)")
        case .sevenDays:
            return loc.text(es: "7 días", en: "7 Days")
        case .thirtyDays:
            return loc.text(es: "30 días", en: "30 Days")
        case .ninetyDays:
            return loc.text(es: "90 días", en: "90 Days")
        case .forever:
            return loc.text(es: "Siempre (sin límite de tiempo)", en: "Forever (no time limit)")
        }
    }
}

/// Cantidad máxima de elementos a conservar en el historial del portapapeles (como en Maccy).
public enum ClipboardMaxItemsOption: Int, Codable, CaseIterable, Identifiable, Sendable {
    case fifty = 50
    case oneHundred = 100
    case twoHundred = 200
    case fiveHundred = 500
    case oneThousand = 1000
    case unlimited = 0

    public var id: Int { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .fifty:
            return loc.text(es: "50 elementos", en: "50 items")
        case .oneHundred:
            return loc.text(es: "100 elementos", en: "100 items")
        case .twoHundred:
            return loc.text(es: "200 elementos (Maccy predeterminado)", en: "200 items (Maccy default)")
        case .fiveHundred:
            return loc.text(es: "500 elementos", en: "500 items")
        case .oneThousand:
            return loc.text(es: "1000 elementos", en: "1000 items")
        case .unlimited:
            return loc.text(es: "Sin límite de cantidad", en: "Unlimited items")
        }
    }
}

/// Atajo rápido de teclado para abrir el buscador rápido del Historial del Portapapeles estilo Maccy.
public enum ClipboardPopupShortcutPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case shiftCommandC = "shift_cmd_c"
    case optionCommandC = "opt_cmd_c"
    case optionCommandV = "opt_cmd_v"
    case controlOptionCommandV = "ctrl_opt_cmd_v"
    case disabled = "disabled"

    public var id: String { rawValue }

    public var badgeText: String {
        switch self {
        case .shiftCommandC: return "⇧⌘C"
        case .optionCommandC: return "⌥⌘C"
        case .optionCommandV: return "⌥⌘V"
        case .controlOptionCommandV: return "⌃⌥⌘V"
        case .disabled: return ""
        }
    }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .shiftCommandC:
            return loc.text(es: "⇧⌘C (Estándar de Maccy)", en: "⇧⌘C (Maccy Default)")
        case .optionCommandC:
            return "⌥⌘C"
        case .optionCommandV:
            return "⌥⌘V"
        case .controlOptionCommandV:
            return "⌃⌥⌘V"
        case .disabled:
            return loc.text(es: "Desactivado", en: "Disabled")
        }
    }

    /// Verifica si un evento de teclado coincide con este atajo.
    public func matches(keyCode: UInt16, charactersIgnoringModifiers: String?, flags: NSEvent.ModifierFlags) -> Bool {
        let cleanFlags = flags.intersection([.command, .shift, .option, .control])
        let char = charactersIgnoringModifiers?.lowercased()
        switch self {
        case .shiftCommandC:
            return (keyCode == 8 || char == "c") && cleanFlags == [.command, .shift]
        case .optionCommandC:
            return (keyCode == 8 || char == "c") && cleanFlags == [.command, .option]
        case .optionCommandV:
            return (keyCode == 9 || char == "v") && cleanFlags == [.command, .option]
        case .controlOptionCommandV:
            return (keyCode == 9 || char == "v") && cleanFlags == [.command, .option, .control]
        case .disabled:
            return false
        }
    }
}

/// Entrada individual persistida en el Historial del Portapapeles (soporta texto, enlaces, archivos e imágenes).
public struct ClipboardHistoryEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let kind: ClipboardItemKind
    public let contentHash: String
    public var textContent: String?
    public var filePaths: [String]
    public var imageFileName: String?
    public var imagePixelWidth: Int?
    public var imagePixelHeight: Int?
    public var byteSize: Int
    public let createdAt: Date
    public var lastCopiedAt: Date
    public var copyCount: Int
    public var isPinned: Bool
    public var sourceAppName: String?
    public var sourceAppBundleID: String?

    public init(
        id: UUID = UUID(),
        kind: ClipboardItemKind,
        contentHash: String,
        textContent: String? = nil,
        filePaths: [String] = [],
        imageFileName: String? = nil,
        imagePixelWidth: Int? = nil,
        imagePixelHeight: Int? = nil,
        byteSize: Int = 0,
        createdAt: Date = Date(),
        lastCopiedAt: Date = Date(),
        copyCount: Int = 1,
        isPinned: Bool = false,
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.contentHash = contentHash
        self.textContent = textContent
        self.filePaths = filePaths
        self.imageFileName = imageFileName
        self.imagePixelWidth = imagePixelWidth
        self.imagePixelHeight = imagePixelHeight
        self.byteSize = byteSize
        self.createdAt = createdAt
        self.lastCopiedAt = lastCopiedAt
        self.copyCount = copyCount
        self.isPinned = isPinned
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
    }

    /// Título resumido en una sola línea para mostrar en la barra lateral, en la lista principal o en el popup estilo Maccy.
    @MainActor
    public func displayTitle(using loc: LocalizationManager = .shared) -> String {
        switch kind {
        case .image:
            if let w = imagePixelWidth, let h = imagePixelHeight, w > 0, h > 0 {
                if let text = textContent?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    return "\(singleLinePreview(of: text)) (\(w)×\(h) px)"
                }
                return loc.text(
                    es: "Imagen (\(w)×\(h) px)",
                    en: "Image (\(w)×\(h) px)"
                )
            }
            return loc.text(es: "Imagen copiada", en: "Copied Image")

        case .files:
            let names = filePaths.map { URL(fileURLWithPath: $0).lastPathComponent }.filter { !$0.isEmpty }
            guard let first = names.first else {
                return loc.text(es: "Archivos copiados", en: "Copied Files")
            }
            if names.count == 1 {
                return first
            }
            return loc.text(
                es: "\(first) y \(names.count - 1) más",
                en: "\(first) & \(names.count - 1) more"
            )

        case .link, .text:
            let raw = textContent ?? ""
            let preview = singleLinePreview(of: raw)
            return preview.isEmpty ? loc.text(es: "(Texto vacío)", en: "(Empty text)") : preview
        }
    }

    /// Subtítulo descriptivo con tamaño, dimensiones, cantidad de copias o aplicación de origen.
    @MainActor
    public func displaySubtitle(using loc: LocalizationManager = .shared) -> String {
        var parts: [String] = []
        parts.append(kind.localizedLabel(using: loc))

        if kind == .image, let w = imagePixelWidth, let h = imagePixelHeight, w > 0, h > 0 {
            parts.append("\(w)×\(h) px")
        } else if kind == .files, filePaths.count > 1 {
            parts.append(loc.text(es: "\(filePaths.count) elementos", en: "\(filePaths.count) items"))
        }

        if byteSize > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(byteSize), countStyle: .file))
        }

        if let app = sourceAppName, !app.isEmpty {
            parts.append(app)
        }

        if copyCount > 1 {
            parts.append("×\(copyCount)")
        }

        return parts.joined(separator: " • ")
    }

    /// Evalúa si la entrada coincide con el texto buscado y el filtro de categoría seleccionado.
    public func matches(query: String, filter: ClipboardHistoryFilter) -> Bool {
        switch filter {
        case .all:
            break
        case .text:
            guard kind == .text else { return false }
        case .images:
            guard kind == .image || imageFileName != nil else { return false }
        case .files:
            guard kind == .files else { return false }
        case .links:
            guard kind == .link else { return false }
        case .pinned:
            guard isPinned else { return false }
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return true }

        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        var searchableBlob = ""
        if let textContent {
            searchableBlob += " " + textContent.lowercased()
        }
        if !filePaths.isEmpty {
            searchableBlob += " " + filePaths.joined(separator: " ").lowercased()
        }
        if let sourceAppName {
            searchableBlob += " " + sourceAppName.lowercased()
        }
        if let w = imagePixelWidth, let h = imagePixelHeight {
            searchableBlob += " \(w)x\(h) \(w)×\(h) imagen image png captura screenshot"
        }
        switch kind {
        case .image:
            searchableBlob += " imagen image foto photo png captura"
        case .files:
            searchableBlob += " archivo file carpeta folder"
        case .link:
            searchableBlob += " enlace link url web http"
        case .text:
            searchableBlob += " texto text"
        }

        return tokens.allSatisfy { searchableBlob.contains($0) }
    }

    private func singleLinePreview(of text: String, maxLength: Int = 140) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        if collapsed.count <= maxLength {
            return collapsed
        }
        let idx = collapsed.index(collapsed.startIndex, offsetBy: maxLength)
        return String(collapsed[..<idx]) + "…"
    }

    /// Calcula un hash SHA-256 determinístico para deduplicar entradas idénticas.
    public static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
