import AppKit
import NativeLatexIntegrations
import WebKit
import XCTest
@testable import LibreLeaf

@MainActor
final class MarkdownPreviewTests: XCTestCase {
    static let fixture = #"""
    # Rich Preview

    Intro with a [link](https://example.org), *emphasis* and inline math $e^{i\pi} + 1 = 0$.[^note]

    - item one
    - item two
      1. nested

    | Engine | Math |
    |:-------|-----:|
    | pdfTeX | yes  |
    | LuaTeX | yes  |

    ![A red square](figs/dot.png)

    ![escape](../outside.png) ![absolute](file:///etc/hosts) ![remote](https://example.org/x.png)

    $$\int_0^1 x^2\,dx = \frac{1}{3}$$

    ```swift
    print("never runs")
    ```

    <script>document.title = "pwned"</script>
    <img src="x" onerror="document.title='pwned'">
    \input{/etc/passwd}

    [^note]: A footnote.
    """#

    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("md-\(UUID().uuidString)/doc")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("figs"), withIntermediateDirectories: true)
        try Self.png(.systemRed).write(to: folder.appendingPathComponent("figs/dot.png"))
        try Self.png(.systemGreen).write(to: folder.deletingLastPathComponent().appendingPathComponent("outside.png"))
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }

    private static func png(_ color: NSColor) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 40, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill(); NSRect(x: 0, y: 0, width: 40, height: 40).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    private func pandocOrSkip() throws -> URL {
        guard let pandoc = ToolPaths.discover().pandoc else { throw XCTSkip("Pandoc not installed") }
        return pandoc
    }

    func testFixtureRendersTablesMathFootnotesImagesAndKeepsRawHTMLInert() async throws {
        _ = try pandocOrSkip()
        let source = folder.appendingPathComponent("rich.md")
        try Self.fixture.write(to: source, atomically: true, encoding: .utf8)
        let before = try Data(contentsOf: source)

        let html = try await MarkdownRenderer.render(Self.fixture)
        let page = MarkdownRenderer.page(body: html)
        try page.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("libreleaf-markdown-preview.html"), atomically: true, encoding: .utf8)
        add(XCTAttachment(string: page))

        for needle in ["<h1", "<table", "<th style=\"text-align: left;\">Engine", "<ol", "<math", "display=\"block\"", "<mfrac>",
                       "src=\"figs/dot.png\"", "class=\"footnotes", "<pre class=\"sourceCode swift\"", "href=\"https://example.org\"",
                       "&lt;script&gt;", "\\input{/etc/passwd}"] {
            XCTAssertTrue(html.contains(needle), "missing \(needle)")
        }
        XCTAssertFalse(html.contains("<script"), "raw HTML must stay text")
        XCTAssertFalse(html.contains("onerror=\""), "raw HTML attributes must stay text")
        XCTAssertFalse(page.contains("mathjax") || page.contains("<link") || page.contains("@import"), "no CDN or remote stylesheets/scripts")
        XCTAssertTrue(page.contains("default-src 'none'"))
        XCTAssertEqual(try Data(contentsOf: source), before, "source file is never written")
    }

    func testMissingPandocAndOversizeInputAreActionable() async {
        do { _ = try await MarkdownRenderer.render("# hi", pandoc: nil); XCTFail() } catch {
            XCTAssertEqual(error as? MarkdownRenderer.Failure, .missingPandoc)
            XCTAssertTrue(error.localizedDescription.contains("brew install pandoc"))
            XCTAssertTrue(error.localizedDescription.contains("Try Again"))
        }
        let huge = String(repeating: "x", count: MarkdownRenderer.maxInputBytes + 1)
        do { _ = try await MarkdownRenderer.render(huge, pandoc: URL(fileURLWithPath: "/usr/bin/true")); XCTFail() } catch {
            XCTAssertEqual(error as? MarkdownRenderer.Failure, .tooLarge(huge.utf8.count))
        }
    }

    func testCancellingARenderStopsPandocAndCleansUp() async throws {
        _ = try pandocOrSkip()
        let tmp = FileManager.default.temporaryDirectory
        func workDirs() throws -> Int { try FileManager.default.contentsOfDirectory(atPath: tmp.path).filter { $0.hasPrefix("libreleaf-preview-") }.count }
        let before = try workDirs()
        let big = String(repeating: "| a | $x^2$ | **b** |\n|---|---|---|\n| 1 | $\\frac{1}{2}$ | [l](u) |\n\n", count: 40_000)
        let started = ContinuousClock.now
        let task = Task { try await MarkdownRenderer.render(big) }
        try await Task.sleep(for: .milliseconds(150))
        task.cancel()
        do { _ = try await task.value; XCTFail("render should be cancelled") } catch { XCTAssertTrue(error is CancellationError, "\(error)") }
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(3), "cancel must not wait for Pandoc to finish")
        XCTAssertEqual(try workDirs(), before, "temp copy removed")
    }

    func testLaunchFailureAndSIGTERMIgnoringRendererAreSurfaced() async throws {
        let notExecutable = folder.appendingPathComponent("pandoc")
        try "not a program".write(to: notExecutable, atomically: true, encoding: .utf8)
        do { _ = try await MarkdownRenderer.render("# hi", pandoc: notExecutable); XCTFail() } catch {
            XCTAssertTrue(error.localizedDescription.contains("couldn’t start"), error.localizedDescription)
        }

        let stubborn = folder.appendingPathComponent("stubborn")
        try "#!/bin/sh\ntrap '' TERM\nexec sleep 30\n".write(to: stubborn, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stubborn.path)
        let started = ContinuousClock.now
        let task = Task { try await MarkdownRenderer.render("# hi", pandoc: stubborn) }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError, "\(error)") }
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(4), "SIGKILL follows an ignored SIGTERM")
    }

    /// Rapid typing: renders cancelled at every point (before launch, mid-launch, mid-run) leave no Pandoc behind.
    func testRapidCancellationLeavesNoRendererProcesses() async throws {
        _ = try pandocOrSkip()
        var tasks: [Task<String, Error>] = []
        for i in 0..<40 {
            let task = Task { try await MarkdownRenderer.render(Self.fixture + String(repeating: "\n\nmore $x_\(i)$", count: 2000)) }
            if i % 4 != 3 { try await Task.sleep(for: .microseconds(i * 250)); task.cancel() }
            tasks.append(task)
        }
        var finished = 0
        for task in tasks {
            do { _ = try await task.value; finished += 1 } catch { XCTAssertTrue(error is CancellationError, "\(error)") }
        }
        XCTAssertGreaterThanOrEqual(finished, 10, "uncancelled renders complete")
        try await Task.sleep(for: .milliseconds(1500)) // past the SIGKILL escalation
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-l", "-P", String(getpid()), "pandoc"]
        let out = Pipe()
        pgrep.standardOutput = out
        try pgrep.run()
        pgrep.waitUntilExit()
        let survivors = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(pgrep.terminationStatus, 1, "no renderer process survives cancellation: \(survivors)")
    }

    func testAssetHandlerServesOnlyImagesInsideTheDocumentFolder() throws {
        try "SECRET".write(to: folder.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link.png"),
                                                   withDestinationURL: folder.deletingLastPathComponent().appendingPathComponent("outside.png"))
        func url(_ s: String) -> URL { URL(string: s, relativeTo: LocalAssetHandler.baseURL)!.absoluteURL }
        XCTAssertEqual(LocalAssetHandler.resolve(url("figs/dot.png"), in: folder)?.lastPathComponent, "dot.png")
        for blocked in ["../outside.png", "/../outside.png", "%2E%2E/outside.png", "link.png", "notes.txt", "figs/missing.png", "figs"] {
            XCTAssertNil(LocalAssetHandler.resolve(url(blocked), in: folder), blocked)
        }
        XCTAssertNil(LocalAssetHandler.resolve(URL(string: "libreleaf-local://other/figs/dot.png")!, in: folder))
        XCTAssertNil(LocalAssetHandler.resolve(url("figs/dot.png"), in: nil), "untitled documents load no files")
    }

    /// Real WebKit: images load only through the guarded scheme, page scripts never run, math is typeset,
    /// typing updates in place without losing scroll, and light/dark screenshots are written for review.
    func testWebViewRendersFixtureSafelyAndKeepsScrollOnUpdate() async throws {
        _ = try pandocOrSkip()
        let html = try await MarkdownRenderer.render(Self.fixture)
        let coordinator = MarkdownWebView.Coordinator()
        let view = MarkdownWebView.makeWebView(coordinator)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = view
        defer { window.close() }

        func js(_ script: String) async throws -> Any? { try await view.evaluateJavaScript(script) }
        func waitFor(_ script: String) async throws {
            for _ in 0..<100 {
                if (try? await js(script)) as? Bool == true { return }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTFail("timed out waiting for \(script)")
        }

        coordinator.show(html + "<script>document.title='pwned'</script>", folder: folder, in: view)
        try await waitFor("document.getElementById('content') !== null && document.readyState === 'complete' && Array.from(document.images).filter(i => i.complete).length === document.images.length")
        let width = try await js("document.querySelector('img[src=\"figs/dot.png\"]').naturalWidth") as? Int
        XCTAssertEqual(width, 40, "relative image loads")
        let loaded = try await js("Array.from(document.images).filter(i => i.naturalWidth > 0).length") as? Int
        let total = try await js("document.images.length") as? Int
        XCTAssertEqual(loaded, 1, "traversal, file:// and remote images blocked")
        XCTAssertEqual(total, 4)
        XCTAssertEqual(coordinator.assets.served, ["dot.png"])
        let title = try await js("document.title") as? String
        XCTAssertNotEqual(title, "pwned", "page scripts are disabled")
        let mathHeight = try await js("document.querySelector('math[display=block]').getBoundingClientRect().height") as? Double ?? 0
        XCTAssertGreaterThan(mathHeight, 20, "display math is typeset as MathML, not raw TeX")
        let linkColor = try await js("getComputedStyle(document.querySelector('a')).color") as? String
        XCTAssertEqual(linkColor, "rgb(65, 105, 225)", "royal-blue links")

        try await snapshot(view, name: "libreleaf-markdown-light.png")
        window.appearance = NSAppearance(named: .darkAqua)
        try await waitFor("getComputedStyle(document.querySelector('a')).color === 'rgb(139, 166, 255)'")
        try await snapshot(view, name: "libreleaf-markdown-dark.png")

        // Typing: content swaps in place and the reader's scroll position survives.
        let long = html + String(repeating: "<p>filler paragraph</p>", count: 200)
        coordinator.show(long, folder: folder, in: view)
        try await waitFor("document.body.scrollHeight > 2000")
        _ = try await js("window.scrollTo(0, 800); 0")
        coordinator.show(long + "<p id=\"typed\">typed</p>", folder: folder, in: view)
        try await waitFor("document.getElementById('typed') !== null")
        let scrollY = try await js("window.scrollY") as? Double
        XCTAssertEqual(scrollY, 800, "unsaved edits update via evaluateJavaScript with page JS off, keeping scroll")
    }

    private func snapshot(_ view: WKWebView, name: String) async throws {
        let image = try await view.takeSnapshot(configuration: nil)
        let png = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))?.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try png.write(to: url)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("Markdown preview screenshot: \(url.path)")
    }
}
