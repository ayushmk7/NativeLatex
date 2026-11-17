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
    /// Set by the representable each update: writes the buffer / reports the caret line and column.
    var onText: ((String) -> Void)?
    var onCursor: ((Int, Int) -> Void)?
    private var isUpdating = false

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
        guard let view, let storage = view.textStorage, view.string != text else { return }
        // ponytail: O(n) diff per sync (~50 ms at 1 MiB); track edit ranges from the other pane if that shows.
        let a = Array(view.string.utf16), b = Array(text.utf16)
        var prefix = 0
        while prefix < min(a.count, b.count), a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(a.count, b.count) - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
        let replaced = NSRange(location: prefix, length: a.count - prefix - suffix)
        let piece = (text as NSString).substring(with: NSRange(location: prefix, length: b.count - prefix - suffix))
        let delta = (piece as NSString).length - replaced.length
        let selection = view.selectedRange()
        let removed = (view.string as NSString).substring(with: replaced)
        isUpdating = true
        storage.replaceCharacters(in: replaced, with: piece)
        var caret = selection.location
        if caret >= NSMaxRange(replaced) { caret += delta } else if caret > prefix { caret = prefix + (piece as NSString).length }
        view.setSelectedRange(NSRange(location: min(caret, storage.length), length: 0))
        isUpdating = false
        didSync(changed: NSRange(location: prefix, length: (piece as NSString).length), removed: removed, delta: delta)
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
        // One pass over UTF-16 up to the caret (no substrings), so large files stay responsive.
        let text = view.string as NSString
        let caret = min(view.selectedRange().location, text.length)
        var line = 1, lineStart = 0, index = 0
        for unit in view.string.utf16 {
            if index >= caret { break }
            if unit == 10 { line += 1; lineStart = index + 1 }
            index += 1
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
        let container = NSView()
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

/// Plain-text source editor.
typealias SourceTextView = HandleTextView
