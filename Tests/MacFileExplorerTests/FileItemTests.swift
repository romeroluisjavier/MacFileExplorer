import XCTest
@testable import MacFileExplorer

final class FileItemTests: XCTestCase {

    func testFolderAndFileInitializationAndSorting() {
        let folder = FileItem(
            url: URL(fileURLWithPath: "/Users/test/Documents"),
            name: "Documents",
            isDirectory: true,
            modificationDate: Date(timeIntervalSince1970: 1_700_000_000),
            size: 4096
        )
        let fileA = FileItem(
            url: URL(fileURLWithPath: "/Users/test/a_report.pdf"),
            name: "a_report.pdf",
            isDirectory: false,
            modificationDate: Date(timeIntervalSince1970: 1_700_000_100),
            size: 204_800,
            kindDescription: "Documento PDF"
        )

        // Las carpetas no deben exponer tamaño en la columna Tamaño (estilo Windows Explorer)
        XCTAssertNil(folder.size)
        XCTAssertEqual(folder.formattedSize, "")
        XCTAssertFalse(fileA.formattedSize.isEmpty)

        // Al ordenar por nombre ascendente, las carpetas deben agruparse primero
        let sorted = FileItem.sort([fileA, folder], by: .name, ascending: true, foldersFirst: true)
        XCTAssertEqual(sorted.first?.name, "Documents")
        XCTAssertEqual(sorted.last?.name, "a_report.pdf")
    }

    func testDateModifiedMixInterleavesFoldersAndFiles() {
        let oldFolder = FileItem(
            url: URL(fileURLWithPath: "/Users/test/OldFolder"),
            name: "OldFolder",
            isDirectory: true,
            modificationDate: Date(timeIntervalSince1970: 1_000)
        )
        let midFile = FileItem(
            url: URL(fileURLWithPath: "/Users/test/mid.txt"),
            name: "mid.txt",
            isDirectory: false,
            modificationDate: Date(timeIntervalSince1970: 2_000)
        )
        let newFolder = FileItem(
            url: URL(fileURLWithPath: "/Users/test/NewFolder"),
            name: "NewFolder",
            isDirectory: true,
            modificationDate: Date(timeIntervalSince1970: 3_000)
        )

        let regularAsc = FileItem.sort(
            [newFolder, midFile, oldFolder],
            by: .modificationDate,
            ascending: true,
            foldersFirst: true
        )
        XCTAssertEqual(regularAsc.map(\.name), ["OldFolder", "NewFolder", "mid.txt"])

        let mixAsc = FileItem.sort(
            [newFolder, midFile, oldFolder],
            by: .modificationDateMix,
            ascending: true,
            foldersFirst: true
        )
        XCTAssertEqual(mixAsc.map(\.name), ["OldFolder", "mid.txt", "NewFolder"])

        let mixDesc = FileItem.sort(
            [oldFolder, midFile, newFolder],
            by: .modificationDateMix,
            ascending: false,
            foldersFirst: true
        )
        XCTAssertEqual(mixDesc.map(\.name), ["NewFolder", "mid.txt", "OldFolder"])
    }

    @MainActor
    func testWindowsCutAndPasteMovesFileAndClearsCutState() async throws {
        let service = FileSystemService()
        let clipboard = ClipboardManager()

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacFileExplorerTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sourceDir = try await service.createFolder(in: tempRoot, baseName: "Origen")
        let destDir = try await service.createFolder(in: tempRoot, baseName: "Destino")
        let fileURL = try await service.createFile(in: sourceDir, baseName: "nota", fileExtension: "txt")

        // Cortar (Cmd+X)
        clipboard.cut([fileURL])
        XCTAssertTrue(clipboard.isCut(url: fileURL))
        XCTAssertEqual(clipboard.activeMode, .cut)

        // Pegar (Cmd+V) en Destino -> debe mover el archivo y limpiar el estado de corte
        let movedURLs = try await clipboard.paste(into: destDir, using: service)
        XCTAssertEqual(movedURLs.count, 1)
        XCTAssertFalse(clipboard.isCut(url: fileURL))
        XCTAssertNil(clipboard.activeMode)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedURLs[0].path(percentEncoded: false)))
    }
}
