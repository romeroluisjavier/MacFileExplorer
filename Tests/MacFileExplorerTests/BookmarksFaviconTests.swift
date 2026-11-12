import AppKit
import XCTest
@testable import MacFileExplorer

final class BookmarksFaviconTests: XCTestCase {

    func testChromeBookmarkItemBackwardCompatibleCodableAndSanitization() throws {
        // Payload legado sin `faviconData`
        let legacyID = UUID()
        let legacyJSON = """
        [
          {
            "id": "\(legacyID.uuidString)",
            "title": "Seller",
            "urlString": "https://seller.example.com/panel"
          }
        ]
        """
        let legacyData = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let decodedLegacy = try JSONDecoder().decode([ChromeBookmarkItem].self, from: legacyData)
        XCTAssertEqual(decodedLegacy.count, 1)
        XCTAssertEqual(decodedLegacy[0].id, legacyID)
        XCTAssertNil(decodedLegacy[0].faviconData)

        // Sanitización de esquema duplicado
        XCTAssertEqual(
            ChromeBookmarkItem.sanitizedURLString("https://https://seller.example.com"),
            "https://seller.example.com"
        )
        let encodedWithFavicon = ChromeBookmarkItem(
            id: legacyID,
            title: "Seller",
            urlString: "seller.example.com",
            faviconData: Data([0x89, 0x50, 0x4E, 0x47])
        )
        XCTAssertEqual(encodedWithFavicon.resolvedURL?.absoluteString, "https://seller.example.com")
        let roundTripData = try JSONEncoder().encode([encodedWithFavicon])
        let decodedRoundTrip = try JSONDecoder().decode([ChromeBookmarkItem].self, from: roundTripData)
        XCTAssertEqual(decodedRoundTrip.first?.faviconData, Data([0x89, 0x50, 0x4E, 0x47]))
    }

    func testParseHTMLIconCandidatesPrioritizationAndResolution() {
        let baseURL = URL(string: "https://seller.example.com/app/dashboard")!
        let html = """
        <html>
        <head>
            <link rel="mask-icon" href="/safari-pinned.svg" color="#000000">
            <link href="/favicon-16.ico" rel="shortcut icon" sizes="16x16">
            <link rel='apple-touch-icon' sizes='180x180' href='/apple-touch-icon.png'>
            <link sizes="64x64" type="image/png" href="//cdn.example.com/icons/app.png?v=1&amp;fmt=png" rel="icon">
            <link rel="icon" type="image/svg+xml" href="data:image/svg+xml;base64,PHN2Zz48L3N2Zz4=">
        </head>
        </html>
        """

        let candidates = FaviconService.parseHTMLIconCandidates(html: html, baseURL: baseURL)
        let urls = candidates.map(\.absoluteString)

        XCTAssertFalse(urls.contains(where: { $0.contains("safari-pinned.svg") }))
        XCTAssertEqual(urls.first, "https://cdn.example.com/icons/app.png?v=1&fmt=png")
        XCTAssertTrue(urls.contains("https://seller.example.com/apple-touch-icon.png"))
        XCTAssertTrue(urls.contains("https://seller.example.com/favicon.ico"))
    }

    func testNormalizeSVGDataURLToCrispPNG() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">
            <rect width="32" height="16" y="0" fill="#FF0000"/>
            <rect width="32" height="16" y="16" fill="#00FF00"/>
        </svg>
        """
        let base64 = Data(svg.utf8).base64EncodedString()
        let decodedBytes = try XCTUnwrap(FaviconService.decodeDataURL("data:image/svg+xml;base64,\(base64)"))
        let pngData = try XCTUnwrap(FaviconService.normalizedPNGData(from: decodedBytes, targetPixelSize: 64))

        let rep = try XCTUnwrap(NSBitmapImageRep(data: pngData))
        XCTAssertEqual(rep.pixelsWide, 64)
        XCTAssertEqual(rep.pixelsHigh, 64)

        // Verificar que un píxel de seguimiento 1×1 sea descartado
        let tinyRep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let tinyPNG = try XCTUnwrap(tinyRep.representation(using: .png, properties: [:]))
        XCTAssertNil(FaviconService.normalizedPNGData(from: tinyPNG))
    }

    @MainActor
    func testBookmarksManagerPersistsCapturedFaviconAndSkipsTransientOAuth() throws {
        let suiteName = "MacFileExplorer.BookmarksFaviconTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let sellerSVG = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"64\" height=\"64\"><rect width=\"64\" height=\"64\" fill=\"#2B6CB0\"/></svg>"
        let oauthSVG = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"64\" height=\"64\"><circle cx=\"32\" cy=\"32\" r=\"30\" fill=\"#EA4335\"/></svg>"
        let sellerPNG = try XCTUnwrap(FaviconService.normalizedPNGData(from: Data(sellerSVG.utf8)))
        let oauthPNG = try XCTUnwrap(FaviconService.normalizedPNGData(from: Data(oauthSVG.utf8)))

        let manager = BookmarksManager(userDefaults: defaults)
        manager.bookmarks = [
            ChromeBookmarkItem(title: "Seller", urlString: "https://seller.shop.com/ventas")
        ]
        let bookmarkID = manager.bookmarks[0].id

        // Una redirección temporal a Google OAuth no debe pisar el favicon del bookmark Seller
        manager.recordCapturedFavicon(
            oauthPNG,
            forPageURL: URL(string: "https://accounts.google.com/v3/signin")!,
            sourceBookmarkID: bookmarkID
        )
        XCTAssertNil(manager.bookmarks[0].faviconData)

        // Al terminar el login y cargar la web real destino, el favicon se guarda de forma persistente
        manager.recordCapturedFavicon(
            sellerPNG,
            forPageURL: URL(string: "https://seller.shop.com/dashboard")!,
            sourceBookmarkID: bookmarkID
        )
        XCTAssertEqual(manager.bookmarks[0].faviconData, sellerPNG)
        XCTAssertNotNil(manager.cachedFavicon(for: manager.bookmarks[0]))

        // Simular reinicio de la app recargando desde UserDefaults
        let reloadedManager = BookmarksManager(userDefaults: defaults)
        XCTAssertEqual(reloadedManager.bookmarks.count, 1)
        XCTAssertEqual(reloadedManager.bookmarks[0].faviconData, sellerPNG)
        XCTAssertNotNil(reloadedManager.cachedFavicon(for: reloadedManager.bookmarks[0]))

        // Editar solo el título conserva el favicon; cambiar la URL lo invalida para refrescarlo
        reloadedManager.updateBookmark(bookmarkID, title: "Mi Seller", urlString: "https://seller.shop.com/ventas")
        XCTAssertEqual(reloadedManager.bookmarks[0].title, "Mi Seller")
        XCTAssertEqual(reloadedManager.bookmarks[0].faviconData, sellerPNG)

        reloadedManager.updateBookmark(bookmarkID, title: "Otra Web", urlString: "https://otro.ejemplo.org")
        XCTAssertNil(reloadedManager.bookmarks[0].faviconData)
    }
}
