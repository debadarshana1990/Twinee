import SwiftUI
import AppKit

@main
struct TwineeApp: App {
    @StateObject private var store = WorkspaceStore()
    @AppStorage("twinee.theme") private var themeRawValue = ThemeMode.white.rawValue

    private var theme: ThemeMode { ThemeMode(rawValue: themeRawValue) ?? .white }

    var body: some Scene {
        WindowGroup {
            TwineeWindow(store: store, theme: theme) {
                themeRawValue = theme == .white ? ThemeMode.black.rawValue : ThemeMode.white.rawValue
            }
            .preferredColorScheme(theme == .white ? .light : .dark)
            .frame(minWidth: 950, minHeight: 650)
        }
        .windowToolbarStyle(.unified)
        .commands { HelpCommands() }
        Window("Twinee Help", id: "help") { HelpView() }
            .windowResizability(.contentSize)
    }
}

enum AppInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev build" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—" }
}

struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Twinee Help") { openWindow(id: "help") }.keyboardShortcut("?", modifiers: .command)
        }
    }
}

struct HelpView: View {
    private let sections: [(String, [String])] = [
        ("Code Browser", ["Paste a Git URL, pick a branch and read the code — no clone to manage.", "Open any text file; HTML files have a Preview mode. ⌘-click a name to jump to its definition.", "Right-click a line to attach a note; notes are saved per repository."]),
        ("AI chat", ["⇧⌘I opens the AI panel on the right. It reads the page you have open.", "Choose GitHub Copilot, Gemini, Claude or Codex. Each uses the command-line tool installed on your Mac."]),
        ("Shortcuts", ["⌘\\  hide or show the sidebar", "⇧⌘I  AI chat", "⌘S  save the page", "⌘B / ⌘I / ⌘U  bold, italic, underline"]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 48, height: 48).background(Brand.gradient, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Twinee").font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("Version \(AppInfo.version) (build \(AppInfo.build))").font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            Divider()
            ForEach(sections, id: \.0) { section in
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.0).font(.system(size: 12, weight: .bold))
                    ForEach(section.1, id: \.self) { line in Text("• " + line).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
            }
            Text("Your notes live on this Mac in ~/Library/Application Support/Twinee.").font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(24).frame(width: 520)
    }
}

enum ThemeMode: String, CaseIterable, Identifiable {
    case white = "White"
    case black = "Black"
    var id: String { rawValue }
}

final class WorkspaceStore: ObservableObject {
    @Published var todos: [TodoItem] = []
    @Published var todoScope: TodoScope? { didSet { if todoScope != nil { activeApp = nil } } }
    @Published var activeApp: DevApp?

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("Twinee", isDirectory: true)
        fileURL = directory.appendingPathComponent("workspace.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder.twinee.decode(WorkspaceData.self, from: data) {
            todos = saved.todos
        }
        activeApp = .tablespoon
    }

    func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.twinee.encode(WorkspaceData(todos: todos))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Twinee could not save the local workspace: %@", error.localizedDescription)
        }
    }
}

// Older workspace files also hold projects and pages; only the tasks are kept.
struct WorkspaceData: Codable {
    var todos: [TodoItem]

    init(todos: [TodoItem] = []) { self.todos = todos }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        todos = try values.decodeIfPresent([TodoItem].self, forKey: .todos) ?? []
    }

    private enum CodingKeys: String, CodingKey { case todos }
}

struct TwineeWindow: View {
    @ObservedObject var store: WorkspaceStore
    let theme: ThemeMode
    let toggleTheme: () -> Void
    @State private var searchText = ""
    @AppStorage("twinee.sidebarHidden") private var sidebarHidden = false
    @State private var hoverSidebar = false
    @StateObject private var ai = AIChatModel()
    @AppStorage("twinee.aiVisible") private var aiVisible = false
    @AppStorage("twinee.aiWidth") private var aiWidth = 340.0
    @StateObject private var compare = CompareModel()
    @StateObject private var codeBrowser = CodeBrowserModel()
    @StateObject private var tableSpoon = TableSpoonModel()
    @StateObject private var git = GitModel()
    @StateObject private var timer = TimerModel()
    @ObservedObject private var tools = DevToolsStore.shared
    @State private var launcherExpanded = true
    @AppStorage("twinee.sidebarWidth") private var sidebarWidth = 258.0
    @State private var showingNewStudyTopic = false
    @State private var studyTopicName = ""
    @State private var subtopicParent: TSNode?
    @State private var subtopicName = ""
    @State private var tagTarget: TSNode?
    @State private var tagText = ""

    private var palette: Palette { Palette(theme) }
    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                if !sidebarHidden {
                    sidebar
                    ResizeDivider(width: $sidebarWidth, range: 200...460, palette: palette)
                }
                pageContent
                if aiVisible {
                    ResizeDivider(width: $aiWidth, range: 260...620, palette: palette, invert: true)
                    AIChatPanel(model: ai, context: pageContext, palette: palette) { aiVisible = false }
                        .frame(width: aiWidth)
                }
            }
            if sidebarHidden {
                // Thin hot zone on the left edge; moving the mouse there slides the sidebar over the page.
                Image(systemName: "chevron.compact.right").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 14, height: 54).background(Brand.gradient, in: UnevenRoundedRectangle(bottomTrailingRadius: 8, topTrailingRadius: 8))
                    .frame(width: 14).contentShape(Rectangle())
                    .frame(maxHeight: .infinity)
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.18)) { sidebarHidden = false; hoverSidebar = false } }
                    .onHover { if $0 { withAnimation(.easeOut(duration: 0.15)) { hoverSidebar = true } } }
                if hoverSidebar {
                    HStack(spacing: 0) {
                        sidebar
                        Rectangle().fill(palette.border).frame(width: 1)
                    }
                    .shadow(color: .black.opacity(0.22), radius: 14, x: 4)
                    .transition(.move(edge: .leading))
                    .onHover { if !$0 { withAnimation(.easeIn(duration: 0.15)) { hoverSidebar = false } } }
                    .zIndex(2)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { aiVisible.toggle() } label: { Image(systemName: "sparkles") }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                    .help(aiVisible ? "Hide AI chat (⇧⌘I)" : "Ask Copilot, Gemini or another AI about this page (⇧⌘I)")
            }
            ToolbarItem(placement: .navigation) {
                Button { withAnimation(.easeInOut(duration: 0.18)) { sidebarHidden.toggle(); hoverSidebar = false } } label: { Image(systemName: "sidebar.left") }
                    .keyboardShortcut("\\", modifiers: .command)
                    .help(sidebarHidden ? "Pin the sidebar (⌘\\)" : "Hide the sidebar for a full page (⌘\\)")
            }
        }
        .onChange(of: store.activeApp) { _ in hoverSidebar = false }
        .onChange(of: store.todoScope) { _ in hoverSidebar = false }
        .foregroundStyle(palette.text)
        .background(palette.background)
    }

    // What the AI panel can read: the page currently on screen.
    private var pageContext: PageContext? {
        if let app = store.activeApp {
            if app == .tablespoon {
                guard let path = tableSpoon.openPath else { return nil }
                return PageContext(title: tableSpoon.relativePath(path), kind: "study file in TableSpoon", text: tableSpoon.text)
            }
            guard app == .code, let path = codeBrowser.currentPath else { return nil }
            let line = codeBrowser.selectedLine + 1
            return PageContext(title: codeBrowser.relativePath(path), kind: "source file (\(codeBrowser.language.name))", text: codeBrowser.text,
                               note: "The cursor is near line \(line).\(codeBrowser.remote.map { " It comes from \($0.url) on branch \($0.branch)." } ?? "")")
        }
        if let scope = store.todoScope {
            let items = store.todos
            let text = items.map { "- [\($0.status.title)] \($0.title)\($0.notes.map { " — " + $0 } ?? "")" }.joined(separator: "\n")
            return PageContext(title: "ToDo board", kind: "task board", text: text.isEmpty ? "(no tasks)" : text)
        }
        return nil
    }

    @ViewBuilder
    private var pageContent: some View {
        if let app = store.activeApp {
            appView(app)
        } else if store.todoScope != nil {
            TodoBoard(store: store, palette: palette, theme: theme, toggleTheme: toggleTheme)
        } else {
            Color.clear
        }
    }

    private var tableSpoonSection: some View {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let rows: [(node: TSNode, depth: Int)] = query.isEmpty ? tableSpoon.visibleRows() : tableSpoon.search(query).map { ($0, 0) }
        let bookmarks = tableSpoon.bookmarkedNodes
        let tags = tableSpoon.allTags
        return VStack(spacing: 2) {
            HStack {
                Button { store.openApp(.tablespoon) } label: {
                    Text("TABLESPOON").font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(store.activeApp == .tablespoon ? palette.accent : palette.muted)
                }.buttonStyle(.plain).help("Open TableSpoon")
                Spacer()
                Button { studyTopicName = ""; showingNewStudyTopic = true } label: { Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).frame(width: 24, height: 24).foregroundStyle(palette.muted).background(palette.surface, in: RoundedRectangle(cornerRadius: 6)) }.buttonStyle(.plain).help("New study topic")
            }.padding(.horizontal, 6).padding(.bottom, 3)
            if query.isEmpty && !bookmarks.isEmpty {
                sidebarHeading("BOOKMARKS", symbol: "bookmark.fill")
                ForEach(bookmarks) { node in studyRow(node, depth: 0) }
                Divider().padding(.vertical, 5)
            }
            if query.isEmpty && !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(tags, id: \.self) { tag in
                            Button { searchText = "#" + tag } label: {
                                Text("#" + tag).font(.system(size: 9, weight: .medium)).padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(palette.accent.opacity(0.14), in: Capsule()).foregroundStyle(palette.accent)
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 6)
                }.padding(.bottom, 6)
            }
            ForEach(rows, id: \.node.id) { row in
                studyRow(row.node, depth: row.depth)
            }
            if rows.isEmpty {
                Text(query.isEmpty ? "No topics yet — tap + to start studying" : "No matching pages, topics or tags").font(.system(size: 10)).foregroundStyle(palette.muted).padding(.top, 14)
            }
        }
        .alert("New study topic", isPresented: $showingNewStudyTopic) {
            TextField("e.g. C++ Memory Management", text: $studyTopicName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { store.openApp(.tablespoon); tableSpoon.createTopic(studyTopicName, nested: false) }
        }
        .alert("Add tag", isPresented: Binding(get: { tagTarget != nil }, set: { if !$0 { tagTarget = nil } }), presenting: tagTarget) { node in
            TextField("e.g. pointers", text: $tagText)
            Button("Cancel", role: .cancel) {}
            Button("Add") { tableSpoon.addTag(tagText, to: node.url) }
        } message: { node in Text("Tag “\(node.displayName)”. Search tags with #name.") }
        .alert("New subtopic", isPresented: Binding(get: { subtopicParent != nil }, set: { if !$0 { subtopicParent = nil } }), presenting: subtopicParent) { parent in
            TextField("Subtopic name", text: $subtopicName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                store.openApp(.tablespoon)
                tableSpoon.selected = parent.id
                tableSpoon.expanded.insert(parent.id)
                tableSpoon.createTopic(subtopicName, nested: true)
            }
        } message: { parent in Text("Inside “\(parent.name)”. Subtopics can hold more subtopics.") }
    }

    private func sidebarHeading(_ title: String, symbol: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 8)).foregroundStyle(Color(hex: 0xF5B301))
            Text(title).font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(palette.muted)
            Spacer()
        }.padding(.horizontal, 6).padding(.bottom, 3)
    }

    private func studyRow(_ node: TSNode, depth: Int) -> some View {
        let isOpen = store.activeApp == .tablespoon && tableSpoon.selected == node.id
        let chevron = tableSpoon.expanded.contains(node.id) ? "chevron.down" : "chevron.right"
        let folderSymbol = depth == 0 ? "books.vertical.fill" : "folder.fill"
        let fileSymbol = node.isPage ? "doc.text" : node.isBoard ? "scribble.variable" : node.isTodo ? "checklist" : "chevron.left.forwardslash.chevron.right"
        let folderTint = depth == 0 ? Color(hex: 0x7C5CFF) : Color(hex: 0xFF7A3D)
        return Button {
            store.openApp(.tablespoon)
            tableSpoon.tap(node)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: node.isDir ? chevron : "circle.fill")
                    .font(.system(size: node.isDir ? 8 : 4, weight: .bold)).foregroundStyle(palette.muted).frame(width: 10)
                Image(systemName: node.isDir ? folderSymbol : fileSymbol)
                    .font(.system(size: 10)).foregroundStyle(node.isDir ? folderTint : palette.muted)
                Text(node.displayName).font(.system(size: 11, weight: node.isDir && depth == 0 ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 0)
                if tableSpoon.isBookmarked(node.url) { Image(systemName: "bookmark.fill").font(.system(size: 8)).foregroundStyle(Color(hex: 0xF5B301)) }
            }
            .padding(.leading, CGFloat(depth) * 12 + 6).padding(.vertical, 5).padding(.trailing, 6)
            .background(isOpen ? palette.accent.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(tableSpoon.isBookmarked(node.url) ? "Remove bookmark" : "Bookmark") { tableSpoon.toggleBookmark(node.url) }
            Button("Add tag…") { tagText = ""; tagTarget = node }
            ForEach(tableSpoon.tags(of: node.url), id: \.self) { tag in
                Button("Remove tag #\(tag)") { tableSpoon.removeTag(tag, from: node.url) }
            }
            Divider()
            if node.isDir {
                Button("New subtopic inside…") { subtopicName = ""; subtopicParent = node }
                Button(tableSpoon.hasBoard("board", in: node.url) ? "Open whiteboard" : "Add whiteboard") { store.openApp(.tablespoon); tableSpoon.addWhiteboard(in: node.url) }
                Button(tableSpoon.hasBoard("todo", in: node.url) ? "Open ToDo board" : "Add ToDo board") { store.openApp(.tablespoon); tableSpoon.addTodoBoard(in: node.url) }
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 28, height: 28).background(Brand.gradient, in: RoundedRectangle(cornerRadius: 7))
                Text("Twinee").font(.system(size: 17, weight: .bold, design: .rounded)).tracking(-0.6)
                Spacer()
                Button { withAnimation(.easeInOut(duration: 0.18)) { sidebarHidden.toggle(); hoverSidebar = false } } label: {
                    Image(systemName: sidebarHidden ? "pin" : "sidebar.left").font(.system(size: 12)).foregroundStyle(palette.muted).frame(width: 24, height: 24)
                }.buttonStyle(.plain).help(sidebarHidden ? "Pin the sidebar" : "Hide the sidebar — move the mouse to the left edge to bring it back")
            }.padding(.horizontal, 15).padding(.top, 18).padding(.bottom, 16)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(palette.muted)
                TextField("Find a page, topic or #tag", text: $searchText).textFieldStyle(.plain).font(.system(size: 10))
                if !searchText.isEmpty { Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(palette.muted) }.buttonStyle(.plain) }
            }.padding(.horizontal, 9).padding(.vertical, 8).background(palette.surface, in: RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.border, lineWidth: 1)).padding(.horizontal, 12).padding(.bottom, 17)
            ScrollView {
                VStack(spacing: 6) {
                    if searchText.isEmpty { appsSection }
                    tableSpoonSection
                }.padding(.horizontal, 8)
            }
            Spacer(minLength: 10)
            HStack(spacing: 7) { Circle().fill(Color(hex: 0x62B58F)).frame(width: 7, height: 7); Text("Saved on this Mac").font(.system(size: 9)).foregroundStyle(palette.muted) }
                .padding(.horizontal, 14).padding(.bottom, 15)
        }
        .frame(width: sidebarWidth).background(LinearGradient(colors: [palette.sidebar, Color(hex: 0x7C5CFF).opacity(palette.isDark ? 0.10 : 0.06)], startPoint: .top, endPoint: .bottom))
    }

    @ViewBuilder
    private func appView(_ app: DevApp) -> some View {
        switch app {
        case .tablespoon: TableSpoonView(model: tableSpoon, palette: palette, theme: theme, toggleTheme: toggleTheme)
        case .whiteboard:
            WhiteboardView(key: WhiteboardStore.globalKey, subtitle: "Global", palette: palette, theme: theme, toggleTheme: toggleTheme)
        case .compare: CompareView(model: compare, palette: palette, theme: theme, toggleTheme: toggleTheme)
        case .code: CodeBrowserView(model: codeBrowser, palette: palette, theme: theme, toggleTheme: toggleTheme)
        case .git:
            GitView(model: git, palette: palette, theme: theme, toggleTheme: toggleTheme) { url in
                codeBrowser.load(url)
                store.openApp(.code)
            }
        case .timer: TimerView(model: timer, palette: palette, theme: theme, toggleTheme: toggleTheme)
        case .launcher: LauncherView(palette: palette, theme: theme, toggleTheme: toggleTheme)
        }
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("APPS").font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(palette.muted)
                .padding(.horizontal, 6).padding(.bottom, 5)
            Button { store.openTodo() } label: {
                HStack(spacing: 7) {
                    Color.clear.frame(width: 10)
                    Image(systemName: "checklist").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white).frame(width: 20, height: 20).background(Color(hex: 0x1FB57A).gradient, in: RoundedRectangle(cornerRadius: 5))
                    Text("ToDo").font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 0)
                    let open = store.openTodoCount
                    if open > 0 { Text("\(open)").font(.system(size: 9)).foregroundStyle(palette.muted) }
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(store.todoScope != nil ? palette.selected : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
            ForEach(DevApp.allCases.filter { $0 != .tablespoon }) { app in appRow(app) }
        }.padding(.bottom, 16)
    }

    private func appRow(_ app: DevApp) -> some View {
        let isSelected = store.activeApp == app
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Button { store.openApp(app) } label: {
                    HStack(spacing: 7) {
                        Color.clear.frame(width: 10)
                        Image(systemName: app.symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white).frame(width: 20, height: 20).background(app.tint.gradient, in: RoundedRectangle(cornerRadius: 5))
                        Text(app.title).font(.system(size: 12, weight: .semibold))
                        Spacer(minLength: 0)
                        if app == .timer && (timer.isRunning || timer.mode == .stopwatch && timer.elapsed > 0) {
                            Text(timer.displayString).font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(palette.accent)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(isSelected ? palette.selected : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
                if app == .launcher && !tools.apps.isEmpty {
                    Button { launcherExpanded.toggle() } label: {
                        Image(systemName: launcherExpanded ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(palette.muted).frame(width: 20, height: 22).contentShape(Rectangle())
                    }.buttonStyle(.plain).help(launcherExpanded ? "Hide apps" : "Show apps")
                }
            }
            if app == .launcher && launcherExpanded {
                ForEach(tools.apps) { linked in
                    Button { AppLauncher.open(linked) } label: {
                        HStack(spacing: 8) {
                            Image(nsImage: AppLauncher.icon(for: linked)).resizable().frame(width: 14, height: 14)
                            Text(linked.name).font(.system(size: 11)).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, 34).padding(.trailing, 8).padding(.vertical, 5)
                        .foregroundStyle(palette.muted)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).help("Open \(linked.name)")
                }
            }
        }
    }
}

struct Palette {
    let isDark: Bool
    let background: Color
    let sidebar: Color
    let surface: Color
    let text: Color
    let muted: Color
    let border: Color
    let accent: Color
    let selected: Color

    init(_ theme: ThemeMode) {
        isDark = theme == .black
        if isDark {
            background = Color(hex: 0x111115)
            sidebar = Color(hex: 0x151519)
            surface = Color(hex: 0x1C1C22)
            text = Color(hex: 0xF2F1F5)
            muted = Color(hex: 0x9897A1)
            border = Color(hex: 0x2C2C34)
            accent = Color(hex: 0xA494FF)
            selected = Color(hex: 0x29243C)
        } else {
            background = Color(hex: 0xF7F7F4)
            sidebar = Color(hex: 0xFFFFFF)
            surface = Color(hex: 0xFFFFFF)
            text = Color(hex: 0x292A32)
            muted = Color(hex: 0x92939B)
            border = Color(hex: 0xEAEAE6)
            accent = Color(hex: 0x7762D5)
            selected = Color(hex: 0xF0EDFF)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

extension JSONEncoder {
    static var twinee: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var twinee: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
