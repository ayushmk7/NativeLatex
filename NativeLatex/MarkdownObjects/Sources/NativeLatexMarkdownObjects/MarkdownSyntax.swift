import AppKit
import ImageIO

/// Finds pipe tables and images in Markdown source, and resolves/loads local images.
public enum MarkdownSyntax {
    public enum Alignment: Equatable { case none, left, center, right }

    public struct Row {
        /// The line without its newline.
        public let line: NSRange
        /// Unescaped pipes outside code spans.
        public let pipes: [Int]
        /// Cell contents, trimmed of spaces.
        public let cells: [NSRange]
        /// The spaces trimmed from cells.
        public let padding: [NSRange]
        public let leading: Bool
    }

    public struct Table {
        public let range: NSRange
        /// Header, delimiter row, body rows.
        public let rows: [Row]
        public let alignments: [Alignment]
        public var leadingPipe: Bool { rows[0].leading }
    }

    // MARK: Tables

    /// `line` is in `text`; the returned ranges are shifted by `base` (text is a copied block of the storage).
    static func row(_ text: NSString, _ line: NSRange, base: Int = 0) -> Row {
        let end = NSMaxRange(line)
        var pipes: [Int] = []
        var i = line.location, codeRun = 0
        while i < end {
            let c = text.character(at: i)
            if c == 92 /* \ */, codeRun == 0 { i += 2; continue }
            if c == 96 /* ` */ {
                var n = 0
                while i < end, text.character(at: i) == 96 { n += 1; i += 1 }
                if codeRun == 0 { codeRun = n } else if n == codeRun { codeRun = 0 }
                continue
            }
            if c == 124 /* | */, codeRun == 0 { pipes.append(i) }
            i += 1
        }
        func isSpace(_ i: Int) -> Bool { let c = text.character(at: i); return c == 32 || c == 9 }
        var first = line.location, last = end - 1
        while first < end, isSpace(first) { first += 1 }
        while last >= first, isSpace(last) { last -= 1 }
        let leading = pipes.first == first && first < end
        let trailing = pipes.last == last && last >= first && !(leading && pipes.count == 1)
        let seps = (leading ? [] : [line.location - 1]) + pipes + (trailing ? [] : [end])
        var cells: [NSRange] = [], padding: [NSRange] = []
        for (a, b) in zip(seps, seps.dropFirst()) {
            var s = a + 1, e = b
            while s < e, isSpace(s) { s += 1 }
            while e > s, isSpace(e - 1) { e -= 1 }
            cells.append(NSRange(location: s, length: e - s))
            padding.append(NSRange(location: a + 1, length: s - (a + 1)))
            padding.append(NSRange(location: e, length: b - e))
        }
        func shift(_ r: NSRange) -> NSRange { NSRange(location: r.location + base, length: r.length) }
        return Row(line: shift(line), pipes: pipes.map { $0 + base }, cells: cells.map(shift), padding: padding.map(shift), leading: leading)
    }

    static func alignments(_ text: NSString, _ row: Row) -> [Alignment]? {
        guard !row.pipes.isEmpty, !row.cells.isEmpty else { return nil }
        var result: [Alignment] = []
        for cell in row.cells {
            let s = text.substring(with: cell)
            let core = s.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            guard !core.isEmpty, core.allSatisfy({ $0 == "-" }), s.count - core.count <= 2 else { return nil }
            let l = s.hasPrefix(":"), r = s.hasSuffix(":")
            result.append(l && r ? .center : r ? .right : l ? .left : .none)
        }
        return result
    }

    /// Pipe tables (header, delimiter row, body until a blank or pipeless line) whose header is in `range`.
    public static func tables(in storageText: NSString, range: NSRange) -> [Table] {
        // A copy of the block: character access on a text storage's string is slow (~6 ms for a 22-row table).
        let text = storageText.substring(with: range) as NSString, base = range.location
        var lines: [NSRange] = []
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byLines, .substringNotRequired]) { _, line, _, _ in lines.append(line) }
        var tables: [Table] = []
        var i = 1
        while i < lines.count {
            let delimiter = row(text, lines[i])
            guard let aligns = alignments(text, delimiter) else { i += 1; continue }
            let header = row(text, lines[i - 1], base: base)
            guard !header.pipes.isEmpty, header.cells.count == aligns.count else { i += 1; continue }
            var rows = [header, row(text, lines[i], base: base)]
            var j = i + 1
            while j < lines.count {
                let r = row(text, lines[j], base: base)
                if r.pipes.isEmpty || r.cells.allSatisfy({ $0.length == 0 }) && r.pipes.isEmpty { break }
                rows.append(r); j += 1
            }
            tables.append(Table(range: NSRange(location: header.line.location, length: NSMaxRange(rows.last!.line) - header.line.location),
                                rows: rows, alignments: aligns))
            i = j + 1
        }
        return tables
    }

    // MARK: Images

    public struct Image { public let range: NSRange; public let source: String }
    private static let image = try! NSRegularExpression(pattern: #"!\[[^\]\n]{0,300}\]\(([^)\n]{1,1000})\)"#)

    public static func images(in text: NSString, range: NSRange) -> [Image] {
        let block = text.substring(with: range)
        return image.matches(in: block, range: NSRange(location: 0, length: (block as NSString).length)).map {
            Image(range: NSRange(location: $0.range.location + range.location, length: $0.range.length),
                  source: (block as NSString).substring(with: $0.range(at: 1)))
        }
    }

    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tif", "tiff", "heic"]
    public static let maxImageBytes = 50 << 20

    /// The image file for a Markdown image destination: relative paths only, resolved (symlinks too) inside
    /// `folder`, a regular image file of bounded size. URLs, absolute paths and anything escaping the folder: nil.
    public static func resolveImage(_ source: String, in folder: URL?) -> URL? {
        guard let folder else { return nil }
        var s = source.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("<"), let close = s.firstIndex(of: ">") { s = String(s[s.index(after: s.startIndex)..<close]) }
        else { s = String(s.prefix { !$0.isWhitespace }) }
        guard !s.isEmpty, !s.hasPrefix("/"), !s.hasPrefix("~"), !s.contains("\\"), !s.contains("?"), !s.contains("#") else { return nil }
        if let colon = s.firstIndex(of: ":"), !s[..<colon].contains("/") { return nil } // a scheme
        let path = s.removingPercentEncoding ?? s
        guard imageExtensions.contains((path as NSString).pathExtension.lowercased()) else { return nil }
        let root = folder.resolvingSymlinksInPath().standardizedFileURL
        let file = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(root.path + "/"),
              let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, (values.fileSize ?? .max) <= maxImageBytes else { return nil }
        return file
    }

    /// Decodes a downsampled copy (at most `maxPixels` on the long side); natural size is the pixel size in points, like Read.
    /// Largest source image decoded, in pixels (~100 MP): the header is read first, so a small file declaring
    /// huge dimensions is refused before any decode.
    public static let maxSourcePixels = 100_000_000

    /// Cache key for a resolved image: path, modification time and size, so an edit on disk reloads it.
    public static func imageKey(_ url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let date = values.contentModificationDate, let size = values.fileSize else { return nil }
        return "G:\(url.path)|\(date.timeIntervalSinceReferenceDate)|\(size)"
    }

    /// A decoded, downsampled image: immutable and Sendable, so it can leave the decoding task.
    struct Decoded: Sendable {
        let image: CGImage
        /// Natural size in points (the source's pixel size, oriented).
        let size: NSSize
        /// Wrapped for drawing, on the main actor where the objects use it.
        @MainActor var rendered: MarkdownRendered { Self.wrap(self) }
        static func wrap(_ d: Decoded) -> MarkdownRendered {
            let wrapped = NSImage(size: d.size)
            wrapped.addRepresentation(NSBitmapImageRep(cgImage: d.image))
            return MarkdownRendered(image: wrapped, size: d.size)
        }
    }

    public static func loadImage(_ url: URL, maxPixels: Int, maxSourcePixels: Int = maxSourcePixels) -> MarkdownRendered? {
        decodeImage(url, maxPixels: maxPixels, maxSourcePixels: maxSourcePixels).map(Decoded.wrap)
    }

    /// Reads the header first (refusing more than `maxSourcePixels`), then decodes at most `maxPixels` on the long side.
    static func decodeImage(_ url: URL, maxPixels: Int, maxSourcePixels: Int = maxSourcePixels) -> Decoded? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              var w = props[kCGImagePropertyPixelWidth] as? Int, var h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0, Double(w) * Double(h) <= Double(maxSourcePixels) else { return nil }
        if let orientation = props[kCGImagePropertyOrientation] as? Int, orientation >= 5 { swap(&w, &h) }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceShouldCacheImmediately: true,
                                        kCGImageSourceThumbnailMaxPixelSize: min(max(w, h), max(maxPixels, 1))]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return Decoded(image: thumb, size: NSSize(width: w, height: h))
    }
}
