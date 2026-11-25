import Foundation
import Observation

/// Configuración de carpeta destino en Google Drive asociada a una cuenta de Google específica.
public struct GoogleDriveFolderDestination: Codable, Equatable, Sendable {
    /// ID de carpeta en Google Drive (ej. `1AbCdEf...`). Si es `nil`, usa la raíz de *Mi unidad*.
    public var folderID: String?
    /// Nombre legible mostrado al usuario (ej. `"Documentos MacFileExplorer"` o `"Mi unidad"`).
    public var folderName: String
    /// URL completa de referencia de la carpeta si fue pegada o capturada desde Drive.
    public var folderURLString: String?

    public init(folderID: String? = nil, folderName: String = "", folderURLString: String? = nil) {
        self.folderID = folderID
        self.folderName = folderName
        self.folderURLString = folderURLString
    }

    public var targetURL: URL {
        if let folderID, !folderID.isEmpty,
           let url = URL(string: "https://drive.google.com/drive/u/0/folders/\(folderID)") {
            return url
        }
        return URL(string: "https://drive.google.com/drive/u/0/my-drive")!
    }
}

/// Preferencias persistentes para la función "Send to Drive" (carpeta destino por cuenta y destino de apertura).
@MainActor
@Observable
public final class GoogleDriveUploadPreferences {
    public static let shared = GoogleDriveUploadPreferences()

    private let defaults: UserDefaults
    private var isBootstrapping = false

    private enum Keys {
        static let foldersByAccount = "com.macfileexplorer.driveUpload.foldersByAccount.v1"
        static let defaultAccountID = "com.macfileexplorer.driveUpload.defaultAccountID.v1"
        static let openInExternalChrome = "com.macfileexplorer.driveUpload.openInExternalChrome.v1"
    }

    /// Carpeta destino configurada por `GoogleAccount.id.uuidString`.
    public var foldersByAccountID: [String: GoogleDriveFolderDestination] = [:] {
        didSet {
            guard !isBootstrapping else { return }
            if let data = try? JSONEncoder().encode(foldersByAccountID) {
                defaults.set(data, forKey: Keys.foldersByAccount)
            }
        }
    }

    /// Cuenta de Google predeterminada cuando el usuario tiene más de una logueada.
    public var defaultAccountID: UUID? = nil {
        didSet {
            guard !isBootstrapping else { return }
            if let defaultAccountID {
                defaults.set(defaultAccountID.uuidString, forKey: Keys.defaultAccountID)
            } else {
                defaults.removeObject(forKey: Keys.defaultAccountID)
            }
        }
    }

    /// Si es `false` (por defecto), abre Google Sheets/Docs/Slides en una pestaña dentro de `MacFileExplorer`
    /// usando la misma sesión de Gmail logueada. Si es `true`, lo abre en Google Chrome externo.
    public var openInExternalChrome: Bool = false {
        didSet {
            guard !isBootstrapping else { return }
            defaults.set(openInExternalChrome, forKey: Keys.openInExternalChrome)
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isBootstrapping = true
        defer { self.isBootstrapping = false }

        if let data = defaults.data(forKey: Keys.foldersByAccount),
           let decoded = try? JSONDecoder().decode([String: GoogleDriveFolderDestination].self, from: data) {
            self.foldersByAccountID = decoded
        }
        if let rawID = defaults.string(forKey: Keys.defaultAccountID) {
            self.defaultAccountID = UUID(uuidString: rawID)
        }
        self.openInExternalChrome = defaults.object(forKey: Keys.openInExternalChrome) as? Bool ?? false
    }

    public func destination(for accountID: UUID) -> GoogleDriveFolderDestination {
        foldersByAccountID[accountID.uuidString] ?? GoogleDriveFolderDestination()
    }

    public func displayFolderName(for accountID: UUID, using loc: LocalizationManager = .shared) -> String {
        let dest = destination(for: accountID)
        if !dest.folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return dest.folderName
        }
        if let id = dest.folderID, !id.isEmpty {
            return loc.text(es: "Carpeta (\(id.prefix(8))…)", en: "Folder (\(id.prefix(8))…)")
        }
        return loc.text(es: "Mi unidad (raíz)", en: "My Drive (root)")
    }

    @discardableResult
    public func setFolder(
        fromUserInput rawInput: String,
        customName: String?,
        for accountID: UUID
    ) -> Bool {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.lowercased().contains("/my-drive") {
            foldersByAccountID.removeValue(forKey: accountID.uuidString)
            return true
        }
        guard let parsedID = Self.extractFolderID(from: trimmed) else {
            return false
        }
        let cleanName = (customName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let dest = GoogleDriveFolderDestination(
            folderID: parsedID,
            folderName: cleanName,
            folderURLString: "https://drive.google.com/drive/u/0/folders/\(parsedID)"
        )
        foldersByAccountID[accountID.uuidString] = dest
        return true
    }

    /// Captura directamente la carpeta abierta actualmente en una pestaña de Google Drive de `MacFileExplorer`.
    @discardableResult
    public func setFolderFromLiveDriveTab(url: URL, pageTitle: String?, for accountID: UUID) -> Bool {
        guard let host = url.host?.lowercased(), host == "drive.google.com" else { return false }
        let cleanedTitle = Self.cleanDriveFolderTitle(from: pageTitle)
        if let folderID = Self.extractFolderID(from: url.absoluteString) {
            foldersByAccountID[accountID.uuidString] = GoogleDriveFolderDestination(
                folderID: folderID,
                folderName: cleanedTitle,
                folderURLString: "https://drive.google.com/drive/u/0/folders/\(folderID)"
            )
            return true
        }
        // Raíz de Mi unidad
        let lowerPath = url.path.lowercased()
        if lowerPath.contains("/my-drive") || lowerPath == "/drive" || lowerPath == "/drive/" || lowerPath.hasPrefix("/drive/u/") {
            foldersByAccountID[accountID.uuidString] = GoogleDriveFolderDestination(
                folderID: nil,
                folderName: "",
                folderURLString: "https://drive.google.com/drive/u/0/my-drive"
            )
            return true
        }
        return false
    }

    /// Extrae el `folderID` desde una URL de Google Drive o un ID directo.
    public static func extractFolderID(from rawInput: String) -> String? {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Caso 1: URL completa tipo `https://drive.google.com/drive/u/0/folders/<ID>?...` o Shared Drive
        if let url = URL(string: trimmed), let host = url.host?.lowercased(), host.contains("drive.google.com") {
            let comps = url.pathComponents
            for marker in ["folders", "shared-drives"] {
                if let idx = comps.firstIndex(of: marker), idx + 1 < comps.count {
                    let candidate = comps[idx + 1]
                    if isPlausibleDriveID(candidate) { return candidate }
                }
            }
            if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
               let idParam = queryItems.first(where: { $0.name == "id" })?.value,
               isPlausibleDriveID(idParam) {
                return idParam
            }
            return nil
        }

        // Caso 2: El usuario pegó directamente el ID de la carpeta
        if isPlausibleDriveID(trimmed) {
            return trimmed
        }
        return nil
    }

    private static func isPlausibleDriveID(_ candidate: String) -> Bool {
        guard candidate.count >= 10 && candidate.count <= 128 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return candidate.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    public static func cleanDriveFolderTitle(from rawTitle: String?) -> String {
        guard var t = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else {
            return ""
        }
        for suffix in [" - Google Drive", " – Google Drive", " — Google Drive"] {
            if t.hasSuffix(suffix) {
                t = String(t.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let lower = t.lowercased()
        if lower == "my drive" || lower == "mi unidad" || lower == "google drive" {
            return ""
        }
        return t
    }
}
