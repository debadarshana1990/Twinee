import SwiftUI
import AppKit

struct WBStroke: Codable, Identifiable, Equatable {
    var id = UUID()
    var points: [CGPoint]
    // -1 means "ink": dark on the white theme, light on the black theme.
    var hex: Int
    var width: Double
}

// Scribbles for every whiteboard, kept apart from the notes workspace. The key is "global" or a project id.
final class WhiteboardStore: ObservableObject {
    static let shared = WhiteboardStore()
    static let globalKey = "global"

    private var boards: [String: [WBStroke]] = [:]
    private let fileURL: URL
    private var saveTask: DispatchWorkItem?

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        fileURL = support.appendingPathComponent("Twinee", isDirectory: true).appendingPathComponent("whiteboards.json")
        if let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode([String: [WBStroke]].self, from: data) {
            boards = saved
        }
    }

    func strokes(for key: String) -> [WBStroke] { boards[key] ?? [] }

    func set(_ strokes: [WBStroke], for key: String) {
        boards[key] = strokes.isEmpty ? nil : strokes
        scheduleSave()
    }

    func remove(key: String) {
        boards[key] = nil
        scheduleSave()
    }

    func flush() {
        saveTask?.cancel()
        write()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.write() }
        saveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: task)
    }

    private func write() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(boards).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Twinee could not save the whiteboards: %@", error.localizedDescription)
        }
    }
}

struct WhiteboardView: View {
    let key: String
    let subtitle: String
    let palette: Palette
    let theme: ThemeMode
    let toggleTheme: () -> Void
    var embedded = false

    @State private var strokes: [WBStroke]
    @State private var current: WBStroke?
    @State private var undoStack: [[WBStroke]] = []
    @State private var erasing = false
    @State private var colorHex = -1
    @State private var lineWidth = 3.0
    @State private var confirmingClear = false
    @State private var erasedInDrag = false

    private static let colors: [Int] = [-1, 0xD6453D, 0xE08A2E, 0x3E9B6F, 0x3F7FD1, 0x8875E2]

    init(key: String, subtitle: String, palette: Palette, theme: ThemeMode, toggleTheme: @escaping () -> Void, embedded: Bool = false) {
        self.embedded = embedded
        self.key = key
        self.subtitle = subtitle
        self.palette = palette
        self.theme = theme
        self.toggleTheme = toggleTheme
        _strokes = State(initialValue: WhiteboardStore.shared.strokes(for: key))
    }

    private func color(_ hex: Int) -> Color {
        hex < 0 ? (palette.isDark ? Color(white: 0.93) : Color(hex: 0x24242C)) : Color(hex: UInt32(hex))
    }

    var body: some View {
        VStack(spacing: 0) {
            if !embedded { AppTopBar(title: "Whiteboard", subtitle: subtitle, palette: palette, theme: theme, toggleTheme: toggleTheme) }
            toolbar
            board
        }
        .background(palette.background)
        .preferredColorScheme(palette.isDark ? .dark : .light)
        .onDisappear { WhiteboardStore.shared.set(strokes, for: key); WhiteboardStore.shared.flush() }
        .confirmationDialog("Clear this whiteboard?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { commit { $0.removeAll() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Everything drawn here will be removed. You can undo this right away.") }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            toolButton("pencil.tip", selected: !erasing, help: "Pen") { erasing = false }
            toolButton("eraser", selected: erasing, help: "Eraser — drag across a stroke to remove it") { erasing = true }
            Rectangle().fill(palette.border).frame(width: 1, height: 18)
            ForEach(Self.colors, id: \.self) { hex in
                Button { colorHex = hex; erasing = false } label: {
                    Circle().fill(color(hex)).frame(width: 16, height: 16)
                        .overlay(Circle().stroke(palette.accent, lineWidth: colorHex == hex && !erasing ? 2 : 0).padding(-3))
                }.buttonStyle(.plain).help(hex < 0 ? "Ink" : "Colour")
            }
            Rectangle().fill(palette.border).frame(width: 1, height: 18)
            Image(systemName: "scribble").font(.system(size: 10)).foregroundStyle(palette.muted)
            Slider(value: $lineWidth, in: 1...12).frame(width: 90).controlSize(.small)
            Spacer()
            Button { undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .buttonStyle(PillButtonStyle(palette: palette)).keyboardShortcut("z", modifiers: .command).disabled(undoStack.isEmpty)
            Button { confirmingClear = true } label: { Label("Clear", systemImage: "trash") }
                .buttonStyle(PillButtonStyle(palette: palette)).disabled(strokes.isEmpty)
        }
        .padding(.horizontal, 24).frame(height: 44)
        .background(palette.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }
    }

    private func toolButton(_ symbol: String, selected: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12)).frame(width: 30, height: 26)
                .foregroundStyle(selected ? palette.accent : palette.muted)
                .background(selected ? palette.selected : .clear, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).help(help)
    }

    private var board: some View {
        Canvas { context, size in
            let spacing: CGFloat = 28
            var dots = Path()
            var y: CGFloat = spacing
            while y < size.height {
                var x: CGFloat = spacing
                while x < size.width { dots.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)); x += spacing }
                y += spacing
            }
            context.fill(dots, with: .color(palette.border.opacity(0.8)))
            for stroke in strokes + (current.map { [$0] } ?? []) {
                context.stroke(Self.path(for: stroke.points), with: .color(color(stroke.hex)), style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round))
            }
        }
        .background(palette.background)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if erasing {
                        if !erasedInDrag { undoStack.append(strokes); erasedInDrag = true }
                        erase(at: value.location)
                    } else if current == nil {
                        current = WBStroke(points: [value.location], hex: colorHex, width: lineWidth)
                    } else {
                        current?.points.append(value.location)
                    }
                }
                .onEnded { _ in
                    if erasing {
                        if erasedInDrag, undoStack.last == strokes { undoStack.removeLast() }
                        erasedInDrag = false
                        WhiteboardStore.shared.set(strokes, for: key)
                    } else if let finished = current {
                        undoStack.append(strokes)
                        strokes.append(finished)
                        current = nil
                        trimUndo()
                        WhiteboardStore.shared.set(strokes, for: key)
                    }
                }
        )
    }

    private static func path(for points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        if points.count == 1 {
            path.addEllipse(in: CGRect(x: first.x - 0.5, y: first.y - 0.5, width: 1, height: 1))
            return path
        }
        path.move(to: first)
        for index in 1..<points.count {
            let mid = CGPoint(x: (points[index - 1].x + points[index].x) / 2, y: (points[index - 1].y + points[index].y) / 2)
            path.addQuadCurve(to: mid, control: points[index - 1])
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    private func erase(at point: CGPoint) {
        let radius: CGFloat = 12
        strokes.removeAll { stroke in
            let reach = radius + stroke.width / 2
            if stroke.points.count == 1 { return hypot(stroke.points[0].x - point.x, stroke.points[0].y - point.y) <= reach }
            for index in 1..<stroke.points.count where Self.distance(from: point, toSegment: stroke.points[index - 1], stroke.points[index]) <= reach { return true }
            return false
        }
    }

    private static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    private func commit(_ change: (inout [WBStroke]) -> Void) {
        undoStack.append(strokes)
        change(&strokes)
        trimUndo()
        WhiteboardStore.shared.set(strokes, for: key)
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        strokes = previous
        WhiteboardStore.shared.set(strokes, for: key)
    }

    private func trimUndo() { if undoStack.count > 50 { undoStack.removeFirst(undoStack.count - 50) } }
}
