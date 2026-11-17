import AppKit
import NativeLatexDesign
import PDFKit
import SwiftUI

@main
struct LibreLeafApp: App {
    init() { _ = AppearanceStore.shared } // apply the saved appearance before the first window

    var body: some Scene {
        DocumentGroup(newDocument: TextDocument()) { file in
            EditorView(document: file.$document, fileURL: file.fileURL)
        }
        .commands {
            NewDocumentCommands()
            AppearanceCommands()
            ConvertCommands()
        }
        Settings { AppearanceSettingsView() }
    }
}

struct EditorView: View {
    @Binding var document: TextDocument
    let fileURL: URL?
    @StateObject private var builder = BuildService()
    @StateObject private var editor = TextViewHandle()
    @State private var pdfData: Data?
    @State private var builtText: String?
    @State private var isStale = false
    @State private var lastFailed = false
    @State private var lastBuild: Duration?
    @State private var log = ""
    @State private var diagnostics: [Diagnostic] = []
    @State private var error: String?
    @State private var showLog = false
    @State private var showPreview = true
    /// Below `narrowWidth` the window shows source *or* preview, never two squeezed columns.
    @State private var isNarrow = false
    @State private var narrowShowsPreview = false
    @State private var showProblems = false
    @State private var line = 1
    @State private var column = 1
    /// Another app changed the file while this window has unsaved edits.
    @State private var diskChanged = false
    @State private var seenDiskDate: Date?

    private var isTeX: Bool { BuildService.rootExtensions.contains(fileURL?.pathExtension.lowercased() ?? "") }
    private var isMarkdown: Bool { ["md", "markdown"].contains(fileURL?.pathExtension.lowercased() ?? "") }
    private var hasPreview: Bool { isTeX || isMarkdown }
    /// Same breakpoint as the Design package's WorkspaceShell: 320pt editor + 280pt preview + room.
    static let narrowWidth: CGFloat = 760

    private var buildState: BuildState {
        if builder.isRunning { return .building }
        if isStale { return .stale }
        if lastFailed { return .failed }
        return pdfData == nil ? .idle : .succeeded
    }

    private var problems: [Problem] {
        diagnostics.map { Problem(id: $0.id, severity: $0.isWarning ? .warning : .error, message: $0.message,
                                  file: $0.file?.lastPathComponent, line: $0.line) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VSplitView {
                // One split view in both widths, so resizing across the breakpoint keeps the editor in place
                // (and focused); only a narrow window's Preview toggle swaps the source out.
                HSplitView {
                    if !(isNarrow && narrowShowsPreview && hasPreview) { source.frame(minWidth: 320) }
                    if hasPreview, isNarrow ? narrowShowsPreview : showPreview { preview.frame(minWidth: 280) }
                }
                .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
                // On the whole pane, so the conflict banner stays visible while a narrow window shows the preview.
                .overlay(alignment: .top) { if diskChanged { diskBanner } }
                .onGeometryChange(for: Bool.self) { $0.size.width < Self.narrowWidth } action: { isNarrow = $0 }
                .layoutPriority(1)
                if showProblems, isTeX {
                    ProblemList(problems: problems, onSelect: reveal)
                        .frame(minHeight: 80, idealHeight: 140, maxHeight: 400)
                }
            }
            StatusBar(status: ShellStatus(errors: diagnostics.filter { !$0.isWarning }.count,
                                          warnings: diagnostics.filter(\.isWarning).count,
                                          line: line, column: column, lastBuild: lastBuild),
                      showPanel: $showProblems)
        }
        .libreLeafTheme()
        .frame(minWidth: 640, minHeight: 420)
        .focusedSceneValue(\.documentFileURL, fileURL)
        .task { reopenSymlinkAtTarget() }
        // ponytail: 2 s poll + activation check; swap for NSFilePresenter/FSEvents if many windows stay open.
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in checkDisk() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in checkDisk() }
        .onChange(of: narrowShowsPreview) {
            // Back to source: return keyboard focus to the editor (the preview took its place).
            if !narrowShowsPreview { DispatchQueue.main.async { editor.focus() } }
        }
        .onChange(of: document.text) {
            // The PDF shows the text as of the last successful build; any other text makes it stale.
            if pdfData != nil, !lastFailed { isStale = document.text != builtText }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if isTeX {
                    if builder.isRunning {
                        Button("Cancel", systemImage: "stop.fill") { builder.cancel() }
                            .keyboardShortcut(".")
                            .help("Cancel Build (⌘.)")
                    } else {
                        Button("Build", systemImage: "hammer") { Task { await build() } }
                            .keyboardShortcut("b")
                            .help("Build (⌘B)")
                    }
                    BuildStatusBadge(state: buildState)
                    Button("Log", systemImage: "doc.plaintext") { showLog.toggle() }
                        .disabled(log.isEmpty)
                        .help("Show Build Log")
                }
                if hasPreview {
                    if isNarrow {
                        // Narrow: preview replaces the source, so the toggle names itself in text.
                        Toggle(isOn: $narrowShowsPreview) {
                            Label("Preview", systemImage: "doc.richtext").labelStyle(.titleAndIcon)
                        }
                        .keyboardShortcut("p", modifiers: [.command, .option])
                        .help(narrowShowsPreview ? "Show Source (⌥⌘P)" : "Show Preview Instead of Source (⌥⌘P)")
                    } else {
                        Toggle(isOn: $showPreview) { Label("Preview", systemImage: "sidebar.right") }
                            .keyboardShortcut("p", modifiers: [.command, .option])
                            .help(showPreview ? "Hide Preview (⌥⌘P)" : "Show Preview (⌥⌘P)")
                    }
                }
                if !isNarrow { // narrow toolbars keep room for the labeled Preview toggle and BB-8; File ▸ Convert stays
                    Menu { ConvertMenuItems(fileURL: fileURL) } label: { Label("Convert", systemImage: "arrow.left.arrow.right") }
                        .help("Import or export a copy")
                }
                BB8Toggle()
            }
        }
        .sheet(isPresented: $showLog) {
            ScrollView { Text(log).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding() }
                .frame(minWidth: 600, minHeight: 400)
                .libreLeafTheme()
                .toolbar { Button("Done") { showLog = false } }
        }
        .alert("Build", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
        } message: { Text(error ?? "") }
    }

    private var texPreview: some View {
        Group {
            if let pdfData {
                // The toolbar's BuildStatusBadge says "Preview out of date" in text, symbol and color.
                PDFPreview(data: pdfData)
                    .accessibilityLabel(isStale ? "PDF preview, out of date" : "PDF preview")
            } else {
                ContentUnavailableView("No PDF yet", systemImage: "doc.richtext",
                                       description: Text("Build (⌘B) compiles this file locally."))
                    .background(Theme.surface)
            }
        }
    }

    private var source: some View {
        SourceTextView(text: $document.text, handle: editor) { line = $0; column = $1 }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var preview: some View {
        Group {
            if isMarkdown { MarkdownPreview(text: document.text) } else { texPreview }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var diskBanner: some View {
        HStack(spacing: Theme.s2) {
            Label("“\(fileURL?.lastPathComponent ?? "")” changed on disk. Your unsaved edits are kept.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(Theme.captionFont)
            Spacer()
            Button("Reload from Disk") { reloadFromDisk() }
                .help("Discard unsaved edits and load the version on disk")
            Button("Keep Mine") { diskChanged = false }
                .help("Keep editing; saving will ask how to resolve the conflict")
        }
        .padding(Theme.s2)
        .background(Theme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.warning).frame(height: 1) }
        .accessibilityElement(children: .contain)
    }

    /// DocumentGroup's NSDocument doesn't reload a clean buffer after another app writes the file,
    /// and cp -p/rsync can restore an older mtime. Any mtime other than NSDocument's own save date is
    /// an outside write: reload a clean buffer, flag a dirty one. Never discards unsaved edits.
    // ponytail: mtime-based; an outside write that reproduces NSDocument's exact save date is missed.
    private func checkDisk() {
        guard let fileURL, let doc = NSDocumentController.shared.document(for: fileURL) else { return }
        var url = fileURL
        url.removeAllCachedResourceValues()
        guard let onDisk = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              onDisk != doc.fileModificationDate, onDisk != seenDiskDate else { return }
        seenDiskDate = onDisk
        guard !document.matchesDisk(at: fileURL) else { return }
        if doc.isDocumentEdited { diskChanged = true } else { reloadFromDisk() }
    }

    private func reloadFromDisk() {
        guard let fileURL, let doc = NSDocumentController.shared.document(for: fileURL) else { return }
        do {
            try doc.revert(toContentsOf: fileURL, ofType: doc.fileType ?? "public.plain-text")
            diskChanged = false
        } catch {
            self.error = "LibreLeaf couldn’t reload “\(fileURL.lastPathComponent)”: \(error.localizedDescription)"
        }
    }

    private func reveal(_ problem: Problem) {
        guard let diagnostic = diagnostics.first(where: { $0.id == problem.id }), let file = diagnostic.file else { return }
        if file.resolvingSymlinksInPath() == fileURL?.resolvingSymlinksInPath() {
            if isNarrow, narrowShowsPreview {
                narrowShowsPreview = false // the source must be on screen to show the line
                DispatchQueue.main.async { editor.reveal(line: diagnostic.line ?? 1) }
            } else {
                editor.reveal(line: diagnostic.line ?? 1)
            }
        } else {
            NSDocumentController.shared.openDocument(withContentsOf: file, display: true) { _, _, _ in }
        }
    }

    private func build() async {
        guard let fileURL else { error = "Save this file before building."; return }
        do {
            try await NSDocument.saveEditedDocuments(under: fileURL.deletingLastPathComponent())
            guard document.matchesDisk(at: fileURL) else {
                error = "“\(fileURL.lastPathComponent)” on disk is not what this window shows; another app may have replaced it. Nothing was built or overwritten. Use File ▸ Revert To to load the disk version, or File ▸ Save As to keep yours as a new file."
                return
            }
            let source = document.text
            let start = ContinuousClock.now
            let result = try await builder.build(root: fileURL)
            lastBuild = .now - start
            log = result.log
            diagnostics = result.diagnostics
            lastFailed = !result.succeeded
            if let data = result.pdfData { pdfData = data; builtText = source }
            isStale = pdfData != nil && (lastFailed || document.text != builtText)
            if !result.succeeded { if diagnostics.isEmpty { error = "Build failed. See Log for details." } else { showProblems = true } }
        } catch BuildError.cancelled {
            isStale = pdfData != nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// NSDocument can't save onto a symlink, so edit the link's target instead.
    private func reopenSymlinkAtTarget() {
        guard let fileURL, (try? fileURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true,
              let linkDoc = NSDocumentController.shared.document(for: fileURL) else { return }
        NSDocumentController.shared.openDocument(withContentsOf: fileURL.resolvingSymlinksInPath(), display: true) { doc, _, _ in
            if doc != nil, !linkDoc.isDocumentEdited { linkDoc.close() }
        }
    }
}

struct PDFPreview: NSViewRepresentable {
    let data: Data

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) { context.coordinator.show(data, in: view) }

    @MainActor
    final class Coordinator {
        private(set) var shown: Data?

        /// Same bytes (every keystroke re-renders the window): leave page, zoom and scroll alone.
        /// `dataRepresentation()` re-serialises the PDF and never equals the input, so compare inputs.
        func show(_ data: Data, in view: PDFView) {
            guard data != shown else { return }
            shown = data
            let page = view.currentPage.flatMap { view.document?.index(for: $0) } ?? 0
            let autoScales = view.autoScales, scale = view.scaleFactor
            view.document = PDFDocument(data: data)
            if !autoScales { view.scaleFactor = scale }
            if let restored = view.document?.page(at: page) { view.go(to: restored) }
        }
    }
}

/// Native Markdown preview: headings, fences, lists, quotes and inline styles. Code is displayed, never run.
struct MarkdownPreview: View {
    let text: String

    enum Block: Equatable {
        case heading(Int, String), paragraph(String), code(String)
        /// `marker` is "•" or the original number ("2."), so ordered lists keep their numbering.
        case listItem(depth: Int, marker: String, text: String)
        case quote(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Label(Self.limitations, systemImage: "info.circle")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.secondary)
                    .padding(.bottom, Theme.s2)
                ForEach(Array(Self.blocks(text).enumerated()), id: \.offset) { _, block in render(block) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.s4)
            .textSelection(.enabled)
        }
        .background(Theme.background)
        .tint(Theme.accentText)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 1) }
    }

    static let limitations = "Basic preview: tables, images, math and footnotes may appear as source or simplified text."

    // ponytail: line-based parser; tables/images/math/nested quotes need Pandoc later.
    static func blocks(_ text: String) -> [Block] {
        // Lone CR (classic Mac) and CRLF both end lines.
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
        var result: [Block] = []
        var fence: [Substring]?
        for line in lines {
            let trimmed = line.drop { $0 == " " || $0 == "\t" }
            let indent = line.count - trimmed.count
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if let code = fence { result.append(.code(code.joined(separator: "\n"))); fence = nil } else { fence = [] }
            } else if fence != nil {
                fence?.append(line)
            } else if let match = trimmed.wholeMatch(of: /(#{1,6}) +(.*)/), indent < 4 {
                result.append(.heading(match.1.count, String(match.2)))
            } else if let match = trimmed.wholeMatch(of: /> ?(.*)/) {
                result.append(.quote(String(match.1)))
            } else if let match = trimmed.wholeMatch(of: /([-*+]|\d{1,9}[.)]) +(.*)/) {
                let marker = match.1.first!.isNumber ? String(match.1) : "•"
                result.append(.listItem(depth: indent / 2, marker: marker, text: String(match.2)))
            } else if !trimmed.isEmpty {
                result.append(.paragraph(String(line)))
            }
        }
        if let code = fence { result.append(.code(code.joined(separator: "\n"))) }
        return result
    }

    @ViewBuilder private func render(_ block: Block) -> some View {
        switch block {
        case let .heading(level, text):
            inline(text).font([.largeTitle, .title, .title2, .title3, .headline, .headline][level - 1]).bold()
        case let .paragraph(text):
            inline(text)
        case let .code(text):
            Text(text).font(Theme.editorFont)
        case let .listItem(depth, marker, text):
            HStack(alignment: .firstTextBaseline, spacing: Theme.s2) {
                Text(marker).foregroundStyle(Theme.secondary).monospacedDigit()
                inline(text)
            }
            .padding(.leading, CGFloat(depth) * Theme.s5)
        case let .quote(text):
            inline(text)
                .foregroundStyle(Theme.secondary)
                .padding(.leading, Theme.s3)
                .overlay(alignment: .leading) { Rectangle().fill(Theme.accent).frame(width: 3) }
                .accessibilityLabel("Quote: \(text)")
        }
    }

    private func inline(_ line: String) -> Text { Text(Self.inline(line)) }

    /// Inline Markdown; links in the brand blue-text token and underlined, so color isn't the only cue.
    static func inline(_ line: String) -> AttributedString {
        var text = (try? AttributedString(markdown: line)) ?? AttributedString(line)
        for run in text.runs where run.link != nil {
            text[run.range].foregroundColor = Theme.accentText
            text[run.range].underlineStyle = .single
        }
        return text
    }
}
