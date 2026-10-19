import SwiftUI
import AppKit

private enum TSPrompt {
    case topic, subtopic, note, code
    case rename(URL)

    var title: String {
        switch self {
        case .topic: return "New topic"
        case .subtopic: return "New subtopic"
        case .note: return "New notes page"
        case .code: return "New experiment file"
        case .rename: return "Rename"
        }
    }

    var message: String {
        switch self {
        case .topic: return "A topic is a folder, e.g. “C++ Memory Management”."
        case .subtopic: return "Created inside the selected topic."
        case .note: return "A rich page in the selected topic."
        case .code: return "Include the extension: main.cpp, test.c, demo.py …"
        case .rename: return "Enter a new name."
        }
    }
}

private let depthColors: [UInt32] = [0x7C5CFF, 0xFF4F8B, 0xFF8A3D, 0x1FB57A]

struct TableSpoonView: View {
    @ObservedObject var model: TableSpoonModel
    let palette: Palette
    let theme: ThemeMode
    let toggleTheme: () -> Void
    @AppStorage("twinee.tsSidebarWidth") private var sidebarWidth = 270.0
    @State private var prompt: TSPrompt?
    @State private var promptText = ""
    @State private var pendingDelete: TSNode?
    @State private var showConsole = true

    private var openNode: URL? { model.openPath.map { URL(fileURLWithPath: $0) } }
    private var isPage: Bool { model.openIsPage }

    var body: some View {
        VStack(spacing: 0) {
            AppTopBar(title: "TableSpoon", subtitle: model.breadcrumb, palette: palette, theme: theme, toggleTheme: toggleTheme)
            HStack(spacing: 0) {
                sidebar.frame(width: sidebarWidth)
                ResizeDivider(width: $sidebarWidth, range: 220...460, palette: palette)
                main
            }
        }
        .background(palette.background)
        .preferredColorScheme(palette.isDark ? .dark : .light)
        .alert(pendingDelete.map { "Move “\($0.name)” to the Trash?" } ?? "", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Move to Trash", role: .destructive) { if let node = pendingDelete { model.delete(node.url) }; pendingDelete = nil }
        } message: { Text("Everything inside it goes too.") }
    }

    // MARK: sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("TOPICS").font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(palette.muted)
                Spacer()
                Button { model.reload() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 10)) }
                    .buttonStyle(.plain).foregroundStyle(palette.muted).help("Refresh")
            }.padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    toolButton("folder.badge.plus", "Topic", prominent: true) { start(.topic) }
                    toolButton("arrow.turn.down.right", "Subtopic") { start(.subtopic) }
                }
                HStack(spacing: 6) {
                    toolButton("note.text", "Note") { start(.note) }
                    toolButton("book.closed", "Journal") { model.createJournal() }
                    toolButton("hammer", "Code") { start(.code) }
                }
                HStack(spacing: 6) {
                    toolButton("scribble.variable", "Whiteboard") { model.addWhiteboard() }
                    toolButton("checklist", "ToDo") { model.addTodoBoard() }
                }
            }.padding(.horizontal, 10).padding(.bottom, 10)

            Rectangle().fill(palette.border).frame(height: 1)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(model.visibleRows(), id: \.node.id) { row in rowView(row.node, depth: row.depth) }
                }.padding(8)
            }
        }
        .background(palette.sidebar)
        .alert(prompt?.title ?? "", isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })) {
            TextField("Name", text: $promptText)
            Button("Cancel", role: .cancel) { prompt = nil }
            Button("OK") { submit() }
        } message: { Text(prompt?.message ?? "") }
    }

    private func toolButton(_ symbol: String, _ title: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            }.frame(maxWidth: .infinity)
        }.buttonStyle(PillButtonStyle(palette: palette, prominent: prominent))
    }

    private func rowView(_ node: TSNode, depth: Int) -> some View {
        let selected = model.selected == node.id
        return HStack(spacing: 6) {
            Image(systemName: node.isDir ? (model.expanded.contains(node.id) ? "chevron.down" : "chevron.right") : "circle")
                .font(.system(size: 8, weight: .bold)).foregroundStyle(palette.muted).frame(width: 10).opacity(node.isDir ? 1 : 0)
            icon(node, depth: depth)
            Text(node.displayName).font(.system(size: 12, weight: node.isDir ? .semibold : .regular)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(depth) * 14 + 6).padding(.trailing, 6).padding(.vertical, 5)
        .background(selected ? palette.selected : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { model.tap(node) }
        .contextMenu {
            if node.isDir {
                Button("New subtopic here…") { model.selected = node.id; start(.subtopic) }
                Button("New note here…") { model.selected = node.id; start(.note) }
                Button("New code file here…") { model.selected = node.id; start(.code) }
                Button(model.hasBoard("board", in: node.url) ? "Open whiteboard" : "Add whiteboard") { model.addWhiteboard(in: node.url) }
                Button(model.hasBoard("todo", in: node.url) ? "Open ToDo board" : "Add ToDo board") { model.addTodoBoard(in: node.url) }
                Divider()
            }
            Button("Rename…") { start(.rename(node.url), text: node.displayName) }
            Button("Move to Trash…", role: .destructive) { pendingDelete = node }
        }
    }

    @ViewBuilder
    private func icon(_ node: TSNode, depth: Int) -> some View {
        if node.isDir {
            Image(systemName: depth == 0 ? "books.vertical.fill" : "folder.fill").font(.system(size: 11)).foregroundStyle(Color(hex: depthColors[min(depth, 3)])).frame(width: 16)
        } else if node.name.hasPrefix("journal-") {
            Image(systemName: "book.closed.fill").font(.system(size: 10)).foregroundStyle(Color(hex: 0xD47F98)).frame(width: 16)
        } else if node.isBoard {
            Image(systemName: "scribble.variable").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(hex: 0xE8517E)).frame(width: 16)
        } else if node.isTodo {
            Image(systemName: "checklist").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(hex: 0x1FB57A)).frame(width: 16)
        } else if node.isPage {
            Image(systemName: "note.text").font(.system(size: 10)).foregroundStyle(Color(hex: 0xD99162)).frame(width: 16)
        } else {
            Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Color(hex: 0x58A486)).frame(width: 16)
        }
    }

    private func start(_ p: TSPrompt, text: String = "") {
        promptText = text
        prompt = p
    }

    private func submit() {
        let name = promptText
        switch prompt {
        case .topic: model.createTopic(name, nested: false)
        case .subtopic: model.createTopic(name, nested: true)
        case .note: model.createNote(name)
        case .code: model.createCode(name)
        case .rename(let url): model.rename(url, to: name)
        case nil: break
        }
        prompt = nil
        promptText = ""
    }

    // MARK: main area

    @State private var showTagPopover = false
    @State private var newTag = ""

    private var main: some View {
        VStack(spacing: 0) {
            if let url = openNode {
                fileBar(url)
                Rectangle().fill(palette.border).frame(height: 1)
                if model.openExt == "board" {
                    WhiteboardView(key: model.whiteboardKey(for: url), subtitle: model.breadcrumb, palette: palette, theme: theme, toggleTheme: toggleTheme, embedded: true)
                        .id(url.path)
                } else if let list = model.todoList, model.openExt == "todo" {
                    TodoBoard(store: list, crumb: "Topic ToDo", title: url.deletingLastPathComponent().lastPathComponent, embedded: true, palette: palette, theme: theme, toggleTheme: toggleTheme)
                        .id(url.path)
                } else if isPage {
                    TSPageView(model: model, palette: palette).id(url.path)
                } else {
                    TSCodeEditor(text: model.text, fileName: url.lastPathComponent, isCode: true, jump: model.jump,
                                 onChange: model.edited, onDefinition: model.findDefinition, onUsages: model.findUsages)
                        .id(url.path)
                        .background(palette.surface)
                }
            } else {
                welcome
            }
            console
        }
    }

    private var fileIcon: String {
        switch model.openExt {
        case "board": return "scribble.variable"
        case "todo": return "checklist"
        case "page": return "note.text"
        default: return "chevron.left.forwardslash.chevron.right"
        }
    }

    private func fileBar(_ url: URL) -> some View {
        HStack(spacing: 8) {
            Image(systemName: fileIcon).foregroundStyle(palette.accent)
            Text(["page", "board", "todo"].contains(model.openExt) ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent).font(.system(size: 12, weight: .semibold)).lineLimit(1).help("Changes are saved automatically")
            Spacer(minLength: 4)
            ForEach(model.tags(of: url), id: \.self) { tag in
                Text("#" + tag).font(.system(size: 10, weight: .medium)).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(palette.accent.opacity(0.14), in: Capsule()).foregroundStyle(palette.accent)
                    .contextMenu { Button("Remove tag") { model.removeTag(tag, from: url) } }
            }
            Button { newTag = ""; showTagPopover = true } label: { Image(systemName: "tag").foregroundStyle(palette.muted) }
                .buttonStyle(.plain).help("Add a tag")
                .popover(isPresented: $showTagPopover) {
                    TextField("tag, then Return", text: $newTag).textFieldStyle(.roundedBorder).frame(width: 170).padding(10)
                        .onSubmit { model.addTag(newTag, to: url); newTag = ""; showTagPopover = false }
                }
            Button { model.toggleBookmark(url) } label: {
                Image(systemName: model.isBookmarked(url) ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(model.isBookmarked(url) ? Color(hex: 0xF5B301) : palette.muted)
            }.buttonStyle(.plain).help(model.isBookmarked(url) ? "Remove bookmark" : "Bookmark — pinned at the top of the sidebar")
            if model.canRun {
                TextField("flags, e.g. -O2 -fsanitize=address", text: $model.flags)
                    .textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced)).frame(minWidth: 90, maxWidth: 250)
                Button { model.stop() } label: { Label("Stop", systemImage: "stop.fill").fixedSize() }
                    .buttonStyle(PillButtonStyle(palette: palette))
                    .help("Interrupt the running program (Ctrl-C)")
                Button { showConsole = true; model.runCurrent() } label: { Label("Build & Run", systemImage: "play.fill").fixedSize() }
                    .buttonStyle(PillButtonStyle(palette: palette, prominent: true))
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Compile and run this file in the terminal (⌘↵)")
            }
        }
        .padding(.horizontal, 14).frame(height: 44).background(palette.surface)
    }

    private var welcome: some View {
        VStack(spacing: 12) {
            Image(systemName: "fork.knife").font(.system(size: 34, weight: .light)).foregroundStyle(Brand.gradient)
            Text("Study by topic").font(.system(size: 18, weight: .semibold, design: .rounded))
            Text("Make a topic like “C++ Memory Management”, add subtopics, and keep notes, a journal and experiment code side by side — then build and run it right here.")
                .font(.system(size: 12)).foregroundStyle(palette.muted).multilineTextAlignment(.center)
            Button { start(.topic) } label: { Label("New topic", systemImage: "folder.badge.plus") }
                .buttonStyle(PillButtonStyle(palette: palette, prominent: true))
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(palette.surface)
    }

    // MARK: terminal

    private var console: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { showConsole.toggle() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: showConsole ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .bold))
                        Text("TERMINAL").font(.system(size: 9, weight: .bold)).tracking(1.2)
                    }
                }.buttonStyle(.plain)
                Text(model.shellName).font(.system(size: 9)).foregroundStyle(Color(hex: 0x6F6C85))
                Spacer()
                Button("Open here") { model.terminal.cd(model.currentDir) }.buttonStyle(.plain).font(.system(size: 10)).help("cd into the selected topic folder")
                Button("Restart") { model.terminal.restart(in: model.currentDir) }.buttonStyle(.plain).font(.system(size: 10)).help("Start a fresh shell")
            }
            .foregroundStyle(Color(hex: 0xA9A6BD)).padding(.horizontal, 14).frame(height: 28)
            .background(Color(hex: 0x17151F))
            if showConsole {
                TSTerminalView(terminal: model.terminal)
                    .frame(height: 220)
                    .onAppear { model.terminal.start(in: model.currentDir) }
            }
        }.background(Color(hex: 0x0E0D14)).environment(\.colorScheme, .dark)
    }
}
