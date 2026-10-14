import SwiftUI

enum RowKind {
    case equal, added, removed, changed
}

struct DiffRow: Identifiable {
    let id: Int
    let kind: RowKind
    let leftIndex: Int?
    let rightIndex: Int?
    let hunk: Int?
    var leftIntra: [NSRange] = []
    var rightIntra: [NSRange] = []
}

struct Hunk: Identifiable {
    let id: Int
    let firstRow: Int
    let rowCount: Int
    let leftStart: Int
    let leftCount: Int
    let rightStart: Int
    let rightCount: Int
}

struct DiffOptions: Equatable {
    var ignoreWhitespace = false
    var ignoreCase = false
}

struct DiffOutput {
    var rows: [DiffRow]
    var hunks: [Hunk]
    var added: Int
    var removed: Int
    var changed: Int
}

enum DiffEngine {
    static func normalize(_ line: String, _ options: DiffOptions) -> String {
        var result = line
        if options.ignoreWhitespace { result = result.filter { !$0.isWhitespace } }
        if options.ignoreCase { result = result.lowercased() }
        return result
    }

    static func compare(left: [String], right: [String], leftDisplay: [String], rightDisplay: [String], options: DiffOptions) -> DiffOutput {
        let l = left.map { normalize($0, options) }
        let r = right.map { normalize($0, options) }

        var prefix = 0
        while prefix < l.count, prefix < r.count, l[prefix] == r[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < l.count - prefix, suffix < r.count - prefix, l[l.count - 1 - suffix] == r[r.count - 1 - suffix] { suffix += 1 }

        let leftMiddle = Array(l[prefix..<(l.count - suffix)])
        let rightMiddle = Array(r[prefix..<(r.count - suffix)])
        var removedSet = Set<Int>()
        var insertedSet = Set<Int>()
        if !leftMiddle.isEmpty || !rightMiddle.isEmpty {
            for change in rightMiddle.difference(from: leftMiddle) {
                switch change {
                case .remove(let offset, _, _): removedSet.insert(offset + prefix)
                case .insert(let offset, _, _): insertedSet.insert(offset + prefix)
                }
            }
        }

        var rows: [DiffRow] = []
        var hunks: [Hunk] = []
        var added = 0, removed = 0, changed = 0
        var i = 0, j = 0

        while i < l.count || j < r.count {
            let leftStart = i, rightStart = j
            var removedRun: [Int] = []
            var insertedRun: [Int] = []
            while i < l.count, removedSet.contains(i) { removedRun.append(i); i += 1 }
            while j < r.count, insertedSet.contains(j) { insertedRun.append(j); j += 1 }

            if removedRun.isEmpty && insertedRun.isEmpty {
                guard i < l.count, j < r.count else { break }
                rows.append(DiffRow(id: rows.count, kind: .equal, leftIndex: i, rightIndex: j, hunk: nil))
                i += 1
                j += 1
                continue
            }

            let hunkIndex = hunks.count
            let firstRow = rows.count
            let paired = min(removedRun.count, insertedRun.count)
            for k in 0..<paired {
                var row = DiffRow(id: rows.count, kind: .changed, leftIndex: removedRun[k], rightIndex: insertedRun[k], hunk: hunkIndex)
                let ranges = intraRanges(leftDisplay[removedRun[k]], rightDisplay[insertedRun[k]], ignoreWhitespace: options.ignoreWhitespace)
                row.leftIntra = ranges.left
                row.rightIntra = ranges.right
                rows.append(row)
            }
            for k in paired..<removedRun.count {
                rows.append(DiffRow(id: rows.count, kind: .removed, leftIndex: removedRun[k], rightIndex: nil, hunk: hunkIndex))
            }
            for k in paired..<insertedRun.count {
                rows.append(DiffRow(id: rows.count, kind: .added, leftIndex: nil, rightIndex: insertedRun[k], hunk: hunkIndex))
            }
            hunks.append(Hunk(id: hunkIndex, firstRow: firstRow, rowCount: rows.count - firstRow, leftStart: leftStart, leftCount: removedRun.count, rightStart: rightStart, rightCount: insertedRun.count))
            added += insertedRun.count - paired
            removed += removedRun.count - paired
            changed += paired
        }
        return DiffOutput(rows: rows, hunks: hunks, added: added, removed: removed, changed: changed)
    }

    private struct Token {
        let text: String
        let length: Int
    }

    private static func tokenize(_ line: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var currentClass = 0
        func flush() {
            if !current.isEmpty { tokens.append(Token(text: current, length: current.utf16.count)) }
            current = ""
            currentClass = 0
        }
        for ch in line {
            let cls = (ch.isLetter || ch.isNumber || ch == "_") ? 1 : (ch.isWhitespace ? 2 : 0)
            if cls == 0 {
                flush()
                tokens.append(Token(text: String(ch), length: String(ch).utf16.count))
            } else if cls == currentClass {
                current.append(ch)
            } else {
                flush()
                current = String(ch)
                currentClass = cls
            }
        }
        flush()
        return tokens
    }

    // Highlights only the tokens that differ, and skips lines too dissimilar for that to help.
    static func intraRanges(_ a: String, _ b: String, ignoreWhitespace: Bool) -> (left: [NSRange], right: [NSRange]) {
        guard a.utf16.count <= 1500, b.utf16.count <= 1500 else { return ([], []) }
        let ta = tokenize(a), tb = tokenize(b)
        guard !ta.isEmpty, !tb.isEmpty else { return ([], []) }

        var removed = Set<Int>(), inserted = Set<Int>()
        for change in tb.map(\.text).difference(from: ta.map(\.text)) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        let common = ta.count - removed.count
        guard Double(common) / Double(max(ta.count, tb.count)) >= 0.3 else { return ([], []) }

        func ranges(_ tokens: [Token], _ marked: Set<Int>) -> [NSRange] {
            var result: [NSRange] = []
            var location = 0
            for (index, token) in tokens.enumerated() {
                defer { location += token.length }
                guard marked.contains(index) else { continue }
                if ignoreWhitespace && token.text.allSatisfy({ $0.isWhitespace }) { continue }
                if let last = result.last, NSMaxRange(last) == location {
                    result[result.count - 1] = NSRange(location: last.location, length: last.length + token.length)
                } else {
                    result.append(NSRange(location: location, length: token.length))
                }
            }
            return result
        }
        return (ranges(ta, removed), ranges(tb, inserted))
    }
}

enum DisplayRow: Identifiable {
    case row(DiffRow)
    case gap(id: Int, count: Int)

    var id: Int {
        switch self {
        case .row(let row): return row.id
        case .gap(let id, _): return id
        }
    }
}

final class CompareResult {
    let rows: [DiffRow]
    let hunks: [Hunk]
    let leftLines: [String]
    let rightLines: [String]
    let leftDisplay: [String]
    let rightDisplay: [String]
    let leftSpans: [[SyntaxSpan]]
    let rightSpans: [[SyntaxSpan]]
    let language: LanguageSpec
    let added: Int
    let removed: Int
    let changed: Int
    let leftFormat: LineFormat
    let rightFormat: LineFormat

    private var cache: [Int: AttributedString] = [:]
    private lazy var allRows: [DisplayRow] = rows.map { DisplayRow.row($0) }
    private lazy var collapsedRows: [DisplayRow] = Self.collapse(rows, context: 3)

    init(output: DiffOutput, left: SplitText, right: SplitText, leftSpans: [[SyntaxSpan]], rightSpans: [[SyntaxSpan]], language: LanguageSpec) {
        rows = output.rows
        hunks = output.hunks
        leftLines = left.lines
        rightLines = right.lines
        leftDisplay = left.display
        rightDisplay = right.display
        self.leftSpans = leftSpans
        self.rightSpans = rightSpans
        self.language = language
        added = output.added
        removed = output.removed
        changed = output.changed
        leftFormat = left.format
        rightFormat = right.format
    }

    func displayRows(collapsed: Bool) -> [DisplayRow] { collapsed ? collapsedRows : allRows }

    private static func collapse(_ rows: [DiffRow], context: Int) -> [DisplayRow] {
        var keep = [Bool](repeating: false, count: rows.count)
        for (index, row) in rows.enumerated() where row.kind != .equal {
            for k in max(0, index - context)...min(rows.count - 1, index + context) { keep[k] = true }
        }
        var result: [DisplayRow] = []
        var skipped = 0
        var gapStart = 0
        for (index, row) in rows.enumerated() {
            if keep[index] {
                if skipped > 0 { result.append(.gap(id: -(gapStart + 1), count: skipped)); skipped = 0 }
                result.append(.row(row))
            } else {
                if skipped == 0 { gapStart = index }
                skipped += 1
            }
        }
        if skipped > 0 { result.append(.gap(id: -(gapStart + 1), count: skipped)) }
        return result
    }

    func attributed(left: Bool, row: DiffRow, colors: SyntaxColors, intraBackground: Color) -> AttributedString {
        let key = row.id * 4 + (left ? 0 : 1) + (colors.isDark ? 2 : 0)
        if let cached = cache[key] { return cached }

        guard let index = left ? row.leftIndex : row.rightIndex else { return AttributedString() }
        let text = left ? leftDisplay[index] : rightDisplay[index]
        let spans = left ? leftSpans[index] : rightSpans[index]
        let intra = left ? row.leftIntra : row.rightIntra
        let units = Array(text.utf16)

        var cuts = Set<Int>([0, units.count])
        for span in spans { cuts.insert(span.start); cuts.insert(span.start + span.length) }
        for range in intra { cuts.insert(range.location); cuts.insert(NSMaxRange(range)) }
        let positions = cuts.filter { $0 >= 0 && $0 <= units.count }.sorted()

        var output = AttributedString()
        var spanIndex = 0
        for k in 0..<max(0, positions.count - 1) {
            let a = positions[k], b = positions[k + 1]
            while spanIndex < spans.count, spans[spanIndex].start + spans[spanIndex].length <= a { spanIndex += 1 }
            var kind = SyntaxKind.plain
            if spanIndex < spans.count, spans[spanIndex].start <= a { kind = spans[spanIndex].kind }
            var piece = AttributedString(String(decoding: units[a..<b], as: UTF16.self))
            piece.foregroundColor = colors.color(kind)
            if kind == .keyword { piece.font = .system(size: 12, weight: .semibold, design: .monospaced) }
            if intra.contains(where: { $0.location <= a && NSMaxRange($0) >= b }) { piece.backgroundColor = intraBackground }
            output += piece
        }
        if units.isEmpty { output = AttributedString(" ") }
        cache[key] = output
        return output
    }
}

struct LineFormat {
    var eol = "\n"
    var trailingNewline = false
}

struct SplitText {
    var lines: [String]
    var display: [String]
    var format: LineFormat

    init(_ text: String) {
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let trailing = normalized.hasSuffix("\n")
        if trailing { normalized.removeLast() }
        lines = (normalized.isEmpty && !trailing) ? [] : normalized.components(separatedBy: "\n")
        display = lines.map { $0.replacingOccurrences(of: "\t", with: "    ") }
        format = LineFormat(eol: text.contains("\r\n") ? "\r\n" : "\n", trailingNewline: trailing)
    }

    static func join(_ lines: [String], format: LineFormat) -> String {
        lines.joined(separator: format.eol) + (format.trailingNewline && !lines.isEmpty ? format.eol : "")
    }
}

enum CompareEngine {
    static func run(left: String, right: String, options: DiffOptions, languageID: String, names: [String]) -> CompareResult {
        let l = SplitText(left)
        let r = SplitText(right)
        let spec: LanguageSpec
        if languageID != "auto", let chosen = LanguageRegistry.spec(id: languageID) {
            spec = chosen
        } else {
            spec = LanguageRegistry.detect(fileNames: names, samples: [left, right])
        }
        let output = DiffEngine.compare(left: l.lines, right: r.lines, leftDisplay: l.display, rightDisplay: r.display, options: options)
        return CompareResult(
            output: output, left: l, right: r,
            leftSpans: SyntaxHighlighter.highlight(lines: l.display, spec: spec),
            rightSpans: SyntaxHighlighter.highlight(lines: r.display, spec: spec),
            language: spec
        )
    }
}
