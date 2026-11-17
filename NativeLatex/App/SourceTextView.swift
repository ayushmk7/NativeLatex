import AppKit
import NativeLatexDesign
import SwiftUI

/// Owns one pane's NSTextView for the window's lifetime and is its delegate. Keeping both here (not in a
/// SwiftUI coordinator) means a hidden pane's view keeps its caret, scroll and undo history, stays in sync
/// with the buffer, and still writes to the document when ⌘Z undoes one of its edits while it is hidden.
@MainActor
class TextViewHandle: NSObject, ObservableObject, NSTextViewDelegate {
    weak var view: NSTextView?
    var scroll: NSScrollView?
    /// The window this pane was last shown in; stays set while the pane is hidden, for moving focus.
    weak var window: NSWindow?
    /// Set by the representable each update: writes the buffer / reports the caret line and column.
    var onText: ((String) -> Void)?
    var onCursor: ((Int, Int) -> Void)?
    /// True while `sync` rewrites the view; edits and selection changes then come from the other pane, not the user.
    private(set) var isUpdating = false

    func focus() {
        guard let view else { return }
        view.window?.makeFirstResponder(view)
    }

    func reveal(line: Int) {
        guard let view else { return }
        let text = view.string as NSString
        var start = 0
        for _ in 1..<max(line, 1) where start < text.length {
            start = NSMaxRange(text.lineRange(for: NSRange(location: start, length: 0)))
        }
        let range = text.lineRange(for: NSRange(location: min(start, text.length), length: 0))
        view.window?.makeFirstResponder(view)
        view.setSelectedRange(range)
        view.scrollRangeToVisible(range)
        view.showFindIndicator(for: range)
    }

    /// Brings the view to `text` after a change made elsewhere (other pane, revert, undo). Only the span that
    /// differs is replaced (no undo registered here), so attributes, layout and the caret elsewhere stay put.
    func sync(_ text: String) {
        guard let view, let storage = view.textStorage else { return }
        // Compared in place (the storage's own string, no copies), so a keystroke in the other pane costs a
        // memory scan, not two full-text copies: ~1 ms at 1 MiB instead of ~150 ms.
        let old: NSString = storage.mutableString, new = text as NSString
        let (prefix, suffix) = Self.commonEnds(old, new)
        if prefix == old.length, old.length == new.length { return } // already showing this text
        let replaced = NSRange(location: prefix, length: old.length - prefix - suffix)
        let piece = new.substring(with: NSRange(location: prefix, length: new.length - prefix - suffix))
        let delta = (piece as NSString).length - replaced.length
        let selection = view.selectedRange()
        let removed = old.substring(with: replaced)
        isUpdating = true
        storage.replaceCharacters(in: replaced, with: piece)
        var caret = selection.location
        if caret >= NSMaxRange(replaced) { caret += delta } else if caret > prefix { caret = prefix + (piece as NSString).length }
        view.setSelectedRange(NSRange(location: min(caret, storage.length), length: 0))
        isUpdating = false
        didSync(changed: NSRange(location: prefix, length: (piece as NSString).length), removed: removed, delta: delta)
    }

    /// Lengths of the common UTF-16 prefix and (non-overlapping) suffix of `a` and `b`, read in chunks.
    nonisolated static func commonEnds(_ a: NSString, _ b: NSString) -> (prefix: Int, suffix: Int) {
        let shorter = min(a.length, b.length), chunk = 4096
        var x = [unichar](repeating: 0, count: chunk), y = [unichar](repeating: 0, count: chunk)
        var prefix = 0
        scan: while prefix < shorter {
            let n = min(chunk, shorter - prefix)
            a.getCharacters(&x, range: NSRange(location: prefix, length: n))
            b.getCharacters(&y, range: NSRange(location: prefix, length: n))
            for i in 0..<n where x[i] != y[i] { prefix += i; break scan }
            prefix += n
        }
        var suffix = 0
        scan: while suffix < shorter - prefix {
            let n = min(chunk, shorter - prefix - suffix)
            a.getCharacters(&x, range: NSRange(location: a.length - suffix - n, length: n))
            b.getCharacters(&y, range: NSRange(location: b.length - suffix - n, length: n))
            for i in stride(from: n - 1, through: 0, by: -1) where x[i] != y[i] { suffix += n - 1 - i; break scan }
            suffix += n
        }
        return (prefix, suffix)
    }

    /// Subclasses restyle here.
    func didSync(changed: NSRange, removed: String, delta: Int) {}

    /// The pane's scroll view, made once. Smart quotes/dashes and autocorrect are off, so LaTeX and
    /// Markdown are never rewritten behind the user's back.
    func scrollView(text: String, label: String) -> NSScrollView {
        if let scroll { return scroll }
        let scroll = NSTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.usesFindBar = true
        view.isIncrementalSearchingEnabled = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.layoutManager?.allowsNonContiguousLayout = true // large files: lay out only what's visible
        view.font = .monospacedSystemFont(ofSize: 13, weight: .regular) // Theme.editorFont
        view.textContainerInset = NSSize(width: Theme.s3, height: Theme.s3)
        view.backgroundColor = NSColor(Theme.background)
        view.textColor = NSColor(Theme.foreground)
        view.insertionPointColor = NSColor(Theme.accent)
        scroll.backgroundColor = NSColor(Theme.background)
        // Set before the delegate: setting `string` fires a selection change.
        view.string = text
        view.setAccessibilityLabel(label)
        view.delegate = self
        self.view = view
        self.scroll = scroll
        configure(view)
        return scroll
    }

    /// Subclasses adjust the new view.
    func configure(_ view: NSTextView) {}

    func textDidChange(_ notification: Notification) {
        guard !isUpdating, let view = notification.object as? NSTextView else { return }
        onText?(view.string)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isUpdating, let view = notification.object as? NSTextView else { return }
        // Counts newlines up to the caret in chunks of the storage itself (no copy of the text), so large
        // files stay responsive.
        let text: NSString = view.textStorage?.mutableString ?? (view.string as NSString)
        let caret = min(view.selectedRange().location, text.length)
        var line = 1, lineStart = 0, index = 0
        var buffer = [unichar](repeating: 0, count: 4096)
        while index < caret {
            let n = min(buffer.count, caret - index)
            text.getCharacters(&buffer, range: NSRange(location: index, length: n))
            for i in 0..<n where buffer[i] == 10 { line += 1; lineStart = index + i + 1 }
            index += n
        }
        onCursor?(line, text.substring(with: NSRange(location: lineStart, length: caret - lineStart)).count + 1)
    }
}

/// Hosts a handle's text view; a fresh container each time, the scroll view inside is reused.
struct HandleTextView: NSViewRepresentable {
    @Binding var text: String
    let handle: TextViewHandle
    var label = "Source"
    var onCursor: (_ line: Int, _ column: Int) -> Void = { _, _ in }

    func makeNSView(context: Context) -> NSView {
        let scroll = handle.scrollView(text: text, label: label)
        let container = PaneContainer()
        container.handle = handle
        scroll.frame = container.bounds
        scroll.autoresizingMask = [.width, .height]
        container.addSubview(scroll) // moves it out of the previous container, if any
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        let binding = $text
        handle.onText = { binding.wrappedValue = $0 }
        handle.onCursor = onCursor
        handle.sync(text)
    }
}

/// Records its handle's window when shown.
final class PaneContainer: NSView {
    weak var handle: TextViewHandle?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { handle?.window = window }
    }
}

/// Plain-text source editor.
typealias SourceTextView = HandleTextView
