import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let tex = UTType(importedAs: "org.tug.tex", conformingTo: .plainText)
    static let markdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

enum SourceFileError: LocalizedError {
    case unsupportedEncoding

    var errorDescription: String? {
        "This file is not UTF-8 text. LibreLeaf left it unchanged."
    }
}

/// Plain-text document that round-trips the original UTF-8 BOM and line endings.
/// NSDocument (behind DocumentGroup) supplies coordinated atomic saves, autosave,
/// versions and the "changed by another application" conflict check.
struct TextDocument: FileDocument {
    // ponytail: public.data lets Open With accept extensionless/unknown text files; non-UTF-8 bytes are rejected on read.
    static let readableContentTypes: [UTType] = [.tex, .markdown, .plainText, .data]
    static let writableContentTypes: [UTType] = [.tex, .markdown, .plainText]

    var text: String
    var hasBOM = false
    var usesCRLF = false

    init(text: String = "") { self.text = text }

    init(configuration: ReadConfiguration) throws {
        try self.init(data: configuration.file.regularFileContents ?? Data())
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

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data())
    }
}
