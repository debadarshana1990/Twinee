import SwiftUI
import AppKit

enum SyntaxKind: UInt8 {
    case plain, keyword, type, string, comment, number, function, property, directive, constant
}

struct SyntaxSpan {
    var start: Int
    var length: Int
    var kind: SyntaxKind
}

struct LanguageSpec: Identifiable {
    let id: String
    let name: String
    let extensions: [String]
    var lineComments: [String] = []
    var blockComments: [(start: String, end: String)] = []
    var quotes: [Character] = ["\"", "'"]
    var multilineQuotes: Set<Character> = []
    var tripleQuotes = false
    var keywords: Set<String> = []
    var constants: Set<String> = []
    var types: Set<String> = []
    var hashDirectives = false
    var atAttributes = false
    var caseInsensitive = false
    var keyColon = false
    var hyphenIdentifiers = false
    var dollarVariables = false
    var markup = false
    var capitalizedTypes = true
}

struct SyntaxColors {
    let isDark: Bool
    let plain: Color

    static func hex(_ kind: SyntaxKind, dark: Bool) -> UInt32? {
        switch kind {
        case .plain: return nil
        case .keyword: return dark ? 0xFC5FA3 : 0x9B2393
        case .type: return dark ? 0x5DD8FF : 0x1C6E82
        case .string: return dark ? 0xFC6A5D : 0xC41A16
        case .comment: return dark ? 0x7F8C98 : 0x6B7A87
        case .number: return dark ? 0xD0BF69 : 0x1C00CF
        case .function: return dark ? 0x67B7A4 : 0x326D74
        case .property: return dark ? 0x41A1C0 : 0x0F68A0
        case .directive: return dark ? 0xFD8F3F : 0x8A4B1F
        case .constant: return dark ? 0xB98EFF : 0x6C36A9
        }
    }

    func color(_ kind: SyntaxKind) -> Color {
        guard let hex = Self.hex(kind, dark: isDark) else { return plain }
        return Color(hex: hex)
    }

    // Follows the window appearance, so highlighted text stays readable when the theme changes.
    static func nsColor(_ kind: SyntaxKind) -> NSColor {
        guard let light = hex(kind, dark: false), let dark = hex(kind, dark: true) else { return .labelColor }
        func make(_ value: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
        }
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? make(dark) : make(light)
        }
    }
}

private func words(_ list: String) -> Set<String> {
    Set(list.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init))
}

private func makeSpec(_ id: String, _ name: String, _ extensions: String, _ configure: (inout LanguageSpec) -> Void = { _ in }) -> LanguageSpec {
    var spec = LanguageSpec(id: id, name: name, extensions: extensions.split(separator: " ").map(String.init))
    configure(&spec)
    return spec
}

private func cLike(_ spec: inout LanguageSpec) {
    spec.lineComments = ["//"]
    spec.blockComments = [("/*", "*/")]
}

enum LanguageRegistry {
    static let plain = LanguageSpec(id: "text", name: "Plain Text", extensions: ["txt", "text", "log", "md", "markdown", "csv"])

    static let all: [LanguageSpec] = [
        makeSpec("swift", "Swift", "swift") {
            cLike(&$0); $0.hashDirectives = true; $0.atAttributes = true; $0.tripleQuotes = true; $0.quotes = ["\""]
            $0.keywords = words("associatedtype class deinit enum extension fileprivate func import init inout internal let open operator private precedencegroup protocol public rethrows static struct subscript typealias var break case catch continue default defer do else fallthrough for guard if in repeat return throw switch where while as is try throws async await actor some any convenience dynamic final lazy mutating nonmutating optional override required weak unowned get set willSet didSet indirect isolated nonisolated self Self super")
            $0.constants = words("true false nil")
            $0.types = words("Int String Bool Double Float Array Dictionary Set Optional Void Character Data Date UUID URL Result Error Any AnyObject")
        },
        makeSpec("c", "C", "c") {
            cLike(&$0); $0.hashDirectives = true
            $0.keywords = words("auto break case char const continue default do double else enum extern float for goto if inline int long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while bool")
            $0.constants = words("NULL true false")
            $0.types = words("size_t ssize_t uint8_t uint16_t uint32_t uint64_t int8_t int16_t int32_t int64_t FILE")
        },
        makeSpec("cpp", "C++", "cpp cc cxx hpp hh h hxx mm m") {
            cLike(&$0); $0.hashDirectives = true
            $0.keywords = words("alignas alignof and asm auto bool break case catch char class concept const consteval constexpr constinit const_cast continue decltype default delete do double dynamic_cast else enum explicit export extern float for friend goto if inline int long mutable namespace new noexcept not operator or override final private protected public register reinterpret_cast requires return short signed sizeof static static_assert static_cast struct switch template this thread_local throw try typedef typeid typename union unsigned using virtual void volatile while")
            $0.constants = words("NULL nullptr true false")
            $0.types = words("string vector map unordered_map set size_t unique_ptr shared_ptr optional uint8_t uint16_t uint32_t uint64_t int8_t int16_t int32_t int64_t")
        },
        makeSpec("csharp", "C#", "cs") {
            cLike(&$0); $0.hashDirectives = true; $0.atAttributes = true
            $0.keywords = words("abstract as base bool break byte case catch char checked class const continue decimal default delegate do double else enum event explicit extern finally fixed float for foreach goto if implicit in int interface internal is lock long namespace new object operator out override params private protected public readonly ref return sbyte sealed short sizeof stackalloc static string struct switch this throw try typeof uint ulong unchecked unsafe ushort using virtual void volatile while var async await record init get set yield partial where")
            $0.constants = words("true false null")
        },
        makeSpec("java", "Java", "java") {
            cLike(&$0); $0.atAttributes = true
            $0.keywords = words("abstract assert boolean break byte case catch char class const continue default do double else enum extends final finally float for goto if implements import instanceof int interface long native new package private protected public return short static strictfp super switch synchronized this throw throws transient try void volatile while var record sealed permits yield")
            $0.constants = words("true false null")
        },
        makeSpec("kotlin", "Kotlin", "kt kts") {
            cLike(&$0); $0.atAttributes = true; $0.tripleQuotes = true
            $0.keywords = words("as break class continue do else for fun if in interface is object package return super this throw try typealias val var when while by catch constructor finally import init where abstract annotation companion const data enum inner internal lateinit open operator out override private protected public sealed suspend vararg")
            $0.constants = words("true false null")
        },
        makeSpec("go", "Go", "go") {
            cLike(&$0); $0.multilineQuotes = ["`"]; $0.quotes = ["\"", "'", "`"]
            $0.keywords = words("break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var")
            $0.constants = words("true false nil iota")
            $0.types = words("string int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64 float32 float64 bool byte rune error any uintptr")
        },
        makeSpec("rust", "Rust", "rs") {
            cLike(&$0); $0.hashDirectives = true
            $0.keywords = words("as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait type unsafe use where while union")
            $0.constants = words("true false")
            $0.types = words("i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str String Vec Option Result Box")
        },
        makeSpec("javascript", "JavaScript", "js jsx mjs cjs") {
            cLike(&$0); $0.multilineQuotes = ["`"]; $0.quotes = ["\"", "'", "`"]
            $0.keywords = words("break case catch class const continue debugger default delete do else export extends finally for function if import in instanceof let new return super switch this throw try typeof var void while with yield async await of static get set from as")
            $0.constants = words("true false null undefined NaN Infinity")
            $0.types = words("Array Object String Number Boolean Promise Map Set Date Error")
        },
        makeSpec("typescript", "TypeScript", "ts tsx") {
            cLike(&$0); $0.multilineQuotes = ["`"]; $0.quotes = ["\"", "'", "`"]; $0.atAttributes = true
            $0.keywords = words("break case catch class const continue debugger default delete do else export extends finally for function if import in instanceof let new return super switch this throw try typeof var void while with yield async await of static get set from as interface type enum implements namespace abstract declare readonly private public protected keyof infer is unknown never any")
            $0.constants = words("true false null undefined NaN Infinity")
            $0.types = words("string number boolean void object symbol bigint Array Promise Map Set Date Error Record Partial")
        },
        makeSpec("python", "Python", "py pyw") {
            $0.lineComments = ["#"]; $0.tripleQuotes = true; $0.atAttributes = true
            $0.keywords = words("and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case")
            $0.constants = words("True False None self cls")
            $0.types = words("int str float bool list dict set tuple bytes object type")
        },
        makeSpec("ruby", "Ruby", "rb") {
            $0.lineComments = ["#"]; $0.blockComments = [("=begin", "=end")]; $0.quotes = ["\"", "'", "`"]
            $0.keywords = words("alias and begin break case class def do else elsif end ensure for if in module next not or redo rescue retry return super then undef unless until when while yield require require_relative attr_accessor attr_reader attr_writer puts")
            $0.constants = words("true false nil self")
        },
        makeSpec("php", "PHP", "php") {
            cLike(&$0); $0.lineComments = ["//", "#"]; $0.dollarVariables = true
            $0.keywords = words("abstract and array as break callable case catch class clone const continue declare default do echo else elseif empty extends final finally fn for foreach function global goto if implements include include_once instanceof interface isset list namespace new or print private protected public require require_once return static switch throw trait try unset use var while xor yield")
            $0.constants = words("true false null TRUE FALSE NULL")
        },
        makeSpec("shell", "Shell", "sh bash zsh") {
            $0.lineComments = ["#"]; $0.dollarVariables = true; $0.quotes = ["\"", "'", "`"]; $0.hyphenIdentifiers = false
            $0.keywords = words("if then else elif fi case esac for while until do done in function select time return exit break continue local export readonly declare unset shift source alias echo cd test")
            $0.constants = words("true false")
        },
        makeSpec("sql", "SQL", "sql") {
            $0.lineComments = ["--"]; $0.blockComments = [("/*", "*/")]; $0.quotes = ["'", "\"", "`"]; $0.caseInsensitive = true
            $0.keywords = words("select from where insert into values update set delete create table alter drop index view join inner left right outer full cross on as and or not is in exists between like order by group having limit offset union all distinct case when then else end primary key foreign references default constraint unique check begin commit rollback transaction with add column")
            $0.constants = words("true false null")
            $0.types = words("int integer bigint smallint varchar char text boolean date timestamp datetime decimal numeric float double blob json")
        },
        makeSpec("html", "HTML", "html htm xhtml vue") {
            $0.blockComments = [("<!--", "-->")]; $0.markup = true
        },
        makeSpec("xml", "XML", "xml plist svg xsd csproj xaml storyboard") {
            $0.blockComments = [("<!--", "-->")]; $0.markup = true
        },
        makeSpec("css", "CSS", "css scss less") {
            $0.blockComments = [("/*", "*/")]; $0.keyColon = true; $0.hyphenIdentifiers = true; $0.atAttributes = true; $0.capitalizedTypes = false
            $0.constants = words("important none auto inherit initial unset transparent")
        },
        makeSpec("json", "JSON", "json jsonc geojson") {
            $0.quotes = ["\""]; $0.keyColon = true; $0.capitalizedTypes = false
            $0.constants = words("true false null")
        },
        makeSpec("yaml", "YAML", "yml yaml") {
            $0.lineComments = ["#"]; $0.keyColon = true; $0.hyphenIdentifiers = true; $0.capitalizedTypes = false
            $0.constants = words("true false null yes no")
        },
    ]

    static func spec(id: String) -> LanguageSpec? {
        id == plain.id ? plain : all.first { $0.id == id }
    }

    static func detect(fileNames: [String], samples: [String]) -> LanguageSpec {
        for name in fileNames {
            let ext = (name as NSString).pathExtension.lowercased()
            if !ext.isEmpty, let match = all.first(where: { $0.extensions.contains(ext) }) { return match }
            if ext.isEmpty, let match = filenameLanguage(name) { return match }
        }
        let sample = samples.map { String($0.prefix(4000)) }.joined(separator: "\n")
        return guess(from: sample)
    }

    private static func filenameLanguage(_ name: String) -> LanguageSpec? {
        switch name.lowercased() {
        case "makefile", "dockerfile": return spec(id: "shell")
        default: return nil
        }
    }

    private static func guess(from sample: String) -> LanguageSpec {
        let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        func has(_ needle: String) -> Bool { sample.contains(needle) }
        if trimmed.hasPrefix("#!") {
            let first = trimmed.split(separator: "\n").first.map(String.init) ?? ""
            if first.contains("python") { return spec(id: "python")! }
            if first.contains("node") { return spec(id: "javascript")! }
            if first.contains("ruby") { return spec(id: "ruby")! }
            return spec(id: "shell")!
        }
        if has("<?php") { return spec(id: "php")! }
        if trimmed.hasPrefix("<?xml") { return spec(id: "xml")! }
        if has("<!DOCTYPE html") || has("<html") { return spec(id: "html")! }
        if (trimmed.hasPrefix("{") || trimmed.hasPrefix("[")) && has("\":") { return spec(id: "json")! }
        if has("import SwiftUI") || has("import Foundation") || (has("func ") && has("let ") && has("var ")) { return spec(id: "swift")! }
        if has("#include") { return spec(id: "cpp")! }
        if has("package main") { return spec(id: "go")! }
        if has("fn main") || has("let mut ") { return spec(id: "rust")! }
        if has("using System") || has("namespace ") && has("public class") { return spec(id: "csharp")! }
        if has("public class") || has("System.out") { return spec(id: "java")! }
        if has("def ") && has(":\n") || has("import ") && !has(";") && has("print(") { return spec(id: "python")! }
        if has("console.log") || has("function ") || has("=> {") { return spec(id: "javascript")! }
        if has("SELECT ") || has("INSERT INTO") || has("CREATE TABLE") { return spec(id: "sql")! }
        return plain
    }
}

enum SyntaxHighlighter {
    private enum State {
        case normal
        case block(end: [UInt16])
        case string(quote: UInt16, triple: Bool)
        case tag
    }

    static func highlight(lines: [String], spec: LanguageSpec) -> [[SyntaxSpan]] {
        guard spec.id != "text" else { return Array(repeating: [], count: lines.count) }

        let lineComments = spec.lineComments.map { Array($0.utf16) }
        let blocks = spec.blockComments.map { (Array($0.start.utf16), Array($0.end.utf16)) }
        let quotes = Set(spec.quotes.compactMap { $0.utf16.first })
        let multiline = Set(spec.multilineQuotes.compactMap { $0.utf16.first })
        var state = State.normal
        var result: [[SyntaxSpan]] = []
        result.reserveCapacity(lines.count)

        for line in lines {
            let chars = Array(line.utf16)
            let n = chars.count
            var spans: [SyntaxSpan] = []
            var i = 0

            func matches(_ at: Int, _ delimiter: [UInt16]) -> Bool {
                guard !delimiter.isEmpty, at + delimiter.count <= n else { return false }
                for k in 0..<delimiter.count where chars[at + k] != delimiter[k] { return false }
                return true
            }
            func find(_ delimiter: [UInt16], from start: Int) -> Int? {
                var k = start
                while k + delimiter.count <= n {
                    if matches(k, delimiter) { return k }
                    k += 1
                }
                return nil
            }
            func scanString(from start: Int, quote: UInt16, triple: Bool) -> (end: Int, closed: Bool) {
                var j = start
                while j < n {
                    if chars[j] == 92 { j += 2; continue }
                    if triple {
                        if j + 2 < n, chars[j] == quote, chars[j + 1] == quote, chars[j + 2] == quote { return (j + 3, true) }
                    } else if chars[j] == quote {
                        return (j + 1, true)
                    }
                    j += 1
                }
                return (n, false)
            }
            func nextNonSpace(_ from: Int) -> UInt16? {
                var k = from
                while k < n, chars[k] == 32 || chars[k] == 9 { k += 1 }
                return k < n ? chars[k] : nil
            }
            func add(_ start: Int, _ end: Int, _ kind: SyntaxKind) {
                guard end > start else { return }
                spans.append(SyntaxSpan(start: start, length: min(end, n) - start, kind: kind))
            }

            switch state {
            case .block(let end):
                if let k = find(end, from: 0) {
                    add(0, k + end.count, .comment)
                    i = k + end.count
                    state = .normal
                } else {
                    add(0, n, .comment)
                    result.append(spans)
                    continue
                }
            case .string(let quote, let triple):
                let scanned = scanString(from: 0, quote: quote, triple: triple)
                add(0, scanned.end, .string)
                if scanned.closed {
                    i = scanned.end
                    state = .normal
                } else {
                    result.append(spans)
                    continue
                }
            default:
                break
            }

            if spec.markup {
                lexMarkup(chars: chars, from: i, spec: spec, blocks: blocks, state: &state, spans: &spans)
                result.append(spans)
                continue
            }

            lineLoop: while i < n {
                let c = chars[i]
                if c == 32 || c == 9 { i += 1; continue }

                for comment in lineComments where matches(i, comment) {
                    add(i, n, .comment)
                    i = n
                    continue lineLoop
                }
                for (start, end) in blocks where matches(i, start) {
                    if let k = find(end, from: i + start.count) {
                        add(i, k + end.count, .comment)
                        i = k + end.count
                    } else {
                        add(i, n, .comment)
                        state = .block(end: end)
                        i = n
                    }
                    continue lineLoop
                }

                if quotes.contains(c) {
                    let triple = spec.tripleQuotes && i + 2 < n && chars[i + 1] == c && chars[i + 2] == c
                    let scanned = scanString(from: triple ? i + 3 : i + 1, quote: c, triple: triple)
                    if !scanned.closed && !triple && c == 39 && !multiline.contains(c) {
                        i += 1
                        continue
                    }
                    var kind = SyntaxKind.string
                    if spec.keyColon, scanned.closed, nextNonSpace(scanned.end) == 58 { kind = .property }
                    add(i, scanned.end, kind)
                    if !scanned.closed && (triple || multiline.contains(c)) { state = .string(quote: c, triple: triple) }
                    i = scanned.end
                    continue
                }

                if c == 35, spec.hashDirectives, chars[..<i].allSatisfy({ $0 == 32 || $0 == 9 }) {
                    var j = i + 1
                    if j < n, chars[j] == 91 || chars[j] == 33 {
                        while j < n, chars[j] != 93 { j += 1 }
                        j = min(j + 1, n)
                    } else {
                        while j < n, chars[j] == 32 { j += 1 }
                        while j < n, isIdentPart(chars[j]) { j += 1 }
                    }
                    add(i, j, .directive)
                    let directive = String(decoding: chars[i..<j], as: UTF16.self)
                    if directive.hasPrefix("#include") || directive.hasPrefix("#import"), let open = nextNonSpace(j), open == 60, let lt = (j..<n).first(where: { chars[$0] == 60 }) {
                        let gt: Int
                        if let close = (lt..<n).first(where: { chars[$0] == 62 }) {
                            gt = close + 1
                        } else {
                            gt = n
                        }
                        add(lt, gt, .string)
                        j = gt
                    }
                    i = j
                    continue
                }

                if c == 64, spec.atAttributes, i + 1 < n, isIdentStart(chars[i + 1]) {
                    var j = i + 1
                    while j < n, isIdentPart(chars[j]) || chars[j] == 46 { j += 1 }
                    add(i, j, .directive)
                    i = j
                    continue
                }

                if isDigit(c) || (c == 46 && i + 1 < n && isDigit(chars[i + 1]) && (i == 0 || !isIdentPart(chars[i - 1]))) {
                    var j = i
                    while j < n, isIdentPart(chars[j]) || (chars[j] == 46 && j + 1 < n && isDigit(chars[j + 1])) { j += 1 }
                    add(i, j, .number)
                    i = j
                    continue
                }

                if isIdentStart(c) || (c == 36 && spec.dollarVariables) {
                    var j = i + 1
                    while j < n {
                        if isIdentPart(chars[j]) { j += 1 }
                        else if spec.hyphenIdentifiers, chars[j] == 45, j + 1 < n, isIdentPart(chars[j + 1]) { j += 1 }
                        else { break }
                    }
                    let word = String(decoding: chars[i..<j], as: UTF16.self)
                    add(i, j, classify(word, followedBy: nextNonSpace(j), spec: spec))
                    i = j
                    continue
                }

                i += 1
            }
            result.append(spans)
        }
        return result
    }

    private static func classify(_ word: String, followedBy next: UInt16?, spec: LanguageSpec) -> SyntaxKind {
        let lookup = spec.caseInsensitive ? word.lowercased() : word
        if spec.keywords.contains(lookup) { return .keyword }
        if spec.constants.contains(lookup) { return .constant }
        if spec.types.contains(word) { return .type }
        if spec.dollarVariables && word.hasPrefix("$") { return .property }
        if next == 40 { return .function }
        if spec.keyColon && next == 58 { return .property }
        if spec.capitalizedTypes, let first = word.unicodeScalars.first, CharacterSet.uppercaseLetters.contains(first), word.contains(where: { $0.isLowercase }) { return .type }
        if word.count > 1, word.allSatisfy({ $0.isUppercase || $0.isNumber || $0 == "_" }), word.contains(where: { $0.isUppercase }) { return .constant }
        return .plain
    }

    private static func lexMarkup(chars: [UInt16], from start: Int, spec: LanguageSpec, blocks: [([UInt16], [UInt16])], state: inout State, spans: inout [SyntaxSpan]) {
        let n = chars.count
        var i = start

        func matches(_ at: Int, _ delimiter: [UInt16]) -> Bool {
            guard at + delimiter.count <= n else { return false }
            for k in 0..<delimiter.count where chars[at + k] != delimiter[k] { return false }
            return true
        }
        func nameChar(_ c: UInt16) -> Bool { isIdentPart(c) || c == 45 || c == 58 || c == 46 }

        outer: while i < n {
            let c = chars[i]
            if case .tag = state {
                if c == 62 { state = .normal; i += 1; continue }
                if c == 47, i + 1 < n, chars[i + 1] == 62 { state = .normal; i += 2; continue }
                if c == 34 || c == 39 {
                    var j = i + 1
                    while j < n, chars[j] != c { j += 1 }
                    j = min(j + 1, n)
                    spans.append(SyntaxSpan(start: i, length: j - i, kind: .string))
                    i = j
                    continue
                }
                if isIdentStart(c) {
                    var j = i + 1
                    while j < n, nameChar(chars[j]) { j += 1 }
                    spans.append(SyntaxSpan(start: i, length: j - i, kind: .property))
                    i = j
                    continue
                }
                i += 1
                continue
            }

            for (open, close) in blocks where matches(i, open) {
                var k = i + open.count
                var closed = false
                while k + close.count <= n {
                    if matches(k, close) { closed = true; break }
                    k += 1
                }
                let end = closed ? k + close.count : n
                spans.append(SyntaxSpan(start: i, length: end - i, kind: .comment))
                if !closed { state = .block(end: close) }
                i = end
                if !closed { return }
                continue outer
            }

            if c == 60, i + 1 < n, chars[i + 1] == 47 || chars[i + 1] == 63 || chars[i + 1] == 33 || isIdentStart(chars[i + 1]) {
                var j = i + 1
                if chars[j] == 47 || chars[j] == 63 || chars[j] == 33 { j += 1 }
                while j < n, nameChar(chars[j]) { j += 1 }
                spans.append(SyntaxSpan(start: i, length: j - i, kind: .keyword))
                state = .tag
                i = j
                continue
            }
            i += 1
        }
    }

    private static func isDigit(_ c: UInt16) -> Bool { c >= 48 && c <= 57 }
    private static func isIdentStart(_ c: UInt16) -> Bool {
        (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c > 127
    }
    private static func isIdentPart(_ c: UInt16) -> Bool { isIdentStart(c) || isDigit(c) || c == 36 }
}
