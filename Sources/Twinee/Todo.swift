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
    var title: String
    var status: TodoStatus = .bucket
    var notes: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

enum TodoScope: Hashable {
    case all
}

protocol TodoSource: ObservableObject {
    var todos: [TodoItem] { get }
    func addTodo(_ title: String)
    func moveTodo(_ id: UUID, to status: TodoStatus)
    func updateTodoTitle(_ id: UUID, _ title: String)
    func updateTodoNotes(_ id: UUID, _ notes: String)
    func deleteTodo(_ id: UUID)
}

extension WorkspaceStore: TodoSource {}

// The board that belongs to one TableSpoon topic or subtopic, kept in a .todo file inside its folder.
final class TSTodoList: ObservableObject, TodoSource {
    @Published private(set) var todos: [TodoItem] = []
    private let url: URL

    init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder.twinee.decode([TodoItem].self, from: data) { todos = saved }
    }

    private func persist() { try? JSONEncoder.twinee.encode(todos).write(to: url, options: .atomic) }

    func addTodo(_ title: String) { todos.append(TodoItem(title: title)); persist() }

    func moveTodo(_ id: UUID, to status: TodoStatus) {
        guard let i = todos.firstIndex(where: { $0.id == id }), todos[i].status != status else { return }
        withAnimation(.easeInOut(duration: 0.18)) { todos[i].status = status; todos[i].updatedAt = Date() }
        persist()
    }

    func updateTodoTitle(_ id: UUID, _ title: String) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].title = title; persist()
    }

    func updateTodoNotes(_ id: UUID, _ notes: String) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].notes = notes.isEmpty ? nil : notes; persist()
    }

    func deleteTodo(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.18)) { todos.removeAll { $0.id == id } }
        persist()
    }
}

extension WorkspaceStore {
    func openTodo() {
        todoScope = .all
    }

    var openTodoCount: Int { todos.filter { $0.status != .done }.count }

    func addTodo(_ title: String) {
        todos.append(TodoItem(title: title))
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

}

struct TodoBoard<Store: TodoSource>: View {
    @ObservedObject var store: Store
    var crumb = "ToDo"
    var title = "All tasks"
    var embedded = false
    let palette: Palette
    let theme: ThemeMode
    let toggleTheme: () -> Void
    @State private var newTitle = ""
    @State private var dropTarget: TodoStatus?

    private var scopedTodos: [TodoItem] { store.todos }

    private func items(_ status: TodoStatus) -> [TodoItem] {
        scopedTodos.filter { $0.status == status }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !embedded { topBar }
            VStack(alignment: .leading, spacing: 18) {
                header
                addRow
                HStack(alignment: .top, spacing: 14) {
                    ForEach(TodoStatus.allCases) { status in column(status) }
                }
                .frame(maxHeight: .infinity)
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
            Text(crumb).foregroundStyle(palette.muted)
            Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(palette.muted.opacity(0.65))
            Text(title).fontWeight(.medium).lineLimit(1)
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
                Text(crumb == "ToDo" ? "EVERYTHING TO DO, ONE PLACE" : "TASKS FOR THIS TOPIC").font(.system(size: 9, weight: .bold)).tracking(1.3).foregroundStyle(palette.accent)
                Text(title).font(.system(size: 28, weight: .bold, design: .rounded)).tracking(-0.8).lineLimit(1)
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
            Button("Add", action: addTask).buttonStyle(.borderedProminent).tint(palette.accent)
                .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.border, lineWidth: 1))
    }

    private func addTask() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        store.addTodo(title)
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
}
