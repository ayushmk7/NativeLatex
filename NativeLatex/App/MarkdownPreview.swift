import AppKit
import NativeLatexDesign
import NativeLatexIntegrations
import SwiftUI
import WebKit

/// Renders Markdown to an HTML fragment with the installed Pandoc. Everything stays local:
/// TeX math becomes native MathML (no MathJax CDN), raw HTML/TeX in the source is shown as text,
/// and `--sandbox` stops Pandoc reading or fetching anything but its input.
enum MarkdownRenderer {
    /// Measured on Apple silicon: a dense 1 MiB mix of tables, math, footnotes and code renders in ~2.5 s at ~300 MB RSS.
    static let maxInputBytes = 1 << 20
    /// MathML is ~5.4× the input on dense math; anything bigger is not loaded into WebKit.
    static let maxOutputBytes = 8 << 20
    /// Pandoc is a GHC program: its RTS heap cap makes it exit 251 "Heap exhausted" instead of growing
    /// (5 MiB of "[" passed 3 GB uncapped; capped, hostile inputs stop in <2 s at ~370 MB RSS).
    static let heapLimit = "256m"
    static let timeout: Duration = .seconds(10)

    enum Failure: LocalizedError, Equatable {
        case missingPandoc
        case tooLarge(Int)
        case outOfMemory
        case outputTooLarge(Int)
        case timedOut
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .missingPandoc:
                "Rich Markdown preview needs Pandoc, which wasn’t found in /opt/homebrew/bin, /usr/local/bin or your PATH. Install it with “brew install pandoc” or from pandoc.org, then choose Try Again. Your file is not affected."
            case .tooLarge(let bytes):
                "This file is \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)), too large to preview live (limit \(ByteCountFormatter.string(fromByteCount: Int64(maxInputBytes), countStyle: .file))). Editing and saving still work."
            case .outOfMemory:
                "This document needs more memory than the live preview allows (\(heapLimit.uppercased())B), so it wasn’t rendered. Split it into smaller files or simplify very deep nesting; editing and saving still work."
            case .outputTooLarge(let bytes):
                "The rendered preview would be \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)), more than the \(ByteCountFormatter.string(fromByteCount: Int64(maxOutputBytes), countStyle: .file)) the live preview shows. Split the document into smaller files; editing and saving still work."
            case .timedOut:
                "Pandoc took longer than \(timeout.components.seconds) seconds and was stopped. Very long runs of *, `, > or $ can be slow to parse; editing and saving still work."
            case .failed(let message):
                "Pandoc couldn’t render this file: \(message)"
            }
        }
    }

    static let arguments = [
        "+RTS", "-M\(heapLimit)", "-RTS",
        "--sandbox",
        // Pandoc Markdown covers GFM pipe tables, footnotes, fenced code and $…$ math; raw HTML/TeX stay literal text.
        "--from=markdown-raw_html-raw_tex-raw_attribute+autolink_bare_uris+task_lists",
        "--to=html5", "--math-method=mathml", "--wrap=none",
    ]

    /// Renders `text` (the unsaved buffer, never the file on disk) via a private temp copy.
    /// Task cancellation terminates Pandoc.
    static func render(_ text: String, pandoc: URL? = ToolPaths.discover().pandoc) async throws -> String {
        guard let pandoc else { throw Failure.missingPandoc }
        let input = Data(text.utf8)
        guard input.count <= maxInputBytes else { throw Failure.tooLarge(input.count) }

        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("libreleaf-preview-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let source = work.appendingPathComponent("in.md"), output = work.appendingPathComponent("out.html")
        let errors = work.appendingPathComponent("stderr.txt")
        try input.write(to: source)
        fm.createFile(atPath: errors.path, contents: nil)
        let errorHandle = try FileHandle(forWritingTo: errors)
        defer { try? errorHandle.close() }

        let process = Process()
        process.executableURL = pandoc
        process.arguments = arguments + ["--output=\(output.path)", source.path]
        process.currentDirectoryURL = work
        process.environment = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorHandle

        try Task.checkCancellation()
        var launchError: Error?
        try await runCancellable {
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                // onCancel may already have fired while nothing was running: don't launch, or stop right after launch.
                guard !Task.isCancelled else { done.resume(); return }
                process.terminationHandler = { _ in done.resume() }
                do { try process.run() } catch { launchError = error; process.terminationHandler = nil; done.resume(); return }
                if Task.isCancelled { stop(process) }
            }
        } onCancel: { stop(process) } onTimeout: { stop(process) }
        if let launchError { throw Failure.failed("LibreWeave couldn’t start \(pandoc.path): \(launchError.localizedDescription)") }
        try Task.checkCancellation()
        guard process.terminationReason == .exit else { throw Failure.timedOut } // not cancelled, so the timer stopped it
        let message = ((try? String(contentsOf: errors, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            // Only a failed run can be heap exhaustion; a successful run's warnings may quote the phrase from the document.
            if process.terminationStatus == 251 || message.contains("Heap exhausted") { throw Failure.outOfMemory }
            throw Failure.failed(message.isEmpty ? "exit status \(process.terminationStatus)." : message)
        }
        // Check the size before reading, so an oversized result never reaches memory or WebKit.
        let size = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= maxOutputBytes else { throw Failure.outputTooLarge(size) }
        guard let html = try? String(contentsOf: output, encoding: .utf8) else { throw Failure.failed("no readable output.") }
        return html
    }

    /// Whole page: strict CSP (no scripts, no network; images only from the local scheme), light/dark blue with Increase Contrast variants.
    static func page(body: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src \(LocalAssetHandler.scheme): data:; style-src 'unsafe-inline'">
        <meta name="color-scheme" content="light dark"><style>\(css)</style></head>
        <body><main id="content">\(body)</main></body></html>
        """
    }

    static let css = """
    :root { --bg:#FFFFFF; --fg:#0A0A0A; --muted:#6E6E73; --line:rgba(0,0,0,.12); --code:#F5F5F7; --link:#2563EB; --accent:#2563EB; }
    @media (prefers-color-scheme: dark) { :root { --bg:#000000; --fg:#F5F5F7; --muted:#98989D; --line:rgba(255,255,255,.16); --code:#141416; --link:#F5F5F7; --accent:#2563EB; } }
    @media (prefers-contrast: more) { :root { --muted:#3A3A3C; } }
    @media (prefers-contrast: more) and (prefers-color-scheme: dark) { :root { --muted:#C7C7CC; --link:#FFFFFF; } }
    html { background:var(--bg); color:var(--fg); font:\(Int(MarkdownStyler.bodySize))px/\(MarkdownStyler.lineHeight) -apple-system, system-ui, sans-serif; }
    body { margin:0; } main { max-width:\(Int(MarkdownStyler.columnWidth))px; margin:0 auto; padding:16px 24px 48px; overflow-wrap:break-word; }
    h1,h2,h3,h4,h5,h6 { line-height:\(MarkdownStyler.headingLineHeight); margin:\(MarkdownStyler.headingSpaceBefore)em 0 .5em; font-weight:700; }
    \(MarkdownStyler.headingSizes.enumerated().map { "h\($0 + 1) { font-size:\($1)px; }" }.joined(separator: " "))
    a { color:var(--link); text-decoration:underline; }
    code, pre { font:13px ui-monospace, SFMono-Regular, Menlo, monospace; background:var(--code); border-radius:4px; }
    code { padding:.1em .3em; } pre { padding:12px; overflow:auto; } pre code { padding:0; background:none; }
    blockquote { margin:1em 0; padding:0 1em; color:var(--muted); border-left:3px solid var(--accent); }
    table { border-collapse:collapse; margin:1em 0; display:block; overflow:auto; }
    th, td { border:1px solid var(--line); padding:6px 12px; } th { background:var(--code); }
    img { max-width:100%; } figure { margin:1em 0; } figcaption { color:var(--muted); font-size:.9em; }
    math[display="block"] { display:block; margin:1em 0; overflow-x:auto; } math { font-size:1.1em; }
    hr { border:0; border-top:1px solid var(--line); } .footnotes { font-size:.9em; color:var(--muted); }
    ul.task-list { list-style:none; padding-left:1.2em; }
    p, ul, ol, dl, blockquote, pre, table, figure, math[display="block"] { margin-top:\(MarkdownStyler.blockGap)px; margin-bottom:\(MarkdownStyler.blockGap)px; }
    """
}

/// Serves `libreleaf-local://doc/<relative path>` for images inside the document's folder only:
/// image extensions, regular files, resolved (symlinks too) under the folder, bounded size. Nothing else is readable.
final class LocalAssetHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "libreleaf-local"
    static let baseURL = URL(string: "\(scheme)://doc/")!
    static let maxBytes = 50 << 20
    static let mimeTypes = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif",
                            "webp": "image/webp", "svg": "image/svg+xml", "bmp": "image/bmp", "tif": "image/tiff", "tiff": "image/tiff"]

    var folder: URL?
    private(set) var served: [String] = []

    static func resolve(_ url: URL, in folder: URL?) -> URL? {
        guard let folder, url.scheme == scheme, url.host == "doc",
              let mime = mimeTypes[url.pathExtension.lowercased()], !mime.isEmpty else { return nil }
        let root = folder.resolvingSymlinksInPath().standardizedFileURL
        let file = root.appendingPathComponent(url.path).standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(root.path + "/"),
              let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, (values.fileSize ?? .max) <= maxBytes else { return nil }
        return file
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let file = Self.resolve(url, in: folder), let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        served.append(file.lastPathComponent)
        task.didReceive(URLResponse(url: url, mimeType: Self.mimeTypes[file.pathExtension.lowercased()],
                                    expectedContentLength: data.count, textEncodingName: nil))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

/// WKWebView with page JavaScript off, no persistent storage, and no navigation away from the preview.
/// Updates swap the content in place, so scroll position survives typing.
struct MarkdownWebView: NSViewRepresentable {
    let html: String
    let folder: URL?
    /// While true, the page takes keyboard focus once it is in a window (only into a focus gap); then cleared.
    var focus: Binding<Bool> = .constant(false)
    /// False while Write covers the page: hidden (out of the key loop, never focused) but kept, with its scroll.
    var visible = true

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView { Self.makeWebView(context.coordinator) }

    @MainActor static func makeWebView(_ coordinator: Coordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(coordinator.assets, forURLScheme: LocalAssetHandler.scheme)
        let view = PreviewWebView(frame: .zero, configuration: config)
        view.onWindow = { [weak coordinator, weak view] in if let view { coordinator?.takeFocusIfRequested(view) } }
        view.navigationDelegate = coordinator
        view.setAccessibilityLabel("Markdown preview")
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        view.isHidden = !visible
        context.coordinator.show(html, folder: folder, in: view)
        context.coordinator.focus = focus
        context.coordinator.takeFocusIfRequested(view)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let assets = LocalAssetHandler()
        private(set) var shown: String?
        private var loadedFolder: URL?
        var focus: Binding<Bool>?

        /// Focuses the page if asked and nothing else has focus; a page not yet in a window waits for `onWindow`.
        func takeFocusIfRequested(_ view: WKWebView) {
            guard focus?.wrappedValue == true, !view.isHidden, let window = view.window else { return }
            if MarkdownPreview.hasFocusGap(window) { window.makeFirstResponder(view) }
            DispatchQueue.main.async { self.focus?.wrappedValue = false } // not during a view update
        }

        func show(_ html: String, folder: URL?, in view: WKWebView) {
            guard html != shown || folder != loadedFolder else { return }
            assets.folder = folder
            if shown == nil || folder != loadedFolder {
                view.loadHTMLString(MarkdownRenderer.page(body: html), baseURL: LocalAssetHandler.baseURL)
            } else if let json = try? JSONSerialization.data(withJSONObject: [html]), let literal = String(data: json, encoding: .utf8) {
                // App-injected script (page scripts stay disabled); keeps scroll position, unlike a reload.
                view.evaluateJavaScript("document.getElementById('content').innerHTML = \(literal)[0]; 0")
            }
            shown = html
            loadedFolder = folder
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = action.request.url else { return .cancel }
            // The preview page itself and in-page anchors (footnotes).
            if url.scheme == LocalAssetHandler.scheme, url.host == "doc", url.path.isEmpty || url.path == "/" { return .allow }
            if action.navigationType == .linkActivated, ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(url)
            }
            return .cancel
        }
    }
}

/// Reports when it joins a window, so a focus request made before that is not lost.
final class PreviewWebView: WKWebView {
    var onWindow: (() -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { onWindow?() }
    }
}

/// Rich, local Markdown preview of the live (unsaved) buffer, debounced while typing.
struct MarkdownPreview: View {
    let text: String
    let fileURL: URL?
    /// Set by the window when Read should take keyboard focus once this render settles, however long Pandoc
    /// takes: the page on success, Try Again on failure. Cleared when handled. Never taken from a view that
    /// has focus (the window clears it if the user switches back to Write).
    var focusRequest: Binding<Bool> = .constant(false)
    /// False while Write covers this view. It stays mounted, so the page, its scroll position and the last
    /// result (page or failure) survive a Read → Write → Read switch; nothing renders while inactive.
    var isActive = true
    /// Pandoc by default; tests substitute slow or failing renderers.
    var render: @Sendable (String) async throws -> String = { try await MarkdownRenderer.render($0) }
    @State private var html: String?
    /// What `html`/`failure` show: an unchanged document is not rendered again (no spinner, no Pandoc run).
    @State private var rendered: Key?
    @State private var failure: String?
    @State private var attempt = 0
    @State private var anchor = WindowAnchor()
    @FocusState private var retryFocused: Bool

    /// Nothing in `window` holds focus (first responder is the window itself, or a view that has left it).
    static func hasFocusGap(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        let responder = window.firstResponder
        return responder == nil || responder === window || (responder as? NSView)?.window !== window
    }

    static let debounce: Duration = .milliseconds(250)

    private struct Key: Equatable { let text: String; let folder: URL?; let attempt: Int }
    private struct Run: Equatable { let key: Key; let active: Bool }

    var body: some View {
        ZStack(alignment: .top) {
            if let html {
                MarkdownWebView(html: html, folder: fileURL?.deletingLastPathComponent(), focus: focusRequest, visible: isActive)
            } else if failure == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Theme.background
            }
            if let failure {
                HStack(alignment: .top, spacing: Theme.s2) {
                    Label(failure, systemImage: "exclamationmark.triangle.fill").font(Theme.captionFont)
                        .textSelection(.enabled)
                    Spacer()
                    // Focusable without Full Keyboard Access, so a failed Read can take the keys; Return or Space retries.
                    Button("Try Again") { attempt += 1 }
                        .focusable()
                        .focused($retryFocused)
                        .onKeyPress(keys: [.return, .space]) { _ in attempt += 1; return .handled }
                }
                .padding(Theme.s2)
                .background(Theme.surface)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.warning).frame(height: 1) }
            }
        }
        .background(Theme.background)
        .background(WindowAnchorView(anchor: anchor))
        // The request can arrive after the render already failed (a missing Pandoc fails at once): still hand
        // the keys to Try Again rather than leave the window with no focused view.
        .onChange(of: focusRequest.wrappedValue) { _, requested in
            guard requested, html == nil, failure != nil else { return }
            DispatchQueue.main.async {
                if Self.hasFocusGap(anchor.view?.window) { retryFocused = true }
                focusRequest.wrappedValue = false
            }
        }
        .overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 1) }
        // A new key cancels the previous task, which cancels its sleep or terminates its Pandoc run. Inactive (under
        // Write) nothing runs; becoming active renders only if the text, folder or attempt changed meanwhile.
        .task(id: Run(key: Key(text: text, folder: fileURL?.deletingLastPathComponent(), attempt: attempt), active: isActive)) {
            let key = Key(text: text, folder: fileURL?.deletingLastPathComponent(), attempt: attempt)
            guard isActive, key != rendered else { return }
            if html != nil { try? await Task.sleep(for: Self.debounce) }
            guard !Task.isCancelled else { return }
            do {
                let page = try await render(text)
                guard !Task.isCancelled else { return }
                html = page // the page takes a pending focus request once it is in the window
                failure = nil
                rendered = key
            } catch is CancellationError {
            } catch {
                failure = error.localizedDescription // last good preview stays visible underneath
                rendered = key // Try Again (a new attempt) or an edit renders again; switching modes doesn't
                if html == nil, focusRequest.wrappedValue {
                    // No page: Try Again takes the keys, unless something got focus meanwhile.
                    DispatchQueue.main.async {
                        if Self.hasFocusGap(anchor.view?.window) { retryFocused = true }
                        focusRequest.wrappedValue = false
                    }
                }
            }
        }
    }
}

/// Gives SwiftUI views access to their window.
final class WindowAnchor { weak var view: NSView? }

struct WindowAnchorView: NSViewRepresentable {
    let anchor: WindowAnchor
    func makeNSView(context: Context) -> NSView { let view = NSView(); anchor.view = view; return view }
    func updateNSView(_ view: NSView, context: Context) { anchor.view = view }
}

/// SIGTERM, then SIGKILL after a second, so a child that ignores SIGTERM can't hang the preview.
private func stop(_ process: Process) {
    guard process.isRunning else { return }
    let pid = process.processIdentifier
    process.terminate()
    DispatchQueue.global().asyncAfter(deadline: .now() + 1) { if process.isRunning { kill(pid, SIGKILL) } }
}

/// Runs `operation`; calls `onCancel` on task cancellation and `onTimeout` once `MarkdownRenderer.timeout` passes.
private func runCancellable(_ operation: () async -> Void, onCancel: @escaping @Sendable () -> Void,
                            onTimeout: @escaping @Sendable () -> Void) async throws {
    let timer = Task { try await Task.sleep(for: MarkdownRenderer.timeout); onTimeout() }
    defer { timer.cancel() }
    await withTaskCancellationHandler(operation: operation, onCancel: onCancel)
}
