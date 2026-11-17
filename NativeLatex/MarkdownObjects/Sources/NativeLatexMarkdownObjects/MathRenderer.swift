import AppKit

/// Renders TeX formulas to vector images with the user's `pdflatex`: one batch, one page per formula
/// (`preview` package). Formulas are checked against an allowlist-ish filter first, because TeX itself reads any
/// absolute path (`openin_any=p` still allowed `\input{/etc/hosts}`); the run has no shell escape, a private
/// temporary folder, a minimal environment and a timeout.
public enum MathRenderer {
    public struct Job: Sendable, Equatable {
        public let formula: String
        public let display: Bool
        /// Body font size in points; TeX renders at 10 pt and is scaled to this.
        public let size: CGFloat
        public init(formula: String, display: Bool, size: CGFloat) { self.formula = formula; self.display = display; self.size = size }
    }

    public typealias Render = @Sendable ([Job]) -> [MarkdownRendered?]
    /// The user's pdflatex, if installed (looked up once).
    public static let automatic: Render? = discover().map { tex in { @Sendable jobs in render(jobs, tex: tex) } }

    public static let maxBatch = 64, maxFormula = 2000
    public static let timeout: TimeInterval = 10
    static let searchPaths = ["/Library/TeX/texbin", "/opt/homebrew/bin", "/usr/local/bin"]

    public static func discover() -> URL? {
        for dir in searchPaths {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("pdflatex")
            if FileManager.default.isExecutableFile(atPath: url.resolvingSymlinksInPath().path) { return url }
        }
        return nil
    }

    /// Control words that read or write files, define macros, change catcodes or expand indirectly.
    static let blocked: Set<String> = [
        "input", "include", "includeonly", "openin", "openout", "closein", "closeout", "read", "readline", "write",
        "immediate", "message", "errmessage", "csname", "endcsname", "catcode", "lccode", "uccode", "mathcode",
        "delcode", "sfcode", "def", "edef", "gdef", "xdef", "let", "futurelet", "expandafter", "noexpand", "special",
        "jobname", "endinput", "newcommand", "renewcommand", "providecommand", "newenvironment", "renewenvironment",
        "DeclareMathOperator", "usepackage", "RequirePackage", "documentclass", "makeatletter", "makeatother",
        "scantokens", "detokenize", "string", "uppercase", "lowercase", "output", "shipout", "afterassignment",
        "aftergroup", "batchmode", "nonstopmode", "scrollmode", "errorstopmode", "the", "meaning", "global", "loop",
        "dump", "count", "countdef", "dimendef", "skipdef", "toksdef", "chardef", "mathchardef", "font", "romannumeral",
        "number", "includegraphics", "InputIfFileExists", "IfFileExists", "lstinputlisting", "verbatiminput",
        "directlua", "newwrite", "newread", "typeout", "sbox", "usebox", "savebox", "newsavebox", "par", "vadjust",
        "insert", "mark", "penalty", "vskip", "newpage", "clearpage", "pagebreak",
    ]
    static let blockedPrefixes = ["pdf", "every", "tracing", "show", "open", "close", "Input", "file"]
    static let environments: Set<String> = ["matrix", "pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix", "smallmatrix",
                                            "cases", "aligned", "alignedat", "gathered", "split", "array", "subarray"]

    /// Whether `formula` is safe to give TeX: balanced braces, no blocked control words, only math environments.
    public static func isAllowed(_ formula: String) -> Bool {
        let units = Array(formula.utf16)
        guard !units.isEmpty, units.count <= maxFormula else { return false }
        for bad in ["^^", "@", "#", "%", "$"] where formula.contains(bad) { return false }
        func isLetter(_ u: UInt16) -> Bool { (65...90).contains(u) || (97...122).contains(u) }
        var depth = 0, i = 0
        while i < units.count {
            let u = units[i]
            if u == 92 /* \ */ {
                var j = i + 1
                while j < units.count, isLetter(units[j]) { j += 1 }
                if j == i + 1 { i += 2; continue } // control symbol: \{ \} \\ \, ...
                let name = String(utf16CodeUnits: Array(units[(i + 1)..<j]), count: j - i - 1)
                if blocked.contains(name) || blockedPrefixes.contains(where: name.hasPrefix) { return false }
                if name == "begin" || name == "end" {
                    var k = j
                    while k < units.count, units[k] == 32 { k += 1 }
                    guard k < units.count, units[k] == 123 /* { */, let close = units[k...].firstIndex(of: 125) else { return false }
                    let env = String(utf16CodeUnits: Array(units[(k + 1)..<close]), count: close - k - 1)
                    guard environments.contains(env) else { return false }
                }
                i = j
                continue
            }
            if u == 123 { depth += 1; if depth > 50 { return false } }
            if u == 125 { depth -= 1; if depth < 0 { return false } }
            i += 1
        }
        return depth == 0
    }

    static let preamble = [
        #"\documentclass{article}"#,
        #"\usepackage{amsmath,amssymb}"#,
        #"\usepackage[active,tightpage]{preview}"#,
        #"\setlength\PreviewBorder{0pt}"#,
        #"\pagestyle{empty}"#,
        #"\begin{document}"#,
    ]

    /// One result per job, in order; nil where the formula is refused or TeX reports an error.
    public static func render(_ jobs: [Job], tex: URL) -> [MarkdownRendered?] {
        let allowed = jobs.map { isAllowed($0.formula) }
        let runnable = jobs.indices.filter { allowed[$0] }
        guard !runnable.isEmpty else { return jobs.map { _ in nil } }
        var results = [MarkdownRendered?](repeating: nil, count: jobs.count)
        if let batch = run(runnable.map { jobs[$0] }, tex: tex) {
            for (k, index) in runnable.enumerated() { results[index] = batch[k] }
        } else if runnable.count > 1 {
            // A batch that went wrong as a whole: one at a time, so a single bad formula doesn't hide the rest.
            for index in runnable { results[index] = run([jobs[index]], tex: tex)?.first ?? nil }
        }
        return results
    }

    /// nil when the run failed as a whole (no PDF, page count mismatch, timeout).
    static func run(_ jobs: [Job], tex: URL) -> [MarkdownRendered?]? {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("LibreWeaveMath-\(UUID().uuidString)")
        guard (try? fm.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])) != nil else { return nil }
        defer { try? fm.removeItem(at: dir) }
        var lines = preamble
        for job in jobs {
            let formula = job.formula.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
            let style = job.display ? #"\displaystyle"# : #"\textstyle"#
            lines.append(#"\begin{preview}\sbox0{$"# + style + " " + formula + #"$}\typeout{LWBOX \the\ht0/\the\dp0}\usebox0\end{preview}"#)
        }
        lines.append(#"\end{document}"#)
        guard (try? (lines.joined(separator: "\n") + "\n").write(to: dir.appendingPathComponent("m.tex"), atomically: true, encoding: .utf8)) != nil else { return nil }

        let process = Process()
        process.executableURL = tex
        process.currentDirectoryURL = dir
        process.arguments = ["-interaction=nonstopmode", "-no-shell-escape", "-file-line-error", "m.tex"]
        process.environment = ["PATH": "\(tex.deletingLastPathComponent().path):/usr/bin:/bin", "HOME": dir.path,
                               "TEXMFOUTPUT": dir.path, "openin_any": "p", "openout_any": "p", "shell_escape": "f", "LANG": "en_US.UTF-8"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        guard (try? process.run()) != nil else { return nil }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            kill(process.processIdentifier, SIGKILL)
            _ = done.wait(timeout: .now() + 2)
            return nil
        }
        guard let pdf = try? Data(contentsOf: dir.appendingPathComponent("m.pdf")),
              let log = try? String(contentsOf: dir.appendingPathComponent("m.log"), encoding: .isoLatin1),
              let first = NSPDFImageRep(data: pdf), first.pageCount == jobs.count else { return nil }

        // Formula k is on line preamble.count + 1 + k; TeX reports errors as "./m.tex:LINE: ...".
        var failed = Set<Int>()
        var boxes: [(height: CGFloat, depth: CGFloat)] = []
        for line in log.split(separator: "\n") {
            if line.hasPrefix("./m.tex:"), let n = Int(line.dropFirst(8).prefix { $0.isNumber }) { failed.insert(n - preamble.count - 1) }
            if line.hasPrefix("LWBOX ") {
                let parts = line.dropFirst(6).split(separator: "/").map { Double($0.replacingOccurrences(of: "pt", with: "")) ?? 0 }
                boxes.append((CGFloat(parts.first ?? 0), CGFloat(parts.count > 1 ? parts[1] : 0)))
            }
        }
        guard boxes.count == jobs.count else { return nil }
        let bp = 72 / 72.27 // TeX points to PDF points
        return jobs.enumerated().map { k, job in
            guard !failed.contains(k), let rep = NSPDFImageRep(data: pdf) else { return nil }
            rep.currentPage = k
            let scale = job.size / 10
            let size = NSSize(width: (rep.bounds.width * scale).rounded(.up), height: (rep.bounds.height * scale).rounded(.up))
            guard size.width > 0, size.height > 0 else { return nil }
            let image = NSImage(size: size)
            image.addRepresentation(rep)
            return MarkdownRendered(image: image, size: size, descent: boxes[k].depth * bp * scale)
        }
    }
}
