import Darwin
import Foundation

struct Diagnostic: Identifiable {
    let id = UUID()
    let file: URL?
    let line: Int?
    let message: String
    let isWarning: Bool
}

struct BuildResult {
    let succeeded: Bool
    let pdfData: Data?
    let log: String
    let diagnostics: [Diagnostic]
}

enum BuildError: LocalizedError, Equatable {
    case missingTeX
    case unsafeName(String)
    case unownedOutputDirectory(String)
    case cancelled
    case logTooLarge(Int)
    case unsafeFolder(String)

    var errorDescription: String? {
        switch self {
        case .missingTeX: "No LaTeX engine (latexmk, pdflatex, xelatex or lualatex) was found. Install MacTeX or BasicTeX, then try Build again."
        case .unsafeName(let name): "“\(name)” can’t be built safely. Rename it using only letters, digits, spaces, “.”, “_” and “-” (not starting with “-” or “.”), ending in .tex, .ltx or .latex."
        case .unownedOutputDirectory(let path): "\(path) was not created by LibreLeaf on this Mac, or contains links. Nothing was changed; remove or rename it to build."
        case .cancelled: "Build cancelled."
        case .unsafeFolder(let path): "LibreLeaf can’t build in “\(path)”: its path contains a character TeX treats as special ($ ; : { } ` \\ % \" or !!), which breaks bibliography and input lookup. Move or rename the folder, then build again."
        case .logTooLarge(let bytes): "The build was stopped after writing \(bytes / (1 << 20)) MB of log output, which usually means a runaway loop in the document. Check the start of the log, fix the source, then build again."
        }
    }
}

@MainActor
final class BuildService: ObservableObject {
    nonisolated static let buildFolderName = ".libreleaf-build"
    nonisolated static let engines = ["latexmk", "pdflatex", "xelatex", "lualatex"]
    nonisolated static let logTailLimit = 1 << 20
    /// Registered LaTeX extensions (LibreLeaf-Info.plist, org.tug.tex).
    nonisolated static let rootExtensions = ["tex", "ltx", "latex"]
    /// On-disk log cap: a looping document can print tens of MB per second.
    var logLimit = 32 << 20
    /// Tests only: run this executable instead of the discovered TeX engine.
    var engineOverride: URL?

    /// Per-install secret written into folders we create; a project can't ship a forged marker.
    nonisolated static var ownerToken: String {
        if let token = UserDefaults.standard.string(forKey: "buildOwnerToken") { return token }
        let token = UUID().uuidString
        UserDefaults.standard.set(token, forKey: "buildOwnerToken")
        return token
    }

    @Published private(set) var isRunning = false
    private var process: Process?
    private var running: Task<(Data, Process.TerminationReason, Int32, Bool), Never>?
    private var generation = 0
    /// Generation the user cancelled. A cancelled build throws `.cancelled` even if the engine
    /// traps SIGTERM and exits with an ordinary status.
    private var cancelledGeneration: Int?

    func cancel() {
        cancelledGeneration = generation
        // isRunning stays true until Foundation reaps the child, so the PID can't have been reused.
        if let process, process.isRunning { Self.terminateTree(process.processIdentifier) }
    }

    /// kpathsea splits search paths on `:`/`;` and expands `$`, `{}`, `!!`; latexmk feeds the
    /// absolute folder into BIBINPUTS and friends, so those characters can't be quoted away.
    nonisolated static func isSafeFolderPath(_ path: String) -> Bool {
        !path.contains(where: { "$;:{}`\\%\"".contains($0) }) && !path.contains("!!")
    }

    /// latexmk interpolates file names into shell commands, so even "./" can't neutralise
    /// backticks or `$()`. Allow only a conservative character set.
    nonisolated static func isSafeRootName(_ name: String) -> Bool {
        guard rootExtensions.contains((name as NSString).pathExtension.lowercased()),
              let first = name.first, first != "-", first != "." else { return false }
        return name.allSatisfy { $0.isLetter || $0.isNumber || " ._-".contains($0) }
    }

    /// argv only (never a shell string). Paths are relative to the root's folder (the working
    /// directory), so the user's folder path never reaches latexmk's internal shell commands.
    nonisolated static func arguments(engine: String, root: URL) -> [String] {
        let input = "./" + root.lastPathComponent
        let outdir = "\(buildFolderName)/\(root.deletingPathExtension().lastPathComponent)"
        let common = ["-interaction=nonstopmode", "-file-line-error", "-synctex=1", "-no-shell-escape"]
        if engine == "latexmk" {
            return ["-norc", "-pdf"] + common + ["-outdir=\(outdir)", input]
        }
        // ponytail: direct engine fallback is a single pass; refs/bibliography need latexmk.
        return common + ["-output-directory=\(outdir)", input]
    }

    /// Creates `<folder>/.libreleaf-build/<stem>`, or reuses it only if it carries this install's
    /// token and nothing in the chain is a symlink (TeX would write through it).
    nonisolated static func prepareOutputDirectory(for root: URL) throws -> URL {
        let fm = FileManager.default
        let parent = root.deletingLastPathComponent().appendingPathComponent(buildFolderName, isDirectory: true)
        let folder = parent.appendingPathComponent(root.deletingPathExtension().lastPathComponent, isDirectory: true)
        let marker = folder.appendingPathComponent(".libreleaf-owner")
        let refuse = BuildError.unownedOutputDirectory(folder.path)
        for url in [parent, folder] where isSymlink(url) { throw refuse }
        if fm.fileExists(atPath: folder.path) {
            guard !isSymlink(marker), (try? String(contentsOf: marker, encoding: .utf8)) == ownerToken,
                  try isPlainTree(folder)
            else { throw refuse }
        } else {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try ownerToken.write(to: marker, atomically: false, encoding: .utf8)
        }
        return folder
    }

    func build(root: URL) async throws -> BuildResult {
        guard Self.isSafeRootName(root.lastPathComponent) else { throw BuildError.unsafeName(root.lastPathComponent) }
        let folderPath = root.deletingLastPathComponent().path
        guard Self.isSafeFolderPath(folderPath) else { throw BuildError.unsafeFolder(folderPath) }
        guard let executable = engineOverride ?? Self.findEngine() else { throw BuildError.missingTeX }

        // One build per window: a new request stops the old one and waits for it to exit.
        if let process, process.isRunning { Self.terminateTree(process.processIdentifier) }
        generation += 1
        let mine = generation
        _ = await running?.value
        guard mine == generation else { throw BuildError.cancelled }

        let sourceFolder = root.deletingLastPathComponent()
        let outputDirectory = try Self.prepareOutputDirectory(for: root)
        let logURL = outputDirectory.appendingPathComponent("LibreLeaf.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logFile = try FileHandle(forWritingTo: logURL)

        let task = Process()
        let pipe = Pipe()
        task.executableURL = executable
        task.currentDirectoryURL = sourceFolder
        task.arguments = Self.arguments(engine: executable.lastPathComponent, root: root)
        // GUI apps don't inherit the login shell PATH; latexmk needs to find its engines.
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ([executable.deletingLastPathComponent().path] + Self.searchPaths).joined(separator: ":")
        task.environment = environment
        task.standardOutput = pipe
        task.standardError = pipe
        task.standardInput = FileHandle.nullDevice
        try task.run()
        process = task
        isRunning = true
        if cancelledGeneration == mine { cancel() } // Cancel pressed while the engine was starting

        // Full log goes to disk as it streams; memory keeps a bounded tail.
        let limit = Self.logTailLimit, diskLimit = logLimit
        let reader = Task.detached { () -> (Data, Process.TerminationReason, Int32, Bool) in
            var tail = Data(), written = 0, overflow = false
            while true {
                let chunk = pipe.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                if overflow { continue } // drain until the killed tree closes the pipe
                let kept = chunk.prefix(diskLimit - written)
                logFile.write(kept)
                written += kept.count
                tail.append(kept)
                if tail.count > limit { tail.removeFirst(tail.count - limit) }
                if written >= diskLimit {
                    overflow = true
                    if task.isRunning { Self.terminateTree(task.processIdentifier) }
                }
            }
            try? logFile.close()
            task.waitUntilExit()
            return (tail, task.terminationReason, task.terminationStatus, overflow)
        }
        running = reader
        let (output, reason, status, overflow) = await reader.value
        if mine == generation { process = nil; running = nil; isRunning = false }
        if overflow, mine == generation { throw BuildError.logTooLarge(logLimit) }

        guard mine == generation, cancelledGeneration != mine, reason == .exit else { throw BuildError.cancelled }
        let log = String(decoding: output, as: UTF8.self)
        let pdfURL = outputDirectory.appendingPathComponent(root.deletingPathExtension().lastPathComponent + ".pdf")
        let pdfData = status == 0 ? try? Data(contentsOf: pdfURL) : nil
        return BuildResult(succeeded: pdfData != nil, pdfData: pdfData, log: log,
                           diagnostics: Self.parseDiagnostics(log, sourceFolder: sourceFolder))
    }

    /// `path.ext:line: message` lines from -file-line-error. Paths outside the source folder are not linked.
    nonisolated static func parseDiagnostics(_ log: String, sourceFolder: URL) -> [Diagnostic] {
        let pattern = #/^((?:\.{0,2}\/)?[^\s:][^:]*\.[A-Za-z]{1,8}):(\d+): (.+)$/#
        let folder = sourceFolder.resolvingSymlinksInPath()
        let base = folder.path + "/"
        return log.split(whereSeparator: \.isNewline).compactMap { raw in
            guard let m = try? pattern.wholeMatch(in: String(raw)) else { return nil }
            // Resolve the directory (the file itself may not exist), so /var vs /private/var compare equal.
            let joined = URL(fileURLWithPath: String(m.1), relativeTo: folder).standardizedFileURL
            let url = joined.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(joined.lastPathComponent)
            let message = String(m.3)
            return Diagnostic(file: url.path.hasPrefix(base) ? url : nil, line: Int(m.2), message: message,
                              isWarning: message.localizedCaseInsensitiveContains("warning"))
        }
    }

    /// latexmk spawns the engine as a child; terminate the whole tree, leaves first.
    nonisolated static func terminateTree(_ pid: pid_t) {
        var children = [pid_t](repeating: 0, count: 256)
        let count = proc_listchildpids(pid, &children, Int32(children.count * MemoryLayout<pid_t>.size))
        for child in children.prefix(max(0, Int(count))) where child > 0 { terminateTree(child) }
        kill(pid, SIGTERM)
    }

    /// True if nothing anywhere under `folder` is a symlink or a hard-linked file. TeX and latexmk
    /// write into subfolders (`\include`, minted, aux dirs), so a link at any depth could redirect a write.
    nonisolated static func isPlainTree(_ folder: URL) throws -> Bool {
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isRegularFileKey]
        // The enumerator does not descend through symlinked folders; it reports the link itself.
        guard let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [],
                                                         errorHandler: { _, _ in false }) else { return false }
        for case let url as URL in items {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true { return false }
            // A hard link shares the inode with a file outside the tree; truncating it writes through.
            if values.isRegularFile == true,
               let links = try FileManager.default.attributesOfItem(atPath: url.path)[.referenceCount] as? Int, links > 1 {
                return false
            }
        }
        return true
    }

    nonisolated private static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    nonisolated private static let searchPaths = ["/Library/TeX/texbin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]

    /// First engine that resolves to a real executable (/Library/TeX/texbin may be a dangling link).
    nonisolated private static func findEngine() -> URL? {
        let dirs = searchPaths + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for engine in engines {
            for dir in dirs {
                let url = URL(fileURLWithPath: dir).appendingPathComponent(engine)
                if FileManager.default.isExecutableFile(atPath: url.resolvingSymlinksInPath().path) { return url }
            }
        }
        return nil
    }
}
