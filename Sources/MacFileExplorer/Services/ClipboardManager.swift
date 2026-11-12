import Foundation
import AppKit
import Observation

/// Gestor de portapapeles de archivos estilo Windows Explorer (`@Observable`).
/// Soporta "Copiar" (`Cmd+C`) y "Cortar" real (`Cmd+X` con atenuación visual del ítem y `moveItem` al pegar con `Cmd+V`).
@MainActor
@Observable
public final class ClipboardManager {

    /// Carga actual del portapapeles interno del explorador.
    public private(set) var payload: ClipboardPayload?

    public init() {}

    // MARK: - Consultas de Estado para la UI

    /// Indica si hay elementos listos para pegarse (internos o provenientes del `NSPasteboard` del sistema).
    public var hasItemsToPaste: Bool {
        if let payload, !payload.urls.isEmpty {
            return true
        }
        return !systemPasteboardFileURLs().isEmpty
    }

    /// Modo activo en el portapapeles (`.copy`, `.cut`, o `nil`).
    public var activeMode: ClipboardOperationMode? {
        payload?.mode
    }

    /// Devuelve `true` si el elemento fue marcado con "Cortar" (`Cmd+X`), permitiendo atenuar su icono/fila en la UI.
    public func isCut(_ item: FileItem) -> Bool {
        isCut(url: item.id)
    }

    /// Devuelve `true` si la URL estandarizada está pendiente de ser movida mediante `Cmd+X`.
    public func isCut(url: URL) -> Bool {
        guard let payload, payload.mode == .cut else { return false }
        return payload.urlSet.contains(url.standardizedFileURL)
    }

    // MARK: - Acciones del Portapapeles

    /// Registra una operación de "Copiar" (`Cmd+C`) y sincroniza las URLs con `NSPasteboard.general`.
    public func copy(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let newPayload = ClipboardPayload(urls: urls, mode: .copy)
        self.payload = newPayload
        writeToSystemPasteboard(newPayload.urls)
    }

    /// Registra una operación de "Cortar" estilo Windows (`Cmd+X`).
    /// Los elementos quedan marcados visualmente hasta que se ejecute `paste(into:)` o se cancele con `Escape`/nueva copia.
    public func cut(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let newPayload = ClipboardPayload(urls: urls, mode: .cut)
        self.payload = newPayload
        writeToSystemPasteboard(newPayload.urls)
    }

    /// Limpia el estado del portapapeles interno (por ejemplo, tras completar un `moveItem` o presionar `Escape`).
    public func clear() {
        payload = nil
    }

    /// Resultado detallado de un pegado (`Cmd+V`) para registrar la operación en el historial de Deshacer (`Cmd+Z`).
    public struct PasteResult: Sendable {
        public let mode: ClipboardOperationMode
        public let pairs: [FileMovePair]
        public var resultingURLs: [URL] { pairs.map(\.destination) }
    }

    /// Ejecuta la operación de pegado (`Cmd+V`) en el directorio de destino:
    /// - Si el modo es `.cut`, ejecuta `FileSystemService.moveItemPairs` y limpia el estado de corte.
    /// - Si el modo es `.copy` (o proviene del `NSPasteboard` externo), ejecuta `FileSystemService.copyItemPairs`.
    @discardableResult
    public func paste(
        into destinationDirectory: URL,
        using fileSystemService: FileSystemService
    ) async throws -> [URL] {
        try await pasteWithResult(into: destinationDirectory, using: fileSystemService).resultingURLs
    }

    /// Ejecuta el pegado devolviendo modo (`.copy`/`.cut`) y pares `(origen -> destino)` reales.
    public func pasteWithResult(
        into destinationDirectory: URL,
        using fileSystemService: FileSystemService
    ) async throws -> PasteResult {
        if let currentPayload = payload, !currentPayload.urls.isEmpty {
            switch currentPayload.mode {
            case .cut:
                let movedPairs = try await fileSystemService.moveItemPairs(
                    from: currentPayload.urls,
                    to: destinationDirectory
                )
                // Al completar el movimiento, limpiamos el estado de corte estilo Windows
                self.payload = nil
                return PasteResult(mode: .cut, pairs: movedPairs)

            case .copy:
                let copiedPairs = try await fileSystemService.copyItemPairs(
                    from: currentPayload.urls,
                    to: destinationDirectory
                )
                return PasteResult(mode: .copy, pairs: copiedPairs)
            }
        }

        // Fallback: si el usuario copió archivos desde Finder u otra app externa
        let externalURLs = systemPasteboardFileURLs()
        guard !externalURLs.isEmpty else {
            return PasteResult(mode: .copy, pairs: [])
        }
        let copiedPairs = try await fileSystemService.copyItemPairs(
            from: externalURLs,
            to: destinationDirectory
        )
        return PasteResult(mode: .copy, pairs: copiedPairs)
    }

    // MARK: - Integración con NSPasteboard

    private func writeToSystemPasteboard(_ urls: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }

    private func systemPasteboardFileURLs() -> [URL] {
        let pasteboard = NSPasteboard.general
        let classes: [AnyClass] = [NSURL.self]
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        guard let nsURLs = pasteboard.readObjects(forClasses: classes, options: options) as? [URL] else {
            return []
        }
        return nsURLs.map(\.standardizedFileURL)
    }
}
