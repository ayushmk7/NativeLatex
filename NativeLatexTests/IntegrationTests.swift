import XCTest
import NativeLatexIntegrations
@testable import LibreLeaf

/// App-level wiring of the Integrations package. Google uses a fake transport only;
/// no real credentials exist anywhere in these tests.
@MainActor
final class IntegrationTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: folder) }

    func testExportTargetsMatchSourceType() {
        XCTAssertEqual(Conversions.exportTargets(for: URL(fileURLWithPath: "/x/a.tex")), [.docx, .odt, .markdown])
        XCTAssertEqual(Conversions.exportTargets(for: URL(fileURLWithPath: "/x/a.md")), [.docx, .odt, .latex])
        XCTAssertEqual(Conversions.exportTargets(for: URL(fileURLWithPath: "/x/a.ltx")), [.docx, .odt, .markdown])
        XCTAssertEqual(Conversions.exportTargets(for: URL(fileURLWithPath: "/x/a.LATEX")), [.docx, .odt, .markdown])
        XCTAssertEqual(Conversions.exportTargets(for: URL(fileURLWithPath: "/x/a.txt")), [])
        XCTAssertEqual(Conversions.exportTargets(for: nil), [])
    }

    func testGoogleDocsIsHonestlyNotConfigured() async throws {
        XCTAssertEqual(Conversions.googleDocs.status, .liveNotConfigured)
        XCTAssertTrue(Conversions.googleDocsMessage.contains("not available in this LibreLeaf build"))
        XCTAssertFalse(Conversions.googleDocsMessage.localizedCaseInsensitiveContains("signed in"))

        // A fake transport is the only way to reach `.ready`.
        struct FakeDrive: GoogleDriveTransport {
            static let fakeKey = "fake-key-not-a-google-credential"
            func exportDocx(documentID: String) async throws -> Data { throw URLError(.userAuthenticationRequired) }
            func createGoogleDoc(name: String, docxFile: URL) async throws -> String { "fakeDoc_\(Self.fakeKey.count)" }
        }
        XCTAssertEqual(GoogleDocsIntegration(enabled: true, transport: FakeDrive()).status, .ready)
    }

    func testMissingConverterGivesActionableError() async throws {
        let source = folder.appendingPathComponent("notes.md")
        try "# Hi".write(to: source, atomically: true, encoding: .utf8)
        let none = LocalConverter(tools: ToolPaths(pandoc: nil, soffice: nil))
        do { _ = try await Conversions.convert(source, to: .docx, in: folder, converter: none); XCTFail() }
        catch {
            XCTAssertTrue(error.localizedDescription.contains("brew install pandoc"), error.localizedDescription)
            XCTAssertTrue(error.localizedDescription.contains("Editing and PDF builds keep working"))
        }
    }

    func testExportCopyNeverOverwritesAndKeepsSource() async throws {
        let tools = ToolPaths.discover()
        try XCTSkipIf(tools.pandoc == nil, "Pandoc not installed")
        let source = folder.appendingPathComponent("paper.tex")
        let text = #"\documentclass{article}\begin{document}See \ref{x}.\end{document}"#
        try text.write(to: source, atomically: true, encoding: .utf8)
        let first = try await Conversions.convert(source, to: .markdown, in: folder, converter: LocalConverter(tools: tools))
        try "USER EDITS".write(to: first.outputURL, atomically: true, encoding: .utf8)
        let second = try await Conversions.convert(source, to: .markdown, in: folder, converter: LocalConverter(tools: tools))

        XCTAssertEqual(first.outputURL.lastPathComponent, "paper.md")
        XCTAssertEqual(second.outputURL.lastPathComponent, "paper 2.md")
        XCTAssertEqual(try String(contentsOf: first.outputURL, encoding: .utf8), "USER EDITS")
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), text)
        let summary = Conversions.summary(second)
        XCTAssertTrue(summary.contains("Review notes:") && summary.contains("Cross-references"), summary)
    }

    func testMarkdownPreviewKeepsListsQuotesAndLoneCRLines() {
        let text = "# Plan\r- one\r\n  * nested\n2. second\r> quoted *line*\rplain"
        XCTAssertEqual(MarkdownPreview.blocks(text), [
            .heading(1, "Plan"),
            .listItem(depth: 0, marker: "•", text: "one"),
            .listItem(depth: 1, marker: "•", text: "nested"),
            .listItem(depth: 0, marker: "2.", text: "second"),
            .quote("quoted *line*"),
            .paragraph("plain"),
        ])
        XCTAssertEqual(MarkdownPreview.blocks("```\r- not a list\r```"), [.code("- not a list")])
    }

        func testLibreTextsAttributionIsVisible() {
        let text = Conversions.attribution(title: "Ideal Gases", authors: ["A. Author"], license: "ccby",
                                           url: URL(string: "https://chem.libretexts.org/x")!)
        XCTAssertTrue(text.contains("License: ccby") && text.contains("by A. Author") && text.contains("https://chem.libretexts.org/x"))
    }
}
