import Foundation

/// External converter executables. Discovery never installs anything.
public struct ToolPaths: Sendable, Equatable {
    public var pandoc: URL?
    public var soffice: URL?

    public init(pandoc: URL?, soffice: URL?) {
        self.pandoc = pandoc
        self.soffice = soffice
    }

    /// Looks in common Homebrew/MacTeX/LibreOffice locations, then the inherited PATH.
    /// A GUI-launched app may not inherit the shell PATH, so fixed locations come first.
    public static func discover(environment: [String: String] = ProcessInfo.processInfo.environment) -> ToolPaths {
        let pathDirs = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/Library/TeX/texbin"] + pathDirs
        func find(_ name: String, extra: [String] = []) -> URL? {
            (extra + dirs.map { "\($0)/\(name)" })
                .first { FileManager.default.isExecutableFile(atPath: $0) }
                .map { URL(fileURLWithPath: $0) }
        }
        return ToolPaths(
            pandoc: find("pandoc"),
            soffice: find("soffice", extra: ["/Applications/LibreOffice.app/Contents/MacOS/soffice"])
        )
    }
}

public struct ProcessOutput: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String
}

public enum ProcessRunError: Error, LocalizedError, Equatable {
    case launchFailed(tool: String, reason: String)
    case timedOut(tool: String, seconds: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case let .launchFailed(tool, reason): return "Virgule could not start \(tool): \(reason)"
        case let .timedOut(tool, seconds): return "\(tool) did not finish within \(Int(seconds)) seconds and was stopped."
        }
    }
}

/// Runs an executable with an argument array (no shell), capturing output through
/// temp files so a chatty child can never deadlock on a full pipe.
public func runProcess(
    _ executable: URL,
    arguments: [String],
    workingDirectory: URL,
    timeout: TimeInterval = 120
) throws -> ProcessOutput {
    let fm = FileManager.default
    let logDir = fm.temporaryDirectory.appendingPathComponent("nativelatex-proc-\(UUID().uuidString)")
    try fm.createDirectory(at: logDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: logDir) }
    let outURL = logDir.appendingPathComponent("stdout")
    let errURL = logDir.appendingPathComponent("stderr")
    fm.createFile(atPath: outURL.path, contents: nil)
    fm.createFile(atPath: errURL.path, contents: nil)
    let outHandle = try FileHandle(forWritingTo: outURL)
    let errHandle = try FileHandle(forWritingTo: errURL)
    defer { try? outHandle.close(); try? errHandle.close() }

    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.currentDirectoryURL = workingDirectory
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = outHandle
    process.standardError = errHandle
    // Minimal environment: child sees its own tool directory, not the app's secrets.
    var env = ["PATH": "\(executable.deletingLastPathComponent().path):/usr/bin:/bin", "LANG": "en_US.UTF-8"]
    env["HOME"] = ProcessInfo.processInfo.environment["HOME"]
    process.environment = env

    let tool = executable.lastPathComponent
    do { try process.run() } catch {
        throw ProcessRunError.launchFailed(tool: tool, reason: error.localizedDescription)
    }
    // ponytail: 20 ms polling; swap for terminationHandler + semaphore if this ever shows in profiles.
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning, Date() < deadline { usleep(20_000) }
    if process.isRunning {
        process.terminate()
        process.waitUntilExit()
        throw ProcessRunError.timedOut(tool: tool, seconds: timeout)
    }
    let read = { (url: URL) in String(decoding: (try? Data(contentsOf: url)) ?? Data(), as: UTF8.self) }
    return ProcessOutput(status: process.terminationStatus, stdout: read(outURL), stderr: read(errURL))
}
