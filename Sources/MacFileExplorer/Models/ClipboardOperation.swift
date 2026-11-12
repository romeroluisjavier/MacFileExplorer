import Foundation

/// Tipo de operación almacenada en el portapapeles del explorador.
public enum ClipboardOperationMode: String, Sendable, Equatable {
    /// Copiar archivos/carpetas (`Cmd+C`). Duplica los elementos al pegar.
    case copy
    /// Cortar archivos/carpetas (`Cmd+X`). Atenúa visualmente los elementos de origen y ejecuta `moveItem` al pegar (`Cmd+V`).
    case cut
}

/// Carga útil inmutable del portapapeles de archivos.
public struct ClipboardPayload: Sendable, Equatable {
    /// URLs estandarizadas de los elementos copiados o cortados.
    public let urls: [URL]

    /// Conjunto de URLs para consulta en O(1) durante el renderizado (ej. atenuar ítems cortados).
    public let urlSet: Set<URL>

    /// Modo de operación (`.copy` o `.cut`).
    public let mode: ClipboardOperationMode

    /// Marca temporal de la operación.
    public let timestamp: Date

    public init(urls: [URL], mode: ClipboardOperationMode, timestamp: Date = Date()) {
        let standardized = urls.map(\.standardizedFileURL)
        self.urls = standardized
        self.urlSet = Set(standardized)
        self.mode = mode
        self.timestamp = timestamp
    }
}
