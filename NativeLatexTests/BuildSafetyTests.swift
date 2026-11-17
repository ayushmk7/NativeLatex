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
        XCTAssertEqual(Array(args.suffix(2)), ["-outdir=.libreleaf-build/My Paper", "./My Paper.tex"])
        XCTAssertTrue(args.contains("-norc") && args.contains("-no-shell-escape"))
        XCTAssertFalse(args.joined().contains(folder.path), "absolute folder path must not reach latexmk")
    }

    func testOutputFolderRefusesForgedMarkersAndSymlinks() throws {
        let fm = FileManager.default
        let build = folder.appendingPathComponent(".libreleaf-build")
        let victim = try write("victim.txt", "FAKE_API_KEY=test-not-real")

        // Forged marker shipped with a project.
        try fm.createDirectory(at: build.appendingPathComponent("forged"), withIntermediateDirectories: true)
        try "LibreLeaf\n".write(to: build.appendingPathComponent("forged/.libreleaf-owner"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try BuildService.prepareOutputDirectory(for: folder.appendingPathComponent("forged.tex")))

        // Output folder is a symlink to elsewhere.
        try fm.createSymbolicLink(at: build.appendingPathComponent("linked"), withDestinationURL: folder)
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
        let log = folder.appendingPathComponent(".libreleaf-build/loop/LibreLeaf.log")
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
