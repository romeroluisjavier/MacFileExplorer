import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MacFileExplorer

@MainActor
@Suite(.serialized)
struct ComprehensiveValidationTests {

    private var repoRootURL: URL {
        // Tests/MacFileExplorerValidationTests/ComprehensiveValidationTests.swift -> repo root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func makeSandbox() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MFE_ComprehensiveValidation_\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - 1. Folder Navigation & Performance (5 tests)

    @Test("01. Large directory (550+ files) enumeration speed & completeness")
    func test01_LargeDirectoryEnumerationSpeedAndCompleteness() async throws {
        let sandboxRoot = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandboxRoot) }

        let fm = FileManager.default
        let largeDir = sandboxRoot.appendingPathComponent("LargeDir", isDirectory: true)
        try fm.createDirectory(at: largeDir, withIntermediateDirectories: true)

        let fileCount = 550
        let folderCount = 5
        for i in 0..<fileCount {
            let fileURL = largeDir.appendingPathComponent(String(format: "item_%04d.txt", i))
            try Data("payload-\(i)".utf8).write(to: fileURL)
        }
        for i in 0..<folderCount {
            let subDir = largeDir.appendingPathComponent("Subfolder_\(i)", isDirectory: true)
            try fm.createDirectory(at: subDir, withIntermediateDirectories: true)
        }
        // Internal cache files must be filtered out automatically by FileSystemService.
        try Data("cache".utf8).write(
            to: largeDir.appendingPathComponent(DirectoryIndexCacheService.hiddenCacheFileName)
        )

        let start = CFAbsoluteTimeGetCurrent()
        let items = try await FileSystemService.shared.fetchDirectoryContents(at: largeDir)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(items.count == fileCount + folderCount)
        #expect(elapsed < 5.0, "Enumerating 555 items took unexpectedly long: \(elapsed)s")
        #expect(!items.contains { $0.name == DirectoryIndexCacheService.hiddenCacheFileName })

        let names = Set(items.map(\.name))
        #expect(names.contains("item_0000.txt"))
        #expect(names.contains("item_0549.txt"))
        #expect(names.contains("Subfolder_0"))
        #expect(names.contains("Subfolder_4"))
    }

    @Test("02. Folder cache hit/miss/invalidation & sorting stability")
    func test02_FolderCacheHitMissInvalidationAndSortingStability() async throws {
        let sandboxRoot = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandboxRoot) }
        await DirectoryIndexCacheService.shared.clearAllCaches()

        let fm = FileManager.default
        let dir = sandboxRoot.appendingPathComponent("CacheSortDir", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        // Initial lookup must be a cache miss.
        #expect(DirectoryIndexCacheService.shared.synchronousMemorySnapshot(for: dir) == nil)

        let folderA = FileItem(
            url: dir.appendingPathComponent("AlphaFolder", isDirectory: true),
            name: "AlphaFolder",
            isDirectory: true,
            modificationDate: Date(timeIntervalSince1970: 1_700_000_200)
        )
        let fileSmall = FileItem(
            url: dir.appendingPathComponent("b_notes.txt"),
            name: "b_notes.txt",
            isDirectory: false,
            modificationDate: Date(timeIntervalSince1970: 1_700_000_100),
            size: 120,
            kindDescription: "Plain Text"
        )
        let fileLarge = FileItem(
            url: dir.appendingPathComponent("a_archive.pdf"),
            name: "a_archive.pdf",
            isDirectory: false,
            modificationDate: Date(timeIntervalSince1970: 1_700_000_300),
            size: 95_000,
            kindDescription: "PDF Document"
        )
        let rawItems = [fileSmall, fileLarge, folderA]

        // Verify deterministic sorting across name, date, size, and kind.
        let byNameAsc = FileItem.sort(rawItems, by: .name, ascending: true, foldersFirst: true)
        #expect(byNameAsc.map(\.name) == ["AlphaFolder", "a_archive.pdf", "b_notes.txt"])

        let byNameDesc = FileItem.sort(rawItems, by: .name, ascending: false, foldersFirst: true)
        #expect(byNameDesc.map(\.name) == ["AlphaFolder", "b_notes.txt", "a_archive.pdf"])

        let byDateDesc = FileItem.sort(rawItems, by: .modificationDate, ascending: false, foldersFirst: true)
        #expect(byDateDesc.map(\.name) == ["AlphaFolder", "a_archive.pdf", "b_notes.txt"])

        let bySizeAsc = FileItem.sort(rawItems, by: .size, ascending: true, foldersFirst: true)
        #expect(bySizeAsc.map(\.name) == ["AlphaFolder", "b_notes.txt", "a_archive.pdf"])

        let byKindAsc = FileItem.sort(rawItems, by: .kind, ascending: true, foldersFirst: true)
        #expect(byKindAsc.map(\.name) == ["AlphaFolder", "a_archive.pdf", "b_notes.txt"])

        // Store in synchronous memory cache and confirm hit + sortKey preservation.
        let sortKey = DirectorySortCacheKey(showHiddenFiles: false, sortField: .name, sortAscending: true)
        DirectoryIndexCacheService.shared.storeInSynchronousMemoryCache(
            rawItems,
            sortedItems: byNameAsc,
            sortKey: sortKey,
            for: dir
        )

        let hit = try #require(DirectoryIndexCacheService.shared.synchronousMemorySnapshot(for: dir))
        #expect(hit.items.count == 3)
        #expect(hit.sortedItems?.map(\.name) == ["AlphaFolder", "a_archive.pdf", "b_notes.txt"])
        #expect(hit.sortKey == sortKey)
        #expect(hit.isFolderTimestampFresh == true)

        // Invalidate caches and verify miss.
        await DirectoryIndexCacheService.shared.clearAllCaches()
        #expect(DirectoryIndexCacheService.shared.synchronousMemorySnapshot(for: dir) == nil)
    }

    @Test("03. Hidden files filtering & search query filtering")
    func test03_HiddenFilesFilteringAndSearchQueryFiltering() async throws {
        let sandboxRoot = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandboxRoot) }

        let fm = FileManager.default
        let dir = sandboxRoot.appendingPathComponent("FilterDir", isDirectory: true)
        try fm.createDirectory(at: dir.appendingPathComponent("Projects", isDirectory: true), withIntermediateDirectories: true)
        try Data("SECRET=1".utf8).write(to: dir.appendingPathComponent(".env"))
        try Data("PDF".utf8).write(to: dir.appendingPathComponent("QuarterlyReport.pdf"))
        try Data("Notes".utf8).write(to: dir.appendingPathComponent("notes.txt"))

        let savedLastDir = PersistenceService.shared.loadLastDirectory()
        let savedShowHidden = PersistenceService.shared.loadShowHiddenFiles()
        let savedSort = PersistenceService.shared.loadSort()
        defer {
            PersistenceService.shared.saveLastDirectory(savedLastDir)
            PersistenceService.shared.saveShowHiddenFiles(savedShowHidden)
            PersistenceService.shared.saveSort(field: savedSort.field, ascending: savedSort.ascending)
        }

        await DirectoryIndexCacheService.shared.clearAllCaches()
        let vm = ExplorerViewModel(initialDirectoryURL: dir)
        vm.sortField = .name
        vm.sortAscending = true
        vm.showHiddenFiles = false
        vm.navigate(to: dir, recordHistory: false)

        // Wait for async directory load to complete
        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline && (vm.isLoading || vm.allItems.count < 4) {
            try await Task.sleep(for: .milliseconds(15))
        }
        #expect(vm.allItems.count == 4)

        // Hidden files excluded when showHiddenFiles == false
        #expect(vm.displayedItems.map(\.name) == ["Projects", "notes.txt", "QuarterlyReport.pdf"])

        // Search query respects hidden file visibility
        vm.searchQuery = ".env"
        #expect(vm.displayedItems.isEmpty)

        // Hidden files included when showHiddenFiles == true
        vm.searchQuery = ""
        vm.showHiddenFiles = true
        #expect(vm.displayedItems.count == 4)
        #expect(vm.displayedItems.contains { $0.name == ".env" })

        // Case-insensitive search query on name
        vm.searchQuery = "quarterly"
        #expect(vm.displayedItems.map(\.name) == ["QuarterlyReport.pdf"])

        await DirectoryIndexCacheService.shared.clearAllCaches()
    }

    @Test("04. Rapid navigation history back/forward stack consistency")
    func test04_RapidNavigationHistoryBackForwardStackConsistency() async throws {
        let sandboxRoot = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandboxRoot) }

        let fm = FileManager.default
        let dir1 = sandboxRoot.appendingPathComponent("Nav1", isDirectory: true)
        let dir2 = sandboxRoot.appendingPathComponent("Nav2", isDirectory: true)
        let dir3 = sandboxRoot.appendingPathComponent("Nav3", isDirectory: true)
        let dir4 = sandboxRoot.appendingPathComponent("Nav4", isDirectory: true)
        for dir in [dir1, dir2, dir3, dir4] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let savedLastDir = PersistenceService.shared.loadLastDirectory()
        defer { PersistenceService.shared.saveLastDirectory(savedLastDir) }

        let vm = ExplorerViewModel(initialDirectoryURL: dir1)
        #expect(vm.currentDirectoryURL == dir1.standardizedFileURL)
        #expect(vm.backStack.isEmpty)
        #expect(vm.forwardStack.isEmpty)

        vm.navigate(to: dir2, recordHistory: true)
        vm.navigate(to: dir3, recordHistory: true)
        #expect(vm.currentDirectoryURL == dir3.standardizedFileURL)
        #expect(vm.backStack == [dir1.standardizedFileURL, dir2.standardizedFileURL])
        #expect(vm.forwardStack.isEmpty)

        // Rapid back navigation
        vm.goBack()
        #expect(vm.currentDirectoryURL == dir2.standardizedFileURL)
        #expect(vm.backStack == [dir1.standardizedFileURL])
        #expect(vm.forwardStack == [dir3.standardizedFileURL])

        vm.goBack()
        #expect(vm.currentDirectoryURL == dir1.standardizedFileURL)
        #expect(vm.backStack.isEmpty)
        #expect(vm.forwardStack == [dir3.standardizedFileURL, dir2.standardizedFileURL])

        // Rapid forward navigation
        vm.goForward()
        #expect(vm.currentDirectoryURL == dir2.standardizedFileURL)
        #expect(vm.backStack == [dir1.standardizedFileURL])
        #expect(vm.forwardStack == [dir3.standardizedFileURL])

        // Navigating to a fresh branch must clear forwardStack
        vm.navigate(to: dir4, recordHistory: true)
        #expect(vm.currentDirectoryURL == dir4.standardizedFileURL)
        #expect(vm.backStack == [dir1.standardizedFileURL, dir2.standardizedFileURL])
        #expect(vm.forwardStack.isEmpty)

        await DirectoryIndexCacheService.shared.clearAllCaches()
    }

    @Test("05. FileItem metadata & kind classification edge cases")
    func test05_FileItemMetadataAndKindClassificationEdgeCases() throws {
        let sandboxRoot = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandboxRoot) }

        let fm = FileManager.default
        let dirURL = sandboxRoot.appendingPathComponent("EdgeFolder", isDirectory: true)
        try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)

        let emptyFileURL = sandboxRoot.appendingPathComponent("empty.txt")
        try Data().write(to: emptyFileURL)

        let zipFileURL = sandboxRoot.appendingPathComponent("bundle.ZIP")
        try Data([0x50, 0x4B, 0x05, 0x06]).write(to: zipFileURL)

        let dotFileURL = sandboxRoot.appendingPathComponent(".hidden_config")
        try Data("key=value".utf8).write(to: dotFileURL)

        let symlinkURL = sandboxRoot.appendingPathComponent("link_to_empty.txt")
        try fm.createSymbolicLink(at: symlinkURL, withDestinationURL: emptyFileURL)

        let dirItem = try FileItem(url: dirURL)
        #expect(dirItem.isDirectory)
        #expect(dirItem.isNavigableFolder)
        #expect(dirItem.size == nil)
        #expect(dirItem.sortableSize == -1)
        #expect(dirItem.formattedSize == "")
        #expect(!dirItem.isZipArchive)

        let emptyItem = try FileItem(url: emptyFileURL)
        #expect(!emptyItem.isDirectory)
        #expect(emptyItem.size == 0)
        #expect(emptyItem.formattedSize == "0 KB")
        #expect(emptyItem.fileExtension == "txt")

        let zipItem = try FileItem(url: zipFileURL)
        #expect(zipItem.fileExtension == "zip")
        #expect(zipItem.isZipArchive)

        let dotItem = try FileItem(url: dotFileURL)
        #expect(dotItem.isHidden)

        let symlinkItem = try FileItem(url: symlinkURL)
        #expect(symlinkItem.isSymbolicLink)

        // Package bundle behaves as non-navigable item and preserves byte size
        let packageItem = FileItem(
            url: sandboxRoot.appendingPathComponent("Sample.app", isDirectory: true),
            name: "Sample.app",
            isDirectory: true,
            isPackage: true,
            size: 4096
        )
        #expect(!packageItem.isNavigableFolder)
        #expect(packageItem.size == 4096)
    }

    // MARK: - 2. First-Run Onboarding, Versioning & Release Notes (4 tests)

    @Test("06. Fresh install vs upgrade detection logic")
    func test06_FreshInstallVsUpgradeDetectionLogic() throws {
        let suiteName = "com.macfileexplorer.tests.onboarding.\(UUID().uuidString)"
        let isolatedDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { isolatedDefaults.removePersistentDomain(forName: suiteName) }

        // Comparator sanity checks
        #expect(AppVersionComparator.compare("v2.7.0", "2.7.0") == .orderedSame)
        #expect(AppVersionComparator.normalizedString(of: "v1.3") == "1.3.0")
        #expect(AppVersionComparator.isNewer("2.7.0", than: "2.6.9"))
        #expect(AppVersionComparator.isNewer("2.7.0", than: "2.7.0-beta.1"))
        #expect(!AppVersionComparator.isNewer("2.7.0", than: "2.7.0"))

        // 1. Fresh install -> showFirstInstallWizard
        let freshManager = AppOnboardingManager(
            defaults: isolatedDefaults,
            currentVersionProvider: { "2.7.0" },
            launchArgumentsProvider: { [] }
        )
        #expect(freshManager.evaluateLaunchAction(commitState: false) == .showFirstInstallWizard)

        // 2. Existing user upgrading from 2.5.0 -> 2.7.0
        isolatedDefaults.set(true, forKey: AppOnboardingManager.DefaultsKeys.hasCompletedOnboarding)
        isolatedDefaults.set("2.5.0", forKey: AppOnboardingManager.DefaultsKeys.lastLaunchedVersion)
        let upgradeManager = AppOnboardingManager(
            defaults: isolatedDefaults,
            currentVersionProvider: { "2.7.0" },
            launchArgumentsProvider: { [] }
        )
        #expect(
            upgradeManager.evaluateLaunchAction(commitState: true)
                == .showUpgradeNotes(previousVersion: "2.5.0", currentVersion: "2.7.0")
        )
        #expect(upgradeManager.lastLaunchedVersion == "2.7.0")

        // 3. Subsequent launch on same version -> .none
        let steadyManager = AppOnboardingManager(
            defaults: isolatedDefaults,
            currentVersionProvider: { "2.7.0" },
            launchArgumentsProvider: { [] }
        )
        #expect(steadyManager.evaluateLaunchAction(commitState: false) == .none)

        // 4. ReleaseNotesCatalog.sectionsNewer filters strictly newer releases
        let newerThan250 = ReleaseNotesCatalog.sectionsNewer(than: "2.5.0")
        #expect(!newerThan250.isEmpty)
        #expect(newerThan250.allSatisfy { AppVersionComparator.isNewer($0.semanticVersion, than: "2.5.0") })
        #expect(ReleaseNotesCatalog.sectionsNewer(than: "99.0.0").isEmpty)
    }

    @Test("07. Release notes catalog integrity & descending semantic versions")
    func test07_ReleaseNotesCatalogIntegrityAndDescendingSemanticVersions() throws {
        let sections = ReleaseNotesCatalog.sections
        #expect(!sections.isEmpty)

        var seenSectionIDs = Set<String>()
        var seenItemIDs = Set<String>()
        var previousVersion: SemanticVersion?

        for section in sections {
            #expect(seenSectionIDs.insert(section.id).inserted, "Duplicate section ID: \(section.id)")
            #expect(!section.versionLabelES.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!section.versionLabelEN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!section.dateLabelES.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!section.dateLabelEN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!section.items.isEmpty)

            let parsedVersion = try #require(
                SemanticVersion(string: section.semanticVersion),
                "Invalid semantic version: \(section.semanticVersion)"
            )
            if let prev = previousVersion {
                #expect(
                    prev >= parsedVersion,
                    "Sections must be descending: \(prev.canonicalString) before \(parsedVersion.canonicalString)"
                )
            }
            previousVersion = parsedVersion

            for item in section.items {
                #expect(seenItemIDs.insert(item.id).inserted, "Duplicate item ID: \(item.id)")
                #expect(!item.icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(!item.titleES.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(!item.titleEN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(!item.summaryES.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(!item.summaryEN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @Test("08. Startup defaults snapshot & wizard trigger conditions")
    func test08_StartupDefaultsSnapshotAndWizardTriggerConditions() throws {
        let suiteName = "com.macfileexplorer.tests.snapshot.\(UUID().uuidString)"
        let isolatedDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { isolatedDefaults.removePersistentDomain(forName: suiteName) }

        // Snapshot taken on clean defaults must remain false even if a legacy key is written later during boot.
        let freshManager = AppOnboardingManager(
            defaults: isolatedDefaults,
            currentVersionProvider: { "2.7.0" },
            launchArgumentsProvider: { [] }
        )
        freshManager.captureStartupDefaultsSnapshot()
        isolatedDefaults.set("es", forKey: "com.macfileexplorer.languagePreference")
        #expect(!freshManager.hasLegacyInstallationSignals())
        #expect(freshManager.evaluateLaunchAction(commitState: false) == .showFirstInstallWizard)

        // When a legacy key exists BEFORE snapshot, manager detects upgrade migration rather than fresh install.
        let legacyManager = AppOnboardingManager(
            defaults: isolatedDefaults,
            currentVersionProvider: { "2.7.0" },
            launchArgumentsProvider: { [] }
        )
        legacyManager.captureStartupDefaultsSnapshot()
        #expect(legacyManager.hasLegacyInstallationSignals())
        let legacyAction = legacyManager.evaluateLaunchAction(commitState: false)
        if case let .showUpgradeNotes(_, current) = legacyAction {
            #expect(current == "2.7.0")
        } else {
            Issue.record("Expected legacy user without lastLaunchedVersion to trigger .showUpgradeNotes, got \(legacyAction)")
        }

        // Explicit launch arguments override normal flow deterministically.
        let wizardArgManager = AppOnboardingManager(
            defaults: isolatedDefaults,
            currentVersionProvider: { "2.7.0" },
            launchArgumentsProvider: { ["--wizard"] }
        )
        #expect(wizardArgManager.evaluateLaunchAction(commitState: false) == .showFirstInstallWizard)

        let previewStepManager = AppOnboardingManager(
            defaults: isolatedDefaults,
            currentVersionProvider: { "2.7.0" },
            launchArgumentsProvider: { ["--preview-wizard=notch"] }
        )
        #expect(previewStepManager.evaluateLaunchAction(commitState: false) == .showPreviewWizard(step: .notch))

        let previewTourManager = AppOnboardingManager(
            defaults: isolatedDefaults,
            currentVersionProvider: { "2.7.0" },
            launchArgumentsProvider: { ["--preview-tour"] }
        )
        #expect(previewTourManager.evaluateLaunchAction(commitState: false) == .startPreviewTour)

        let previewUpgradeManager = AppOnboardingManager(
            defaults: isolatedDefaults,
            currentVersionProvider: { "2.7.0" },
            launchArgumentsProvider: { ["--preview-upgrade=2.5.1"] }
        )
        #expect(
            previewUpgradeManager.evaluateLaunchAction(commitState: false)
                == .showUpgradeNotes(previousVersion: "2.5.1", currentVersion: "2.7.0")
        )
    }

    @Test("09. Update checker release notes sanitization & display formatting")
    func test09_UpdateCheckerReleaseNotesSanitizationAndFormatting() {
        let rawMarkdown = """
        ### Novedades de la versión 2.7.0
        ---
        - **Asistente de instalación** con [guía interactiva](https://example.com/guide)
        * Columna `Fecha` en el historial del portapapeles
        https://raw.githubusercontent.com/romeroluisjavier/MacFileExplorer/main/releases/test.dmg
        ## Instalación
        xattr -dr com.apple.quarantine /Applications/MacFileExplorer.app
        SHA-256: abcdef123456
        Sitio web y demos: https://example.com
        """

        let cleaned = GitHubUpdateParser.sanitizeReleaseNotesForDisplay(rawMarkdown)
        let lines = cleaned.components(separatedBy: .newlines)

        #expect(lines.count == 3)
        #expect(lines[0] == "Novedades de la versión 2.7.0")
        #expect(lines[1] == "• Asistente de instalación con guía interactiva")
        #expect(lines[2] == "• Columna Fecha en el historial del portapapeles")
        #expect(!cleaned.contains("**"))
        #expect(!cleaned.contains("###"))
        #expect(!cleaned.contains("https://"))
        #expect(!cleaned.contains("xattr"))
        #expect(!cleaned.contains("SHA-256"))

        let swiftSnippet = """
        ReleaseNoteSection(
            id: "v2.7.0",
            items: [
                ReleaseNoteItem(titleES: "Primera novedad", titleEN: "First Feature"),
                ReleaseNoteItem(titleES: "Segunda novedad", titleEN: "Second Feature")
            ]
        )
        ReleaseNoteSection(
            id: "v2.6.0",
            items: [
                ReleaseNoteItem(titleES: "Vieja", titleEN: "Old")
            ]
        )
        """
        #expect(
            GitHubUpdateParser.extractLatestSectionTitles(fromReleaseNotesSwift: swiftSnippet, isSpanish: true)
                == "• Primera novedad\n• Segunda novedad"
        )
        #expect(
            GitHubUpdateParser.extractLatestSectionTitles(fromReleaseNotesSwift: swiftSnippet, isSpanish: false)
                == "• First Feature\n• Second Feature"
        )
    }

    // MARK: - 3. Clipboard History (Date Column & Sorting) (4 tests)

    @Test("10. Clipboard entry deduplication & copyCount increment")
    func test10_ClipboardEntryDeduplicationAndCopyCountIncrement() throws {
        let sandboxRoot = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandboxRoot) }

        let prefs = ClipboardHistoryPreferences.shared
        let savedEnabled = prefs.isEnabled
        prefs.isEnabled = true
        defer { prefs.isEnabled = savedEnabled }

        let storageDir = sandboxRoot.appendingPathComponent("ClipboardDedup", isDirectory: true)
        let manager = ClipboardHistoryManager(storageDirectoryURL: storageDir, startMonitoringImmediately: false)

        let t1 = Date(timeIntervalSince1970: 1_750_000_100)
        let t2 = Date(timeIntervalSince1970: 1_750_000_200)
        let t3 = Date(timeIntervalSince1970: 1_750_000_300)

        let first = try #require(manager.recordText("Hello MacFileExplorer", sourceAppName: "Notes", now: t1))
        let second = try #require(
            manager.recordText("https://github.com/romeroluisjavier/MacFileExplorer", sourceAppName: "Safari", now: t2)
        )
        let bumped = try #require(manager.recordText("Hello MacFileExplorer", sourceAppName: "Terminal", now: t3))

        #expect(second.kind == .link)
        #expect(manager.items.count == 2)
        #expect(bumped.id == first.id)
        #expect(bumped.copyCount == 2)
        #expect(bumped.lastCopiedAt == t3)
    }

    @Test("11. Clipboard date column compact labels & time formatting")
    func test11_ClipboardDateColumnCompactLabelsAndTimeFormatting() throws {
        let loc = LocalizationManager.shared
        let savedPref = loc.preference
        defer { loc.preference = savedPref }

        let now = Date()
        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: now))
        let priorYear = try #require(Calendar.current.date(byAdding: .year, value: -1, to: now))

        let todayEntry = ClipboardHistoryEntry(kind: .text, contentHash: "h1", textContent: "Today", lastCopiedAt: now)
        let yesterdayEntry = ClipboardHistoryEntry(kind: .text, contentHash: "h2", textContent: "Yesterday", lastCopiedAt: yesterday)
        let olderEntry = ClipboardHistoryEntry(kind: .text, contentHash: "h3", textContent: "Older", lastCopiedAt: priorYear)

        loc.preference = .spanish
        #expect(todayEntry.compactDateDayLabel(using: loc) == "Hoy")
        #expect(yesterdayEntry.compactDateDayLabel(using: loc) == "Ayer")

        loc.preference = .english
        #expect(todayEntry.compactDateDayLabel(using: loc) == "Today")
        #expect(yesterdayEntry.compactDateDayLabel(using: loc) == "Yesterday")

        let olderLabel = olderEntry.compactDateDayLabel(using: loc)
        #expect(!olderLabel.isEmpty)
        #expect(olderLabel != "Today")
        #expect(olderLabel != "Yesterday")

        #expect(!todayEntry.compactTimeLabel.isEmpty)
        #expect(todayEntry.compactTimeLabel == now.formatted(date: .omitted, time: .shortened))
    }

    @Test("12. Clipboard sorting by Date, Name, Kind, Size, SourceApp, CopyCount")
    func test12_ClipboardSortingByAllFieldsAscendingAndDescending() throws {
        let sandboxRoot = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandboxRoot) }

        let prefs = ClipboardHistoryPreferences.shared
        let savedEnabled = prefs.isEnabled
        let savedSortField = prefs.sortField
        let savedSortAscending = prefs.sortAscending
        let savedKeepPinned = prefs.keepPinnedOnTop
        defer {
            prefs.isEnabled = savedEnabled
            prefs.sortField = savedSortField
            prefs.sortAscending = savedSortAscending
            prefs.keepPinnedOnTop = savedKeepPinned
        }

        prefs.isEnabled = true
        prefs.keepPinnedOnTop = false

        let storageDir = sandboxRoot.appendingPathComponent("ClipboardSort", isDirectory: true)
        let manager = ClipboardHistoryManager(storageDirectoryURL: storageDir, startMonitoringImmediately: false)

        let t1 = Date(timeIntervalSince1970: 1_750_001_000)
        let t2 = Date(timeIntervalSince1970: 1_750_002_000)
        let t3 = Date(timeIntervalSince1970: 1_750_003_000)
        let t4 = Date(timeIntervalSince1970: 1_750_004_000)

        let alpha = try #require(manager.recordText("Alpha short", sourceAppName: "Xcode", now: t1))
        let zeta = try #require(manager.recordText("Zeta much longer payload string for size test", sourceAppName: "Chrome", now: t2))
        let link = try #require(manager.recordText("https://example.org", sourceAppName: nil, now: t3))
        // Bump alpha so copyCount == 3 (highest) and lastCopiedAt == t4 (newest)
        _ = manager.recordText("Alpha short", sourceAppName: "Xcode", now: t4)
        _ = manager.recordText("Alpha short", sourceAppName: "Xcode", now: t4)

        // Date
        prefs.sortField = .date
        prefs.sortAscending = false
        #expect(manager.filteredItems.map(\.id) == [alpha.id, link.id, zeta.id])
        prefs.sortAscending = true
        #expect(manager.filteredItems.map(\.id) == [zeta.id, link.id, alpha.id])

        // Name
        prefs.sortField = .name
        prefs.sortAscending = true
        #expect(manager.filteredItems.map(\.id) == [alpha.id, link.id, zeta.id])
        prefs.sortAscending = false
        #expect(manager.filteredItems.map(\.id) == [zeta.id, link.id, alpha.id])

        // Kind (.text sortRank 0 < .link sortRank 1)
        prefs.sortField = .kind
        prefs.sortAscending = true
        #expect(manager.filteredItems.last?.id == link.id)
        prefs.sortAscending = false
        #expect(manager.filteredItems.first?.id == link.id)

        // Size (alpha: 11 bytes, link: 19 bytes, zeta: 45 bytes)
        prefs.sortField = .size
        prefs.sortAscending = true
        #expect(manager.filteredItems.map(\.id) == [alpha.id, link.id, zeta.id])
        prefs.sortAscending = false
        #expect(manager.filteredItems.map(\.id) == [zeta.id, link.id, alpha.id])

        // SourceApp (empty/nil always stays at the end regardless of direction)
        prefs.sortField = .sourceApp
        prefs.sortAscending = true
        #expect(manager.filteredItems.map(\.id) == [zeta.id, alpha.id, link.id])
        prefs.sortAscending = false
        #expect(manager.filteredItems.map(\.id) == [alpha.id, zeta.id, link.id])

        // CopyCount (alpha has 3, others have 1)
        prefs.sortField = .copyCount
        prefs.sortAscending = false
        #expect(manager.filteredItems.first?.id == alpha.id)
        prefs.sortAscending = true
        #expect(manager.filteredItems.last?.id == alpha.id)

        // toggleSort switches to defaultAscending and flips on second call
        manager.toggleSort(by: .name)
        #expect(prefs.sortField == .name)
        #expect(prefs.sortAscending == true)
        manager.toggleSort(by: .name)
        #expect(prefs.sortAscending == false)
    }

    @Test("13. Clipboard pinned items stay on top when keepPinnedOnTop enabled vs disabled")
    func test13_ClipboardPinnedItemsStayOnTopWhenKeepPinnedEnabledVsDisabled() throws {
        let sandboxRoot = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandboxRoot) }

        let prefs = ClipboardHistoryPreferences.shared
        let savedEnabled = prefs.isEnabled
        let savedSortField = prefs.sortField
        let savedSortAscending = prefs.sortAscending
        let savedKeepPinned = prefs.keepPinnedOnTop
        defer {
            prefs.isEnabled = savedEnabled
            prefs.sortField = savedSortField
            prefs.sortAscending = savedSortAscending
            prefs.keepPinnedOnTop = savedKeepPinned
        }

        prefs.isEnabled = true
        prefs.sortField = .date
        prefs.sortAscending = false

        let storageDir = sandboxRoot.appendingPathComponent("ClipboardPin", isDirectory: true)
        let manager = ClipboardHistoryManager(storageDirectoryURL: storageDir, startMonitoringImmediately: false)

        let oldest = try #require(manager.recordText("Oldest pinned item", now: Date(timeIntervalSince1970: 1_750_010_000)))
        let middle = try #require(manager.recordText("Middle item", now: Date(timeIntervalSince1970: 1_750_020_000)))
        let newest = try #require(manager.recordText("Newest item", now: Date(timeIntervalSince1970: 1_750_030_000)))

        manager.togglePin(oldest.id)
        #expect(manager.pinnedCount == 1)

        // keepPinnedOnTop = true -> pinned oldest item is placed first
        prefs.keepPinnedOnTop = true
        #expect(manager.filteredItems.map(\.id) == [oldest.id, newest.id, middle.id])

        // keepPinnedOnTop = false -> strict date descending order
        prefs.keepPinnedOnTop = false
        #expect(manager.filteredItems.map(\.id) == [newest.id, middle.id, oldest.id])
    }

    // MARK: - 4. Notch, Calendar & Music Decoy (4 tests)

    @Test("14. NotchCalendarEvent meeting URL extraction & countdown/time formatting")
    func test14_NotchCalendarEventMeetingURLExtractionAndCountdownFormatting() {
        let loc = LocalizationManager.shared
        let savedPref = loc.preference
        defer { loc.preference = savedPref }

        // Meeting URL extraction for Google Meet, Zoom, and Teams
        let meetURL = NotchCalendarEvent.extractMeetingURL(from: [nil, "Join here: https://meet.google.com/abc-defg-hij today"])
        #expect(meetURL?.absoluteString == "https://meet.google.com/abc-defg-hij")

        let zoomURL = NotchCalendarEvent.extractMeetingURL(from: ["Room: https://us02web.zoom.us/j/1234567890?pwd=abc"])
        #expect(zoomURL?.absoluteString == "https://us02web.zoom.us/j/1234567890?pwd=abc")

        let teamsURL = NotchCalendarEvent.extractMeetingURL(from: ["https://teams.microsoft.com/l/meetup-join/19%3ameeting_xyz"])
        #expect(teamsURL?.absoluteString == "https://teams.microsoft.com/l/meetup-join/19%3ameeting_xyz")

        #expect(NotchCalendarEvent.extractMeetingURL(from: [nil, "", "Coffee catchup in room 3B"]) == nil)

        // Countdown & time formatting
        let baseNow = Date(timeIntervalSince1970: 1_760_000_000)

        let allDay = NotchCalendarEvent(
            id: "allday", title: "Holiday", startDate: baseNow, endDate: baseNow.addingTimeInterval(86_400),
            isAllDay: true, isGoogleCalendar: true, calendarName: "Personal"
        )
        let liveNow = NotchCalendarEvent(
            id: "live", title: "Standup", startDate: baseNow.addingTimeInterval(-300), endDate: baseNow.addingTimeInterval(1500),
            isAllDay: false, isGoogleCalendar: true, calendarName: "Work", meetingURL: meetURL
        )
        let in15m = NotchCalendarEvent(
            id: "15m", title: "Sync", startDate: baseNow.addingTimeInterval(15 * 60), endDate: baseNow.addingTimeInterval(45 * 60),
            isAllDay: false, isGoogleCalendar: true, calendarName: "Work"
        )
        let in90m = NotchCalendarEvent(
            id: "90m", title: "Review", startDate: baseNow.addingTimeInterval(90 * 60), endDate: baseNow.addingTimeInterval(120 * 60),
            isAllDay: false, isGoogleCalendar: true, calendarName: "Work"
        )

        #expect(liveNow.hasMeetingLink)
        #expect(allDay.formattedTimeRange == "—")
        #expect(allDay.formattedStartTime == "—")
        #expect(in15m.formattedTimeRange.contains("–"))

        loc.preference = .english
        #expect(allDay.countdownLabel(from: baseNow, using: loc) == "All day")
        #expect(liveNow.countdownLabel(from: baseNow, using: loc) == "Live now")
        #expect(in15m.countdownLabel(from: baseNow, using: loc) == "In 15m")
        #expect(in90m.countdownLabel(from: baseNow, using: loc) == "In 1h 30m")

        loc.preference = .spanish
        #expect(allDay.countdownLabel(from: baseNow, using: loc) == "Todo el día")
        #expect(liveNow.countdownLabel(from: baseNow, using: loc) == "En curso")
        #expect(in15m.countdownLabel(from: baseNow, using: loc) == "En 15 min")
        #expect(in90m.countdownLabel(from: baseNow, using: loc) == "En 1h 30m")
    }

    @Test("15. Notch calendar preferences persistence & defaults")
    func test15_NotchCalendarPreferencesPersistenceAndDefaults() throws {
        let suiteName = "com.macfileexplorer.tests.notchcal.\(UUID().uuidString)"
        let isolatedDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { isolatedDefaults.removePersistentDomain(forName: suiteName) }

        let prefs = NotchPreferences(defaults: isolatedDefaults)

        // Verify defaults
        #expect(prefs.calendarEnabled)
        #expect(prefs.calendarSource == .googleCalendar)
        #expect(prefs.calendarRangeMode == .daily)
        #expect(prefs.calendarDisplayFormat == .googleAgenda)
        #expect(prefs.calendarIconStyle == .microCircle)
        #expect(prefs.calendarIconPosition == .rightBeforeControls)
        #expect(prefs.calendarIconSize == .medium)
        #expect(prefs.calendarIconShowEventBadge)
        #expect(!prefs.calendarIconShowDayNumber)
        #expect(prefs.calendarUseNativeEventColors)

        // Mutate the 5 calendar icon/color preferences & range/format
        prefs.calendarIconStyle = .pillWithNextEvent
        prefs.calendarIconPosition = .leftNextToMusic
        prefs.calendarIconSize = .large
        prefs.calendarIconShowEventBadge = false
        prefs.calendarIconShowDayNumber = true
        prefs.calendarUseNativeEventColors = false
        prefs.calendarRangeMode = .weekly
        prefs.calendarDisplayFormat = .googleTimeline

        // Reload from the same isolated UserDefaults to verify persistence
        let reloaded = NotchPreferences(defaults: isolatedDefaults)
        #expect(reloaded.calendarIconStyle == .pillWithNextEvent)
        #expect(reloaded.calendarIconPosition == .leftNextToMusic)
        #expect(reloaded.calendarIconSize == .large)
        #expect(!reloaded.calendarIconShowEventBadge)
        #expect(reloaded.calendarIconShowDayNumber)
        #expect(!reloaded.calendarUseNativeEventColors)
        #expect(reloaded.calendarRangeMode == .weekly)
        #expect(reloaded.calendarDisplayFormat == .googleTimeline)
    }

    @Test("16. NotchMediaService stored hasActiveTrack & isPlaying stability")
    func test16_NotchMediaServiceStoredHasActiveTrackAndIsPlayingStability() throws {
        let service = NotchMediaService.shared
        defer { service.stopDemoPreview() }

        service.stopDemoPreview()
        #expect(!service.isDemoMode)

        service.startDemoPreview()
        #expect(service.isDemoMode)
        #expect(service.currentTrack != nil)
        #expect(service.hasActiveTrack)
        #expect(service.isPlaying)

        // Seeking updates elapsedTime without flipping hasActiveTrack or isPlaying
        service.seek(to: 42)
        #expect(service.hasActiveTrack)
        #expect(service.isPlaying)
        let elapsed = try #require(service.currentTrack?.elapsedTime)
        #expect(abs(elapsed - 42) < 0.5)

        // Toggling play/pause flips only isPlaying while keeping hasActiveTrack stable
        service.togglePlayPause()
        #expect(service.hasActiveTrack)
        #expect(!service.isPlaying)

        service.togglePlayPause()
        #expect(service.hasActiveTrack)
        #expect(service.isPlaying)

        // Stopping demo preview cleanly resets both stored flags
        service.stopDemoPreview()
        #expect(!service.isDemoMode)
        #expect(service.currentTrack == nil)
        #expect(!service.hasActiveTrack)
        #expect(!service.isPlaying)
    }

    @Test("17. NotchPreferences resetDefaults restores calendar & notch defaults")
    func test17_NotchPreferencesResetDefaultsRestoresCalendarAndNotchDefaults() throws {
        let suiteName = "com.macfileexplorer.tests.notchreset.\(UUID().uuidString)"
        let isolatedDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { isolatedDefaults.removePersistentDomain(forName: suiteName) }

        let prefs = NotchPreferences(defaults: isolatedDefaults)

        // Mutate Notch & Calendar settings (avoiding system-daemon side effects)
        prefs.pillSize = .spacious
        prefs.artworkStyle = .roundedSquare
        prefs.animationStyle = .bouncySpring
        prefs.animationSpeed = 1.75
        prefs.backgroundOpacity = 0.78
        prefs.ambientGlowIntensity = 0.90
        prefs.showAlbumArtwork = false
        prefs.calendarRangeMode = .weekly
        prefs.calendarDisplayFormat = .compactList
        prefs.calendarOpenTarget = .defaultBrowser
        prefs.calendarAlertLeadMinutes = 15
        prefs.calendarAlertSound = .hero
        prefs.calendarIconStyle = .dateBadgeTile
        prefs.calendarIconPosition = .center
        prefs.calendarIconSize = .small
        prefs.calendarIconShowEventBadge = false
        prefs.calendarIconShowDayNumber = true
        prefs.calendarUseNativeEventColors = false

        prefs.resetDefaults()

        #expect(prefs.pillSize == .normal)
        #expect(prefs.artworkStyle == .circleWithRing)
        #expect(prefs.animationStyle == .smoothFluid)
        #expect(abs(prefs.animationSpeed - NotchPreferences.defaultAnimationSpeed) < 0.001)
        #expect(abs(prefs.backgroundOpacity - NotchPreferences.defaultBackgroundOpacity) < 0.001)
        #expect(abs(prefs.ambientGlowIntensity - NotchPreferences.defaultAmbientGlowIntensity) < 0.001)
        #expect(prefs.showAlbumArtwork)
        #expect(prefs.calendarEnabled)
        #expect(prefs.calendarSource == .googleCalendar)
        #expect(prefs.calendarRangeMode == .daily)
        #expect(prefs.calendarDisplayFormat == .googleAgenda)
        #expect(prefs.calendarOpenTarget == .googleChrome)
        #expect(prefs.calendarAlertLeadMinutes == 5)
        #expect(prefs.calendarAlertSound == .glass)
        #expect(prefs.calendarIconStyle == .microCircle)
        #expect(prefs.calendarIconPosition == .rightBeforeControls)
        #expect(prefs.calendarIconSize == .medium)
        #expect(prefs.calendarIconShowEventBadge)
        #expect(!prefs.calendarIconShowDayNumber)
        #expect(prefs.calendarUseNativeEventColors)
    }

    // MARK: - 5. Installer & Packaging Integrity (3 tests)

    @Test("18. Installer & packaging scripts pass bash -n and contain required steps")
    func test18_InstallerAndPackagingScriptsSyntaxAndRequiredSteps() throws {
        let packageScript = repoRootURL.appendingPathComponent("package_release.sh")
        let installerScript = repoRootURL.appendingPathComponent("Config/Installer/Instalar MacFileExplorer.command")

        #expect(FileManager.default.fileExists(atPath: packageScript.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: installerScript.path(percentEncoded: false)))

        for script in [packageScript, installerScript] {
            let bashCheck = Process()
            bashCheck.executableURL = URL(fileURLWithPath: "/bin/bash")
            bashCheck.arguments = ["-n", script.path(percentEncoded: false)]
            try bashCheck.run()
            bashCheck.waitUntilExit()
            #expect(bashCheck.terminationStatus == 0, "bash -n failed for \(script.lastPathComponent)")
        }

        let packageText = try String(contentsOf: packageScript, encoding: .utf8)
        #expect(packageText.contains("MacFileExplorerMusicDecoy.app"))
        #expect(packageText.contains("xattr -cr"))
        #expect(packageText.contains("codesign --force --sign - --identifier \"com.apple.Music\""))
        #expect(packageText.contains("codesign --force --sign - --identifier \"com.macfileexplorer.app\""))
        #expect(packageText.contains("codesign --verify --deep --strict"))
        #expect(packageText.contains("Instalar MacFileExplorer.command"))
        #expect(packageText.contains("hdiutil verify"))

        let installerText = try String(contentsOf: installerScript, encoding: .utf8)
        #expect(installerText.contains("ditto"))
        #expect(installerText.contains("xattr -dr com.apple.quarantine"))
        #expect(installerText.contains("--wizard"))
    }

    @Test("19. Config/Info.plist and Config/MusicDecoy/Info.plist are valid XML with required keys")
    func test19_InfoPlistsAreValidXMLWithRequiredKeys() throws {
        let mainPlistURL = repoRootURL.appendingPathComponent("Config/Info.plist")
        let decoyPlistURL = repoRootURL.appendingPathComponent("Config/MusicDecoy/Info.plist")

        let mainData = try Data(contentsOf: mainPlistURL)
        let mainObj = try PropertyListSerialization.propertyList(from: mainData, options: [], format: nil)
        let mainDict = try #require(mainObj as? [String: Any])

        #expect(mainDict["CFBundleIdentifier"] as? String == "com.macfileexplorer.app")
        #expect(mainDict["CFBundleExecutable"] as? String == "MacFileExplorer")
        #expect(mainDict["LSMinimumSystemVersion"] as? String == "14.0")
        let shortVersion = try #require(mainDict["CFBundleShortVersionString"] as? String)
        #expect(SemanticVersion(string: shortVersion) != nil)
        #expect(!(mainDict["NSCalendarsUsageDescription"] as? String ?? "").isEmpty)
        #expect(!(mainDict["NSCalendarsFullAccessUsageDescription"] as? String ?? "").isEmpty)
        #expect(!(mainDict["NSAudioCaptureUsageDescription"] as? String ?? "").isEmpty)

        let decoyData = try Data(contentsOf: decoyPlistURL)
        let decoyObj = try PropertyListSerialization.propertyList(from: decoyData, options: [], format: nil)
        let decoyDict = try #require(decoyObj as? [String: Any])

        #expect(decoyDict["CFBundleIdentifier"] as? String == "com.apple.Music")
        #expect(decoyDict["CFBundleExecutable"] as? String == "MacFileExplorerMusicDecoy")
        #expect(decoyDict["LSBackgroundOnly"] as? Bool == true)
        #expect(decoyDict["NSAppleScriptEnabled"] as? Bool == true)
        #expect(decoyDict["OSAScriptingDefinition"] as? String == "MusicDecoy.sdef")
    }

    @Test("20. Sources/ obeys zero @State property wrapper rule")
    func test20_SourcesObeyZeroAtStatePropertyWrapperRule() throws {
        let sourcesURL = repoRootURL.appendingPathComponent("Sources", isDirectory: true)
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: sourcesURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        )
        let regex = try NSRegularExpression(pattern: #"@State\b"#)

        var swiftFileCount = 0
        var violations: [String] = []

        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            swiftFileCount += 1
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            for (idx, line) in lines.enumerated() {
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                if regex.firstMatch(in: line, range: range) != nil {
                    violations.append("\(url.lastPathComponent):\(idx + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        #expect(swiftFileCount > 0, "Expected to scan Swift files under Sources/")
        #expect(
            violations.isEmpty,
            "Found forbidden @State usage in Sources/ (must use @ViewState): \(violations.joined(separator: "; "))"
        )
    }
}
