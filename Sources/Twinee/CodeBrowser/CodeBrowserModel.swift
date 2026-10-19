import SwiftUI
import AppKit

struct FileNode: Identifiable, Hashable {
    let id: String
    let name: String
    var children: [FileNode]?
}

struct CodeHit: Identifiable {
    let id = UUID()
    let path: String
    let line: Int
    let text: String
    let kind: SymbolKind?
}

struct LineJump: Equatable {
    let line: Int
    let token = UUID()
}

final class CodeBrowserModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case files = "Files"
        case outline = "Outline"
        case symbols = "Symbols"
        case notes = "Notes"
        var id: String { rawValue }
    }

    @Published var root: URL?
    @Published private(set) var tree: [FileNode] = []
    @Published private(set) var files: [String] = []
    @Published private(set) var symbols: [CodeSymbol] = []
    @Published private(set) var isIndexing = false
    @Published var tab: Tab = .files
    @Published var query = ""
    @Published var kindFilter: SymbolKind?
    @Published private(set) var currentPath: String?
    @Published private(set) var text = ""
    @Published private(set) var language: SourceLanguage = .cpp
    @Published var jump: LineJump?
    @Published var hits: [CodeHit] = []
    @Published var hitsTitle = ""
    @Published var message: String?
    @Published private(set) var isSearching = false

    @Published private(set) var remote: RemoteSource?
    @Published var isFetchingRemote = false
    @Published var remoteError: String?
    @Published private(set) var remoteBranches: [String] = []
    @Published private(set) var remoteDefaultBranch: String?
    @Published private(set) var selectedLine = 0

    private var symbolsByFile: [String: [CodeSymbol]] = [:]
    private var symbolsByName: [String: [CodeSymbol]] = [:]
    private var generation = 0

    private static let skippedDirectories: Set<String> = ["node_modules", "build", "DerivedData", "__pycache__", "venv", "Pods", "dist", "target", "site-packages", "CMakeFiles"]
    private static let maxFiles = 5000
    private static let binaryExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "ico", "icns", "tiff", "webp", "heic", "pdf", "zip", "gz", "tgz", "bz2", "xz", "7z", "rar", "tar", "jar", "war", "o", "a", "so", "dylib", "dll", "exe", "class", "pyc", "pyo", "bin", "dmg", "iso", "mp3", "mp4", "mov", "avi", "mkv", "wav", "flac", "ogg", "ttf", "otf", "woff", "woff2", "eot", "sqlite", "db", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "lock", "DS_Store"]
    private static let maxIndexedBytes = 1_500_000

    var outline: [CodeSymbol] { currentPath.flatMap { symbolsByFile[$0] } ?? [] }
    var fileCount: Int { files.count }

    func relativePath(_ path: String) -> String {
        guard let root else { return path }
        return path.hasPrefix(root.path + "/") ? String(path.dropFirst(root.path.count + 1)) : path
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to browse"
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url)
    }

    var displayName: String {
        if let remote { return "\(GitModel.repoName(from: remote.url)) @ \(remote.branch)" }
        return root?.lastPathComponent ?? ""
    }

    // Notes follow the repository (or folder), not the temporary checkout.
    var sourceKey: String { remote.map { NoteSource.key(forRemote: $0.url) } ?? root?.path ?? "" }

    func setSelectedLine(_ line: Int) { selectedLine = line }

    func load(_ url: URL, remote: RemoteSource? = nil) {
        generation += 1
        let current = generation
        root = url
        self.remote = remote
        if let remote {
            DevToolsStore.shared.codeRemote = remote
        } else {
            DevToolsStore.shared.codeFolder = url.path
            DevToolsStore.shared.codeRemote = nil
        }
        selectedLine = 0
        tree = []
        files = []
        symbols = []
        symbolsByFile = [:]
        symbolsByName = [:]
        currentPath = nil
        text = ""
        hits = []
        message = nil
        isIndexing = true

        DispatchQueue.global(qos: .userInitiated).async {
            var collected: [String] = []
            let nodes = Self.scan(url, files: &collected)
            DispatchQueue.main.async {
                guard current == self.generation else { return }
                self.tree = nodes
                self.files = collected
            }

            var byFile: [String: [CodeSymbol]] = [:]
            for path in collected {
                guard let language = SourceLanguage.from(extension: (path as NSString).pathExtension) else { continue }
                if let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int, size > Self.maxIndexedBytes { continue }
                guard let content = try? CompareModel.readText(URL(fileURLWithPath: path)) else { continue }
                byFile[path] = SymbolExtractor.extract(text: content, path: path, language: language)
            }
            let all = byFile.values.flatMap { $0 }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            let byName = Dictionary(grouping: all, by: \.name)
            DispatchQueue.main.async {
                guard current == self.generation else { return }
                self.symbolsByFile = byFile
                self.symbolsByName = byName
                self.symbols = all
                self.isIndexing = false
                if self.currentPath == nil, let first = collected.first { self.open(path: first) }
            }
        }
    }

    private static func scan(_ directory: URL, files: inout [String]) -> [FileNode] {
        guard files.count < maxFiles,
              let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        else { return [] }
        var directories: [FileNode] = []
        var sources: [FileNode] = []
        for entry in entries.sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                if skippedDirectories.contains(entry.lastPathComponent) { continue }
                let children = scan(entry, files: &files)
                if !children.isEmpty { directories.append(FileNode(id: entry.path, name: entry.lastPathComponent, children: children)) }
            } else if !binaryExtensions.contains(entry.pathExtension.lowercased()), files.count < maxFiles {
                files.append(entry.path)
                sources.append(FileNode(id: entry.path, name: entry.lastPathComponent, children: nil))
            }
        }
        return directories + sources
    }

    func isFile(_ path: String) -> Bool { !((try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) }

    func open(path: String, line: Int? = nil) {
        let language = SourceLanguage.detect(path: path)
        if path == currentPath {
            if let line { jump = LineJump(line: line) }
            return
        }
        let url = URL(fileURLWithPath: path)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let content = try CompareModel.readText(url)
                DispatchQueue.main.async {
                    self.currentPath = path
                    self.language = language
                    self.text = content
                    self.message = nil
                    self.jump = LineJump(line: line ?? 0)
                }
            } catch {
                DispatchQueue.main.async { self.message = error.localizedDescription }
            }
        }
    }

    func open(_ symbol: CodeSymbol) {
        open(path: symbol.path, line: symbol.line)
    }

    func open(_ hit: CodeHit) {
        open(path: hit.path, line: hit.line)
    }

    func filteredFiles() -> [String] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return files }
        return files.filter { relativePath($0).localizedCaseInsensitiveContains(needle) }
    }

    func filteredSymbols(_ list: [CodeSymbol], limit: Int = 600) -> [CodeSymbol] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        var result = list.filter { symbol in
            (kindFilter == nil || symbol.kind == kindFilter) && (needle.isEmpty || symbol.name.localizedCaseInsensitiveContains(needle) || (symbol.container?.localizedCaseInsensitiveContains(needle) ?? false))
        }
        if result.count > limit { result = Array(result.prefix(limit)) }
        return result
    }

    // MARK: Navigation

    func goToDefinition(of word: String) {
        let found = symbolsByName[word] ?? []
        guard !found.isEmpty else {
            hitsTitle = "No definition found for “\(word)”"
            hits = []
            message = "No definition of “\(word)” in this folder. Try “Find Usages”."
            return
        }
        message = nil
        let definitions = found.filter { $0.kind != .prototype }
        let preferred = definitions.isEmpty ? found : definitions
        if preferred.count == 1, let only = preferred.first {
            open(only)
            hits = []
            return
        }
        hitsTitle = "Definitions of “\(word)” (\(found.count))"
        hits = found.map { CodeHit(path: $0.path, line: $0.line, text: $0.signature, kind: $0.kind) }
    }

    func findUsages(of word: String) {
        guard !word.isEmpty, !files.isEmpty else { return }
        isSearching = true
        hitsTitle = "Searching for “\(word)”…"
        let paths = files
        let current = generation
        DispatchQueue.global(qos: .userInitiated).async {
            var found: [CodeHit] = []
            outer: for path in paths {
                guard let content = try? CompareModel.readText(URL(fileURLWithPath: path)), content.contains(word) else { continue }
                for (index, line) in content.components(separatedBy: "\n").enumerated() where Self.contains(word: word, in: line) {
                    found.append(CodeHit(path: path, line: index, text: line.trimmingCharacters(in: .whitespaces), kind: nil))
                    if found.count >= 500 { break outer }
                }
            }
            DispatchQueue.main.async {
                guard current == self.generation else { return }
                self.isSearching = false
                self.hits = found
                self.hitsTitle = "Usages of “\(word)” (\(found.count)\(found.count >= 500 ? "+" : ""))"
            }
        }
    }

    private static func contains(word: String, in line: String) -> Bool {
        let units = Array(line.utf16)
        let target = Array(word.utf16)
        guard target.count <= units.count else { return false }
        func isWord(_ c: UInt16) -> Bool { (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c > 127 }
        var i = 0
        while i + target.count <= units.count {
            if units[i] == target[0], Array(units[i..<(i + target.count)]) == target,
               i == 0 || !isWord(units[i - 1]),
               i + target.count == units.count || !isWord(units[i + target.count]) { return true }
            i += 1
        }
        return false
    }
}

final class CodeTextView: NSTextView {
    var onDefinition: ((String) -> Void)?
    var onUsages: ((String) -> Void)?
    var onAddNote: ((Int) -> Void)?
    var onSelectionLine: ((Int) -> Void)?
    var lineStarts: [Int] = [0]

    func lineIndex(forCharacter location: Int) -> Int {
        var low = 0, high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= location { low = mid } else { high = mid - 1 }
        }
        return low
    }

    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: stillSelectingFlag)
        if !stillSelectingFlag { onSelectionLine?(lineIndex(forCharacter: charRange.location)) }
    }

    func word(at point: NSPoint) -> String? {
        let adjusted = NSPoint(x: point.x - textContainerInset.width, y: point.y - textContainerInset.height)
        guard let lm = layoutManager, let container = textContainer, !string.isEmpty else { return nil }
        var fraction: CGFloat = 0
        let glyph = lm.glyphIndex(for: adjusted, in: container, fractionOfDistanceThroughGlyph: &fraction)
        let rect = lm.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        guard rect.contains(adjusted) else { return nil }
        let units = Array(string.utf16)
        var index = lm.characterIndexForGlyph(at: glyph)
        func isWord(_ c: UInt16) -> Bool { (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c > 127 }
        guard index < units.count, isWord(units[index]) else { return nil }
        var start = index
        while start > 0, isWord(units[start - 1]) { start -= 1 }
        while index < units.count, isWord(units[index]) { index += 1 }
        return String(decoding: units[start..<index], as: UTF16.self)
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let word = word(at: convert(event.locationInWindow, from: nil)) {
            onDefinition?(word)
            return
        }
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        if onAddNote != nil, !string.isEmpty {
            let line = lineIndex(forCharacter: characterIndexForInsertion(at: convert(event.locationInWindow, from: nil)))
            let note = NSMenuItem(title: "Add Note on Line \(line + 1)…", action: #selector(addNote(_:)), keyEquivalent: "")
            note.tag = line
            note.target = self
            menu.insertItem(note, at: 0)
            menu.insertItem(.separator(), at: 1)
        }
        if let word = word(at: convert(event.locationInWindow, from: nil)) {
            let definition = NSMenuItem(title: "Go to Definition of “\(word)”", action: #selector(goDefinition(_:)), keyEquivalent: "")
            definition.representedObject = word
            definition.target = self
            let usages = NSMenuItem(title: "Find Usages of “\(word)”", action: #selector(findUsages(_:)), keyEquivalent: "")
            usages.representedObject = word
            usages.target = self
            menu.insertItem(usages, at: 0)
            menu.insertItem(definition, at: 0)
            menu.insertItem(.separator(), at: 2)
        }
        return menu
    }

    @objc private func addNote(_ sender: NSMenuItem) { onAddNote?(sender.tag) }
    @objc private func goDefinition(_ sender: NSMenuItem) { if let word = sender.representedObject as? String { onDefinition?(word) } }
    @objc private func findUsages(_ sender: NSMenuItem) { if let word = sender.representedObject as? String { onUsages?(word) } }
}

final class LineNumberRuler: NSRulerView {
    var lineStarts: [Int] = [0] { didSet { needsDisplay = true } }
    var noteLines: Set<Int> = [] { didSet { needsDisplay = true } }
    private let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)

    init(scrollView: NSScrollView, textView: NSTextView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 50
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func refresh() { needsDisplay = true }

    private func lineIndex(forCharacter location: Int) -> Int {
        var low = 0, high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= location { low = mid } else { high = mid - 1 }
        }
        return low
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = clientView as? NSTextView, let lm = tv.layoutManager, let container = tv.textContainer, tv.string.utf16.count > 0 else { return }
        let length = tv.string.utf16.count
        let visible = tv.visibleRect
        let glyphRange = lm.glyphRange(forBoundingRect: visible, in: container)
        let characters = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let attributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: NSColor.secondaryLabelColor]
        var line = lineIndex(forCharacter: characters.location)
        while line < lineStarts.count, lineStarts[line] <= NSMaxRange(characters) {
            let start = min(lineStarts[line], length - 1)
            let glyph = lm.glyphIndexForCharacter(at: start)
            let fragment = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let y = convert(NSPoint(x: 0, y: fragment.minY + tv.textContainerInset.height), from: tv).y
            let label = "\(line + 1)" as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 8, y: y + (fragment.height - size.height) / 2), withAttributes: attributes)
            if noteLines.contains(line) {
                NSColor.systemOrange.setFill()
                NSBezierPath(ovalIn: NSRect(x: 6, y: y + fragment.height / 2 - 3, width: 6, height: 6)).fill()
            }
            line += 1
        }
    }
}

struct CodeViewer: NSViewRepresentable {
    let text: String
    let language: SourceLanguage
    let jump: LineJump?
    let onDefinition: (String) -> Void
    let onUsages: (String) -> Void
    var noteLines: Set<Int> = []
    var onAddNote: ((Int) -> Void)?
    var onSelectionLine: ((Int) -> Void)?

    final class Coordinator {
        var renderedText: String?
        var renderedLanguage: SourceLanguage?
        var handledJump: UUID?
        var lineStarts: [Int] = [0]
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = false
        let tv = CodeTextView(frame: .zero)
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = false
        tv.drawsBackground = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = true
        tv.autoresizingMask = []
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = tv
        scroll.hasVerticalRuler = true
        scroll.verticalRulerView = LineNumberRuler(scrollView: scroll, textView: tv)
        scroll.rulersVisible = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? CodeTextView else { return }
        let coordinator = context.coordinator
        tv.onDefinition = onDefinition
        tv.onUsages = onUsages
        tv.onAddNote = onAddNote
        tv.onSelectionLine = onSelectionLine
        (scroll.verticalRulerView as? LineNumberRuler)?.noteLines = noteLines

        if coordinator.renderedText != text || coordinator.renderedLanguage != language {
            let rendered = Self.render(text, language: language)
            tv.textStorage?.setAttributedString(rendered.text)
            coordinator.renderedText = text
            coordinator.renderedLanguage = language
            coordinator.lineStarts = rendered.lineStarts
            tv.lineStarts = rendered.lineStarts
            (scroll.verticalRulerView as? LineNumberRuler)?.lineStarts = rendered.lineStarts
            tv.scroll(NSPoint.zero)
        }

        if let jump, jump.token != coordinator.handledJump {
            coordinator.handledJump = jump.token
            let starts = coordinator.lineStarts
            guard !starts.isEmpty else { return }
            let line = min(max(0, jump.line), starts.count - 1)
            DispatchQueue.main.async { Self.reveal(line: line, starts: starts, in: scroll, textView: tv) }
        }
    }

    private static func reveal(line: Int, starts: [Int], in scroll: NSScrollView, textView tv: CodeTextView) {
        guard let lm = tv.layoutManager, let container = tv.textContainer else { return }
        let length = (tv.string as NSString).length
        guard length > 0 else { return }
        let start = min(starts[line], length)
        let lineRange = (tv.string as NSString).lineRange(for: NSRange(location: min(start, length - 1), length: 0))
        lm.ensureLayout(forCharacterRange: lineRange)
        let glyphs = lm.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
        let rect = lm.boundingRect(forGlyphRange: glyphs, in: container)
        let y = max(0, rect.minY + tv.textContainerInset.height - scroll.contentView.bounds.height / 3)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
        lm.addTemporaryAttribute(.backgroundColor, value: NSColor.controlAccentColor.withAlphaComponent(0.25), forCharacterRange: lineRange)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: lineRange)
        }
    }

    private static func render(_ source: String, language: SourceLanguage) -> (text: NSAttributedString, lineStarts: [Int]) {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let style = NSMutableParagraphStyle()
        style.defaultTabInterval = ("    " as NSString).size(withAttributes: [.font: font]).width
        style.tabStops = []
        let attributed = NSMutableAttributedString(string: normalized, attributes: [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
        let lines = normalized.components(separatedBy: "\n")
        var starts: [Int] = []
        var offset = 0
        let spans = normalized.utf16.count > 800_000 ? nil : LanguageRegistry.spec(id: language.specID).map { SyntaxHighlighter.highlight(lines: lines, spec: $0) }
        let bold = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        for (index, line) in lines.enumerated() {
            starts.append(offset)
            if let spans {
                for span in spans[index] where span.kind != .plain {
                    let range = NSRange(location: offset + span.start, length: span.length)
                    attributed.addAttribute(.foregroundColor, value: SyntaxColors.nsColor(span.kind), range: range)
                    if span.kind == .keyword { attributed.addAttribute(.font, value: bold, range: range) }
                }
            }
            offset += line.utf16.count + 1
        }
        return (attributed, starts)
    }
}
