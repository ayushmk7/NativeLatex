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
}
