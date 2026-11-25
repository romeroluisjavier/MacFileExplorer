import Foundation
import AppKit
import CoreImage
import ImageIO
import Observation

/// Gestor de portapapeles de archivos estilo Windows Explorer (`@Observable`).
/// Soporta "Copiar" (`Cmd+C`) y "Cortar" real (`Cmd+X` con atenuación visual del ítem y `moveItem` al pegar con `Cmd+V`).
@MainActor
@Observable
public final class ClipboardManager {

    /// Modos de copia de medios desde la Vista Rápida (imágenes y videos).
    public enum MediaCopyMode: Sendable {
        /// Copia tanto los píxeles de la imagen (PNG/TIFF) como la referencia del archivo (`.fileURL`).
        case imageAndFile
        /// Copia únicamente los píxeles de la imagen (PNG/TIFF) sin adjuntar el archivo.
        case imageOnly
        /// Copia únicamente la referencia del archivo (`.fileURL`).
        case fileOnly
    }

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
        ClipboardHistoryManager.shared.recordFileURLs(
            newPayload.urls,
            sourceAppName: "MacFileExplorer",
            sourceAppBundleID: "com.macfileexplorer.app"
        )
        ClipboardHistoryManager.shared.acknowledgeSystemPasteboardChange()
    }

    /// Copia una imagen desde Vista Rápida al portapapeles en el modo elegido:
    /// - `.imageAndFile`: escribe píxeles PNG/TIFF (respetando orientación EXIF y transparencia) + `.fileURL`,
    ///   funcionando tanto en chats/documentos (WhatsApp, Slack, Docs, Preview) como en carpetas (Finder/MacFileExplorer).
    /// - `.imageOnly`: escribe solo los píxeles PNG/TIFF de la imagen.
    /// - `.fileOnly`: escribe solo el archivo (`.fileURL`).
    @discardableResult
    public func copyImageMedia(
        _ url: URL,
        mode: MediaCopyMode = .imageAndFile,
        targetPasteboard: NSPasteboard = .general
    ) -> Bool {
        let standardized = url.standardizedFileURL
        let isSystemPasteboard = (targetPasteboard === NSPasteboard.general)

        if mode == .fileOnly {
            if isSystemPasteboard {
                copy([standardized])
            } else {
                targetPasteboard.clearContents()
                targetPasteboard.writeObjects([standardized as NSURL])
            }
            return true
        }

        let encoded = Self.loadUprightImagePasteboardData(from: standardized)
        let pbItem = NSPasteboardItem()

        if mode == .imageAndFile {
            pbItem.setString(standardized.absoluteString, forType: .fileURL)
        }
        if let pngData = encoded?.pngData {
            pbItem.setData(pngData, forType: .png)
        }
        if let tiffData = encoded?.tiffData {
            pbItem.setData(tiffData, forType: .tiff)
        }

        // Si por algún formato exótico no pudimos decodificar píxeles, garantizar al menos el archivo
        if encoded == nil {
            pbItem.setString(standardized.absoluteString, forType: .fileURL)
        }

        targetPasteboard.clearContents()
        let wrote = targetPasteboard.writeObjects([pbItem])

        if isSystemPasteboard {
            if mode == .imageAndFile || encoded == nil {
                self.payload = ClipboardPayload(urls: [standardized], mode: .copy)
                _ = ClipboardHistoryManager.shared.recordFileURLs(
                    [standardized],
                    sourceAppName: "MacFileExplorer",
                    sourceAppBundleID: "com.macfileexplorer.app"
                )
            } else {
                self.payload = nil
                if let image = encoded?.image {
                    _ = ClipboardHistoryManager.shared.recordImage(
                        image,
                        sourceAppName: "MacFileExplorer",
                        sourceAppBundleID: "com.macfileexplorer.app"
                    )
                }
            }
            ClipboardHistoryManager.shared.acknowledgeSystemPasteboardChange()
        }

        return wrote
    }

    private struct UprightImagePasteboardData {
        let pngData: Data
        let tiffData: Data?
        let image: NSImage
    }

    /// Decodifica una imagen desde disco aplicando su orientación EXIF y conservando transparencia alfa
    /// para generar representaciones PNG y TIFF listas para cualquier app de macOS.
    private static func loadUprightImagePasteboardData(from url: URL) -> UprightImagePasteboardData? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let rawCGImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            guard let fallbackImg = NSImage(contentsOf: url),
                  let tiff = fallbackImg.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                return nil
            }
            return UprightImagePasteboardData(pngData: png, tiffData: tiff, image: fallbackImg)
        }

        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let exifOrientation = (props?[kCGImagePropertyOrientation] as? NSNumber)?.int32Value ?? 1
        let uprightCGImage: CGImage
        if exifOrientation != 1 {
            let ciImage = CIImage(cgImage: rawCGImage).oriented(forExifOrientation: exifOrientation)
            let ciContext = CIContext(options: [.useSoftwareRenderer: false])
            uprightCGImage = ciContext.createCGImage(ciImage, from: ciImage.extent) ?? rawCGImage
        } else {
            uprightCGImage = rawCGImage
        }

        let bitmapRep = NSBitmapImageRep(cgImage: uprightCGImage)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return nil
        }
        let tiffData = bitmapRep.tiffRepresentation
        let nsImage = NSImage(
            cgImage: uprightCGImage,
            size: NSSize(width: uprightCGImage.width, height: uprightCGImage.height)
        )
        return UprightImagePasteboardData(pngData: pngData, tiffData: tiffData, image: nsImage)
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
