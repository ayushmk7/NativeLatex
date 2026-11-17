import AppKit
import NativeLatexDesign
import SwiftUI

extension NSAttributedString.Key {
    /// Markup characters drawn as nothing (null glyphs) in the Write view. The text itself is untouched.
    static let markdownHidden = NSAttributedString.Key("LibreWeaveMarkdownHidden")
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
    /// Read: `line-height: 1.55`, paragraphs `margin: 1em`, headings `margin-top: 1.4em`, `line-height: 1.25`.
    static let lineHeight: CGFloat = 1.55, headingLineHeight: CGFloat = 1.25, headingSpaceBefore: CGFloat = 1.4
    /// Read's `main { max-width: 46em }` at the 15 px body size.
    static let columnWidth: CGFloat = 46 * bodySize
    /// Font and paragraph style per heading level, made once (measuring line height costs a layout manager).
    nonisolated(unsafe) static let headingStyles: [[NSAttributedString.Key: Any]] = headingSizes.map { size in
        let font = NSFont.systemFont(ofSize: size, weight: .bold)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing(font, multiple: headingLineHeight)
        // Read's 1.4em margin above, less the blank line's 1em that already separates the blocks.
        style.paragraphSpacingBefore = max(0, size * headingSpaceBefore - bodySize)
        return [.font: font, .paragraphStyle: style]
    }
    static let bodyLineSpacing = lineSpacing(.systemFont(ofSize: bodySize), multiple: lineHeight)
    /// Extra space below each line so it is `lineHeight` × the font size tall, like CSS line-height.
    static func lineSpacing(_ font: NSFont, multiple: CGFloat) -> CGFloat {
        max(0, (font.pointSize * multiple - NSLayoutManager().defaultLineHeight(for: font)).rounded())
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }
    private static let heading = regex(#"^ {0,3}(#{1,6})([ \t]+|$)"#)
    private static let quote = regex(#"^ {0,3}(>[ \t]?)+"#)
    private static let list = regex(#"^[ \t]*([-*+]|\d{1,9}[.)])[ \t]+(\[[ xX]\][ \t]+)?"#)
    private static let blankLine = regex(#"^[ \t]*$"#)
    private static let literalLine = regex(#"^ {0,3}(\||\$\$|<|---[ \t]*$|\+\+\+).*$"#)
    /// Longest inline span (emphasis, link, image, math) the Write view styles, in UTF-16 units. Unbounded
    /// lazy spans made a long line of unmatched markers quadratic: a 24 KB line of `*a ` cost seconds per
    /// keystroke. Bounded, each marker scans at most this far, so styling stays linear in the line length.
    static let maxInlineSpan = 300
    private static let code = regex(#"(`+)(?!`)([\s\S]*?[^`])\1(?!`)"#)
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

    /// Restyles `limit` (whole paragraphs; all of `storage` if nil). Hidden markup stays hidden everywhere;
    /// only fence lines inside `reveal` (the caret's lines) turn from clear to dim, which never moves text. Code fences are found over the whole text, since an opening fence
    /// anywhere above changes what follows; a fence block touching `limit` is restyled whole.
    static func apply(to storage: NSTextStorage, reveal: NSRange, in limit: NSRange? = nil, fences known: [(range: NSRange, markers: [NSRange])]? = nil) {
        let text = storage.string as NSString
        let all = NSRange(location: 0, length: text.length)
        let blocks = known ?? fences(text)
        var target = limit.map { text.paragraphRange(for: NSIntersectionRange($0, all).location == NSNotFound ? NSRange(location: text.length, length: 0) : NSIntersectionRange($0, all)) } ?? all
        for block in blocks where NSIntersectionRange(block.range, target).length > 0 || NSLocationInRange(target.location, block.range) {
            target = NSUnionRange(target, text.paragraphRange(for: block.range))
        }
        let fg = NSColor(Theme.foreground), secondary = NSColor(Theme.secondary), accent = NSColor(Theme.accentText)
        let body = NSFont.systemFont(ofSize: bodySize)
        let mono = NSFont.monospacedSystemFont(ofSize: bodySize - 2, weight: .regular)
        let codeBackground = NSColor(Theme.surface)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = bodyLineSpacing
        // A blank line is the gap between blocks: one body size tall, like Read's 1em paragraph margin.
        let gap = NSMutableParagraphStyle()
        gap.minimumLineHeight = bodySize; gap.maximumLineHeight = bodySize

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

        for m in matches(blankLine) { storage.addAttribute(.paragraphStyle, value: gap, range: text.lineRange(for: m.range)) }
        for block in blocks where NSIntersectionRange(block.range, target).length > 0 {
            storage.addAttribute(.font, value: mono, range: block.range)
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
            // Shade only the code lines between the fences.
            let first = text.lineRange(for: block.markers[0])
            let bodyEnd = block.markers.count > 1 ? text.lineRange(for: block.markers[1]).location : NSMaxRange(block.range)
            if bodyEnd > NSMaxRange(first) {
                storage.addAttribute(.backgroundColor, value: codeBackground, range: NSRange(location: NSMaxRange(first), length: bodyEnd - NSMaxRange(first)))
            }
        }
        // Front matter at the very top stays literal.
        if target.location == 0, text.hasPrefix("---\n"), let end = text.range(of: "\n---", options: [], range: NSRange(location: 3, length: text.length - 3)).nonEmpty {
            monoLiteral(NSRange(location: 0, length: NSMaxRange(end)))
        }
        for m in matches(literalLine) where !isProtected(m.range) { monoLiteral(m.range) }

        for m in matches(heading) where !isProtected(m.range) {
            let line = text.lineRange(for: m.range)
            storage.addAttributes(headingStyles[m.range(at: 1).length - 1], range: line)
            hide(m.range)
        }
        for m in matches(quote) where !isProtected(m.range) {
            let line = text.lineRange(for: m.range)
            storage.addAttribute(.foregroundColor, value: secondary, range: line)
            let indented = paragraph.mutableCopy() as! NSMutableParagraphStyle
            indented.firstLineHeadIndent = 16; indented.headIndent = 16
            storage.addAttribute(.paragraphStyle, value: indented, range: line)
            hide(m.range)
        }
        for m in matches(list) where !isProtected(m.range) {
            storage.addAttribute(.foregroundColor, value: accent, range: m.range) // markers stay visible, like bullets
        }

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
        guard let m = line.firstMatch(of: #/^([ \t]*)(?:([-*+])|(\d{1,9})([.)])|(>))([ \t]+)(\[[ xX]\][ \t]+)?/#) else { return false }
        let wholeLine = text.substring(with: lineRange).trimmingCharacters(in: .newlines)
        let rest = wholeLine.dropFirst(line.count)
        if line.count == m.output.0.count, rest.allSatisfy({ $0 == " " || $0 == "\t" }) {
            // Empty item (at most spaces after the caret): end the list, trailing spaces included.
            view.insertText("", replacementRange: NSRange(location: lineRange.location, length: (wholeLine as NSString).length))
            return true
        }
        var marker = String(m.output.1)
        if let bullet = m.output.2 { marker += bullet }
        if let number = m.output.3.flatMap({ Int($0) }), let close = m.output.4 { marker += "\(number + 1)\(close)" }
        if let q = m.output.5 { marker += q }
        marker += m.output.6
        if m.output.7 != nil { marker += "[ ] " }
        view.insertText("\n" + marker, replacementRange: caret)
        return true
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

    /// Side insets that center a column of at most `MarkdownStyler.columnWidth`, never less than Read's 24 pt padding.
    func centerColumn() {
        guard let view else { return }
        let padding = view.textContainer?.lineFragmentPadding ?? 0
        let side = max(Theme.s5, ((view.frame.width - MarkdownStyler.columnWidth) / 2 - padding).rounded(.down))
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
        guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        // Inside fenced code, Return is a plain newline: `- ` or `> ` there is code (a diff, YAML, a shell prompt).
        let caret = textView.selectedRange().location
        if MarkdownStyler.fences(textView.string as NSString).contains(where: { caret > $0.range.location && caret <= NSMaxRange($0.range) }) {
            return false
        }
        return MarkdownFormat.continueBlock(textView)
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
        return text.substring(with: text.paragraphRange(for: range)).split(separator: "\n", omittingEmptySubsequences: false)
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
        let all = NSRange(location: 0, length: text.length)
        let caret = text.lineRange(for: NSRange(location: min(view.selectedRange().location, text.length), length: 0))
        revealed = view.window?.firstResponder === view ? caret : NSRange(location: NSNotFound, length: 0)
        if range == nil { fences = MarkdownStyler.fences(text) }
        let limits: [NSRange?] = range == nil ? [nil] : [range, also].compactMap { $0 }
            .filter { $0.location != NSNotFound }
            .map { NSRange(location: min($0.location, text.length), length: max(0, min(NSMaxRange($0), text.length) - min($0.location, text.length))) }
        for limit in limits {
            MarkdownStyler.apply(to: storage, reveal: revealed, in: limit, fences: fences)
            let refreshed = limit.map { text.paragraphRange(for: $0) } ?? all
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
                if characterIndexes[i] < storage.length, storage.attribute(.markdownHidden, at: characterIndexes[i], effectiveRange: nil) != nil {
                    props[i].insert(.null)
                    changed = true
                }
            }
            guard changed else { return 0 }
            layoutManager.setGlyphs(glyphs, properties: props, characterIndexes: characterIndexes, font: font, forGlyphRange: range)
            return range.length
        }
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
                .help(command.title)
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
