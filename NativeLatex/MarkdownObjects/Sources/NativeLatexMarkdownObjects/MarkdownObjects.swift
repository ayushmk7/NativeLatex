import AppKit
import ImageIO

public extension NSAttributedString.Key {
    /// On the first character of a span drawn as an object (table edge/rule, image): a `MarkdownObjectBox`.
    static let markdownObject = NSAttributedString.Key("LibreWeaveMarkdownObject")
    /// Characters of an object span (and table cell padding) drawn as nothing.
    static let markdownObjectHidden = NSAttributedString.Key("LibreWeaveMarkdownObjectHidden")
    /// Cache key of an image span, rendered or not, so a finished render finds its spans.
    static let markdownObjectSource = NSAttributedString.Key("LibreWeaveMarkdownObjectSource")
}

/// The Write view's markup key (`MarkdownStyler`'s `.markdownHidden`); this layout manager hides it too.
let writerHiddenKey = NSAttributedString.Key("LibreWeaveMarkdownHidden")

nonisolated(unsafe) private var ownerKey: UInt8 = 0

/// What an object glyph draws.
public final class MarkdownObjectBox: NSObject {
    enum Content {
        /// A table separator: whitespace up to `edge` (x in the line), with a hairline `pad` before it (the column start less the cell padding).
        case edge(CGFloat, row: TableRow?)
        /// The delimiter row: a horizontal rule `width` wide.
        case rule(CGFloat, row: TableRow)
        /// A local image.
        case image(NSImage, size: NSSize)
    }
    let content: Content
    init(_ content: Content) { self.content = content }
}

/// One table row's grid, like Read's `th, td { border: 1px solid var(--line) }` and shaded `th`: column
/// boundaries in glyph-position x (the same space as edges), drawn from the row's first separator glyph.
struct TableRow {
    let bounds: [CGFloat]
    /// Header and delimiter rows: the header shade.
    let shaded: Bool
    /// A line along the top (every row but the delimiter) / bottom (the last row).
    let top: Bool, bottom: Bool
}

/// A finished render.
public struct MarkdownRendered {
    public let image: NSImage
    /// Natural size in points; images are scaled down to the column when shown.
    public let size: NSSize
    public init(image: NSImage, size: NSSize) { self.image = image; self.size = size }
}

/// Presents pipe tables and local images in a Markdown Write view without changing a character:
/// objects are attributes plus glyph tricks (a control glyph sized to the object, the rest null glyphs), so
/// saving, copying, undo and the caret all work on the Markdown source. A span on the caret's line shows its
/// source so it can be edited; anything that can't be rendered (outside the folder, too wide) stays as
/// the Write view styled it. Math is never run through TeX here: it stays source (Read renders it with
/// Pandoc MathML). Runs after each restyle via the text storage delegate.
@MainActor
public final class MarkdownObjects: NSObject, NSTextStorageDelegate {
    public private(set) weak var view: NSTextView?
    /// Images resolve only inside this folder (the document's).
    public private(set) var folder: URL?
    /// The caret's lines, whose objects show their source. Defaults to the caret line while the view has focus.
    public var revealRange: () -> NSRange? = { nil }

    private(set) var cache: [String: MarkdownRendered?] = [:]
    private var queuedImages: [String: URL] = [:]
    private var flushScheduled = false
    private var inFlight = Set<String>()
    private var ownEdit = false
    /// Body font and colour for table cells. A text view's `font`/`textColor` are its first character's, which
    /// is a heading or quote in many documents, so the host passes its body style.
    private var bodyFont = NSFont.systemFont(ofSize: 15)
    private var bodyColor: NSColor?

    static let maxBlockLines = 400, maxTableRows = 300, maxTableColumns = 40, maxImageHeight: CGFloat = 800
    static let cellPad: CGFloat = 9

    /// Starts presenting objects in `view` (once per view; again just updates the folder). The view's own layout
    /// manager and delegate stay in charge: its delegate must call `glyphProperty`, `controlCharacterAction` and
    /// `boundingBox`, and its layout manager `draw`. Until the delegate sizes control glyphs (implements
    /// `layoutManager(_:boundingBoxForControlGlyphAt:…)`) this does nothing, so the text stays as it is.
    @discardableResult
    public static func attach(to view: NSTextView?, folder: URL?, bodyFont: NSFont? = nil, bodyColor: NSColor? = nil) -> MarkdownObjects? {
        guard let view, let storage = view.textStorage,
              let delegate = view.layoutManager?.delegate,
              delegate.responds(to: #selector(NSLayoutManagerDelegate.layoutManager(_:boundingBoxForControlGlyphAt:for:proposedLineFragment:glyphPosition:characterIndex:)))
        else { return nil }
        if let existing = storage.delegate as? MarkdownObjects {
            if existing.folder != folder { existing.folder = folder; existing.cache = [:]; existing.latestKey = [:]; existing.reprocess(nil) }
            return existing
        }
        let objects = MarkdownObjects()
        objects.view = view
        objects.folder = folder
        objects.bodyFont = bodyFont ?? view.font ?? objects.bodyFont
        objects.bodyColor = bodyColor
        objects.revealRange = { [weak view] in
            guard let view, view.window?.firstResponder === view else { return nil }
            return (view.string as NSString).lineRange(for: view.selectedRange())
        }
        guard storage.delegate == nil else { return nil } // ponytail: sole storage delegate; chain if the writer needs one
        storage.delegate = objects
        // The storage's delegate is weak and callers (the Write view's `.task`) drop the result: the storage keeps it.
        objc_setAssociatedObject(storage, &ownerKey, objects, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objects.installRotors(on: view)
        objects.reprocess(nil)
        return objects
    }

    // MARK: Processing

    public nonisolated func textStorage(_ storage: NSTextStorage, willProcessEditing mask: NSTextStorageEditActions,
                                        range: NSRange, changeInLength delta: Int) {
        MainActor.assumeIsolated {
            // Character edits are followed by the Write view's restyle (an attribute edit); objects follow that.
            guard !ownEdit, !mask.contains(.editedCharacters) else { return }
            process(storage, range)
        }
    }

    /// Re-presents `range`'s blocks (all of the text if nil) as an edit of our own.
    func reprocess(_ ranges: [NSRange]?) {
        guard let storage = view?.textStorage else { return }
        ownEdit = true
        storage.beginEditing()
        for range in ranges ?? [NSRange(location: 0, length: storage.length)] { process(storage, range) }
        storage.endEditing()
        ownEdit = false
    }

    /// Expands `range` to whole blocks (runs of non-blank lines), bounded so a huge block stays cheap.
    static func block(_ text: NSString, around range: NSRange) -> NSRange {
        let all = NSRange(location: 0, length: text.length)
        var start = text.lineRange(for: NSRange(location: min(range.location, text.length), length: 0)).location
        var end = NSMaxRange(text.lineRange(for: NSRange(location: min(NSMaxRange(range), text.length), length: 0)))
        func blank(_ line: NSRange) -> Bool { text.substring(with: line).allSatisfy(\.isWhitespace) }
        var n = 0
        while start > 0, n < maxBlockLines {
            let line = text.lineRange(for: NSRange(location: start - 1, length: 0))
            if blank(line) { break }
            start = line.location; n += 1
        }
        n = 0
        while end < text.length, n < maxBlockLines {
            let line = text.lineRange(for: NSRange(location: end, length: 0))
            if blank(line) { break }
            end = NSMaxRange(line); n += 1
        }
        return NSIntersectionRange(NSRange(location: start, length: end - start), all)
    }

    func process(_ storage: NSTextStorage, _ edited: NSRange) {
        let text = storage.mutableString
        guard text.length > 0 else { return }
        let target = Self.block(text, around: edited)
        guard target.length > 0 else { return }
        // Removing is a storage mutation (~2 ms each at 1 MiB); skip keys the block doesn't have.
        for key in [NSAttributedString.Key.markdownObject, .markdownObjectHidden, .markdownObjectSource] {
            var present = false
            storage.enumerateAttribute(key, in: target) { value, _, stop in if value != nil { present = true; stop.pointee = true } }
            if present { storage.removeAttribute(key, range: target) }
        }
        let reveal = revealRange()
        func revealed(_ r: NSRange) -> Bool {
            guard let reveal else { return false }
            return NSIntersectionRange(r, reveal).length > 0 || NSLocationInRange(reveal.location, r) || reveal.location == NSMaxRange(r)
        }
        var taken = IndexSet()
        for table in MarkdownSyntax.tables(in: text, range: target) where !isCode(storage, table.rows[0].line) {
            taken.insert(integersIn: table.range.location..<NSMaxRange(table.range))
            layOut(table, in: storage, revealed: revealed)
        }
        func free(_ r: NSRange) -> Bool {
            !taken.intersects(integersIn: r.location..<NSMaxRange(r)) && !isCode(storage, r)
        }
        for span in MarkdownSyntax.images(in: text, range: target) where free(span.range) {
            guard let url = MarkdownSyntax.resolveImage(span.source, in: folder), let key = MarkdownSyntax.imageKey(url) else { continue }
            storage.addAttribute(.markdownObjectSource, value: key, range: span.range)
            request(key)
            guard !revealed(span.range) else { continue }
            if let cached = cache[key] {
                if let cached { place(cached, span.range, in: storage) }
            } else if !inFlight.contains(key) {
                queuedImages[key] = url
                scheduleFlush()
            }
        }
    }

    private func isCode(_ storage: NSTextStorage, _ range: NSRange) -> Bool {
        var code = false
        storage.enumerateAttribute(.backgroundColor, in: range) { value, _, stop in if value != nil { code = true; stop.pointee = true } }
        return code
    }

    private var availableWidth: CGFloat {
        guard let container = view?.textContainer else { return 600 }
        return max(100, container.size.width - 2 * container.lineFragmentPadding)
    }

    /// Draws `rendered` in place of `range`, scaled to the column; tall objects make their line taller.
    private func place(_ rendered: MarkdownRendered, _ range: NSRange, in storage: NSTextStorage) {
        var size = rendered.size
        let scale = min(1, availableWidth / max(size.width, 1), Self.maxImageHeight / max(size.height, 1))
        size = NSSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let box = MarkdownObjectBox(.image(rendered.image, size: size))
        storage.addAttribute(.markdownObject, value: box, range: NSRange(location: range.location, length: 1))
        if range.length > 1 { storage.addAttribute(.markdownObjectHidden, value: true, range: NSRange(location: range.location + 1, length: range.length - 1)) }
        let text = storage.mutableString
        let paragraph = text.paragraphRange(for: NSRange(location: range.location, length: 0))
        let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? bodyFont
        let style = (storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle ?? .default).mutableCopy() as! NSMutableParagraphStyle
        // The image sits on the baseline; the line is tall enough for it plus the font's descender.
        let needed = (size.height + abs(font.descender)).rounded(.up)
        if needed > style.minimumLineHeight { style.minimumLineHeight = needed }
        if style.maximumLineHeight > 0, style.maximumLineHeight < needed { style.maximumLineHeight = needed }
        storage.addAttribute(.paragraphStyle, value: style, range: paragraph)
    }

    private func layOut(_ table: MarkdownSyntax.Table, in storage: NSTextStorage, revealed: (NSRange) -> Bool) {
        let n = table.alignments.count
        guard n > 0, n <= Self.maxTableColumns, table.rows.count <= Self.maxTableRows else { return }
        let fg = bodyColor ?? view?.textColor ?? .textColor
        let bold = NSFontManager.shared.convert(bodyFont, toHaveTrait: .boldFontMask)
        // Cells in the body font (the Write view shows pipe-table lines as literal mono); code spans keep theirs.
        for (index, row) in table.rows.enumerated() where index != 1 {
            for cell in row.cells where cell.length > 0 {
                storage.enumerateAttribute(.backgroundColor, in: cell) { value, sub, _ in
                    guard value == nil else { return }
                    storage.addAttributes([.font: index == 0 ? bold : bodyFont, .foregroundColor: fg], range: sub)
                }
            }
        }
        var widths = [CGFloat](repeating: 0, count: n)
        var cellWidths: [[CGFloat]] = []
        for (index, row) in table.rows.enumerated() {
            let w = row.cells.map { index == 1 ? 0 : Self.visibleWidth(storage, $0) }
            cellWidths.append(w)
            for (c, width) in w.enumerated() where c < n { widths[c] = max(widths[c], width) }
        }
        let pad = Self.cellPad
        var starts = [CGFloat](repeating: 0, count: n)
        var x = table.leadingPipe ? pad : 0
        for c in 0..<n { starts[c] = x; x += widths[c] + 2 * pad }
        let total = x - pad
        guard total <= availableWidth else { return } // too wide: stays literal
        let bounds = [starts[0] - pad] + (1..<n).map { starts[$0] - pad } + [starts[n - 1] + widths[n - 1] + pad]
        func frame(_ index: Int) -> TableRow {
            TableRow(bounds: bounds, shaded: index < 2, top: index != 1, bottom: index == table.rows.count - 1)
        }
        for (index, row) in table.rows.enumerated() {
            if index == 1 {
                guard !revealed(row.line) else { continue }
                storage.addAttribute(.markdownObject, value: MarkdownObjectBox(.rule(total, row: frame(index))), range: NSRange(location: row.line.location, length: 1))
                if row.line.length > 1 { storage.addAttribute(.markdownObjectHidden, value: true, range: NSRange(location: row.line.location + 1, length: row.line.length - 1)) }
                let style = NSMutableParagraphStyle(); style.minimumLineHeight = 5; style.maximumLineHeight = 5
                storage.addAttribute(.paragraphStyle, value: style, range: row.line)
                continue
            }
            for gap in row.padding where gap.length > 0 { storage.addAttribute(.markdownObjectHidden, value: true, range: gap) }
            for (k, pipe) in row.pipes.enumerated() {
                let cell = k + (row.leading ? 0 : 1) // the cell that follows this pipe
                var edge = total
                if cell < n, cell < row.cells.count {
                    let slack = widths[cell] - cellWidths[index][cell]
                    let shift: CGFloat = switch table.alignments[cell] { case .right: slack; case .center: (slack / 2).rounded(); default: 0 }
                    edge = starts[cell] + shift
                }
                storage.addAttribute(.markdownObject, value: MarkdownObjectBox(.edge(edge, row: k == 0 ? frame(index) : nil)),
                                     range: NSRange(location: pipe, length: 1))
            }
        }
    }

    /// Width of `range` as drawn: hidden markup excluded.
    static func visibleWidth(_ storage: NSTextStorage, _ range: NSRange) -> CGFloat {
        let shown = NSMutableAttributedString()
        storage.enumerateAttributes(in: range) { attrs, sub, _ in
            if attrs[writerHiddenKey] == nil, attrs[.markdownObjectHidden] == nil { shown.append(storage.attributedSubstring(from: sub)) }
        }
        // CTLine: NSAttributedString.size() made a typesetter per cell (~0.2 ms each).
        return ceil(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(shown), nil, nil, nil))
    }

    // MARK: Rendering queue

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.flush() }
    }

    /// Images decoded per batch. One batch is in flight at a time and the next starts when it finishes, so a
    /// document with many images holds at most this many decodes before the cache budget sees them.
    static let decodeBatch = 4
    /// Most decodes ever in flight at once (tests).
    private(set) var peakInFlight = 0

    func flush() {
        flushScheduled = false
        guard !queuedImages.isEmpty, inFlight.isEmpty else { return } // a batch in flight schedules the next when done
        let images = Dictionary(uniqueKeysWithValues: queuedImages.prefix(Self.decodeBatch).map { ($0.key, $0.value) })
        for key in images.keys { queuedImages[key] = nil }
        let maxPixels = Int(2 * max(availableWidth, 800))
        inFlight.formUnion(images.keys)
        peakInFlight = max(peakInFlight, inFlight.count)
        Task.detached(priority: .userInitiated) {
            var results: [String: MarkdownRendered?] = [:]
            for (key, url) in images { results[key] = autoreleasepool { MarkdownSyntax.loadImage(url, maxPixels: maxPixels) } }
            let done = results
            await MainActor.run { [weak self] in
                self?.finish(done)
                if self?.queuedImages.isEmpty == false { self?.scheduleFlush() }
            }
        }
    }

    /// Stores results (nil = can't render: stays source) and re-presents the spans that use them.
    func finish(_ results: [String: MarkdownRendered?]) {
        for key in results.keys { inFlight.remove(key) }
        guard let storage = view?.textStorage else { return }
        // Only results a span still uses: drops an older save's decode that finishes after the newer one was
        // requested (it must not evict the new one), and a batch from before a folder change or an edit.
        let used = Self.sourceKeys(storage)
        var fresh: [String: MarkdownRendered?] = [:]
        for (key, value) in results where used.contains(key) {
            if let latest = latestKey[Self.imagePath(ofKey: key)], latest != key { continue }
            fresh[key] = value
        }
        for (key, value) in fresh {
            guard let value else { cache[key] = .some(nil); continue }
            if decodedBytes + Self.bytes(value) > decodedByteLimit {
                // Over budget: first drop decodes no span uses any more (removed or re-saved images).
                for (k, v) in cache where v != nil && !used.contains(k) { cache[k] = nil }
            }
            // Past the budget an image stays its Markdown source and is not retried (no re-decode loop) until the
            // document is reopened or its folder changes, which start a fresh budget.
            // shortcut: first ~256 MB of decodes shown, the rest stay source; switch to visible-range loading (decode
            // on screen, drop off screen) when documents with more column-width images than that are common.
            cache[key] = decodedBytes + Self.bytes(value) <= decodedByteLimit ? .some(value) : .some(nil)
        }
        var ranges: [NSRange] = []
        storage.enumerateAttribute(.markdownObjectSource, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if let key = value as? String, fresh[key] != nil { ranges.append(range) }
        }
        if !ranges.isEmpty { reprocess(ranges) }
    }

    /// Decoded images kept at most (~32 column-width photos); the cache holds every image a span shows.
    var decodedByteLimit = 256 << 20
    private var decodedBytes: Int { cache.values.reduce(0) { $0 + ($1.map(Self.bytes) ?? 0) } }
    static func bytes(_ rendered: MarkdownRendered) -> Int {
        rendered.image.representations.reduce(0) { $0 + (($1 as? NSBitmapImageRep).map { $0.bytesPerRow * $0.pixelsHigh } ?? 0) }
    }
    private static func sourceKeys(_ storage: NSTextStorage) -> Set<String> {
        var keys = Set<String>()
        storage.enumerateAttribute(.markdownObjectSource, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if let key = value as? String { keys.insert(key) }
        }
        return keys
    }

    /// The newest key requested per image path. A key is path|mtime|size, so a re-saved image gets a new one;
    /// its old decode (~8 MB) is dropped instead of kept beside the new one.
    private var latestKey: [String: String] = [:]

    func request(_ key: String) {
        let path = Self.imagePath(ofKey: key)
        guard latestKey[path] != key else { return }
        if let old = latestKey[path] { cache[old] = nil }
        latestKey[path] = key
    }

    /// `imageKey`'s path part: everything before its last two `|` fields (a path may itself contain `|`).
    static func imagePath(ofKey key: String) -> String {
        key.split(separator: "|", omittingEmptySubsequences: false).dropLast(2).joined(separator: "|")
    }

    /// Decoded images held (tests).
    var cachedImageCount: Int { cache.values.filter { $0 != nil }.count }

    /// Test hook: a result as if a render had finished.
    public func prime(_ key: String, _ rendered: MarkdownRendered?) { cache[key] = .some(rendered) }
    /// Whether any render is queued or running.
    public var isRendering: Bool { flushScheduled || !inFlight.isEmpty || !queuedImages.isEmpty }

    // MARK: Glyphs (called from the host's layout manager delegate)

    /// The glyph property for `index`: a control glyph for an object, null for its hidden rest; nil when not ours.
    public nonisolated static func glyphProperty(at index: Int, in storage: NSAttributedString,
                                                 proposed: NSLayoutManager.GlyphProperty) -> NSLayoutManager.GlyphProperty? {
        guard index < storage.length else { return nil }
        if storage.attribute(.markdownObject, at: index, effectiveRange: nil) != nil { return .controlCharacter }
        if storage.attribute(.markdownObjectHidden, at: index, effectiveRange: nil) != nil { return proposed.union(.null) }
        return nil
    }

    /// `.whitespace` for an object's control glyph (so it takes `boundingBox`'s width); nil when not ours.
    public nonisolated static func controlCharacterAction(at index: Int, in storage: NSAttributedString) -> NSLayoutManager.ControlCharacterAction? {
        index < storage.length && storage.attribute(.markdownObject, at: index, effectiveRange: nil) != nil ? .whitespace : nil
    }

    /// The box an object's control glyph occupies; nil when not ours.
    public nonisolated static func boundingBox(at index: Int, in storage: NSAttributedString, glyphPosition position: NSPoint) -> NSRect? {
        guard index < storage.length, let box = storage.attribute(.markdownObject, at: index, effectiveRange: nil) as? MarkdownObjectBox else { return nil }
        let width: CGFloat = switch box.content {
        case let .edge(edge, _): max(2, edge - position.x)
        case let .rule(width, _): width
        case let .image(_, size): size.width
        }
        return NSRect(x: position.x, y: 0, width: width, height: 1)
    }
}

public extension MarkdownObjects {
    /// Draws the objects in `glyphs`; call from the host layout manager's `drawGlyphs` after `super`.
    nonisolated static func draw(_ manager: NSLayoutManager, glyphRange glyphs: NSRange, at origin: NSPoint) {
        manager.drawObjects(glyphs, origin)
    }
}

extension NSLayoutManager {
    /// Read's colours: `--line` rgba(0,0,0,.12) / rgba(255,255,255,.16), `th` background `--code` #F5F5F7 / #141416.
    fileprivate func drawGrid(_ row: TableRow, line: NSRect, offset: CGFloat) {
        guard let left = row.bounds.first, let right = row.bounds.last else { return }
        let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let x0 = (offset + left).rounded(), x1 = (offset + right).rounded()
        if row.shaded {
            // Drawn after the text, so blended: darken (light) / lighten (dark) tints the background and leaves the
            // text's own colour exactly as it was, like a background behind it.
            (dark ? NSColor(srgbRed: 0x14 / 255, green: 0x14 / 255, blue: 0x16 / 255, alpha: 1)
                  : NSColor(srgbRed: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF7 / 255, alpha: 1)).setFill()
            NSRect(x: x0, y: line.minY.rounded(), width: x1 - x0, height: line.maxY.rounded() - line.minY.rounded()).fill(using: dark ? .lighten : .darken)
        }
        (dark ? NSColor(white: 1, alpha: 0.16) : NSColor(white: 0, alpha: 0.12)).setFill()
        // Whole-point rects: crisp at 1x and 2x. Verticals stop short of the top line so corners aren't drawn twice.
        let top = line.minY.rounded(), bottom = line.maxY.rounded()
        for b in row.bounds { NSRect(x: (offset + b).rounded(), y: top + (row.top ? 1 : 0), width: 1, height: bottom - top - (row.top ? 1 : 0)).fill(using: .sourceOver) }
        if row.top { NSRect(x: x0, y: top, width: x1 - x0 + 1, height: 1).fill(using: .sourceOver) }
        if row.bottom { NSRect(x: x0, y: bottom, width: x1 - x0 + 1, height: 1).fill(using: .sourceOver) }
    }

    fileprivate func drawObjects(_ glyphs: NSRange, _ origin: NSPoint) {
        guard let storage = textStorage else { return }
        let chars = characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        storage.enumerateAttribute(.markdownObject, in: chars) { value, range, _ in
            guard let box = value as? MarkdownObjectBox else { return }
            let glyph = glyphIndexForCharacter(at: range.location)
            guard NSLocationInRange(glyph, glyphs), let container = textContainer(forGlyphAt: glyph, effectiveRange: nil) else { return }
            let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).offsetBy(dx: origin.x, dy: origin.y)
            let cell = boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).offsetBy(dx: origin.x, dy: origin.y)
            let baseline = line.minY + location(forGlyphAt: glyph).y
            switch box.content {
            case let .edge(edge, row):
                // The edge glyph ends at `edge`, which maps position x to view x.
                if let row { drawGrid(row, line: line, offset: cell.maxX - edge) }
            case let .rule(_, row):
                drawGrid(row, line: line, offset: cell.minX)
            case let .image(image, size):
                image.draw(in: NSRect(x: cell.minX, y: baseline - size.height, width: size.width, height: size.height),
                           from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
        }
    }
}

// MARK: VoiceOver

/// The Write view's accessible text stays the Markdown source, so VoiceOver edits, selects and reads exactly what
/// is saved. Objects drawn over that source are announced through two rotors instead: Images (alt text, or the
/// file name when there is none) and Tables (size and header cells). Choosing an item selects its source span.
/// The rotors hold this object weakly; the text storage keeps it alive.
extension MarkdownObjects: NSAccessibilityCustomRotorItemSearchDelegate {
    static let imagesRotor = "Images", tablesRotor = "Tables"

    func installRotors(on view: NSTextView) {
        let mine = [Self.imagesRotor, Self.tablesRotor]
        let others = view.accessibilityCustomRotors().filter { !mine.contains($0.label) }
        view.setAccessibilityCustomRotors(others + mine.map { NSAccessibilityCustomRotor(label: $0, itemSearchDelegate: self) })
    }

    /// A rotor's items in document order, skipping code (where nothing is drawn as an object).
    func rotorItems(_ rotor: String) -> [(range: NSRange, label: String)] {
        guard let storage = view?.textStorage, storage.length > 0 else { return [] }
        let text = storage.mutableString, all = NSRange(location: 0, length: storage.length)
        if rotor == Self.imagesRotor {
            return MarkdownSyntax.images(in: text, range: all).filter { !isCode(storage, $0.range) }.map { ($0.range, Self.imageLabel(text, $0)) }
        }
        return MarkdownSyntax.tables(in: text, range: all).filter { !isCode(storage, $0.rows[0].line) }.map { ($0.range, Self.tableLabel(text, $0)) }
    }

    static func imageLabel(_ text: NSString, _ image: MarkdownSyntax.Image) -> String {
        let span = text.substring(with: image.range) as NSString
        let close = span.range(of: "](") // alt text can't contain "]"
        let alt = close.location == NSNotFound ? "" : span.substring(with: NSRange(location: 2, length: close.location - 2)).trimmingCharacters(in: .whitespaces)
        if !alt.isEmpty { return "Image, \(alt)" }
        var source = image.source.trimmingCharacters(in: .whitespaces)
        if source.hasPrefix("<"), let end = source.firstIndex(of: ">") { source = String(source[source.index(after: source.startIndex)..<end]) }
        else { source = String(source.prefix { !$0.isWhitespace }) }
        let name = (source as NSString).lastPathComponent
        return "Image, no description, \(name.removingPercentEncoding ?? name)"
    }

    static func tableLabel(_ text: NSString, _ table: MarkdownSyntax.Table) -> String {
        let header = table.rows[0].cells.map { text.substring(with: $0) }.joined(separator: ", ")
        let rows = table.rows.count - 2
        return "Table, \(table.alignments.count) columns, \(rows) \(rows == 1 ? "row" : "rows"): \(header)"
    }

    public nonisolated func rotor(_ rotor: NSAccessibilityCustomRotor,
                                  resultFor search: NSAccessibilityCustomRotor.SearchParameters) -> NSAccessibilityCustomRotor.ItemResult? {
        MainActor.assumeIsolated {
            guard let view else { return nil }
            var items = rotorItems(rotor.label)
            if !search.filterString.isEmpty { items = items.filter { $0.label.localizedCaseInsensitiveContains(search.filterString) } }
            let current = search.currentItem?.targetRange.location
            let item = search.searchDirection == .previous
                ? (current.map { c in items.last { $0.range.location < c } } ?? items.last)
                : (current.map { c in items.first { $0.range.location > c } } ?? items.first)
            guard let item else { return nil }
            let result = NSAccessibilityCustomRotor.ItemResult(targetElement: view)
            result.targetRange = item.range
            result.customLabel = item.label
            return result
        }
    }
}
