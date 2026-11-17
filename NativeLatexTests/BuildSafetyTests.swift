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

        for name in ["paper.tex", "My Paper_v2-final.tex", "thèse 2.TEX"] {
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
