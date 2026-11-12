import Foundation

/// Categoría del nodo en el panel lateral izquierdo (Navigation Pane).
public enum NavigationSectionKind: String, Sendable, Hashable {
    case quickAccess = "Acceso rápido"
    case volumes = "Este equipo"
    case directory = "Carpeta"
}

/// Carpetas importantes estándar de macOS configurables dentro de la sección "Acceso rápido".
public enum QuickAccessFolder: String, CaseIterable, Identifiable, Codable, Sendable, Hashable {
    case home
    case desktop
    case downloads
    case documents
    case applications
    case pictures
    case music
    case movies
    case trash

    public var id: String { rawValue }

    /// Conjunto predeterminado (coincide con las carpetas mostradas inicialmente en Acceso rápido).
    public static let defaultFolders: Set<QuickAccessFolder> = [
        .home, .desktop, .downloads, .documents, .applications, .pictures, .trash
    ]

    public var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .desktop: return "menubar.dock.rectangle"
        case .downloads: return "arrow.down.circle.fill"
        case .documents: return "doc.text.fill"
        case .applications: return "app.badge.fill"
        case .pictures: return "photo.fill"
        case .music: return "music.note"
        case .movies: return "film"
        case .trash: return "trash.fill"
        }
    }

    /// URL estandarizada del directorio en macOS.
    public var directoryURL: URL? {
        let fm = FileManager.default
        switch self {
        case .home:
            return fm.homeDirectoryForCurrentUser.standardizedFileURL
        case .desktop:
            return fm.urls(for: .desktopDirectory, in: .userDomainMask).first?.standardizedFileURL
        case .downloads:
            return fm.urls(for: .downloadsDirectory, in: .userDomainMask).first?.standardizedFileURL
        case .documents:
            return fm.urls(for: .documentDirectory, in: .userDomainMask).first?.standardizedFileURL
        case .applications:
            return URL(fileURLWithPath: "/Applications").standardizedFileURL
        case .pictures:
            return fm.urls(for: .picturesDirectory, in: .userDomainMask).first?.standardizedFileURL
        case .music:
            return fm.urls(for: .musicDirectory, in: .userDomainMask).first?.standardizedFileURL
        case .movies:
            return fm.urls(for: .moviesDirectory, in: .userDomainMask).first?.standardizedFileURL
        case .trash:
            return fm.urls(for: .trashDirectory, in: .userDomainMask).first?.standardizedFileURL
        }
    }

    /// Nombre base interno antes de localizar dinámicamente en UI.
    public var defaultTitle: String {
        switch self {
        case .home:
            let user = FileManager.default.homeDirectoryForCurrentUser.lastPathComponent
            return "Inicio (\(user))"
        case .desktop: return "Escritorio"
        case .downloads: return "Descargas"
        case .documents: return "Documentos"
        case .applications: return "Aplicaciones"
        case .pictures: return "Imágenes"
        case .music: return "Música"
        case .movies: return "Películas"
        case .trash: return "Papelera"
        }
    }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .home:
            let user = FileManager.default.homeDirectoryForCurrentUser.lastPathComponent
            return loc.text(es: "Inicio (\(user))", en: "Home (\(user))")
        case .desktop:
            return loc.text(es: "Escritorio", en: "Desktop")
        case .downloads:
            return loc.text(es: "Descargas", en: "Downloads")
        case .documents:
            return loc.text(es: "Documentos", en: "Documents")
        case .applications:
            return loc.text(es: "Aplicaciones", en: "Applications")
        case .pictures:
            return loc.text(es: "Imágenes", en: "Pictures")
        case .music:
            return loc.text(es: "Música", en: "Music")
        case .movies:
            return loc.text(es: "Películas", en: "Movies")
        case .trash:
            return loc.text(es: "Papelera", en: "Trash")
        }
    }
}

/// Representa un nodo dentro del árbol jerárquico del panel de navegación izquierdo.
/// La expansión de subcarpetas (`chevron`) se gestiona de forma independiente a la selección/navegación.
public struct NavigationNode: Identifiable, Hashable, Sendable {
    /// Identificador único compuesto por sección y ruta estandarizada para permitir que una misma carpeta
    /// exista tanto en "Acceso rápido" como dentro del árbol de "Este equipo" sin colisión de IDs en SwiftUI.
    public let id: String

    /// URL del directorio o volumen en el sistema de archivos.
    public let url: URL

    /// Nombre visible del nodo (ej. "Escritorio", "Descargas", "Macintosh HD").
    public let title: String

    /// Nombre del símbolo SF Symbol (ej. "desktopcomputer", "arrow.down.circle", "externaldrive").
    public let systemImage: String

    /// Sección a la que pertenece el nodo.
    public let section: NavigationSectionKind

    /// Indica si el nodo puede tener subcarpetas desplegables mediante chevron.
    public let isExpandable: Bool

    /// Indica si esta carpeta fue fijada manualmente por el usuario como favorita en Acceso rápido.
    public let isCustomQuickAccessFavorite: Bool

    public init(
        url: URL,
        title: String,
        systemImage: String = "folder.fill",
        section: NavigationSectionKind = .directory,
        isExpandable: Bool = true,
        isCustomQuickAccessFavorite: Bool = false
    ) {
        let standardized = url.standardizedFileURL
        self.id = "\(section.rawValue)::\(standardized.path(percentEncoded: false))"
        self.url = standardized
        self.title = title
        self.systemImage = systemImage
        self.section = section
        self.isExpandable = isExpandable
        self.isCustomQuickAccessFavorite = isCustomQuickAccessFavorite
    }
}
