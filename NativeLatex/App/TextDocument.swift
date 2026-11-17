import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let tex = UTType(importedAs: "org.tug.tex", conformingTo: .plainText)
    static let markdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
    static let bibtex = UTType(importedAs: "org.tug.bib", conformingTo: .plainText)
    static let texPackage = UTType(importedAs: "org.tug.sty", conformingTo: .plainText)
    static let texClass = UTType(importedAs: "org.tug.cls", conformingTo: .plainText)
}

enum SourceFileError: LocalizedError {
    case unsupportedEncoding

    var errorDescription: String? {
        "This file is not UTF-8 text. LibreWeave left it unchanged."
    }
}

/// Plain-text document that round-trips the original UTF-8 BOM and line endings.
/// NSDocument (behind DocumentGroup) supplies coordinated atomic saves, autosave,
/// versions and the "changed by another application" conflict check.
struct TextDocument: FileDocument {
    // Text types only: claiming public.data put LibreWeave in Open With for every binary file.
    // ponytail: extensionless files resolve to public.data and can't be opened; add a typed Open panel if needed.
    static let readableContentTypes: [UTType] = [.tex, .markdown, .bibtex, .texPackage, .texClass, .plainText]
    static let writableContentTypes: [UTType] = [.tex, .markdown, .plainText]

    var text: String
    var hasBOM = false
    var usesCRLF = false
    /// Format of this document. Untitled and duplicated documents have no file URL yet, so the
    /// window needs this to keep Markdown preview and TeX controls. Not saved into the file.
    var contentType: UTType = .plainText

    init(text: String = "", contentType: UTType = .plainText) {
        self.text = text
        self.contentType = contentType
    }

    init(configuration: ReadConfiguration) throws {
        try self.init(data: configuration.file.regularFileContents ?? Data())
        contentType = configuration.contentType // also set for Duplicate, which has no URL
    }

    /// The saved file's own extension when there is a file (so .ltx stays .ltx); otherwise the
    /// type's preferred one (tex, md, txt).
    func sourceExtension(at fileURL: URL?) -> String {
        (fileURL.map(\.pathExtension) ?? contentType.preferredFilenameExtension ?? "").lowercased()
    }

    init(data: Data) throws {
        hasBOM = data.starts(with: [0xEF, 0xBB, 0xBF])
        guard let original = String(data: hasBOM ? data.dropFirst(3) : data, encoding: .utf8),
              !original.contains("\0") else { throw SourceFileError.unsupportedEncoding }
        // Convert only files that are consistently CRLF; mixed endings are kept byte-for-byte.
        let crlf = original.components(separatedBy: "\r\n").count - 1
        usesCRLF = crlf > 0 && crlf == original.components(separatedBy: "\n").count - 1
        text = usesCRLF ? original.replacingOccurrences(of: "\r\n", with: "\n") : original
    }

    func data() -> Data {
        // Normalize first so pasted CRLF text doesn't become CR CR LF.
        let out = usesCRLF ? text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n") : text
        var bytes = Data(out.utf8)
        if hasBOM { bytes.insert(contentsOf: [0xEF, 0xBB, 0xBF], at: 0) }
        return bytes
    }

    /// True when the file holds exactly the bytes this buffer would save. Catches external
    /// replacements NSDocument misses on a clean buffer (cp -p/rsync keep an older mtime).
    func matchesDisk(at url: URL) -> Bool {
        (try? Data(contentsOf: url)) == data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data())
    }
}
