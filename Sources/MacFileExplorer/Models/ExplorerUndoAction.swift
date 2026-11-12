import Foundation

/// Par origen → destino utilizado para ejecutar y revertir movimientos/restauraciones de archivos.
public struct FileMovePair: Sendable, Hashable {
    public let source: URL
    public let destination: URL

    public init(source: URL, destination: URL) {
        self.source = source.standardizedFileURL
        self.destination = destination.standardizedFileURL
    }
}

/// Tipos de acciones sobre el sistema de archivos reversibles con `Cmd+Z` / `Cmd+Shift+Z`.
public enum ExplorerUndoOperationKind: Sendable {
    public enum CreatedActionType: Sendable {
        case pasteCopy
        case dragCopy
        case newFolder
        case newFile
        case unarchive
    }

    /// Movimiento real (`Cmd+X` → `Cmd+V` o arrastrar y soltar para mover).
    case move(pairs: [FileMovePair])
    /// Elementos creados (pegar copia, arrastrar copia, nueva carpeta, nuevo archivo, descomprimir `.zip`).
    /// Al deshacer se envían a la Papelera; al rehacer se restauran desde la Papelera.
    case createdItems(urls: [URL], trashedURLs: [URL], actionType: CreatedActionType)
    /// Elementos enviados a la Papelera (`Delete`): `source` = ubicación original, `destination` = ruta en Papelera.
    case trash(pairs: [FileMovePair])
    /// Renombrado en línea (`F2` / `Enter`).
    case rename(oldURL: URL, newURL: URL)
}

/// Registro individual en la pila de Deshacer / Rehacer de `ExplorerViewModel`.
public struct ExplorerUndoEntry: Identifiable, Sendable {
    public let id: UUID
    public let kind: ExplorerUndoOperationKind

    public init(id: UUID = UUID(), kind: ExplorerUndoOperationKind) {
        self.id = id
        self.kind = kind
    }

    @MainActor
    public func actionDisplayName(using loc: LocalizationManager) -> String {
        switch kind {
        case .move:
            return loc.text(es: "Mover", en: "Move")
        case .createdItems(_, _, let actionType):
            switch actionType {
            case .pasteCopy:
                return loc.text(es: "Pegar", en: "Paste")
            case .dragCopy:
                return loc.text(es: "Copiar", en: "Copy")
            case .newFolder:
                return loc.text(es: "Nueva carpeta", en: "New folder")
            case .newFile:
                return loc.text(es: "Nuevo archivo", en: "New file")
            case .unarchive:
                return loc.text(es: "Desarchivar", en: "Unarchive")
            }
        case .trash:
            return loc.text(es: "Eliminar", en: "Delete")
        case .rename:
            return loc.text(es: "Renombrar", en: "Rename")
        }
    }
}
