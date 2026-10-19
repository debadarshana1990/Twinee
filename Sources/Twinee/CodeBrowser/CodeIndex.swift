import SwiftUI

enum SourceLanguage: Equatable {
    case c, cpp, python
    case other(String)

    var specID: String {
        switch self {
        case .c: return "c"
        case .cpp: return "cpp"
        case .python: return "python"
        case .other(let id): return id
        }
    }

    var name: String {
        switch self {
        case .c: return "C"
        case .cpp: return "C++"
        case .python: return "Python"
        case .other(let id): return LanguageRegistry.spec(id: id)?.name ?? "Text"
        }
    }

    static func from(extension ext: String) -> SourceLanguage? {
        switch ext.lowercased() {
        case "c": return .c
        case "h", "hpp", "hh", "hxx", "h++", "cpp", "cc", "cxx", "c++", "inl", "ipp", "tpp": return .cpp
        case "py", "pyi": return .python
        default: return nil
        }
    }

    // Any file can be opened; languages without symbol indexing still get syntax colouring.
    static func detect(path: String) -> SourceLanguage {
        if let known = from(extension: (path as NSString).pathExtension) { return known }
        let name = (path as NSString).lastPathComponent
        let spec = LanguageRegistry.detect(fileNames: [name], samples: [])
        return .other(spec.id)
    }

    var isIndexed: Bool {
        if case .other = self { return false }
        return true
    }
}

enum SymbolKind: String, CaseIterable, Identifiable {
    case function, method, prototype, cls, structure, enumeration, union, namespace, macro, typedef, variable

    var id: String { rawValue }

    var label: String {
        switch self {
        case .function: return "Function"
        case .method: return "Method"
        case .prototype: return "Declaration"
        case .cls: return "Class"
        case .structure: return "Struct"
        case .enumeration: return "Enum"
        case .union: return "Union"
        case .namespace: return "Namespace"
        case .macro: return "Macro"
        case .typedef: return "Typedef"
        case .variable: return "Constant"
        }
    }

    var symbol: String {
        switch self {
        case .function: return "f.cursive"
        case .method: return "m.square"
        case .prototype: return "doc.text"
        case .cls: return "c.square"
        case .structure: return "s.square"
        case .enumeration: return "e.square"
        case .union: return "u.square"
        case .namespace: return "n.square"
        case .macro: return "number.square"
        case .typedef: return "t.square"
        case .variable: return "v.square"
        }
    }

    var tint: Color {
        switch self {
        case .function, .method: return Color(hex: 0x58A486)
        case .prototype: return Color(hex: 0x8E8E99)
        case .cls, .structure, .enumeration, .union: return Color(hex: 0x638FC8)
        case .namespace: return Color(hex: 0xD99162)
        case .macro: return Color(hex: 0xCF7892)
        case .typedef: return Color(hex: 0x8170D8)
        case .variable: return Color(hex: 0xB98EFF)
        }
    }

    var isType: Bool { self == .cls || self == .structure || self == .enumeration || self == .union || self == .typedef }
    var isCallable: Bool { self == .function || self == .method || self == .prototype }
}

struct CodeSymbol: Identifiable, Hashable {
    let name: String
    let kind: SymbolKind
    let line: Int
    let path: String
    let container: String?
    let signature: String

    var id: String { "\(path)#\(line)#\(kind.rawValue)#\(name)" }
}

enum SymbolExtractor {
    static func extract(text: String, path: String, language: SourceLanguage) -> [CodeSymbol] {
        guard language.isIndexed else { return [] }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let spec = LanguageRegistry.spec(id: language.specID)!
        let spans = SyntaxHighlighter.highlight(lines: lines, spec: spec)
        let code = blanked(lines, spans: spans, dropPreprocessor: language != .python)
        var symbols: [CodeSymbol]
        switch language {
        case .python: symbols = python(code, original: lines, path: path)
        case .c, .cpp: symbols = cFamily(code, original: lines, path: path, cpp: language == .cpp)
        case .other: symbols = []
        }
        symbols.sort { $0.line < $1.line }
        return symbols
    }

    // Comments and strings become spaces so braces and keywords inside them are never mistaken for code.
    private static func blanked(_ lines: [String], spans: [[SyntaxSpan]], dropPreprocessor: Bool) -> [String] {
        var result: [String] = []
        var continuation = false
        for (index, line) in lines.enumerated() {
            var units = Array(line.utf16)
            for span in spans[index] where span.kind == .comment || span.kind == .string {
                for k in span.start..<min(units.count, span.start + span.length) { units[k] = 32 }
            }
            let text = String(decoding: units, as: UTF16.self)
            if dropPreprocessor {
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                if continuation || trimmed.hasPrefix("#") {
                    continuation = line.trimmingCharacters(in: .whitespaces).hasSuffix("\\")
                    result.append("")
                    continue
                }
            }
            result.append(text)
        }
        return result
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern)
    }

    private static func match(_ expression: NSRegularExpression, _ text: String) -> NSTextCheckingResult? {
        expression.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    private static func group(_ result: NSTextCheckingResult, _ index: Int, in text: String) -> String? {
        let range = result.range(at: index)
        guard range.location != NSNotFound else { return nil }
        return (text as NSString).substring(with: range)
    }

    private static func squeeze(_ text: String, limit: Int = 140) -> String {
        let collapsed = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return collapsed.count > limit ? String(collapsed.prefix(limit)) + "…" : collapsed
    }

    // MARK: Python

    private static func python(_ code: [String], original: [String], path: String) -> [CodeSymbol] {
        let definition = regex(#"^(\s*)(?:async\s+)?def\s+([A-Za-z_]\w*)\s*\("#)
        let classDefinition = regex(#"^(\s*)class\s+([A-Za-z_]\w*)"#)
        let constant = regex(#"^([A-Z][A-Z0-9_]+)\s*(?::[^=]+)?="#)
        var symbols: [CodeSymbol] = []
        var scopes: [(indent: Int, name: String, isClass: Bool)] = []

        for (index, line) in code.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let indent = line.prefix { $0 == " " || $0 == "\t" }.count
            if let found = match(classDefinition, line), let name = group(found, 2, in: line) {
                while let last = scopes.last, last.indent >= indent { scopes.removeLast() }
                symbols.append(CodeSymbol(name: name, kind: .cls, line: index, path: path, container: scopes.last?.name, signature: squeeze(original[index].trimmingCharacters(in: .whitespaces))))
                scopes.append((indent, name, true))
            } else if let found = match(definition, line), let name = group(found, 2, in: line) {
                while let last = scopes.last, last.indent >= indent { scopes.removeLast() }
                let owner = scopes.last
                symbols.append(CodeSymbol(name: name, kind: owner?.isClass == true ? .method : .function, line: index, path: path, container: owner?.name, signature: squeeze(original[index].trimmingCharacters(in: .whitespaces))))
                scopes.append((indent, name, false))
            } else if indent == 0, let found = match(constant, line), let name = group(found, 1, in: line) {
                scopes.removeAll()
                symbols.append(CodeSymbol(name: name, kind: .variable, line: index, path: path, container: nil, signature: squeeze(original[index])))
            } else {
                while let last = scopes.last, last.indent >= indent { scopes.removeLast() }
            }
        }
        return symbols
    }

    // MARK: C and C++

    private struct Block {
        enum Kind { case namespace, type, function, other }
        var kind: Kind
        var name = ""
        var inParens = false
        var symbolIndex: Int?
    }

    private static let controlWords: Set<String> = ["if", "for", "while", "switch", "catch", "return", "sizeof", "else", "do", "defined", "alignas", "decltype", "static_assert", "__attribute__", "typeof", "throw", "new", "delete"]

    private static func cFamily(_ code: [String], original: [String], path: String, cpp: Bool) -> [CodeSymbol] {
        var symbols: [CodeSymbol] = []
        let macro = regex(#"^\s*#\s*define\s+([A-Za-z_]\w*)"#)
        for (index, line) in original.enumerated() {
            if let found = match(macro, line), let name = group(found, 1, in: line) {
                symbols.append(CodeSymbol(name: name, kind: .macro, line: index, path: path, container: nil, signature: squeeze(line.trimmingCharacters(in: .whitespaces))))
            }
        }

        let namespaceExpression = regex(#"^(?:inline\s+)?namespace\s*([A-Za-z_][\w:]*)?\s*$"#)
        let externExpression = regex(#"^extern\b[^()=]*$"#)
        let typeExpression = regex(#"\b(class|struct|union|enum)\b(?:\s+(?:class|struct))?\s*([^{:;=]*)"#)
        let nameExpression = regex(#"((?:[A-Za-z_]\w*::)*(?:operator\s*\S+?|~?[A-Za-z_]\w*))\s*$"#)
        let accessExpression = regex(#"\b(?:public|private|protected|signals|slots)\s*:"#)
        let templateExpression = regex(#"^\s*template\s*<[^(){};]*?>\s*(?=[A-Za-z_])"#)

        var stack: [Block] = []
        var pending = ""
        var pendingLine = 0
        var parenDepth = 0
        var awaitingTypedef: Int?

        func clean(_ text: String) -> String {
            let range = NSRange(location: 0, length: (text as NSString).length)
            let stripped = accessExpression.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
            let strippedRange = NSRange(location: 0, length: (stripped as NSString).length)
            return templateExpression.stringByReplacingMatches(in: stripped, range: strippedRange, withTemplate: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func lineOf(offset: Int, in text: String) -> Int {
            let prefix = (text as NSString).substring(to: min(offset, (text as NSString).length))
            return pendingLine + prefix.reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
        }

        // Splits "ns::Class::name" into its container and base name.
        func split(_ qualified: String, enclosing: Block?) -> (name: String, container: String?) {
            let parts = qualified.components(separatedBy: "::")
            if parts.count > 1 { return (parts.last!, parts.dropLast().joined(separator: "::")) }
            if let enclosing, enclosing.kind == .type { return (qualified, enclosing.name) }
            return (qualified, nil)
        }

        func callable(_ text: String, enclosing: Block?) -> (name: String, container: String?, offset: Int, signature: String)? {
            guard let open = text.firstIndex(of: "("), text[open...].contains(")") else { return nil }
            let prefix = String(text[..<open])
            if prefix.contains("=") && !prefix.contains("operator") { return nil }
            guard let found = match(nameExpression, prefix), let qualified = group(found, 1, in: prefix) else { return nil }
            let base = qualified.components(separatedBy: "::").last ?? qualified
            if controlWords.contains(base) { return nil }
            let words = prefix.split(whereSeparator: { $0.isWhitespace || $0 == "*" || $0 == "&" })
            if !cpp && words.count < 2 && enclosing != nil { return nil }
            let parts = split(qualified.trimmingCharacters(in: .whitespaces), enclosing: enclosing)
            var depth = 0
            var close = open
            for index in text[open...].indices {
                if text[index] == "(" { depth += 1 }
                if text[index] == ")" { depth -= 1; if depth == 0 { close = index; break } }
            }
            let signature = squeeze(String(text[...close]))
            let offset = text.distance(from: text.startIndex, to: open)
            return (parts.name, parts.container, offset, signature)
        }

        func handleOpen() {
            let text = clean(pending)
            let enclosing = stack.last
            let canDefine = enclosing == nil || enclosing?.kind == .namespace || enclosing?.kind == .type
            var block = Block(kind: .other)
            defer { stack.append(block); pending = "" }
            guard canDefine, !text.isEmpty else { return }

            if let found = match(namespaceExpression, text) {
                let name = group(found, 1, in: text) ?? ""
                block = Block(kind: .namespace, name: name)
                if !name.isEmpty { symbols.append(CodeSymbol(name: name, kind: .namespace, line: lineOf(offset: 0, in: text), path: path, container: nil, signature: "namespace \(name)")) }
                return
            }
            if match(externExpression, text) != nil {
                block = Block(kind: .namespace)
                return
            }
            if !text.contains("("), !text.contains("="), let found = match(typeExpression, text), let keyword = group(found, 1, in: text) {
                let tail = group(found, 2, in: text) ?? ""
                let identifiers = tail.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") }).map(String.init).filter { $0 != "final" }
                let name = identifiers.last ?? ""
                let kind: SymbolKind = keyword == "class" ? .cls : keyword == "union" ? .union : keyword == "enum" ? .enumeration : .structure
                let owner = enclosing?.kind == .type ? enclosing?.name : nil
                symbols.append(CodeSymbol(name: name.isEmpty ? "(anonymous)" : name, kind: kind, line: lineOf(offset: (text as NSString).range(of: keyword).location, in: text), path: path, container: owner, signature: squeeze("\(keyword) \(tail)")))
                block = Block(kind: kind == .enumeration ? .other : .type, name: name, symbolIndex: symbols.count - 1)
                return
            }
            if let function = callable(text, enclosing: enclosing) {
                let kind: SymbolKind = function.container != nil ? .method : .function
                symbols.append(CodeSymbol(name: function.name, kind: kind, line: lineOf(offset: function.offset, in: text), path: path, container: function.container, signature: function.signature))
                block = Block(kind: .function)
            }
        }

        func handleSemicolon() {
            let text = clean(pending)
            defer { pending = "" }
            if let index = awaitingTypedef {
                awaitingTypedef = nil
                let identifiers = text.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") }).map(String.init)
                if let name = identifiers.last {
                    if symbols[index].name == "(anonymous)" {
                        let old = symbols[index]
                        symbols[index] = CodeSymbol(name: name, kind: old.kind, line: old.line, path: path, container: old.container, signature: old.signature)
                    } else {
                        symbols.append(CodeSymbol(name: name, kind: .typedef, line: pendingLine, path: path, container: nil, signature: "typedef \(symbols[index].name) \(name)"))
                    }
                }
                return
            }
            let enclosing = stack.last
            guard enclosing == nil || enclosing?.kind == .namespace || enclosing?.kind == .type, !text.isEmpty else { return }

            if text.hasPrefix("typedef") || text.hasPrefix("using ") {
                var name: String?
                if let found = match(regex(#"\(\s*\*\s*(\w+)\s*\)"#), text) { name = group(found, 1, in: text) }
                else if text.hasPrefix("using "), let found = match(regex(#"^using\s+(\w+)\s*="#), text) { name = group(found, 1, in: text) }
                else if text.hasPrefix("typedef") { name = text.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") }).map(String.init).last }
                if let name { symbols.append(CodeSymbol(name: name, kind: .typedef, line: pendingLine, path: path, container: nil, signature: squeeze(text))) }
                return
            }
            let blocked = ["return", "friend", "static_assert", "extern", "delete", "goto"]
            if blocked.contains(where: { text.hasPrefix($0 + " ") }) { return }
            if let function = callable(text, enclosing: enclosing) {
                let prefixWords = text.prefix(function.offset).split(whereSeparator: { $0.isWhitespace || $0 == "*" || $0 == "&" })
                let needsType = enclosing?.kind != .type
                if needsType && prefixWords.count < 2 { return }
                symbols.append(CodeSymbol(name: function.name, kind: .prototype, line: lineOf(offset: function.offset, in: text), path: path, container: function.container, signature: function.signature))
            }
        }

        for (lineIndex, line) in code.enumerated() {
            for ch in line {
                if pending.isEmpty && !ch.isWhitespace { pendingLine = lineIndex }
                switch ch {
                case "(":
                    parenDepth += 1
                    pending.append(ch)
                case ")":
                    parenDepth = max(0, parenDepth - 1)
                    pending.append(ch)
                case "{":
                    if parenDepth > 0 {
                        stack.append(Block(kind: .other, inParens: true))
                        pending.append(ch)
                    } else {
                        handleOpen()
                    }
                case "}":
                    guard let popped = stack.popLast() else { pending = ""; continue }
                    if popped.inParens {
                        pending.append(ch)
                    } else {
                        pending = ""
                        if let index = popped.symbolIndex, symbols[index].kind != .namespace { awaitingTypedef = index }
                    }
                case ";":
                    if parenDepth > 0 { pending.append(ch) } else { handleSemicolon(); awaitingTypedef = nil }
                default:
                    if pending.isEmpty && ch.isWhitespace { continue }
                    pending.append(ch)
                }
            }
            if !pending.isEmpty { pending.append("\n") }
        }
        return symbols
    }
}
