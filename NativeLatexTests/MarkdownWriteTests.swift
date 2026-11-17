import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import LibreWeave

/// Write mode and the Source / Both / Preview layout, driven through real document windows and the View menu.
@MainActor
final class MarkdownWriteTests: XCTestCase {
    static let fixture = """
    ---
    title: Fixture
    ---

    # Title

    Some **bold**, *it* and a [link](https://example.org) here.

    - item one
    - item two

    | a | b |
    |---|:-:|
    | 1 | 2 |

    ```swift
    let x = "**not bold**"
    ```

    $$\\int_0^1 x\\,dx$$

    <!-- keep me -->
    """

    private var dir: URL!
    private var opened: [NSDocument] = []

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("write-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        for document in opened { document.updateChangeCount(.changeCleared); document.close() }
        try? FileManager.default.removeItem(at: dir)
    }

    private func open(_ name: String, _ text: String, width: CGFloat = 1100) async throws -> (NSDocument, NSWindow) {
        let url = dir.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        // Never displayed or activated: the window is made but not ordered on screen, so tests don't take focus.
        let (document, _) = try await NSDocumentController.shared.openDocument(withContentsOf: url, display: false)
        opened.append(document)
        if document.windowControllers.isEmpty { document.makeWindowControllers() }
        let window = try XCTUnwrap(document.windowControllers.first?.window)
        window.setContentSize(NSSize(width: width, height: 640))
        settle()
        return (document, window)
    }

    private func settle(_ seconds: TimeInterval = 0.4) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    /// The window's segmented controls: the toolbar's Source / Both / Preview and the pane's Read / Write.
    /// (The View menu mirrors them, but menu validation needs a key window, which a background test host never gets.)
    private func segmented(_ count: Int, in window: NSWindow) -> NSSegmentedControl? {
        func find(_ v: NSView) -> NSSegmentedControl? {
            if let c = v as? NSSegmentedControl, c.segmentCount == count { return c }
            return v.subviews.lazy.compactMap(find).first
        }
        // Toolbar item views first (they exist even when the window was never shown), then the window's views.
        return (window.toolbar?.items ?? []).lazy.compactMap { $0.view.flatMap(find) }.first
            ?? window.contentView?.superview.flatMap(find)
    }

    private enum Pane: Int { case source, both, preview }

    private func show(_ pane: Pane, in window: NSWindow, file: StaticString = #filePath, line: UInt = #line) throws {
        let control = try XCTUnwrap(segmented(3, in: window), "layout control", file: file, line: line)
        XCTAssertTrue(control.isEnabled(forSegment: pane.rawValue), "\(pane) enabled", file: file, line: line)
        control.selectedSegment = pane.rawValue
        control.sendAction(control.action, to: control.target)
        settle()
    }

    private func setWrite(_ on: Bool, in window: NSWindow, file: StaticString = #filePath, line: UInt = #line) throws {
        let control = try XCTUnwrap(segmented(2, in: window), "Read/Write control", file: file, line: line)
        control.selectedSegment = on ? 1 : 0
        control.sendAction(control.action, to: control.target)
        settle()
    }

    private func textView(_ label: String, in window: NSWindow) -> NSTextView? {
        func find(_ v: NSView) -> NSTextView? {
            if let t = v as? NSTextView, t.accessibilityLabel() == label { return t }
            return v.subviews.lazy.compactMap(find).first
        }
        return window.contentView.flatMap(find)
    }

    private func webView(in window: NSWindow) -> WKWebView? {
        func find(_ v: NSView) -> WKWebView? { (v as? WKWebView) ?? v.subviews.lazy.compactMap(find).first }
        return window.contentView.flatMap(find)
    }

    /// The Read preview appears once Pandoc has rendered. Yields to the main actor (rather than only spinning
    /// the run loop) so the preview's render task can finish.
    private func renderedPreview(in window: NSWindow) async -> WKWebView? {
        for _ in 0..<100 {
            if let view = webView(in: window) { return view }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    private func text(_ document: NSDocument) throws -> String {
        let wrapper = try document.fileWrapper(ofType: document.fileType ?? "net.daringfireball.markdown")
        return try XCTUnwrap(wrapper.regularFileContents.flatMap { String(data: $0, encoding: .utf8) })
    }

    /// Ordinary writing in Write mode lands in the same Markdown buffer; untouched syntax stays byte-for-byte,
    /// and the saved file reopens with exactly that text.
    func testWriteModeEditsTheSameBufferAndPreservesUntouchedMarkdown() async throws {
        let (document, window) = try await open("notes.md", Self.fixture)
        let source = try XCTUnwrap(textView("Source", in: window))
        try setWrite(true, in: window)
        let writer = try XCTUnwrap(textView("Write", in: window), "Write view shown")
        XCTAssertNil(source.window, "Write fills the window")
        XCTAssertEqual(writer.string, Self.fixture)

        // Looking around changes nothing.
        for offset in stride(from: 0, to: (Self.fixture as NSString).length, by: 17) {
            writer.setSelectedRange(NSRange(location: offset, length: 0))
        }
        settle()
        XCTAssertEqual(try text(document), Self.fixture, "no-op: caret movement and styling never edit")
        XCTAssertFalse(document.isDocumentEdited)

        // Rendered look: heading sized, markup hidden off the caret line, bold applied, literal blocks monospaced.
        window.makeFirstResponder(writer)
        writer.setSelectedRange(NSRange(location: 0, length: 0))
        settle()
        let storage = try XCTUnwrap(writer.textStorage)
        let ns = Self.fixture as NSString
        let headingFont = try XCTUnwrap(storage.attribute(.font, at: ns.range(of: "Title").location, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(headingFont.pointSize, MarkdownStyler.headingSizes[0])
        XCTAssertNotNil(storage.attribute(.markdownHidden, at: ns.range(of: "# Title").location, effectiveRange: nil), "# hidden")
        XCTAssertNotNil(storage.attribute(.markdownHidden, at: ns.range(of: "**bold**").location, effectiveRange: nil), "** hidden")
        let bold = try XCTUnwrap(storage.attribute(.font, at: ns.range(of: "bold**").location, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(bold.fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertNotNil(storage.attribute(.markdownHidden, at: NSMaxRange(ns.range(of: "[link")) , effectiveRange: nil), "](url) hidden")
        let fenced = ns.range(of: "**not bold**")
        XCTAssertNil(storage.attribute(.markdownHidden, at: fenced.location, effectiveRange: nil), "code keeps its characters")
        let table = try XCTUnwrap(storage.attribute(.font, at: ns.range(of: "| a |").location, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(table.isFixedPitch, "tables stay as Markdown")
        writer.setSelectedRange(NSRange(location: ns.range(of: "Some").location, length: 0))
        settle()
        XCTAssertNil(storage.attribute(.markdownHidden, at: ns.range(of: "**bold**").location, effectiveRange: nil), "caret line reveals markup")

        // Write: add words, continue a list, start a paragraph, format, delete.
        var expected = Self.fixture
        func type(_ s: String) { writer.insertText(s, replacementRange: writer.selectedRange()); settle(0.05) }
        writer.setSelectedRange(NSRange(location: NSMaxRange((writer.string as NSString).range(of: "here.")), length: 0))
        type(" More words")
        expected = expected.replacingOccurrences(of: "here.", with: "here. More words")
        writer.setSelectedRange(NSRange(location: NSMaxRange((writer.string as NSString).range(of: "- item two")), length: 0))
        writer.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        type("item three")
        expected = expected.replacingOccurrences(of: "- item two", with: "- item two\n- item three")
        writer.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        writer.doCommand(by: #selector(NSResponder.insertNewline(_:))) // empty item ends the list
        type("Fresh paragraph.")
        expected = expected.replacingOccurrences(of: "- item three", with: "- item three\nFresh paragraph.")
        writer.setSelectedRange((writer.string as NSString).range(of: "Fresh"))
        MarkdownFormat.wrap(writer, marker: "**")
        expected = expected.replacingOccurrences(of: "Fresh paragraph.", with: "**Fresh** paragraph.")
        writer.setSelectedRange((writer.string as NSString).range(of: " More"))
        type("")
        expected = expected.replacingOccurrences(of: " More words", with: " words")
        settle()

        XCTAssertEqual(try text(document), expected)
        XCTAssertEqual(source.string, expected, "Source pane shows the same buffer")
        // Write edits register on the document's undo manager, like Source typing; the end of each real key
        // event closes that undo group, which is what marks the document edited (so closing asks to save).
        XCTAssertTrue(document.undoManager?.canUndo == true, "Write edits are tracked by the document")
        for untouched in ["---\ntitle: Fixture\n---", "| a | b |\n|---|:-:|\n| 1 | 2 |", "```swift\nlet x = \"**not bold**\"\n```",
                          "$$\\int_0^1 x\\,dx$$", "<!-- keep me -->"] {
            XCTAssertTrue(expected.contains(untouched), untouched)
        }

        let url = try XCTUnwrap(document.fileURL)
        try await document.save(to: url, ofType: try XCTUnwrap(document.fileType), for: .saveOperation)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), expected, "saved bytes")
        document.close()
        opened.removeAll { $0 === document }
        let (reopened, reopenedWindow) = try await open("notes.md", expected)
        XCTAssertEqual(try text(reopened), expected)
        XCTAssertEqual(textView("Source", in: reopenedWindow)?.string, expected, "reopened window shows the saved text")
    }

    /// ⌘Z/⇧⌘Z from either pane, including after the pane that made the edit is hidden.
    func testUndoAndRedoAcrossPanesAndLayoutSwitches() async throws {
        let original = "# Notes\n\nFirst line.\n"
        let (document, window) = try await open("undo.md", original)
        let source = try XCTUnwrap(textView("Source", in: window))
        try setWrite(true, in: window)
        let writer = try XCTUnwrap(textView("Write", in: window))
        // ⌘Z's path: the action travels up the responder chain from the focused view to the window's undo manager.
        func send(_ action: String) { _ = window.firstResponder?.tryToPerform(Selector((action)), with: nil); settle(0.2) }

        // Edit in Write, hide Write (Source Only), undo from Source.
        window.makeFirstResponder(writer)
        writer.setSelectedRange(NSRange(location: (original as NSString).length, length: 0))
        writer.insertText("Written.", replacementRange: writer.selectedRange())
        settle()
        XCTAssertEqual(try text(document), original + "Written.")
        try show(.source, in: window)
        XCTAssertNil(writer.window, "Write pane hidden")
        window.makeFirstResponder(source)
        send("undo:")
        XCTAssertEqual(try text(document), original, "⌘Z in Source undoes the Write edit")
        XCTAssertEqual(source.string, original)
        send("redo:")
        XCTAssertEqual(try text(document), original + "Written.", "⇧⌘Z redoes it")

        // Edit in Source, switch to Write (full width), undo from Write.
        source.setSelectedRange(NSRange(location: 0, length: 0))
        source.insertText("Top. ", replacementRange: source.selectedRange())
        settle()
        XCTAssertEqual(try text(document), "Top. " + original + "Written.")
        try setWrite(true, in: window)
        XCTAssertNil(source.window, "Source pane hidden")
        XCTAssertEqual(writer.string, "Top. " + original + "Written.", "hidden edits reached Write")
        window.makeFirstResponder(writer)
        send("undo:")
        XCTAssertEqual(try text(document), original + "Written.", "⌘Z in Write undoes the Source edit")
        send("undo:")
        XCTAssertEqual(try text(document), original)
        XCTAssertEqual(writer.string, original)
        XCTAssertEqual(source.string, original, "hidden Source kept in sync")
        try show(.both, in: window)
        XCTAssertEqual(textView("Source", in: window)?.string, original)
    }

    /// Either pane can fill a wide window, both can share it, and a narrow window offers one at a time.
    func testLayoutShowsEitherPaneFullWidthOrBoth() async throws {
        let (_, window) = try await open("layout.md", "# Layout\n\nText.\n")
        let width = try XCTUnwrap(window.contentView).bounds.width
        let source = try XCTUnwrap(textView("Source", in: window))
        do { let p = await renderedPreview(in: window); XCTAssertNotNil(p, "both panes by default") }

        try show(.source, in: window)
        XCTAssertNil(webView(in: window))
        XCTAssertGreaterThan(try XCTUnwrap(source.enclosingScrollView).frame.width, width - 40, "source full width")

        try show(.preview, in: window)
        XCTAssertNil(source.window, "source hidden")
        let full = await renderedPreview(in: window)
        XCTAssertGreaterThan(try XCTUnwrap(full).frame.width, width - 40, "preview full width")
        try setWrite(true, in: window)
        XCTAssertGreaterThan(try XCTUnwrap(textView("Write", in: window)?.enclosingScrollView).frame.width, width - 40, "Write full width")
        try setWrite(false, in: window) // back to Read

        try show(.both, in: window)
        XCTAssertNotNil(source.window)
        do { let p = await renderedPreview(in: window); XCTAssertNotNil(p) }

        // Narrow: Both falls back to Source and the control says so; widening restores Both.
        let layout = try XCTUnwrap(segmented(3, in: window))
        window.setContentSize(NSSize(width: 640, height: 640))
        settle()
        XCTAssertFalse(layout.isEnabled(forSegment: Pane.both.rawValue), "narrow windows can't show both")
        XCTAssertNil(webView(in: window), "narrow: Both falls back to source")
        XCTAssertEqual(layout.selectedSegment, Pane.source.rawValue, "selection is truthful while narrow")
        let toolbar = try XCTUnwrap(window.toolbar)
        let visible = Set((toolbar.visibleItems ?? []).map(\.itemIdentifier))
        let expected = toolbar.items.filter { $0.view != nil }.map(\.itemIdentifier)
        XCTAssertTrue(expected.allSatisfy(visible.contains), "nothing overflows at minimum width, BB-8 included: \(toolbar.items.map(\.label))")
        window.setContentSize(NSSize(width: 1100, height: 640))
        settle()
        do { let p = await renderedPreview(in: window); XCTAssertNotNil(p, "widening restores Both") }
        XCTAssertEqual(layout.selectedSegment, Pane.both.rawValue)

        window.setContentSize(NSSize(width: 640, height: 640))
        settle()
        try show(.preview, in: window)
        do { let p = await renderedPreview(in: window); XCTAssertNotNil(p) }
        XCTAssertNil(source.window)
        XCTAssertEqual(layout.selectedSegment, Pane.preview.rawValue)
    }

    /// Write is the full-width editor in every path in, and the mode control always matches what is on screen:
    /// Source Only or Source and Preview leave Write; Read returns to the layout Write replaced.
    func testWriteIsFullWidthAndModeMatchesTheVisibleLayout() async throws {
        let (document, window) = try await open("modes.md", "# Modes\n\nText.\n")
        let width = try XCTUnwrap(window.contentView).bounds.width
        let layout = try XCTUnwrap(segmented(3, in: window)), mode = try XCTUnwrap(segmented(2, in: window))
        let source = try XCTUnwrap(textView("Source", in: window))
        func check(_ pane: Pane, write: Bool, _ step: String, line: UInt = #line) async {
            XCTAssertEqual(layout.selectedSegment, pane.rawValue, "\(step): layout", line: line)
            XCTAssertEqual(mode.selectedSegment, write ? 1 : 0, "\(step): mode", line: line)
            XCTAssertEqual(source.window != nil, pane != .preview, "\(step): source shown", line: line)
            let writer = textView("Write", in: window)
            XCTAssertEqual(writer != nil, write, "\(step): Write shown", line: line)
            if let scroll = writer?.enclosingScrollView { XCTAssertGreaterThan(scroll.frame.width, width - 40, "\(step): Write full width", line: line) }
            if pane != .source, !write { let p = await renderedPreview(in: window); XCTAssertNotNil(p, "\(step): Read shown", line: line) }
            if pane == .source { XCTAssertNil(webView(in: window), "\(step): no Read", line: line) }
        }

        await check(.both, write: false, "default")
        try setWrite(true, in: window); await check(.preview, write: true, "Both → Write")
        try setWrite(false, in: window); await check(.both, write: false, "Write → Read restores Both")

        try show(.source, in: window); await check(.source, write: false, "Source Only")
        try setWrite(true, in: window); await check(.preview, write: true, "Source → Write")
        try setWrite(false, in: window); await check(.both, write: false, "Read from Write that replaced Source shows Read beside it")

        try show(.preview, in: window); await check(.preview, write: false, "Preview Only (Read)")
        try setWrite(true, in: window); await check(.preview, write: true, "Read → Write")
        try setWrite(false, in: window); await check(.preview, write: false, "Write → Read keeps Preview Only")

        try setWrite(true, in: window)
        try show(.source, in: window); await check(.source, write: false, "Source Only leaves Write")
        try show(.preview, in: window); await check(.preview, write: false, "Preview Only after leaving Write is Read")
        try setWrite(true, in: window)
        try show(.both, in: window); await check(.both, write: false, "Source and Preview leaves Write")
        XCTAssertFalse(document.isDocumentEdited, "mode changes never edit")

        XCTAssertEqual(PaneState.selfCheck(), [], "every transition, including narrow windows")
    }

    /// ⌥⌘P (View ▸ Toggle Preview) hides the preview, then brings it back beside the source, or alone when narrow.
    func testTogglePreviewShortcutLogic() {
        XCTAssertEqual(PaneLayout.both.toggled(narrow: false), .source)
        XCTAssertEqual(PaneLayout.preview.toggled(narrow: false), .source)
        XCTAssertEqual(PaneLayout.source.toggled(narrow: false), .both)
        XCTAssertEqual(PaneLayout.source.toggled(narrow: true), .preview)
    }

    /// TeX keeps its PDF preview read-only; plain text has no preview controls.
    func testWriteIsMarkdownOnly() async throws {
        let (_, tex) = try await open("paper.tex", "\\documentclass{article}\n")
        XCTAssertNil(segmented(2, in: tex), "no Read/Write for TeX: its PDF preview is read-only")
        try show(.preview, in: tex) // layout still works for the PDF preview
        XCTAssertNil(textView("Source", in: tex)?.window)

        let (_, plain) = try await open("plain.txt", "hello")
        XCTAssertNil(segmented(3, in: plain), "plain text has no preview to lay out")
    }

    /// Switching Read/Write and layouts is view state only: no undo entry, no change, same bytes on disk.
    func testModeAndLayoutTogglesNeverEditTheDocument() async throws {
        let (document, window) = try await open("toggle.md", Self.fixture)
        let url = try XCTUnwrap(document.fileURL)
        let before = try Data(contentsOf: url)
        for _ in 0..<2 {
            try setWrite(true, in: window)
            try show(.preview, in: window)
            try show(.source, in: window)
            try show(.both, in: window)
            try setWrite(false, in: window)
        }
        XCTAssertEqual(try text(document), Self.fixture)
        XCTAssertFalse(document.undoManager?.canUndo ?? false, "nothing registered as an edit")
        XCTAssertFalse(document.isDocumentEdited)
        XCTAssertEqual(try Data(contentsOf: url), before, "file untouched")
    }

    /// Another app's write: a clean buffer reloads (Write shows it); unsaved edits are never replaced, even in Preview Only.
    func testExternalChangeReloadsCleanWriteAndWarnsInPreviewOnly() async throws {
        let (document, window) = try await open("external.md", "# One\n")
        let url = try XCTUnwrap(document.fileURL)
        try setWrite(true, in: window)
        try show(.preview, in: window)
        try "# Two\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path)
        var reloaded = false
        for _ in 0..<40 where !reloaded { try await Task.sleep(for: .milliseconds(100)); reloaded = textView("Write", in: window)?.string == "# Two\n" }
        XCTAssertTrue(reloaded, "clean buffer reloads into Write")

        document.updateChangeCount(.changeDone) // unsaved edits
        try "# Three\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: url.path)
        // The banner itself is SwiftUI content the test host can't inspect; the app smoke test checks it via
        // System Events. Here: after the 2 s disk check has run, the unsaved buffer must not be replaced.
        try await Task.sleep(for: .seconds(3))
        XCTAssertEqual(try text(document), "# Two\n", "unsaved buffer kept, not replaced")
    }

    /// Selecting text keeps the current reveal (no reflow mid-selection); hidden fence lines collapse without a band.
    func testSelectionKeepsLayoutAndHidesFences() async throws {
        let text = "Intro **bold** here.\n\n```\ncode\n```\n\nOther **line**.\n"
        let (_, window) = try await open("select.md", text)
        try setWrite(true, in: window)
        let writer = try XCTUnwrap(textView("Write", in: window))
        let storage = try XCTUnwrap(writer.textStorage)
        let ns = text as NSString
        window.makeFirstResponder(writer)
        writer.setSelectedRange(NSRange(location: ns.range(of: "Other").location, length: 0))
        settle()
        XCTAssertNil(storage.attribute(.markdownHidden, at: ns.range(of: "**line").location, effectiveRange: nil), "caret line revealed")
        XCTAssertNotNil(storage.attribute(.markdownHidden, at: ns.range(of: "**bold").location, effectiveRange: nil))

        writer.setSelectedRange(NSRange(location: 2, length: ns.range(of: "Other").location)) // drag-select up into the intro
        settle()
        XCTAssertNotNil(storage.attribute(.markdownHidden, at: ns.range(of: "**bold").location, effectiveRange: nil), "selection doesn't reveal (no reflow)")
        XCTAssertNil(storage.attribute(.markdownHidden, at: ns.range(of: "**line").location, effectiveRange: nil), "previous reveal kept")

        let fence = ns.range(of: "```\ncode")
        XCTAssertEqual(storage.attribute(.foregroundColor, at: fence.location, effectiveRange: nil) as? NSColor, .clear, "fence hidden")
        let fenceFont = try XCTUnwrap(storage.attribute(.font, at: fence.location, effectiveRange: nil) as? NSFont)
        XCTAssertGreaterThan(fenceFont.pointSize, 1, "hidden fence line keeps its height")
        XCTAssertNil(storage.attribute(.backgroundColor, at: fence.location, effectiveRange: nil), "no grey band on the fence line")
        XCTAssertNotNil(storage.attribute(.backgroundColor, at: ns.range(of: "code\n").location, effectiveRange: nil), "code lines shaded")
    }

    // MARK: Headless pair: Source and Write in one bare window that is never shown or made key.

    /// Both panes wired like EditorView: an edit writes the buffer, then both views sync to it. Offscreen text
    /// views apply undo without sending textDidChange (the app's key window does send it), so storage edits
    /// outside a sync stand in for that path here.
    @MainActor private final class Pair {
        let source = TextViewHandle(), writer = WritingHandle()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        var doc: String
        private var observers: [Any] = []
        var sv: NSTextView { source.view! }
        var wv: NSTextView { writer.view! }

        init(_ text: String) {
            doc = text
            window.isReleasedWhenClosed = false
            let content = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
            window.contentView = content
            let s = source.scrollView(text: text, label: "Source"), w = writer.scrollView(text: text, label: "Write")
            s.frame = NSRect(x: 0, y: 0, width: 450, height: 500); w.frame = NSRect(x: 450, y: 0, width: 450, height: 500)
            content.addSubview(s); content.addSubview(w)
            for handle in [source, writer] as [TextViewHandle] { handle.onText = { [unowned self] in self.set($0) } }
            for view in [sv, wv] {
                observers.append(NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: view.textStorage, queue: nil) { [unowned self] _ in
                    MainActor.assumeIsolated {
                        guard !self.source.isUpdating, !self.writer.isUpdating, view.textStorage!.editedMask.contains(.editedCharacters) else { return }
                        let text = view.string
                        DispatchQueue.main.async { self.set(text) }
                    }
                })
            }
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }

        /// The buffer changed (from a pane, or externally): store it and bring both views to it.
        func set(_ text: String) {
            guard text != doc else { return }
            doc = text
            source.sync(text)
            writer.sync(text)
        }

        func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }

        func key(_ view: NSTextView, _ chars: String, code: UInt16 = 0, settle: Bool = true) {
            window.makeFirstResponder(view) // a bare, unshown window: no app focus change
            for c in chars {
                window.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                                  context: nil, characters: String(c), charactersIgnoringModifiers: String(c), isARepeat: false, keyCode: code)!)
            }
            if settle { pump() }
        }

        func undo() { window.undoManager!.undo(); pump() }
        func redo() { window.undoManager!.redo(); pump() }
        func location(of needle: String) -> Int { (doc as NSString).range(of: needle).location }
    }

    /// Keystrokes typed in one pane, then the other, then the first again: each ⌘Z undoes one pane's typing
    /// in reverse order, even when the other pane's edit shifted the first pane's typing range.
    func testCrossPaneTypingUndoesInOrder() {
        let pair = Pair("# Notes\n\nOne two.\n")
        defer { pair.window.close() }
        XCTAssertIdentical(pair.sv.undoManager, pair.wv.undoManager)
        let one = pair.location(of: "One")
        pair.sv.setSelectedRange(NSRange(location: one, length: 0)); pair.key(pair.sv, "ab")
        pair.wv.setSelectedRange(NSRange(location: one, length: 0)); pair.key(pair.wv, "X") // before Source's typing
        pair.sv.setSelectedRange(NSRange(location: pair.location(of: "bOne") + 1, length: 0)); pair.key(pair.sv, "c")
        let typed = "# Notes\n\nXabcOne two.\n"
        XCTAssertEqual(pair.doc, typed)
        var steps: [String] = []
        for _ in 0..<3 { pair.undo(); steps.append(pair.doc) }
        XCTAssertEqual(steps, ["# Notes\n\nXabOne two.\n", "# Notes\n\nabOne two.\n", "# Notes\n\nOne two.\n"])
        XCTAssertEqual(pair.sv.string, pair.doc)
        XCTAssertEqual(pair.wv.string, pair.doc)
        for _ in 0..<3 { pair.redo() }
        XCTAssertEqual(pair.doc, typed)
        XCTAssertEqual(pair.sv.string, typed)
        XCTAssertEqual(pair.wv.string, typed)
    }

    /// In Write, Return inside fenced code is a plain newline; outside code it still continues a list.
    func testReturnInFencedCodeNeverContinuesListsOrQuotes() {
        let pair = Pair("- item\n\n```diff\n- removed\n> quoted\n```\n")
        defer { pair.window.close() }
        func returnAfter(_ needle: String) {
            let r = (pair.doc as NSString).range(of: needle)
            pair.wv.setSelectedRange(NSRange(location: NSMaxRange(r), length: 0))
            pair.key(pair.wv, "\r", code: 36)
        }
        returnAfter("- removed")
        returnAfter("> quoted")
        XCTAssertEqual(pair.doc, "- item\n\n```diff\n- removed\n\n> quoted\n\n```\n")
        pair.set("```\n- a") // unclosed fence runs to the end of the text
        returnAfter("- a")
        XCTAssertEqual(pair.doc, "```\n- a\n")
        pair.set("- item")
        returnAfter("- item")
        XCTAssertEqual(pair.doc, "- item\n- ", "outside code, Return continues the list")
    }

    /// Return with the caret right after a list or quote marker splits the item; it used to treat the item as
    /// empty and delete the marker ("- foo" became "foo"). A truly empty item still ends the list.
    func testReturnRightAfterAMarkerSplitsTheItem() {
        for (text, caret, expected) in [("- foo", 2, "- \n- foo"), ("1. foo", 3, "1. \n2. foo"), ("> foo", 2, "> \n> foo"),
                                        ("- [ ] task", 6, "- [ ] \n- [ ] task"), ("- ", 2, ""), ("a\n- \nb", 4, "a\n\nb")] {
            let handle = WritingHandle()
            _ = handle.scrollView(text: text, label: "Write")
            let view = handle.view!
            view.setSelectedRange(NSRange(location: caret, length: 0))
            XCTAssertTrue(handle.textView(view, doCommandBy: #selector(NSResponder.insertNewline(_:))), text)
            XCTAssertEqual(view.string, expected, text)
        }
    }

    /// Typing on a fence line (its info string) restyles only the edit, not the whole text: ~1.5 s per keystroke
    /// on 1 MiB before. Incremental styling must equal a full restyle, including edits that open or close a
    /// fence (which change everything after them), and undo must restore the exact source.
    func testFenceLineEditsRestyleLocallyAndMatchAFullRestyle() {
        var big = ""
        while big.utf8.count < 1 << 20 { big += "## H\n\nSome **bold** and *it* with `code`.\n\n- a\n\n```swift\nlet x = 1\n```\n\n" }
        let handle = WritingHandle()
        let scroll = handle.scrollView(text: big, label: "Write")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = scroll // never ordered in
        let view = handle.view!
        func styleRuns(_ s: NSAttributedString) -> [String] {
            var runs: [String] = []
            s.enumerateAttributes(in: NSRange(location: 0, length: s.length)) { a, r, _ in
                let font = a[.font] as? NSFont
                runs.append("\(r.location),\(r.length) \(font?.fontName ?? "-") \(font?.pointSize ?? 0) h\(a[.markdownHidden] != nil) b\(a[.backgroundColor] != nil) c\((a[.foregroundColor] as? NSColor) == .clear)")
            }
            return runs
        }
        func assertMatchesFullRestyle(_ label: String) {
            let fresh = NSTextStorage(string: view.string)
            MarkdownStyler.apply(to: fresh, reveal: NSRange(location: NSNotFound, length: 0))
            XCTAssertEqual(styleRuns(view.textStorage!), styleRuns(fresh), label)
        }
        let infoLine = NSMaxRange((big as NSString).range(of: "```swift", options: [], range: NSRange(location: 500_000, length: 100_000)))
        view.setSelectedRange(NSRange(location: infoLine, length: 0))
        var worst: Duration = .zero
        for ch in ["u", "i"] {
            let start = ContinuousClock.now
            view.insertText(ch, replacementRange: view.selectedRange())
            worst = max(worst, ContinuousClock.now - start)
        }
        XCTAssertLessThan(worst, .milliseconds(150), "keystroke on a fence line \(worst)")
        assertMatchesFullRestyle("info string edit")
        // Structural edits: open a fence mid-paragraph, then close it again by deleting a backtick.
        let para = (view.string as NSString).range(of: "Some **bold**", options: [], range: NSRange(location: 600_000, length: 100_000)).location
        view.setSelectedRange(NSRange(location: para, length: 0))
        view.insertText("```\n", replacementRange: view.selectedRange())
        assertMatchesFullRestyle("new opening fence")
        view.insertText("", replacementRange: NSRange(location: para, length: 1))
        assertMatchesFullRestyle("fence broken by deleting a backtick")
        while view.undoManager?.canUndo == true { view.undoManager?.undo() }
        XCTAssertEqual(view.string, big, "undo restores the exact source")
        assertMatchesFullRestyle("after undo")
    }

    /// Moving the caret onto a hidden fence line reveals it without moving the text below.
    func testRevealingAFenceLineDoesNotShiftTextBelow() {
        let pair = Pair("Intro.\n\n```\ncode\n```\n\nAfter.\n")
        defer { pair.window.close() }
        pair.window.makeFirstResponder(pair.wv)
        func afterY() -> CGFloat {
            let layout = pair.wv.layoutManager!
            layout.ensureLayout(for: pair.wv.textContainer!)
            return layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: pair.location(of: "After")), effectiveRange: nil).minY
        }
        pair.wv.setSelectedRange(NSRange(location: 0, length: 0)); pair.pump()
        let away = afterY()
        pair.wv.setSelectedRange(NSRange(location: pair.location(of: "```") + 1, length: 0)); pair.pump()
        XCTAssertEqual(afterY(), away)
    }

    /// A change from the other pane that shrinks the text across a fence (select-all-and-type, a reload) used to
    /// restyle Write mid-edit from its selection callback and throw NSRangeException.
    func testShrinkingSyncAcrossAFenceDoesNotRestyleMidEdit() {
        let pair = Pair("- item\n\n```diff\n- removed\n> quoted\n```\n")
        defer { pair.window.close() }
        pair.window.makeFirstResponder(pair.wv)
        pair.wv.setSelectedRange(NSRange(location: pair.location(of: "quoted"), length: 0)); pair.pump()
        pair.set("```\n- a")
        pair.set("- item")
        XCTAssertEqual(pair.wv.string, "- item")
    }

    /// A long line of unmatched markers styles in linear time. Unbounded lazy spans took 0.7–2.5 s per
    /// keystroke on a 24–32 KB line; bounded, a 4× longer line costs about 4× (quadratic would be 16×).
    func testLongLinesOfUnmatchedMarkersStyleInLinearTime() {
        func style(_ unit: String, _ count: Int) -> Duration {
            let storage = NSTextStorage(string: String(repeating: unit, count: count))
            let start = ContinuousClock.now
            MarkdownStyler.apply(to: storage, reveal: NSRange(location: NSNotFound, length: 0))
            return ContinuousClock.now - start
        }
        for unit in ["*a ", "**a ", "_a ", "~~a ", "[a ", "![a ", "$a ", "`a "] {
            let short = style(unit, 8000), long = style(unit, 32000)
            XCTAssertLessThan(short, .milliseconds(500), "\(unit) x8000: \(short)")
            XCTAssertLessThan(long / max(short, .microseconds(1)), 8, "\(unit): x8000 \(short), x32000 \(long)")
        }
        // Spans up to the bound still style.
        let em = String(repeating: "x", count: MarkdownStyler.maxInlineSpan - 1)
        let storage = NSTextStorage(string: "*\(em)*")
        MarkdownStyler.apply(to: storage, reveal: NSRange(location: NSNotFound, length: 0))
        XCTAssertNotNil(storage.attribute(.markdownHidden, at: 0, effectiveRange: nil), "emphasis at the bound is styled")
    }

    /// The other pane's sync finds the changed span with a chunked compare; check the edge cases.
    func testCommonEndsFindsTheChangedSpan() {
        func ends(_ a: String, _ b: String) -> [Int] { let r = TextViewHandle.commonEnds(a as NSString, b as NSString); return [r.prefix, r.suffix] }
        XCTAssertEqual(ends("same", "same"), [4, 0])
        XCTAssertEqual(ends("abc", "Xabc"), [0, 3])
        XCTAssertEqual(ends("abc", "abcX"), [3, 0])
        XCTAssertEqual(ends("aaa", "aa"), [2, 0], "suffix never overlaps the prefix")
        XCTAssertEqual(ends("hi 👋 x", "hi 👍 x"), [4, 2], "emoji sharing a high surrogate: the prefix ends mid-pair")
        let long = String(repeating: "é👋 ", count: 5000) // spans several 4096-unit chunks
        XCTAssertEqual(ends(long + "A" + long, long + "BC" + long), [(long as NSString).length, (long as NSString).length])
    }

    /// One keystroke on a 1 MiB document with both panes open: the typing pane, the binding and the other
    /// pane's sync, restyle and layout. Was ~130 ms mean (~420 ms worst) in Source and ~90 ms in Write.
    func testOneMiBKeystrokeWithBothPanesOpen() {
        var big = ""
        while big.utf8.count < 1 << 20 { big += "# Heading café\n\nPara with **bold**, *it*, `code`, [l](u) and 👋🏽.\n- a\n- b\n\n```\ncode\n```\n\n" }
        let pair = Pair(big)
        defer { pair.window.close() }
        for view in [pair.sv, pair.wv] {
            view.setSelectedRange(NSRange(location: 500_000, length: 0))
            pair.key(view, "w") // warm up
            var worst: Duration = .zero
            for c in ["a", "*", "`", "b"] {
                let start = ContinuousClock.now
                pair.key(view, c, settle: false) // the whole edit path runs synchronously inside the key event
                view.layoutManager?.ensureLayout(forCharacterRange: view.selectedRange())
                worst = max(worst, ContinuousClock.now - start)
                pair.pump()
            }
            XCTAssertLessThan(worst, .milliseconds(100), "\(view.accessibilityLabel() ?? "") worst keystroke \(worst)")
        }
        XCTAssertEqual(pair.sv.string, pair.doc)
        XCTAssertEqual(pair.wv.string, pair.doc)
    }

    /// Typing in Write stays responsive on a 1 MiB document (measured ~16 ms per keystroke on Apple silicon).
    func testWriteTypingLatencyOnOneMiBDocument() {
        var big = ""
        while big.utf8.count < 1 << 20 { big += Self.fixture + "\n\nPara with **bold**, *it*, `code` and [l](u).\n- a\n- b\n\n" }
        let handle = WritingHandle()
        let scroll = handle.scrollView(text: big, label: "Write")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = scroll
        let view = try! XCTUnwrap(handle.view)
        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: 500_000, length: 0))
        view.insertText("w", replacementRange: view.selectedRange()) // warm up
        var worst: Duration = .zero
        for ch in ["a", "`", "\n", "*", "b"] {
            let start = ContinuousClock.now
            view.insertText(ch, replacementRange: view.selectedRange())
            view.layoutManager?.ensureLayout(forCharacterRange: view.selectedRange())
            worst = max(worst, ContinuousClock.now - start)
        }
        XCTAssertLessThan(worst, .milliseconds(100), "worst keystroke \(worst)")
    }

    /// Read/Write sits in the toolbar of every Markdown window (.md and .markdown, wide and narrow), stays
    /// reachable in Source Only, and choosing Write there reveals the Write pane. TeX and plain text don't get it.
    /// Hosted in a window that is never put on screen, with SwiftUI's toolbar bridged into it.
    func testReadWriteControlInEveryMarkdownWindowAndLayout() throws {
        func host(_ name: String, width: CGFloat) -> NSWindow {
            var stored = "# Title\n\nBody.\n"
            let binding = Binding<TextDocument>(get: { TextDocument(text: stored) }, set: { stored = $0.text })
            let hosting = NSHostingView(rootView: EditorView(document: binding, fileURL: dir.appendingPathComponent(name)))
            hosting.sceneBridgingOptions = [.toolbars]
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 600),
                                  styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting // never ordered in
            settle()
            return window
        }
        func labels(_ window: NSWindow) -> [String] { (window.toolbar?.items ?? []).map(\.label) }

        for name in ["notes.md", "notes.markdown"] {
            for width: CGFloat in [1100, 640] {
                let window = host(name, width: width)
                defer { window.close() }
                XCTAssertTrue(labels(window).contains("Preview Mode"), "\(name) @\(width): \(labels(window))")
                try show(.source, in: window)
                XCTAssertNil(textView("Write", in: window))
                let mode = try XCTUnwrap(segmented(2, in: window), "\(name) @\(width): Read/Write reachable in Source Only")
                XCTAssertEqual(mode.label(forSegment: 1), "Write")
                mode.selectedSegment = 1
                mode.sendAction(mode.action, to: mode.target)
                settle()
                XCTAssertNotNil(textView("Write", in: window), "\(name) @\(width): choosing Write reveals the Write pane")
                XCTAssertNil(textView("Source", in: window), "\(name) @\(width): Write fills the window")
                if width < EditorView.narrowWidth {
                    let items = window.toolbar?.items.filter { $0.view != nil }.map(\.itemIdentifier) ?? []
                    let visible = Set((window.toolbar?.visibleItems ?? window.toolbar?.items ?? []).map(\.itemIdentifier))
                    XCTAssertTrue(items.allSatisfy(visible.contains), "\(name): nothing overflows at 640 pt: \(labels(window))")
                }
            }
        }
        for name in ["paper.tex", "plain.txt"] {
            let window = host(name, width: 1100)
            defer { window.close() }
            XCTAssertFalse(labels(window).contains("Preview Mode"), "\(name) has no Read/Write: \(labels(window))")
        }
    }
}
