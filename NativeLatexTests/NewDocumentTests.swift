import AppKit
import XCTest
@testable import LibreLeaf

/// File > New… (⌘N): format chooser, then an untitled document of that type.
@MainActor
final class NewDocumentTests: XCTestCase {
    /// Each kind opens an untitled, unsaved document whose first Save suggests the right extension.
    func testEachKindOpensUntitledDocumentWithMatchingExtension() throws {
        let expected: [(NewDocumentKind, String, String)] = [
            (.latex, "org.tug.tex", "tex"),
            (.markdown, "net.daringfireball.markdown", "md"),
            (.plainText, "public.plain-text", "txt"),
        ]
        for (kind, uti, ext) in expected {
            let document = try NewDocument.open(kind)
            defer { document.close() }
            XCTAssertNil(document.fileURL, "\(kind) must not be written anywhere before the first save")
            XCTAssertEqual(document.fileType, uti)
            XCTAssertEqual(document.fileNameExtension(forType: uti, saveOperation: .saveOperation), ext)
            XCTAssertTrue(NSDocumentController.shared.documents.contains(document))
            XCTAssertTrue(document.windowControllers.first?.window?.isVisible ?? false, "\(kind) opens its own window")
            XCTAssertTrue(document.writableTypes(for: .saveOperation).contains(uti), "Save panel can keep \(ext)")
        }
    }

    /// First save of an untitled document opens the real Save panel with the chosen extension.
    func testFirstSaveAsksForLocationWithChosenExtension() throws {
        for (kind, ext) in [(NewDocumentKind.latex, "tex"), (.markdown, "md"), (.plainText, "txt")] {
            let document = try NewDocument.open(kind)
            defer { document.close() }
            let window = try XCTUnwrap(document.windowControllers.first?.window)
            document.save(nil) // ⌘S
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            let panel = try XCTUnwrap(window.attachedSheet as? NSSavePanel, "\(kind): ⌘S shows a Save panel")
            XCTAssertEqual((panel.nameFieldStringValue as NSString).pathExtension, ext, "\(kind) suggested name: \(panel.nameFieldStringValue)")
            XCTAssertNil(document.fileURL, "nothing saved until the user confirms")
            window.endSheet(panel, returnCode: .cancel)
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            XCTAssertNil(document.fileURL, "Cancel leaves the document untitled")
        }
    }

    /// Two new documents get two independent windows, like DocumentGroup's own New.
    func testNewDocumentsGetSeparateWindows() throws {
        let a = try NewDocument.open(.latex), b = try NewDocument.open(.markdown)
        defer { a.close(); b.close() }
        XCTAssertNotIdentical(a.windowControllers.first?.window, b.windowControllers.first?.window)
    }

    /// Chooser lists the three formats in order, and Cancel is reachable with Esc.
    func testChooserOffersThreeFormatsAndCancel() {
        let buttons = NewDocument.chooser().buttons
        XCTAssertEqual(buttons.map(\.title), ["LaTeX (.tex)", "Markdown (.md)", "Plain Text (.txt)", "Cancel"])
        XCTAssertEqual(buttons.first?.keyEquivalent, "\r", "Return picks LaTeX")
        XCTAssertEqual(buttons.last?.keyEquivalent, "\u{1b}", "Esc cancels")
    }

    /// File menu: our New… owns ⌘N, Open Another App… owns ⌘⇧N; Open…, Open Recent and Save stay native.
    func testFileMenuKeepsNativeItems() throws {
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let items = try XCTUnwrap(NSApp.mainMenu?.items.first { $0.title == "File" }?.submenu).items
        let new = try XCTUnwrap(items.first { $0.title == "New…" })
        XCTAssertEqual(new.keyEquivalent, "n")
        XCTAssertEqual(new.keyEquivalentModifierMask, .command)
        XCTAssertFalse(items.contains { $0.title == "New" }, "DocumentGroup's chooser-less New is replaced")
        for title in ["Open…", "Open Recent", "Save", "Save As…", "Close"] {
            XCTAssertTrue(items.contains { $0.title == title }, "\(title) still in File menu")
        }
        let allItems: [NSMenuItem] = (NSApp.mainMenu?.items ?? []).flatMap { $0.submenu?.items ?? [] }
        let shiftN = allItems.filter { item in
            item.keyEquivalent.lowercased() == "n" && item.keyEquivalentModifierMask.contains([.command, .shift])
        }
        XCTAssertEqual(shiftN.map { $0.title }, ["Open Another App…"], "only Open Another App… claims ⌘⇧N")
        XCTAssertTrue(items.contains { $0.title == "Open Another App…" }, "it lives in the File menu")
    }

    /// The chooser picks exactly one .app (not a folder, not a file inside a bundle), starting in
    /// /Applications; validation accepts real apps only. Nothing is launched.
    func testOpenAnotherAppChooserOnlyAcceptsApps() throws {
        let panel = OpenAnotherApp.chooser()
        XCTAssertEqual(panel.allowedContentTypes, [.applicationBundle])
        XCTAssertTrue(panel.canChooseFiles)
        XCTAssertFalse(panel.canChooseDirectories)
        XCTAssertFalse(panel.allowsMultipleSelection)
        XCTAssertFalse(panel.treatsFilePackagesAsDirectories)
        XCTAssertEqual(panel.directoryURL?.path, "/Applications")
        XCTAssertEqual(panel.prompt, "Open")

        let calculator = try XCTUnwrap(NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.calculator"))
        XCTAssertTrue(OpenAnotherApp.isApplication(calculator))
        XCTAssertFalse(OpenAnotherApp.isApplication(calculator.appendingPathComponent("Contents/Info.plist")))
        XCTAssertFalse(OpenAnotherApp.isApplication(URL(fileURLWithPath: "/Applications", isDirectory: true)))
        XCTAssertFalse(OpenAnotherApp.isApplication(URL(fileURLWithPath: "/bin/ls")), "bare executables are not apps")
        let plugIns = calculator.deletingLastPathComponent().appendingPathComponent("Home.app/Contents/PlugIns")
        if let appex = try? FileManager.default.contentsOfDirectory(at: plugIns, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "appex" }) {
            XCTAssertFalse(OpenAnotherApp.isApplication(appex), "app extensions are not apps")
        }
        let text = FileManager.default.temporaryDirectory.appendingPathComponent("not-an-app-\(UUID()).txt")
        try "x".write(to: text, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: text) }
        XCTAssertFalse(OpenAnotherApp.isApplication(text))
    }
}
