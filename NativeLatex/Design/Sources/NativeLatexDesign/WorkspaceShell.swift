import SwiftUI

// MARK: - Models the shell displays (the app owns the real state)

public enum BuildState: Equatable, Sendable {
    case idle
    case building
    case succeeded
    case failed
    /// Sources changed or the last build failed; the shown PDF is older than the source.
    case stale

    var title: String {
        switch self {
        case .idle: "Ready"
        case .building: "Building…"
        case .succeeded: "Built"
        case .failed: "Build failed"
        case .stale: "Preview out of date"
        }
    }

    var symbol: String {
        switch self {
        case .idle: "circle"
        case .building: "hammer"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .stale: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .idle, .building: Theme.secondary
        case .succeeded: Theme.success
        case .failed: Theme.error
        case .stale: Theme.warning
        }
    }
}

public struct Problem: Identifiable, Hashable, Sendable {
    public enum Severity: Int, Comparable, Sendable {
        case error, warning, info
        public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    public let id: UUID
    public var severity: Severity
    public var message: String
    public var file: String?
    public var line: Int?

    public init(id: UUID = UUID(), severity: Severity, message: String, file: String? = nil, line: Int? = nil) {
        self.id = id; self.severity = severity; self.message = message; self.file = file; self.line = line
    }
}

public struct SourceTab: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var isDirty: Bool

    public init(id: String, title: String, isDirty: Bool = false) {
        self.id = id; self.title = title; self.isDirty = isDirty
    }
}

/// Cursor and build facts for the bottom status bar.
public struct ShellStatus: Equatable, Sendable {
    public var errors: Int
    public var warnings: Int
    public var line: Int
    public var column: Int
    public var lastBuild: Duration?

    public init(errors: Int = 0, warnings: Int = 0, line: Int = 1, column: Int = 1, lastBuild: Duration? = nil) {
        self.errors = errors; self.warnings = warnings; self.line = line; self.column = column; self.lastBuild = lastBuild
    }
}

// MARK: - Window shell

/// Workspace window layout from the UX plan:
/// toolbar (sidebar · title/root · Build · state · preview · BB-8), files sidebar,
/// editor | preview split, optional problems panel, status bar.
/// Below `narrowWidth` the preview replaces the editor when toggled instead of squeezing a column.
public struct WorkspaceShell<Sidebar: View, Editor: View, Preview: View, Panel: View>: View {
    let title: String
    let subtitle: String
    let buildState: BuildState
    let status: ShellStatus
    @Binding var showPreview: Bool
    @Binding var showPanel: Bool
    let onBuild: () -> Void
    let sidebar: Sidebar, editor: Editor, preview: Preview, panel: Panel

    var narrowWidth: CGFloat = 760

    public init(
        title: String,
        subtitle: String = "",
        buildState: BuildState,
        status: ShellStatus,
        showPreview: Binding<Bool>,
        showPanel: Binding<Bool>,
        onBuild: @escaping () -> Void,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder editor: () -> Editor,
        @ViewBuilder preview: () -> Preview,
        @ViewBuilder panel: () -> Panel
    ) {
        self.title = title; self.subtitle = subtitle; self.buildState = buildState; self.status = status
        _showPreview = showPreview; _showPanel = showPanel; self.onBuild = onBuild
        self.sidebar = sidebar(); self.editor = editor(); self.preview = preview(); self.panel = panel()
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 360)
        } detail: {
            VStack(spacing: 0) {
                VSplitView {
                    GeometryReader { geo in
                        content(narrow: geo.size.width < narrowWidth)
                    }
                    .frame(minHeight: 200, maxHeight: .infinity)
                    .layoutPriority(1)
                    if showPanel {
                        panel.frame(minHeight: 80, idealHeight: 160, maxHeight: 400)
                    }
                }
                StatusBar(status: status, showPanel: $showPanel)
            }
            .background(Theme.background)
        }
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: onBuild) {
                    Label("Build", systemImage: "hammer")
                }
                .keyboardShortcut("b")
                .disabled(buildState == .building)
                .help("Build (⌘B)")

                BuildStatusBadge(state: buildState)

                Toggle(isOn: $showPreview) {
                    Label("Preview", systemImage: "sidebar.right")
                }
                .help(showPreview ? "Hide Preview" : "Show Preview")

                BB8Toggle()
            }
        }
        .tint(Theme.accent)
    }

    @ViewBuilder private func content(narrow: Bool) -> some View {
        if narrow {
            if showPreview { preview } else { editor }
        } else {
            HSplitView {
                editor.frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                if showPreview {
                    preview.frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

// MARK: - Pieces

/// Text + symbol + color, so color never carries the state alone.
public struct BuildStatusBadge: View {
    let state: BuildState
    public init(state: BuildState) { self.state = state }

    public var body: some View {
        HStack(spacing: 6) {
            if state == .building {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: state.symbol).foregroundStyle(state.color)
            }
            Text(state.title).foregroundStyle(Theme.secondary)
        }
        .font(Theme.captionFont)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Build status: \(state.title)")
    }
}

/// Bottom bar: problem counts (toggle the panel), cursor position, last build time.
public struct StatusBar: View {
    let status: ShellStatus
    @Binding var showPanel: Bool

    public init(status: ShellStatus, showPanel: Binding<Bool>) {
        self.status = status; _showPanel = showPanel
    }

    public var body: some View {
        HStack(spacing: Theme.s4) {
            Button { showPanel.toggle() } label: {
                HStack(spacing: Theme.s3) {
                    Label("\(status.errors) \(status.errors == 1 ? "error" : "errors")", systemImage: "xmark.octagon")
                        .foregroundStyle(status.errors > 0 ? Theme.error : Theme.secondary)
                    Label("\(status.warnings) \(status.warnings == 1 ? "warning" : "warnings")", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(status.warnings > 0 ? Theme.warning : Theme.secondary)
                }
            }
            .buttonStyle(.plain)
            .help(showPanel ? "Hide Problems" : "Show Problems")

            Spacer()
            Text("Ln \(status.line), Col \(status.column)")
            if let lastBuild = status.lastBuild {
                Text(lastBuild.formatted(.units(allowed: [.seconds], width: .narrow, fractionalPart: .show(length: 1))))
                    .accessibilityLabel("Last build took \(lastBuild.formatted())")
            }
        }
        .font(Theme.captionFont)
        .monospacedDigit()
        .foregroundStyle(Theme.secondary)
        .padding(.horizontal, Theme.s3)
        .frame(height: 24)
        .background(Theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

/// Source tabs above the editor: accent underline on the selected tab, dot for unsaved changes.
public struct SourceTabBar: View {
    let tabs: [SourceTab]
    @Binding var selection: SourceTab.ID?
    let onClose: (SourceTab.ID) -> Void

    public init(tabs: [SourceTab], selection: Binding<SourceTab.ID?>, onClose: @escaping (SourceTab.ID) -> Void = { _ in }) {
        self.tabs = tabs; _selection = selection; self.onClose = onClose
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(tabs) { tab in
                    let selected = tab.id == selection
                    HStack(spacing: 6) {
                        Button(tab.title) { selection = tab.id }
                            .buttonStyle(.plain)
                            .foregroundStyle(selected ? Theme.foreground : Theme.secondary)
                        Button { onClose(tab.id) } label: {
                            Image(systemName: tab.isDirty ? "circle.fill" : "xmark")
                                .font(.system(size: tab.isDirty ? 6 : 9, weight: .bold))
                                .frame(width: 14, height: 14)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.secondary)
                        .accessibilityLabel(tab.isDirty ? "Close \(tab.title), unsaved changes" : "Close \(tab.title)")
                    }
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .padding(.horizontal, Theme.s3)
                    .frame(height: 30)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(selected ? Theme.accent : .clear).frame(height: 2)
                    }
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .frame(height: 30)
        .background(Theme.background)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

/// Problems panel list, sorted by severity then position. Selecting a row reports it to the app.
public struct ProblemList: View {
    let problems: [Problem]
    let onSelect: (Problem) -> Void

    public init(problems: [Problem], onSelect: @escaping (Problem) -> Void = { _ in }) {
        self.problems = problems.sorted { ($0.severity, $0.file ?? "", $0.line ?? 0) < ($1.severity, $1.file ?? "", $1.line ?? 0) }
        self.onSelect = onSelect
    }

    public var body: some View {
        List(problems) { problem in
            Button { onSelect(problem) } label: {
                HStack(alignment: .firstTextBaseline, spacing: Theme.s2) {
                    Image(systemName: icon(problem.severity)).foregroundStyle(color(problem.severity))
                    Text(problem.message).foregroundStyle(Theme.foreground)
                    Spacer()
                    if let file = problem.file {
                        Text(problem.line.map { "\(file):\($0)" } ?? file)
                            .font(Theme.editorFont)
                            .foregroundStyle(Theme.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(String(describing: problem.severity)), \(problem.message)\(problem.file.map { ", \($0)" } ?? "")\(problem.line.map { " line \($0)" } ?? "")")
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.surface)
    }

    private func icon(_ s: Problem.Severity) -> String {
        switch s {
        case .error: "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    private func color(_ s: Problem.Severity) -> Color {
        switch s {
        case .error: Theme.error
        case .warning: Theme.warning
        case .info: Theme.accentText
        }
    }
}
