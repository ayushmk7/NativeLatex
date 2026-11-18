import XCTest
@testable import NativeLatexIntegrations

/// Shared corpus from the documented 2026-11-17 conversion test.
let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("docs/research/conversion-fixtures")

func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("nativelatex-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

final class ConversionTests: XCTestCase {
    let tools = ToolPaths.discover()
    var work: URL!
    var converter: LocalConverter { LocalConverter(tools: tools) }

    override func setUpWithError() throws {
        work = try makeTempDir()
        // Copy so tests never write next to the documented fixtures.
        for name in ["article.tex", "notes.md", "refs.bib", "figure.png"] {
            try FileManager.default.copyItem(at: fixtures.appendingPathComponent(name), to: work.appendingPathComponent(name))
        }
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: work) }

    func requirePandoc() throws { try XCTSkipIf(tools.pandoc == nil, "Pandoc not installed") }
    func requireLibreOffice() throws { try XCTSkipIf(tools.soffice == nil, "LibreOffice not installed") }
    func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    // MARK: Markdown round trips

    func testMarkdownRoundTripThroughDocxAndOdt() throws {
        try requirePandoc()
        let source = work.appendingPathComponent("notes.md")
        let original = try Data(contentsOf: source)
        for office in [DocumentFormat.docx, .odt] {
            let out = work.appendingPathComponent("out-\(office.rawValue)")
            let exported = try converter.convert(source, to: office, in: out)
            XCTAssertEqual(exported.outputURL.lastPathComponent, "notes.\(office.rawValue)")
            XCTAssertTrue(exported.reviewNotes.contains { $0.contains("language tags") }, "\(office)")

            let back = try converter.convert(exported.outputURL, to: .markdown, in: out)
            let md = try read(back.outputURL)
            for expected in ["NativeLatex Markdown sample", "**bold**", "*emphasis*", "https://example.org",
                             "mc^{2}", "Alpha", "Beta", "This is the footnote body", "let greeting"] {
                XCTAssertTrue(md.contains(expected), "\(office) readback lost \(expected):\n\(md)")
            }
            // The embedded figure is extracted beside the copy and linked relatively.
            let media = try XCTUnwrap(back.mediaDirectory, "\(office) image not extracted")
            let images = try FileManager.default.subpathsOfDirectory(atPath: media.path).filter { !$0.hasSuffix("/") && $0.contains(".") }
            XCTAssertFalse(images.isEmpty)
            XCTAssertTrue(md.contains("notes_media/"), md)
            XCTAssertFalse(md.contains(work.path), "absolute temp path leaked into \(office) import")
            XCTAssertTrue(back.reviewNotes.contains { $0.contains("does not reconstruct") })
            // Known losses (conversion test 2026-11-17): code fence language tag dropped;
            // ODT readback turns inline math into display math.
            XCTAssertFalse(md.contains("```swift"))
            if office == .odt { XCTAssertTrue(md.contains("$$E = mc^{2}$$"), md) }
        }
        XCTAssertEqual(try Data(contentsOf: source), original, "source modified")
    }

    // MARK: LaTeX round trips

    func testLatexRoundTripThroughDocxAndOdt() throws {
        try requirePandoc()
        let source = work.appendingPathComponent("article.tex")
        let original = try Data(contentsOf: source)
        for office in [DocumentFormat.docx, .odt] {
            let out = work.appendingPathComponent("out-\(office.rawValue)")
            let exported = try converter.convert(source, to: office, in: out)
            let notes = exported.reviewNotes.joined(separator: "\n")
            for flag in ["Cross-references", "Equation numbers", "Citations", "Custom macros", "captions"] {
                XCTAssertTrue(notes.contains(flag), "missing review flag \(flag)")
            }

            let back = try converter.convert(exported.outputURL, to: .latex, in: out)
            let tex = try read(back.outputURL)
            for expected in ["\\begin{document}", "Overview", "\\textbf{bold}", "quasar",
                             "mc^{2}", "Alpha", "Knuth", "TeXbook", "Custom LaTeX environment content"] {
                XCTAssertTrue(tex.contains(expected), "\(office) LaTeX import lost \(expected)")
            }
            // Known loss, asserted so a future fix is noticed: macro definition is gone.
            XCTAssertFalse(tex.contains("\\newcommand{\\projectword}"))
            let media = try XCTUnwrap(back.mediaDirectory)
            XCTAssertTrue(tex.contains("article_media/"))
            XCTAssertFalse(tex.contains(work.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: media.path))
        }
        XCTAssertEqual(try Data(contentsOf: source), original, "source modified")
    }

    func testMarkdownToLatexCopiesImageNextToCopy() throws {
        try requirePandoc()
        let result = try converter.convert(work.appendingPathComponent("notes.md"), to: .latex, in: work.appendingPathComponent("tex"))
        let tex = try read(result.outputURL)
        XCTAssertTrue(tex.contains("notes_media/"), tex)
        XCTAssertNotNil(result.mediaDirectory)
    }

    // MARK: LibreOffice

    func testLibreOfficeOfficeConversionsAndPdf() throws {
        try requirePandoc()
        try requireLibreOffice()
        let docx = try converter.convert(work.appendingPathComponent("notes.md"), to: .docx, in: work).outputURL
        let odt = try converter.convert(docx, to: .odt, in: work.appendingPathComponent("lo"))
        XCTAssertEqual(odt.tool, "LibreOffice")
        XCTAssertEqual(odt.outputURL.lastPathComponent, "notes.odt")
        let md = try read(converter.convert(odt.outputURL, to: .markdown, in: work.appendingPathComponent("lo")).outputURL)
        XCTAssertTrue(md.contains("This is the footnote body"), md)

        let pdf = try converter.convert(odt.outputURL, to: .pdf, in: work.appendingPathComponent("lo"))
        XCTAssertTrue(try Data(contentsOf: pdf.outputURL).starts(with: Data("%PDF".utf8)))
    }

    // MARK: Safety and errors

    func testNeverOverwritesExistingCopy() throws {
        try requirePandoc()
        let source = work.appendingPathComponent("notes.md")
        let out = work.appendingPathComponent("out")
        let first = try converter.convert(source, to: .docx, in: out)
        let firstBytes = try Data(contentsOf: first.outputURL)
        let second = try converter.convert(source, to: .docx, in: out)
        XCTAssertEqual(second.outputURL.lastPathComponent, "notes 2.docx")
        XCTAssertEqual(try Data(contentsOf: first.outputURL), firstBytes)
    }

    func testMissingToolsGiveInstallGuidance() {
        let none = LocalConverter(tools: ToolPaths(pandoc: nil, soffice: nil))
        XCTAssertThrowsError(try none.convert(work.appendingPathComponent("notes.md"), to: .docx, in: work)) { error in
            guard case .toolMissing("Pandoc", _) = error as? ConversionError else { return XCTFail("\(error)") }
            XCTAssertTrue(error.localizedDescription.contains("Virgule needs Pandoc"))
        }
        let fakeDocx = work.appendingPathComponent("x.docx")
        FileManager.default.createFile(atPath: fakeDocx.path, contents: Data())
        XCTAssertThrowsError(try none.convert(fakeDocx, to: .odt, in: work)) { error in
            guard case .toolMissing("LibreOffice", _) = error as? ConversionError else { return XCTFail("\(error)") }
        }
    }

    func testUnsupportedAndMissingSource() {
        XCTAssertThrowsError(try converter.convert(work.appendingPathComponent("notes.md"), to: .pdf, in: work)) {
            XCTAssertEqual($0 as? ConversionError, .unsupported(from: "md", to: "pdf"))
        }
        let missing = work.appendingPathComponent("nope.md")
        XCTAssertThrowsError(try converter.convert(missing, to: .docx, in: work)) {
            XCTAssertEqual($0 as? ConversionError, .sourceMissing(missing))
        }
    }

    func testPandocFailureSurfacesStderr() throws {
        try requirePandoc()
        let bad = work.appendingPathComponent("broken.docx")
        try Data("not a zip".utf8).write(to: bad)
        XCTAssertThrowsError(try converter.convert(bad, to: .markdown, in: work)) { error in
            guard case let .converterFailed(tool, status, message) = error as? ConversionError else { return XCTFail("\(error)") }
            XCTAssertEqual(tool, "Pandoc")
            XCTAssertNotEqual(status, 0)
            XCTAssertFalse(message.isEmpty)
        }
    }

    func testProcessArgumentsAreNotShellInterpreted() throws {
        let tricky = "a b; echo pwned $(whoami) `id` > /tmp/x"
        let result = try runProcess(URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["%s", tricky], workingDirectory: work)
        XCTAssertEqual(result.stdout, tricky)
        XCTAssertEqual(result.status, 0)
    }

    func testProcessTimeoutStopsChild() {
        XCTAssertThrowsError(try runProcess(URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], workingDirectory: work, timeout: 0.2)) {
            XCTAssertEqual($0 as? ProcessRunError, .timedOut(tool: "sleep", seconds: 0.2))
        }
    }
}
