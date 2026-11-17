import AppKit
import PDFKit
import SwiftUI

@main
struct LibreLeafApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: TextDocument()) { file in
            EditorView(document: file.$document, fileURL: file.fileURL)
        }
    }
}

struct EditorView: View {
    @Binding var document: TextDocument
    let fileURL: URL?
    @StateObject private var builder = BuildService()
    @State private var pdfData: Data?
    @State private var isStale = false
    @State private var log = ""
    @State private var diagnostics: [Diagnostic] = []
    @State private var error: String?
    @State private var showLog = false

    private var isTeX: Bool { fileURL?.pathExtension.lowercased() == "tex" }
    private var isMarkdown: Bool { ["md", "markdown"].contains(fileURL?.pathExtension.lowercased() ?? "") }

    var body: some View {
        HSplitView {
            TextEditor(text: $document.text)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .frame(minWidth: 320)
            if isMarkdown {
                MarkdownPreview(text: document.text).frame(minWidth: 280)
            } else if isTeX {
                texPane.frame(minWidth: 280)
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .task { reopenSymlinkAtTarget() }
        .toolbar {
            if isTeX {
                if builder.isRunning {
                    Button("Cancel", systemImage: "stop.fill") { builder.cancel() }
                } else {
                    Button("Build", systemImage: "play.fill") { Task { await build() } }
                        .keyboardShortcut("b")
                }
                Button("Log", systemImage: "doc.plaintext") { showLog.toggle() }
                    .disabled(log.isEmpty)
            }
        }
        .sheet(isPresented: $showLog) {
            ScrollView { Text(log).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding() }
                .frame(minWidth: 600, minHeight: 400)
                .toolbar { Button("Done") { showLog = false } }
        }
        .alert("Build", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
        } message: { Text(error ?? "") }
    }

    private var texPane: some View {
        VStack(spacing: 0) {
            if let pdfData {
                PDFPreview(data: pdfData)
                    .overlay(alignment: .topTrailing) {
                        if isStale { Text("Stale").font(.caption).padding(4).background(.yellow, in: .capsule).padding(8) }
                    }
            } else {
                ContentUnavailableView("No PDF yet", systemImage: "doc.richtext", description: Text("Build (⌘B) compiles this file locally."))
            }
            if !diagnostics.isEmpty {
                List(diagnostics) { d in
                    Label("\(d.file?.lastPathComponent ?? "?"):\(d.line ?? 0) \(d.message)",
                          systemImage: d.isWarning ? "exclamationmark.triangle" : "xmark.octagon")
                        .textSelection(.enabled)
                }
                .frame(height: 120)
            }
        }
    }

    private func build() async {
        guard let fileURL else { error = "Save this file before building."; return }
        do {
            try await saveIfNeeded(fileURL)
            let result = try await builder.build(root: fileURL)
            log = result.log
            diagnostics = result.diagnostics
            if let data = result.pdfData { pdfData = data; isStale = false } else { isStale = pdfData != nil }
            if !result.succeeded && diagnostics.isEmpty { error = "Build failed. See Log for details." }
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

    /// Saves through the window's NSDocument so autosave, versions and conflict handling stay in charge.
    private func saveIfNeeded(_ url: URL) async throws {
        guard let doc = NSDocumentController.shared.document(for: url), doc.isDocumentEdited else { return }
        // Refuse to overwrite a file another app changed since we loaded it.
        let onDisk = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if let known = doc.fileModificationDate, let onDisk, onDisk > known {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey:
                "This file changed outside LibreLeaf. Use File ▸ Revert To or Save As before building."])
        }
        try await doc.save(to: url, ofType: doc.fileType ?? "public.plain-text", for: .saveOperation)
    }
}

struct PDFPreview: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        guard view.document?.dataRepresentation() != data else { return }
        let page = view.currentPage.flatMap { view.document?.index(for: $0) } ?? 0
        view.document = PDFDocument(data: data)
        if let restored = view.document?.page(at: page) { view.go(to: restored) }
    }
}

/// Native Markdown preview: headings, fences and inline styles. Code is displayed, never run.
struct MarkdownPreview: View {
    let text: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in block }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .textSelection(.enabled)
        }
    }

    // ponytail: line-based block parser; tables/images/math need Pandoc later.
    private var blocks: [Text] {
        var result: [Text] = []
        var fence: [Substring]?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("```") {
                if let code = fence { result.append(Text(code.joined(separator: "\n")).font(.system(.body, design: .monospaced))); fence = nil }
                else { fence = [] }
            } else if fence != nil {
                fence?.append(line)
            } else if let level = line.firstIndex(where: { $0 != "#" }).map({ line.distance(from: line.startIndex, to: $0) }),
                      (1...6).contains(level), line.dropFirst(level).first == " " {
                result.append(inline(line.dropFirst(level + 1)).font([.largeTitle, .title, .title2, .title3, .headline, .headline][level - 1]).bold())
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                result.append(inline(line))
            }
        }
        if let code = fence { result.append(Text(code.joined(separator: "\n")).font(.system(.body, design: .monospaced))) }
        return result
    }

    private func inline(_ line: Substring) -> Text {
        Text((try? AttributedString(markdown: String(line))) ?? AttributedString(String(line)))
    }
}
