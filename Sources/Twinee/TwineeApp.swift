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
        ("Pages", ["Write like a wiki page: headings, lists, code, info/note/warning panels, status tags and a live “On this page” outline.", "Add sticky notes from the page toolbar; drag, resize and recolour them.", "Right-click a page in the sidebar to rename or delete it."]),
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

enum TopicKind: String, CaseIterable, Identifiable, Codable {
    case idea = "Rough idea"
    case notes = "Notes"
    case implementation = "Implementation"
    case journal = "Journal"
    case links = "Links"
    case videos = "Videos"

    var id: String { rawValue }
    var symbol: String {
        return switch self {
        case .idea: "lightbulb"
        case .notes: "note.text"
        case .implementation: "hammer"
        case .journal: "book.closed"
        case .links: "link"
        case .videos: "play.rectangle"
        }
    }
    var tint: Color {
        return switch self {
        case .idea: Color(hex: 0x8875E2)
        case .notes: Color(hex: 0xD99162)
        case .implementation: Color(hex: 0x58A486)
        case .journal: Color(hex: 0xD47F98)
        case .links: Color(hex: 0x638FC8)
        case .videos: Color(hex: 0xCC776E)
        }
    }
}

struct Project: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var details: String
    var symbol: String
    var colorIndex: Int
    var todoNotes: Data?
}

struct Topic: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var projectID: UUID
    var kind: TopicKind
    var title: String
    var richText: Data
    var plainText: String
    var url: String
    var stickies: [Sticky] = []
    var labels: [String] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var body: String { plainText }

    private enum CodingKeys: String, CodingKey {
        case id, projectID, kind, title, richText, plainText, sections, body, url, stickies, labels, createdAt, updatedAt
    }

    init(id: UUID = UUID(), projectID: UUID, kind: TopicKind, title: String, sections: [TopicSection], url: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.projectID = projectID
        self.kind = kind
        self.title = title
        let document = RichText.document(from: sections)
        self.richText = RichText.encode(document)
        self.plainText = document.string
        self.url = url
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        projectID = try values.decode(UUID.self, forKey: .projectID)
        kind = try values.decode(TopicKind.self, forKey: .kind)
        title = try values.decode(String.self, forKey: .title)
        url = try values.decodeIfPresent(String.self, forKey: .url) ?? ""
        stickies = try values.decodeIfPresent([Sticky].self, forKey: .stickies) ?? []
        labels = try values.decodeIfPresent([String].self, forKey: .labels) ?? []
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        if let savedRichText = try values.decodeIfPresent(Data.self, forKey: .richText) {
            richText = savedRichText
            plainText = try values.decodeIfPresent(String.self, forKey: .plainText) ?? RichText.decode(savedRichText).string
        } else {
            // Earlier versions stored a single note or a list of sections.
            var legacy = try values.decodeIfPresent([TopicSection].self, forKey: .sections) ?? []
            if legacy.isEmpty {
                legacy = [TopicSection(title: "", content: try values.decodeIfPresent(String.self, forKey: .body) ?? "")]
            }
            let document = RichText.document(from: legacy)
            richText = RichText.encode(document)
            plainText = document.string
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(projectID, forKey: .projectID)
        try values.encode(kind, forKey: .kind)
        try values.encode(title, forKey: .title)
        try values.encode(richText, forKey: .richText)
        try values.encode(plainText, forKey: .plainText)
        try values.encode(url, forKey: .url)
        try values.encode(stickies, forKey: .stickies)
        try values.encode(labels, forKey: .labels)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(updatedAt, forKey: .updatedAt)
    }
}

struct TopicSection: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var content: String
}

final class WorkspaceStore: ObservableObject {
    @Published var projects: [Project] = []
    @Published var topics: [Topic] = []
    @Published var todos: [TodoItem] = []
    @Published var selectedProjectID: UUID?
    @Published var selectedTopicID: UUID? { didSet { if selectedTopicID != nil { activeApp = nil } } }
    @Published var todoScope: TodoScope? { didSet { if todoScope != nil { activeApp = nil } } }
    @Published var activeApp: DevApp?
    @Published var whiteboardProjectID: UUID?

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("Twinee", isDirectory: true)
        fileURL = directory.appendingPathComponent("workspace.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder.twinee.decode(WorkspaceData.self, from: data) {
            projects = saved.projects
            topics = saved.topics
            todos = saved.todos
        } else {
            let seed = Self.starterWorkspace()
            projects = seed.projects
            topics = seed.topics
            todos = seed.todos
            persist()
        }
        selectedProjectID = projects.first?.id
        selectedTopicID = nil
        todoScope = projects.first.map { TodoScope.project($0.id) }
    }

    func addProject(name: String, details: String) {
        let symbols = ["sparkles", "terminal", "sun.max", "diamond", "leaf"]
        let project = Project(name: name, details: details, symbol: symbols[projects.count % symbols.count], colorIndex: projects.count % 5)
        projects.append(project)
        selectedProjectID = project.id
        selectedTopicID = nil
        todoScope = .project(project.id)
        persist()
    }

    func createTopic(in projectID: UUID) {
        let topic = Topic(projectID: projectID, kind: .idea, title: "Untitled Page", sections: [], url: "")
        topics.insert(topic, at: 0)
        selectedProjectID = projectID
        selectedTopicID = topic.id
        todoScope = nil
        persist()
    }

    func saveTopic(_ topic: Topic) {
        if let index = topics.firstIndex(where: { $0.id == topic.id }) {
            topics[index] = topic
        } else {
            topics.append(topic)
        }
        persist()
    }

    func renameTopic(id: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = topics.firstIndex(where: { $0.id == id }) else { return }
        topics[index].title = trimmed
        topics[index].updatedAt = Date()
        persist()
    }

    func deleteTopic(id: UUID) {
        let projectID = topics.first(where: { $0.id == id })?.projectID
        topics.removeAll { $0.id == id }
        if selectedTopicID == id {
            selectedTopicID = nil
            todoScope = (projectID ?? selectedProjectID).map { TodoScope.project($0) }
        }
        persist()
    }

    func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.twinee.encode(WorkspaceData(projects: projects, topics: topics, todos: todos))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Twinee could not save the local workspace: %@", error.localizedDescription)
        }
    }

    private static func starterWorkspace() -> WorkspaceData {
        let twinee = Project(name: "Twinee", details: "A softer home for everything you learn.", symbol: "sparkles", colorIndex: 0)
        let cpp = Project(name: "C++ Learning", details: "Build a stronger systems foundation.", symbol: "terminal", colorIndex: 1)
        let life = Project(name: "Life & little things", details: "Ideas worth keeping close.", symbol: "sun.max", colorIndex: 2)
        let now = Date()
        let topics = [
            Topic(projectID: twinee.id, kind: .idea, title: "A second brain that feels like a garden", sections: [TopicSection(title: "The idea", content: "What if knowledge management felt less like filing paperwork and more like tending a small garden? Projects are the beds; topics are the things growing in them."), TopicSection(title: "Guiding thought", content: "Keep it gentle, useful, and easy to return to.")], url: "", createdAt: now.addingTimeInterval(-2_600), updatedAt: now.addingTimeInterval(-2_600)),
            Topic(projectID: cpp.id, kind: .implementation, title: "Memory allocator — next steps", sections: [TopicSection(title: "To explore", content: "Explore alignment guarantees and add a small benchmark harness."), TopicSection(title: "Questions", content: "How does the free-list allocator split and coalesce blocks? What happens to fragmentation under mixed allocation sizes?")], url: "", createdAt: now.addingTimeInterval(-14_400), updatedAt: now.addingTimeInterval(-14_400)),
            Topic(projectID: life.id, kind: .journal, title: "A note to future me", sections: [TopicSection(title: "Today", content: "Capture the thought while it is still warm. It does not need to be complete or clever."), TopicSection(title: "Remember", content: "A few honest lines are enough to find this thread again later.")], url: "", createdAt: now.addingTimeInterval(-86_400), updatedAt: now.addingTimeInterval(-86_400)),
            Topic(projectID: twinee.id, kind: .notes, title: "Keep the first version small", sections: [TopicSection(title: "Must have", content: "Projects, a handful of topic types, and a calm place to write."), TopicSection(title: "Later", content: "Fast search. No accounts or sync to start — the first version should open quickly and get out of the way.")], url: "", createdAt: now.addingTimeInterval(-115_200), updatedAt: now.addingTimeInterval(-115_200)),
            Topic(projectID: cpp.id, kind: .videos, title: "Allocator design talk", sections: [TopicSection(title: "Why I saved this", content: "A good watch when revisiting allocator strategies and memory layout tradeoffs.")], url: "https://www.youtube.com/results?search_query=memory+allocator+design", createdAt: now.addingTimeInterval(-208_800), updatedAt: now.addingTimeInterval(-208_800)),
            Topic(projectID: life.id, kind: .links, title: "A place to collect useful things", sections: [TopicSection(title: "Why it matters", content: "Save links beside the idea they belong to, then add one sentence about why the link matters.")], url: "https://developer.apple.com/documentation/swiftui", createdAt: now.addingTimeInterval(-259_200), updatedAt: now.addingTimeInterval(-259_200)),
        ]
        let todos = [
            TodoItem(projectID: twinee.id, title: "Sketch the knowledge portal layout", status: .done, updatedAt: now.addingTimeInterval(-7_200)),
            TodoItem(projectID: twinee.id, title: "Try the ToDo board with real work", status: .ongoing, updatedAt: now.addingTimeInterval(-3_600)),
            TodoItem(projectID: twinee.id, title: "Decide what to track next", status: .bucket, updatedAt: now.addingTimeInterval(-1_800)),
            TodoItem(projectID: cpp.id, title: "Add a benchmark harness to the allocator", status: .ongoing, updatedAt: now.addingTimeInterval(-5_400)),
            TodoItem(projectID: cpp.id, title: "Read about alignment guarantees", status: .bucket, updatedAt: now.addingTimeInterval(-2_400)),
            TodoItem(projectID: life.id, title: "Write down one thing worth remembering", status: .bucket, updatedAt: now.addingTimeInterval(-900)),
        ]
        return WorkspaceData(projects: [twinee, cpp, life], topics: topics, todos: todos)
    }
}

struct WorkspaceData: Codable {
    var projects: [Project]
    var topics: [Topic]
    var todos: [TodoItem]

    init(projects: [Project], topics: [Topic], todos: [TodoItem] = []) {
        self.projects = projects
        self.topics = topics
        self.todos = todos
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        projects = try values.decode([Project].self, forKey: .projects)
        topics = try values.decode([Topic].self, forKey: .topics)
        todos = try values.decodeIfPresent([TodoItem].self, forKey: .todos) ?? []
    }
}

enum PendingDelete: Identifiable {
    case project(Project)
    case topic(Topic)

    var id: UUID {
        switch self {
        case .project(let project): return project.id
        case .topic(let topic): return topic.id
        }
    }
}

struct TwineeWindow: View {
    @ObservedObject var store: WorkspaceStore
    let theme: ThemeMode
    let toggleTheme: () -> Void
    @State private var searchText = ""
    @State private var collapsedProjectIDs: Set<UUID> = []
    @State private var todoExpanded = false
    @AppStorage("twinee.sidebarHidden") private var sidebarHidden = false
    @State private var hoverSidebar = false
    @StateObject private var ai = AIChatModel()
    @AppStorage("twinee.aiVisible") private var aiVisible = false
    @AppStorage("twinee.aiWidth") private var aiWidth = 340.0
    @StateObject private var compare = CompareModel()
    @StateObject private var codeBrowser = CodeBrowserModel()
    @StateObject private var git = GitModel()
    @StateObject private var timer = TimerModel()
    @ObservedObject private var tools = DevToolsStore.shared
    @State private var launcherExpanded = true
    @State private var pendingDelete: PendingDelete?
    @State private var renamingProject: Project?
    @State private var renameText = ""
    @State private var renamingTopic: Topic?
    @State private var topicRenameText = ""
    @AppStorage("twinee.sidebarWidth") private var sidebarWidth = 258.0
    @State private var showingNewProject = false
    @State private var projectName = ""
    @State private var projectDetails = ""

    private var palette: Palette { Palette(theme) }
    private var currentTopic: Topic? { store.topics.first { $0.id == store.selectedTopicID } }

    private func topics(in project: Project) -> [Topic] {
        store.topics.filter { topic in
            topic.projectID == project.id && (searchText.isEmpty || [topic.title, topic.body, topic.url].contains { $0.localizedCaseInsensitiveContains(searchText) })
        }.sorted { $0.createdAt > $1.createdAt }
    }

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
        .onChange(of: store.selectedTopicID) { _ in hoverSidebar = false }
        .onChange(of: store.activeApp) { _ in hoverSidebar = false }
        .onChange(of: store.todoScope) { _ in hoverSidebar = false }
        .foregroundStyle(palette.text)
        .background(palette.background)
        .alert("Create a project", isPresented: $showingNewProject) {
            TextField("Project name", text: $projectName)
            TextField("A short description (optional)", text: $projectDetails)
            Button("Cancel", role: .cancel) { projectName = ""; projectDetails = "" }
            Button("Create") {
                let name = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { store.addProject(name: name, details: projectDetails.trimmingCharacters(in: .whitespacesAndNewlines)) }
                projectName = ""; projectDetails = ""
            }
        } message: { Text("Give this thread of work a place of its own.") }
    }

    // What the AI panel can read: the page currently on screen.
    private var pageContext: PageContext? {
        if let app = store.activeApp {
            guard app == .code, let path = codeBrowser.currentPath else { return nil }
            let line = codeBrowser.selectedLine + 1
            return PageContext(title: codeBrowser.relativePath(path), kind: "source file (\(codeBrowser.language.name))", text: codeBrowser.text,
                               note: "The cursor is near line \(line).\(codeBrowser.remote.map { " It comes from \($0.url) on branch \($0.branch)." } ?? "")")
        }
        if let scope = store.todoScope {
            let items = store.todos.filter { item in
                if case .project(let id) = scope { return item.projectID == id }
                return true
            }
            let text = items.map { "- [\($0.status.title)] \($0.title)\($0.notes.map { " — " + $0 } ?? "")" }.joined(separator: "\n")
            return PageContext(title: "ToDo board", kind: "task board", text: text.isEmpty ? "(no tasks)" : text)
        }
        if let topic = currentTopic {
            let stickies = topic.stickies.map(\.text).filter { !$0.isEmpty }.map { "- " + $0 }.joined(separator: "\n")
            let text = topic.plainText + (stickies.isEmpty ? "" : "\n\nSticky notes:\n" + stickies) + (topic.url.isEmpty ? "" : "\n\nLink: " + topic.url)
            return PageContext(title: topic.title.isEmpty ? "Untitled Page" : topic.title, kind: "\(topic.kind.rawValue.lowercased()) page", text: text)
        }
        return nil
    }

    @ViewBuilder
    private var pageContent: some View {
        if let app = store.activeApp {
            appView(app)
        } else if let scope = store.todoScope {
            TodoBoard(store: store, scope: scope, palette: palette, theme: theme, toggleTheme: toggleTheme)
                .id(scope)
        } else if let topic = currentTopic {
            TopicCanvas(topic: topic, projects: store.projects, palette: palette, theme: theme, toggleTheme: toggleTheme, onSave: store.saveTopic, onDelete: store.deleteTopic)
                .id(topic.id)
        } else {
            emptyCanvas
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
                TextField("Find a topic", text: $searchText).textFieldStyle(.plain).font(.system(size: 10))
                if !searchText.isEmpty { Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(palette.muted) }.buttonStyle(.plain) }
            }.padding(.horizontal, 9).padding(.vertical, 8).background(palette.surface, in: RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.border, lineWidth: 1)).padding(.horizontal, 12).padding(.bottom, 17)
            ScrollView {
                VStack(spacing: 6) {
                    if searchText.isEmpty { appsSection }
                    HStack {
                        Text("PROJECTS").font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(palette.muted)
                        Spacer()
                        Button { showingNewProject = true } label: { Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).frame(width: 24, height: 24).foregroundStyle(palette.muted).background(palette.surface, in: RoundedRectangle(cornerRadius: 6)) }.buttonStyle(.plain).help("New project")
                    }.padding(.horizontal, 6).padding(.bottom, 3)
                    ForEach(Array(store.projects.enumerated()), id: \.element.id) { index, project in
                        projectGroup(project, index: index)
                    }
                    if !searchText.isEmpty && store.projects.allSatisfy({ topics(in: $0).isEmpty }) {
                        Text("No matching topics").font(.system(size: 10)).foregroundStyle(palette.muted).padding(.top, 20)
                    }
                }.padding(.horizontal, 8)
            }
            Spacer(minLength: 10)
            HStack(spacing: 7) { Circle().fill(Color(hex: 0x62B58F)).frame(width: 7, height: 7); Text("Saved on this Mac").font(.system(size: 9)).foregroundStyle(palette.muted) }
                .padding(.horizontal, 14).padding(.bottom, 15)
        }
        .frame(width: sidebarWidth).background(LinearGradient(colors: [palette.sidebar, Color(hex: 0x7C5CFF).opacity(palette.isDark ? 0.10 : 0.06)], startPoint: .top, endPoint: .bottom))
        .alert(
            deleteTitle(pendingDelete),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { item in
            Button("Delete", role: .destructive) {
                switch item {
                case .project(let project): store.deleteProject(id: project.id)
                case .topic(let topic): store.deleteTopic(id: topic.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text(deleteMessage(item))
        }
        .alert("Rename project", isPresented: Binding(get: { renamingProject != nil }, set: { if !$0 { renamingProject = nil } }), presenting: renamingProject) { project in
            TextField("Project name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { store.renameProject(id: project.id, name: renameText) }
        }
        .alert("Rename topic", isPresented: Binding(get: { renamingTopic != nil }, set: { if !$0 { renamingTopic = nil } }), presenting: renamingTopic) { topic in
            TextField("Topic title", text: $topicRenameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { store.renameTopic(id: topic.id, title: topicRenameText) }
        }
    }

    private func deleteTitle(_ item: PendingDelete?) -> String {
        switch item {
        case .project(let project): return "Delete “\(project.name)”?"
        case .topic(let topic): return "Delete “\(topic.title.isEmpty ? "Untitled Page" : topic.title)”?"
        case nil: return ""
        }
    }

    private func deleteMessage(_ item: PendingDelete) -> String {
        switch item {
        case .project(let project):
            let topicCount = store.topics.filter { $0.projectID == project.id }.count
            let taskCount = store.todos.filter { $0.projectID == project.id }.count
            return "This permanently deletes the project, its \(topicCount) \(topicCount == 1 ? "topic" : "topics") and \(taskCount) \(taskCount == 1 ? "task" : "tasks"). This can't be undone."
        case .topic:
            return "This permanently deletes the topic and everything written in it. This can't be undone."
        }
    }

    @ViewBuilder
    private func topicActions(_ topic: Topic) -> some View {
        Button("Rename…") { topicRenameText = topic.title; renamingTopic = topic }
        Divider()
        Button("Delete topic…", role: .destructive) { pendingDelete = .topic(topic) }
    }

    @ViewBuilder
    private func projectActions(_ project: Project) -> some View {
        Button("New topic") { createPage(in: project.id) }
        Button("Whiteboard") { store.openWhiteboard(for: project.id) }
        Button("Rename…") { renameText = project.name; renamingProject = project }
        Divider()
        Button("Delete project…", role: .destructive) { pendingDelete = .project(project) }
    }

    @ViewBuilder
    private func appView(_ app: DevApp) -> some View {
        switch app {
        case .whiteboard:
            let projectName = store.whiteboardProjectID.flatMap { id in store.projects.first { $0.id == id }?.name }
            WhiteboardView(key: store.whiteboardProjectID?.uuidString ?? WhiteboardStore.globalKey, subtitle: projectName ?? "Global", palette: palette, theme: theme, toggleTheme: toggleTheme)
                .id(store.whiteboardProjectID?.uuidString ?? WhiteboardStore.globalKey)
        case .compare: CompareView(model: compare, palette: palette, theme: theme, toggleTheme: toggleTheme)
        case .code: CodeBrowserView(model: codeBrowser, palette: palette, theme: theme, toggleTheme: toggleTheme)
        case .git:
            GitView(model: git, palette: palette, theme: theme, toggleTheme: toggleTheme) { url in
                codeBrowser.load(url)
                store.openApp(.code)
            }
        case .timer: TimerView(model: timer, projects: store.projects, palette: palette, theme: theme, toggleTheme: toggleTheme)
        case .launcher: LauncherView(palette: palette, theme: theme, toggleTheme: toggleTheme)
        }
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("APPS").font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(palette.muted)
                .padding(.horizontal, 6).padding(.bottom, 5)
            Button {
                todoExpanded.toggle()
                if todoExpanded && store.todoScope == nil { store.openTodo(.all) }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: todoExpanded ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(palette.muted).frame(width: 10)
                    Image(systemName: "checklist").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white).frame(width: 20, height: 20).background(Color(hex: 0x1FB57A).gradient, in: RoundedRectangle(cornerRadius: 5))
                    Text("ToDo").font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 0)
                    Text("\(store.openTodoCount(for: nil))").font(.system(size: 9)).foregroundStyle(palette.muted)
                }.padding(.horizontal, 8).padding(.vertical, 5).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if todoExpanded {
                todoRow("All tasks", symbol: "tray.full", tint: palette.accent, scope: .all, count: store.openTodoCount(for: nil))
                ForEach(Array(store.projects.enumerated()), id: \.element.id) { index, project in
                    todoRow(project.name, symbol: "circle.fill", tint: ProjectPalette.color(index), scope: .project(project.id), count: store.openTodoCount(for: project.id))
                }
            }
            ForEach(DevApp.allCases) { app in appRow(app) }
        }.padding(.bottom, 16)
    }

    private func appRow(_ app: DevApp) -> some View {
        let isSelected = store.activeApp == app && (app != .whiteboard || store.whiteboardProjectID == nil)
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

    private func todoRow(_ title: String, symbol: String, tint: Color, scope: TodoScope, count: Int) -> some View {
        let isSelected = store.todoScope == scope
        return Button { store.openTodo(scope) } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: symbol == "circle.fill" ? 6 : 10)).foregroundStyle(tint).frame(width: 14)
                Text(title).font(.system(size: 11, weight: isSelected ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 0)
                if count > 0 { Text("\(count)").font(.system(size: 9)).foregroundStyle(palette.muted) }
            }
            .padding(.leading, 29).padding(.trailing, 8).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isSelected ? palette.text : palette.muted)
            .background(isSelected ? palette.selected : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    @ViewBuilder
    private func projectGroup(_ project: Project, index: Int) -> some View {
        let projectTopics = topics(in: project)
        let isSearching = !searchText.isEmpty
        if !isSearching || !projectTopics.isEmpty {
            let isExpanded = isSearching || !collapsedProjectIDs.contains(project.id)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Button { toggleProject(project.id) } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(palette.muted)
                            .frame(width: 18, height: 22).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Button { openProject(project.id) } label: {
                        HStack(spacing: 7) {
                            Image(systemName: project.symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white).frame(width: 20, height: 20).background(projectColor(index).gradient, in: RoundedRectangle(cornerRadius: 5))
                            Text(project.name).lineLimit(1).font(.system(size: 12, weight: .semibold))
                            Spacer(minLength: 0)
                            Text("\(store.topics.filter { $0.projectID == project.id }.count)").font(.system(size: 9)).foregroundStyle(palette.muted)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    .contextMenu { projectActions(project) }
                    Menu { projectActions(project) } label: {
                        Image(systemName: "ellipsis").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.muted).frame(width: 18, height: 22)
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Project options")
                    Button { createPage(in: project.id) } label: {
                        Image(systemName: "plus").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.accent).frame(width: 22, height: 22).background(palette.selected, in: RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain).help("New topic in \(project.name)")
                }.padding(.horizontal, 8).padding(.vertical, 5)

                if isExpanded {
                    if !isSearching {
                        todoRow("ToDo", symbol: "checklist", tint: palette.accent, scope: .project(project.id), count: store.openTodoCount(for: project.id))
                    }
                    if !isSearching {
                        let boardSelected = store.activeApp == .whiteboard && store.whiteboardProjectID == project.id
                        Button { store.openWhiteboard(for: project.id) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "scribble.variable").font(.system(size: 10)).foregroundStyle(palette.accent).frame(width: 14)
                                Text("Whiteboard").font(.system(size: 11, weight: boardSelected ? .semibold : .regular)).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.leading, 29).padding(.trailing, 8).padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(boardSelected ? palette.text : palette.muted)
                            .background(boardSelected ? palette.selected : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    ForEach(projectTopics) { topic in
                        let isSelected = store.selectedTopicID == topic.id
                        HStack(spacing: 2) {
                        Button { store.selectedProjectID = project.id; store.selectedTopicID = topic.id; store.todoScope = nil } label: {
                            HStack(spacing: 8) {
                                Image(systemName: topic.kind.symbol).font(.system(size: 10)).foregroundStyle(topic.kind.tint).frame(width: 14)
                                Text(topic.title.isEmpty ? "Untitled Page" : topic.title).font(.system(size: 11, weight: isSelected ? .semibold : .regular)).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.leading, 29).padding(.trailing, 8).padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(isSelected ? palette.text : palette.muted)
                            .background(isSelected ? palette.selected : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .contextMenu { topicActions(topic) }
                        Menu { topicActions(topic) } label: {
                            Image(systemName: "ellipsis").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.muted).frame(width: 18, height: 22)
                        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Topic options")
                        }
                    }
                    if projectTopics.isEmpty {
                        Button { createPage(in: project.id) } label: {
                            Text("Add the first topic").font(.system(size: 10)).foregroundStyle(palette.accent).padding(.leading, 37).padding(.vertical, 6)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var emptyCanvas: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text").font(.system(size: 28, weight: .light)).foregroundStyle(palette.accent)
            Text("Choose a topic from a project").font(.system(size: 16, weight: .semibold, design: .rounded))
            Text("Write freely with headings, bullets, and lists.").font(.system(size: 11)).foregroundStyle(palette.muted)
            Button("New topic") { createPage(in: store.selectedProjectID ?? store.projects.first?.id) }.buttonStyle(.borderedProminent).tint(palette.accent).padding(.top, 4)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(palette.background)
    }

    private func toggleProject(_ id: UUID) {
        if collapsedProjectIDs.contains(id) { collapsedProjectIDs.remove(id) } else { collapsedProjectIDs.insert(id) }
    }

    private func openProject(_ id: UUID) {
        collapsedProjectIDs.remove(id)
        store.openTodo(.project(id))
    }

    private func createPage(in projectID: UUID?) {
        guard let projectID else { showingNewProject = true; return }
        collapsedProjectIDs.remove(projectID)
        searchText = ""
        store.createTopic(in: projectID)
    }

    private func projectColor(_ index: Int) -> Color {
        ProjectPalette.color(index)
    }
}

struct TopicCanvas: View {
    let projects: [Project]
    let palette: Palette
    let theme: ThemeMode
    let toggleTheme: () -> Void
    let onSave: (Topic) -> Void
    let onDelete: (UUID) -> Void
    @State private var draft: Topic
    @State private var saveTask: DispatchWorkItem?
    @State private var hasUnsavedChanges = false
    @State private var showingDeleteConfirmation = false
    @State private var outline: [OutlineItem] = []
    @AppStorage("twinee.pageFullWidth") private var fullWidth = false
    @StateObject private var editor = EditorController()

    init(topic: Topic, projects: [Project], palette: Palette, theme: ThemeMode, toggleTheme: @escaping () -> Void, onSave: @escaping (Topic) -> Void, onDelete: @escaping (UUID) -> Void) {
        self.projects = projects
        self.palette = palette
        self.theme = theme
        self.toggleTheme = toggleTheme
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: topic)
    }

    private var projectName: String { projects.first(where: { $0.id == draft.projectID })?.name ?? "Project" }
    private var urlIsAllowed: Bool {
        guard !draft.url.isEmpty else { return true }
        guard let url = URL(string: draft.url) else { return false }
        return ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(projectName).foregroundStyle(palette.muted)
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(palette.muted.opacity(0.65))
                Text(draft.title.isEmpty ? "Untitled Page" : draft.title).fontWeight(.medium).lineLimit(1)
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: hasUnsavedChanges ? "circle.fill" : "checkmark.circle.fill").font(.system(size: 8))
                    Text(!urlIsAllowed ? "Use an http(s) link" : hasUnsavedChanges ? "Saving…" : "Saved").font(.system(size: 9))
                }.foregroundStyle(!urlIsAllowed ? Color.red : hasUnsavedChanges ? palette.accent : palette.muted)
                Picker("Theme", selection: Binding(get: { theme }, set: { _ in toggleTheme() })) {
                    Text("White").tag(ThemeMode.white)
                    Text("Black").tag(ThemeMode.black)
                }.pickerStyle(.segmented).frame(width: 116).help("Choose the white or black theme")
                Button { fullWidth.toggle() } label: { Image(systemName: fullWidth ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right").font(.system(size: 11)).foregroundStyle(palette.muted).frame(width: 26, height: 26) }
                    .buttonStyle(.plain).help(fullWidth ? "Use a readable page width" : "Use the full window width")
                Button { addSticky() } label: { Label("Sticky", systemImage: "note.text.badge.plus") }
                    .buttonStyle(PillButtonStyle(palette: palette)).help("Add a sticky note to this page")
                Button("Save") { saveNow() }.keyboardShortcut("s", modifiers: .command).buttonStyle(.borderedProminent).tint(palette.accent).disabled(!urlIsAllowed)
                Button { showingDeleteConfirmation = true } label: { Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(palette.muted).frame(width: 28, height: 28) }.buttonStyle(.plain).help("Delete topic")
            }
            .font(.system(size: 10))
            .padding(.horizontal, 24).frame(height: 52)
            .background(palette.surface)
            .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }

            FormatBar(editor: editor, palette: palette, showsTip: false, trailing: { InsertMenu(editor: editor, palette: palette) })
                .padding(.horizontal, 24).padding(.vertical, 8)
                .background(palette.surface)
                .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }

            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        paper
                            .frame(maxWidth: fullWidth ? .infinity : 940, maxHeight: .infinity)
                            .frame(maxWidth: .infinity)
                        if !outline.isEmpty {
                            OutlineRail(items: outline, palette: palette) { editor.reveal($0) }.frame(width: 190)
                        }
                    }
                    .background(palette.background)
                    ForEach($draft.stickies) { $sticky in
                        StickyView(sticky: $sticky, bounds: proxy.size) { draft.stickies.removeAll { $0.id == sticky.id } }
                    }
                }
            }
        }
        .background(palette.background)
        .preferredColorScheme(palette.isDark ? .dark : .light)
        .onChange(of: draft) { updated in scheduleSave(updated) }
        .onChange(of: draft.plainText) { _ in refreshOutline() }
        .onAppear { DispatchQueue.main.async { refreshOutline() } }
        .onDisappear { if hasUnsavedChanges { saveNow() } }
        .confirmationDialog("Delete this topic?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete topic", role: .destructive) { saveTask?.cancel(); hasUnsavedChanges = false; onDelete(draft.id) }
        } message: { Text("This will delete the topic and everything written in it.") }
    }

    private func refreshOutline() { outline = editor.outline() }

    private var wordCount: Int { draft.plainText.split { $0.isWhitespace || $0.isNewline }.count }

    private var paper: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(ProjectPalette.color(projects.firstIndex { $0.id == draft.projectID } ?? 0).gradient).frame(height: 5)
                .clipShape(RoundedRectangle(cornerRadius: 3)).padding(.bottom, 6)
            TextField("Untitled Page", text: $draft.title)
                .textFieldStyle(.plain).font(.system(size: 36, weight: .bold, design: .rounded)).tracking(-1)
            HStack(spacing: 8) {
                Image(systemName: draft.kind.symbol).foregroundStyle(draft.kind.tint)
                Text("Created \(draft.createdAt.formatted(date: .abbreviated, time: .shortened))")
                Text("·")
                Text("Updated \(draft.updatedAt.formatted(.relative(presentation: .named)))")
                Text("·")
                Text("\(wordCount) words")
            }.font(.system(size: 10)).foregroundStyle(palette.muted)
            HStack(spacing: 10) {
                Picker("Type", selection: $draft.kind) { ForEach(TopicKind.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().fixedSize()
                Picker("Project", selection: $draft.projectID) { ForEach(projects) { Text($0.name).tag($0.id) } }.labelsHidden().fixedSize()
                Image(systemName: "link").font(.system(size: 10)).foregroundStyle(palette.muted)
                TextField("Add a link or video URL…", text: $draft.url).textFieldStyle(.plain).font(.system(size: 11))
            }.font(.system(size: 10))
            LabelChips(labels: $draft.labels, palette: palette)
            Rectangle().fill(palette.border).frame(height: 1).padding(.vertical, 4)
            RichTextEditor(data: $draft.richText, plainText: $draft.plainText, controller: editor)
        }
        .padding(.horizontal, 44).padding(.top, 28).padding(.bottom, 14)
        .background(palette.surface)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(palette.border, lineWidth: 1))
        .shadow(color: .black.opacity(palette.isDark ? 0.4 : 0.07), radius: 10, y: 3)
        .padding(.horizontal, 28).padding(.vertical, 20)
    }

    private func addSticky() {
        let count = draft.stickies.count
        draft.stickies.append(Sticky(x: 420 + Double(count % 6) * 28, y: 150 + Double(count % 6) * 28, colorIndex: count % Sticky.colors.count))
    }

    private func scheduleSave(_ updated: Topic) {
        hasUnsavedChanges = true
        saveTask?.cancel()
        guard urlIsAllowed else { return }
        let task = DispatchWorkItem {
            var saved = updated
            saved.updatedAt = Date()
            onSave(saved)
            hasUnsavedChanges = false
        }
        saveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: task)
    }

    private func saveNow() {
        guard urlIsAllowed else { return }
        saveTask?.cancel()
        var saved = draft
        saved.updatedAt = Date()
        onSave(saved)
        hasUnsavedChanges = false
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
