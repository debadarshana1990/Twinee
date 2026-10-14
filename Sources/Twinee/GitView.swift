import SwiftUI
import AppKit

final class GitModel: ObservableObject {
    enum Status: Equatable {
        case idle
        case running(String)
        case succeeded(String)
        case failed(String)
    }

    @Published var urlText = ""
    @Published private(set) var status = Status.idle
    @Published private(set) var progress = ""
    @Published private(set) var log = ""
    @Published private(set) var activeRepoID: UUID?
    @Published private(set) var lastClonedPath: String?

    private var process: Process?
    private var cancelled = false
    private var cloneTarget: URL?
    private let tools = DevToolsStore.shared

    var isRunning: Bool {
        if case .running = status { return true }
        return false
    }

    // Only remote transports are accepted so a pasted URL can't run a local command or be read as an option.
    static func validate(_ text: String) -> String? {
        let url = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty { return nil }
        if url.hasPrefix("-") { return "That doesn't look like a repository URL." }
        if url.contains(where: { $0.isWhitespace || $0.isNewline }) { return "The URL can't contain spaces." }
        let schemes = ["https://", "http://", "ssh://", "git://"]
        if schemes.contains(where: { url.lowercased().hasPrefix($0) }) { return url.count > 10 ? nil : "The URL is incomplete." }
        let scp = #"^[A-Za-z0-9._-]+@[A-Za-z0-9.-]+:[A-Za-z0-9._~/-]+$"#
        if url.range(of: scp, options: .regularExpression) != nil { return nil }
        return "Use an https://, ssh:// or git@host:owner/repo URL."
    }

    static func repoName(from url: String) -> String {
        var name = url.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).components(separatedBy: CharacterSet(charactersIn: "/:")).last ?? ""
        if name.hasSuffix(".git") { name = String(name.dropLast(4)) }
        let allowed = name.filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" }
        return allowed.isEmpty || allowed.hasPrefix(".") ? "repository" : allowed
    }

    func clone() {
        let url = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isRunning, !url.isEmpty, Self.validate(url) == nil else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Clone Here"
        panel.message = "Choose where to clone \(Self.repoName(from: url))"
        if let last = tools.cloneFolder { panel.directoryURL = URL(fileURLWithPath: last) }
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        tools.cloneFolder = parent.path

        let name = Self.repoName(from: url)
        let target = parent.appendingPathComponent(name, isDirectory: true)
        if FileManager.default.fileExists(atPath: target.path) {
            status = .failed("A folder named “\(name)” already exists in \(parent.path). Choose another location.")
            return
        }
        cloneTarget = target
        log = ""
        lastClonedPath = nil
        run(["clone", "--progress", "--", url, target.path], directory: parent, title: "Cloning \(name)…") { [self] code in
            if cancelled {
                try? FileManager.default.removeItem(at: target)
                status = .idle
            } else if code == 0 {
                tools.repos.insert(RepoEntry(name: name, url: url, path: target.path), at: 0)
                lastClonedPath = target.path
                status = .succeeded("Cloned into \(target.path)")
            } else {
                status = .failed("git clone failed (exit code \(code)). See the log below.")
            }
            cloneTarget = nil
        }
    }

    func pull(_ repo: RepoEntry) {
        guard !isRunning else { return }
        guard FileManager.default.fileExists(atPath: repo.path) else {
            status = .failed("The folder for “\(repo.name)” is missing: \(repo.path)")
            return
        }
        log = ""
        activeRepoID = repo.id
        run(["-C", repo.path, "pull", "--ff-only", "--progress"], directory: nil, title: "Pulling \(repo.name)…") { [self] code in
            activeRepoID = nil
            if cancelled {
                status = .idle
            } else if code == 0 {
                if let index = tools.repos.firstIndex(where: { $0.id == repo.id }) { tools.repos[index].lastPulled = Date() }
                status = .succeeded("\(repo.name) is up to date")
            } else {
                status = .failed("git pull failed (exit code \(code)). If the branches have diverged, pull in a terminal to merge or rebase.")
            }
        }
    }

    func addExisting() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder that is already a git repository"
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent(".git").path) else {
            status = .failed("“\(folder.lastPathComponent)” is not a git repository.")
            return
        }
        guard !tools.repos.contains(where: { $0.path == folder.path }) else {
            status = .failed("“\(folder.lastPathComponent)” is already in your list.")
            return
        }
        let remote = Self.output(of: ["-C", folder.path, "remote", "get-url", "origin"]) ?? ""
        tools.repos.insert(RepoEntry(name: folder.lastPathComponent, url: remote, path: folder.path), at: 0)
        status = .succeeded("Added \(folder.lastPathComponent)")
    }

    func remove(_ repo: RepoEntry) {
        tools.repos.removeAll { $0.id == repo.id }
    }

    func cancel() {
        guard isRunning else { return }
        cancelled = true
        process?.terminate()
    }

    private static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_MERGE_AUTOEDIT"] = "no"
        env["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes"
        env["PATH"] = "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:" + (env["PATH"] ?? "")
        return env
    }

    private static func output(of arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.environment = environment()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }

    private func run(_ arguments: [String], directory: URL?, title: String, finish: @escaping (Int32) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.environment = Self.environment()
        if let directory { process.currentDirectoryURL = directory }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        cancelled = false
        progress = ""
        status = .running(title)
        self.process = process

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            if let chunk = String(data: data, encoding: .utf8) { DispatchQueue.main.async { self?.consume(chunk) } }
        }
        process.terminationHandler = { [weak self] finished in
            pipe.fileHandleForReading.readabilityHandler = nil
            let rest = pipe.fileHandleForReading.readDataToEndOfFile()
            DispatchQueue.main.async {
                if let self {
                    if !rest.isEmpty, let chunk = String(data: rest, encoding: .utf8) { self.consume(chunk) }
                    self.process = nil
                    finish(finished.terminationStatus)
                }
            }
        }
        do {
            try process.run()
        } catch {
            self.process = nil
            status = .failed("Could not start git: \(error.localizedDescription)")
        }
    }

    // Git redraws progress with carriage returns, so only finished lines go to the log.
    private func consume(_ chunk: String) {
        let pieces = chunk.components(separatedBy: CharacterSet(charactersIn: "\r\n")).filter { !$0.isEmpty }
        if let last = pieces.last { progress = last }
        for piece in pieces where !piece.contains("%") || piece.contains("done") {
            log += piece + "\n"
        }
    }
}

struct GitView: View {
    @ObservedObject var model: GitModel
    @ObservedObject private var tools = DevToolsStore.shared
    let palette: Palette
    let theme: ThemeMode
    let toggleTheme: () -> Void
    let openInCodeBrowser: (URL) -> Void

    private var validation: String? { GitModel.validate(model.urlText) }
    private var canClone: Bool { !model.urlText.trimmingCharacters(in: .whitespaces).isEmpty && validation == nil && !model.isRunning }

    var body: some View {
        VStack(spacing: 0) {
            AppTopBar(title: "Git Pull", subtitle: "Clone and update repositories", palette: palette, theme: theme, toggleTheme: toggleTheme)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    cloneCard
                    statusArea
                    reposCard
                }
                .frame(maxWidth: 820, alignment: .leading)
                .padding(.horizontal, 28).padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .background(palette.background)
        .preferredColorScheme(palette.isDark ? .dark : .light)
    }

    private var cloneCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CLONE A REPOSITORY").font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(palette.muted)
            HStack(spacing: 10) {
                Image(systemName: "link").foregroundStyle(palette.muted)
                TextField("https://github.com/owner/repo.git", text: $model.urlText)
                    .textFieldStyle(.plain).font(.system(size: 12, design: .monospaced))
                    .onSubmit { if canClone { model.clone() } }
                Button { model.clone() } label: { Label("Clone…", systemImage: "arrow.down.circle") }
                    .buttonStyle(PillButtonStyle(palette: palette, prominent: true)).disabled(!canClone)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(palette.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(validation == nil ? palette.border : Color.red.opacity(0.7), lineWidth: 1))
            if let validation {
                Text(validation).font(.system(size: 10)).foregroundStyle(Color.red)
            } else {
                Text("You'll be asked where to put it. Private repositories need credentials already saved in your keychain or an SSH key loaded in your agent.")
                    .font(.system(size: 10)).foregroundStyle(palette.muted)
            }
        }.devCard(palette)
    }

    @ViewBuilder
    private var statusArea: some View {
        switch model.status {
        case .idle:
            EmptyView()
        case .running(let title):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button("Cancel") { model.cancel() }.buttonStyle(PillButtonStyle(palette: palette))
                }
                Text(model.progress).font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.muted).lineLimit(2)
                logView
            }.devCard(palette)
        case .succeeded(let message):
            VStack(alignment: .leading, spacing: 10) {
                Label(message, systemImage: "checkmark.circle.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: 0x58A486))
                if let path = model.lastClonedPath {
                    HStack(spacing: 8) {
                        Button { openInCodeBrowser(URL(fileURLWithPath: path)) } label: { Label("Open in Code Browser", systemImage: "chevron.left.forwardslash.chevron.right") }
                            .buttonStyle(PillButtonStyle(palette: palette, prominent: true))
                        Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) } label: { Label("Show in Finder", systemImage: "folder") }
                            .buttonStyle(PillButtonStyle(palette: palette))
                    }
                }
                if !model.log.isEmpty { logView }
            }.devCard(palette)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.red)
                if !model.log.isEmpty { logView }
            }.devCard(palette)
        }
    }

    private var logView: some View {
        ScrollView {
            Text(model.log.isEmpty ? " " : model.log)
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.muted)
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
        .frame(height: 110)
        .background(palette.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border, lineWidth: 1))
    }

    private var reposCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("YOUR REPOSITORIES").font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(palette.muted)
                Spacer()
                Button { model.addExisting() } label: { Label("Add existing…", systemImage: "plus") }
                    .buttonStyle(PillButtonStyle(palette: palette))
            }
            if tools.repos.isEmpty {
                Text("Repositories you clone here will be listed so you can pull the latest changes with one click.")
                    .font(.system(size: 11)).foregroundStyle(palette.muted).padding(.vertical, 8)
            }
            ForEach(tools.repos) { repo in repoRow(repo) }
        }.devCard(palette)
    }

    private func repoRow(_ repo: RepoEntry) -> some View {
        let exists = FileManager.default.fileExists(atPath: repo.path)
        return HStack(spacing: 12) {
            Image(systemName: "externaldrive.connected.to.line.under").foregroundStyle(exists ? palette.accent : palette.muted).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(repo.name).font(.system(size: 12, weight: .semibold))
                Text(repo.path).font(.system(size: 9)).foregroundStyle(palette.muted).lineLimit(1).truncationMode(.head)
                Text(repo.lastPulled.map { "Last pulled " + $0.formatted(.relative(presentation: .named)) } ?? (exists ? "Cloned " + repo.clonedAt.formatted(.relative(presentation: .named)) : "Folder not found"))
                    .font(.system(size: 9)).foregroundStyle(palette.muted)
            }
            Spacer()
            if model.activeRepoID == repo.id { ProgressView().controlSize(.small) }
            Button { model.pull(repo) } label: { Label("Pull", systemImage: "arrow.down.to.line") }
                .buttonStyle(PillButtonStyle(palette: palette, prominent: true)).disabled(model.isRunning || !exists)
            Menu {
                Button("Open in Code Browser") { openInCodeBrowser(URL(fileURLWithPath: repo.path)) }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: repo.path)]) }
                Button("Open in Terminal") { Self.openTerminal(repo.path) }
                if !repo.url.isEmpty { Button("Copy URL") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(repo.url, forType: .string) } }
                Divider()
                Button("Remove from list", role: .destructive) { model.remove(repo) }
            } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize().disabled(!exists && repo.path.isEmpty)
        }
        .padding(10)
        .background(palette.background, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(palette.border, lineWidth: 1))
    }

    private static func openTerminal(_ path: String) {
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }
}

extension View {
    func devCard(_ palette: Palette) -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border, lineWidth: 1))
    }
}
