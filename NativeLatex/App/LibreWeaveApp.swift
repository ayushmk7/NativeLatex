import AppKit
import NativeLatexDesign
import PDFKit
import SwiftUI

@main
struct LibreWeaveApp: App {
    init() {
        Self.migrateAppearance(into: .standard, legacy: UserDefaults(suiteName: BuildService.legacyDefaultsDomain))
        _ = AppearanceStore.shared // apply the saved appearance before the first window
    }

    /// The bundle ID changed from app.libreleaf.LibreLeaf: carry the user's BB-8 choice over once.
    /// A value already in the new domain wins; an unknown old value is ignored. The old domain is only read.
    static func migrateAppearance(into defaults: UserDefaults, legacy: UserDefaults?) {
        let key = "appearanceMode" // AppearanceStore.defaultsKey, internal to the Design package
        guard defaults.object(forKey: key) == nil,
              let old = legacy?.string(forKey: key), AppAppearance(rawValue: old) != nil else { return }
        defaults.set(old, forKey: key)
    }

    var body: some Scene {
        DocumentGroup(newDocument: NewDocument.makeDocument()) { file in
            EditorView(document: file.$document, fileURL: file.fileURL)
        }
        .commands {
            NewDocumentCommands()
            PaneCommands()
            MarkdownFormatCommands()
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
    @StateObject private var writer = WritingHandle()
    @State private var pdfData: Data?
    @State private var builtText: String?
    @State private var isStale = false
    @State private var lastFailed = false
    @State private var lastBuild: Duration?
    @State private var log = ""
    @State private var diagnostics: [Diagnostic] = []
    @State private var error: String?
    @State private var showLog = false
    /// Per window: source only, both side by side, or preview only.
    /// Per window: Source / Both / Preview, and Read or Write for Markdown (see PaneState).
    @State private var panes = PaneState()
    /// Read should take keyboard focus when its render settles (see MarkdownPreview.focusRequest).
    @State private var readFocus = false
    /// Below `narrowWidth` the window shows source *or* preview, never two squeezed columns.
    @State private var isNarrow = false
    @State private var showProblems = false
    @State private var line = 1
    @State private var column = 1
    /// Another app changed the file while this window has unsaved edits.
    @State private var diskChanged = false
    @State private var seenDiskDate: Date?

    /// Untitled and duplicated windows have no URL yet; the document's type stands in until the first save.
    private var isTeX: Bool { BuildService.rootExtensions.contains(document.sourceExtension(at: fileURL)) }
    private var isMarkdown: Bool { ["md", "markdown"].contains(document.sourceExtension(at: fileURL)) }
    private var hasPreview: Bool { isTeX || isMarkdown }
    /// Same breakpoint as the Design package's WorkspaceShell: 320pt editor + 280pt preview + room.
    static let narrowWidth: CGFloat = 760

    private var markdownWrite: Bool { panes.write }

    /// What the window shows: no preview for plain text; a narrow window can't show both; Write fills the window.
    private var shown: PaneLayout { panes.shown(narrow: isNarrow, hasPreview: hasPreview, markdown: isMarkdown) }

    /// Controls show what is on screen; choosing sets the requested layout (Both returns when the window widens).
    private var shownBinding: Binding<PaneLayout> { Binding(get: { shown }, set: { panes.choose($0) }) }

    /// Formatting needs an editable Markdown view on screen: Write, or the source beside or instead of Read.
    private var canFormat: Bool { panes.canFormat(narrow: isNarrow, markdown: isMarkdown) }

    /// The view Format commands and the format bar act on: the one editable view on screen (Write, else the
    /// source), which then takes focus. A hidden pane that still holds focus mid-transition is never edited.
    private func formatTarget() -> NSTextView? {
        let pane = panes.formatPane(narrow: isNarrow, markdown: isMarkdown)
        guard let view = pane == .write ? writer.view : pane == .source ? editor.view : nil, view.window != nil else { return nil }
        if view.window?.firstResponder !== view { view.window?.makeFirstResponder(view) }
        return view
    }

    /// Document Mode shows what is on screen: neither Read nor Write while only the source is visible
    /// (Source Only, or Both in a narrow window, which keeps the editor so typing survives a resize).
    private var modeSelection: Binding<Bool?> {
        Binding(get: { shown == .source ? nil : panes.write }, set: { if let on = $0 { writeBinding.wrappedValue = on } })
    }

    private var writeBinding: Binding<Bool> {
        Binding(get: { panes.write }, set: { on in if isMarkdown { panes.setWrite(on, narrow: isNarrow) } })
    }

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
                    if shown != .preview { source.frame(minWidth: 320) }
                    if shown != .source { preview.frame(minWidth: 280) }
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
        .libreWeaveTheme()
        .frame(minWidth: 640, minHeight: 420)
        .focusedSceneValue(\.documentFileURL, fileURL)
        .focusedSceneValue(\.paneControls, hasPreview ? PaneControls(layout: shownBinding, isNarrow: isNarrow,
                                                                    write: isMarkdown ? writeBinding : nil,
                                                                    formatTarget: canFormat ? formatTarget : nil) : nil)
        .task { reopenSymlinkAtTarget() }
        // ponytail: 2 s poll + activation check; swap for NSFilePresenter/FSEvents if many windows stay open.
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in checkDisk() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in checkDisk() }
        .onChange(of: shown) { old, new in
            if new != .preview { readFocus = false }
            // Focus follows the pane that just appeared in place of the one holding it.
            if old == .preview, new != .preview { DispatchQueue.main.async { editor.focus() } }
            if new == .preview, isMarkdown, markdownWrite { DispatchQueue.main.async { writer.focus() } }
        }
        .onChange(of: markdownWrite) {
            // Write replaces the source (and back): the caret and scroll position carry over. Focus first, so
            // Write reveals the markup on the caret's line.
            if markdownWrite { readFocus = false } // Write owns focus now; a pending Read hand-off is void
            if markdownWrite, shown != .source { DispatchQueue.main.async { writer.focus(); writer.takeSelection(from: editor) } }
            // Leaving Write removes the focused editor; keep the keyboard in the window.
            if !markdownWrite { DispatchQueue.main.async { editor.takeSelection(from: writer); focusAfterRead() } }
        }
        .onChange(of: isMarkdown) {
            // Saved as another type (e.g. .tex) while in Write: Write is Markdown-only, so return to the earlier layout.
            if !isMarkdown, panes.write { panes.setWrite(false, narrow: isNarrow) }
        }
        .onChange(of: document.text) {
            // Keep both text views on the buffer, visible or not, so undo in either stays valid.
            editor.sync(document.text)
            writer.sync(document.text)
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
                    Picker("Layout", selection: shownBinding) {
                        Label("Source", systemImage: "doc.plaintext").tag(PaneLayout.source)
                        Label("Source and Preview", systemImage: "rectangle.split.2x1").tag(PaneLayout.both)
                            .selectionDisabled(isNarrow)
                        Label("Preview", systemImage: "doc.richtext").tag(PaneLayout.preview)
                    }
                    .pickerStyle(.segmented)
                    .labelStyle(.iconOnly)
                    .help(isNarrow ? "Show Source or Preview (⌥⌘1, ⌥⌘3); widen the window to show both"
                                   : "Show Source (⌥⌘1), Both (⌥⌘2) or Preview (⌥⌘3)")
                    .accessibilityLabel("Layout")
                }
                if isMarkdown {
                    // In the toolbar, so every Markdown window offers it in every layout and width.
                    Picker("Document Mode", selection: modeSelection) {
                        Text("Read").tag(Bool?.some(false))
                        Text("Write").tag(Bool?.some(true))
                    }
                    .pickerStyle(.segmented)
                    .help("Read: the Pandoc rendering beside or instead of the source. Write: edit the formatted document full width with markup hidden; tables, math and images stay as Markdown (⌥⌘E). Read or Source Only (⌥⌘1) leaves Write.")
                    .accessibilityLabel("Document Mode")
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
                .libreWeaveTheme()
                .toolbar { Button("Done") { showLog = false } }
        }
        .alert("Build", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
        } message: { Text(error ?? "") }
    }

    /// After Read: the source if it is on screen, else the Read page (scroll keys work there). The page
    /// appears once Pandoc has rendered, so this retries briefly.
    /// After leaving Write, fill the focus gap: the source if visible, else ask Read to take focus when its
    /// render settles (page, or Try Again on failure). Write coming back, or any focus meanwhile, wins.
    private func focusAfterRead() {
        guard !markdownWrite, MarkdownPreview.hasFocusGap(writer.window ?? editor.window) else { return }
        if shown != .preview { editor.focus() } else { readFocus = true }
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
            if isMarkdown { markdownPane } else { texPreview }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Read stays mounted under Write (hidden, not rendering), so switching back shows the same page at the
    /// same scroll position with no spinner or Pandoc run unless the text changed.
    private var markdownPane: some View {
        ZStack {
            MarkdownPreview(text: document.text, fileURL: fileURL, focusRequest: $readFocus, isActive: !markdownWrite)
                .opacity(markdownWrite ? 0 : 1)
                .allowsHitTesting(!markdownWrite)
                .accessibilityHidden(markdownWrite)
            if markdownWrite {
                VStack(spacing: 0) {
                    MarkdownFormatBar(target: formatTarget)
                        .background(Theme.surface)
                    HandleTextView(text: $document.text, handle: writer, label: "Write") { line = $0; column = $1 }
                }
                .background(Theme.background)
            }
        }
        .overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 1) }
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
            self.error = "LibreWeave couldn’t reload “\(fileURL.lastPathComponent)”: \(error.localizedDescription)"
        }
    }

    private func reveal(_ problem: Problem) {
        guard let diagnostic = diagnostics.first(where: { $0.id == problem.id }), let file = diagnostic.file else { return }
        if file.resolvingSymlinksInPath() == fileURL?.resolvingSymlinksInPath() {
            if shown == .preview {
                panes.choose(isNarrow ? .source : .both) // the source must be on screen to show the line
                DispatchQueue.main.async { editor.reveal(line: diagnostic.line ?? 1) }
            } else {
                editor.reveal(line: diagnostic.line ?? 1)
            }
        } else {
            NSDocumentController.shared.openDocument(withContentsOf: file, display: true) { _, _, _ in }
        }
    }

    private func build() async {
        var root = fileURL
        if root == nil { root = await saveUntitledForBuild() }
        guard let fileURL = root else { return }
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

    /// Untitled LaTeX: Build shows the normal Save panel, then builds the saved file.
    /// Cancel writes nothing and builds nothing; save errors are shown by NSDocument itself.
    private func saveUntitledForBuild() async -> URL? {
        guard let window = editor.view?.window ?? NSApp.keyWindow,
              let doc = NSDocumentController.shared.document(for: window) else {
            error = "Save this document (File ▸ Save, ⌘S), then build."
            return nil
        }
        guard let url = await doc.saveUntitled() else { return nil }
        guard BuildService.rootExtensions.contains(url.pathExtension.lowercased()) else {
            error = "Saved as “\(url.lastPathComponent)”. Build works on .tex, .ltx and .latex files."
            return nil
        }
        return url
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

/// The focused window's pane state, for the View menu.
struct PaneControls {
    var layout: Binding<PaneLayout>
    var isNarrow: Bool
    /// Markdown only: Read/Write mode of the preview pane.
    var write: Binding<Bool>?
    /// Markdown with an editable view on screen: the view Format commands act on. Nil disables them.
    var formatTarget: (() -> NSTextView?)?
}

extension FocusedValues {
    @Entry var paneControls: PaneControls? = nil
}

/// View ▸ Source Only / Source and Preview / Preview Only, and Write (full-width editing) for Markdown.
struct PaneCommands: Commands {
    @FocusedValue(\.paneControls) private var controls

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            item("Source Only", .source, "1")
            item("Source and Preview", .both, "2")
                .disabled(controls == nil || controls?.isNarrow == true)
            item("Preview Only", .preview, "3")
            Button("Toggle Preview") {
                guard let controls else { return }
                controls.layout.wrappedValue = controls.layout.wrappedValue.toggled(narrow: controls.isNarrow)
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(controls == nil)
            // Write fills the window; turning it off returns to the previous layout.
            Toggle("Write", isOn: Binding(get: { controls?.write?.wrappedValue ?? false }, set: { controls?.write?.wrappedValue = $0 }))
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(controls?.write == nil)
            Divider()
        }
    }

    private func item(_ title: String, _ layout: PaneLayout, _ key: KeyEquivalent) -> some View {
        Toggle(title, isOn: Binding(get: { controls?.layout.wrappedValue == layout },
                                    set: { _ in controls?.layout.wrappedValue = layout }))
            .keyboardShortcut(key, modifiers: [.command, .option])
            .disabled(controls == nil)
    }
}

/// Format menu for Markdown windows, acting on the window's focused (else visible) Source or Write view.
/// Its items only exist for Markdown, so ⌘B stays Build in LaTeX windows; they are disabled when nothing
/// editable is on screen (Read in Preview Only), instead of silently doing nothing.
struct MarkdownFormatCommands: Commands {
    @FocusedValue(\.paneControls) private var controls

    /// Menu sections in the formatting bar's order: inline styles, then block styles, from the shared list.
    static var sections: [[MarkdownFormat.Command]] {
        let all = MarkdownFormat.Command.all
        return [all.filter { $0.group == .inline }, all.filter { $0.group == .block }].filter { !$0.isEmpty }
    }

    var body: some Commands {
        CommandMenu("Format") {
            if controls?.write != nil {
                ForEach(Array(Self.sections.enumerated()), id: \.offset) { index, section in
                    if index > 0 { Divider() }
                    ForEach(section) { command in
                        Button(command.title) { if let view = controls?.formatTarget?() { command.perform(on: view) } }
                            .keyboardShortcut(command.shortcut)
                            .disabled(controls?.formatTarget == nil)
                    }
                }
            } else {
                Text("Formatting is available in Markdown documents.")
            }
        }
    }
}
