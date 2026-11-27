import AppKit
@preconcurrency import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

public enum QuickActionImageFormat: String, CaseIterable, Identifiable, Sendable {
    case jpg
    case png

    public var id: String { rawValue }

    public var fileExtension: String { rawValue }

    public var utType: UTType {
        switch self {
        case .jpg: return .jpeg
        case .png: return .png
        }
    }

    public var displayTitle: String {
        switch self {
        case .jpg: return "JPG (.jpg)"
        case .png: return "PNG (.png)"
        }
    }
}

public enum QuickActionImageRotation: Sendable {
    case right90
    case left90
    case rotate180
}

public struct QuickActionImageConvertOptions: Sendable {
    public var format: QuickActionImageFormat = .jpg
    public var quality: Double = 0.85
    public var dpi: Int = 72
    public var keepOriginalSize: Bool = true
    public var targetWidth: Int = 1920
    public var useTargetMaxSizeMB: Bool = false
    public var targetMaxSizeMB: Double = 1.0

    public init() {}
}

public enum QuickActionVideoQuality: String, CaseIterable, Identifiable, Sendable {
    case highest
    case medium
    case low

    public var id: String { rawValue }

    public var avPreset: String {
        switch self {
        case .highest: return AVAssetExportPreset1920x1080
        case .medium: return AVAssetExportPreset1280x720
        case .low: return AVAssetExportPreset960x540
        }
    }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .highest: return loc.text(es: "Alta (1080p)", en: "High (1080p)")
        case .medium: return loc.text(es: "Media (720p)", en: "Medium (720p)")
        case .low: return loc.text(es: "Ligera (540p)", en: "Low (540p)")
        }
    }
}

public struct QuickActionVideoConvertOptions: Sendable {
    public var quality: QuickActionVideoQuality = .highest
    public var useTargetMaxSizeMB: Bool = false
    public var targetMaxSizeMB: Double = 10.0

    public init() {}
}

public enum QuickActionsService {

    private static func localizedText(es: String, en: String) -> String {
        LocalizationManager.currentLanguageIsSpanish() ? es : en
    }

    public static let supportedImageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "webp", "tiff", "tif", "bmp", "gif", "avif"
    ]

    public static let supportedVideoExtensions: Set<String> = [
        "mov", "mp4", "m4v", "avi", "mkv"
    ]

    public static func isImageURL(_ url: URL) -> Bool {
        supportedImageExtensions.contains(url.pathExtension.lowercased())
    }

    public static func isVideoURL(_ url: URL) -> Bool {
        supportedVideoExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: - Imágenes: Conversión con Calidad, PPP (DPI), Ancho y Peso en MB

    public static func convertImages(
        _ urls: [URL],
        options: QuickActionImageConvertOptions
    ) async throws -> [URL] {
        var results: [URL] = []
        for url in urls {
            let outputURL = try await Task.detached(priority: .userInitiated) {
                try convertSingleImage(url: url, options: options)
            }.value
            results.append(outputURL)
        }
        return results
    }

    private static func convertSingleImage(
        url: URL,
        options: QuickActionImageConvertOptions
    ) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let originalCGImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(domain: "QuickActionsService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: localizedText(
                    es: "No se pudo leer la imagen \(url.lastPathComponent).",
                    en: "Could not read image \(url.lastPathComponent)."
                )
            ])
        }

        var workingImage = originalCGImage
        if !options.keepOriginalSize, options.targetWidth > 0, originalCGImage.width > 0 {
            let targetW = options.targetWidth
            if targetW != originalCGImage.width {
                let scale = Double(targetW) / Double(originalCGImage.width)
                let targetH = max(1, Int((Double(originalCGImage.height) * scale).rounded()))
                if let resized = resizeCGImage(originalCGImage, width: targetW, height: targetH) {
                    workingImage = resized
                }
            }
        }

        let targetBytes: Int? = options.useTargetMaxSizeMB && options.targetMaxSizeMB > 0
            ? Int(options.targetMaxSizeMB * 1_048_576.0)
            : nil

        let outputData: Data
        if let targetBytes {
            outputData = try encodeImageWithinByteLimit(
                workingImage,
                format: options.format,
                initialQuality: options.quality,
                dpi: options.dpi,
                maxBytes: targetBytes
            )
        } else {
            outputData = try encodeImage(
                workingImage,
                format: options.format,
                quality: options.quality,
                dpi: options.dpi
            )
        }

        let baseName = url.deletingPathExtension().lastPathComponent
        let destURL = uniqueDestinationURL(
            in: url.deletingLastPathComponent(),
            baseName: baseName,
            extension: options.format.fileExtension
        )
        try outputData.write(to: destURL, options: .atomic)
        return destURL
    }

    private static func encodeImageWithinByteLimit(
        _ image: CGImage,
        format: QuickActionImageFormat,
        initialQuality: Double,
        dpi: Int,
        maxBytes: Int
    ) throws -> Data {
        if format == .jpg {
            var low = 0.05
            var high = max(0.1, min(1.0, initialQuality))
            var bestData = try encodeImage(image, format: .jpg, quality: low, dpi: dpi)
            if bestData.count <= maxBytes {
                for _ in 0..<7 {
                    let mid = (low + high) / 2.0
                    let candidate = try encodeImage(image, format: .jpg, quality: mid, dpi: dpi)
                    if candidate.count <= maxBytes {
                        bestData = candidate
                        low = mid
                    } else {
                        high = mid
                    }
                }
                return bestData
            }
        }

        // Si aún supera el límite (o es PNG), reducir dimensiones progresivamente hasta cumplir el peso esperado
        var currentImage = image
        for _ in 0..<6 {
            let candidate = try encodeImage(currentImage, format: format, quality: format == .jpg ? 0.65 : 1.0, dpi: dpi)
            if candidate.count <= maxBytes || currentImage.width <= 120 {
                return candidate
            }
            let nextW = max(100, Int(Double(currentImage.width) * 0.75))
            let nextH = max(100, Int(Double(currentImage.height) * 0.75))
            guard let smaller = resizeCGImage(currentImage, width: nextW, height: nextH) else {
                return candidate
            }
            currentImage = smaller
        }
        return try encodeImage(currentImage, format: format, quality: 0.5, dpi: dpi)
    }

    private static func encodeImage(
        _ image: CGImage,
        format: QuickActionImageFormat,
        quality: Double,
        dpi: Int
    ) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, format.utType.identifier as CFString, 1, nil) else {
            throw NSError(domain: "QuickActionsService", code: 2, userInfo: [
                NSLocalizedDescriptionKey: localizedText(
                    es: "No se pudo crear el destino de imagen.",
                    en: "Could not create image destination."
                )
            ])
        }

        let clampedQuality = max(0.05, min(1.0, quality))
        let resolvedDPI = max(1, dpi)
        var props: [CFString: Any] = [
            kCGImagePropertyDPIWidth: resolvedDPI,
            kCGImagePropertyDPIHeight: resolvedDPI
        ]
        if format == .jpg {
            props[kCGImageDestinationLossyCompressionQuality] = clampedQuality
        }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "QuickActionsService", code: 3, userInfo: [
                NSLocalizedDescriptionKey: localizedText(
                    es: "No se pudo codificar la imagen.",
                    en: "Could not encode image."
                )
            ])
        }
        return data as Data
    }

    private static func resizeCGImage(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    // MARK: - Imágenes: Rotar (90° Derecha, 90° Izquierda, 180°)

    public static func rotateImages(
        _ urls: [URL],
        rotation: QuickActionImageRotation
    ) async throws -> [URL] {
        var results: [URL] = []
        for url in urls {
            let updatedURL = try await Task.detached(priority: .userInitiated) {
                try rotateSingleImageInPlace(url: url, rotation: rotation)
            }.value
            results.append(updatedURL)
        }
        return results
    }

    private static func rotateSingleImageInPlace(
        url: URL,
        rotation: QuickActionImageRotation
    ) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(domain: "QuickActionsService", code: 4, userInfo: [
                NSLocalizedDescriptionKey: localizedText(
                    es: "No se pudo leer la imagen \(url.lastPathComponent).",
                    en: "Could not read image \(url.lastPathComponent)."
                )
            ])
        }

        let origW = cgImage.width
        let origH = cgImage.height
        let newW = (rotation == .rotate180) ? origW : origH
        let newH = (rotation == .rotate180) ? origH : origW

        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: newW,
            height: newH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "QuickActionsService", code: 5, userInfo: [
                NSLocalizedDescriptionKey: localizedText(
                    es: "No se pudo rotar la imagen.",
                    en: "Could not rotate image."
                )
            ])
        }

        ctx.translateBy(x: CGFloat(newW) / 2.0, y: CGFloat(newH) / 2.0)
        switch rotation {
        case .right90:
            ctx.rotate(by: -.pi / 2.0)
        case .left90:
            ctx.rotate(by: .pi / 2.0)
        case .rotate180:
            ctx.rotate(by: .pi)
        }
        ctx.draw(cgImage, in: CGRect(x: -CGFloat(origW) / 2.0, y: -CGFloat(origH) / 2.0, width: CGFloat(origW), height: CGFloat(origH)))

        guard let rotatedImage = ctx.makeImage() else {
            throw NSError(domain: "QuickActionsService", code: 6, userInfo: [
                NSLocalizedDescriptionKey: localizedText(
                    es: "Error al generar la imagen rotada.",
                    en: "Failed to generate rotated image."
                )
            ])
        }

        let ext = url.pathExtension.lowercased()
        let format: QuickActionImageFormat = (ext == "png") ? .png : .jpg
        let data = try encodeImage(rotatedImage, format: format, quality: 0.92, dpi: 72)
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Imágenes: Eliminar Fondo (PNG con Transparencia)

    /// Elimina el fondo de las imágenes indicadas utilizando Vision (`VNGenerateForegroundInstanceMaskRequest`)
    /// y guarda cada resultado como un archivo nuevo en formato PNG con fondo transparente (`<nombre>_no_bg.png`).
    public static func removeBackgroundFromImages(
        _ urls: [URL],
        onFileProcessed: (@Sendable (Int, Int) async -> Void)? = nil
    ) async throws -> [URL] {
        let imageURLs = urls.filter { isImageURL($0) }
        var createdURLs: [URL] = []
        createdURLs.reserveCapacity(imageURLs.count)
        let total = imageURLs.count

        for (index, url) in imageURLs.enumerated() {
            let outputURL = try await Task.detached(priority: .userInitiated) {
                try removeBackgroundFromSingleImage(at: url)
            }.value
            createdURLs.append(outputURL)
            if let onFileProcessed {
                await onFileProcessed(index + 1, total)
            }
        }
        return createdURLs
    }

    private static func removeBackgroundFromSingleImage(at url: URL) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let originalCGImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(domain: "QuickActionsService", code: 30, userInfo: [
                NSLocalizedDescriptionKey: localizedText(
                    es: "No se pudo leer la imagen \(url.lastPathComponent).",
                    en: "Could not read image \(url.lastPathComponent)."
                )
            ])
        }

        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let exifOrientation = (props?[kCGImagePropertyOrientation] as? NSNumber)?.int32Value ?? 1
        let dpiValue = (props?[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72.0
        let resolvedDPI = max(1, Int(dpiValue.rounded()))

        var workingCIImage = CIImage(cgImage: originalCGImage)
        if exifOrientation != 1 {
            workingCIImage = workingCIImage.oriented(forExifOrientation: exifOrientation)
        }

        let handler = VNImageRequestHandler(ciImage: workingCIImage, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])

        guard let observation = request.results?.first,
              !observation.allInstances.isEmpty else {
            throw NSError(domain: "QuickActionsService", code: 31, userInfo: [
                NSLocalizedDescriptionKey: localizedText(
                    es: "No se detectó un objeto o persona principal para separar del fondo en \(url.lastPathComponent).",
                    en: "No main subject or person was detected to separate from the background in \(url.lastPathComponent)."
                )
            ])
        }

        let maskedPixelBuffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances,
            from: handler,
            croppedToInstancesExtent: false
        )

        let maskedCIImage = CIImage(cvPixelBuffer: maskedPixelBuffer)
        let targetColorSpace: CGColorSpace
        if let cgCS = originalCGImage.colorSpace, cgCS.model == .rgb {
            targetColorSpace = cgCS
        } else {
            targetColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        }

        let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        guard let outputCGImage = ciContext.createCGImage(
            maskedCIImage,
            from: maskedCIImage.extent,
            format: .RGBA8,
            colorSpace: targetColorSpace
        ) else {
            throw NSError(domain: "QuickActionsService", code: 32, userInfo: [
                NSLocalizedDescriptionKey: localizedText(
                    es: "No se pudo generar el PNG con transparencia para \(url.lastPathComponent).",
                    en: "Could not generate transparent PNG for \(url.lastPathComponent)."
                )
            ])
        }

        let pngData = try encodeImage(outputCGImage, format: .png, quality: 1.0, dpi: resolvedDPI)
        let destURL = uniqueDestinationURL(
            in: url.deletingLastPathComponent(),
            baseName: "\(url.deletingPathExtension().lastPathComponent)_no_bg",
            extension: "png"
        )
        try pngData.write(to: destURL, options: .atomic)
        return destURL
    }

    // MARK: - Videos: Convertir MOV -> MP4, Trim y Eliminar Audio

    public static func convertVideosToMP4(
        _ urls: [URL],
        options: QuickActionVideoConvertOptions
    ) async throws -> [URL] {
        var results: [URL] = []
        for url in urls {
            let asset = AVURLAsset(url: url)
            let destURL = uniqueDestinationURL(
                in: url.deletingLastPathComponent(),
                baseName: url.deletingPathExtension().lastPathComponent,
                extension: "mp4"
            )
            guard let session = AVAssetExportSession(asset: asset, presetName: options.quality.avPreset) else {
                throw NSError(domain: "QuickActionsService", code: 10, userInfo: [
                    NSLocalizedDescriptionKey: localizedText(
                        es: "No se pudo inicializar la exportación de video para \(url.lastPathComponent).",
                        en: "Could not initialize video export for \(url.lastPathComponent)."
                    )
                ])
            }
            session.outputURL = destURL
            session.outputFileType = .mp4
            session.shouldOptimizeForNetworkUse = true
            if options.useTargetMaxSizeMB && options.targetMaxSizeMB > 0 {
                session.fileLengthLimit = Int64(options.targetMaxSizeMB * 1_048_576.0)
            }
            try await runExportSession(session)
            results.append(destURL)
        }
        return results
    }

    public static func trimVideo(
        _ url: URL,
        startSeconds: Double,
        endSeconds: Double,
        fadeInSeconds: Double = 0.0,
        fadeOutSeconds: Double = 0.0
    ) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let ext = url.pathExtension.lowercased() == "mov" ? "mov" : "mp4"
        let fileType: AVFileType = (ext == "mov") ? .mov : .mp4
        let destURL = uniqueDestinationURL(
            in: url.deletingLastPathComponent(),
            baseName: "\(url.deletingPathExtension().lastPathComponent)_trim",
            extension: ext
        )

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "QuickActionsService", code: 11, userInfo: [
                NSLocalizedDescriptionKey: localizedText(
                    es: "No se pudo inicializar el recorte de video.",
                    en: "Could not initialize video trim."
                )
            ])
        }
        let start = CMTime(seconds: max(0, startSeconds), preferredTimescale: 1000)
        let end = CMTime(seconds: max(startSeconds + 0.05, endSeconds), preferredTimescale: 1000)
        let trimRange = CMTimeRange(start: start, end: end)
        session.timeRange = trimRange
        session.outputURL = destURL
        session.outputFileType = fileType
        session.shouldOptimizeForNetworkUse = true

        if (fadeInSeconds > 0 || fadeOutSeconds > 0),
           let videoTrack = try? await asset.loadTracks(withMediaType: .video).first {
            let naturalSize = (try? await videoTrack.load(.naturalSize)) ?? CGSize(width: 1920, height: 1080)
            let transform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
            let transformedSize = naturalSize.applying(transform)
            let renderSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))

            let videoComposition = AVMutableVideoComposition()
            videoComposition.renderSize = renderSize.width > 0 && renderSize.height > 0 ? renderSize : CGSize(width: 1920, height: 1080)
            videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = trimRange

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            layerInstruction.setTransform(transform, at: start)

            let clipDuration = CMTimeGetSeconds(trimRange.duration)
            if fadeInSeconds > 0 {
                let actualFadeIn = min(fadeInSeconds, clipDuration * 0.45)
                let fadeInEnd = CMTimeAdd(start, CMTime(seconds: actualFadeIn, preferredTimescale: 1000))
                layerInstruction.setOpacityRamp(
                    fromStartOpacity: 0.0,
                    toEndOpacity: 1.0,
                    timeRange: CMTimeRange(start: start, end: fadeInEnd)
                )
            }
            if fadeOutSeconds > 0 {
                let actualFadeOut = min(fadeOutSeconds, clipDuration * 0.45)
                let fadeOutStart = CMTimeSubtract(end, CMTime(seconds: actualFadeOut, preferredTimescale: 1000))
                layerInstruction.setOpacityRamp(
                    fromStartOpacity: 1.0,
                    toEndOpacity: 0.0,
                    timeRange: CMTimeRange(start: fadeOutStart, end: end)
                )
            }

            instruction.layerInstructions = [layerInstruction]
            videoComposition.instructions = [instruction]
            session.videoComposition = videoComposition
        }

        try await runExportSession(session)
        return destURL
    }

    public static func removeAudioFromVideos(_ urls: [URL]) async throws -> [URL] {
        var results: [URL] = []
        for url in urls {
            let asset = AVURLAsset(url: url)
            let composition = AVMutableComposition()
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let sourceVideoTrack = videoTracks.first,
                  let compVideoTrack = composition.addMutableTrack(
                      withMediaType: .video,
                      preferredTrackID: kCMPersistentTrackID_Invalid
                  ) else {
                throw NSError(domain: "QuickActionsService", code: 12, userInfo: [
                    NSLocalizedDescriptionKey: localizedText(
                        es: "El archivo \(url.lastPathComponent) no contiene pista de video.",
                        en: "The file \(url.lastPathComponent) does not contain a video track."
                    )
                ])
            }
            let duration = try await asset.load(.duration)
            let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
            try compVideoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: sourceVideoTrack,
                at: .zero
            )
            compVideoTrack.preferredTransform = preferredTransform

            let ext = url.pathExtension.lowercased() == "mov" ? "mov" : "mp4"
            let fileType: AVFileType = (ext == "mov") ? .mov : .mp4
            let destURL = uniqueDestinationURL(
                in: url.deletingLastPathComponent(),
                baseName: "\(url.deletingPathExtension().lastPathComponent)_sin_audio",
                extension: ext
            )

            guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
                throw NSError(domain: "QuickActionsService", code: 13, userInfo: [
                    NSLocalizedDescriptionKey: localizedText(
                        es: "No se pudo exportar el video sin audio.",
                        en: "Could not export video without audio."
                    )
                ])
            }
            session.outputURL = destURL
            session.outputFileType = fileType
            session.shouldOptimizeForNetworkUse = true
            try await runExportSession(session)
            results.append(destURL)
        }
        return results
    }

    private static func runExportSession(_ session: AVAssetExportSession) async throws {
        await session.export()
        if let error = session.error {
            throw error
        }
        if session.status != .completed {
            throw NSError(domain: "QuickActionsService", code: 14, userInfo: [
                NSLocalizedDescriptionKey: localizedText(
                    es: "La exportación de video no se completó correctamente.",
                    en: "Video export did not complete successfully."
                )
            ])
        }
    }

    public static let supportedPDFExtensions: Set<String> = ["pdf"]

    public static func isPDFURL(_ url: URL) -> Bool {
        supportedPDFExtensions.contains(url.pathExtension.lowercased())
    }

    public static func supportsPrivacyStripper(_ url: URL) -> Bool {
        isImageURL(url) || isVideoURL(url) || isPDFURL(url)
    }

    // MARK: - Limpiador de Metadatos (Privacy Stripper: Imágenes, Videos y PDFs)

    /// Elimina metadatos sensibles (GPS, datos de cámara/lente, autor, software y fechas personales)
    /// de imágenes, videos o PDFs, generando copias limpias `<nombre>_clean.<ext>` listas para compartir.
    public static func stripMetadata(
        from urls: [URL],
        onFileProcessed: (@Sendable (Int, Int) async -> Void)? = nil
    ) async throws -> [URL] {
        var cleanedURLs: [URL] = []
        cleanedURLs.reserveCapacity(urls.count)
        let total = urls.count

        for (index, url) in urls.enumerated() {
            let outputURL: URL
            if isImageURL(url) {
                outputURL = try await Task.detached(priority: .userInitiated) {
                    try stripImageMetadata(at: url)
                }.value
            } else if isVideoURL(url) {
                outputURL = try await stripVideoMetadata(at: url)
            } else if isPDFURL(url) {
                outputURL = try await Task.detached(priority: .userInitiated) {
                    try stripPDFMetadata(at: url)
                }.value
            } else {
                continue
            }
            cleanedURLs.append(outputURL)
            if let onFileProcessed {
                await onFileProcessed(index + 1, total)
            }
        }
        return cleanedURLs
    }

    private static func stripImageMetadata(at url: URL) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let originalImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(domain: "QuickActionsService", code: 20, userInfo: [
                NSLocalizedDescriptionKey: localizedText(
                    es: "No se pudo leer la imagen \(url.lastPathComponent).",
                    en: "Could not read image \(url.lastPathComponent)."
                )
            ])
        }

        // Hornear orientación EXIF en los píxeles para eliminar {TIFF}/{Exif}/{GPS}/{IPTC} sin girar la foto
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let exifOrientation = (props?[kCGImagePropertyOrientation] as? NSNumber)?.int32Value ?? 1
        let uprightImage: CGImage
        if exifOrientation != 1 {
            let ciImage = CIImage(cgImage: originalImage).oriented(forExifOrientation: exifOrientation)
            let ciContext = CIContext(options: [.useSoftwareRenderer: false])
            uprightImage = ciContext.createCGImage(ciImage, from: ciImage.extent) ?? originalImage
        } else {
            uprightImage = originalImage
        }

        let ext = url.pathExtension.lowercased()
        let (targetUTType, targetExt): (UTType, String) = switch ext {
        case "png": (.png, "png")
        case "heic": (.heic, "heic")
        case "tiff", "tif": (.tiff, "tiff")
        default: (.jpeg, (ext == "jpg" || ext == "jpeg") ? ext : "jpg")
        }

        let destURL = uniqueDestinationURL(
            in: url.deletingLastPathComponent(),
            baseName: "\(url.deletingPathExtension().lastPathComponent)_clean",
            extension: targetExt
        )

        var chosenUTType = targetUTType
        var chosenURL = destURL
        var destination = CGImageDestinationCreateWithURL(chosenURL as CFURL, chosenUTType.identifier as CFString, 1, nil)
        if destination == nil {
            // Fallback universal a JPEG si el códec destino no soporta escritura directa
            chosenUTType = .jpeg
            chosenURL = uniqueDestinationURL(
                in: url.deletingLastPathComponent(),
                baseName: "\(url.deletingPathExtension().lastPathComponent)_clean",
                extension: "jpg"
            )
            destination = CGImageDestinationCreateWithURL(chosenURL as CFURL, chosenUTType.identifier as CFString, 1, nil)
        }

        guard let finalDestination = destination else {
            throw NSError(domain: "QuickActionsService", code: 21, userInfo: [
                NSLocalizedDescriptionKey: localizedText(
                    es: "No se pudo crear la imagen limpia para \(url.lastPathComponent).",
                    en: "Could not create clean image for \(url.lastPathComponent)."
                )
            ])
        }

        var cleanProperties: [CFString: Any] = [
            kCGImagePropertyOrientation: 1
        ]
        if chosenUTType == .jpeg || chosenUTType == .heic {
            cleanProperties[kCGImageDestinationLossyCompressionQuality] = 0.94
        }

        CGImageDestinationAddImage(finalDestination, uprightImage, cleanProperties as CFDictionary)
        guard CGImageDestinationFinalize(finalDestination) else {
            throw NSError(domain: "QuickActionsService", code: 22, userInfo: [
                NSLocalizedDescriptionKey: localizedText(
                    es: "No se pudo guardar la imagen sin metadatos.",
                    en: "Could not save metadata-free image."
                )
            ])
        }
        return chosenURL
    }

    private static func stripVideoMetadata(at url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let composition = AVMutableComposition()
        let duration = try await asset.load(.duration)
        let fullRange = CMTimeRange(start: .zero, duration: duration)

        var insertedAnyTrack = false
        for mediaType: AVMediaType in [.video, .audio] {
            let tracks = try await asset.loadTracks(withMediaType: mediaType)
            for track in tracks {
                guard let compTrack = composition.addMutableTrack(
                    withMediaType: mediaType,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else {
                    continue
                }
                let trackRange = try await track.load(.timeRange)
                let rangeToInsert = trackRange.duration.isValid && trackRange.duration > .zero
                    ? CMTimeRange(start: .zero, duration: min(duration, trackRange.duration))
                    : fullRange
                try compTrack.insertTimeRange(rangeToInsert, of: track, at: .zero)
                if mediaType == .video {
                    compTrack.preferredTransform = try await track.load(.preferredTransform)
                }
                insertedAnyTrack = true
            }
        }

        guard insertedAnyTrack else {
            throw NSError(domain: "QuickActionsService", code: 23, userInfo: [
                NSLocalizedDescriptionKey: localizedText(
                    es: "No se encontraron pistas multimedia en \(url.lastPathComponent).",
                    en: "No media tracks found in \(url.lastPathComponent)."
                )
            ])
        }

        let ext = url.pathExtension.lowercased() == "mov" ? "mov" : "mp4"
        let fileType: AVFileType = (ext == "mov") ? .mov : .mp4
        let destURL = uniqueDestinationURL(
            in: url.deletingLastPathComponent(),
            baseName: "\(url.deletingPathExtension().lastPathComponent)_clean",
            extension: ext
        )

        // Intentar primero Passthrough (instantáneo, sin pérdida de calidad), fallback a HighestQuality
        let compatiblePassthrough = await withCheckedContinuation { continuation in
            AVAssetExportSession.determineCompatibility(
                ofExportPreset: AVAssetExportPresetPassthrough,
                with: composition,
                outputFileType: fileType
            ) { isCompatible in
                continuation.resume(returning: isCompatible)
            }
        }
        let chosenPreset = compatiblePassthrough ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality

        guard let session = AVAssetExportSession(asset: composition, presetName: chosenPreset) ?? AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "QuickActionsService", code: 24, userInfo: [
                NSLocalizedDescriptionKey: localizedText(
                    es: "No se pudo inicializar el limpiador de video.",
                    en: "Could not initialize video metadata stripper."
                )
            ])
        }

        session.outputURL = destURL
        session.outputFileType = fileType
        session.shouldOptimizeForNetworkUse = true
        session.metadata = []
        session.metadataItemFilter = AVMetadataItemFilter.forSharing()
        try await runExportSession(session)
        return destURL
    }

    private static func stripPDFMetadata(at url: URL) throws -> URL {
        guard let sourceDoc = PDFDocument(url: url) else {
            throw NSError(domain: "QuickActionsService", code: 25, userInfo: [
                NSLocalizedDescriptionKey: localizedText(
                    es: "No se pudo abrir el PDF \(url.lastPathComponent).",
                    en: "Could not open PDF \(url.lastPathComponent)."
                )
            ])
        }
        if sourceDoc.isEncrypted && sourceDoc.isLocked {
            throw NSError(domain: "QuickActionsService", code: 26, userInfo: [
                NSLocalizedDescriptionKey: localizedText(
                    es: "El PDF está protegido con contraseña y no se pueden limpiar sus metadatos.",
                    en: "The PDF is password-protected and its metadata cannot be stripped."
                )
            ])
        }

        let cleanDoc = PDFDocument()
        for pageIndex in 0..<sourceDoc.pageCount {
            if let page = sourceDoc.page(at: pageIndex) {
                cleanDoc.insert(page, at: cleanDoc.pageCount)
            }
        }
        cleanDoc.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: "",
            PDFDocumentAttribute.authorAttribute: "",
            PDFDocumentAttribute.subjectAttribute: "",
            PDFDocumentAttribute.creatorAttribute: "",
            PDFDocumentAttribute.producerAttribute: "",
            PDFDocumentAttribute.keywordsAttribute: []
        ]

        let destURL = uniqueDestinationURL(
            in: url.deletingLastPathComponent(),
            baseName: "\(url.deletingPathExtension().lastPathComponent)_clean",
            extension: "pdf"
        )
        guard cleanDoc.write(to: destURL) else {
            throw NSError(domain: "QuickActionsService", code: 27, userInfo: [
                NSLocalizedDescriptionKey: localizedText(
                    es: "No se pudo guardar el PDF sin metadatos.",
                    en: "Could not save metadata-free PDF."
                )
            ])
        }
        return destURL
    }

    private static func uniqueDestinationURL(
        in directory: URL,
        baseName: String,
        extension ext: String
    ) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent("\(baseName).\(ext)")
        var counter = 1
        while fm.fileExists(atPath: candidate.path(percentEncoded: false)) {
            candidate = directory.appendingPathComponent("\(baseName)_\(counter).\(ext)")
            counter += 1
        }
        return candidate
    }
}
