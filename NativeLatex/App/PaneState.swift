/// Source Only, Source and Preview, or Preview Only.
enum PaneLayout: Hashable {
    case source, both, preview

    /// ⌥⌘P: hide the preview, or bring it back beside the source (alone if the window is narrow).
    func toggled(narrow: Bool) -> PaneLayout { self == .source ? (narrow ? .preview : .both) : .source }
}

/// A window's panes and its Markdown preview mode. Write is the full-width editor, like a TextEdit
/// document: it is never a half pane beside the source, and the mode always matches what is on screen.
struct PaneState: Equatable {
    /// The requested layout; a narrow window shows Both as Source.
    var layout = PaneLayout.both
    /// Markdown only: Write (editable formatted document) instead of Read (Pandoc rendering).
    var write = false
    /// The layout Write replaced, restored by Read.
    var beforeWrite: PaneLayout?

    /// What the window shows: no preview for plain text; a narrow window can't show both. Write only
    /// applies to Markdown (a window saved as .tex shows its layout, not a leftover Write).
    func shown(narrow: Bool, hasPreview: Bool = true, markdown: Bool = true) -> PaneLayout {
        guard hasPreview else { return .source }
        if write, markdown { return .preview }
        return narrow && layout == .both ? .source : layout
    }

    /// Format commands need an editable Markdown view on screen: Write, or the source (Read in Preview Only has none).
    func canFormat(narrow: Bool, markdown: Bool) -> Bool { formatPane(narrow: narrow, markdown: markdown) != nil }

    enum Editable { case source, write }

    /// The one editable view on screen, which Format acts on: Write while writing, else the source if shown.
    /// Never the hidden one, even if it still holds focus mid-transition.
    func formatPane(narrow: Bool, markdown: Bool) -> Editable? {
        guard markdown else { return nil }
        if write { return .write }
        return shown(narrow: narrow, markdown: markdown) != .preview ? .source : nil
    }

    /// A layout chosen from the toolbar or View menu. Every layout leaves Write: the layout control shows
    /// nothing selected while Write fills the window, so choosing Preview there means the Read preview.
    mutating func choose(_ new: PaneLayout) {
        write = false
        beforeWrite = nil
        layout = new
    }

    /// Write fills the window and remembers the layout it replaced. Read returns to that layout unless Read
    /// would be hidden there (Source Only, or Both in a narrow window, which shows only the source): then it
    /// shows Source and Preview, or Preview Only when narrow. Read is never selected but off screen.
    mutating func setWrite(_ on: Bool, narrow: Bool) {
        if on {
            if !write { beforeWrite = layout }
            layout = .preview
        } else {
            let back = beforeWrite ?? layout
            let readHidden = back == .source || (narrow && back == .both)
            layout = readHidden ? (narrow ? .preview : .both) : back
            beforeWrite = nil
        }
        write = on
    }

    #if DEBUG
    /// Every transition the toolbar and View menu can make, checked without a window (the Xcode test host
    /// can't launch on every machine). Run by the unit tests, or headless: `swiftc -D DEBUG PaneState.swift main.swift`
    /// with a main.swift of `let f = PaneState.selfCheck(); print(f); precondition(f.isEmpty)`.
    static func selfCheck() -> [String] {
        var failures: [String] = []
        func expect(_ s: PaneState, _ shown: PaneLayout, write: Bool, narrow: Bool = false, _ step: String) {
            if s.shown(narrow: narrow) != shown || s.write != write { failures.append("\(step): \(s.shown(narrow: narrow)) write=\(s.write)") }
        }
        var s = PaneState()
        expect(s, .both, write: false, "default")
        s.setWrite(true, narrow: false); expect(s, .preview, write: true, "Both → Write")
        s.setWrite(false, narrow: false); expect(s, .both, write: false, "Write → Read restores Both")
        s.choose(.source); expect(s, .source, write: false, "Source Only")
        s.setWrite(true, narrow: false); expect(s, .preview, write: true, "Source → Write")
        s.setWrite(false, narrow: false); expect(s, .both, write: false, "Read after Source → Write shows Read beside source")
        s.choose(.preview); expect(s, .preview, write: false, "Preview Only is Read")
        s.setWrite(true, narrow: false); expect(s, .preview, write: true, "Read → Write")
        s.setWrite(true, narrow: false); expect(s, .preview, write: true, "Write again: no change")
        s.setWrite(false, narrow: false); expect(s, .preview, write: false, "Write → Read keeps Preview Only")
        s.setWrite(true, narrow: false); s.choose(.source); expect(s, .source, write: false, "Source Only leaves Write")
        s.choose(.preview); expect(s, .preview, write: false, "Preview Only after leaving Write is Read")
        s.setWrite(true, narrow: false); s.choose(.preview); expect(s, .preview, write: false, "Preview chosen in Write shows Read")
        s.setWrite(true, narrow: false); s.choose(.both); expect(s, .both, write: false, "Source and Preview leaves Write")
        s.setWrite(true, narrow: false); s.choose(s.shown(narrow: false).toggled(narrow: false))
        expect(s, .source, write: false, "⌥⌘P from Write shows Source, mode Read")
        s = PaneState(); s.choose(.source); s.setWrite(true, narrow: true); s.setWrite(false, narrow: true)
        expect(s, .preview, write: false, narrow: true, "narrow: Read after Source → Write shows Read alone")
        s = PaneState(); expect(s, .source, write: false, narrow: true, "narrow: Both shows Source")
        s.setWrite(true, narrow: true); expect(s, .preview, write: true, narrow: true, "narrow: Write fills the window")
        s.setWrite(false, narrow: true); expect(s, .preview, write: false, narrow: true, "narrow: Both → Write → Read shows Read, not Source")
        s = PaneState(); s.setWrite(false, narrow: true)
        expect(s, .preview, write: false, narrow: true, "narrow: Read tapped from the initial Source shows Read")
        s = PaneState(); s.choose(.source); s.setWrite(false, narrow: false)
        expect(s, .both, write: false, "Read tapped in Source Only shows Read beside the source")
        // Saved as .tex while in Write: no Write for non-Markdown, and leaving it restores the earlier layout.
        s = PaneState(); s.setWrite(true, narrow: false)
        s.setWrite(false, narrow: false); expect(s, .both, write: false, "leaving Write after a .tex save restores Both")
        var f = PaneState()
        let formats = [(f.canFormat(narrow: false, markdown: true), true, "Both: source editable"),
                       ({ f.choose(.preview); return f.canFormat(narrow: false, markdown: true) }(), false, "Read in Preview Only: nothing editable"),
                       ({ f.setWrite(true, narrow: false); return f.canFormat(narrow: false, markdown: true) }(), true, "Write"),
                       (f.canFormat(narrow: false, markdown: false), false, "not Markdown")]
        for (got, want, step) in formats where got != want { failures.append("canFormat, \(step): \(got)") }
        // Format targets only the visible editor: Write hides the source, Read Preview Only has no editor.
        var g = PaneState()
        let panes: [(Editable?, Editable?, String)] = [
            (g.formatPane(narrow: false, markdown: true), .source, "Both → source"),
            (g.formatPane(narrow: true, markdown: true), .source, "narrow Both → source"),
            ({ g.setWrite(true, narrow: false); return g.formatPane(narrow: false, markdown: true) }(), .write, "Write → write, not the hidden source"),
            ({ g.setWrite(false, narrow: false); g.choose(.preview); return g.formatPane(narrow: false, markdown: true) }(), nil, "Read Preview Only → none"),
            ({ g.choose(.source); return g.formatPane(narrow: false, markdown: true) }(), .source, "Source Only → source"),
        ]
        for (got, want, step) in panes where got != want { failures.append("formatPane, \(step): \(String(describing: got))") }
        if PaneState().shown(narrow: false, hasPreview: false) != .source { failures.append("plain text: source only") }
        return failures
    }
    #endif
}

