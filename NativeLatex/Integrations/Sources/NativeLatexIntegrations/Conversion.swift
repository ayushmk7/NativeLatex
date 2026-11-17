import Foundation

public enum DocumentFormat: String, CaseIterable, Sendable {
    case latex = "tex", markdown = "md", docx, odt, html, pdf

    public init?(fileExtension ext: String) {
        switch ext.lowercased() {
        case "tex", "ltx", "latex": self = .latex
        case "md", "markdown": self = .markdown
        case "htm", "html": self = .html
        default: self.init(rawValue: ext.lowercased())
        }
    }

    var pandocReader: String? {
        switch self {
        case .latex: return "latex"
        case .markdown: return "markdown"
        case .docx: return "docx"
        case .odt: return "odt"
        case .html: return "html+tex_math_single_backslash"
        case .pdf: return nil
        }
    }

    var pandocWriter: String? { self == .pdf ? nil : (self == .html ? "html" : pandocReader) }
    var isOffice: Bool { self == .docx || self == .odt }
    var isText: Bool { self == .latex || self == .markdown || self == .html }
}

public struct ConversionResult: Sendable {
    /// The new copy. The source file is never modified.
    public let outputURL: URL
    /// Extracted images, referenced from `outputURL` by relative path. Nil when none.
    public let mediaDirectory: URL?
    public let tool: String
    /// Things a person must check. Never empty: a clean exit is not a fidelity guarantee.
    public let reviewNotes: [String]
    /// Raw converter stderr, kept for the session log.
    public let log: String
}

public enum ConversionError: Error, LocalizedError, Equatable {
    case toolMissing(tool: String, installHint: String)
    case unsupported(from: String, to: String)
    case sourceMissing(URL)
    case destinationExists(URL)
    case converterFailed(tool: String, status: Int32, message: String)
    case outputMissing(tool: String, message: String)

    public var errorDescription: String? {
        switch self {
        case let .toolMissing(tool, hint):
            return "LibreWeave needs \(tool) for this conversion, and it is not installed. \(hint) Editing and PDF builds keep working."
        case let .unsupported(from, to):
            return "LibreWeave cannot convert \(from) to \(to)."
        case let .sourceMissing(url):
            return "The source file \(url.path) does not exist."
        case let .destinationExists(url):
            return "\(url.path) already exists; LibreWeave never overwrites a previous copy."
        case let .converterFailed(tool, status, message):
            return "\(tool) failed (exit \(status)): \(message.isEmpty ? "no error output" : message)"
        case let .outputMissing(tool, message):
            return "\(tool) exited without writing the expected file. \(message)"
        }
    }
}

/// Local, non-destructive converter. Pandoc handles text <-> office documents;
/// LibreOffice handles DOCX <-> ODT and office -> PDF.
public struct LocalConverter: Sendable {
    public var tools: ToolPaths
    public var timeout: TimeInterval

    public init(tools: ToolPaths = .discover(), timeout: TimeInterval = 120) {
        self.tools = tools
        self.timeout = timeout
    }

    /// Converts `source` into a new file inside `destinationDirectory`.
    /// Name collisions get a numeric suffix (`name 2.docx`), never an overwrite.
    public func convert(_ source: URL, to target: DocumentFormat, in destinationDirectory: URL) throws -> ConversionResult {
        let fm = FileManager.default
        let source = source.standardizedFileURL
        guard fm.fileExists(atPath: source.path) else { throw ConversionError.sourceMissing(source) }
        guard let from = DocumentFormat(fileExtension: source.pathExtension), from != .pdf else {
            throw ConversionError.unsupported(from: source.pathExtension.isEmpty ? "this file" : source.pathExtension, to: target.rawValue)
        }
        guard from != target else { throw ConversionError.unsupported(from: from.rawValue, to: target.rawValue) }
        let useLibreOffice = from.isOffice && (target.isOffice || target == .pdf)
        guard useLibreOffice || (from.pandocReader != nil && target.pandocWriter != nil) else {
            throw ConversionError.unsupported(from: from.rawValue, to: target.rawValue)
        }

        try fm.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let stem = uniqueStem(source.deletingPathExtension().lastPathComponent, ext: target.rawValue, in: destinationDirectory)
        let work = fm.temporaryDirectory.appendingPathComponent("nativelatex-convert-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let tool: String, log: String
        let produced: URL
        let mediaName = "\(stem)_media"
        if useLibreOffice {
            (produced, log) = try runLibreOffice(source, to: target, stem: stem, work: work)
            tool = "LibreOffice"
        } else {
            (produced, log) = try runPandoc(source, from: from, to: target, stem: stem, mediaName: mediaName, work: work)
            tool = "Pandoc"
        }

        let output = destinationDirectory.appendingPathComponent("\(stem).\(target.rawValue)")
        let producedMedia = work.appendingPathComponent(mediaName)
        let media = fm.fileExists(atPath: producedMedia.path) ? destinationDirectory.appendingPathComponent(mediaName) : nil
        for url in [output, media].compactMap({ $0 }) where fm.fileExists(atPath: url.path) {
            throw ConversionError.destinationExists(url)
        }
        if let media { try fm.moveItem(at: producedMedia, to: media) }
        try fm.moveItem(at: produced, to: output)

        let sourceText = from.isText ? (try? String(contentsOf: source, encoding: .utf8)) : nil
        return ConversionResult(
            outputURL: output, mediaDirectory: media, tool: tool,
            reviewNotes: Self.reviewNotes(sourceText: sourceText, from: from, to: target, log: log),
            log: log
        )
    }

    private func runPandoc(_ source: URL, from: DocumentFormat, to target: DocumentFormat, stem: String, mediaName: String, work: URL) throws -> (URL, String) {
        guard let pandoc = tools.pandoc else {
            throw ConversionError.toolMissing(tool: "Pandoc", installHint: "Install it from pandoc.org or with `brew install pandoc`.")
        }
        let out = work.appendingPathComponent("\(stem).\(target.rawValue)")
        var args = [
            "--from=\(from.pandocReader!)", "--to=\(target.pandocWriter!)", "--standalone",
            "--resource-path=\(source.deletingLastPathComponent().path)",
            "--output=\(out.path)",
        ]
        // Text targets get images copied next to the new file with relative links,
        // so the copy survives temp cleanup (see conversion test, 2026-11-17).
        // HTML is skipped: extracting would fetch its remote images over the network.
        if target.isText, from != .html { args.append("--extract-media=\(mediaName)") }
        if from == .latex || from == .markdown { args.append("--citeproc") }
        args.append(source.path) // absolute path: cannot be mistaken for an option
        let result = try runProcess(pandoc, arguments: args, workingDirectory: work, timeout: timeout)
        guard result.status == 0 else {
            throw ConversionError.converterFailed(tool: "Pandoc", status: result.status, message: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard FileManager.default.fileExists(atPath: out.path) else {
            throw ConversionError.outputMissing(tool: "Pandoc", message: result.stderr)
        }
        return (out, result.stderr)
    }

    private func runLibreOffice(_ source: URL, to target: DocumentFormat, stem: String, work: URL) throws -> (URL, String) {
        guard let soffice = tools.soffice else {
            throw ConversionError.toolMissing(tool: "LibreOffice", installHint: "Install it from libreoffice.org or with `brew install --cask libreoffice`.")
        }
        // LibreOffice names output after the input; copy under the final stem first.
        let input = work.appendingPathComponent("in-\(stem).\(source.pathExtension)")
        try FileManager.default.copyItem(at: source, to: input)
        let outDir = work.appendingPathComponent("out")
        let profile = work.appendingPathComponent("profile") // private profile: no clash with an open LibreOffice
        let args = [
            "-env:UserInstallation=\(profile.absoluteString)",
            "--headless", "--norestore", "--nolockcheck",
            "--convert-to", target.rawValue, "--outdir", outDir.path, input.path,
        ]
        let result = try runProcess(soffice, arguments: args, workingDirectory: work, timeout: timeout)
        let out = outDir.appendingPathComponent("in-\(stem).\(target.rawValue)")
        let log = result.stdout + result.stderr
        guard result.status == 0 else {
            throw ConversionError.converterFailed(tool: "LibreOffice", status: result.status, message: log.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        // soffice can exit 0 without converting (e.g. unreadable file); trust only the file.
        guard FileManager.default.fileExists(atPath: out.path) else {
            throw ConversionError.outputMissing(tool: "LibreOffice", message: log)
        }
        let renamed = work.appendingPathComponent("\(stem).\(target.rawValue)")
        try FileManager.default.moveItem(at: out, to: renamed)
        return (renamed, log)
    }

    private func uniqueStem(_ base: String, ext: String, in dir: URL) -> String {
        let fm = FileManager.default
        func taken(_ s: String) -> Bool {
            fm.fileExists(atPath: dir.appendingPathComponent("\(s).\(ext)").path)
                || fm.fileExists(atPath: dir.appendingPathComponent("\(s)_media").path)
        }
        var stem = base, n = 2
        while taken(stem) { stem = "\(base) \(n)"; n += 1 }
        return stem
    }

    /// Flags structures the 2026-11-17 conversion test showed are lost or changed
    /// without any converter warning.
    static func reviewNotes(sourceText: String?, from: DocumentFormat, to: DocumentFormat, log: String) -> [String] {
        var notes = ["Review this copy before sharing: a successful conversion does not mean nothing changed."]
        let text = sourceText ?? ""
        func has(_ pattern: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }
        if from == .latex {
            if has(#"\\(eq|auto|c|page)?ref\{"#) { notes.append("Cross-references (\\ref, \\eqref) become literal text or lose their targets.") }
            if has(#"\\begin\{(equation|align|gather)\}"#) { notes.append("Equation numbers are dropped.") }
            if has(#"\\(cite[a-z]*|parencite|textcite)\{"#) { notes.append("Citations are rendered in Pandoc's default author-date style, not the document's bibliography style.") }
            if has(#"\\(newcommand|renewcommand|def|newenvironment|DeclareMathOperator)\b"#) { notes.append("Custom macros and environments are expanded or flattened; their definitions are not kept.") }
            if has(#"\\caption\{"#) { notes.append("Figure/table numbering and placement change; captions may become ordinary text.") }
        }
        if from == .markdown, to.isOffice, has("(?m)^(```|~~~)\\s*[A-Za-z]") {
            notes.append("Code block language tags are not preserved in office formats.")
        }
        if from.isOffice, to.isText {
            notes.append("Imported text does not reconstruct original LaTeX macros, labels, equation numbering, or bibliography files.")
        }
        if from == .html, to.isText, has(#"<img[^>]+src=\"https?://"#) {
            notes.append("Remote images are linked, not downloaded; they need network access to display.")
        }
        notes += log.split(separator: "\n").filter { $0.contains("[WARNING]") }.map { "Converter warning: \($0)" }
        return notes
    }
}
