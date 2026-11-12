import XCTest
@testable import MacFileExplorer

final class ReleaseNotesTests: XCTestCase {

    func testReleaseNotesCatalogHasUniqueIDsAndLocalizedCopy() {
        XCTAssertFalse(ReleaseNotesCatalog.sections.isEmpty)

        var seenSectionIDs = Set<String>()
        var seenItemIDs = Set<String>()

        for section in ReleaseNotesCatalog.sections {
            XCTAssertTrue(seenSectionIDs.insert(section.id).inserted, "Duplicate section id: \(section.id)")
            XCTAssertFalse(section.versionLabelES.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(section.versionLabelEN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(section.dateLabelES.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(section.dateLabelEN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(section.items.isEmpty)

            for item in section.items {
                XCTAssertTrue(seenItemIDs.insert(item.id).inserted, "Duplicate item id: \(item.id)")
                XCTAssertFalse(item.icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                XCTAssertFalse(item.titleES.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                XCTAssertFalse(item.titleEN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                XCTAssertFalse(item.summaryES.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                XCTAssertFalse(item.summaryEN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
