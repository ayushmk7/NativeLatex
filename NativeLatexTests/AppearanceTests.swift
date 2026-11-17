import AppKit
import NativeLatexDesign
import SwiftUI
import XCTest
@testable import LibreLeaf

/// Hosts the real editor window content offscreen and reads its pixels in Light and Dark
/// (the test shell can't take screenshots). PNGs go to $LIBRELEAF_SNAPSHOT_DIR when set.
@MainActor
final class AppearanceTests: XCTestCase {
    func testEditorWindowIsWhiteInLightAndBlackInDark() throws {
        let tex = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).md")
        for (name, appearance, expected) in [("light", NSAppearance.Name.aqua, 255), ("dark", .darkAqua, 0)] {
            let doc = TextDocument(text: "# Title\n\nBody with `code`.")
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
                                  styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false // ARC owns it; the default double-frees on close
            window.appearance = NSAppearance(named: appearance)
            window.contentView = NSHostingView(rootView: EditorView(document: .constant(doc), fileURL: tex))
            window.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            let view = try XCTUnwrap(window.contentView)
            let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            if let dir = ProcessInfo.processInfo.environment["LIBRELEAF_SNAPSHOT_DIR"] {
                try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("editor-\(name).png"))
            }
            // Editor background, well inside the source pane, below the first lines.
            let color = try XCTUnwrap(rep.colorAt(x: rep.pixelsWide / 4, y: rep.pixelsHigh * 3 / 4)?.usingColorSpace(.sRGB))
            XCTAssertEqual(Int(color.redComponent * 255), expected, accuracy: 2, "\(name) editor background")
            XCTAssertEqual(Int(color.blueComponent * 255), expected, accuracy: 2, "\(name) editor background")
            window.close()
        }
    }

    /// Narrow windows show one full-width pane; the same text view (undo history, caret) survives
    /// crossing the breakpoint in both directions.
    func testNarrowWindowShowsOnePaneAndKeepsTheSameEditor() throws {
        let md = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).md")
        let doc = TextDocument(text: "# Title\n\nSee [a link](https://example.org).")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 560),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: EditorView(document: .constant(doc), fileURL: md))
        func settle(_ width: CGFloat) throws -> NSTextView {
            window.setContentSize(NSSize(width: width, height: 560))
            window.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            if let dir = ProcessInfo.processInfo.environment["LIBRELEAF_SNAPSHOT_DIR"], let view = window.contentView,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("layout-\(Int(width)).png"))
            }
            func find(_ v: NSView) -> NSTextView? { (v as? NSTextView) ?? v.subviews.lazy.compactMap(find).first }
            return try XCTUnwrap(find(window.contentView!))
        }
        let wide = try settle(1000)
        XCTAssertLessThan(try XCTUnwrap(wide.enclosingScrollView).frame.width, 600, "side by side when wide")
        let narrow = try settle(640)
        XCTAssertIdentical(narrow, wide, "narrow layout reuses the editor")
        XCTAssertGreaterThan(try XCTUnwrap(narrow.enclosingScrollView).frame.width, 600, "source fills a narrow window")
        XCTAssertIdentical(try settle(1000), wide, "and so does widening again")
        XCTAssertEqual(wide.string, doc.text)
        window.close()
    }

    func testMarkdownPreviewStatesLimitsAndStylesLinks() throws {
        for word in ["tables", "images", "math", "footnotes"] {
            XCTAssertTrue(MarkdownPreview.limitations.contains(word), word)
        }
        let text = MarkdownPreview.inline("See [a link](https://example.org) here.")
        let link = try XCTUnwrap(text.runs.first { $0.link != nil })
        XCTAssertEqual(link.underlineStyle, .single, "links are underlined, not color-only")
        XCTAssertEqual(link.foregroundColor, Theme.accentText)
        XCTAssertNil(text.runs.first { $0.link == nil }?.foregroundColor, "plain text keeps the default color")
    }

    /// Resizing across the narrow breakpoint keeps the same editor, focused, with its caret and undo
    /// history, and typing still reaches the document.
    func testResizingAcrossBreakpointKeepsFocusCaretUndoAndTyping() throws {
        let md = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).md")
        var stored = "# Title\n\nBody."
        let binding = Binding<TextDocument>(get: { TextDocument(text: stored) }, set: { stored = $0.text })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 520),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: EditorView(document: binding, fileURL: md))
        func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.5)) }
        func find(_ v: NSView) -> NSTextView? { (v as? NSTextView) ?? v.subviews.lazy.compactMap(find).first }
        func type(_ chars: String) throws {
            for c in chars {
                window.sendEvent(try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                                windowNumber: window.windowNumber, context: nil, characters: String(c),
                                                                charactersIgnoringModifiers: String(c), isARepeat: false, keyCode: 0)))
            }
            pump()
        }
        pump()
        let editor = try XCTUnwrap(find(window.contentView!))
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        try type("X")
        for width in [640.0, 1000.0, 640.0] {
            window.setContentSize(NSSize(width: width, height: 520))
            pump()
            XCTAssertIdentical(find(window.contentView!), editor, "same editor at \(width)")
            XCTAssertIdentical(window.firstResponder, editor, "editor keeps focus at \(width)")
            XCTAssertEqual(editor.selectedRange().location, 3, "caret kept at \(width)")
        }
        try type("Y")
        XCTAssertEqual(stored, "# XYTitle\n\nBody.", "typing reaches the document")
        // History survives; performing undo needs DocumentGroup's document undo, so it is checked live, not here.
        XCTAssertTrue(editor.undoManager?.canUndo ?? false, "undo history kept")
        window.close()
    }
}
