import AppKit
import NativeLatexDesign
import SwiftUI

/// LibreLeaf sample window built only from NativeLatexDesign components.
/// `swift run NativeLatexDesignDemo` opens it; `--snapshot <dir>` writes light/dark PNGs and quits.
@main
struct DemoApp: App {
    @NSApplicationDelegateAdaptor(SnapshotDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("LibreLeaf") {
            SampleWorkspace()
                .frame(minWidth: 640, minHeight: 420)
        }
        .defaultSize(width: 1180, height: 720)
        .commands { AppearanceCommands() }

        Settings { AppearanceSettingsView() }
    }
}

struct SampleWorkspace: View {
    @State private var showPreview = true
    @State private var showPanel = true
    @State private var tab: SourceTab.ID? = "main.tex"
    @State private var file: String? = "main.tex"
    @State private var state: BuildState = .failed

    private let tabs = [SourceTab(id: "main.tex", title: "main.tex", isDirty: true), SourceTab(id: "intro.tex", title: "intro.tex"), SourceTab(id: "notes.md", title: "notes.md")]
    private let problems = [
        Problem(severity: .warning, message: "Citation 'knuth84' undefined", file: "intro.tex", line: 14),
        Problem(severity: .error, message: "Undefined control sequence \\begn", file: "main.tex", line: 12),
    ]

    var body: some View {
        WorkspaceShell(
            title: "LibreLeaf — thesis",
            subtitle: "main.tex",
            buildState: state,
            status: ShellStatus(errors: 1, warnings: 1, line: 12, column: 4, lastBuild: .milliseconds(1240)),
            showPreview: $showPreview,
            showPanel: $showPanel,
            onBuild: { state = .building }
        ) {
            List(["main.tex", "intro.tex", "refs.bib", "notes.md", "figures"], id: \.self, selection: $file) { name in
                Label(name, systemImage: name == "figures" ? "folder" : "doc.text")
            }
        } editor: {
            VStack(spacing: 0) {
                SourceTabBar(tabs: tabs, selection: $tab)
                ScrollView {
                    Text(Self.source)
                        .font(Theme.editorFont)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.s4)
                        .textSelection(.enabled)
                }
            }
            .background(Theme.background)
        } preview: {
            ZStack {
                Theme.surface
                // PDF pages keep their real white paper and dark ink in both appearances.
                let ink = Color(red: 0.07, green: 0.07, blue: 0.07)
                VStack(alignment: .leading, spacing: 10) {
                    Text("LibreLeaf: A Thesis").font(.system(size: 18, weight: .bold, design: .serif)).foregroundColor(ink)
                    Text("1  Introduction").font(.system(size: 13, weight: .semibold, design: .serif)).foregroundColor(ink)
                    Text("Writing in ordinary folders, compiled with the local TeX installation.").font(.system(size: 11, design: .serif)).foregroundColor(ink)
                    Spacer()
                }
                .environment(\.colorScheme, .light)
                .padding(28)
                .frame(width: 300, height: 390)
                .background(.white)
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
            }
        } panel: {
            ProblemList(problems: problems)
        }
    }

    static let source = """
    \\documentclass{article}
    \\usepackage{amsmath}

    \\title{LibreLeaf: A Thesis}
    \\begin{document}
    \\maketitle

    \\input{intro}

    \\section{Method}
    Let $f(x) = \\sum_{k=0}^{n} a_k x^k$.
    \\begn{equation}
      E = mc^2
    \\end{equation}
    \\end{document}
    """
}

@MainActor
final class SnapshotDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        Task { @MainActor in
            for mode in [AppAppearance.light, .dark] {
                AppearanceStore.shared.mode = mode
                try? await Task.sleep(for: .seconds(1.5))
                for (name, view) in [("shell", NSApp.windows.first { $0.isVisible }?.contentView?.superview),
                                     ("bb8", Self.hostBB8(night: mode == .dark))] {
                    guard let view else { continue }
                    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name)-\(mode.rawValue).png"))
                }
            }
            AppearanceStore.shared.mode = .system
            NSApp.terminate(nil)
        }
    }

    static func hostBB8(night: Bool) -> NSView {
        let host = NSHostingView(rootView: BB8Artwork(night: night, em: 16).padding(16).background(Theme.background))
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        return host
    }
}
