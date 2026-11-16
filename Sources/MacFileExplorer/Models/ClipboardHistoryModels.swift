import AppKit
import Carbon
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

/// Cantidad de elementos recientes mostrados en el menú desplegable rápido (`⌃⌘V` estilo Maccy).
public enum ClipboardDropdownCountOption: Int, Codable, CaseIterable, Identifiable, Sendable {
    case ten = 10
    case fifteen = 15
    case twenty = 20
    case thirty = 30

    public var id: Int { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .ten:
            return loc.text(es: "Últimos 10 elementos (Predeterminado)", en: "Last 10 items (Default)")
        case .fifteen:
            return loc.text(es: "Últimos 15 elementos", en: "Last 15 items")
        case .twenty:
            return loc.text(es: "Últimos 20 elementos", en: "Last 20 items")
        case .thirty:
            return loc.text(es: "Últimos 30 elementos", en: "Last 30 items")
        }
    }
}

/// Modelo personalizable de combinación de teclas (código de tecla física + modificadores `⌃`, `⌥`, `⇧`, `⌘`)
/// compatible con registro global de hotkeys en macOS (`RegisterEventHotKey`) y eventos locales de `NSEvent`.
public struct ClipboardKeyShortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    public var command: Bool
    public var control: Bool
    public var option: Bool
    public var shift: Bool
    public var keyDisplayLabel: String
    public var isEnabled: Bool

    public init(
        keyCode: UInt16,
        command: Bool = false,
        control: Bool = false,
        option: Bool = false,
        shift: Bool = false,
        keyDisplayLabel: String,
        isEnabled: Bool = true
    ) {
        self.keyCode = keyCode
        self.command = command
        self.control = control
        self.option = option
        self.shift = shift
        self.keyDisplayLabel = keyDisplayLabel
        self.isEnabled = isEnabled
    }

    // MARK: - Atajos Predeterminados (Estilo Maccy del Usuario)

    /// `⌃⌘V` (`Ctrl + Cmd + V`): Abre el menú desplegable rápido de los últimos 10 ítems sin importar dónde estés en la Mac.
    public static let defaultQuickPasteDropdown = ClipboardKeyShortcut(
        keyCode: 9, // 'v'
        command: true,
        control: true,
        option: false,
        shift: false,
        keyDisplayLabel: "V"
    )

    /// `⇧⌘C` (`Shift + Cmd + C`): Abre el buscador completo del Historial del Portapapeles en MacFileExplorer.
    public static let defaultFullHistorySearch = ClipboardKeyShortcut(
        keyCode: 8, // 'c'
        command: true,
        control: false,
        option: false,
        shift: true,
        keyDisplayLabel: "C"
    )

    /// `⌥P` (`Option + P`): Fijar o desfijar el elemento seleccionado en el historial.
    public static let defaultPinItem = ClipboardKeyShortcut(
        keyCode: 35, // 'p'
        command: false,
        control: false,
        option: true,
        shift: false,
        keyDisplayLabel: "P"
    )

    /// `⌥⌫` (`Option + Backspace`): Eliminar el elemento seleccionado del historial.
    public static let defaultDeleteItem = ClipboardKeyShortcut(
        keyCode: 51, // Backspace
        command: false,
        control: false,
        option: true,
        shift: false,
        keyDisplayLabel: "⌫"
    )

    /// `⌥↵` (`Option + Enter`): Copiar / Pegar elemento seleccionado como texto plano sin formato.
    public static let defaultPlainTextCopy = ClipboardKeyShortcut(
        keyCode: 36, // Return
        command: false,
        control: false,
        option: true,
        shift: false,
        keyDisplayLabel: "↵"
    )

    /// `⌥⌘⌫` (`Option + Cmd + Backspace`): Limpiar todos los elementos no fijados del historial.
    public static let defaultClearHistory = ClipboardKeyShortcut(
        keyCode: 51, // Backspace
        command: true,
        control: false,
        option: true,
        shift: false,
        keyDisplayLabel: "⌫"
    )

    /// Representación visual estilo macOS (ej. `⌃⌘V`, `⇧⌘C`, `⌥P`, `⌥⌫`).
    public var displayString: String {
        guard isEnabled else { return "—" }
        var result = ""
        if control { result += "⌃" }
        if option { result += "⌥" }
        if shift { result += "⇧" }
        if command { result += "⌘" }
        result += keyDisplayLabel.uppercased()
        return result
    }

    /// Modificadores `NSEvent.ModifierFlags` correspondientes.
    public var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if command { flags.insert(.command) }
        if control { flags.insert(.control) }
        if option { flags.insert(.option) }
        if shift { flags.insert(.shift) }
        return flags
    }

    /// Modificadores de Carbon (`cmdKey`, `controlKey`, `optionKey`, `shiftKey`) para `RegisterEventHotKey`.
    public var carbonModifiers: UInt32 {
        var mods: UInt32 = 0
        if command { mods |= UInt32(cmdKey) }
        if shift { mods |= UInt32(shiftKey) }
        if option { mods |= UInt32(optionKey) }
        if control { mods |= UInt32(controlKey) }
        return mods
    }

    /// Verifica si un evento de teclado coincide con este atajo.
    public func matches(
        keyCode eventKeyCode: UInt16,
        charactersIgnoringModifiers: String?,
        flags: NSEvent.ModifierFlags
    ) -> Bool {
        guard isEnabled else { return false }
        let cleanFlags = flags.intersection([.command, .control, .option, .shift])
        guard cleanFlags == modifierFlags else { return false }
        if eventKeyCode == keyCode {
            return true
        }
        if let chars = charactersIgnoringModifiers?.uppercased(),
           !chars.isEmpty,
           chars == keyDisplayLabel.uppercased() {
            return true
        }
        return false
    }

    /// Construye un `ClipboardKeyShortcut` a partir de un `NSEvent` capturado en el grabador de atajos.
    public static func from(event: NSEvent) -> ClipboardKeyShortcut? {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        // Ignorar pulsaciones de solo modificadores
        let modifierOnlyKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        guard !modifierOnlyKeyCodes.contains(event.keyCode) else { return nil }
        guard !flags.isEmpty else { return nil }

        let label = Self.humanReadableKeyLabel(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers)
        return ClipboardKeyShortcut(
            keyCode: event.keyCode,
            command: flags.contains(.command),
            control: flags.contains(.control),
            option: flags.contains(.option),
            shift: flags.contains(.shift),
            keyDisplayLabel: label,
            isEnabled: true
        )
    }

    public static func humanReadableKeyLabel(keyCode: UInt16, characters: String?) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 36, 76: return "↵"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "Esc"
        case 117: return "⌦"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            if let chars = characters?.trimmingCharacters(in: .whitespacesAndNewlines), !chars.isEmpty {
                return chars.uppercased()
            }
            return "Key\(keyCode)"
        }
    }
}

/// Presets rápidos para el atajo de abrir el menú desplegable del portapapeles.
public enum ClipboardPopupShortcutPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case controlCommandV = "ctrl_cmd_v"
    case shiftCommandC = "shift_cmd_c"
    case optionCommandC = "opt_cmd_c"
    case optionCommandV = "opt_cmd_v"
    case controlOptionCommandV = "ctrl_opt_cmd_v"
    case disabled = "disabled"

    public var id: String { rawValue }

    public var badgeText: String {
        switch self {
        case .controlCommandV: return "⌃⌘V"
        case .shiftCommandC: return "⇧⌘C"
        case .optionCommandC: return "⌥⌘C"
        case .optionCommandV: return "⌥⌘V"
        case .controlOptionCommandV: return "⌃⌥⌘V"
        case .disabled: return ""
        }
    }

    public var keyShortcut: ClipboardKeyShortcut {
        switch self {
        case .controlCommandV:
            return .defaultQuickPasteDropdown
        case .shiftCommandC:
            return .defaultFullHistorySearch
        case .optionCommandC:
            return ClipboardKeyShortcut(keyCode: 8, command: true, control: false, option: true, shift: false, keyDisplayLabel: "C")
        case .optionCommandV:
            return ClipboardKeyShortcut(keyCode: 9, command: true, control: false, option: true, shift: false, keyDisplayLabel: "V")
        case .controlOptionCommandV:
            return ClipboardKeyShortcut(keyCode: 9, command: true, control: true, option: true, shift: false, keyDisplayLabel: "V")
        case .disabled:
            var disabled = ClipboardKeyShortcut.defaultQuickPasteDropdown
            disabled.isEnabled = false
            return disabled
        }
    }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .controlCommandV:
            return loc.text(es: "⌃⌘V (Pegar desde menú Maccy)", en: "⌃⌘V (Paste from Maccy menu)")
        case .shiftCommandC:
            return "⇧⌘C"
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

    public func matches(keyCode: UInt16, charactersIgnoringModifiers: String?, flags: NSEvent.ModifierFlags) -> Bool {
        keyShortcut.matches(keyCode: keyCode, charactersIgnoringModifiers: charactersIgnoringModifiers, flags: flags)
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

    /// Título estilo Maccy (con `⏎` para saltos de línea, igual que en la captura de referencia de Maccy).
    @MainActor
    public func maccyMenuTitle(maxLength: Int = 62, using loc: LocalizationManager = .shared) -> String {
        switch kind {
        case .image:
            if let text = textContent?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return maccyFormattedTextPreview(text, maxLength: maxLength)
            }
            if let w = imagePixelWidth, let h = imagePixelHeight, w > 0, h > 0 {
                return loc.text(es: "Imagen (\(w)×\(h) px)", en: "Image (\(w)×\(h) px)")
            }
            return loc.text(es: "Imagen", en: "Image")

        case .files:
            if filePaths.count == 1, let first = filePaths.first {
                return URL(fileURLWithPath: first).absoluteString
            }
            let names = filePaths.map { URL(fileURLWithPath: $0).lastPathComponent }.filter { !$0.isEmpty }
            guard let first = names.first else {
                return loc.text(es: "Archivos copiados", en: "Copied Files")
            }
            return loc.text(
                es: "\(first) y \(names.count - 1) más",
                en: "\(first) & \(names.count - 1) more"
            )

        case .link, .text:
            let raw = textContent ?? ""
            let preview = maccyFormattedTextPreview(raw, maxLength: maxLength)
            return preview.isEmpty ? loc.text(es: "(Texto vacío)", en: "(Empty text)") : preview
        }
    }

    /// Título resumido en una sola línea para mostrar en la barra lateral o en la lista principal.
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

    private func maccyFormattedTextPreview(_ text: String, maxLength: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let withNewlineGlyph = lines.joined(separator: "⏎")
        guard withNewlineGlyph.count > maxLength else { return withNewlineGlyph }
        let headCount = max(12, (maxLength - 3) * 2 / 3)
        let tailCount = max(8, maxLength - 3 - headCount)
        let head = withNewlineGlyph.prefix(headCount)
        let tail = withNewlineGlyph.suffix(tailCount)
        return "\(head)...\(tail)"
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
