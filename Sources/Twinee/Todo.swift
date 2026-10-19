import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum TodoStatus: String, Codable, CaseIterable, Identifiable {
    case bucket, ongoing, done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bucket: return "Bucket"
        case .ongoing: return "Ongoing"
        case .done: return "Done"
        }
    }

    var symbol: String {
        switch self {
        case .bucket: return "circle"
        case .ongoing: return "circle.lefthalf.filled"
        case .done: return "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .bucket: return Color(hex: 0x8E8E99)
        case .ongoing: return Color(hex: 0xD99162)
        case .done: return Color(hex: 0x58A486)
        }
    }

    var next: TodoStatus {
        switch self {
        case .bucket: return .ongoing
        case .ongoing: return .done
        case .done: return .bucket
        }
    }
}

struct TodoItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var projectID: UUID
    var title: String
    var status: TodoStatus = .bucket
    var notes: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

enum TodoScope: Hashable {
    case all
    case project(UUID)
}

extension WorkspaceStore {
    func renameProject(id: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].name = trimmed
        persist()
    }

    // Removes the project together with its topics and tasks, then moves the selection somewhere valid.
    func deleteProject(id: UUID) {
        topics.removeAll { $0.projectID == id }
        todos.removeAll { $0.projectID == id }
        projects.removeAll { $0.id == id }
        WhiteboardStore.shared.remove(key: id.uuidString)
        if whiteboardProjectID == id { whiteboardProjectID = nil; activeApp = nil }

        let topicRemoved = selectedTopicID.map { selected in !topics.contains { $0.id == selected } } ?? false
        var scopeRemoved = false
        if case .project(let scopeID) = todoScope, scopeID == id { scopeRemoved = true }
        if selectedProjectID == id { selectedProjectID = projects.first?.id }
        if topicRemoved { selectedTopicID = nil }
        if topicRemoved || scopeRemoved { todoScope = projects.first.map { TodoScope.project($0.id) } }
        persist()
    }

    func openTodo(_ scope: TodoScope) {
        todoScope = scope
        selectedTopicID = nil
        if case .project(let id) = scope { selectedProjectID = id }
    }

    func openTodoCount(for projectID: UUID?) -> Int {
        todos.filter { $0.status != .done && (projectID == nil || $0.projectID == projectID) }.count
    }

    func addTodo(_ title: String, projectID: UUID) {
        todos.append(TodoItem(projectID: projectID, title: title))
        persist()
    }

    func moveTodo(_ id: UUID, to status: TodoStatus) {
        guard let index = todos.firstIndex(where: { $0.id == id }), todos[index].status != status else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            todos[index].status = status
            todos[index].updatedAt = Date()
        }
        persist()
    }

    func updateTodoTitle(_ id: UUID, _ title: String) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].title = title
        persist()
    }

    func updateTodoNotes(_ id: UUID, _ notes: String) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].notes = notes.isEmpty ? nil : notes
        persist()
    }

    func deleteTodo(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.18)) { todos.removeAll { $0.id == id } }
        persist()
    }

    func setTodoNotes(_ data: Data, for projectID: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[index].todoNotes = data.isEmpty ? nil : data
        persist()
    }
}

struct TodoBoard: View {
    @ObservedObject var store: WorkspaceStore
    let scope: TodoScope
    let palette: Palette
    let theme: ThemeMode
    let toggleTheme: () -> Void
    @State private var newTitle = ""
    @State private var targetProjectID: UUID?
    @State private var dropTarget: TodoStatus?
    @State private var notesExpanded = true
    @StateObject private var notesEditor = EditorController()

    private var scopedProject: Project? {
        guard case .project(let id) = scope else { return nil }
        return store.projects.first { $0.id == id }
    }

    private var scopedTodos: [TodoItem] {
        switch scope {
        case .all: return store.todos
        case .project(let id): return store.todos.filter { $0.projectID == id }
        }
    }

    private var addProjectID: UUID? { scopedProject?.id ?? targetProjectID ?? store.selectedProjectID ?? store.projects.first?.id }

    private func items(_ status: TodoStatus) -> [TodoItem] {
        scopedTodos.filter { $0.status == status }.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func color(for projectID: UUID) -> Color {
        ProjectPalette.color(store.projects.firstIndex { $0.id == projectID } ?? 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            VStack(alignment: .leading, spacing: 18) {
                header
                addRow
                HStack(alignment: .top, spacing: 14) {
                    ForEach(TodoStatus.allCases) { status in column(status) }
                }
                .frame(maxHeight: .infinity)
                if let project = scopedProject { notesBox(project) }
            }
            .frame(maxWidth: 1120, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 34).padding(.top, 24).padding(.bottom, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(palette.background)
        }
        .background(palette.background)
        .preferredColorScheme(palette.isDark ? .dark : .light)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Text("ToDo").foregroundStyle(palette.muted)
            Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(palette.muted.opacity(0.65))
            Text(scopedProject?.name ?? "All tasks").fontWeight(.medium).lineLimit(1)
            Spacer()
            Picker("Theme", selection: Binding(get: { theme }, set: { _ in toggleTheme() })) {
                Text("White").tag(ThemeMode.white)
                Text("Black").tag(ThemeMode.black)
            }.pickerStyle(.segmented).frame(width: 116).help("Choose the white or black theme")
        }
        .font(.system(size: 10))
        .padding(.horizontal, 24).frame(height: 52)
        .background(palette.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }
    }

    private var header: some View {
        let total = scopedTodos.count
        let done = scopedTodos.filter { $0.status == .done }.count
        return HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(scopedProject == nil ? "EVERY PROJECT, ONE PLACE" : "PROJECT TODO").font(.system(size: 9, weight: .bold)).tracking(1.3).foregroundStyle(palette.accent)
                Text(scopedProject?.name ?? "All tasks").font(.system(size: 28, weight: .bold, design: .rounded)).tracking(-0.8).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(total == 0 ? "No tasks yet" : "\(done) of \(total) done").font(.system(size: 10, weight: .medium)).foregroundStyle(palette.muted)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.border)
                        Capsule().fill(TodoStatus.done.tint).frame(width: total == 0 ? 0 : geometry.size.width * CGFloat(done) / CGFloat(total))
                    }
                }.frame(width: 150, height: 5)
            }
        }
    }

    private var addRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill").font(.system(size: 15)).foregroundStyle(palette.accent)
            TextField("Add a task to Bucket and press Return…", text: $newTitle)
                .textFieldStyle(.plain).font(.system(size: 12)).onSubmit(addTask)
            if scopedProject == nil, !store.projects.isEmpty {
                Picker("Project", selection: Binding(get: { addProjectID }, set: { targetProjectID = $0 })) {
                    ForEach(store.projects) { Text($0.name).tag(Optional($0.id)) }
                }.labelsHidden().frame(width: 160)
            }
            Button("Add", action: addTask).buttonStyle(.borderedProminent).tint(palette.accent)
                .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || addProjectID == nil)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.border, lineWidth: 1))
    }

    private func addTask() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let projectID = addProjectID else { return }
        store.addTodo(title, projectID: projectID)
        newTitle = ""
    }

    private func column(_ status: TodoStatus) -> some View {
        let columnItems = items(status)
        let isTarget = dropTarget == status
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: status.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(status.tint)
                Text(status.title).font(.system(size: 12, weight: .semibold))
                Text("\(columnItems.count)").font(.system(size: 9, weight: .medium)).foregroundStyle(palette.muted)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(palette.border.opacity(0.7), in: Capsule())
                Spacer()
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(columnItems) { card($0) }
                    if columnItems.isEmpty {
                        Text(emptyHint(status)).font(.system(size: 10)).foregroundStyle(palette.muted)
                            .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 26)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.surface.opacity(palette.isDark ? 0.7 : 0.8), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isTarget ? palette.accent : palette.border, lineWidth: isTarget ? 1.5 : 1))
        .onDrop(of: [UTType.text], isTargeted: Binding(
            get: { dropTarget == status },
            set: { targeted in
                if targeted { dropTarget = status } else if dropTarget == status { dropTarget = nil }
            }
        )) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let string = object as? NSString, let id = UUID(uuidString: string as String) else { return }
                DispatchQueue.main.async { store.moveTodo(id, to: status) }
            }
            return true
        }
    }

    private func emptyHint(_ status: TodoStatus) -> String {
        switch status {
        case .bucket: return "Ideas and tasks waiting\nfor their turn"
        case .ongoing: return "Drag a task here\nwhen you start it"
        case .done: return "Finished tasks\nland here"
        }
    }

    private func card(_ item: TodoItem) -> some View {
        let isDone = item.status == .done
        return HStack(alignment: .top, spacing: 9) {
            Button { store.moveTodo(item.id, to: item.status.next) } label: {
                Image(systemName: item.status.symbol).font(.system(size: 15)).foregroundStyle(item.status.tint)
            }.buttonStyle(.plain).help("Move to \(item.status.next.title)")
            VStack(alignment: .leading, spacing: 5) {
                TextField("Task", text: Binding(get: { item.title }, set: { store.updateTodoTitle(item.id, $0) }), axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 12, weight: .medium)).lineLimit(1...5)
                    .strikethrough(isDone).foregroundStyle(isDone ? palette.muted : palette.text)
                if scopedProject == nil, let project = store.projects.first(where: { $0.id == item.projectID }) {
                    HStack(spacing: 5) {
                        Circle().fill(color(for: project.id)).frame(width: 5, height: 5)
                        Text(project.name).font(.system(size: 9)).foregroundStyle(palette.muted).lineLimit(1)
                    }
                }
                TextField("Add a note…", text: Binding(get: { item.notes ?? "" }, set: { store.updateTodoNotes(item.id, $0) }), axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 10)).lineLimit(2...6)
                    .foregroundStyle(palette.muted)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.surface.opacity(palette.isDark ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.border, lineWidth: 1))
            }
            Spacer(minLength: 0)
            Menu {
                ForEach(TodoStatus.allCases.filter { $0 != item.status }) { status in
                    Button("Move to \(status.title)") { store.moveTodo(item.id, to: status) }
                }
                Divider()
                Button("Delete task", role: .destructive) { store.deleteTodo(item.id) }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 11)).foregroundStyle(palette.muted).frame(width: 18, height: 18)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .padding(10)
        .background(palette.background, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(palette.border, lineWidth: 1))
        .onDrag { NSItemProvider(object: item.id.uuidString as NSString) }
    }

    private func notesBox(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.easeInOut(duration: 0.15)) { notesExpanded.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: notesExpanded ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(palette.muted).frame(width: 10)
                    Image(systemName: "note.text").font(.system(size: 12)).foregroundStyle(palette.accent)
                    Text("Notes").font(.system(size: 12, weight: .semibold))
                    Text("Free space for anything about \(project.name)").font(.system(size: 10)).foregroundStyle(palette.muted).lineLimit(1)
                    Spacer()
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if notesExpanded {
                FormatBar(editor: notesEditor, palette: palette, showsTip: false)
                TodoNotes(project: project, store: store, controller: notesEditor)
                    .frame(height: 140)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.border, lineWidth: 1))
            }
        }
    }
}

private struct TodoNotes: View {
    let project: Project
    let store: WorkspaceStore
    let controller: EditorController
    @State private var data: Data
    @State private var saveTask: DispatchWorkItem?

    init(project: Project, store: WorkspaceStore, controller: EditorController) {
        self.project = project
        self.store = store
        self.controller = controller
        _data = State(initialValue: project.todoNotes ?? Data())
    }

    var body: some View {
        RichTextEditor(data: $data, controller: controller)
            .onChange(of: data) { updated in
                saveTask?.cancel()
                let task = DispatchWorkItem { store.setTodoNotes(updated, for: project.id) }
                saveTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: task)
            }
            .onDisappear {
                guard saveTask != nil else { return }
                saveTask?.cancel()
                store.setTodoNotes(data, for: project.id)
            }
    }
}

enum ProjectPalette {
    static func color(_ index: Int) -> Color {
        [Color(hex: 0x7C5CFF), Color(hex: 0xFF8A3D), Color(hex: 0x1FB57A), Color(hex: 0x2F8CFF), Color(hex: 0xFF4F8B)][index % 5]
    }
}
