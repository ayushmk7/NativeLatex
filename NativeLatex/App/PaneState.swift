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

    /// What the window shows: no preview for plain text; a narrow window can't show both.
    func shown(narrow: Bool, hasPreview: Bool = true) -> PaneLayout {
        guard hasPreview else { return .source }
        if write { return .preview }
        return narrow && layout == .both ? .source : layout
    }

    /// A layout chosen from the toolbar or View menu. Source Only and Source and Preview leave Write
    /// (the mode control then says Read); Preview Only keeps the current mode.
    mutating func choose(_ new: PaneLayout) {
        if new != .preview { write = false }
        beforeWrite = nil
        layout = new
    }

    /// Write fills the window and remembers the layout it replaced. Read returns to that layout, except
    /// that Source Only comes back as Source and Preview (Preview Only when narrow), so Read is visible.
    mutating func setWrite(_ on: Bool, narrow: Bool) {
        if on {
            if !write { beforeWrite = layout }
            layout = .preview
        } else {
            let back = beforeWrite ?? layout
            layout = back == .source ? (narrow ? .preview : .both) : back
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
        s.setWrite(true, narrow: false); s.choose(.both); expect(s, .both, write: false, "Source and Preview leaves Write")
        s.setWrite(true, narrow: false); s.choose(s.shown(narrow: false).toggled(narrow: false))
        expect(s, .source, write: false, "⌥⌘P from Write shows Source, mode Read")
        s = PaneState(); s.choose(.source); s.setWrite(true, narrow: true); s.setWrite(false, narrow: true)
        expect(s, .preview, write: false, narrow: true, "narrow: Read after Source → Write shows Read alone")
        s = PaneState(); expect(s, .source, write: false, narrow: true, "narrow: Both shows Source")
        s.setWrite(true, narrow: true); expect(s, .preview, write: true, narrow: true, "narrow: Write fills the window")
        if PaneState().shown(narrow: false, hasPreview: false) != .source { failures.append("plain text: source only") }
        return failures
    }
    #endif
}

