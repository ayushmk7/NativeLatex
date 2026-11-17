import AppKit
import NativeLatexDesign
import SwiftUI

/// Lets the window jump the editor to a line (Problems panel) without owning the NSTextView.
@MainActor
final class TextViewHandle: ObservableObject {
    weak var view: NSTextView?

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
}

/// Plain-text source editor. Unlike `TextEditor`, smart quotes/dashes and autocorrect are off,
/// so LaTeX and Markdown are never rewritten behind the user's back.
struct SourceTextView: NSViewRepresentable {
    @Binding var text: String
    let handle: TextViewHandle
    var onCursor: (_ line: Int, _ column: Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        view.delegate = context.coordinator
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
        view.string = text
        view.setAccessibilityLabel("Source")
        handle.view = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
        // External change (revert, reload): keep the caret where it was, clamped.
        let location = min(view.selectedRange().location, (text as NSString).length)
        context.coordinator.isUpdating = true
        view.string = text
        view.setSelectedRange(NSRange(location: location, length: 0))
        context.coordinator.isUpdating = false
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SourceTextView
        var isUpdating = false

        init(_ parent: SourceTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdating, let view = notification.object as? NSTextView else { return }
            // ponytail: O(caret offset) scan per selection change; fine for source files, index lines if huge files lag.
            let prefix = (view.string as NSString).substring(to: min(view.selectedRange().location, (view.string as NSString).length))
            let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
            parent.onCursor(lines.count, (lines.last?.count ?? 0) + 1)
        }
    }
}
