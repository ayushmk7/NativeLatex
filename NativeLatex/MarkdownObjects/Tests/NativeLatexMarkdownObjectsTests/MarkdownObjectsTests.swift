import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import NativeLatexMarkdownObjects

/// Hostless: text views that are never in a window, no app, nothing on screen.
@MainActor
final class MarkdownObjectsTests: XCTestCase {
    private var undo: UndoHost?
    private let hostDelegate = HostGlyphDelegate()

    /// A Write-like view: TextKit 1, 15 pt system font, pipe-table lines styled literal mono as the Write view does.
    private func make(_ text: String, folder: URL? = nil, width: CGFloat = 700) -> (NSTextView, MarkdownObjects) {
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: width, height: 800)
        let view = scroll.documentView as! NSTextView
        view.frame = NSRect(x: 0, y: 0, width: width, height: 800)
        view.isRichText = false
        view.allowsUndo = true
        view.font = .systemFont(ofSize: 15)
        view.string = text
        // The host's own layout manager and delegate, as the Write view's will be: they call the package.
        let manager = HostLayoutManager()
        manager.allowsNonContiguousLayout = true
        view.textContainer!.replaceLayoutManager(manager)
        manager.delegate = hostDelegate
        restyle(view, nil)
        let objects = MarkdownObjects.attach(to: view, folder: folder)!
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

    private func fakeImage(_ size: NSSize) -> MarkdownRendered {
        let image = NSImage(size: size, flipped: false) { rect in NSColor.black.setFill(); rect.fill(); return true }
        return MarkdownRendered(image: image, size: size)
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
        let (view, objects) = make(source, folder: folder)
        try await waitForRenders(objects)
        XCTAssertEqual(view.string, source)
        XCTAssertEqual(Array(view.string.utf8), Array(source.utf8))
        // Table pipes (6) + delimiter rule + image; math stays source.
        XCTAssertEqual(objectCount(view), 8)
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep) // offscreen draw path runs
        XCTAssertEqual(view.string, source)
    }

    /// The app's `.task` discards `attach`'s result and the storage's delegate is weak: the objects must live on
    /// (edits re-present, image loads land) as long as the text does.
    func testObjectsOutliveADiscardedAttachResult() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try writePNG(folder.appendingPathComponent("p.png"), width: 8, height: 8)
        let source = "| a | b |\n|---|---|\n| x | y |\n\n![p](p.png)\n"
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 700, height: 800)
        let view = scroll.documentView as! NSTextView
        view.font = .systemFont(ofSize: 15)
        view.string = source
        let manager = HostLayoutManager(); manager.allowsNonContiguousLayout = true
        view.textContainer!.replaceLayoutManager(manager)
        manager.delegate = hostDelegate
        weak var objects: MarkdownObjects?
        autoreleasepool { objects = MarkdownObjects.attach(to: view, folder: folder) } // result dropped, as in the app
        XCTAssertNotNil(objects, "kept alive by the text storage")
        XCTAssertTrue(view.textStorage!.delegate === objects)
        // The image decoded after attach returned still lands.
        let end = Date().addingTimeInterval(5)
        while box(view, at: (source as NSString).range(of: "![p]").location) == nil, Date() < end { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertNotNil(box(view, at: (source as NSString).range(of: "![p]").location), "image load finished and was shown")
        // An edit plus the writer's restyle still re-presents the table (header realigns to the wider cell).
        let at = (source as NSString).range(of: "x").location + 1
        let before = x(view, (source as NSString).range(of: "b").location)
        view.textStorage!.replaceCharacters(in: NSRange(location: at, length: 0), with: "-much-longer")
        restyle(view, NSRange(location: at, length: 0))
        XCTAssertGreaterThan(x(view, (view.string as NSString).range(of: "b").location), before + 40)
    }

    func testAttachIsInertUntilTheHostSizesObjectGlyphs() {
        let scroll = NSTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        view.string = "| a | b |\n|---|---|\n| x | y |\n"
        let plain = PlainGlyphDelegate()
        view.layoutManager!.delegate = plain // hides markup only, like today's Write view
        let before = view.layoutManager!
        XCTAssertNil(MarkdownObjects.attach(to: view, folder: nil))
        XCTAssertTrue(view.layoutManager === before && view.layoutManager!.delegate === plain, "host's layout manager and delegate kept")
        XCTAssertNil(view.textStorage!.delegate)
        XCTAssertEqual(objectCount(view), 0)
    }

    // MARK: Tables

    /// A text view's `font` and `textColor` are its first character's. A document that opens with a heading
    /// (or a quote) must not give its tables 30 pt bold (or grey) cells: the host's body style wins.
    func testTableCellsUseTheHostBodyStyleNotTheFirstCharacter() {
        let scroll = NSTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        view.frame = NSRect(x: 0, y: 0, width: 700, height: 800)
        view.isRichText = false
        view.string = "# Title\n\n| a | b |\n|---|---|\n| 1 | 2 |\n"
        let manager = HostLayoutManager()
        view.textContainer!.replaceLayoutManager(manager)
        manager.delegate = hostDelegate
        restyle(view, nil)
        let heading = NSFont.boldSystemFont(ofSize: 30)
        view.textStorage!.addAttributes([.font: heading, .foregroundColor: NSColor.gray], range: NSRange(location: 0, length: 7))
        XCTAssertEqual(view.font?.pointSize, 30, "precondition: the view's font is the heading's")
        let body = NSFont.systemFont(ofSize: 15)
        XCTAssertNotNil(MarkdownObjects.attach(to: view, folder: nil, bodyFont: body, bodyColor: .textColor))
        let text = view.string as NSString
        for cell in ["a", "1"] {
            let i = text.range(of: cell, options: .backwards).location
            let font = view.textStorage!.attribute(.font, at: i, effectiveRange: nil) as? NSFont
            XCTAssertEqual(font?.pointSize, 15, "cell \(cell) in the body size")
            XCTAssertEqual(view.textStorage!.attribute(.foregroundColor, at: i, effectiveRange: nil) as? NSColor, .textColor, "cell \(cell) in the body colour")
        }
    }

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

    /// Read's table, drawn offscreen in light mode: the same vertical grid lines in every row, a horizontal
    /// line on every row's top and the table's bottom, the header shaded #F5F5F7, body white, text still black.
    func testTableGridAndHeaderShadeMatchRead() {
        let source = "| Name | Qty | Mid |\n|:-----|----:|:---:|\n| apple pie | 3 | x |\n| fig | 1200 | wider cell |\n\nafter\n"
        let (view, _) = make(source)
        view.appearance = NSAppearance(named: .aqua)
        view.backgroundColor = .white
        view.textColor = .black
        let lm = view.layoutManager!, text = source as NSString
        lm.ensureLayout(for: view.textContainer!)
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: rep) }
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        func line(_ s: String) -> NSRect {
            lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: text.range(of: s).location), effectiveRange: nil)
                .offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
        }
        func pixel(_ x: CGFloat, _ y: CGFloat) -> NSColor { rep.colorAt(x: Int(x * scale), y: Int(y * scale))!.usingColorSpace(.sRGB)! }
        func gray(_ c: NSColor) -> CGFloat { (c.redComponent + c.greenComponent + c.blueComponent) / 3 }
        /// x (pt) of vertical lines: pixel columns dark over the line's full height (text never spans all of it).
        func verticals(_ s: String) -> [CGFloat] {
            let r = line(s)
            var xs: [CGFloat] = []
            for px in 0..<rep.pixelsWide {
                let x = CGFloat(px) / scale
                let full = stride(from: r.minY.rounded() + 1.5, to: r.maxY.rounded() - 0.5, by: 1 / scale).allSatisfy { gray(pixel(x, $0)) < 0.93 }
                if full, xs.last.map({ x - $0 > 3 }) ?? true { xs.append(x.rounded()) }
            }
            return xs
        }
        let header = verticals("| Name")
        XCTAssertEqual(header.count, 4, "left border, two inner lines, right border: \(header)")
        XCTAssertEqual(verticals("| apple"), header)
        XCTAssertEqual(verticals("| fig"), header)
        XCTAssertTrue(verticals("after").isEmpty, "no grid outside the table")
        let inside = header[0] + 3
        // Header shade (#F5F5F7 = 0.96), body white.
        let shade = pixel(inside, line("| Name").midY)
        XCTAssertEqual(shade.redComponent, 0xF5 / 255, accuracy: 0.02); XCTAssertEqual(shade.blueComponent, 0xF7 / 255, accuracy: 0.02)
        XCTAssertGreaterThan(gray(pixel(inside, line("| apple").midY)), 0.99, "body cells unshaded")
        // Header text keeps its colour: darken never lightens black glyphs.
        let nameGlyphs = lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: text.range(of: "Name"), actualCharacterRange: nil), in: view.textContainer!)
            .offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
        var darkest: CGFloat = 1
        for y in stride(from: nameGlyphs.minY, to: nameGlyphs.maxY, by: 0.5) { for x in stride(from: nameGlyphs.minX, to: nameGlyphs.maxX, by: 0.5) { darkest = min(darkest, gray(pixel(x, y))) } }
        XCTAssertLessThan(darkest, 0.2, "header text still drawn dark")
        // Horizontal lines: header top, first body row top, table bottom; none below.
        for (s, y) in [("| Name", line("| Name").minY), ("| apple", line("| apple").minY), ("| fig", line("| fig").maxY)] {
            XCTAssertLessThan(gray(pixel(inside + 20, y.rounded() + 0.25)), 0.93, "horizontal line at \(s)")
        }
        XCTAssertGreaterThan(gray(pixel(inside + 20, line("| fig").maxY.rounded() + 3)), 0.99, "nothing below the table")
        XCTAssertEqual(view.string, source)
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
        guard case let .image(image, size)? = box(view, at: at)?.content else { return XCTFail("image not shown") }
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

    func testImageDimensionsAreCappedBeforeDecoding() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let small = folder.appendingPathComponent("s.png")
        try writePNG(small, width: 8, height: 8)
        XCTAssertNotNil(MarkdownSyntax.loadImage(small, maxPixels: 100, maxSourcePixels: 64))
        XCTAssertNil(MarkdownSyntax.loadImage(small, maxPixels: 100, maxSourcePixels: 63))
        // A 65-byte PNG whose header declares 11000 x 10000 (110 MP): refused (cap or ImageIO), never decoded; the cap itself is proven with maxSourcePixels above.
        let bomb = folder.appendingPathComponent("bomb.png")
        try Self.pngHeader(width: 11000, height: 10000).write(to: bomb)
        XCTAssertNotNil(MarkdownSyntax.resolveImage("bomb.png", in: folder))
        XCTAssertNil(MarkdownSyntax.loadImage(bomb, maxPixels: 1600))
        XCTAssertEqual(MarkdownSyntax.maxSourcePixels, 100_000_000)
    }

    private func bitmapImage(_ side: Int) -> MarkdownRendered {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let image = NSImage(size: NSSize(width: side, height: side)); image.addRepresentation(rep)
        return MarkdownRendered(image: image, size: image.size)
    }

    private func imageFolder(_ names: [String]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in names { try writePNG(folder.appendingPathComponent(name), width: 16, height: 16) }
        return folder
    }

    /// Saves `file` again (new modification time) and restyles, as the Write view does on the next edit.
    private func resave(_ file: URL, _ n: Int, in view: NSTextView) throws -> String {
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000 + Double(n))], ofItemAtPath: file.path)
        restyle(view, nil)
        return try key(file)
    }

    /// The cache key `process` uses: resolved like a span's source (symlinks too), fresh file attributes.
    private func key(_ file: URL) throws -> String {
        try XCTUnwrap(MarkdownSyntax.imageKey(try XCTUnwrap(MarkdownSyntax.resolveImage(file.lastPathComponent, in: file.deletingLastPathComponent()))))
    }

    /// Re-saving an image gives it a new key (path|mtime|size); its old decode must go, or each save kept one more
    /// (~8 MB for a column-width photo). Other images keep theirs. Results are handed in directly (no wait).
    func testResavedImageReplacesItsOldDecode() throws {
        let folder = try imageFolder(["a.png", "b.png"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let (view, objects) = make("![a](a.png)\n\n![b](b.png)\n", folder: folder)
        let a = folder.appendingPathComponent("a.png"), b = folder.appendingPathComponent("b.png")
        objects.finish([try key(b): bitmapImage(4)])
        var last = ""
        for save in 1...6 { last = try resave(a, save, in: view); objects.finish([last: bitmapImage(4)]) }
        XCTAssertEqual(objects.cachedImageCount, 2, "one decode per image path, however often it is saved")
        XCTAssertNotNil(objects.cache[last] ?? nil, "the newest save is the one kept")
        XCTAssertEqual(MarkdownObjects.imagePath(ofKey: "G:/d/x|y.png|2.0|6"), "G:/d/x|y.png", "a path may contain |")
    }

    /// Two saves in quick succession put two decodes in flight; if the older finishes last it must be dropped,
    /// not cached over (or evict) the decode for the file as it is now.
    func testOlderDecodeFinishingLastNeverEvictsTheCurrentOne() throws {
        let folder = try imageFolder(["a.png"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let (view, objects) = make("![a](a.png)\n", folder: folder)
        let file = folder.appendingPathComponent("a.png")
        let old = try resave(file, 1, in: view), new = try resave(file, 2, in: view) // both requested, neither finished
        objects.finish([new: bitmapImage(4)])
        objects.finish([old: bitmapImage(4)]) // the stale one arrives last
        XCTAssertNotNil(objects.cache[new] ?? nil, "current decode kept")
        XCTAssertNil(objects.cache[old], "stale decode dropped")
        XCTAssertEqual(objects.cachedImageCount, 1)
        XCTAssertEqual(objectCount(view), 1, "the image is still drawn")
    }

    /// A document with more distinct images than the decode budget keeps at most the budget's worth: the first
    /// ones are drawn, the rest stay Markdown source (text untouched), and nothing re-decodes in a loop.
    /// Removing images frees their decodes for images added later.
    func testDecodedImagesStayWithinTheBudget() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for i in 1...12 { try writePNG(folder.appendingPathComponent("p\(i).png"), width: 16, height: 16) }
        let one = MarkdownObjects.bytes(try XCTUnwrap(MarkdownSyntax.loadImage(folder.appendingPathComponent("p1.png"), maxPixels: 1600)))
        let source = (1...10).map { "![p](p\($0).png)" }.joined(separator: "\n\n") + "\n"
        let (view, objects) = make(source, folder: folder)
        objects.decodedByteLimit = 4 * one
        try await waitForRenders(objects)
        XCTAssertEqual(objects.cachedImageCount, 4, "at most the budget's worth of decodes")
        XCTAssertEqual(objectCount(view), 4, "the rest stay source")
        XCTAssertEqual(view.string, source)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertFalse(objects.isRendering, "no re-decode loop for over-budget images")

        // Remove every image, then add two new ones: the old decodes are unreferenced and make room.
        view.textStorage!.replaceCharacters(in: NSRange(location: 0, length: view.textStorage!.length), with: "![p](p11.png)\n\n![p](p12.png)\n")
        restyle(view, nil)
        try await waitForRenders(objects)
        XCTAssertEqual(objectCount(view), 2, "new images drawn once old decodes are unreferenced")
        XCTAssertLessThanOrEqual(objects.cachedImageCount, 4)
    }

    /// Many distinct images decode a few at a time, never all at once (each decode is held until its batch
    /// finishes), and every one is drawn; once done nothing is queued or decoding again.
    func testManyImagesDecodeInSmallBatches() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for i in 1...24 { try writePNG(folder.appendingPathComponent("p\(i).png"), width: 16, height: 16) }
        let source = (1...24).map { "![p](p\($0).png)" }.joined(separator: "\n\n") + "\n"
        let (view, objects) = make(source, folder: folder)
        try await waitForRenders(objects)
        XCTAssertLessThanOrEqual(objects.peakInFlight, MarkdownObjects.decodeBatch, "decodes in flight stay bounded")
        XCTAssertEqual(objectCount(view), 24, "all images drawn, batch by batch")
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertFalse(objects.isRendering, "nothing re-queued after the last batch")
        XCTAssertEqual(view.string, source)
    }

    /// The budget is per document folder: attaching to another folder (or reopening, a new instance) starts
    /// afresh, so images left as source by a full budget are decoded again there, still within the cap.
    func testFolderChangeResetsTheDecodeBudget() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let a = base.appendingPathComponent("a"), b = base.appendingPathComponent("b")
        for folder in [a, b] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for i in 1...6 { try writePNG(folder.appendingPathComponent("p\(i).png"), width: 16, height: 16) }
        }
        defer { try? FileManager.default.removeItem(at: base) }
        let one = MarkdownObjects.bytes(try XCTUnwrap(MarkdownSyntax.loadImage(a.appendingPathComponent("p1.png"), maxPixels: 1600)))
        let source = (1...6).map { "![p](p\($0).png)" }.joined(separator: "\n\n") + "\n"
        let (view, objects) = make(source, folder: a)
        objects.decodedByteLimit = 3 * one
        try await waitForRenders(objects)
        XCTAssertEqual(objectCount(view), 3, "budget full in folder a")

        XCTAssertIdentical(MarkdownObjects.attach(to: view, folder: b), objects, "same presenter, new folder")
        try await waitForRenders(objects)
        XCTAssertEqual(objectCount(view), 3, "fresh budget in folder b: images drawn again, still capped")
        XCTAssertEqual(objects.cachedImageCount, 3, "folder a's decodes are gone, not added to b's")
        XCTAssertEqual(view.string, source)

        // A decode from folder a that finishes after the switch is not cached: no span uses it.
        let stale = try key(a.appendingPathComponent("p6.png"))
        objects.finish([stale: bitmapImage(4)])
        XCTAssertNil(objects.cache[stale], "old folder's late decode dropped")
        XCTAssertEqual(objects.cachedImageCount, 3)

        let (reopened, fresh) = make(source, folder: b) // reopening: a new presenter, its own budget
        try await waitForRenders(fresh)
        XCTAssertEqual(objectCount(reopened), 6, "default budget fits them all")
    }

    func testImageEditedOnDiskOrAddedLaterReloads() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("p.png")
        try writePNG(file, width: 8, height: 8)
        let source = "![p](p.png)\n\n![later](later.png)\n"
        let (view, objects) = make(source, folder: folder)
        try await waitForRenders(objects)
        func width(_ s: String) -> CGFloat? {
            guard case let .image(_, size)? = box(view, at: (source as NSString).range(of: s).location)?.content else { return nil }
            return size.width
        }
        XCTAssertEqual(width("![p]"), 8)
        XCTAssertNil(width("![later]"), "missing file stays source")
        // Replaced on disk (new size and time) and the missing one created; the next restyle picks both up.
        try writePNG(file, width: 16, height: 8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: file.path)
        try writePNG(folder.appendingPathComponent("later.png"), width: 4, height: 4)
        restyle(view, nil)
        try await waitForRenders(objects)
        XCTAssertEqual(width("![p]"), 16)
        XCTAssertEqual(width("![later]"), 4)
        XCTAssertEqual(view.string, source)
    }

    /// PNG signature, IHDR (8-bit RGBA), an empty IDAT and IEND.
    static func pngHeader(width: UInt32, height: UInt32) -> Data {
        func crc(_ bytes: [UInt8]) -> UInt32 {
            var c: UInt32 = 0xFFFF_FFFF
            for b in bytes { c ^= UInt32(b); for _ in 0..<8 { c = c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 } }
            return ~c
        }
        func be(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
        func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
            let typed = Array(type.utf8) + body
            return be(UInt32(body.count)) + typed + be(crc(typed))
        }
        let ihdr = be(width) + be(height) + [8, 6, 0, 0, 0]
        return Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + chunk("IHDR", ihdr) + chunk("IDAT", [0x78, 0x9C, 0x03, 0x00, 0x00, 0x00, 0x00, 0x01]) + chunk("IEND", []))
    }

    // MARK: Math

    /// Write never runs TeX (a filter bypass let a formula read a private file): math stays source. A fake
    /// `pdflatex` first on PATH and in every searched folder would leave a marker if anything started it.
    func testMathStaysSourceAndNoTeXEverStarts() async throws {
        let fm = FileManager.default
        let bin = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: bin) }
        let marker = bin.appendingPathComponent("started")
        for tool in ["pdflatex", "latex", "lualatex", "xelatex", "tectonic", "latexmk", "pandoc"] {
            let script = bin.appendingPathComponent(tool)
            try "#!/bin/sh\ntouch '\(marker.path)'\n".write(to: script, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        }
        let oldPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        setenv("PATH", bin.path + ":" + oldPath, 1)
        defer { setenv("PATH", oldPath, 1) }
        let source = "Energy $E=mc^2$, $\\input{/etc/hosts}$ and\n\n$$\n\\int_0^1 x\\,dx\n$$\n\n| a | b |\n|---|---|\n| $x$ | y |\n"
        let (view, objects) = make(source)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertFalse(objects.isRendering)
        XCTAssertFalse(fm.fileExists(atPath: marker.path), "a TeX tool was started")
        XCTAssertEqual(view.string, source)
        let text = source as NSString
        for formula in ["$E=mc^2$", "$\\input{/etc/hosts}$", "$$\n\\int"] {
            let r = text.range(of: formula)
            var touched = false
            view.textStorage!.enumerateAttributes(in: r) { a, _, _ in
                if a[.markdownObject] != nil || a[.markdownObjectHidden] != nil || a[.markdownObjectSource] != nil { touched = true }
            }
            XCTAssertFalse(touched, "\(formula) is left exactly as the Write view styled it")
        }
        // And the package has no way to start a process at all.
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        for file in try fm.subpathsOfDirectory(atPath: sources.path) where file.hasSuffix(".swift") {
            let code = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            for banned in ["Process(", "NSTask", "posix_spawn", "system(", "popen", "execv", "pdflatex", "NSWorkspace"] {
                XCTAssertFalse(code.contains(banned), "\(file) contains \(banned)")
            }
        }
    }

    func testCaretLineShowsImageSourceOtherLinesShowImage() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try writePNG(folder.appendingPathComponent("p.png"), width: 8, height: 8)
        let source = "first ![p](p.png) line\nsecond line\n"
        let (view, objects) = make(source, folder: folder)
        objects.prime(MarkdownSyntax.imageKey(MarkdownSyntax.resolveImage("p.png", in: folder)!)!, fakeImage(NSSize(width: 24, height: 14)))
        objects.revealRange = { nil }
        objects.reprocess(nil)
        let span = (source as NSString).range(of: "![p](p.png)")
        XCTAssertNotNil(box(view, at: span.location))
        // The text after the image moves to the image's width.
        XCTAssertEqual(x(view, NSMaxRange(span)) - x(view, span.location), 24, accuracy: 0.5)
        objects.revealRange = { NSRange(location: 0, length: 23) } // caret on the first line
        restyle(view, NSRange(location: 0, length: 0))
        XCTAssertNil(box(view, at: span.location), "caret line shows the source for editing")
        objects.revealRange = { NSRange(location: 23, length: 12) }
        restyle(view, NSRange(location: 0, length: 0))
        XCTAssertNotNil(box(view, at: span.location))
    }

    // MARK: Undo and speed

    func testUndoSeesOnlyTypingNotPresentation() {
        let source = "| a | b |\n|---|---|\n| x | y |\n\n$q$\n"
        let (view, objects) = make(source)
        let host = UndoHost(); undo = host; view.delegate = host
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
        let (view, objects) = make(source)
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
        XCTAssertLessThan(own, 0.05, "objects pass for one table block (1 MiB storage)")
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

/// What the Write view adds: its layout manager draws objects after its own drawing.
final class HostLayoutManager: NSLayoutManager {
    override func drawGlyphs(forGlyphRange glyphs: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphs, at: origin)
        MarkdownObjects.draw(self, glyphRange: glyphs, at: origin)
    }
}

/// What the Write view's layout manager delegate adds: three forwarding calls beside its own markup hiding.
final class HostGlyphDelegate: NSObject, NSLayoutManagerDelegate {
    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes: UnsafePointer<Int>,
                       font: NSFont, forGlyphRange range: NSRange) -> Int {
        guard let storage = layoutManager.textStorage else { return 0 }
        var changed = false
        let props = UnsafeMutablePointer<NSLayoutManager.GlyphProperty>.allocate(capacity: range.length)
        defer { props.deallocate() }
        for i in 0..<range.length {
            props[i] = properties[i]
            if let p = MarkdownObjects.glyphProperty(at: characterIndexes[i], in: storage, proposed: props[i]) { props[i] = p; changed = true }
        }
        guard changed else { return 0 }
        layoutManager.setGlyphs(glyphs, properties: props, characterIndexes: characterIndexes, font: font, forGlyphRange: range)
        return range.length
    }
    func layoutManager(_ layoutManager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction,
                       forControlCharacterAt index: Int) -> NSLayoutManager.ControlCharacterAction {
        layoutManager.textStorage.flatMap { MarkdownObjects.controlCharacterAction(at: index, in: $0) } ?? action
    }
    func layoutManager(_ layoutManager: NSLayoutManager, boundingBoxForControlGlyphAt glyphIndex: Int, for container: NSTextContainer,
                       proposedLineFragment rect: NSRect, glyphPosition position: NSPoint, characterIndex index: Int) -> NSRect {
        layoutManager.textStorage.flatMap { MarkdownObjects.boundingBox(at: index, in: $0, glyphPosition: position) } ?? NSRect(origin: position, size: .zero)
    }
}

/// Today's Write view: hides markup, sizes no control glyphs.
final class PlainGlyphDelegate: NSObject, NSLayoutManagerDelegate {}
