import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct JumpTarget: Equatable {
    let rowID: Int
    let token = UUID()
}

struct CompareSide {
    var text = ""
    var url: URL?
    var savedText = ""

    var isModified: Bool { url != nil && text != savedText }
}

final class CompareModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case input = "Text"
        case diff = "Differences"
        var id: String { rawValue }
    }

    @Published var left = CompareSide() { didSet { if left.text != oldValue.text { dirty = true } } }
    @Published var right = CompareSide() { didSet { if right.text != oldValue.text { dirty = true } } }
    @Published var mode: Mode = .input
    @Published var languageID = "auto"
    @Published var ignoreWhitespace = false
    @Published var ignoreCase = false
    @Published var differencesOnly = false
    @Published private(set) var result: CompareResult?
    @Published private(set) var isComparing = false
    @Published var message: String?
    @Published var currentHunk = 0
    @Published var jump: JumpTarget?

    private(set) var dirty = true
    private var generation = 0
    private var jumpAfterCompare = true

    private static let maxFileBytes = 10_000_000

    var canCompare: Bool { !(left.text.isEmpty && right.text.isEmpty) }

    func title(isLeft: Bool) -> String {
        (isLeft ? left.url : right.url)?.lastPathComponent ?? (isLeft ? "Left" : "Right")
    }

    func compare(jumpToFirst: Bool = true) {
        guard canCompare else {
            message = "Add text or open a file on at least one side to compare."
            return
        }
        message = nil
        generation += 1
        let current = generation
        mode = .diff
        isComparing = true
        dirty = false
        jumpAfterCompare = jumpToFirst

        let leftText = left.text, rightText = right.text
        let options = DiffOptions(ignoreWhitespace: ignoreWhitespace, ignoreCase: ignoreCase)
        let language = languageID
        let names = [left.url?.lastPathComponent, right.url?.lastPathComponent].compactMap { $0 }

        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = CompareEngine.run(left: leftText, right: rightText, options: options, languageID: language, names: names)
            DispatchQueue.main.async {
                guard current == self.generation else { return }
                self.result = outcome
                self.isComparing = false
                self.currentHunk = min(self.currentHunk, max(0, outcome.hunks.count - 1))
                if self.jumpAfterCompare, !outcome.hunks.isEmpty { self.goToHunk(0) }
            }
        }
    }

    func recompareIfShowing() {
        if mode == .diff, result != nil || isComparing { compare(jumpToFirst: false) }
    }

    func showDifferences() {
        if dirty || result == nil { compare() }
    }

    func goToHunk(_ index: Int) {
        guard let hunks = result?.hunks, hunks.indices.contains(index) else { return }
        currentHunk = index
        jump = JumpTarget(rowID: hunks[index].firstRow)
    }

    func step(_ delta: Int) {
        guard let count = result?.hunks.count, count > 0 else { return }
        goToHunk((currentHunk + delta + count) % count)
    }

    func swapSides() {
        let previous = left
        left = right
        right = previous
        if canCompare { compare(jumpToFirst: false) }
    }

    func clear() {
        generation += 1
        left = CompareSide()
        right = CompareSide()
        result = nil
        isComparing = false
        message = nil
        mode = .input
    }

    // Replaces the target side's lines for this hunk with the other side's lines.
    func copyHunk(_ index: Int, toRight: Bool) {
        guard let result, result.hunks.indices.contains(index) else { return }
        let hunk = result.hunks[index]
        var target = toRight ? result.rightLines : result.leftLines
        let source = toRight ? result.leftLines : result.rightLines
        let sourceRange = toRight ? hunk.leftStart..<(hunk.leftStart + hunk.leftCount) : hunk.rightStart..<(hunk.rightStart + hunk.rightCount)
        let targetRange = toRight ? hunk.rightStart..<(hunk.rightStart + hunk.rightCount) : hunk.leftStart..<(hunk.leftStart + hunk.leftCount)
        target.replaceSubrange(targetRange, with: source[sourceRange])
        currentHunk = index
        if toRight {
            right.text = SplitText.join(target, format: result.rightFormat)
        } else {
            left.text = SplitText.join(target, format: result.leftFormat)
        }
        compare(jumpToFirst: false)
    }

    // MARK: Files

    func openFile(isLeft: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a text or source file for the \(isLeft ? "left" : "right") side"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url, isLeft: isLeft)
        compareIfReady()
    }

    func openTwoFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Choose two files to compare"
        guard panel.runModal() == .OK else { return }
        guard panel.urls.count == 2 else {
            message = "Select exactly two files, or open them one side at a time."
            return
        }
        load(panel.urls[0], isLeft: true)
        load(panel.urls[1], isLeft: false)
        compareIfReady()
    }

    func handleDrop(_ url: URL, isLeft: Bool) {
        DispatchQueue.main.async {
            self.load(url, isLeft: isLeft)
            self.compareIfReady()
        }
    }

    private func compareIfReady() {
        if left.url != nil && right.url != nil || (!left.text.isEmpty && !right.text.isEmpty) { compare() }
    }

    private func load(_ url: URL, isLeft: Bool) {
        do {
            let text = try Self.readText(url)
            let side = CompareSide(text: text, url: url, savedText: text)
            if isLeft { left = side } else { right = side }
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    static func readText(_ url: URL) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes[.size] as? Int, size > maxFileBytes {
            throw CompareError.tooLarge(url.lastPathComponent)
        }
        let data = try Data(contentsOf: url)
        if data.prefix(8000).contains(0) { throw CompareError.binary(url.lastPathComponent) }
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .isoLatin1) { return text }
        throw CompareError.unreadable(url.lastPathComponent)
    }

    func save(isLeft: Bool) {
        var side = isLeft ? left : right
        var destination = side.url
        if destination == nil {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = isLeft ? "left.txt" : "right.txt"
            guard panel.runModal() == .OK else { return }
            destination = panel.url
        }
        guard let destination else { return }
        do {
            try side.text.write(to: destination, atomically: true, encoding: .utf8)
            side.url = destination
            side.savedText = side.text
            if isLeft { left = side } else { right = side }
            message = nil
        } catch {
            message = "Could not save \(destination.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func reload(isLeft: Bool) {
        guard let url = isLeft ? left.url : right.url else { return }
        load(url, isLeft: isLeft)
        recompareIfShowing()
    }
}

enum CompareError: LocalizedError {
    case binary(String)
    case tooLarge(String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .binary(let name): return "\(name) looks like a binary file, so it can't be compared as text."
        case .tooLarge(let name): return "\(name) is larger than 10 MB, which is too big to compare."
        case .unreadable(let name): return "\(name) could not be read as text."
        }
    }
}

// Plain-text editor that keeps code exactly as typed and accepts dropped files.
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var onFileDrop: (URL) -> Void

    final class DropTextView: NSTextView {
        var onFileDrop: ((URL) -> Void)?

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
            if let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], let url = urls.first {
                onFileDrop?(url)
                return true
            }
            return super.performDragOperation(sender)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let tv = DropTextView(frame: .zero)
        tv.delegate = context.coordinator
        tv.onFileDrop = onFileDrop
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.textColor = .labelColor
        tv.insertionPointColor = .labelColor
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.textContainerInset = NSSize(width: 4, height: 6)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.string = text
        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? DropTextView else { return }
        tv.onFileDrop = onFileDrop
        if tv.string != text { tv.string = text }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor

        init(_ parent: CodeEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}
