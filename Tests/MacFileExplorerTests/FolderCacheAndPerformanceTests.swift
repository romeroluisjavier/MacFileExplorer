import Foundation
import XCTest
@testable import MacFileExplorer

@MainActor
final class FolderCacheAndPerformanceTests: XCTestCase {

    private var sandboxRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        let fm = FileManager.default
        sandboxRoot = fm.temporaryDirectory.appendingPathComponent("MFE_PerfTests_\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: sandboxRoot, withIntermediateDirectories: true)
        await DirectoryIndexCacheService.shared.clearAllCaches()
    }

    override func tearDown() async throws {
        await DirectoryIndexCacheService.shared.clearAllCaches()
        if let sandboxRoot {
            try? FileManager.default.removeItem(at: sandboxRoot)
        }
        try await super.tearDown()
    }

    func testRevisitedCachedFolderDoesNotFlashLoadingAndStaysFreshAfterCacheWrite() async throws {
        let fm = FileManager.default
        let folderA = sandboxRoot.appendingPathComponent("A", isDirectory: true)
        let folderB = sandboxRoot.appendingPathComponent("B", isDirectory: true)
        try fm.createDirectory(at: folderA, withIntermediateDirectories: true)
        try fm.createDirectory(at: folderB, withIntermediateDirectories: true)

        for i in 0..<40 {
            try Data("a-\(i)".utf8).write(to: folderA.appendingPathComponent("a_\(i).txt"))
        }
        for i in 0..<250 {
            try Data("b-\(i)".utf8).write(to: folderB.appendingPathComponent("b_\(i).txt"))
        }

        let savedLastDir = PersistenceService.shared.loadLastDirectory()
        defer { PersistenceService.shared.saveLastDirectory(savedLastDir) }

        let vm = ExplorerViewModel(initialDirectoryURL: folderA)
        vm.navigate(to: folderA, recordHistory: false)
        try await waitUntil { vm.displayedItems.count == 40 && !vm.isLoading }

        vm.navigate(to: folderB, recordHistory: true)
        try await waitUntil { vm.displayedItems.count == 250 && !vm.isLoading }

        // Esperar persistencia de `.macfileexplorer_dir.cache` en disco
        try await Task.sleep(for: .milliseconds(300))

        // La escritura de caché oculta jamás debe autoinvalidar la frescura de la carpeta
        let snapshotB = DirectoryIndexCacheService.shared.synchronousMemorySnapshot(for: folderB)
        XCTAssertNotNil(snapshotB)
        XCTAssertEqual(snapshotB?.isFolderTimestampFresh, true)

        // Al volver a A y B repetidamente, la carga debe ser síncrona y sin ningún parpadeo de `isLoading`
        for _ in 0..<10 {
            vm.navigate(to: folderA, recordHistory: true)
            XCTAssertFalse(vm.isLoading)
            XCTAssertFalse(vm.isSlowLoadingOverlayVisible)
            XCTAssertEqual(vm.displayedItems.count, 40)

            vm.navigate(to: folderB, recordHistory: true)
            XCTAssertFalse(vm.isLoading)
            XCTAssertFalse(vm.isSlowLoadingOverlayVisible)
            XCTAssertEqual(vm.displayedItems.count, 250)
        }
    }

    func testDuplicateFinderIgnoresInternalHiddenCaches() async throws {
        let fm = FileManager.default
        let dir = sandboxRoot.appendingPathComponent("Dups", isDirectory: true)
        let sub = dir.appendingPathComponent("Sub", isDirectory: true)
        try fm.createDirectory(at: sub, withIntermediateDirectories: true)

        let payload = Data(repeating: 0x33, count: 4096)
        try payload.write(to: dir.appendingPathComponent("doc1.bin"))
        try payload.write(to: sub.appendingPathComponent("doc2.bin"))
        try payload.write(to: dir.appendingPathComponent(DirectoryIndexCacheService.hiddenCacheFileName))
        try payload.write(to: sub.appendingPathComponent(DirectoryIndexCacheService.hiddenCacheFileName))

        let groups = await DuplicateFinderService.findDuplicates(in: dir, includeSubfolders: true, includeHidden: true)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.items.count, 2)
        XCTAssertFalse(groups.flatMap(\.items).contains { $0.name.hasPrefix(".macfileexplorer_") })
    }

    private func waitUntil(timeoutMs: Int = 3000, _ predicate: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        while Date() < deadline {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(predicate(), "Condition did not become true within \(timeoutMs)ms")
    }
}
