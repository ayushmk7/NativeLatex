import AppKit
import XCTest
@testable import LibreWeave

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

    /// Outside New… (e.g. a Dock-click New) the factory uses the controller's default type, the
    /// same one NSDocument is given, so the window's tools match the Save panel's extension.
    func testFactoryWithoutPendingKindUsesControllerDefaultType() throws {
        let fallback = try XCTUnwrap(NSDocumentController.shared.defaultType)
        XCTAssertEqual(NewDocument.makeDocument().contentType.identifier, fallback)
        let markdown = try NewDocument.open(.markdown)
        defer { markdown.close() }
        XCTAssertEqual(NewDocument.makeDocument().contentType.identifier, fallback, "pending kind is cleared after open")
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

    /// File menu: our New… owns ⌘N, Open Another Document… owns ⌘⇧N; Open…, Open Recent and Save stay native.
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
        XCTAssertEqual(shiftN.map { $0.title }, ["Open Another Document…"], "only Open Another Document… claims ⌘⇧N")
        XCTAssertTrue(items.contains { $0.title == "Open Another Document…" }, "it lives in the File menu")
    }

    /// ⌘⇧N shows the same type-filtered Open panel as File > Open…; Cancel opens nothing.
    func testOpenAnotherDocumentShowsNativeOpenPanel() throws {
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let menu = try XCTUnwrap(NSApp.mainMenu?.items.first { $0.title == "File" }?.submenu)
        let index = menu.indexOfItem(withTitle: "Open Another Document…")
        XCTAssertNotEqual(index, -1)
        let before = NSDocumentController.shared.documents.count
        menu.performActionForItem(at: index)
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        let panel = try XCTUnwrap(NSApp.windows.compactMap { $0 as? NSOpenPanel }.first { $0.isVisible }, "Open panel shown")
        let types = Set(panel.allowedContentTypes.map(\.identifier))
        XCTAssertTrue(types.isSuperset(of: ["org.tug.tex", "net.daringfireball.markdown", "public.plain-text"]), "\(types)")
        XCTAssertFalse(types.contains("public.data"), "only document types LibreWeave reads")
        panel.cancel(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(NSDocumentController.shared.documents.count, before, "Cancel opens nothing")
    }

    private func toolbarLabels(_ document: NSDocument) throws -> [String] {
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let window = try XCTUnwrap(document.windowControllers.first?.window)
        return (window.toolbar?.items ?? []).map(\.label)
    }

    /// Before the first save there is no file URL; the window still knows its format.
    func testUntitledWindowsKeepTheirFormatTools() throws {
        let tex = try NewDocument.open(.latex), md = try NewDocument.open(.markdown), txt = try NewDocument.open(.plainText)
        defer { tex.close(); md.close(); txt.close() }
        let texLabels = try toolbarLabels(tex), mdLabels = try toolbarLabels(md), txtLabels = try toolbarLabels(txt)
        XCTAssertTrue(texLabels.contains("Build"), "untitled LaTeX has Build: \(texLabels)")
        XCTAssertTrue(texLabels.contains("Preview"), "and its PDF preview toggle")
        XCTAssertTrue(mdLabels.contains("Preview"), "untitled Markdown has its preview: \(mdLabels)")
        XCTAssertFalse(mdLabels.contains("Build"))
        XCTAssertFalse(txtLabels.contains("Build") || txtLabels.contains("Preview"), "plain text has neither: \(txtLabels)")
    }

    /// File > Duplicate also makes a URL-less document; it keeps the source's format.
    func testDuplicateKeepsFormatTools() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dup-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for (name, tool, absent) in [("notes.md", "Preview", "Build"), ("paper.tex", "Build", nil)] {
            let url = dir.appendingPathComponent(name)
            try "x".write(to: url, atomically: true, encoding: .utf8)
            let original = try NSDocumentController.shared.makeDocument(withContentsOf: url, ofType: name.hasSuffix("md") ? "net.daringfireball.markdown" : "org.tug.tex")
            NSDocumentController.shared.addDocument(original)
            let copy = try original.duplicate()
            defer { copy.close(); original.close() }
            XCTAssertNil(copy.fileURL, "\(name) duplicate is untitled")
            let labels = try toolbarLabels(copy)
            XCTAssertTrue(labels.contains(tool), "\(name) duplicate: \(labels)")
            if let absent { XCTAssertFalse(labels.contains(absent), "\(name) duplicate: \(labels)") }
        }
    }

    /// Build on untitled LaTeX uses the normal Save panel; Cancel writes nothing and returns nil.
    /// The Save button itself isn't driven: the panel runs out of process (ViewBridge), so XCTest
    /// can't set its folder and a confirmed save would land in the user's default folder.
    func testUntitledSaveForBuildCancelWritesNothing() async throws {
        let document = try NewDocument.open(.latex)
        defer { document.close() }
        let window = try XCTUnwrap(document.windowControllers.first?.window)
        let saving = Task { await document.saveUntitled() }
        var panel: NSSavePanel?
        for _ in 0..<40 where panel == nil {
            try await Task.sleep(for: .milliseconds(50))
            panel = window.attachedSheet as? NSSavePanel
        }
        let sheet = try XCTUnwrap(panel, "Build shows the normal Save panel")
        XCTAssertEqual((sheet.nameFieldStringValue as NSString).pathExtension, "tex")
        window.endSheet(sheet, returnCode: .cancel)
        let result = await saving.value
        XCTAssertNil(result, "Cancel: nothing to build")
        XCTAssertNil(document.fileURL, "Cancel: nothing written")
    }

    /// A document that already has a file is returned as-is: no panel, no write.
    func testSaveUntitledReturnsExistingFileWithoutWriting() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("saved-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("paper.tex")
        try "x".write(to: url, atomically: true, encoding: .utf8)
        let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let document = try NSDocumentController.shared.makeDocument(withContentsOf: url, ofType: "org.tug.tex")
        defer { document.close() }
        let result = await document.saveUntitled()
        XCTAssertEqual(result, url)
        var fresh = url; fresh.removeAllCachedResourceValues()
        XCTAssertEqual(try fresh.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, modified)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["paper.tex"])
    }
}
