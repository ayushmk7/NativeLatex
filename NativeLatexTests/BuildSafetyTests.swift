import PDFKit
import XCTest
@testable import LibreLeaf

@MainActor
final class BuildSafetyTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        // Temp dir lives under /var -> /private/var, which exercises symlinked-path mapping.
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: folder) }

    private func write(_ name: String, _ text: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testMaliciousRootNamesAreRejectedBeforeAnyProcessRuns() async throws {
        for name in ["-pdflatex=touch PWNED;.tex", "a`touch PWNED`.tex", "$(touch PWNED).tex", "x;touch PWNED.tex", ".hidden.tex", "notes.txt"] {
            XCTAssertFalse(BuildService.isSafeRootName(name), name)
            let root = try write(name, #"\documentclass{article}\begin{document}x\end{document}"#)
            do { _ = try await BuildService().build(root: root); XCTFail(name) }
            catch { XCTAssertEqual(error as? BuildError, .unsafeName(name)) }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("PWNED").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(BuildService.buildFolderName).path))

        for name in ["paper.tex", "My Paper_v2-final.tex", "thèse 2.TEX", "notes.ltx", "book.latex"] {
            XCTAssertTrue(BuildService.isSafeRootName(name), name)
        }
        let args = BuildService.arguments(engine: "latexmk", root: folder.appendingPathComponent("My Paper.tex"))
        XCTAssertEqual(Array(args.suffix(2)), ["-outdir=.libreleaf-build/My Paper-\(BuildService.ownerToken.prefix(8))", "./My Paper.tex"])
        XCTAssertTrue(args.contains("-norc") && args.contains("-no-shell-escape"))
        XCTAssertFalse(args.joined().contains(folder.path), "absolute folder path must not reach latexmk")
    }

    func testOutputFolderRefusesForgedMarkersAndSymlinks() throws {
        let fm = FileManager.default
        let build = folder.appendingPathComponent(".libreleaf-build")
        let victim = try write("victim.txt", "FAKE_API_KEY=test-not-real")

        // Forged marker shipped with a project.
        let forged = build.appendingPathComponent(BuildService.outputName(for: folder.appendingPathComponent("forged.tex")))
        try fm.createDirectory(at: forged, withIntermediateDirectories: true)
        try "LibreLeaf\n".write(to: forged.appendingPathComponent(".libreleaf-owner"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try BuildService.prepareOutputDirectory(for: folder.appendingPathComponent("forged.tex")))

        // Output folder is a symlink to elsewhere.
        try fm.createSymbolicLink(at: build.appendingPathComponent(BuildService.outputName(for: folder.appendingPathComponent("linked.tex"))),
                                  withDestinationURL: folder)
        XCTAssertThrowsError(try BuildService.prepareOutputDirectory(for: folder.appendingPathComponent("linked.tex")))

        // Our own folder is reusable until a symlink is planted inside it.
        let root = folder.appendingPathComponent("paper.tex")
        let out = try BuildService.prepareOutputDirectory(for: root)
        XCTAssertNoThrow(try BuildService.prepareOutputDirectory(for: root))
        try fm.createSymbolicLink(at: out.appendingPathComponent("paper.pdf"), withDestinationURL: victim)
        XCTAssertThrowsError(try BuildService.prepareOutputDirectory(for: root))
        XCTAssertEqual(try String(contentsOf: victim, encoding: .utf8), "FAKE_API_KEY=test-not-real")
    }

    func testOutputFolderRefusesNestedSymlinksAndHardLinks() async throws {
        let fm = FileManager.default
        let canary = try write("canary.txt", "CANARY")
        let root = try write("paper.tex", #"\documentclass{article}\begin{document}x\end{document}"#)
        let out = try BuildService.prepareOutputDirectory(for: root)

        // Symlink two levels down inside an otherwise owned folder.
        let nested = out.appendingPathComponent("chapters/deep", isDirectory: true)
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: nested.appendingPathComponent("paper.aux"), withDestinationURL: canary)
        XCTAssertThrowsError(try BuildService.prepareOutputDirectory(for: root))
        do { _ = try await BuildService().build(root: root); XCTFail("build must refuse a linked output tree") }
        catch { XCTAssertEqual(error as? BuildError, .unownedOutputDirectory(out.path)) }

        // Symlinked subfolder pointing outside.
        try fm.removeItem(at: out.appendingPathComponent("chapters"))
        try fm.createSymbolicLink(at: out.appendingPathComponent("chapters"), withDestinationURL: folder)
        XCTAssertThrowsError(try BuildService.prepareOutputDirectory(for: root))

        // Nested hard link to a file outside the tree.
        try fm.removeItem(at: out.appendingPathComponent("chapters"))
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        try fm.linkItem(at: canary, to: nested.appendingPathComponent("paper.log"))
        XCTAssertThrowsError(try BuildService.prepareOutputDirectory(for: root))

        // Clean nested folders stay reusable.
        try fm.removeItem(at: nested.appendingPathComponent("paper.log"))
        try "aux".write(to: nested.appendingPathComponent("ok.aux"), atomically: true, encoding: .utf8)
        XCTAssertNoThrow(try BuildService.prepareOutputDirectory(for: root))
        XCTAssertEqual(try String(contentsOf: canary, encoding: .utf8), "CANARY")
    }

    /// chmod 0300 (write+search, no read) hid a nested symlink from FileManager.enumerator while TeX
    /// could still write through the known path. The scan must refuse what it can't list.
    func testUnreadableNestedFolderFailsClosed() async throws {
        let fm = FileManager.default
        let canary = try write("canary.txt", "CANARY")
        let root = try write("paper.tex", #"\documentclass{article}\begin{document}x\end{document}"#)
        let out = try BuildService.prepareOutputDirectory(for: root)
        let hidden = out.appendingPathComponent("chapters", isDirectory: true)
        try fm.createDirectory(at: hidden, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: hidden.appendingPathComponent("paper.aux"), withDestinationURL: canary)
        try fm.setAttributes([.posixPermissions: 0o300], ofItemAtPath: hidden.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hidden.path) }

        XCTAssertThrowsError(try BuildService.isPlainTree(out))
        XCTAssertThrowsError(try BuildService.prepareOutputDirectory(for: root))
        do { _ = try await BuildService().build(root: root); XCTFail("build must refuse an unlistable output tree") }
        catch { XCTAssertEqual(error as? BuildError, .unownedOutputDirectory(out.path)) }
        XCTAssertEqual(try String(contentsOf: canary, encoding: .utf8), "CANARY")

        // Readable but not searchable (0600) also fails closed; restoring 0755 makes it reusable.
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: hidden.path)
        XCTAssertThrowsError(try BuildService.prepareOutputDirectory(for: root))
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hidden.path)
        try fm.removeItem(at: hidden.appendingPathComponent("paper.aux"))
        XCTAssertNoThrow(try BuildService.prepareOutputDirectory(for: root))
    }

    /// A reset token (defaults wiped, folder copied from another Mac) must not block the folder
    /// forever: it gets a fresh folder, the old output stays, and forged markers are still refused.
    func testLostOwnerTokenGetsFreshFolderAndKeepsOldOutput() throws {
        let defaults = UserDefaults.standard, key = "buildOwnerToken"
        let saved = defaults.string(forKey: key)
        defer { if let saved { defaults.set(saved, forKey: key) } else { defaults.removeObject(forKey: key) } }
        let root = try write("paper.tex", "x")
        let old = try BuildService.prepareOutputDirectory(for: root)
        try "OLD".write(to: old.appendingPathComponent("paper.pdf"), atomically: true, encoding: .utf8)

        defaults.set(UUID().uuidString, forKey: key)
        let fresh = try BuildService.prepareOutputDirectory(for: root)
        XCTAssertNotEqual(fresh, old)
        XCTAssertEqual(try String(contentsOf: old.appendingPathComponent("paper.pdf"), encoding: .utf8), "OLD")
        XCTAssertTrue(BuildService.arguments(engine: "latexmk", root: root).contains("-outdir=.libreleaf-build/\(fresh.lastPathComponent)"))

        // Someone who guesses the new folder name still can't forge the full token.
        let other = try write("other.tex", "x")
        let guessed = folder.appendingPathComponent(".libreleaf-build/\(BuildService.outputName(for: other))")
        try FileManager.default.createDirectory(at: guessed, withIntermediateDirectories: true)
        try String(BuildService.ownerToken.prefix(8)).write(to: guessed.appendingPathComponent(".libreleaf-owner"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try BuildService.prepareOutputDirectory(for: other))
    }

    /// After the bundle ID change, the LibreLeaf-era token is adopted (old folders stay owned and
    /// untouched), the old domain is not changed, a current token wins, and a malformed one is ignored.
    func testOwnerTokenMigratesFromLibreLeafDomain() throws {
        func suite() -> (UserDefaults, String) {
            let name = "libreweave.test.\(UUID().uuidString)"
            return (UserDefaults(suiteName: name)!, name)
        }
        let (current, currentName) = suite(), (legacy, legacyName) = suite()
        defer { current.removePersistentDomain(forName: currentName); legacy.removePersistentDomain(forName: legacyName) }
        let old = UUID().uuidString
        legacy.set(old, forKey: "buildOwnerToken")

        XCTAssertEqual(BuildService.ownerToken(in: current, legacy: legacy), old)
        XCTAssertEqual(current.string(forKey: "buildOwnerToken"), old, "migrated once, then read from the new domain")
        XCTAssertEqual(legacy.string(forKey: "buildOwnerToken"), old, "old preferences are left as they were")
        legacy.set(UUID().uuidString, forKey: "buildOwnerToken")
        XCTAssertEqual(BuildService.ownerToken(in: current, legacy: legacy), old, "an existing new-domain token wins")

        let (fresh, freshName) = suite()
        defer { fresh.removePersistentDomain(forName: freshName) }
        legacy.set("", forKey: "buildOwnerToken")
        let made = BuildService.ownerToken(in: fresh, legacy: legacy)
        XCTAssertNotNil(UUID(uuidString: made), "a blank legacy value is not adopted")
        XCTAssertNotNil(UUID(uuidString: BuildService.ownerToken(in: suite().0, legacy: nil)))
        XCTAssertEqual(BuildService.legacyDefaultsDomain, "app.libreleaf.LibreLeaf")
    }

    /// With the migrated token, a folder built by the old app is reused as-is and its output kept.
    func testMigratedTokenKeepsExistingBuildFolderOwned() throws {
        let defaults = UserDefaults.standard, key = "buildOwnerToken"
        let saved = defaults.string(forKey: key)
        defer { if let saved { defaults.set(saved, forKey: key) } else { defaults.removeObject(forKey: key) } }
        let root = try write("paper.tex", "x")
        let built = try BuildService.prepareOutputDirectory(for: root) // "old app" builds
        try "OLD".write(to: built.appendingPathComponent("paper.pdf"), atomically: true, encoding: .utf8)
        let token = try XCTUnwrap(defaults.string(forKey: key))

        let legacyName = "libreweave.test.\(UUID().uuidString)"
        let legacy = try XCTUnwrap(UserDefaults(suiteName: legacyName))
        defer { legacy.removePersistentDomain(forName: legacyName) }
        legacy.set(token, forKey: key)
        defaults.removeObject(forKey: key) // new bundle ID: empty preferences
        XCTAssertEqual(BuildService.ownerToken(in: defaults, legacy: legacy), token)
        XCTAssertEqual(try BuildService.prepareOutputDirectory(for: root), built)
        XCTAssertEqual(try String(contentsOf: built.appendingPathComponent("paper.pdf"), encoding: .utf8), "OLD")
    }

    /// latexmk skips an unchanged failed document and prints no file:line; the engine .log has them.
    func testFailedBuildRecoversDiagnosticsFromEngineLog() async throws {
        let engine = try write("latexmk", "#!/bin/sh\necho 'Latexmk: Nothing to do, previous errors'\nexit 12\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: engine.path)
        let root = try write("paper.tex", "x")
        _ = try write("chap.tex", "x")
        let out = try BuildService.prepareOutputDirectory(for: root)
        try "! Undefined control sequence.\n./chap.tex:3: Undefined control sequence.\n".write(
            to: out.appendingPathComponent("paper.log"), atomically: true, encoding: .utf8)
        let service = BuildService()
        service.engineOverride = engine
        let result = try await service.build(root: root)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.diagnostics.map { "\($0.file?.lastPathComponent ?? "nil"):\($0.line ?? 0)" }, ["chap.tex:3"])
    }

    /// The engine .log fallback is read as a bounded tail, never loaded whole.
    func testEngineLogFallbackReadsBoundedTail() throws {
        let log = folder.appendingPathComponent("huge.log")
        let filler = Data(repeating: UInt8(ascii: "x"), count: 3 << 20)
        try (filler + Data("\n./chap.tex:9: Undefined control sequence.\n".utf8)).write(to: log)
        let tail = try XCTUnwrap(BuildService.readTail(of: log, limit: 1 << 20))
        XCTAssertEqual(tail.count, 1 << 20)
        XCTAssertEqual(BuildService.parseDiagnostics(String(decoding: tail, as: UTF8.self), sourceFolder: folder).map(\.line), [9])
        XCTAssertEqual(BuildService.readTail(of: folder.appendingPathComponent("missing.log"), limit: 10), nil)
        try Data("short".utf8).write(to: log)
        XCTAssertEqual(BuildService.readTail(of: log, limit: 1 << 20), Data("short".utf8))
    }

    /// Same thing end to end with real latexmk: Build, Build again unchanged.
    func testRepeatedFailedLatexmkBuildKeepsDiagnostics() async throws {
        let root = try write("paper.tex", "\\documentclass{article}\\begin{document}\\input{chap}\\end{document}\n")
        _ = try write("chap.tex", "Text\n\n\\undefinedmacro\n")
        let service = BuildService()
        for attempt in 1...2 {
            let result: BuildResult
            do { result = try await service.build(root: root) } catch BuildError.missingTeX { throw XCTSkip("No TeX installed") }
            XCTAssertFalse(result.succeeded)
            XCTAssertTrue(result.diagnostics.contains { $0.file?.lastPathComponent == "chap.tex" && $0.line == 3 },
                          "attempt \(attempt): \(result.diagnostics.map(\.message))")
        }
    }

    func testPDFPreviewKeepsDocumentAndZoomForSameBytes() throws {
        func pdf(_ text: String) -> Data {
            let view = NSTextField(labelWithString: text)
            view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
            return view.dataWithPDF(inside: view.bounds)
        }
        let first = pdf("one"), second = pdf("two")
        let view = PDFView(), coordinator = PDFPreview.Coordinator()
        coordinator.show(first, in: view)
        let shown = try XCTUnwrap(view.document)
        view.autoScales = false
        view.scaleFactor = 2.5
        coordinator.show(Data(first), in: view) // equal bytes, new Data value: what each keystroke passes
        XCTAssertTrue(view.document === shown, "same PDF must not be reassigned")
        XCTAssertEqual(view.scaleFactor, 2.5, accuracy: 0.01)
        coordinator.show(second, in: view)
        XCTAssertFalse(view.document === shown)
        XCTAssertEqual(view.scaleFactor, 2.5, accuracy: 0.01, "zoom survives a rebuilt PDF")
    }

    func testRunawayLogIsCappedOnDiskAndStopsTheBuild() async throws {
        // Fake engine that prints forever, like a looping document.
        let engine = try write("latexmk", "#!/bin/sh\nexec /usr/bin/yes 'Runaway output from a looping document'\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: engine.path)
        let root = try write("loop.tex", "x")
        let service = BuildService()
        service.engineOverride = engine
        service.logLimit = 1 << 20
        do { _ = try await service.build(root: root); XCTFail("runaway build must stop") }
        catch { XCTAssertEqual(error as? BuildError, .logTooLarge(1 << 20)) }
        let log = folder.appendingPathComponent(".libreleaf-build/\(BuildService.outputName(for: root))/LibreLeaf.log")
        let size = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: log.path)[.size] as? Int)
        XCTAssertEqual(size, 1 << 20, "log must stop exactly at the cap")
        XCTAssertFalse(service.isRunning)
    }

    func testLtxAndLatexRootsBuild() async throws {
        for name in ["notes.ltx", "book.latex"] {
            let root = try write(name, #"\documentclass{article}\begin{document}Hi\end{document}"#)
            do {
                let result = try await BuildService().build(root: root)
                XCTAssertEqual(result.pdfData?.prefix(4), Data("%PDF".utf8), result.log)
            } catch BuildError.missingTeX { throw XCTSkip("No TeX installed") }
        }
    }

    func testFoldersWithTeXSpecialCharactersAreRefused() async throws {
        for name in ["a$b", "x;y", "c:d", "{e}", "f!!g"] {
            let sub = folder.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            let root = sub.appendingPathComponent("paper.tex")
            try "x".write(to: root, atomically: true, encoding: .utf8)
            do { _ = try await BuildService().build(root: root); XCTFail(name) }
            catch { XCTAssertEqual(error as? BuildError, .unsafeFolder(sub.path), name) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: sub.appendingPathComponent(BuildService.buildFolderName).path))
        }
        XCTAssertTrue(BuildService.isSafeFolderPath("/Users/me/My Papers/thèse (2026)"))
    }

    func testCancelAlwaysReportsCancelledEvenIfEngineExitsNormally() async throws {
        // Engine that catches SIGTERM and exits with an ordinary status, as latexmk can (12).
        let engine = try write("latexmk", "#!/bin/sh\ntrap 'exit 12' TERM\necho started\nwhile :; do sleep 0.05; done\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: engine.path)
        let root = try write("slow.tex", "x")
        let service = BuildService()
        service.engineOverride = engine
        let build = Task { try await service.build(root: root) }
        while !service.isRunning { try await Task.sleep(for: .milliseconds(20)) }
        try await Task.sleep(for: .milliseconds(200)) // let the trap install
        service.cancel()
        do { _ = try await build.value; XCTFail("cancelled build must not report a result") }
        catch { XCTAssertEqual(error as? BuildError, .cancelled) }
        XCTAssertFalse(service.isRunning)
        service.cancel() // nothing running: must not signal a stale (possibly reused) PID
    }

    /// Clean (autosaved) buffer, then another app restores an older copy with an older mtime.
    func testCleanBufferDetectsExternalReplacementWithOlderMtime() throws {
        let url = try write("root.tex", "MINE\r\n")
        let buffer = try TextDocument(data: Data(contentsOf: url))
        XCTAssertTrue(buffer.matchesDisk(at: url), "CRLF buffer must match its own file byte-for-byte")

        try "COAUTHOR\r\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: url.path)
        XCTAssertFalse(buffer.matchesDisk(at: url))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "COAUTHOR\r\n", "check must not write")
        try FileManager.default.removeItem(at: url)
        XCTAssertFalse(buffer.matchesDisk(at: url), "missing file is a mismatch, not a match")
    }

    func testDiagnosticsAndTextRoundTrip() throws {
        let log = """
        ./main.tex:5: Undefined control sequence.
        /tmp/../etc/evil.sty:1: outside
        ../sibling/x.tex:2: outside
        Latexmk: Run number 1 of rule 'pdflatex'
        Package hyperref Warning: Token not allowed on input line 3.
        """
        let diags = BuildService.parseDiagnostics(log, sourceFolder: folder)
        XCTAssertEqual(diags.map(\.line), [5, 1, 2])
        guard diags.count == 3 else { return }
        XCTAssertEqual(diags[0].file?.lastPathComponent, "main.tex")
        XCTAssertNil(diags[1].file)
        XCTAssertNil(diags[2].file)

        // BOM + CRLF and mixed endings survive byte-for-byte; pasted CRLF doesn't become CR CR LF.
        for bytes in [[0xEF, 0xBB, 0xBF] + Array("a\r\nb\r\n".utf8), Array("a\r\nb\nc".utf8)] {
            XCTAssertEqual(try TextDocument(data: Data(bytes)).data(), Data(bytes))
        }
        var doc = try TextDocument(data: Data("a\r\n".utf8))
        doc.text += "pasted\r\nline\n"
        XCTAssertEqual(doc.data(), Data("a\r\npasted\r\nline\r\n".utf8))
        XCTAssertThrowsError(try TextDocument(data: Data([0xFF, 0xFE, 0x00])))
    }

    func testCancelKillsChildProcesses() throws {
        let shell = Process()
        let pipe = Pipe()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "sleep 30 & echo $!; wait"]
        shell.standardOutput = pipe
        try shell.run()
        let line = String(decoding: pipe.fileHandleForReading.availableData, as: UTF8.self)
        let child = try XCTUnwrap(pid_t(line.trimmingCharacters(in: .whitespacesAndNewlines)))
        BuildService.terminateTree(shell.processIdentifier)
        shell.waitUntilExit()
        usleep(100_000)
        XCTAssertNotEqual(kill(child, 0), 0, "engine child must not outlive cancel")
    }

    func testNewerBuildSupersedesOlderAndProducesPDF() async throws {
        let root = try write("article.tex", #"\documentclass{article}\begin{document}\input{part}\end{document}"#)
        _ = try write("part.tex", #"Hello $e^{i\pi}+1=0$."#)
        let service = BuildService()
        async let older = service.build(root: root)
        async let newer = service.build(root: root)
        do {
            let result = try await newer
            XCTAssertTrue(result.succeeded, result.log)
            XCTAssertEqual(result.pdfData?.prefix(4), Data("%PDF".utf8))
        } catch BuildError.missingTeX { throw XCTSkip("No TeX installed") }
        do { _ = try await older; XCTFail("older build must not publish") }
        catch { XCTAssertEqual(error as? BuildError, .cancelled) }
    }
}
