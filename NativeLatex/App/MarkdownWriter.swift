import AppKit
import NativeLatexDesign
import SwiftUI

extension NSAttributedString.Key {
    /// Markup characters drawn as nothing (null glyphs) in the Write view. The text itself is untouched.
    static let markdownHidden = NSAttributedString.Key("LibreWeaveMarkdownHidden")
}

/// Styles Markdown source so it reads like the rendered document: headings, emphasis, code, links,
/// quotes and lists are formatted and their markup is hidden, except on the line being edited.
/// Only attributes change; the characters (and so the saved Markdown) are exactly what the user typed.
/// Tables, math, images, HTML and front matter stay visible as Markdown in a quiet monospaced style.
enum MarkdownStyler {
    static let bodySize: CGFloat = 15
    static let headingSizes: [CGFloat] = [26, 22, 19, 17, 15, 15]

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }
    private static let heading = regex(#"^ {0,3}(#{1,6})([ \t]+|$)"#)
    private static let quote = regex(#"^ {0,3}(>[ \t]?)+"#)
    private static let list = regex(#"^[ \t]*([-*+]|\d{1,9}[.)])[ \t]+(\[[ xX]\][ \t]+)?"#)
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

    /// Restyles `limit` (whole paragraphs; all of `storage` if nil). Markup inside `reveal` (the caret's
    /// lines) stays visible, dimmed. Code fences are found over the whole text, since an opening fence
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
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 4

        storage.beginEditing()
        defer { storage.endEditing() }
        storage.setAttributes([.font: body, .foregroundColor: fg, .paragraphStyle: paragraph], range: target)
        var protected = IndexSet() // code and literal Markdown: no further styling inside

        func isRevealed(_ range: NSRange) -> Bool {
            NSIntersectionRange(range, reveal).length > 0 || (reveal.length == 0 && NSLocationInRange(reveal.location, NSRange(location: range.location, length: range.length + 1)))
        }
        func hide(_ range: NSRange) {
            guard range.length > 0 else { return }
            if isRevealed(range) {
                storage.addAttribute(.foregroundColor, value: secondary, range: range)
            } else {
                storage.addAttribute(.markdownHidden, value: true, range: range)
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
            let level = m.range(at: 1).length
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: headingSizes[level - 1], weight: .bold), range: line)
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
@MainActor
enum MarkdownFormat {
    static func wrap(_ view: NSTextView, marker: String) {
        let range = view.selectedRange()
        let selected = (view.string as NSString).substring(with: range)
        view.insertText(marker + selected + marker, replacementRange: range)
        let inner = NSRange(location: range.location + (marker as NSString).length, length: (selected as NSString).length)
        view.setSelectedRange(inner)
    }

    static func link(_ view: NSTextView) {
        let range = view.selectedRange()
        let selected = (view.string as NSString).substring(with: range)
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

    /// Adds `prefix` to every selected line, or removes it if all already have it.
    static func togglePrefix(_ view: NSTextView, _ prefix: String) {
        let lines = selectedLines(view).text.components(separatedBy: "\n")
        let remove = lines.filter { !$0.isEmpty }.allSatisfy { $0.hasPrefix(prefix) }
        replaceLinePrefixes(view) { line in
            if remove { return line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : line }
            return line.isEmpty ? line : prefix + line
        }
    }

    /// Return in a list or quote continues it; Return on an empty item ends it. Returns false otherwise.
    static func continueBlock(_ view: NSTextView) -> Bool {
        let text = view.string as NSString
        let caret = view.selectedRange()
        guard caret.length == 0 else { return false }
        let lineRange = text.lineRange(for: NSRange(location: caret.location, length: 0))
        let line = text.substring(with: NSRange(location: lineRange.location, length: caret.location - lineRange.location))
        guard let m = line.firstMatch(of: #/^([ \t]*)(?:([-*+])|(\d{1,9})([.)])|(>))([ \t]+)(\[[ xX]\][ \t]+)?/#) else { return false }
        if line.count == m.output.0.count { // empty item: end the list
            view.insertText("", replacementRange: NSRange(location: lineRange.location, length: (line as NSString).length))
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

/// The Write view's text view: Markdown styled as rendered, markup hidden off the caret's lines.
@MainActor
final class WritingHandle: TextViewHandle, NSLayoutManagerDelegate {
    private var revealed = NSRange(location: NSNotFound, length: 0)
    /// Fenced code blocks, rescanned only when an edit could change fence structure; otherwise shifted.
    private var fences: [(range: NSRange, markers: [NSRange])] = []
    private var edited: NSRange?
    private var fenceEdit = false
    private var mouseUp: Any?

    override func configure(_ view: NSTextView) {
        view.font = .systemFont(ofSize: MarkdownStyler.bodySize)
        view.textContainerInset = NSSize(width: Theme.s5, height: Theme.s4)
        view.layoutManager?.delegate = self // TextKit 1 for per-glyph hiding
        view.layoutManager?.allowsNonContiguousLayout = true // large files: lay out only what's visible
        // Reveal follows the caret only after a click or drag ends, so the line doesn't reflow under the mouse.
        mouseUp = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            if let self, event.window === self.view?.window { DispatchQueue.main.async { self.updateReveal() } }
            return event
        }
        restyle(nil)
    }

    deinit { if let mouseUp { NSEvent.removeMonitor(mouseUp) } }

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
        restyle(fenceEdit ? nil : edited)
        edited = nil
        fenceEdit = false
    }

    override func didSync(changed: NSRange, removed: String, delta: Int) {
        noteEdit(at: changed.location, removedLength: changed.length - delta, insertedLength: changed.length,
                 changedText: removed + ((view?.string ?? "") as NSString).substring(with: changed))
        if startsFence(changed) { fenceEdit = true }
        restyle(fenceEdit ? nil : changed)
        fenceEdit = false
    }

    override func textViewDidChangeSelection(_ notification: Notification) {
        super.textViewDidChangeSelection(notification)
        // Mid-sync the storage is still being edited; didSync restyles once it settles.
        guard !isUpdating else { return }
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
            button("Heading", "textformat.size", help: "Cycle heading level") { MarkdownFormat.heading($0) }
            button("Bold", "bold", help: "Bold (⌘B)") { MarkdownFormat.wrap($0, marker: "**") }
            button("Italic", "italic", help: "Italic (⌘I)") { MarkdownFormat.wrap($0, marker: "*") }
            button("Link", "link", help: "Link (⌘K)") { MarkdownFormat.link($0) }
            button("Bulleted List", "list.bullet", help: "Bulleted list") { MarkdownFormat.togglePrefix($0, "- ") }
            button("Quote", "text.quote", help: "Block quote") { MarkdownFormat.togglePrefix($0, "> ") }
            Spacer()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, Theme.s2)
        .padding(.vertical, Theme.s1)
    }

    /// Shortcuts live in the Format menu (so they work in either pane); the bar is for the pointer.
    private func button(_ title: String, _ symbol: String, help: String, action: @escaping (NSTextView) -> Void) -> some View {
        Button { if let view = target() { action(view); view.window?.makeFirstResponder(view) } } label: {
            Label(title, systemImage: symbol)
        }
        .help(help)
        .accessibilityLabel(title)
    }
}
