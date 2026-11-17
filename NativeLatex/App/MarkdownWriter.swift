import AppKit
import NativeLatexDesign
import NativeLatexMarkdownObjects
import SwiftUI

extension NSAttributedString.Key {
    /// Markup characters drawn as nothing (null glyphs) in the Write view. The text itself is untouched.
    static let markdownHidden = NSAttributedString.Key("LibreWeaveMarkdownHidden")
    /// Block markup kept as (clear) glyphs and drawn over by `MarkdownLayoutManager` (bullets, task boxes,
    /// rules). The caret treats it like hidden markup: one stop after it, Delete removes it whole.
    static let markdownAtomic = NSAttributedString.Key("LibreWeaveMarkdownAtomic")
    /// A fenced code block (fence lines included): `MarkdownLayoutManager` draws Read's rounded `pre` box behind it.
    static let markdownCodeBlock = NSAttributedString.Key("LibreWeaveMarkdownCodeBlock")
    /// What `MarkdownLayoutManager` draws for a range: a `MarkdownDecoration` raw value.
    static let markdownDecoration = NSAttributedString.Key("LibreWeaveMarkdownDecoration")
    /// Quote depth of a line (Int): that many accent bars at its left edge.
    static let markdownQuote = NSAttributedString.Key("LibreWeaveMarkdownQuote")
}

/// Block visuals Write draws where Read's CSS would: list bullets (disc, circle, square by depth), task
/// boxes and thematic rules.
enum MarkdownDecoration: String {
    case disc, circle, square, task, taskDone, rule
}

/// Draws quote bars and `MarkdownDecoration`s behind the text. Only drawing: glyphs, layout, selection
/// and the text itself are the standard TextKit ones.
final class MarkdownLayoutManager: NSLayoutManager {
    /// Read: `blockquote { border-left: 3px; padding-left: 1em }`, so each level indents 18 pt.
    static let quoteIndent: CGFloat = 18, quoteBar: CGFloat = 3

    /// Table rules and local images (`MarkdownObjects`) over the text.
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        MarkdownObjects.draw(self, glyphRange: glyphsToShow, at: origin)
    }

    /// Read: `pre { background: var(--code); border-radius: 4px; padding: 12px }`.
    static let codeRadius: CGFloat = 4, codePadding: CGFloat = 12

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage, let container = textContainers.first else {
            return super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        }
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        // Code boxes first, so the selection highlight (drawn by super) stays visible on top.
        NSColor(Theme.surface).setFill()
        storage.enumerateAttribute(.markdownCodeBlock, in: chars) { value, run, _ in
            guard value != nil else { return }
            var block = NSRange()
            _ = storage.attribute(.markdownCodeBlock, at: run.location, longestEffectiveRange: &block, in: NSRange(location: 0, length: storage.length))
            let glyphs = glyphRange(forCharacterRange: block, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            // Lay out what this pass draws, through the block: an image or table above it on screen can have grown
            // (MarkdownObjects attaching, an image decoding) since the last layout, and non-contiguous layout would
            // hand back the old fragments, painting the box that much above its code. Growth above the viewport
            // needs nothing (the view re-lays out before drawing). Laying out from glyph 0 also works but cost
            // 836 ms on a 1 MiB first draw; this costs ~2 ms.
            ensureLayout(forGlyphRange: NSUnionRange(glyphsToShow, glyphs))
            let top = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let bottom = lineFragmentRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil)
            let padding = container.lineFragmentPadding
            let box = NSRect(x: origin.x + top.minX + padding, y: origin.y + top.minY,
                             width: top.width - 2 * padding, height: bottom.maxY - top.minY)
            NSBezierPath(roundedRect: box, xRadius: Self.codeRadius, yRadius: Self.codeRadius).fill()
        }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        let accent = NSColor(Theme.accent), secondary = NSColor(Theme.secondary), line = NSColor(Theme.line)
        let padding = container.lineFragmentPadding
        storage.enumerateAttribute(.markdownQuote, in: chars) { value, range, _ in
            guard let depth = value as? Int else { return }
            accent.setFill()
            enumerateLineFragments(forGlyphRange: glyphRange(forCharacterRange: range, actualCharacterRange: nil)) { rect, _, _, _, _ in
                for level in 0..<depth {
                    NSRect(x: origin.x + rect.minX + padding + CGFloat(level) * Self.quoteIndent, y: origin.y + rect.minY,
                           width: Self.quoteBar, height: rect.height).fill()
                }
            }
        }
        storage.enumerateAttribute(.markdownDecoration, in: chars) { value, range, _ in
            guard let raw = value as? String, let decoration = MarkdownDecoration(rawValue: raw) else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            let fragment = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let baseline = origin.y + fragment.minY + location(forGlyphAt: glyphs.location).y
            let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: MarkdownStyler.bodySize)
            let box = boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: origin.x, dy: origin.y)
            switch decoration {
            case .rule:
                line.setFill()
                NSRect(x: origin.x + fragment.minX + padding, y: (origin.y + fragment.minY + font.ascender - font.descender).rounded() - 0.5,
                       width: fragment.width - 2 * padding, height: 1).fill()
            case .disc, .circle, .square:
                let d: CGFloat = 5.5
                let dot = NSRect(x: box.midX - d / 2, y: baseline - font.xHeight / 2 - d / 2, width: d, height: d)
                (storage.attribute(.markdownQuote, at: range.location, effectiveRange: nil) == nil ? NSColor(Theme.foreground) : secondary).set()
                switch decoration {
                case .disc: NSBezierPath(ovalIn: dot).fill()
                case .circle: let p = NSBezierPath(ovalIn: dot.insetBy(dx: 0.5, dy: 0.5)); p.lineWidth = 1; p.stroke()
                default: dot.insetBy(dx: 0.25, dy: 0.25).fill()
                }
            case .task, .taskDone:
                let side: CGFloat = 13
                let square = NSRect(x: box.midX - side / 2, y: baseline - font.capHeight / 2 - side / 2, width: side, height: side)
                let path = NSBezierPath(roundedRect: square.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
                if decoration == .taskDone {
                    accent.setFill(); path.fill()
                    let check = NSBezierPath()
                    check.move(to: NSPoint(x: square.minX + 3.2, y: square.midY))
                    check.line(to: NSPoint(x: square.minX + 5.6, y: square.maxY - 3.4)) // flipped view: maxY is the bottom
                    check.line(to: NSPoint(x: square.maxX - 3, y: square.minY + 3.4))
                    check.lineWidth = 1.8; check.lineCapStyle = .round; check.lineJoinStyle = .round
                    NSColor.white.setStroke(); check.stroke()
                } else {
                    secondary.setStroke(); path.lineWidth = 1; path.stroke()
                }
            }
        }
    }
}

/// Styles Markdown source so it reads like the rendered document: headings, emphasis, code, links,
/// quotes and lists are formatted and their markup is hidden, on the caret's line too, so moving the caret
/// never changes a line's width. Sizes and spacing are the Read stylesheet's (`MarkdownRenderer.css`).
/// Only attributes change; the characters (and so the saved Markdown) are exactly what the user typed.
/// Tables, math, images, HTML and front matter stay visible as Markdown in a quiet monospaced style.
enum MarkdownStyler {
    static let bodySize: CGFloat = 15
    /// h1–h6 in points; Read's stylesheet uses the same values in px.
    static let headingSizes: [CGFloat] = [30, 22.5, 18.75, 15, 13, 12]
    /// Read: `line-height: 1.55`, blocks `margin: blockGap`, headings `margin-top: 1.4em`, `line-height: 1.25`.
    static let lineHeight: CGFloat = 1.55, headingLineHeight: CGFloat = 1.25, headingSpaceBefore: CGFloat = 1.4
    /// Read's `main { max-width: 46em }` at the 15 px body size.
    static let columnWidth: CGFloat = 46 * bodySize
    /// Font and paragraph style per heading level, made once (measuring line height costs a layout manager).
    nonisolated(unsafe) static let headingStyles: [[NSAttributedString.Key: Any]] = headingSizes.map { size in
        let font = NSFont.systemFont(ofSize: size, weight: .bold)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing(font, multiple: headingLineHeight)
        // Read's 1.4em margin above (collapsed with the block gap), less the blank line already above it.
        style.paragraphSpacingBefore = max(0, size * headingSpaceBefore - blockGap)
        return [.font: font, .paragraphStyle: style]
    }
    static let bodyLineSpacing = lineSpacing(.systemFont(ofSize: bodySize), multiple: lineHeight)
    /// A blank line is an ordinary body line (so typing on it never changes its height), and it is the gap
    /// between blocks: Read's paragraph, list, quote, code and table margins are this height too.
    static let blockGap = NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: bodySize)) + bodyLineSpacing
    /// Extra space below each line so it is `lineHeight` × the font size tall, like CSS line-height.
    static func lineSpacing(_ font: NSFont, multiple: CGFloat) -> CGFloat {
        max(0, (font.pointSize * multiple - NSLayoutManager().defaultLineHeight(for: font)).rounded())
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }
    private static let heading = regex(#"^ {0,3}(#{1,6})([ \t]+|$)"#)
    private static let quote = regex(#"^ {0,3}(>[ \t]?)+"#)
    /// Groups: quote prefix, indentation, marker, task box.
    private static let list = regex(#"^((?: {0,3}>[ \t]?)*)([ \t]*)([-*+]|\d{1,9}[.)])[ \t]+(\[[ xX]\][ \t]+)?"#)
    private static let setext = regex(#"^ {0,3}(=+|-+)[ \t]*$"#)
    private static let hardBreak = regex(#"(?<!\\)\\$"#)
    private static let rule = regex(#"^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
    private static let literalLine = regex(#"^ {0,3}(\||\$\$|<|\+\+\+).*$"#)
    /// Longest inline span (emphasis, link, image, math) the Write view styles, in UTF-16 units. Unbounded
    /// lazy spans made a long line of unmatched markers quadratic: a 24 KB line of `*a ` cost seconds per
    /// keystroke. Bounded, each marker scans at most this far, so styling stays linear in the line length.
    static let maxInlineSpan = 300
    /// One line only, like the other inline spans: a span across lines styled differently when the Write view
    /// restyled just the edited line than on a full restyle (and a stray backtick could turn paragraphs into code).
    private static let code = regex(#"(`+)(?!`)([^\n]{0,\#(maxInlineSpan)}?[^`\n])\1(?!`)"#)
    private static let strong = regex(#"(\*\*|__)(?=\S)([^\n]{0,\#(maxInlineSpan)}?\S)\1"#)
    private static let emphasis = regex(#"(?<![*_\w])([*_])(?=[^\s*_])([^\n]{0,\#(maxInlineSpan)}?[^\s\\])\1(?![*_\w])"#)
    private static let strike = regex(#"(~~)(?=\S)([^\n]{0,\#(maxInlineSpan)}?\S)~~"#)
    private static let image = regex(#"!\[[^\]\n]{0,\#(maxInlineSpan)}+\]\([^)\n]{0,\#(maxInlineSpan)}+\)"#)
    private static let link = regex(#"(?<!!)(\[)([^\]\n]{1,\#(maxInlineSpan)}+)(\]\([^)\n]{0,\#(maxInlineSpan)}+\))"#)
    private static let math = regex(#"\$[^$\n]{1,\#(maxInlineSpan)}+\$"#)

    /// Fenced code blocks (``` or ~~~, closed by the same fence or the end of the text) and their fence lines.
    static func fences(_ text: NSString) -> [(range: NSRange, markers: [NSRange])] {
        var result: [(NSRange, [NSRange])] = []
        var open: (start: Int, fence: String, line: NSRange)?
        var location = 0
        while location < text.length {
            let line = text.lineRange(for: NSRange(location: location, length: 0))
            let content = text.substring(with: line).trimmingCharacters(in: .newlines)
            let visible = NSRange(location: line.location, length: (content as NSString).length)
            let trimmed = content.drop { $0 == " " }
            if content.count - trimmed.count <= 3, let char = trimmed.first, char == "`" || char == "~" {
                let run = String(trimmed.prefix { $0 == char })
                if run.count >= 3 {
                    if let o = open, run.hasPrefix(o.fence), trimmed.dropFirst(run.count).allSatisfy(\.isWhitespace) {
                        result.append((NSRange(location: o.start, length: NSMaxRange(visible) - o.start), [o.line, visible]))
                        open = nil
                    } else if open == nil {
                        open = (line.location, run, visible)
                    }
                }
            }
            location = NSMaxRange(line)
        }
        if let o = open { result.append((NSRange(location: o.start, length: text.length - o.start), [o.line])) }
        return result
    }

    /// YAML front matter: `---` on the first line through the next line starting `---`.
    static func frontMatter(_ text: NSString) -> NSRange? {
        guard text.hasPrefix("---\n") else { return nil }
        let end = text.range(of: "\n---", options: [], range: NSRange(location: 3, length: text.length - 3))
        return end.location == NSNotFound ? nil : NSRange(location: 0, length: NSMaxRange(end))
    }

    /// Restyles `limit` (whole paragraphs; all of `storage` if nil). Hidden markup stays hidden everywhere;
    /// only fence lines inside `reveal` (the caret's lines) turn from clear to dim, which never moves text. Code fences are found over the whole text, since an opening fence
    /// anywhere above changes what follows; a fence block touching `limit` is restyled whole.
    /// `range` plus the lines around it: a line's look depends on its neighbours (`---` under text is a heading
    /// underline, not a rule; a lazy line continues the quote above), so an edit restyles them too.
    /// Plain paragraph text (could sit above a setext underline): not blank, a heading, quote, list item or fence.
    static func isParagraphText(_ line: String) -> Bool {
        !line.allSatisfy(\.isWhitespace) && line.firstMatch(of: #/^ {0,3}(#|>|```|~~~|[-*+][ \t]|\d{1,9}[.)][ \t])/#) == nil
    }

    /// Width of a task box with its gap, as Read's checkbox CSS: 13 px + `margin-right: .5em`.
    static let taskWidth: CGFloat = 13 + 0.5 * bodySize

    /// Pandoc needs a blank line (or a block boundary) before a list: `- x` right under paragraph text is
    /// more of that paragraph. A marker line starts or continues a list after a blank line, another item,
    /// an indented line (item content), a heading, or at the top. Quote markers are ignored on both lines.
    /// Pandoc starts a new list when the marker kind changes between adjacent items at the same indentation:
    /// `-`, `*`, `+`, or a number with `.` or `)`. Read shows the two lists a block gap apart.
    // ponytail: only the line directly above is compared; an item after a wrapped continuation line gets no gap.
    static func startsNewList(_ m: NSTextCheckingResult, in text: NSString) -> Bool {
        let line = text.lineRange(for: m.range)
        guard line.location > 0 else { return false }
        let above = text.lineRange(for: NSRange(location: line.location - 1, length: 0))
        guard let prev = list.firstMatch(in: text as String, range: above),
              text.substring(with: prev.range(at: 1)) == text.substring(with: m.range(at: 1)),
              text.substring(with: prev.range(at: 2)) == text.substring(with: m.range(at: 2)) else { return false }
        func kind(_ marker: String) -> String { marker.last.map(String.init) ?? "" } // `-`/`*`/`+`, or `.`/`)` after digits
        return kind(text.substring(with: prev.range(at: 3))) != kind(text.substring(with: m.range(at: 3)))
    }

    static func startsList(_ m: NSTextCheckingResult, in text: NSString) -> Bool {
        let line = m.range.location
        guard line > 0 else { return true }
        let previous = text.substring(with: text.lineRange(for: NSRange(location: line - 1, length: 0)))
        let unquoted = m.range(at: 1).length > 0 ? String(previous.trimmingPrefix(#/(?: {0,3}>[ \t]?)*/#)) : previous
        if unquoted.allSatisfy(\.isWhitespace) || unquoted.first == " " || unquoted.first == "\t" { return true }
        return unquoted.firstMatch(of: #/^(?:[-*+]|\d{1,9}[.)])[ \t]|^ {0,3}#{1,6}([ \t]|$)/#) != nil
    }

    /// Lines styled from context (a lazy line continues the quote any number of lines above it; a list needs a
    /// blank line or another item above) depend on their whole block, so an edit restyles out to the blank
    /// lines around it.
    // ponytail: at most `maxBlockLines` each way, so a 1 MiB text without blank lines stays cheap per keystroke;
    // a lazy quote run longer than that can keep stale styling until the next full restyle.
    static let maxBlockLines = 200
    static func block(around range: NSRange, in text: NSString) -> NSRange {
        func blank(_ line: NSRange) -> Bool { text.substring(with: line).allSatisfy(\.isWhitespace) }
        var start = range.location, end = NSMaxRange(range)
        for _ in 0..<maxBlockLines where start > 0 {
            let line = text.lineRange(for: NSRange(location: start - 1, length: 0))
            if blank(line) { break }
            start = line.location
        }
        for _ in 0..<maxBlockLines where end < text.length {
            let line = text.lineRange(for: NSRange(location: end, length: 0))
            if blank(line) { break }
            end = NSMaxRange(line)
        }
        return NSRange(location: start, length: end - start)
    }

    static func withNextLine(_ range: NSRange, in text: NSString) -> NSRange {
        var r = NSMaxRange(range) < text.length ? NSUnionRange(range, text.lineRange(for: NSRange(location: NSMaxRange(range), length: 0))) : range
        // And the line before: a setext underline changes the line above it.
        if r.location > 0 { r = NSUnionRange(r, text.lineRange(for: NSRange(location: r.location - 1, length: 0))) }
        return r
    }

    /// Returns the range actually restyled (whole blocks around `limit`), for the caller to redisplay.
    @discardableResult
    static func apply(to storage: NSTextStorage, reveal: NSRange, in limit: NSRange? = nil, fences known: [(range: NSRange, markers: [NSRange])]? = nil) -> NSRange {
        let text = storage.string as NSString
        let all = NSRange(location: 0, length: text.length)
        let blocks = known ?? fences(text)
        // Clamped, not NSIntersectionRange: that gives {0, 0} for an empty range at the end, which restyled the
        // first line instead of the last after a delete at the end of the text.
        var target = limit.map { r -> NSRange in
            let lo = min(max(0, r.location), text.length), hi = min(max(lo, NSMaxRange(r)), text.length)
            return withNextLine(text.paragraphRange(for: NSRange(location: lo, length: hi - lo)), in: text)
        } ?? all
        for block in blocks where NSIntersectionRange(block.range, target).length > 0 || NSLocationInRange(target.location, block.range) {
            target = NSUnionRange(target, text.paragraphRange(for: block.range))
        }
        if let matter = frontMatter(text), target.location <= NSMaxRange(matter) { target = NSUnionRange(target, text.paragraphRange(for: matter)) }
        if limit != nil { target = block(around: target, in: text) }
        let fg = NSColor(Theme.foreground), secondary = NSColor(Theme.secondary), accent = NSColor(Theme.accentText)
        let body = NSFont.systemFont(ofSize: bodySize)
        let mono = NSFont.monospacedSystemFont(ofSize: bodySize - 2, weight: .regular)
        let codeBackground = NSColor(Theme.surface)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = bodyLineSpacing

        storage.beginEditing()
        defer { storage.endEditing() }
        storage.setAttributes([.font: body, .foregroundColor: fg, .paragraphStyle: paragraph], range: target)
        var protected = IndexSet() // code and literal Markdown: no further styling inside

        func isRevealed(_ range: NSRange) -> Bool {
            NSIntersectionRange(range, reveal).length > 0 || (reveal.length == 0 && NSLocationInRange(reveal.location, NSRange(location: range.location, length: range.length + 1)))
        }
        func hide(_ range: NSRange) {
            guard range.length > 0 else { return }
            storage.addAttribute(.markdownHidden, value: true, range: range)
        }
        /// Line-start markup before indented text: clear glyphs kerned to zero width, not null glyphs. After
        /// leading null glyphs TextKit lays the line out at `headIndent`, ignoring `firstLineHeadIndent`.
        func collapse(_ range: NSRange) {
            storage.addAttributes([.foregroundColor: NSColor.clear, .markdownAtomic: true], range: range)
            for i in range.location..<NSMaxRange(range) {
                let width = (text.substring(with: NSRange(location: i, length: 1)) as NSString).size(withAttributes: [.font: body]).width
                storage.addAttribute(.kern, value: -width, range: NSRange(location: i, length: 1))
            }
        }
        func isProtected(_ range: NSRange) -> Bool { protected.intersects(integersIn: range.location..<NSMaxRange(range)) }
        func protect(_ range: NSRange) { protected.insert(integersIn: range.location..<NSMaxRange(range)) }
        func matches(_ pattern: NSRegularExpression) -> [NSTextCheckingResult] { pattern.matches(in: storage.string, range: target) }
        func addTrait(_ trait: NSFontTraitMask, _ range: NSRange) {
            storage.enumerateAttribute(.font, in: range) { value, sub, _ in
                guard let font = value as? NSFont else { return }
                storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: sub)
            }
        }
        func monoLiteral(_ range: NSRange) {
            storage.addAttributes([.font: mono, .foregroundColor: secondary], range: range)
            protect(range)
        }

        // Read's `pre`: monospaced at normal line height, 12 pt inside a rounded neutral box. The fence lines are that
        // box's top and bottom padding (a fixed 12 pt line), not an extra blank line.
        let fenceFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let codeStyle = NSMutableParagraphStyle(), fenceStyle = NSMutableParagraphStyle()
        codeStyle.firstLineHeadIndent = MarkdownLayoutManager.codePadding; codeStyle.headIndent = MarkdownLayoutManager.codePadding
        codeStyle.tailIndent = -MarkdownLayoutManager.codePadding
        fenceStyle.setParagraphStyle(codeStyle)
        fenceStyle.minimumLineHeight = MarkdownLayoutManager.codePadding; fenceStyle.maximumLineHeight = MarkdownLayoutManager.codePadding
        for block in blocks where NSIntersectionRange(block.range, target).length > 0 {
            storage.addAttributes([.font: mono, .paragraphStyle: codeStyle, .markdownCodeBlock: true], range: block.range)
            for marker in block.markers {
                storage.addAttributes([.font: fenceFont, .paragraphStyle: fenceStyle], range: text.lineRange(for: marker))
            }
            protect(block.range)
            for marker in block.markers {
                if isRevealed(marker) {
                    storage.addAttribute(.foregroundColor, value: secondary, range: marker)
                } else {
                    // Drawn clear rather than removed: the line keeps its exact height, so revealing it when the
                    // caret arrives only changes colour and never shifts the text below.
                    storage.addAttribute(.foregroundColor, value: NSColor.clear, range: marker)
                }
            }
        }
        // Front matter at the very top stays literal.
        if let matter = frontMatter(text), NSIntersectionRange(matter, target).length > 0 { monoLiteral(matter) }
        // Pandoc: a rule needs a blank line (or the top) above it. Under paragraph text, `---` / `===` make that
        // line a setext heading (h2 / h1); `***` or `- - -` there are just more paragraph text.
        for m in matches(setext) where !isProtected(m.range) {
            guard m.range.location > 0 else { continue }
            let previous = text.lineRange(for: NSRange(location: m.range.location - 1, length: 0))
            guard !isProtected(previous), isParagraphText(text.substring(with: previous)) else { continue }
            let level = text.character(at: m.range(at: 1).location) == 0x3D ? 1 : 2
            storage.addAttributes(headingStyles[level - 1], range: previous)
            storage.addAttributes([.foregroundColor: NSColor.clear, .markdownAtomic: true], range: m.range)
            protect(m.range)
        }
        for m in matches(rule) where !isProtected(m.range) {
            let previous = m.range.location > 0 ? text.substring(with: text.lineRange(for: NSRange(location: m.range.location - 1, length: 0))) : ""
            guard previous.allSatisfy(\.isWhitespace) else { continue }
            storage.addAttributes([.foregroundColor: NSColor.clear, .markdownAtomic: true, .markdownDecoration: MarkdownDecoration.rule.rawValue], range: m.range)
            protect(m.range)
        }
        for m in matches(literalLine) where !isProtected(m.range) { monoLiteral(m.range) }

        for m in matches(heading) where !isProtected(m.range) {
            let line = text.lineRange(for: m.range)
            storage.addAttributes(headingStyles[m.range(at: 1).length - 1], range: line)
            hide(m.range)
            storage.addAttribute(.markdownAtomic, value: true, range: m.range) // block marker: caret after it
        }
        for m in matches(quote) where !isProtected(m.range) {
            let line = text.lineRange(for: m.range)
            let depth = text.substring(with: m.range).filter { $0 == ">" }.count
            let indented = paragraph.mutableCopy() as! NSMutableParagraphStyle
            indented.firstLineHeadIndent = CGFloat(depth) * MarkdownLayoutManager.quoteIndent; indented.headIndent = indented.firstLineHeadIndent
            storage.addAttributes([.foregroundColor: secondary, .paragraphStyle: indented], range: line)
            storage.addAttribute(.markdownQuote, value: depth, range: line)
            collapse(m.range)
        }
        // Lazy continuation: a non-blank line right under quoted text is more of that quote in Pandoc, even
        // without `>` (and even `- b`). Lines are walked in order so a run of lazy lines follows the quote.
        var lazy = target.location
        while lazy < NSMaxRange(target) {
            let line = text.lineRange(for: NSRange(location: lazy, length: 0))
            lazy = NSMaxRange(line)
            guard line.location > 0, storage.attribute(.markdownQuote, at: line.location, effectiveRange: nil) == nil, !isProtected(line),
                  let depth = storage.attribute(.markdownQuote, at: line.location - 1, effectiveRange: nil) as? Int else { continue }
            let content = text.substring(with: line)
            let above = text.substring(with: text.lineRange(for: NSRange(location: line.location - 1, length: 0)))
            guard !content.allSatisfy(\.isWhitespace), !above.drop(while: { $0 == ">" || $0 == " " || $0 == "\t" }).allSatisfy(\.isWhitespace),
                  content.firstMatch(of: #/^ {0,3}(#|```|~~~)/#) == nil else { continue }
            let style = storage.attribute(.paragraphStyle, at: line.location - 1, effectiveRange: nil) ?? paragraph
            storage.addAttributes([.foregroundColor: secondary, .paragraphStyle: style, .markdownQuote: depth], range: line)
        }
        // Lists: text starts where Read's starts (40 pt per level; task lists 18 pt, box inline), wrapped lines
        // align under it. Bullets and task boxes are drawn over their clear marker glyphs; numbers stay text.
        for m in matches(list) where !isProtected(NSRange(location: m.range(at: 3).location, length: NSMaxRange(m.range) - m.range(at: 3).location))
            && startsList(m, in: text) {
            let line = text.lineRange(for: m.range)
            let marker = m.range(at: 3), task = m.range(at: 4)
            let atomic = NSRange(location: marker.location, length: NSMaxRange(m.range) - marker.location)
            let indent = text.substring(with: m.range(at: 2)).reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            // ponytail: nesting depth from indentation (2 columns a level), not Pandoc's exact list-item rules.
            let depth = indent / 2
            storage.addAttribute(.markdownAtomic, value: true, range: atomic)
            var visible = text.substring(with: m.range(at: 2))
            if task.location != NSNotFound {
                collapse(NSRange(location: marker.location, length: task.location - marker.location))
                let box = NSRange(location: task.location, length: 3)
                let done = text.character(at: task.location + 1) != 0x20
                storage.addAttributes([.foregroundColor: NSColor.clear, .markdownDecoration: (done ? MarkdownDecoration.taskDone : .task).rawValue], range: box)
                // `[ ]` and `[x]` take Read's checkbox width (13 pt box + .4em margin) whatever their glyphs.
                let natural = (text.substring(with: task) as NSString).size(withAttributes: [.font: body]).width
                storage.addAttribute(.kern, value: taskWidth - natural, range: NSRange(location: task.location + 2, length: 1))
            } else if text.character(at: marker.location) > 0x39 || text.character(at: marker.location) < 0x30 {
                let shape: [MarkdownDecoration] = [.disc, .circle, .square]
                storage.addAttributes([.foregroundColor: NSColor.clear, .markdownDecoration: shape[depth % 3].rawValue], range: marker)
                visible += text.substring(with: NSRange(location: marker.location, length: NSMaxRange(m.range) - marker.location))
            } else {
                visible += text.substring(with: NSRange(location: marker.location, length: NSMaxRange(m.range) - marker.location))
            }
            let quoted = (storage.attribute(.paragraphStyle, at: line.location, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? 0
            let width = (visible as NSString).size(withAttributes: [.font: body]).width
            let style = paragraph.mutableCopy() as! NSMutableParagraphStyle
            if startsNewList(m, in: text) { style.paragraphSpacingBefore = blockGap } // Read: a new <ul>/<ol>, with its margin
            if task.location != NSNotFound {
                // Read: `ul.task-list { padding-left: 1.2em }`, the box inline before the text.
                style.firstLineHeadIndent = max(quoted, quoted + CGFloat(depth + 1) * 18 - width)
                style.headIndent = style.firstLineHeadIndent + width + taskWidth
            } else {
                style.headIndent = quoted + CGFloat(depth + 1) * 40 // Read: `ul, ol { padding-left: 40px }`, marker outside
                style.firstLineHeadIndent = max(quoted, style.headIndent - width)
            }
            storage.addAttribute(.paragraphStyle, value: style, range: line)
            protect(atomic)
        }

        for m in matches(hardBreak) where !isProtected(m.range) { hide(m.range) } // Shift-Return's `\`
        for m in matches(code) where !isProtected(m.range) {
            storage.addAttributes([.font: mono, .backgroundColor: codeBackground], range: m.range(at: 2))
            hide(m.range(at: 1))
            hide(NSRange(location: NSMaxRange(m.range) - m.range(at: 1).length, length: m.range(at: 1).length))
            protect(m.range)
        }
        for m in matches(math) where !isProtected(m.range) { monoLiteral(m.range) }
        for m in matches(image) where !isProtected(m.range) { monoLiteral(m.range) }
        for (pattern, trait) in [(strong, NSFontTraitMask.boldFontMask), (emphasis, .italicFontMask)] {
            for m in matches(pattern) where !isProtected(m.range) {
                addTrait(trait, m.range(at: 2))
                let marker = m.range(at: 1).length
                hide(NSRange(location: m.range.location, length: marker))
                hide(NSRange(location: NSMaxRange(m.range) - marker, length: marker))
            }
        }
        for m in matches(strike) where !isProtected(m.range) {
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: m.range(at: 2))
            hide(NSRange(location: m.range.location, length: 2))
            hide(NSRange(location: NSMaxRange(m.range) - 2, length: 2))
        }
        for m in matches(link) where !isProtected(m.range) {
            storage.addAttributes([.foregroundColor: accent, .underlineStyle: NSUnderlineStyle.single.rawValue], range: m.range(at: 2))
            hide(m.range(at: 1))
            hide(m.range(at: 3))
        }
        return target
    }
}

private extension NSRange {
    var nonEmpty: NSRange? { location == NSNotFound ? nil : self }
}

/// Markdown formatting and list continuation, applied through `insertText(_:replacementRange:)` so each
/// command is one native undo step and goes through the normal text-change path. Works in either pane.
/// Every command toggles: run it again on the same text and the source is back to what it was.
@MainActor
enum MarkdownFormat {
    /// One formatting command, shared by the Format menu and the formatting bar.
    @MainActor struct Command: Identifiable {
        enum Group { case inline, block }
        let id: String
        let title: String
        let shortcut: KeyboardShortcut?
        let symbol: String
        let group: Group
        private let action: @MainActor (NSTextView) -> Void

        init(_ id: String, _ title: String, _ shortcut: KeyboardShortcut?, _ symbol: String, _ group: Group, _ action: @escaping @MainActor (NSTextView) -> Void) {
            self.id = id; self.title = title; self.shortcut = shortcut; self.symbol = symbol; self.group = group; self.action = action
        }

        func perform(on view: NSTextView) { action(view) }

        /// The shortcut as a menu shows it, e.g. "⇧⌘X"; nil without one.
        var shortcutText: String? {
            guard let shortcut else { return nil }
            let m = shortcut.modifiers
            let symbols = [(EventModifiers.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")].filter { m.contains($0.0) }.map(\.1)
            return symbols.joined() + String(shortcut.key.character).uppercased()
        }

        /// Tooltip: the title and its shortcut, "Bold (⌘B)".
        var help: String { shortcutText.map { "\(title) (\($0))" } ?? title }

        /// Menu and bar order. ⌥⌘1–3, ⌥⌘E and ⌥⌘P are the View menu's, so block styles use ⌃⌘ and ⇧⌘.
        static let all: [Command] = [
            Command("bold", "Bold", KeyboardShortcut("b"), "bold", .inline) { wrap($0, marker: "**") },
            Command("italic", "Italic", KeyboardShortcut("i"), "italic", .inline) { wrap($0, marker: "*") },
            Command("strikethrough", "Strikethrough", KeyboardShortcut("x", modifiers: [.command, .shift]), "strikethrough", .inline) { wrap($0, marker: "~~") },
            Command("code", "Inline Code", nil, "chevron.left.forwardslash.chevron.right", .inline) { wrap($0, marker: "`") },
            Command("link", "Link", KeyboardShortcut("k"), "link", .inline) { link($0) },
            Command("body", "Body", KeyboardShortcut("0", modifiers: [.command, .control]), "text.alignleft", .block) { setBlock($0, .body) },
            Command("heading1", "Heading 1", KeyboardShortcut("1", modifiers: [.command, .control]), "textformat.size.larger", .block) { setBlock($0, .heading(1)) },
            Command("heading2", "Heading 2", KeyboardShortcut("2", modifiers: [.command, .control]), "textformat.size", .block) { setBlock($0, .heading(2)) },
            Command("heading3", "Heading 3", KeyboardShortcut("3", modifiers: [.command, .control]), "textformat.size.smaller", .block) { setBlock($0, .heading(3)) },
            Command("bulleted", "Bulleted List", KeyboardShortcut("8", modifiers: [.command, .shift]), "list.bullet", .block) { setBlock($0, .bulleted) },
            Command("numbered", "Numbered List", KeyboardShortcut("7", modifiers: [.command, .shift]), "list.number", .block) { setBlock($0, .numbered) },
            Command("checklist", "Checklist", KeyboardShortcut("9", modifiers: [.command, .shift]), "checklist", .block) { setBlock($0, .checklist) },
            Command("quote", "Quote", nil, "text.quote", .block) { togglePrefix($0, "> ") },
            Command("codeBlock", "Code Block", nil, "curlybraces", .block) { codeBlock($0) },
        ]
    }

    /// Toggles inline `marker` (`**`, `*`, `~~` or `` ` ``) on the selection, or on the word at the caret.
    /// Already formatted (markers just inside or just outside the selection): removes them. Otherwise wraps
    /// the selection without its outer spaces, since `**word **` isn't bold in Markdown.
    static func wrap(_ view: NSTextView, marker: String) {
        let text = view.string as NSString
        var range = view.selectedRange()
        if range.length == 0 {
            let word = view.selectionRange(forProposedRange: range, granularity: .selectByWord)
            if word.length > 0, !text.substring(with: word).contains(where: \.isWhitespace), !text.substring(with: word).contains("\n") { range = word }
        }
        while range.length > 0, text.substring(with: NSRange(location: range.location, length: 1)).first!.isWhitespace { range.location += 1; range.length -= 1 }
        while range.length > 0, text.substring(with: NSRange(location: NSMaxRange(range) - 1, length: 1)).first!.isWhitespace { range.length -= 1 }
        let n = (marker as NSString).length
        let chars: Set<Character> = marker.first == "*" ? ["*", "_"] : [marker.first!]
        /// Whether a run of `count` marker characters carries this marker: `***` is both bold and italic.
        func carries(_ count: Int) -> Bool {
            switch marker {
            case "**": count == 2 || count == 3
            case "*": count == 1 || count == 3
            default: count == n
            }
        }
        func run(_ s: String) -> Int { guard let c = s.first, chars.contains(c) else { return 0 }; return s.prefix { $0 == c }.count }
        let selected = text.substring(with: range)
        // Markers inside the selection (it was selected across the hidden markup).
        let inner = run(selected), innerEnd = run(String(selected.reversed()))
        if range.length > 2 * n, carries(min(inner, innerEnd)), selected.first == selected.last {
            let kept = (selected as NSString).substring(with: NSRange(location: n, length: range.length - 2 * n))
            view.insertText(kept, replacementRange: range)
            view.setSelectedRange(NSRange(location: range.location, length: (kept as NSString).length))
            return
        }
        // Markers just outside the selection.
        let before = String(text.substring(to: range.location).reversed()), after = text.substring(from: NSMaxRange(range))
        if run(before) > 0, before.first == after.first, carries(min(run(before), run(after))) {
            view.insertText(selected, replacementRange: NSRange(location: range.location - n, length: range.length + 2 * n))
            view.setSelectedRange(NSRange(location: range.location - n, length: range.length))
            return
        }
        view.insertText(marker + selected + marker, replacementRange: range)
        view.setSelectedRange(NSRange(location: range.location + n, length: range.length))
    }

    private static let inlineLink = try! NSRegularExpression(pattern: #"(?<!!)\[([^\]\n]*)\]\([^)\n]*\)"#)

    /// Wraps the selection as `[text](https://)` with the URL selected; with the selection anywhere in a
    /// link (text or URL), unlinks it, keeping the text.
    static func link(_ view: NSTextView) {
        let text = view.string as NSString
        let range = view.selectedRange()
        let line = text.lineRange(for: range)
        if let m = inlineLink.matches(in: view.string, range: line).first(where: { range.location >= $0.range.location && NSMaxRange(range) <= NSMaxRange($0.range) }) {
            let label = text.substring(with: m.range(at: 1))
            view.insertText(label, replacementRange: m.range)
            view.setSelectedRange(NSRange(location: m.range.location, length: (label as NSString).length))
            return
        }
        let selected = text.substring(with: range)
        let label = selected.isEmpty ? "link" : selected
        view.insertText("[\(label)](https://)", replacementRange: range)
        view.setSelectedRange(NSRange(location: range.location + (label as NSString).length + 3, length: 8))
    }

    /// Cycles the caret line through # → ## → ### → plain text.
    static func heading(_ view: NSTextView) {
        replaceLinePrefixes(view) { line in
            let hashes = line.prefix { $0 == "#" }.count
            let rest = line.drop { $0 == "#" }.drop { $0 == " " }
            return hashes >= 3 ? String(rest) : String(repeating: "#", count: hashes + 1) + " " + rest
        }
    }

    enum Block: Equatable { case body, heading(Int), bulleted, numbered, checklist }

    /// Heading, list or task marker after a line's indentation (and any quote markers).
    private static let blockPrefix = #/^([ \t]*(?:>[ \t]?)*)(#{1,6}[ \t]+|(?:[-*+]|\d{1,9}[.)])[ \t]+(?:\[[ xX]\][ \t]+)?)?/#

    static func block(of line: String) -> Block {
        guard let m = line.prefixMatch(of: blockPrefix), let prefix = m.output.2 else { return .body }
        if prefix.first == "#" { return .heading(prefix.prefix { $0 == "#" }.count) }
        if prefix.contains("[") { return .checklist }
        return prefix.first!.isNumber ? .numbered : .bulleted
    }

    /// Sets the selected lines' block style, replacing any heading or list marker (indentation and quote
    /// markers stay). If every non-empty line already has `style`, they become body text instead.
    static func setBlock(_ view: NSTextView, _ style: Block) {
        let lines = selectedLines(view).text.components(separatedBy: "\n")
        let target = lines.filter { !$0.isEmpty }.allSatisfy { block(of: $0) == style } ? .body : style
        var number = 0
        replaceLinePrefixes(view) { line in
            guard !line.isEmpty, let m = line.prefixMatch(of: blockPrefix) else { return line }
            let content = line[m.range.upperBound...]
            let marker: String
            switch target {
            case .body: marker = ""
            case .heading(let level): marker = String(repeating: "#", count: level) + " "
            case .bulleted: marker = "- "
            case .numbered: number += 1; marker = "\(number). "
            case .checklist: marker = "- [ ] "
            }
            return m.output.1 + marker + content
        }
    }

    /// Adds `prefix` to every selected line, or removes it if all already have it.
    static func togglePrefix(_ view: NSTextView, _ prefix: String) {
        let lines = selectedLines(view).text.components(separatedBy: "\n")
        let remove = lines.filter { !$0.isEmpty }.allSatisfy { $0.hasPrefix(prefix) }
        replaceLinePrefixes(view) { line in
            if remove { return line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : line }
            return line.isEmpty ? line : prefix + line
        }
    }

    /// Fences the selected lines as a code block; inside a fenced block, removes its fence lines.
    static func codeBlock(_ view: NSTextView) {
        let text = view.string as NSString
        let caret = view.selectedRange()
        if let block = MarkdownStyler.fences(text).first(where: { NSLocationInRange(caret.location, $0.range) || caret.location == NSMaxRange($0.range) }) {
            let whole = text.lineRange(for: block.range)
            let open = text.lineRange(for: block.markers[0])
            let bodyEnd = block.markers.count > 1 ? text.lineRange(for: block.markers[1]).location : NSMaxRange(whole)
            var code = text.substring(with: NSRange(location: NSMaxRange(open), length: max(0, bodyEnd - NSMaxRange(open))))
            if block.markers.count > 1, text.substring(with: whole).hasSuffix("\n"), !code.hasSuffix("\n") { code += "\n" }
            if !text.substring(with: whole).hasSuffix("\n"), code.hasSuffix("\n") { code.removeLast() }
            view.insertText(code, replacementRange: whole)
            view.setSelectedRange(NSRange(location: whole.location, length: (code as NSString).length))
            return
        }
        let (range, lines) = selectedLines(view)
        view.insertText("```\n" + lines + "\n```", replacementRange: range)
        view.setSelectedRange(NSRange(location: range.location + 4, length: (lines as NSString).length))
    }

    /// Return in a list or quote continues it; Return on an empty item ends it. Returns false otherwise.
    static func continueBlock(_ view: NSTextView) -> Bool {
        let text = view.string as NSString
        let caret = view.selectedRange()
        guard caret.length == 0 else { return false }
        let lineRange = text.lineRange(for: NSRange(location: caret.location, length: 0))
        let line = text.substring(with: NSRange(location: lineRange.location, length: caret.location - lineRange.location))
        // Quote markers (any depth) then an optional list marker: "> > a" and "> - a" keep both.
        guard let m = line.prefixMatch(of: #/([ \t]*(?:>[ \t]?)*)(?:(?:([-*+])|(\d{1,9})([.)]))([ \t]+)(\[[ xX]\][ \t]+)?)?/#),
              m.output.1.contains(">") || m.output.2 != nil || m.output.3 != nil else { return false }
        let wholeLine = text.substring(with: lineRange).trimmingCharacters(in: .newlines)
        let rest = wholeLine.dropFirst(line.count)
        if line.count == m.output.0.count, rest.allSatisfy({ $0 == " " || $0 == "\t" }) {
            // Empty item (at most spaces after the caret): end the list, trailing spaces included. After an
            // item, leave a blank line too, or the next text would continue that item (lazy continuation in Read).
            let previous = lineRange.location > 0 ? text.substring(with: text.lineRange(for: NSRange(location: lineRange.location - 1, length: 0))) : ""
            let separate = previous.firstMatch(of: #/^[ \t]*(?:[-*+]|\d{1,9}[.)]|>)[ \t]*\S/#) != nil
            view.insertText(separate ? "\n" : "", replacementRange: NSRange(location: lineRange.location, length: (wholeLine as NSString).length))
            return true
        }
        var marker = String(m.output.1)
        if let bullet = m.output.2 { marker += bullet }
        if let number = m.output.3.flatMap({ Int($0) }), let close = m.output.4 { marker += "\(number + 1)\(close)" }
        marker += m.output.5 ?? ""
        if m.output.6 != nil { marker += "[ ] " }
        view.insertText("\n" + marker, replacementRange: caret)
        return true
    }

    /// Return in prose starts a new paragraph (a blank line), so Read shows it as a separate paragraph, not
    /// a line joined to the one above. Table rows, display math, HTML and front matter keep a plain newline,
    /// as does Return at the start of a line. Returns false when a plain newline is right.
    static func paragraphBreak(_ view: NSTextView) -> Bool {
        let text = view.string as NSString
        let caret = view.selectedRange()
        let line = text.lineRange(for: NSRange(location: caret.location, length: 0))
        let before = text.substring(with: NSRange(location: line.location, length: caret.location - line.location))
        guard !before.allSatisfy(\.isWhitespace), before.firstMatch(of: #/^ {0,3}(\||\$\$|<|---|\+\+\+)/#) == nil,
              !isTableRow(line, in: text) else { return false }
        if text.hasPrefix("---\n"), let end = text.range(of: "\n---", range: NSRange(location: 3, length: text.length - 3)).nonEmpty,
           caret.location <= end.location { return false } // front matter
        view.insertText("\n\n", replacementRange: caret)
        return true
    }

    private static let tableDelimiter = #/^[ \t]*\|?[ \t]*:?-+:?[ \t]*(\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*$/#

    /// A pipe-table row, with or without outer pipes (`a | b`): the line has a `|` and a delimiter row
    /// (`---|:-:`) is the line itself, the next line (a header row), or above it through lines that all have `|`
    /// (every pipe-table row does). Prose with a `|` stops at the first line without one.
    // ponytail: walks at most `maxTableScan` lines, so a keystroke never scans a whole 1 MiB block; a row more
    // than that far below its delimiter gets a paragraph break. Track table spans in the styler if that matters.
    static let maxTableScan = 1000
    static func isTableRow(_ line: NSRange, in text: NSString) -> Bool {
        func has(_ r: NSRange) -> Bool { text.range(of: "|", options: .literal, range: r).location != NSNotFound }
        func isDelimiter(_ r: NSRange) -> Bool {
            r.length < 1000 && has(r) && text.substring(with: r).trimmingCharacters(in: .newlines).wholeMatch(of: tableDelimiter) != nil
        }
        guard has(line) else { return false }
        if isDelimiter(line) { return true }
        if NSMaxRange(line) < text.length, isDelimiter(text.lineRange(for: NSRange(location: NSMaxRange(line), length: 0))) { return true }
        var up = line
        for _ in 0..<maxTableScan where up.location > 0 {
            up = text.lineRange(for: NSRange(location: up.location - 1, length: 0))
            if isDelimiter(up) { return true }
            if !has(up) { return false }
        }
        return false
    }

    private static func selectedLines(_ view: NSTextView) -> (range: NSRange, text: String) {
        let text = view.string as NSString
        var range = text.lineRange(for: view.selectedRange())
        if range.length > 0, text.substring(with: range).hasSuffix("\n") { range.length -= 1 }
        return (range, text.substring(with: range))
    }

    private static func replaceLinePrefixes(_ view: NSTextView, _ transform: (String) -> String) {
        let (range, text) = selectedLines(view)
        let replaced = text.components(separatedBy: "\n").map(transform).joined(separator: "\n")
        guard replaced != text else { return }
        view.insertText(replaced, replacementRange: range)
        view.setSelectedRange(NSRange(location: range.location, length: (replaced as NSString).length))
    }
}

/// The Write view's text view: Markdown styled as rendered in a centered, Read-width column; markup hidden.
@MainActor
final class WritingHandle: TextViewHandle, NSLayoutManagerDelegate {
    private var revealed = NSRange(location: NSNotFound, length: 0)
    /// Fenced code blocks, rescanned only when an edit could change fence structure; otherwise shifted.
    private var fences: [(range: NSRange, markers: [NSRange])] = []
    private var edited: NSRange?
    private var fenceEdit = false
    /// End of the front matter at the last restyle (0 if none).
    private var frontMatterEnd = 0, styledLength = 0
    private var mouseUp: Any?
    private var resize: Any?

    override func configure(_ view: NSTextView) {
        view.font = .systemFont(ofSize: MarkdownStyler.bodySize)
        view.textContainerInset = NSSize(width: Theme.s5, height: Theme.s4)
        // Full-width editor, centered column: the side insets grow so the text is at most Read's width.
        view.postsFrameChangedNotifications = true
        resize = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.centerColumn() }
        }
        centerColumn()
        if let container = view.textContainer, !(view.layoutManager is MarkdownLayoutManager) {
            container.replaceLayoutManager(MarkdownLayoutManager()) // draws bullets, task boxes, quote bars, rules
        }
        view.layoutManager?.delegate = self // TextKit 1 for per-glyph hiding
        view.layoutManager?.allowsNonContiguousLayout = true // large files: lay out only what's visible
        // Reveal follows the caret only after a click or drag ends, so the line doesn't reflow under the mouse.
        mouseUp = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            if let self, event.window === self.view?.window { DispatchQueue.main.async { self.updateReveal() } }
            return event
        }
        restyle(nil)
    }

    deinit {
        if let mouseUp { NSEvent.removeMonitor(mouseUp) }
        if let resize { NotificationCenter.default.removeObserver(resize) }
    }

    /// Side insets that center a column of at most `MarkdownStyler.columnWidth`; text never starts closer than
    /// Read's 24 pt padding. The inset excludes the line fragment padding, which TextKit adds inside it.
    func centerColumn() {
        guard let view else { return }
        let padding = view.textContainer?.lineFragmentPadding ?? 0
        let side = (max(Theme.s5, (view.frame.width - MarkdownStyler.columnWidth) / 2) - padding).rounded(.down)
        if view.textContainerInset.width != side { view.textContainerInset = NSSize(width: side, height: Theme.s4) }
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
        let replacement = replacementString ?? ""
        noteEdit(at: range.location, removedLength: range.length, insertedLength: (replacement as NSString).length,
                 changedText: (textView.string as NSString).substring(with: range) + replacement)
        let inserted = NSRange(location: range.location, length: (replacement as NSString).length)
        edited = edited.map { NSUnionRange($0, inserted) } ?? inserted
        return true
    }

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        if let edited, startsFence(edited) { fenceEdit = true }
        if fenceEdit { restyleAfterFenceEdit() } else { restyle(edited) }
        edited = nil
        fenceEdit = false
        pendingEdits = []
    }

    override func didSync(changed: NSRange, removed: String, delta: Int) {
        noteEdit(at: changed.location, removedLength: changed.length - delta, insertedLength: changed.length,
                 changedText: removed + ((view?.string ?? "") as NSString).substring(with: changed))
        if startsFence(changed) { fenceEdit = true }
        if fenceEdit { restyleAfterFenceEdit() } else { restyle(changed) }
        fenceEdit = false
        pendingEdits = []
    }

    /// One edit since the last restyle, with the fence blocks as they were before it.
    private struct Edit { let location: Int, removed: Int, inserted: Int; let before: [(range: NSRange, markers: [NSRange])] }
    private var pendingEdits: [Edit] = []

    /// After an edit that may change fence structure: rescan fences (cheap), then restyle only what moved.
    /// Blocks before the edit can't change (fences are scanned top-down). If the blocks after it are the old ones
    /// shifted, only the edited paragraphs and the blocks that touched the edit restyle; otherwise everything
    /// from the edit to the end does (e.g. a new opening fence turns the rest of the text into code).
    private func restyleAfterFenceEdit() {
        guard let view, pendingEdits.count == 1, let e = pendingEdits.first else { restyle(nil); return }
        let text = view.string as NSString
        let new = MarkdownStyler.fences(text)
        fences = new
        let delta = e.inserted - e.removed, oldEnd = e.location + e.removed, newEnd = e.location + e.inserted
        guard newEnd <= text.length else { restyle(nil); return }
        func same(_ a: [(range: NSRange, markers: [NSRange])], _ b: [(range: NSRange, markers: [NSRange])]) -> Bool {
            a.count == b.count && zip(a, b).allSatisfy { $0.range == $1.range && $0.markers == $1.markers }
        }
        let oldTail = e.before.filter { $0.range.location >= oldEnd }.map { block in
            (range: NSRange(location: block.range.location + delta, length: block.range.length),
             markers: block.markers.map { NSRange(location: $0.location + delta, length: $0.length) })
        }
        var start = e.location
        var end = same(oldTail, new.filter { $0.range.location >= newEnd }) ? newEnd : text.length
        for block in e.before where block.range.location < oldEnd + 1 && NSMaxRange(block.range) + 1 >= e.location {
            start = min(start, block.range.location)
            end = max(end, min(text.length, NSMaxRange(block.range) + (NSMaxRange(block.range) >= oldEnd ? delta : 0)))
        }
        restyle(NSRange(location: start, length: max(0, end - start)))
    }

    override func textViewDidChangeSelection(_ notification: Notification) {
        super.textViewDidChangeSelection(notification)
        // Mid-sync or mid-edit the storage is still changing and the cached fences are stale (a shrinking
        // command edit used to throw NSRangeException here); didSync / textDidChange restyle once it settles.
        guard !isUpdating, edited == nil else { return }
        let event = NSApp.currentEvent?.type
        guard event != .leftMouseDown, event != .leftMouseDragged else { return } // wait for mouse-up
        updateReveal()
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.deleteBackward(_:)): return deleteAcrossHiddenMarkup(textView, forward: false)
        case #selector(NSResponder.deleteForward(_:)): return deleteAcrossHiddenMarkup(textView, forward: true)
        case #selector(NSResponder.moveRight(_:)), #selector(NSResponder.moveForward(_:)): return moveCaret(textView, forward: true)
        case #selector(NSResponder.moveLeft(_:)), #selector(NSResponder.moveBackward(_:)): return moveCaret(textView, forward: false)
        case #selector(NSResponder.insertLineBreak(_:)):
            // Shift-Return: a Markdown hard line break (`\` + newline; the backslash is hidden), so Read breaks
            // the line too instead of joining it. Never NSTextView's U+2028, which isn't Markdown.
            textView.insertText("\\\n", replacementRange: textView.selectedRange())
            return true
        case #selector(NSResponder.insertNewline(_:)): break
        default: return false
        }
        // Inside fenced code, Return is a plain newline: `- ` or `> ` there is code (a diff, YAML, a shell prompt).
        let caret = textView.selectedRange().location
        // The cached blocks are current between edits (kept by noteEdit/restyle), so no rescan per keystroke.
        if fences.contains(where: { caret > $0.range.location && caret <= NSMaxRange($0.range) }) {
            return false
        }
        return MarkdownFormat.continueBlock(textView) || MarkdownFormat.paragraphBreak(textView)
    }

    /// The hidden-markup run touching `location` (a hidden character at or just before it), if any.
    private func hiddenRun(at location: Int, in storage: NSTextStorage) -> NSRange? {
        func hidden(_ i: Int) -> Bool { i >= 0 && i < storage.length && Self.isMarkup(storage, i) }
        guard hidden(location) || hidden(location - 1) else { return nil }
        var a = hidden(location) ? location : location - 1, b = a + 1
        while hidden(a - 1) { a -= 1 }
        while hidden(b) { b += 1 }
        return NSRange(location: a, length: b - a)
    }

    /// Every caret position in or at the edges of a hidden run draws at the same spot, so the run gets one
    /// caret stop. Block markup (`# `, `> `, a list marker or task box) stops after itself, so typing lands in
    /// the heading or item. Inline markup stops before itself, like TextEdit: typing at the end of a bold word
    /// or link continues it, and typing before one does not.
    private func caretStop(_ run: NSRange, in storage: NSTextStorage) -> Int {
        storage.attribute(.markdownAtomic, at: run.location, effectiveRange: nil) != nil ? NSMaxRange(run) : run.location
    }

    /// The caret position `location` draws as (its run's stop, or itself).
    private func stop(_ location: Int, in storage: NSTextStorage) -> Int {
        hiddenRun(at: location, in: storage).map { caretStop($0, in: storage) } ?? location
    }

    /// Hidden or atomic (drawn-over) markup: caret and Delete treat both as one unit.
    private static func isMarkup(_ storage: NSTextStorage, _ i: Int) -> Bool {
        storage.attribute(.markdownHidden, at: i, effectiveRange: nil) != nil || storage.attribute(.markdownAtomic, at: i, effectiveRange: nil) != nil
    }

    /// Left/Right move to the next position that draws somewhere else: one press, one visible step, across
    /// hidden markup. (AppKit's own glyph moves get lost before null glyphs.) Selections use AppKit's moves.
    private func moveCaret(_ view: NSTextView, forward: Bool) -> Bool {
        let caret = view.selectedRange()
        guard caret.length == 0, let storage = view.textStorage else { return false }
        let text = storage.string as NSString
        let current = stop(caret.location, in: storage)
        var p = caret.location
        while forward ? p < text.length : p > 0 {
            p = forward ? NSMaxRange(text.rangeOfComposedCharacterSequence(at: p)) : text.rangeOfComposedCharacterSequence(at: p - 1).location
            let next = stop(p, in: storage)
            if next != current {
                view.setSelectedRange(NSRange(location: next, length: 0))
                view.scrollRangeToVisible(NSRange(location: next, length: 0))
                return true
            }
        }
        return true // already at the end: nothing visible to move past
    }

    /// Clicks, Up/Down, Home/End and programmatic moves land on the stop. Selections, and changes made by an
    /// edit or a sync (attributes still stale), are left alone.
    func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRange old: NSRange, toCharacterRange new: NSRange) -> NSRange {
        guard new.length == 0, !isUpdating, edited == nil, let storage = textView.textStorage else { return new }
        return NSRange(location: stop(new.location, in: storage), length: 0)
    }

    /// Delete next to hidden markup removes what you see: a visible character past the markup, or, at the
    /// start of a heading, quote or list item, its block marker (the line becomes body text). Never one
    /// invisible inline marker.
    private func deleteAcrossHiddenMarkup(_ view: NSTextView, forward: Bool) -> Bool {
        let caret = view.selectedRange()
        guard caret.length == 0, let storage = view.textStorage else { return false }
        let text = storage.string as NSString
        let probe = forward ? caret.location : caret.location - 1
        guard probe >= 0, probe < text.length, Self.isMarkup(storage, probe),
              let run = hiddenRun(at: probe, in: storage) else { return false }
        if !forward, storage.attribute(.markdownAtomic, at: run.location, effectiveRange: nil) != nil {
            var block = run.location
            while block < NSMaxRange(run), storage.attribute(.markdownAtomic, at: block, effectiveRange: nil) != nil { block += 1 }
            view.insertText("", replacementRange: NSRange(location: run.location, length: block - run.location))
            return true
        }
        let edge = forward ? NSMaxRange(run) : run.location - 1
        guard edge >= 0, edge < text.length else { return true } // only markup on that side: nothing visible to delete
        view.insertText("", replacementRange: text.rangeOfComposedCharacterSequence(at: edge))
        return true
    }

    /// Fence structure can change only if a fence run is typed/removed, the edit touches a fence line, or an
    /// edited line now starts like a fence (`isFenceLine`); otherwise cached blocks shift (no document rescan).
    private func noteEdit(at location: Int, removedLength: Int, insertedLength: Int, changedText: String) {
        pendingEdits.append(Edit(location: location, removed: removedLength, inserted: insertedLength, before: fences))
        let edit = NSRange(location: max(0, location - 1), length: removedLength + 2) // touching a fence line counts
        if changedText.contains("```") || changedText.contains("~~~")
            || fences.contains(where: { $0.markers.contains { NSIntersectionRange(edit, NSRange(location: $0.location, length: $0.length + 1)).length > 0 } }) {
            fenceEdit = true
            return
        }
        let delta = insertedLength - removedLength, end = location + removedLength
        fences = fences.map { block in
            func shift(_ r: NSRange) -> NSRange { r.location >= end ? NSRange(location: r.location + delta, length: r.length) : r }
            var range = shift(block.range)
            if block.range.location < location, NSMaxRange(block.range) >= end { range.length += delta }
            return (range, block.markers.map(shift))
        }
    }

    private func startsFence(_ range: NSRange) -> Bool {
        guard let text = view?.string as NSString?, NSMaxRange(range) <= text.length else { return true }
        // Through the next line: a Return before "```" makes that line a fence.
        let lines = NSRange(location: range.location, length: min(range.length + 1, text.length - range.location))
        return text.substring(with: text.paragraphRange(for: lines)).split(separator: "\n", omittingEmptySubsequences: false)
            .contains { let t = $0.drop { $0 == " " }; return t.hasPrefix("```") || t.hasPrefix("~~~") }
    }

    /// Moves the revealed markup to the caret's lines; a selection keeps the current reveal (no reflow while selecting).
    private func updateReveal() {
        guard let view, view.selectedRange().length == 0 else { return }
        let lines = (view.string as NSString).lineRange(for: view.selectedRange())
        guard lines != revealed else { return }
        restyle(lines, also: revealed)
    }

    /// Restyles `range` (paragraphs) or everything; `also` is a second range to refresh (the old reveal).
    func restyle(_ range: NSRange?, also: NSRange? = nil) {
        guard let view, let storage = view.textStorage else { return }
        let text = view.string as NSString
        let caret = text.lineRange(for: NSRange(location: min(view.selectedRange().location, text.length), length: 0))
        revealed = view.window?.firstResponder === view ? caret : NSRange(location: NSNotFound, length: 0)
        if range == nil { fences = MarkdownStyler.fences(text) }
        // The line after an edit too: Return splits a line, and the new line ("# x") needs its own style.
        var range = range.map { NSRange(location: $0.location, length: min($0.length + 1, max(0, text.length - $0.location))) }
        // Front matter that an edit opened, closed or shrank: restyle from the top through its old and new end.
        // The old end is in the old text's coordinates; an edit above it moved it by up to the length change.
        let matterEnd = max(MarkdownStyler.frontMatter(text).map(NSMaxRange) ?? 0, frontMatterEnd + max(0, text.length - styledLength))
        if let r = range, matterEnd > 0, r.location <= matterEnd + 1 { range = NSUnionRange(r, NSRange(location: 0, length: min(matterEnd + 1, text.length))) }
        frontMatterEnd = MarkdownStyler.frontMatter(text).map(NSMaxRange) ?? 0
        styledLength = text.length
        let limits: [NSRange?] = range == nil ? [nil] : [range, also].compactMap { $0 }
            .filter { $0.location != NSNotFound }
            .map { NSRange(location: min($0.location, text.length), length: max(0, min(NSMaxRange($0), text.length) - min($0.location, text.length))) }
        for limit in limits {
            let refreshed = MarkdownStyler.apply(to: storage, reveal: revealed, in: limit, fences: fences)
            view.layoutManager?.invalidateGlyphs(forCharacterRange: refreshed, changeInLength: 0, actualCharacterRange: nil)
            view.layoutManager?.invalidateLayout(forCharacterRange: refreshed, actualCharacterRange: nil)
        }
    }

    nonisolated func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                                   properties: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes: UnsafePointer<Int>,
                                   font: NSFont, forGlyphRange range: NSRange) -> Int {
        MainActor.assumeIsolated {
            guard let storage = layoutManager.textStorage else { return 0 }
            var changed = false
            let props = UnsafeMutablePointer<NSLayoutManager.GlyphProperty>.allocate(capacity: range.length)
            defer { props.deallocate() }
            for i in 0..<range.length {
                props[i] = properties[i]
                if let object = MarkdownObjects.glyphProperty(at: characterIndexes[i], in: storage, proposed: props[i]) {
                    props[i] = object
                    changed = true
                } else if characterIndexes[i] < storage.length, storage.attribute(.markdownHidden, at: characterIndexes[i], effectiveRange: nil) != nil {
                    props[i].insert(.null)
                    changed = true
                }
            }
            guard changed else { return 0 }
            layoutManager.setGlyphs(glyphs, properties: props, characterIndexes: characterIndexes, font: font, forGlyphRange: range)
            return range.length
        }
    }

    /// Object glyphs (table separators, images) are whitespace sized by `MarkdownObjects`.
    nonisolated func layoutManager(_ layoutManager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction,
                                   forControlCharacterAt index: Int) -> NSLayoutManager.ControlCharacterAction {
        layoutManager.textStorage.flatMap { MarkdownObjects.controlCharacterAction(at: index, in: $0) } ?? action
    }

    nonisolated func layoutManager(_ layoutManager: NSLayoutManager, boundingBoxForControlGlyphAt glyphIndex: Int, for container: NSTextContainer,
                                   proposedLineFragment rect: NSRect, glyphPosition position: NSPoint, characterIndex index: Int) -> NSRect {
        layoutManager.textStorage.flatMap { MarkdownObjects.boundingBox(at: index, in: $0, glyphPosition: position) } ?? NSRect(origin: position, size: .zero)
    }
}

/// Formatting buttons for the focused Markdown text view (Write or Source).
struct MarkdownFormatBar: View {
    let target: () -> NSTextView?

    var body: some View {
        HStack(spacing: Theme.s1) {
            ForEach(MarkdownFormat.Command.all) { command in
                if command.id == "body" { Divider().frame(height: 16) }
                Button { if let view = target() { command.perform(on: view); view.window?.makeFirstResponder(view) } } label: {
                    Label(command.title, systemImage: command.symbol)
                }
                .help(command.help)
                .accessibilityLabel(command.title)
            }
            Spacer()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, Theme.s2)
        .padding(.vertical, Theme.s1)
    }
}
