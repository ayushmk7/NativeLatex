import AppKit
import NativeLatexIntegrations
import SwiftUI
import UniformTypeIdentifiers

/// Bridges NSDocument's delegate-style save callback to async.
private final class SaveCallback: NSObject {
    var done: ((Bool) -> Void)?
    @objc func document(_ document: NSDocument, didSave: Bool, contextInfo: UnsafeMutableRawPointer?) { done?(didSave) }
}

extension NSDocument {
    /// Same path as ⌘S: NSDocument's own "changed by another application" check (which also
    /// catches cp -p/rsync replacements) shows its sheet, and nothing is overwritten unless the user chooses to.
    func saveIfEdited() async throws {
        guard isDocumentEdited, let url = fileURL else { return }
        guard await runSave() else {
            throw CocoaError(.userCancelled, userInfo: [NSLocalizedDescriptionKey:
                "“\(url.lastPathComponent)” was not saved, so LibreWeave stopped. Save it (or resolve the change made by another app), then try again."])
        }
    }

    /// Untitled document: the normal Save panel, as for ⌘S. Returns the saved file, or nil on
    /// Cancel (nothing written). A document that already has a file just returns it.
    func saveUntitled() async -> URL? {
        if let fileURL { return fileURL }
        return await runSave() ? fileURL : nil
    }

    private func runSave() async -> Bool {
        let callback = SaveCallback()
        return await withCheckedContinuation { continuation in
            callback.done = { continuation.resume(returning: $0) }
            save(withDelegate: callback, didSave: #selector(SaveCallback.document(_:didSave:contextInfo:)), contextInfo: nil)
        }
    }

    /// Saves every edited open document inside `folder` (root, \\input files, .bib, .sty), since TeX reads them from disk.
    static func saveEditedDocuments(under folder: URL) async throws {
        let base = folder.resolvingSymlinksInPath().path + "/"
        for document in NSDocumentController.shared.documents
        where document.isDocumentEdited && document.fileURL?.resolvingSymlinksInPath().path.hasPrefix(base) == true {
            try await document.saveIfEdited()
        }
    }
}

extension DocumentFormat {
    var displayName: String {
        switch self {
        case .latex: "LaTeX"
        case .markdown: "Markdown"
        case .docx: "Word (DOCX)"
        case .odt: "OpenDocument (ODT)"
        case .html: "HTML"
        case .pdf: "PDF"
        }
    }
}

/// Import/Export Copy, LibreTexts import and the Google Docs status, driven from menus and the toolbar.
/// Every conversion writes a new file next to its source (or in a folder the user picks);
/// LocalConverter never overwrites and never modifies the source.
@MainActor
enum Conversions {
    static let copyFormats: [DocumentFormat] = [.docx, .odt, .markdown, .latex]

    /// No live Google transport ships, so this is always `.liveNotConfigured`.
    static let googleDocs = GoogleDocsIntegration(enabled: true)

    static func exportTargets(for url: URL?) -> [DocumentFormat] {
        guard let from = url.flatMap({ DocumentFormat(fileExtension: $0.pathExtension) }),
              from == .latex || from == .markdown else { return [] }
        return copyFormats.filter { $0 != from }
    }

    static var googleDocsMessage: String {
        googleDocs.status == .ready ? "Google Docs is connected." : GoogleDocsError.liveNotConfigured.localizedDescription
    }

    nonisolated static func convert(_ source: URL, to format: DocumentFormat, in folder: URL,
                                    converter: LocalConverter = LocalConverter()) async throws -> ConversionResult {
        try await Task.detached { try converter.convert(source, to: format, in: folder) }.value
    }

    // MARK: Actions

    static func exportCurrent(to format: DocumentFormat) {
        guard let document = NSDocumentController.shared.currentDocument, let url = document.fileURL else {
            return fail("Save this file before exporting a copy.")
        }
        Task {
            do {
                try await document.saveIfEdited()
                let result = try await convert(url, to: format, in: url.deletingLastPathComponent())
                present(result, title: "Exported a \(format.displayName) copy")
            } catch { fail(error.localizedDescription) }
        }
    }

    static func importCopy(as format: DocumentFormat) {
        let panel = NSOpenPanel()
        panel.message = "Choose a file. LibreWeave writes a new \(format.displayName) copy next to it; the original is not changed."
        panel.prompt = "Import Copy"
        panel.allowedContentTypes = ["docx", "odt", "md", "markdown", "tex", "ltx", "latex"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let source = panel.url else { return }
        Task {
            do {
                let result = try await convert(source, to: format, in: source.deletingLastPathComponent())
                present(result, title: "Imported a \(format.displayName) copy")
            } catch { fail(error.localizedDescription) }
        }
    }

    static func importLibreTexts(as format: DocumentFormat) {
        let alert = NSAlert()
        alert.messageText = "Import LibreTexts Page"
        alert.informativeText = "Paste a public https://….libretexts.org page link. Only openly licensed pages are copied, with attribution kept in the file."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        field.placeholderString = "https://chem.libretexts.org/Bookshelves/…"
        alert.accessoryView = field
        alert.addButton(withTitle: "Choose Folder…")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let link = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pageURL = URL(string: link) else { return fail(LibreTextsError.notLibreTextsURL(link).localizedDescription) }
        do { _ = try LibreTextsClient.apiURL(for: pageURL) } catch { return fail(error.localizedDescription) }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Import Here"
        panel.message = "Choose where to save the new \(format.displayName) copy."
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        Task {
            do {
                let (page, result) = try await LibreTextsClient().importPage(pageURL, as: format, into: folder)
                present(result, title: "Imported “\(page.title)”", preface: attribution(page))
            } catch { fail(error.localizedDescription) }
        }
    }

    static func showGoogleDocsStatus() {
        let alert = NSAlert()
        alert.messageText = "Google Docs: not connected"
        alert.informativeText = googleDocsMessage + "\n\nUse Export Copy ▸ Word (DOCX), then upload it at docs.google.com."
        alert.runModal()
    }

    // MARK: Presentation

    static func attribution(_ page: LibreTextsPage) -> String {
        attribution(title: page.title, authors: page.authors, license: page.license, url: page.pageURL)
    }

    static func attribution(title: String, authors: [String], license: String?, url: URL) -> String {
        let by = authors.isEmpty ? "" : " by \(authors.joined(separator: ", "))"
        return "Source: \(title)\(by), LibreTexts\nLicense: \(license ?? "none")\n\(url.absoluteString)\nThe copy starts with this attribution; keep it when you reuse the text."
    }

    static func summary(_ result: ConversionResult, preface: String? = nil) -> String {
        var parts = [preface,
                     "Saved as “\(result.outputURL.lastPathComponent)” in \(result.outputURL.deletingLastPathComponent().path) (\(result.tool)).",
                     result.mediaDirectory.map { "Images: \($0.lastPathComponent)/" }].compactMap { $0 }
        parts.append("Review notes:\n" + result.reviewNotes.map { "• \($0)" }.joined(separator: "\n"))
        return parts.joined(separator: "\n\n")
    }

    private static func present(_ result: ConversionResult, title: String, preface: String? = nil) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = summary(result, preface: preface)
        alert.addButton(withTitle: "Open Copy")
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "Done")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let url = result.outputURL
            if ["tex", "ltx", "latex", "md", "markdown"].contains(url.pathExtension.lowercased()) {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            } else {
                NSWorkspace.shared.open(url)
            }
        case .alertSecondButtonReturn:
            NSWorkspace.shared.activateFileViewerSelecting([result.outputURL])
        default: break
        }
    }

    private static func fail(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Conversion not completed"
        alert.informativeText = message
        alert.runModal()
    }
}

/// Shared by the File ▸ Convert menu and the window toolbar.
struct ConvertMenuItems: View {
    /// The front document's file; nil when there is none or it is unsaved.
    var fileURL: URL?

    var body: some View {
        let targets = Conversions.exportTargets(for: fileURL)
        Menu("Export Copy") {
            ForEach(targets, id: \.self) { format in
                Button(format.displayName + "…") { Conversions.exportCurrent(to: format) }
            }
        }
        .disabled(targets.isEmpty)
        Menu("Import Copy") {
            Button("As LaTeX…") { Conversions.importCopy(as: .latex) }
            Button("As Markdown…") { Conversions.importCopy(as: .markdown) }
        }
        Menu("Import LibreTexts Page") {
            Button("As LaTeX…") { Conversions.importLibreTexts(as: .latex) }
            Button("As Markdown…") { Conversions.importLibreTexts(as: .markdown) }
        }
        Divider()
        Button("Google Docs: Not Connected…") { Conversions.showGoogleDocsStatus() }
    }
}

struct ConvertCommands: Commands {
    @FocusedValue(\.documentFileURL) private var fileURL

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Menu("Convert") { ConvertMenuItems(fileURL: fileURL ?? nil) }
        }
    }
}

extension FocusedValues {
    @Entry var documentFileURL: URL?? = nil
}
