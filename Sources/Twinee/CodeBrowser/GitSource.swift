import Foundation
import CryptoKit

struct RemoteSource: Codable, Equatable {
    var url: String
    var branch: String
}

struct CodeNote: Codable, Identifiable, Equatable {
    var id = UUID()
    var sourceKey: String
    var branch: String?
    var path: String
    // Zero-based line; nil for a note on the whole file.
    var line: Int?
    var text: String
    var createdAt = Date()
    var updatedAt = Date()
}

enum NoteSource {
    static func key(forRemote url: String) -> String {
        var value = url.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).lowercased()
        if value.hasSuffix(".git") { value = String(value.dropLast(4)) }
        return value
    }
}

private enum GitCLI {
    static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes"
        env["PATH"] = "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:" + (env["PATH"] ?? "")
        return env
    }

    struct Result {
        let status: Int32
        let output: String
    }

    // Blocking; call from a background queue.
    static func run(_ arguments: [String]) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.environment = environment()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return Result(status: -1, output: error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    static func lastLine(_ output: String) -> String {
        let lines = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lines.last(where: { $0.lowercased().hasPrefix("fatal") || $0.lowercased().hasPrefix("error") }) ?? lines.last ?? "git failed"
    }
}

extension CodeBrowserModel {
    private static var cacheRoot: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Twinee", isDirectory: true).appendingPathComponent("GitBrowse", isDirectory: true)
    }

    // A throwaway checkout used only for reading; it is never added to the repository list.
    static func checkoutURL(for remote: RemoteSource) -> URL {
        let digest = SHA256.hash(data: Data(NoteSource.key(forRemote: remote.url).utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let branch = remote.branch.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." ? $0 : "_" }
        return cacheRoot.appendingPathComponent(digest, isDirectory: true).appendingPathComponent(String(branch), isDirectory: true)
    }

    func fetchBranches(url rawURL: String, completion: @escaping (Result<(branches: [String], defaultBranch: String?), Error>) -> Void) {
        let url = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = GitModel.validate(url) ?? (url.isEmpty ? "Enter a repository URL." : nil) {
            completion(.failure(GitBrowseError(problem)))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = GitCLI.run(["ls-remote", "--symref", "--", url, "HEAD", "refs/heads/*"])
            var branches: [String] = []
            var head: String?
            for line in result.output.split(separator: "\n") {
                if line.hasPrefix("ref: refs/heads/") {
                    head = line.dropFirst("ref: refs/heads/".count).split(separator: "\t").first.map(String.init)
                } else if let range = line.range(of: "refs/heads/"), line.contains("\t") {
                    branches.append(String(line[range.upperBound...]))
                }
            }
            DispatchQueue.main.async {
                if result.status != 0 {
                    completion(.failure(GitBrowseError(GitCLI.lastLine(result.output))))
                } else if branches.isEmpty {
                    completion(.failure(GitBrowseError("No branches were found in that repository.")))
                } else {
                    completion(.success((branches.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }, head)))
                }
            }
        }
    }

    func browseRemote(url rawURL: String, branch: String) {
        let url = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isFetchingRemote, GitModel.validate(url) == nil, !url.isEmpty, !branch.isEmpty, !branch.hasPrefix("-") else { return }
        let remote = RemoteSource(url: url, branch: branch)
        let target = Self.checkoutURL(for: remote)
        isFetchingRemote = true
        remoteError = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var result = GitCLI.Result(status: 1, output: "")
            if fm.fileExists(atPath: target.appendingPathComponent(".git").path) {
                result = GitCLI.run(["-C", target.path, "fetch", "--depth", "1", "--no-tags", "origin", branch])
                if result.status == 0 { result = GitCLI.run(["-C", target.path, "reset", "--hard", "FETCH_HEAD"]) }
            }
            if result.status != 0 {
                try? fm.removeItem(at: target)
                try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                result = GitCLI.run(["clone", "--depth", "1", "--single-branch", "--no-tags", "--branch", branch, "--", url, target.path])
            }
            DispatchQueue.main.async {
                self.isFetchingRemote = false
                if result.status == 0 {
                    self.load(target, remote: remote)
                } else {
                    try? fm.removeItem(at: target)
                    self.remoteError = GitCLI.lastLine(result.output)
                }
            }
        }
    }

    func restoreRemoteIfNeeded() {
        guard root == nil, let remote = DevToolsStore.shared.codeRemote else { return }
        let target = Self.checkoutURL(for: remote)
        if FileManager.default.fileExists(atPath: target.appendingPathComponent(".git").path) {
            load(target, remote: remote)
        }
    }
}

struct GitBrowseError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: Notes

extension CodeBrowserModel {
    var notes: [CodeNote] {
        DevToolsStore.shared.codeNotes
            .filter { $0.sourceKey == sourceKey }
            .sorted { ($0.path, $0.line ?? -1) < ($1.path, $1.line ?? -1) }
    }

    var currentRelativePath: String? { currentPath.map(relativePath) }

    func noteLines(in path: String?) -> Set<Int> {
        guard let path else { return [] }
        let relative = relativePath(path)
        return Set(notes.filter { $0.path == relative }.compactMap(\.line))
    }

    func saveNote(_ note: CodeNote) {
        let store = DevToolsStore.shared
        let trimmed = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = store.codeNotes.firstIndex(where: { $0.id == note.id }) {
            if trimmed.isEmpty {
                store.codeNotes.remove(at: index)
            } else {
                var updated = note
                updated.text = trimmed
                updated.updatedAt = Date()
                store.codeNotes[index] = updated
            }
        } else if !trimmed.isEmpty {
            var created = note
            created.text = trimmed
            store.codeNotes.append(created)
        }
    }

    func deleteNote(_ id: UUID) {
        DevToolsStore.shared.codeNotes.removeAll { $0.id == id }
    }

    func newNote(line: Int?) -> CodeNote? {
        guard let path = currentRelativePath else { return nil }
        return CodeNote(sourceKey: sourceKey, branch: remote?.branch, path: path, line: line, text: "")
    }

    func open(_ note: CodeNote) {
        guard let root else { return }
        open(path: root.appendingPathComponent(note.path).path, line: note.line)
    }
}
