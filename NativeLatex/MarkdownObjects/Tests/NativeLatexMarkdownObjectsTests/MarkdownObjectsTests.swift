import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import NativeLatexMarkdownObjects

/// Hostless: text views that are never in a window, no app, nothing on screen.
@MainActor
final class MarkdownObjectsTests: XCTestCase {
    private var undo: UndoHost?

    /// A Write-like view: TextKit 1, 15 pt system font, pipe-table lines styled literal mono as the Write view does.
    private func make(_ text: String, folder: URL? = nil, math: MathRenderer.Render? = nil, width: CGFloat = 700) -> (NSTextView, MarkdownObjects) {
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: width, height: 800)
        let view = scroll.documentView as! NSTextView
        view.frame = NSRect(x: 0, y: 0, width: width, height: 800)
        view.isRichText = false
        view.allowsUndo = true
        view.font = .systemFont(ofSize: 15)
        view.string = text
        view.layoutManager!.allowsNonContiguousLayout = true // TextKit 1, non-contiguous, like the Write view
        restyle(view, nil)
        let objects = MarkdownObjects.attach(to: view, folder: folder, renderMath: math)!
        return (view, objects)
    }

    /// What the Write view's restyle does to attributes: reset `range`'s paragraphs (an attribute-only edit).
    private func restyle(_ view: NSTextView, _ range: NSRange?) {
        let storage = view.textStorage!, text = storage.mutableString
        let target = range.map { text.paragraphRange(for: $0) } ?? NSRange(location: 0, length: text.length)
        storage.beginEditing()
        storage.setAttributes([.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.textColor], range: target)
        text.enumerateSubstrings(in: target, options: .byLines) { line, r, _, _ in
            if line?.hasPrefix("|") == true { storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: r) }
        }
        storage.endEditing()
    }

    private func x(_ view: NSTextView, _ index: Int) -> CGFloat {
        let lm = view.layoutManager!
        lm.ensureLayout(for: view.textContainer!)
        let g = lm.glyphIndexForCharacter(at: index)
        return lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil).minX + lm.location(forGlyphAt: g).x
    }

    private func objectCount(_ view: NSTextView) -> Int {
        var n = 0
        view.textStorage!.enumerateAttribute(.markdownObject, in: NSRange(location: 0, length: view.textStorage!.length)) { v, _, _ in if v != nil { n += 1 } }
        return n
    }

    private func box(_ view: NSTextView, at index: Int) -> MarkdownObjectBox? {
        view.textStorage!.attribute(.markdownObject, at: index, effectiveRange: nil) as? MarkdownObjectBox
    }

    private func fakeImage(_ size: NSSize, descent: CGFloat = 0) -> MarkdownRendered {
        let image = NSImage(size: size, flipped: false) { rect in NSColor.black.setFill(); rect.fill(); return true }
        return MarkdownRendered(image: image, size: size, descent: descent)
    }

    private func writePNG(_ url: URL, width: Int, height: Int) throws {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(NSColor.systemRed.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }

    private func waitForRenders(_ objects: MarkdownObjects, timeout: TimeInterval = 15) async throws {
        let end = Date().addingTimeInterval(timeout)
        try await Task.sleep(nanoseconds: 200_000_000)
        while objects.isRendering, Date() < end { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertFalse(objects.isRendering, "renders did not finish")
    }

    // MARK: Source preservation

    func testEveryObjectKeepsTheMarkdownBytes() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try writePNG(folder.appendingPathComponent("pic.png"), width: 40, height: 20)
        let source = "# T\r\n\n| a | b |\n|:--|--:|\n| 1 | 22 |\n\n![p](pic.png) and $x^2$ costs $5 and $10\n\n$$\n\\frac{a}{b}\n$$\n"
        let fake: MathRenderer.Render = { jobs in jobs.map { _ in MarkdownRendered(image: NSImage(size: NSSize(width: 30, height: 12)), size: NSSize(width: 30, height: 12), descent: 3) } }
        let (view, objects) = make(source, folder: folder, math: fake)
        try await waitForRenders(objects)
        XCTAssertEqual(view.string, source)
        XCTAssertEqual(Array(view.string.utf8), Array(source.utf8))
        // Table pipes (6) + delimiter rule + image + 2 math; `$5 and $10` is not math.
        XCTAssertEqual(objectCount(view), 10)
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep) // offscreen draw path runs
        XCTAssertEqual(view.string, source)
    }

    // MARK: Tables

    func testTableColumnsAlignAndRightAlignmentEndsTogether() {
        let source = "| Name | Qty |\n|:-----|----:|\n| apple pie | 3 |\n| fig | 1200 |\n"
        let (view, _) = make(source)
        let text = source as NSString
        func start(_ s: String) -> Int { text.range(of: s).location }
        // Left column starts together.
        XCTAssertEqual(x(view, start("Name")), x(view, start("apple")), accuracy: 0.5)
        XCTAssertEqual(x(view, start("Name")), x(view, start("fig")), accuracy: 0.5)
        // Right column: cells end together.
        let qtyEnd = x(view, start("Qty") + 3), threeEnd = x(view, start("3 |") + 1), bigEnd = x(view, start("1200") + 4)
        XCTAssertEqual(threeEnd, bigEnd, accuracy: 0.5)
        XCTAssertEqual(qtyEnd, bigEnd, accuracy: 0.5)
        XCTAssertGreaterThan(x(view, start("Qty")), x(view, start("apple pie") + 9))
        // Delimiter row collapses to a rule.
        let lm = view.layoutManager!
        let delimiter = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: start("|:-")), effectiveRange: nil)
        XCTAssertLessThanOrEqual(delimiter.height, 6)
        if case .rule = box(view, at: start("|:-"))?.content {} else { XCTFail("delimiter row is not a rule") }
    }

    func testTableEditRealignsOtherRows() {
        let source = "| a | b |\n|---|---|\n| x | y |\n"
        let (view, _) = make(source)
        let text = source as NSString
        let before = x(view, text.range(of: "b").location)
        // Type into the last row's first cell; the Write view then restyles that paragraph only.
        let at = text.range(of: "x").location + 1
        view.textStorage!.replaceCharacters(in: NSRange(location: at, length: 0), with: "-much-longer")
        restyle(view, NSRange(location: at, length: 0))
        let now = view.string as NSString
        let headerB = x(view, now.range(of: "b").location), rowY = x(view, now.range(of: "y").location)
        XCTAssertGreaterThan(headerB, before + 40, "header row (outside the edited paragraph) moved with the wider column")
        XCTAssertEqual(headerB, rowY, accuracy: 0.5)
    }

    func testTableEdgeCasesStayLiteral() {
        let escaped = MarkdownSyntax.row("| a \\| b | `c|d` | e |" as NSString, NSRange(location: 0, length: 22))
        XCTAssertEqual(escaped.cells.count, 3, "escaped pipes and pipes in code spans don't split cells")
        XCTAssertTrue(MarkdownSyntax.tables(in: "| a | b |\nnot a delimiter\n" as NSString, range: NSRange(location: 0, length: 26)).isEmpty)
        XCTAssertTrue(MarkdownSyntax.tables(in: "| a | b |\n|---|\n" as NSString, range: NSRange(location: 0, length: 16)).isEmpty, "column count mismatch")
        let noOuterPipes = MarkdownSyntax.tables(in: "a | b\n--|--\nc | d\n" as NSString, range: NSRange(location: 0, length: 18))
        XCTAssertEqual(noOuterPipes.first?.rows.count, 3)
        // Too wide for the column: left as source.
        let wide = "| " + String(repeating: "word ", count: 60) + "| b |\n|---|---|\n| x | y |\n"
        let (view, _) = make(wide, width: 400)
        XCTAssertEqual(objectCount(view), 0)
        // Inside a code block (the Write view gives code a background): not a table.
        let (code, _) = make("| a | b |\n|---|---|\n")
        code.textStorage!.addAttribute(.backgroundColor, value: NSColor.gray, range: NSRange(location: 0, length: code.textStorage!.length))
        code.textStorage!.beginEditing(); code.textStorage!.edited(.editedAttributes, range: NSRange(location: 0, length: 1), changeInLength: 0); code.textStorage!.endEditing()
        XCTAssertEqual(objectCount(code), 0)
    }

    // MARK: Images

    func testImagesLoadOnlyFromTheDocumentFolder() async throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = base.appendingPathComponent("doc"), outside = base.appendingPathComponent("secret")
        try fm.createDirectory(at: folder.appendingPathComponent("img"), withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        try writePNG(folder.appendingPathComponent("img/ok.png"), width: 8, height: 8)
        try writePNG(outside.appendingPathComponent("s.png"), width: 8, height: 8)
        try fm.createSymbolicLink(at: folder.appendingPathComponent("link.png"), withDestinationURL: outside.appendingPathComponent("s.png"))
        try fm.createSymbolicLink(at: folder.appendingPathComponent("dirlink"), withDestinationURL: outside)
        try "not an image".write(to: folder.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        XCTAssertNotNil(MarkdownSyntax.resolveImage("img/ok.png", in: folder))
        XCTAssertNotNil(MarkdownSyntax.resolveImage("<img/ok.png> \"title\"", in: folder))
        XCTAssertNotNil(MarkdownSyntax.resolveImage("./img/../img/ok.png", in: folder))
        for bad in ["../secret/s.png", "%2E%2E/secret/s.png", "link.png", "dirlink/s.png", outside.appendingPathComponent("s.png").path,
                    "file://" + outside.appendingPathComponent("s.png").path, "https://example.com/a.png", "data:image/png;base64,AAAA",
                    "~/a.png", "missing.png", "notes.txt", "img", "img/ok.png?x=1"] {
            XCTAssertNil(MarkdownSyntax.resolveImage(bad, in: folder), bad)
        }
        XCTAssertNil(MarkdownSyntax.resolveImage("img/ok.png", in: nil), "no folder (unsaved document): nothing loads")
    }

    func testImageIsShownScaledToTheColumnAndDownsampled() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try writePNG(folder.appendingPathComponent("big.png"), width: 4000, height: 1000)
        let source = "before\n\n![big](big.png)\n\n![away](../x.png)\n"
        let (view, objects) = make(source, folder: folder, width: 500)
        try await waitForRenders(objects)
        let at = (source as NSString).range(of: "![big]").location
        guard case let .image(image, size, _, tint)? = box(view, at: at)?.content else { return XCTFail("image not shown") }
        XCTAssertFalse(tint)
        let column = view.textContainer!.size.width - 2 * view.textContainer!.lineFragmentPadding
        XCTAssertLessThanOrEqual(size.width, column)
        XCTAssertEqual(size.width / size.height, 4, accuracy: 0.05)
        let pixels = image.representations.map(\.pixelsWide).max() ?? 0
        XCTAssertLessThanOrEqual(pixels, 2 * 800, "decoded downsampled, not at 4000 px")
        XCTAssertEqual(objectCount(view), 1, "the image outside the folder stays as Markdown")
        // A click inside the image lands in its source span.
        let lm = view.layoutManager!
        let rect = lm.boundingRect(forGlyphRange: NSRange(location: lm.glyphIndexForCharacter(at: at), length: 1), in: view.textContainer!)
        let hit = view.characterIndexForInsertion(at: NSPoint(x: rect.minX + 3 + view.textContainerOrigin.x, y: rect.midY + view.textContainerOrigin.y))
        XCTAssertTrue(hit == at || hit == at + 1, "hit \(hit) not at the image span \(at)")
    }

    // MARK: Math

    func testMathFollowsPandocDollarRules() {
        func spans(_ s: String) -> [String] { MarkdownSyntax.math(in: s as NSString, range: NSRange(location: 0, length: (s as NSString).length)).map { ($0.display ? "D:" : "") + $0.formula } }
        XCTAssertEqual(spans("costs $5 and $10 today"), [])
        XCTAssertEqual(spans("$x$"), ["x"])
        XCTAssertEqual(spans("a $x^2 + y$ b"), ["x^2 + y"])
        XCTAssertEqual(spans("$ x$ and $x $"), [])
        XCTAssertEqual(spans("\\$5 then $y$"), ["y"])
        XCTAssertEqual(spans("$x$5"), [])
        XCTAssertEqual(spans("$$\n\\int_0^1 x\\,dx\n$$"), ["D:\\int_0^1 x\\,dx"])
        XCTAssertEqual(spans("$$a\n\nb$$"), [], "a blank line ends the paragraph")
        XCTAssertEqual(spans("$a \\$ b$"), ["a \\$ b"])
    }

    func testMathFilterRefusesFileAccessAndDefinitions() {
        for bad in ["\\input{/etc/hosts}", "\\include{x}", "\\csname input\\endcsname{x}", "^^5cinput{x}", "\\def\\x{y}", "a % comment",
                    "\\catcode`\\a=0", "\\begin{document}", "\\end{preview}", "\\openin1=x", "\\read1to\\x", "\\immediate\\write18{ls}",
                    "\\pdffilesize{x}", "\\everymath{}", "{", "a}", "\\the\\year", "\\newcommand\\x{}", "\\typeout{x}", "x@y",
                    "\\expandafter\\x", String(repeating: "x", count: 2001), ""] {
            XCTAssertFalse(MathRenderer.isAllowed(bad), bad)
        }
        for good in ["x^2", "\\frac{a}{b}", "\\theta + \\therefore", "\\begin{aligned} a &= b \\\\ c &= d \\end{aligned}",
                     "\\sqrt[3]{x}", "\\{ x \\}", "\\left( \\sum_{n=1}^\\infty \\frac{1}{n^2} \\right)", "\\text{if } x > 0",
                     "\\begin{pmatrix} 1 & 0 \\\\ 0 & 1 \\end{pmatrix}", "\\mathbb{R}"] {
            XCTAssertTrue(MathRenderer.isAllowed(good), good)
        }
    }

    func testMathRendersWithTeXAndBadFormulasStayAlone() throws {
        guard let tex = MathRenderer.discover() else { throw XCTSkip("pdflatex not installed") }
        let jobs = [MathRenderer.Job(formula: "x^2", display: false, size: 15),
                    MathRenderer.Job(formula: "\\undefinedmacro x", display: false, size: 15),
                    MathRenderer.Job(formula: "\\frac{a}{b_j}", display: true, size: 15),
                    MathRenderer.Job(formula: "\\input{/etc/hosts}", display: false, size: 15)]
        let start = Date()
        let results = MathRenderer.render(jobs, tex: tex)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        XCTAssertEqual(results.count, 4)
        XCTAssertNotNil(results[0]); XCTAssertNil(results[1]); XCTAssertNotNil(results[2]); XCTAssertNil(results[3])
        let frac = try XCTUnwrap(results[2])
        XCTAssertGreaterThan(frac.size.height, results[0]!.size.height, "display fraction is taller")
        XCTAssertGreaterThan(frac.descent, 2, "fraction sits on the baseline with depth below")
    }

    func testMathWithoutTeXStaysSource() {
        let source = "Energy $E=mc^2$ and $$\\int x$$\n"
        let (view, objects) = make(source, math: nil)
        XCTAssertEqual(objectCount(view), 0)
        XCTAssertFalse(objects.isRendering, "nothing queued without a renderer")
        XCTAssertEqual(view.string, source)
    }

    func testCaretLineShowsMathSourceOtherLinesShowFormula() {
        let source = "first $x^2$ line\nsecond line\n"
        let (view, objects) = make(source)
        objects.prime("I:x^2", fakeImage(NSSize(width: 24, height: 14), descent: 2))
        objects.revealRange = { nil }
        objects.reprocess(nil)
        let at = (source as NSString).range(of: "$x^2$").location
        XCTAssertNotNil(box(view, at: at))
        // The text after the formula moves to the formula's width.
        XCTAssertEqual(x(view, at + 5) - x(view, at), 24, accuracy: 0.5)
        objects.revealRange = { NSRange(location: 0, length: 17) } // caret on the first line
        restyle(view, NSRange(location: 0, length: 0))
        XCTAssertNil(box(view, at: at), "caret line shows the source for editing")
        objects.revealRange = { NSRange(location: 17, length: 12) }
        restyle(view, NSRange(location: 0, length: 0))
        XCTAssertNotNil(box(view, at: at))
    }

    // MARK: Undo and speed

    func testUndoSeesOnlyTypingNotPresentation() {
        let source = "| a | b |\n|---|---|\n| x | y |\n\n$q$\n"
        let (view, objects) = make(source)
        let host = UndoHost(); undo = host; view.delegate = host
        objects.prime("I:q", fakeImage(NSSize(width: 10, height: 10)))
        objects.reprocess(nil)
        XCTAssertFalse(host.manager.canUndo, "presentation registered no undo")
        let at = (source as NSString).range(of: "x").location + 1
        view.setSelectedRange(NSRange(location: at, length: 0))
        host.manager.beginUndoGrouping()
        view.insertText("zz", replacementRange: view.selectedRange())
        restyle(view, NSRange(location: at, length: 0))
        host.manager.endUndoGrouping()
        XCTAssertTrue(view.string.contains("xzz"))
        host.manager.undo()
        restyle(view, nil)
        XCTAssertEqual(view.string, source)
    }

    func testTypingInLargeDocumentStaysFast() {
        var parts: [String] = []
        var size = 0, n = 0
        while size < 1 << 20 {
            let chunk = n % 10 == 0
                ? "| col \(n) | value | more |\n|---|:-:|--:|\n" + (0..<20).map { "| r\($0) | \($0 * n) | x |\n" }.joined() + "\n"
                : "Paragraph \(n) with $x_{\(n)}^2$ inline math and ![i](missing\(n).png) and text that fills the line.\n\n"
            parts.append(chunk); size += chunk.utf8.count; n += 1
        }
        let source = parts.joined()
        let start = Date()
        let (view, objects) = make(source, math: nil)
        let full = Date().timeIntervalSince(start)
        XCTAssertLessThan(full, 4, "attach + full pass on 1 MiB")
        let text = view.string as NSString
        let cell = text.range(of: "| r10 |").location + 4
        var worst = 0.0, total = 0.0
        for i in 0..<20 {
            let t = Date()
            view.textStorage!.replaceCharacters(in: NSRange(location: cell + i, length: 0), with: "k")
            restyle(view, NSRange(location: cell + i, length: 0))
            worst = max(worst, Date().timeIntervalSince(t)); total += Date().timeIntervalSince(t)
        }
        XCTAssertLessThan(worst, 0.05, "keystroke in a 22-row table (storage edit + restyle + objects)")
        // The objects' own share of a keystroke: re-presenting the edited table block.
        var own = 0.0
        for _ in 0..<20 { let t = Date(); objects.reprocess([NSRange(location: cell, length: 0)]); own = max(own, Date().timeIntervalSince(t)) }
        // ponytail: ~20 ms at 1 MiB is storage attribute mutation cost (~2 ms per call); batch writes if it shows.
        XCTAssertLessThan(own, 0.03, "objects pass for one table block (1 MiB storage)")
        XCTAssertGreaterThan(objectCount(view), 1000)
        _ = objects
        print("objects pass \(Int(own * 1e6)) us; 1 MiB full pass \(Int(full * 1000)) ms, worst table keystroke \(Int(worst * 1000)) ms, mean \(Int(total * 50)) ms")
    }
}

final class UndoHost: NSObject, NSTextViewDelegate {
    let manager = UndoManager()
    override init() { manager.groupsByEvent = false }
    func undoManager(for view: NSTextView) -> UndoManager? { manager }
}
