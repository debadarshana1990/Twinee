import SwiftUI

enum DevApp: String, CaseIterable, Identifiable {
    case tablespoon, whiteboard, compare, code, git, timer, launcher

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tablespoon: return "TableSpoon"
        case .whiteboard: return "Whiteboard"
        case .compare: return "Compare"
        case .code: return "Code Browser"
        case .git: return "Git Pull"
        case .timer: return "Timer"
        case .launcher: return "Launcher"
        }
    }

    var tint: Color {
        switch self {
        case .tablespoon: return Color(hex: 0xFF7A3D)
        case .whiteboard: return Color(hex: 0xE8517E)
        case .compare: return Color(hex: 0x2F9BD8)
        case .code: return Color(hex: 0x37B26C)
        case .git: return Color(hex: 0xF08A24)
        case .timer: return Color(hex: 0xE5484D)
        case .launcher: return Color(hex: 0x8E5CE6)
        }
    }

    var symbol: String {
        switch self {
        case .tablespoon: return "fork.knife"
        case .whiteboard: return "scribble.variable"
        case .compare: return "arrow.left.arrow.right.square"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .git: return "arrow.down.circle"
        case .timer: return "timer"
        case .launcher: return "square.grid.2x2"
        }
    }
}

struct RepoEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var url: String
    var path: String
    var clonedAt = Date()
    var lastPulled: Date?
}

struct LauncherApp: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var path: String
}

struct FocusSession: Codable, Identifiable, Equatable {
    var id = UUID()
    var label: String
    var start: Date
    var seconds: Int
}

struct TimerSettings: Codable, Equatable {
    var focusMinutes = 25
    var shortBreakMinutes = 5
    var longBreakMinutes = 15
    var autoStartNext = false
}

private struct DevToolsData: Codable {
    var repos: [RepoEntry] = []
    var apps: [LauncherApp] = []
    var sessions: [FocusSession] = []
    var timer = TimerSettings()
    var codeFolder: String?
    var cloneFolder: String?
    var codeRemote: RemoteSource?
    var codeNotes: [CodeNote] = []

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        repos = try values.decodeIfPresent([RepoEntry].self, forKey: .repos) ?? []
        apps = try values.decodeIfPresent([LauncherApp].self, forKey: .apps) ?? []
        sessions = try values.decodeIfPresent([FocusSession].self, forKey: .sessions) ?? []
        timer = try values.decodeIfPresent(TimerSettings.self, forKey: .timer) ?? TimerSettings()
        codeFolder = try values.decodeIfPresent(String.self, forKey: .codeFolder)
        cloneFolder = try values.decodeIfPresent(String.self, forKey: .cloneFolder)
        codeRemote = try values.decodeIfPresent(RemoteSource.self, forKey: .codeRemote)
        codeNotes = try values.decodeIfPresent([CodeNote].self, forKey: .codeNotes) ?? []
    }
}

// Settings and history for the developer apps, kept apart from the notes workspace.
final class DevToolsStore: ObservableObject {
    static let shared = DevToolsStore()

    @Published var repos: [RepoEntry] = [] { didSet { save() } }
    @Published var apps: [LauncherApp] = [] { didSet { save() } }
    @Published var sessions: [FocusSession] = [] { didSet { save() } }
    @Published var timer = TimerSettings() { didSet { save() } }
    @Published var codeFolder: String? { didSet { save() } }
    @Published var cloneFolder: String? { didSet { save() } }
    @Published var codeRemote: RemoteSource? { didSet { save() } }
    @Published var codeNotes: [CodeNote] = [] { didSet { save() } }

    private let fileURL: URL
    private var isLoading = true

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        fileURL = support.appendingPathComponent("Twinee", isDirectory: true).appendingPathComponent("devtools.json")
        if let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder.twinee.decode(DevToolsData.self, from: data) {
            repos = saved.repos
            apps = saved.apps
            sessions = saved.sessions
            timer = saved.timer
            codeFolder = saved.codeFolder
            cloneFolder = saved.cloneFolder
            codeRemote = saved.codeRemote
            codeNotes = saved.codeNotes
        }
        isLoading = false
    }

    private func save() {
        guard !isLoading else { return }
        var data = DevToolsData()
        data.repos = repos
        data.apps = apps
        data.sessions = sessions
        data.timer = timer
        data.codeFolder = codeFolder
        data.cloneFolder = cloneFolder
        data.codeRemote = codeRemote
        data.codeNotes = codeNotes
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder.twinee.encode(data).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Twinee could not save developer tool data: %@", error.localizedDescription)
        }
    }
}

extension WorkspaceStore {
    func openApp(_ app: DevApp) {
        todoScope = nil
        activeApp = app
    }
}
