import XCTest
@testable import MacFileExplorer

final class OCRIndexCacheServiceTests: XCTestCase {

    func testBoundedOCRArchiveNeverExceedsFiveMegabytes() {
        var entries: [String: (fileSize: Int64, mtime: TimeInterval, accessed: TimeInterval, transcript: String)] = [:]
        // Generar ~7 MB de texto poco repetitivo para forzar que incluso comprimido LZFSE supere 512 KB en prueba acotada
        let now = Date().timeIntervalSince1970
        for i in 0..<250 {
            let randomChunk = (0..<250).map { _ in String(Int.random(in: 10000...99999)) }.joined(separator: " ")
            entries["img_\(i).png"] = (
                fileSize: Int64(1024 + i),
                mtime: now,
                accessed: now + Double(i),
                transcript: "Ivana Baldizon \(i) \(randomChunk)"
            )
        }

        let limitBytes = 200 * 1024 // Probar el mecanismo LRU estricto con límite de 200 KB
        let encoded = OCRIndexCacheService.encodeBoundedArchiveData(entries: &entries, maxBytes: limitBytes)
        XCTAssertNotNil(encoded)
        XCTAssertLessThanOrEqual(encoded?.count ?? Int.max, limitBytes)
        XCTAssertFalse(entries.isEmpty)
        XCTAssertNotNil(entries["img_249.png"], "Las entradas más recientes deben conservarse con LRU")
    }

    func testCacheStoresReadsAndInvalidatesOnMetadataChange() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacFileExplorerOCRTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imgURL = tempDir.appendingPathComponent("sample.png")
        let mtime = Date(timeIntervalSince1970: 1_700_000_000)

        await OCRIndexCacheService.shared.storeTranscript(
            "Ivana Baldizón Hernández",
            for: imgURL,
            fileSize: 4096,
            modificationDate: mtime
        )

        let hit = await OCRIndexCacheService.shared.cachedTranscript(
            for: imgURL,
            fileSize: 4096,
            modificationDate: mtime
        )
        XCTAssertEqual(hit, "Ivana Baldizón Hernández")

        // Si cambia el tamaño o la fecha, debe invalidar
        let missSize = await OCRIndexCacheService.shared.cachedTranscript(
            for: imgURL,
            fileSize: 8192,
            modificationDate: mtime
        )
        XCTAssertNil(missSize)

        let missDate = await OCRIndexCacheService.shared.cachedTranscript(
            for: imgURL,
            fileSize: 4096,
            modificationDate: Date(timeIntervalSince1970: 1_700_005_000)
        )
        XCTAssertNil(missDate)

        // Verificar que flush escribe el archivo oculto `.macfileexplorer_ocr.cache` <= 5 MB
        await OCRIndexCacheService.shared.flushFolderArchive(for: tempDir)
        let cacheFile = tempDir.appendingPathComponent(OCRIndexCacheService.hiddenCacheFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFile.path))
        let attrs = try FileManager.default.attributesOfItem(atPath: cacheFile.path)
        let bytes = (attrs[.size] as? NSNumber)?.intValue ?? Int.max
        XCTAssertLessThanOrEqual(bytes, OCRIndexCacheService.maxArchiveSizeBytes)
    }
}
