import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The formats File > New… offers.
enum NewDocumentKind: CaseIterable {
    case latex, markdown, plainText

    var type: UTType {
        switch self {
        case .latex: .tex
        case .markdown: .markdown
        case .plainText: .plainText
        }
    }

    var title: String {
        switch self {
        case .latex: "LaTeX (.tex)"
        case .markdown: "Markdown (.md)"
        case .plainText: "Plain Text (.txt)"
        }
    }
}

@MainActor
enum NewDocument {
    /// Opens a new window with an untitled, never-saved document of `kind`. It has no file URL,
    /// so nothing touches disk until the first ⌘S, whose Save panel suggests the kind's extension.
    /// DocumentGroup's own controller makes the document, so it behaves like any other window
    /// (tabs, Window menu, autosave, Save As).
    @discardableResult
    static func open(_ kind: NewDocumentKind) throws -> NSDocument {
        let controller = NSDocumentController.shared
        let document = try controller.makeUntitledDocument(ofType: kind.type.identifier)
        controller.addDocument(document)
        document.makeWindowControllers()
        document.showWindows()
        return document
    }

    static func chooser() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "New Document"
        alert.informativeText = "Choose a format. You’ll name and save the document the first time you save it."
        for kind in NewDocumentKind.allCases { alert.addButton(withTitle: kind.title) }
        alert.addButton(withTitle: "Cancel") // NSAlert maps Esc to a button titled Cancel
        return alert
    }

    /// File > New… (⌘N): ask for the format every time, then open the untitled document.
    static func choose() {
        let index = chooser().runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard NewDocumentKind.allCases.indices.contains(index) else { return } // Cancel
        do { try open(NewDocumentKind.allCases[index]) } catch { NSApp.presentError(error) }
    }
}

/// Replaces only DocumentGroup's New item; Open…, Open Recent, Save and the rest stay native.
struct NewDocumentCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New…") { NewDocument.choose() }
                .keyboardShortcut("n")
        }
    }
}
