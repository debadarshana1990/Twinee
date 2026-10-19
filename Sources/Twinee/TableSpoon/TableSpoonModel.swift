import SwiftUI
import AppKit

struct TSNode: Identifiable, Hashable {
    let url: URL
    let isDir: Bool
    var children: [TSNode] = []
    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var ext: String { isDir ? "" : url.pathExtension.lowercased() }
    var isPage: Bool { ext == "page" }
    var isBoard: Bool { ext == "board" }
    var isTodo: Bool { ext == "todo" }
    var displayName: String { isPage || isBoard || isTodo ? url.deletingPathExtension().lastPathComponent : name }
}

struct TSMeta: Codable, Equatable {
    var bookmarked = false
    var tags: [String] = []
    var isEmpty: Bool { !bookmarked && tags.isEmpty }
}

struct TSJump: Equatable {
    let token = UUID()
    let line: Int
}

// A study workspace kept as plain folders and files: topic → subtopic → notes, journal entries and experiment code.
@MainActor
final class TableSpoonModel: ObservableObject {
    @Published var tree: [TSNode] = []
    @Published var expanded: Set<String> = []
    @Published var selected: String?
    @Published private(set) var openPath: String?
    @Published var text = ""
    @Published var jump: TSJump?
    @Published private(set) var openIsPage = false
    @Published private(set) var openExt = ""
    private(set) var todoList: TSTodoList?
    @Published var flags = ""
    @Published private(set) var meta: [String: TSMeta] = [:]

    let root: URL
    private var saveWork: DispatchWorkItem?
    let terminal = TSTerminal()
    private var pageData = Data()
    private var dirty = false

    init() {
        let fm = FileManager.default
        root = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Twinee/TableSpoon", isDirectory: true)
        let fresh = !fm.fileExists(atPath: root.path)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        if fresh { seedSample() }
        migrateMarkdown()
        loadMeta()
        reload(expandAll: true)
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in self?.flush() }
    }

    // MARK: bookmarks and tags

    private var metaURL: URL { root.appendingPathComponent(".tablespoon-meta.json") }

    private func loadMeta() {
        if let data = try? Data(contentsOf: metaURL), let m = try? JSONDecoder().decode([String: TSMeta].self, from: data) { meta = m }
    }

    private func saveMeta() {
        meta = meta.filter { !$0.value.isEmpty }
        if let data = try? JSONEncoder().encode(meta) { try? data.write(to: metaURL, options: .atomic) }
    }

    private func metaKey(_ url: URL) -> String { relativePath(url.path) }

    func isBookmarked(_ url: URL) -> Bool { meta[metaKey(url)]?.bookmarked == true }
    func tags(of url: URL) -> [String] { meta[metaKey(url)]?.tags ?? [] }

    func toggleBookmark(_ url: URL) {
        var m = meta[metaKey(url)] ?? TSMeta()
        m.bookmarked.toggle()
        meta[metaKey(url)] = m
        saveMeta()
    }

    func addTag(_ raw: String, to url: URL) {
        let tag = raw.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "#"))).lowercased()
        guard !tag.isEmpty else { return }
        var m = meta[metaKey(url)] ?? TSMeta()
        if !m.tags.contains(tag) { m.tags.append(tag) }
        meta[metaKey(url)] = m
        saveMeta()
    }

    func removeTag(_ tag: String, from url: URL) {
        guard var m = meta[metaKey(url)] else { return }
        m.tags.removeAll { $0 == tag }
        meta[metaKey(url)] = m
        saveMeta()
    }

    var allTags: [String] { Array(Set(meta.values.flatMap(\.tags))).sorted() }

    func allNodes() -> [TSNode] {
        var out: [TSNode] = []
        func walk(_ nodes: [TSNode]) { for n in nodes { out.append(n); walk(n.children) } }
        walk(tree)
        return out
    }

    var bookmarkedNodes: [TSNode] { allNodes().filter { !$0.isDir && isBookmarked($0.url) } }

    /// Matches names, `#tag`, or plain text against tags.
    func search(_ query: String) -> [TSNode] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let tagQuery = q.hasPrefix("#") ? String(q.dropFirst()).lowercased() : nil
        return allNodes().filter { node in
            let t = tags(of: node.url)
            if let tq = tagQuery { return !tq.isEmpty && t.contains { $0.contains(tq) } }
            return node.displayName.localizedCaseInsensitiveContains(q) || t.contains { $0.contains(q.lowercased()) }
        }
    }

    private func remapMeta(from old: String, to new: String) {
        var m: [String: TSMeta] = [:]
        for (k, v) in meta {
            if k == old || k.hasPrefix(old + "/") { m[new + k.dropFirst(old.count)] = v } else { m[k] = v }
        }
        meta = m
        saveMeta()
    }

    // MARK: tree

    func reload(expandAll: Bool = false) {
        tree = Self.scan(root)
        guard expandAll else { return }
        func walk(_ nodes: [TSNode]) { for node in nodes where node.isDir { expanded.insert(node.id); walk(node.children) } }
        walk(tree)
    }

    private static func scan(_ dir: URL) -> [TSNode] {
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return items
            .filter { !$0.lastPathComponent.hasSuffix(".out") && !$0.lastPathComponent.hasSuffix(".dSYM") }
            .map { url in
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return TSNode(url: url, isDir: isDir, children: isDir ? scan(url) : [])
            }
            .sorted { $0.isDir != $1.isDir ? $0.isDir : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func visibleRows() -> [(node: TSNode, depth: Int)] {
        var rows: [(TSNode, Int)] = []
        func walk(_ nodes: [TSNode], _ depth: Int) {
            for node in nodes {
                rows.append((node, depth))
                if node.isDir && expanded.contains(node.id) { walk(node.children, depth + 1) }
            }
        }
        walk(tree, 0)
        return rows
    }

    func tap(_ node: TSNode) {
        selected = node.id
        if node.isDir {
            if expanded.contains(node.id) { expanded.remove(node.id) } else { expanded.insert(node.id) }
        } else {
            open(node.id)
        }
    }

    var currentDir: URL {
        guard let selected else { return root }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: selected, isDirectory: &isDir)
        let url = URL(fileURLWithPath: selected)
        return isDir.boolValue ? url : url.deletingLastPathComponent()
    }

    func relativePath(_ path: String) -> String {
        path.hasPrefix(root.path + "/") ? String(path.dropFirst(root.path.count + 1)) : path
    }

    var shellName: String { (ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh") }

    var breadcrumb: String {
        guard let selected else { return "Study by topic" }
        return relativePath(selected).replacingOccurrences(of: ".page", with: "").components(separatedBy: "/").joined(separator: "  ›  ")
    }

    // MARK: creating things

    private func clean(_ name: String) -> String? {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        return value.isEmpty || value.hasPrefix(".") ? nil : value
    }

    private func unique(_ dir: URL, _ name: String) -> URL {
        var url = dir.appendingPathComponent(name)
        var n = 2
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return url
    }

    private func write(_ url: URL, _ content: String) {
        do { try content.write(to: url, atomically: true, encoding: .utf8) } catch { log("Could not write \(url.lastPathComponent): \(error.localizedDescription)\n") }
    }

    private func writePage(_ url: URL, markdown: String) {
        let data = RichText.encode(RichText.document(fromMarkdown: markdown))
        do { try data.write(to: url, options: .atomic) } catch { log("Could not write \(url.lastPathComponent): \(error.localizedDescription)\n") }
    }

    // Earlier versions kept notes as Markdown; they become rich pages.
    private func migrateMarkdown() {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        for case let url as URL in walker where url.pathExtension.lowercased() == "md" {
            let page = url.deletingPathExtension().appendingPathExtension("page")
            guard !FileManager.default.fileExists(atPath: page.path), let md = try? String(contentsOf: url, encoding: .utf8) else { continue }
            writePage(page, markdown: md)
            try? FileManager.default.removeItem(at: url)
        }
    }

    func createTopic(_ name: String, nested: Bool) {
        guard let name = clean(name) else { return }
        let parent = nested ? currentDir : root
        let dir = unique(parent, name)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        writePage(dir.appendingPathComponent("notes.page"), markdown: "# \(name)\n\n## Goals\n- [ ] \n\n## Notes\n\n")
        expanded.insert(parent.path); expanded.insert(dir.path)
        reload()
        open(dir.appendingPathComponent("notes.page").path)
    }

    func createNote(_ name: String) {
        guard var name = clean(name) else { return }
        if !name.lowercased().hasSuffix(".page") { name += ".page" }
        let url = unique(currentDir, name)
        writePage(url, markdown: "# \((url.lastPathComponent as NSString).deletingPathExtension)\n\n")
        finishCreate(url)
    }

    // Optional extras a topic or subtopic can carry: one whiteboard and one ToDo board per folder.
    func hasBoard(_ ext: String, in dir: URL) -> Bool { FileManager.default.fileExists(atPath: dir.appendingPathComponent(ext == "board" ? "Whiteboard.board" : "ToDo.todo").path) }

    func addWhiteboard(in dir: URL? = nil) {
        let folder = dir ?? currentDir
        let url = folder.appendingPathComponent("Whiteboard.board")
        if !FileManager.default.fileExists(atPath: url.path) { write(url, UUID().uuidString) }
        selected = folder.path
        finishCreate(url)
    }

    func addTodoBoard(in dir: URL? = nil) {
        let folder = dir ?? currentDir
        let url = folder.appendingPathComponent("ToDo.todo")
        if !FileManager.default.fileExists(atPath: url.path) { try? Data("[]".utf8).write(to: url) }
        selected = folder.path
        finishCreate(url)
    }

    func whiteboardKey(for url: URL) -> String {
        if let id = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty { return "ts:" + id }
        let id = UUID().uuidString
        write(url, id)
        return "ts:" + id
    }

    func createJournal() {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let day = f.string(from: Date())
        let url = currentDir.appendingPathComponent("journal-\(day).page")
        if !FileManager.default.fileExists(atPath: url.path) {
            writePage(url, markdown: "# Journal — \(day)\n\n## What I tried\n\n## What I learned\n\n## Questions / next steps\n- [ ] \n")
        }
        finishCreate(url)
    }

    func createCode(_ name: String) {
        guard let name = clean(name) else { return }
        let url = unique(currentDir, name)
        write(url, Self.template(for: url.pathExtension.lowercased()))
        finishCreate(url)
    }

    private func finishCreate(_ url: URL) {
        expanded.insert(url.deletingLastPathComponent().path)
        reload()
        open(url.path)
    }

    func rename(_ url: URL, to name: String) {
        guard var name = clean(name) else { return }
        let old = url.pathExtension.lowercased()
        if ["page", "board", "todo"].contains(old) && !name.lowercased().hasSuffix("." + old) { name += "." + old }
        guard name != url.lastPathComponent else { return }
        flush()
        let target = url.deletingLastPathComponent().appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: target.path) else { log("“\(name)” already exists.\n"); return }
        do {
            try FileManager.default.moveItem(at: url, to: target)
            remapMeta(from: metaKey(url), to: metaKey(target))
            func remap(_ p: String) -> String { p == url.path || p.hasPrefix(url.path + "/") ? target.path + p.dropFirst(url.path.count) : p }
            if let p = openPath { openPath = remap(p) }
            if let s = selected { selected = remap(s) }
            expanded = Set(expanded.map(remap))
            reload()
        } catch { log("Rename failed: \(error.localizedDescription)\n") }
    }

    func delete(_ url: URL) {
        flush()
        if url.pathExtension.lowercased() == "board" { WhiteboardStore.shared.remove(key: whiteboardKey(for: url)) }
        let key = metaKey(url)
        meta = meta.filter { $0.key != key && !$0.key.hasPrefix(key + "/") }
        saveMeta()
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        if let p = openPath, p == url.path || p.hasPrefix(url.path + "/") { openPath = nil; text = ""; pageData = Data() }
        if let s = selected, s == url.path || s.hasPrefix(url.path + "/") { selected = nil }
        reload()
    }

    // MARK: editing

    func open(_ path: String) {
        if path == openPath { selected = path; return }
        flush()
        let ext = (path as NSString).pathExtension.lowercased()
        openExt = ext
        todoList = nil
        if ext == "board" || ext == "todo" {
            if ext == "todo" { todoList = TSTodoList(url: URL(fileURLWithPath: path)) }
            text = ""
            openIsPage = false
        } else if path.hasSuffix(".page") {
            guard let data = FileManager.default.contents(atPath: path) else { log("Cannot open \((path as NSString).lastPathComponent).\n"); return }
            pageData = data
            text = RichText.decode(data).string
            openIsPage = true
        } else {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
                log("Cannot open \((path as NSString).lastPathComponent): not a UTF-8 text file.\n")
                return
            }
            text = content
            openIsPage = false
        }
        openPath = path; selected = path; dirty = false
    }

    var currentPageData: Data { pageData }

    func edited(_ value: String) {
        text = value
        scheduleSave()
    }

    func editedPage(_ data: Data, plain: String) {
        pageData = data
        text = plain
        scheduleSave()
    }

    private func scheduleSave() {
        dirty = true
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func flush() {
        saveWork?.cancel()
        guard dirty, let path = openPath else { return }
        dirty = false
        if openIsPage {
            try? pageData.write(to: URL(fileURLWithPath: path), options: .atomic)
        } else {
            write(URL(fileURLWithPath: path), text)
        }
    }

    // MARK: build & run

    static func runCommand(for url: URL, flags: String) -> String? {
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let file = q(url.lastPathComponent)
        let stem = url.deletingPathExtension().lastPathComponent
        let bin = q(stem + ".out")
        switch url.pathExtension.lowercased() {
        case "cpp", "cc", "cxx": return "c++ -std=c++17 -g -Wall -Wextra \(flags) \(file) -o \(bin) && ./\(bin)"
        case "c": return "cc -std=c11 -g -Wall -Wextra \(flags) \(file) -o \(bin) && ./\(bin)"
        case "swift": return "swiftc \(flags) \(file) -o \(bin) && ./\(bin)"
        case "rs": return "rustc \(flags) \(file) -o \(bin) && ./\(bin)"
        case "go": return "go run \(flags) \(file)"
        case "py": return "python3 \(flags) \(file)"
        case "js": return "node \(flags) \(file)"
        case "sh": return "bash \(file)"
        case "java": return "javac \(flags) \(file) && java \(q(stem))"
        default: return nil
        }
    }

    var canRun: Bool { openPath.flatMap { Self.runCommand(for: URL(fileURLWithPath: $0), flags: "") } != nil }

    func runCurrent() {
        guard let path = openPath, !openIsPage, !["board", "todo"].contains(openExt) else { return }
        flush()
        let url = URL(fileURLWithPath: path)
        guard let command = Self.runCommand(for: url, flags: flags) else { return }
        terminal.run(command, in: url.deletingLastPathComponent())
    }

    func stop() { terminal.interrupt() }

    func log(_ s: String) { terminal.say(s) }

    // MARK: code browsing

    private func codeFiles() -> [URL] {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return [] }
        var result: [URL] = []
        for case let url as URL in walker {
            let ext = url.pathExtension.lowercased()
            guard !ext.isEmpty, ext != "md", ext != "page", ext != "board", ext != "todo", ext != "out", ext != "txt" else { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true, (values?.fileSize ?? 0) < 1_000_000 { result.append(url) }
        }
        return result
    }

    private func matches(of regex: NSRegularExpression, in url: URL) -> [(line: Int, text: String)] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var hits: [(Int, String)] = []
        for (index, line) in content.components(separatedBy: "\n").enumerated() {
            if regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil { hits.append((index, line.trimmingCharacters(in: .whitespaces))) }
        }
        return hits
    }

    func findDefinition(_ word: String) {
        flush()
        let w = NSRegularExpression.escapedPattern(for: word)
        let pattern = "(\\b(class|struct|enum|union|namespace|typedef|using|def|func|function|interface|fn|let|var|const)\\s+\(w)\\b)|(^[A-Za-z_][\\w:<>,\\s\\*&~]*[\\s\\*&]\(w)\\s*\\([^;]*$)|(#define\\s+\(w)\\b)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        var hits: [(url: URL, line: Int, text: String)] = []
        for url in codeFiles() { for hit in matches(of: regex, in: url) { hits.append((url, hit.line, hit.text)) } }
        hits.sort { ($0.url.path == openPath ? 0 : 1) < ($1.url.path == openPath ? 0 : 1) }
        guard let first = hits.first else { log("No definition found for “\(word)”.\n"); return }
        open(first.url.path)
        jump = TSJump(line: first.line)
        if hits.count > 1 {
            log("Definitions of “\(word)”:\n" + hits.prefix(20).map { "  \(relativePath($0.url.path)):\($0.line + 1)  \($0.text)\n" }.joined())
        }
    }

    func findUsages(_ word: String) {
        flush()
        guard let regex = try? NSRegularExpression(pattern: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b") else { return }
        var lines: [String] = []
        for url in codeFiles() { for hit in matches(of: regex, in: url) { lines.append("  \(relativePath(url.path)):\(hit.line + 1)  \(hit.text)\n") } }
        log(lines.isEmpty ? "No usages of “\(word)”.\n" : "Usages of “\(word)” (\(lines.count)):\n" + lines.prefix(100).joined())
    }

    // MARK: sample content

    private static func template(for ext: String) -> String {
        switch ext {
        case "cpp", "cc", "cxx": return "#include <iostream>\n\nint main() {\n    std::cout << \"hello, experiment\\n\";\n    return 0;\n}\n"
        case "c": return "#include <stdio.h>\n\nint main(void) {\n    puts(\"hello, experiment\");\n    return 0;\n}\n"
        case "py": return "print(\"hello, experiment\")\n"
        case "js": return "console.log(\"hello, experiment\");\n"
        case "swift": return "print(\"hello, experiment\")\n"
        case "go": return "package main\n\nimport \"fmt\"\n\nfunc main() {\n\tfmt.Println(\"hello, experiment\")\n}\n"
        case "rs": return "fn main() {\n    println!(\"hello, experiment\");\n}\n"
        default: return ""
        }
    }

    private func seedSample() {
        let dir = root.appendingPathComponent("C++ Memory Management/Stack vs Heap", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        writePage(root.appendingPathComponent("C++ Memory Management/notes.page"), markdown: """
        # C++ Memory Management

        ## Goals
        - [x] Understand stack vs heap
        - [ ] Smart pointers
        - [ ] Custom allocators

        Subtopics live in folders below this topic.
        """)
        writePage(dir.appendingPathComponent("notes.page"), markdown: """
        # Stack vs Heap

        ## Goals
        - [x] See where locals and `new` allocations live
        - [ ] Measure the cost of `new` vs stack allocation

        ## Notes
        Stack memory is reclaimed automatically when a scope ends. Heap memory lives until you `delete` it.

        > Try Build & Run on main.cpp with -fsanitize=address in the flags box.
        """)
        write(dir.appendingPathComponent("main.cpp"), """
        #include <iostream>

        int main() {
            int onStack = 42;
            int* onHeap = new int(42);

            std::cout << "stack: " << &onStack << "\\nheap:  " << onHeap << "\\n";

            delete onHeap;
            return 0;
        }
        """)
    }
}
