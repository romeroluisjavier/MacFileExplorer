import Foundation

/// Modos de visualización del área principal de contenidos (estilo Windows 11 Explorer).
public enum ExplorerViewMode: String, CaseIterable, Identifiable, Sendable {
    case details = "Detalles"
    case largeIcons = "Iconos grandes"

    public var id: String { rawValue }

    /// Nombre del símbolo SF Symbol representativo para la barra de herramientas / vista.
    public var systemImage: String {
        switch self {
        case .details:
            return "list.bullet.rectangle"
        case .largeIcons:
            return "square.grid.2x2"
        }
    }
}

/// Modo de visualización de iconos por fila en la vista Lista / Detalles.
public enum ListIconDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case basic = "basic"
    case appIcon = "appIcon"
    case thumbnail = "thumbnail"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .basic:
            return "doc.plaintext"
        case .appIcon:
            return "app.badge.checkmark"
        case .thumbnail:
            return "photo.on.rectangle"
        }
    }
}
