import XCTest
@testable import NativeLatexIntegrations

/// Test double only. The token is a fixed fake string; no real Google credentials exist here.
final class FakeGoogleDrive: GoogleDriveTransport, @unchecked Sendable {
    static let fakeAccessToken = "fake-token-not-a-google-credential"
    let accessToken = FakeGoogleDrive.fakeAccessToken
    var docs: [String: Data] = [:]
    var uploads: [(name: String, bytes: Data)] = []

    func exportDocx(documentID: String) async throws -> Data {
        XCTAssertEqual(accessToken, Self.fakeAccessToken)
        guard let data = docs[documentID] else { throw URLError(.fileDoesNotExist) }
        return data
    }

    func createGoogleDoc(name: String, docxFile: URL) async throws -> String {
        XCTAssertEqual(accessToken, Self.fakeAccessToken)
        uploads.append((name, try Data(contentsOf: docxFile)))
        return "fakeNewDoc_\(uploads.count)_abcdefgh"
    }
}

final class GoogleDocsTests: XCTestCase {
    let tools = ToolPaths.discover()

    func testDisabledAndLiveNotConfiguredAreTruthful() async throws {
        let off = GoogleDocsIntegration(enabled: false)
        XCTAssertEqual(off.status, .disabled)
        let noLive = GoogleDocsIntegration(enabled: true)
        XCTAssertEqual(noLive.status, .liveNotConfigured)
        let dir = try makeTempDir()
        do { _ = try await off.importDocument(id: "abcdefghijk", as: .markdown, into: dir); XCTFail() }
        catch { XCTAssertEqual(error as? GoogleDocsError, .disabled) }
        do { _ = try await noLive.exportCopy(of: fixtures.appendingPathComponent("notes.md")); XCTFail() }
        catch {
            XCTAssertEqual(error as? GoogleDocsError, .liveNotConfigured)
            XCTAssertTrue(error.localizedDescription.contains("not available in this Virgule build"))
        }
    }

    func testFakeExportUploadsNewDocxAndImportConvertsDoc() async throws {
        try XCTSkipIf(tools.pandoc == nil, "Pandoc not installed")
        let drive = FakeGoogleDrive()
        let google = GoogleDocsIntegration(enabled: true, transport: drive, converter: LocalConverter(tools: tools))
        XCTAssertEqual(google.status, .ready)

        let (id, notes) = try await google.exportCopy(of: fixtures.appendingPathComponent("notes.md"))
        XCTAssertEqual(id, "fakeNewDoc_1_abcdefgh")
        XCTAssertEqual(drive.uploads.first?.name, "notes")
        XCTAssertTrue(drive.uploads.first!.bytes.starts(with: Data("PK".utf8)), "upload is not a DOCX zip")
        XCTAssertFalse(notes.isEmpty)

        // Round trip: the "Google Doc" is the DOCX we uploaded.
        drive.docs[id] = drive.uploads[0].bytes
        let dir = try makeTempDir()
        let imported = try await google.importDocument(id: id, as: .markdown, into: dir)
        XCTAssertTrue(imported.outputURL.path.hasPrefix(dir.path))
        XCTAssertTrue(try String(contentsOf: imported.outputURL, encoding: .utf8).contains("This is the footnote body"))
    }

    func testRejectsMalformedDocumentID() async throws {
        let google = GoogleDocsIntegration(enabled: true, transport: FakeGoogleDrive())
        do { _ = try await google.importDocument(id: "../../etc/passwd", as: .markdown, into: try makeTempDir()); XCTFail() }
        catch { XCTAssertEqual(error as? GoogleDocsError, .invalidDocumentID("../../etc/passwd")) }
    }
}

final class LibreTextsTests: XCTestCase {
    let page = URL(string: "https://chem.libretexts.org/Bookshelves/Intro/01:_Chapter/1.02:_Atoms_(Test)")!

    /// Fake Deki responses shaped like the live API (checked 2026-11-17); content is synthetic.
    func fakeFetch(license: String?) -> LibreTextsClient.Fetch {
        let base = "https://chem.libretexts.org/@api/deki/pages/=Bookshelves%252FIntro%252F01%253A_Chapter%252F1.02%253A_Atoms_%2528Test%2529"
        let tags: [[String: String]] = (license.map { [["@value": "license:\($0)"]] } ?? []) + [["@value": "author@Ada Example"], ["@value": "article:topic"]]
        let responses: [String: Any] = [
            "\(base)?dream.out.format=json": ["title": "1.2: Atoms <Test>", "uri.ui": page.absoluteString],
            "\(base)/tags?dream.out.format=json": ["tag": tags],
            "\(base)/contents?dream.out.format=json": ["body": [
                "<h2>Isotopes</h2><p>Carbon-12 is \\(\\ce{^{12}_{6}C}\\) and Table \\(\\PageIndex{1}\\).</p><img alt=\"atom\" src=\"https://chem.libretexts.org/@api/deki/files/1/atom.png\">",
                "",
            ]],
        ]
        return { url in
            guard let body = responses[url.absoluteString] else { return (Data(#"{"message":"Not Found"}"#.utf8), 404) }
            return (try JSONSerialization.data(withJSONObject: body), 200)
        }
    }

    func testApiURLDoubleEncodesPathAndRejectsOtherHosts() throws {
        XCTAssertEqual(try LibreTextsClient.apiURL(for: page).absoluteString,
                       "https://chem.libretexts.org/@api/deki/pages/=Bookshelves%252FIntro%252F01%253A_Chapter%252F1.02%253A_Atoms_%2528Test%2529")
        for bad in ["http://chem.libretexts.org/x", "https://libretexts.org.evil.com/x", "https://chem.libretexts.org/"] {
            XCTAssertThrowsError(try LibreTextsClient.apiURL(for: URL(string: bad)!), bad)
        }
    }

    func testImportsPageWithAttributionAndMath() async throws {
        try XCTSkipIf(ToolPaths.discover().pandoc == nil, "Pandoc not installed")
        let dir = try makeTempDir()
        let (meta, result) = try await LibreTextsClient(fetch: fakeFetch(license: "ccby")).importPage(page, as: .markdown, into: dir)
        XCTAssertEqual(meta.license, "ccby")
        XCTAssertEqual(meta.authors, ["Ada Example"])
        let md = try String(contentsOf: result.outputURL, encoding: .utf8)
        XCTAssertTrue(md.contains("Ada Example"), md)
        XCTAssertTrue(md.contains("license ccby"), md)
        XCTAssertTrue(md.contains("$\\ce{^{12}_{6}C}$"), md)
        XCTAssertTrue(md.contains("title: \"1.2: Atoms \\\\<Test\\\\>\""), md) // HTML-escaped title survives as text
        XCTAssertTrue(result.reviewNotes.contains { $0.contains("Remote images") })
        XCTAssertTrue(result.reviewNotes.contains { $0.contains("mhchem") })
    }

    func testRefusesUnlicensedOrAllRightsReserved() async throws {
        for license in [nil, "arr"] {
            do { _ = try await LibreTextsClient(fetch: fakeFetch(license: license)).importPage(page, as: .markdown, into: try makeTempDir()); XCTFail() }
            catch { XCTAssertEqual(error as? LibreTextsError, .licenseNotReusable(license)) }
        }
    }

    func testHttpErrorIsExplicit() async throws {
        let client = LibreTextsClient(fetch: { _ in (Data(), 503) })
        do { _ = try await client.fetchPage(page); XCTFail() }
        catch {
            guard case .httpStatus(503, _) = error as? LibreTextsError else { return XCTFail("\(error)") }
        }
    }

    /// Opt-in live check against the public, key-free API: NATIVELATEX_LIVE_NETWORK=1 swift test
    func testLivePublicPage() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NATIVELATEX_LIVE_NETWORK"] == "1", "live network test is opt-in")
        let url = URL(string: "https://chem.libretexts.org/Bookshelves/Introductory_Chemistry/Introductory_Chemistry_(LibreTexts)/01%3A_The_Chemical_World/1.02%3A_Chemicals_Compose_Ordinary_Things")!
        let page = try await LibreTextsClient().fetchPage(url)
        XCTAssertEqual(page.title, "1.2: Chemicals Compose Ordinary Things")
        XCTAssertNotNil(page.license)
        XCTAssertTrue(page.html.contains("Chemistry"))
    }
}
