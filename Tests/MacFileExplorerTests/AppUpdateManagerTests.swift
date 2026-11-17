import XCTest
@testable import MacFileExplorer

final class AppUpdateManagerTests: XCTestCase {

    func testSemanticVersionParsingAndComparison() {
        XCTAssertEqual(SemanticVersion(string: "v1.5.0"), SemanticVersion(string: "1.5.0"))
        XCTAssertEqual(SemanticVersion(string: "1.5"), SemanticVersion(string: "1.5.0"))
        XCTAssertTrue(SemanticVersion(string: "v1.5.10")! > SemanticVersion(string: "1.5.2")!)
        XCTAssertTrue(SemanticVersion(string: "2.0.0")! > SemanticVersion(string: "1.9.9")!)
        XCTAssertFalse(SemanticVersion(string: "1.5.0")! > SemanticVersion(string: "1.5.0")!)
        XCTAssertNil(SemanticVersion(string: "v1.6.0-beta.1", allowPrerelease: false))
        XCTAssertNotNil(SemanticVersion(string: "v1.6.0-beta.1", allowPrerelease: true))
    }

    func testAssetFilenameVersionParsing() {
        let dmg = GitHubUpdateParser.parseVersionFromAssetName("MacFileExplorer-1.6.0.dmg")
        XCTAssertEqual(dmg?.version, SemanticVersion(string: "1.6.0"))
        XCTAssertEqual(dmg?.priorityRank, 2)

        let zip = GitHubUpdateParser.parseVersionFromAssetName("MacFileExplorer-v1.5.1.zip")
        XCTAssertEqual(zip?.version, SemanticVersion(string: "1.5.1"))
        XCTAssertEqual(zip?.priorityRank, 1)

        XCTAssertNil(GitHubUpdateParser.parseVersionFromAssetName("README.md"))
    }

    func testCollectCandidatesFromTagsAndReleasesFolder() {
        let releasesJSON = "[]".data(using: .utf8)
        let tagsJSON = """
        [
          {"name": "v1.4.0"},
          {"name": "v1.6.0"},
          {"name": "v1.5.0"}
        ]
        """.data(using: .utf8)
        let contentsJSON = """
        [
          {
            "name": "MacFileExplorer-1.5.0.dmg",
            "type": "file",
            "size": 13000000,
            "download_url": "https://raw.githubusercontent.com/romeroluisjavier/MacFileExplorer/main/releases/MacFileExplorer-1.5.0.dmg"
          },
          {
            "name": "MacFileExplorer-1.6.0.dmg",
            "type": "file",
            "size": 13500000,
            "download_url": "https://raw.githubusercontent.com/romeroluisjavier/MacFileExplorer/main/releases/MacFileExplorer-1.6.0.dmg"
          }
        ]
        """.data(using: .utf8)

        let candidates = GitHubUpdateParser.collectCandidates(
            releasesData: releasesJSON,
            tagsData: tagsJSON,
            contentsData: contentsJSON,
            fallbackPlistData: nil
        )

        XCTAssertEqual(candidates.first?.version, SemanticVersion(string: "1.6.0"))
        XCTAssertEqual(candidates.first?.installerFileName, "MacFileExplorer-1.6.0.dmg")
        XCTAssertEqual(candidates.first?.expectedFileSize, 13500000)
        XCTAssertNotNil(candidates.first?.installerDownloadURL)
    }

    func testFallbackInfoPlistParsing() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleShortVersionString</key>
            <string>1.6.1</string>
        </dict>
        </plist>
        """.data(using: .utf8)!

        let parsed = GitHubUpdateParser.parseVersionFromInfoPlist(plist)
        XCTAssertEqual(parsed, SemanticVersion(string: "1.6.1"))
    }
}
