import SwiftUI
import AppKit

enum RichText {
    static let bodySize: CGFloat = 14
    static let headingSizes: [CGFloat] = [26, 20, 16]
    static let listIndent: CGFloat = 24

    static var bodyFont: NSFont { NSFont.systemFont(ofSize: bodySize) }

    // Menlo survives the RTF round trip, so a fixed-pitch font is what marks text as code.
    static var codeFont: NSFont { NSFont(name: "Menlo", size: 12.5) ?? NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular) }
    static var codeBackground: NSColor { NSColor(white: 0.5, alpha: 0.16) }

    static func isCode(_ font: NSFont?) -> Bool { font?.isFixedPitch == true }

    // Runs of whole paragraphs written in the code font.
    static func codeBlocks(in text: NSAttributedString) -> [NSRange] {
        let ns = text.string as NSString
        var blocks: [NSRange] = []
        var current: NSRange?
        var location = 0
        while location < ns.length {
            let paragraph = ns.paragraphRange(for: NSRange(location: location, length: 0))
            var end = NSMaxRange(paragraph)
            if end > paragraph.location, ns.character(at: end - 1) == 10 { end -= 1 }
            let isBlock = end > paragraph.location
                && isCode(text.attribute(.font, at: paragraph.location, effectiveRange: nil) as? NSFont)
                && isCode(text.attribute(.font, at: end - 1, effectiveRange: nil) as? NSFont)
            if isBlock {
                current = current.map { NSUnionRange($0, paragraph) } ?? paragraph
            } else if let finished = current {
                blocks.append(finished)
                current = nil
            }
            location = NSMaxRange(paragraph)
        }
        if let finished = current { blocks.append(finished) }
        return blocks
    }

    static func highlight(_ storage: NSMutableAttributedString, range: NSRange, spec: LanguageSpec?) {
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
        let text = (storage.string as NSString).substring(with: range)
        let language = spec ?? LanguageRegistry.detect(fileNames: [], samples: [text])
        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
        guard language.id != "text" else { return }
        let lines = text.components(separatedBy: "\n")
        let spans = SyntaxHighlighter.highlight(lines: lines, spec: language)
        var offset = range.location
        for (index, line) in lines.enumerated() {
            for span in spans[index] where span.kind != .plain {
                storage.addAttribute(.foregroundColor, value: SyntaxColors.nsColor(span.kind), range: NSRange(location: offset + span.start, length: span.length))
            }
            offset += line.utf16.count + 1
        }
    }

    // nil is body text; 0...2 are Heading 1...3.
    static func font(heading level: Int?) -> NSFont {
        guard let level else { return bodyFont }
        return NSFont.systemFont(ofSize: headingSizes[min(max(level, 0), 2)], weight: .bold)
    }

    static func headingLevel(of font: NSFont?) -> Int? {
        guard let font else { return nil }
        return headingSizes.firstIndex(of: font.pointSize)
    }

    static var baseParagraph: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        style.paragraphSpacing = 4
        return style
    }

    static var listParagraph: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        style.paragraphSpacing = 4
        style.headIndent = listIndent
        style.tabStops = [NSTextTab(textAlignment: .left, location: listIndent)]
        style.defaultTabInterval = listIndent
        return style
    }

    static var bodyAttributes: [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: baseParagraph]
    }

    static func document(from sections: [TopicSection]) -> NSAttributedString {
        let doc = NSMutableAttributedString()
        for section in sections {
            if !section.title.isEmpty {
                var attrs = bodyAttributes
                attrs[.font] = font(heading: 1)
                doc.append(NSAttributedString(string: section.title + "\n", attributes: attrs))
            }
            if !section.content.isEmpty {
                doc.append(NSAttributedString(string: section.content + "\n", attributes: bodyAttributes))
            }
        }
        return doc
    }

    // Colors are not stored so the text follows the White/Black theme.
    static func encode(_ attributed: NSAttributedString) -> Data {
        guard attributed.length > 0 else { return Data() }
        let copy = NSMutableAttributedString(attributedString: attributed)
        let full = NSRange(location: 0, length: copy.length)
        copy.removeAttribute(.foregroundColor, range: full)
        copy.removeAttribute(.backgroundColor, range: full)
        return (try? copy.data(from: full, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])) ?? Data()
    }

    static func decode(_ data: Data) -> NSAttributedString {
        guard !data.isEmpty, let loaded = NSAttributedString(rtf: data, documentAttributes: nil) else {
            return NSAttributedString()
        }
        let doc = NSMutableAttributedString(attributedString: loaded)
        let full = NSRange(location: 0, length: doc.length)
        let fm = NSFontManager.shared
        // RTF drops the system font for Helvetica Neue, so rebuild fonts from size and traits.
        doc.enumerateAttribute(.font, in: full) { value, range, _ in
            guard let old = value as? NSFont else {
                doc.addAttribute(.font, value: bodyFont, range: range)
                return
            }
            let traits = fm.traits(of: old)
            if old.isFixedPitch {
                var code = codeFont
                if traits.contains(.boldFontMask) { code = fm.convert(code, toHaveTrait: .boldFontMask) }
                if traits.contains(.italicFontMask) { code = fm.convert(code, toHaveTrait: .italicFontMask) }
                doc.addAttribute(.font, value: code, range: range)
                doc.addAttribute(.backgroundColor, value: codeBackground, range: range)
                return
            }
            var font = NSFont.systemFont(ofSize: old.pointSize, weight: traits.contains(.boldFontMask) ? .bold : .regular)
            if traits.contains(.italicFontMask) { font = fm.convert(font, toHaveTrait: .italicFontMask) }
            doc.addAttribute(.font, value: font, range: range)
        }
        doc.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
        for block in codeBlocks(in: doc) { highlight(doc, range: block, spec: nil) }
        return doc
    }
}

enum ListMarker {
    static let bullet = "•\t"

    // UTF-16 length of the list marker that starts the line, if any.
    static func length(of line: String) -> Int? {
        if line.hasPrefix(bullet) { return 2 }
        let digits = line.prefix { $0.isASCII && $0.isNumber }.count
        guard digits > 0, line.dropFirst(digits).hasPrefix(".\t") else { return nil }
        return digits + 2
    }

    static func number(of line: String) -> Int? {
        Int(line.prefix { $0.isASCII && $0.isNumber })
    }
}

final class EditorController: ObservableObject {
    weak var textView: NSTextView?
    var codeLanguage: LanguageSpec?

    func toggleCode() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let ns = tv.string as NSString
        let selection = tv.selectedRange()
        let paragraph = ns.paragraphRange(for: selection)
        var content = paragraph
        if content.length > 0, ns.character(at: NSMaxRange(content) - 1) == 10 { content.length -= 1 }
        let isInline = selection.length > 0 && !ns.substring(with: selection).contains("\n") && selection != content
        let target = isInline ? selection : paragraph

        if target.length == 0 {
            let has = RichText.isCode(tv.typingAttributes[.font] as? NSFont)
            tv.typingAttributes[.font] = has ? RichText.bodyFont : RichText.codeFont
            if has { tv.typingAttributes.removeValue(forKey: .backgroundColor) } else { tv.typingAttributes[.backgroundColor] = RichText.codeBackground }
            tv.window?.makeFirstResponder(tv)
            return
        }
        let removing = RichText.isCode(storage.attribute(.font, at: target.location, effectiveRange: nil) as? NSFont)
        guard tv.shouldChangeText(in: target, replacementString: nil) else { return }
        storage.beginEditing()
        if removing {
            storage.addAttribute(.font, value: RichText.bodyFont, range: target)
            storage.removeAttribute(.backgroundColor, range: target)
            storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: target)
        } else {
            storage.addAttribute(.font, value: RichText.codeFont, range: target)
            storage.addAttribute(.backgroundColor, value: RichText.codeBackground, range: target)
        }
        storage.endEditing()
        if !removing && !isInline { RichText.highlight(storage, range: target, spec: codeLanguage) }
        tv.didChangeText()
        tv.window?.makeFirstResponder(tv)
    }

    func setCodeLanguage(_ spec: LanguageSpec?) {
        codeLanguage = spec
        rehighlight()
        textView?.didChangeText()
        textView?.window?.makeFirstResponder(textView)
    }

    // Recolors the code block around the caret after an edit.
    func rehighlight() {
        guard let tv = textView, let storage = tv.textStorage, storage.length > 0, !tv.hasMarkedText() else { return }
        let caret = tv.selectedRange().location
        guard let block = RichText.codeBlocks(in: storage).first(where: { NSLocationInRange(caret, $0) || NSMaxRange($0) == caret }) else { return }
        RichText.highlight(storage, range: block, spec: codeLanguage)
    }

    func heading(_ level: Int?) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let paragraph = (tv.string as NSString).paragraphRange(for: tv.selectedRange())
        let currentFont = (paragraph.length > 0 ? storage.attribute(.font, at: paragraph.location, effectiveRange: nil) : tv.typingAttributes[.font]) as? NSFont
        let target = RichText.headingLevel(of: currentFont) == level ? nil : level
        let font = RichText.font(heading: target)
        if paragraph.length > 0, tv.shouldChangeText(in: paragraph, replacementString: nil) {
            storage.addAttribute(.font, value: font, range: paragraph)
            storage.removeAttribute(.backgroundColor, range: paragraph)
            tv.didChangeText()
        }
        tv.typingAttributes[.font] = font
        tv.typingAttributes.removeValue(forKey: .backgroundColor)
        tv.window?.makeFirstResponder(tv)
    }

    func toggle(_ trait: NSFontTraitMask) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let fm = NSFontManager.shared
        let selection = tv.selectedRange()
        if selection.length == 0 {
            let current = (tv.typingAttributes[.font] as? NSFont) ?? RichText.bodyFont
            let has = fm.traits(of: current).contains(trait)
            tv.typingAttributes[.font] = has ? fm.convert(current, toNotHaveTrait: trait) : fm.convert(current, toHaveTrait: trait)
        } else {
            let first = (storage.attribute(.font, at: selection.location, effectiveRange: nil) as? NSFont) ?? RichText.bodyFont
            let has = fm.traits(of: first).contains(trait)
            guard tv.shouldChangeText(in: selection, replacementString: nil) else { return }
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: selection) { value, range, _ in
                let font = (value as? NSFont) ?? RichText.bodyFont
                storage.addAttribute(.font, value: has ? fm.convert(font, toNotHaveTrait: trait) : fm.convert(font, toHaveTrait: trait), range: range)
            }
            storage.endEditing()
            tv.didChangeText()
        }
        tv.window?.makeFirstResponder(tv)
    }

    func toggleUnderline() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let selection = tv.selectedRange()
        let single = NSUnderlineStyle.single.rawValue
        if selection.length == 0 {
            let has = ((tv.typingAttributes[.underlineStyle] as? Int) ?? 0) != 0
            if has { tv.typingAttributes.removeValue(forKey: .underlineStyle) } else { tv.typingAttributes[.underlineStyle] = single }
        } else {
            let has = ((storage.attribute(.underlineStyle, at: selection.location, effectiveRange: nil) as? Int) ?? 0) != 0
            guard tv.shouldChangeText(in: selection, replacementString: nil) else { return }
            if has { storage.removeAttribute(.underlineStyle, range: selection) } else { storage.addAttribute(.underlineStyle, value: single, range: selection) }
            tv.didChangeText()
        }
        tv.window?.makeFirstResponder(tv)
    }

    func toggleList(ordered: Bool) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let ns = tv.string as NSString
        let selected = ns.paragraphRange(for: tv.selectedRange())
        var paragraphs: [NSRange] = []
        var location = selected.location
        repeat {
            let range = ns.paragraphRange(for: NSRange(location: location, length: 0))
            paragraphs.append(range)
            location = NSMaxRange(range)
        } while location < NSMaxRange(selected)

        func markerLength(_ range: NSRange) -> Int? { ListMarker.length(of: ns.substring(with: range)) }
        func isRequestedKind(_ range: NSRange) -> Bool {
            let line = ns.substring(with: range)
            return ListMarker.length(of: line) != nil && line.hasPrefix(ListMarker.bullet) != ordered
        }
        let removing = paragraphs.allSatisfy(isRequestedKind)

        let original = tv.selectedRange()
        let lengthBefore = tv.string.utf16.count
        tv.undoManager?.beginUndoGrouping()
        for (index, paragraph) in paragraphs.enumerated().reversed() {
            if let length = markerLength(paragraph) {
                Self.replace(in: tv, range: NSRange(location: paragraph.location, length: length), with: "")
            }
            if !removing {
                let marker = ordered ? "\(index + 1).\t" : ListMarker.bullet
                Self.replace(in: tv, range: NSRange(location: paragraph.location, length: 0), with: marker)
            }
            Self.style(storage, at: paragraph.location, list: !removing)
        }
        tv.undoManager?.endUndoGrouping()
        let delta = tv.string.utf16.count - lengthBefore
        if original.length == 0 {
            tv.setSelectedRange(NSRange(location: max(selected.location, original.location + delta), length: 0))
        } else {
            tv.setSelectedRange(NSRange(location: selected.location, length: max(0, selected.length + delta)))
        }
        tv.didChangeText()
        tv.window?.makeFirstResponder(tv)
    }

    static func replace(in tv: NSTextView, range: NSRange, with string: String) {
        guard let storage = tv.textStorage, tv.shouldChangeText(in: range, replacementString: string) else { return }
        var attributes = tv.typingAttributes
        if range.location < storage.length { attributes = storage.attributes(at: range.location, effectiveRange: nil) }
        storage.replaceCharacters(in: range, with: NSAttributedString(string: string, attributes: attributes))
        tv.didChangeText()
    }

    static func style(_ storage: NSTextStorage, at location: Int, list: Bool) {
        let ns = storage.string as NSString
        let range = ns.paragraphRange(for: NSRange(location: min(location, ns.length), length: 0))
        guard range.length > 0 else { return }
        storage.addAttribute(.paragraphStyle, value: list ? RichText.listParagraph : RichText.baseParagraph, range: range)
    }
}

struct FormatBar: View {
    let editor: EditorController
    let palette: Palette
    var showsTip = true

    var body: some View {
        HStack(spacing: 3) {
            textTool("Body", help: "Normal text (⌥⌘0)", key: "0", modifiers: [.command, .option]) { editor.heading(nil) }
            textTool("H1", help: "Heading 1 (⌥⌘1)", key: "1", modifiers: [.command, .option]) { editor.heading(0) }
            textTool("H2", help: "Heading 2 (⌥⌘2)", key: "2", modifiers: [.command, .option]) { editor.heading(1) }
            textTool("H3", help: "Heading 3 (⌥⌘3)", key: "3", modifiers: [.command, .option]) { editor.heading(2) }
            divider
            iconTool("bold", help: "Bold (⌘B)", key: "b", modifiers: .command) { editor.toggle(.boldFontMask) }
            iconTool("italic", help: "Italic (⌘I)", key: "i", modifiers: .command) { editor.toggle(.italicFontMask) }
            iconTool("underline", help: "Underline (⌘U)", key: "u", modifiers: .command) { editor.toggleUnderline() }
            divider
            iconTool("list.bullet", help: "Bulleted list (⇧⌘8)", key: "8", modifiers: [.command, .shift]) { editor.toggleList(ordered: false) }
            iconTool("list.number", help: "Numbered list (⇧⌘7)", key: "7", modifiers: [.command, .shift]) { editor.toggleList(ordered: true) }
            divider
            iconTool("chevron.left.forwardslash.chevron.right", help: "Code (⌘E)", key: "e", modifiers: .command) { editor.toggleCode() }
            Menu {
                Button("Auto-detect language") { editor.setCodeLanguage(nil) }
                Divider()
                ForEach(LanguageRegistry.all) { language in Button(language.name) { editor.setCodeLanguage(language) } }
            } label: {
                Image(systemName: "curlybraces").font(.system(size: 12, weight: .medium)).frame(width: 24, height: 24)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Language for code highlighting")
            Spacer()
            if showsTip {
                Text("Tip: type # for a heading, - for a bullet, ``` for code").font(.system(size: 9)).foregroundStyle(palette.muted)
            }
        }
        .padding(5)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(palette.border, lineWidth: 1))
    }

    private var divider: some View {
        Rectangle().fill(palette.border).frame(width: 1, height: 18).padding(.horizontal, 4)
    }

    private func textTool(_ title: String, help: String, key: KeyEquivalent, modifiers: EventModifiers, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: .semibold)).frame(minWidth: 26).padding(.vertical, 5).padding(.horizontal, 4)
        }
        .buttonStyle(.plain).foregroundStyle(palette.text).help(help).keyboardShortcut(key, modifiers: modifiers)
    }

    private func iconTool(_ symbol: String, help: String, key: KeyEquivalent, modifiers: EventModifiers, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium)).frame(width: 28, height: 24)
        }
        .buttonStyle(.plain).foregroundStyle(palette.text).help(help).keyboardShortcut(key, modifiers: modifiers)
    }
}

struct RichTextEditor: NSViewRepresentable {
    @Binding var data: Data
    var plainText: Binding<String>? = nil
    let controller: EditorController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.delegate = context.coordinator
        tv.isRichText = true
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.importsGraphics = false
        tv.textContainerInset = NSSize(width: 4, height: 6)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = true
        tv.font = RichText.bodyFont
        tv.defaultParagraphStyle = RichText.baseParagraph
        tv.typingAttributes = RichText.bodyAttributes
        tv.textStorage?.setAttributedString(RichText.decode(data))
        controller.textView = tv
        return scroll
    }

    // The editor is recreated for every topic, so the text view owns its content afterwards.
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        controller.textView = scroll.documentView as? NSTextView
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor

        init(_ parent: RichTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.controller.rehighlight()
            parent.data = RichText.encode(tv.attributedString())
            parent.plainText?.wrappedValue = tv.string
        }

        func textView(_ tv: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url = (link as? URL) ?? (link as? String).flatMap { URL(string: $0) }
            if let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
            return true
        }

        func textView(_ tv: NSTextView, doCommandBy selector: Selector) -> Bool {
            selector == #selector(NSResponder.insertNewline(_:)) ? handleNewline(tv) : false
        }

        // Typing "- ", "* ", "1. " or "# " at the start of a line turns it into a list or heading.
        func textView(_ tv: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            guard replacementString == " ", range.length == 0, let storage = tv.textStorage else { return true }
            let ns = tv.string as NSString
            let lineStart = ns.paragraphRange(for: NSRange(location: range.location, length: 0)).location
            let prefix = ns.substring(with: NSRange(location: lineStart, length: range.location - lineStart))
            let prefixRange = NSRange(location: lineStart, length: prefix.utf16.count)

            if prefix == "-" || prefix == "*" {
                EditorController.replace(in: tv, range: prefixRange, with: ListMarker.bullet)
                EditorController.style(storage, at: lineStart, list: true)
                tv.setSelectedRange(NSRange(location: lineStart + 2, length: 0))
                tv.didChangeText()
                return false
            }
            if prefix.count > 1, prefix.hasSuffix("."), let number = Int(prefix.dropLast()) {
                let marker = "\(number).\t"
                EditorController.replace(in: tv, range: prefixRange, with: marker)
                EditorController.style(storage, at: lineStart, list: true)
                tv.setSelectedRange(NSRange(location: lineStart + marker.utf16.count, length: 0))
                tv.didChangeText()
                return false
            }
            if !prefix.isEmpty, prefix.count <= 3, prefix.allSatisfy({ $0 == "#" }) {
                let font = RichText.font(heading: prefix.count - 1)
                EditorController.replace(in: tv, range: prefixRange, with: "")
                let paragraph = (tv.string as NSString).paragraphRange(for: NSRange(location: lineStart, length: 0))
                if paragraph.length > 0 { storage.addAttribute(.font, value: font, range: paragraph) }
                tv.setSelectedRange(NSRange(location: lineStart, length: 0))
                tv.typingAttributes[.font] = font
                tv.didChangeText()
                return false
            }
            return true
        }

        private func handleNewline(_ tv: NSTextView) -> Bool {
            let selection = tv.selectedRange()
            guard selection.length == 0, let storage = tv.textStorage else { return false }
            let ns = tv.string as NSString
            let paragraph = ns.paragraphRange(for: selection)
            let line = ns.substring(with: paragraph).trimmingCharacters(in: .newlines)

            let fontHere = (paragraph.length > 0 ? storage.attribute(.font, at: paragraph.location, effectiveRange: nil) : tv.typingAttributes[.font]) as? NSFont
            let lineEndLocation = paragraph.location + line.utf16.count

            if RichText.isCode(fontHere) {
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    // Return on an empty code line leaves the block.
                    if line.utf16.count > 0 {
                        EditorController.replace(in: tv, range: NSRange(location: paragraph.location, length: line.utf16.count), with: "")
                    }
                    let range = (tv.string as NSString).paragraphRange(for: NSRange(location: paragraph.location, length: 0))
                    if range.length > 0 {
                        storage.addAttribute(.font, value: RichText.bodyFont, range: range)
                        storage.removeAttribute(.backgroundColor, range: range)
                    }
                    tv.typingAttributes[.font] = RichText.bodyFont
                    tv.typingAttributes.removeValue(forKey: .backgroundColor)
                    tv.didChangeText()
                    return true
                }
                let indent = String(line.prefix { $0 == " " || $0 == "\t" })
                tv.insertText("\n" + indent, replacementRange: selection)
                return true
            }

            // Typing ``` (optionally with a language) and pressing Return starts a code block.
            let fence = line.trimmingCharacters(in: .whitespaces)
            if fence.hasPrefix("```"), selection.location == lineEndLocation {
                let tag = String(fence.dropFirst(3)).lowercased()
                parent.controller.codeLanguage = LanguageRegistry.all.first { $0.id == tag || $0.extensions.contains(tag) }
                EditorController.replace(in: tv, range: NSRange(location: paragraph.location, length: line.utf16.count), with: "")
                let emptied = (tv.string as NSString).paragraphRange(for: NSRange(location: paragraph.location, length: 0))
                if emptied.length > 0 {
                    storage.addAttribute(.font, value: RichText.codeFont, range: emptied)
                    storage.addAttribute(.backgroundColor, value: RichText.codeBackground, range: emptied)
                }
                tv.setSelectedRange(NSRange(location: paragraph.location, length: 0))
                tv.typingAttributes[.font] = RichText.codeFont
                tv.typingAttributes[.backgroundColor] = RichText.codeBackground
                tv.didChangeText()
                return true
            }

            if let markerLength = ListMarker.length(of: line) {
                if line.utf16.count == markerLength {
                    EditorController.replace(in: tv, range: NSRange(location: paragraph.location, length: markerLength), with: "")
                    EditorController.style(storage, at: paragraph.location, list: false)
                    tv.typingAttributes[.paragraphStyle] = RichText.baseParagraph
                    tv.didChangeText()
                    return true
                }
                let next = ListMarker.number(of: line).map { "\($0 + 1).\t" } ?? ListMarker.bullet
                tv.insertText("\n" + next, replacementRange: selection)
                EditorController.style(storage, at: tv.selectedRange().location, list: true)
                tv.didChangeText()
                return true
            }

            let lineEnd = paragraph.location + line.utf16.count
            if paragraph.length > 0, selection.location == lineEnd,
               RichText.headingLevel(of: storage.attribute(.font, at: paragraph.location, effectiveRange: nil) as? NSFont) != nil {
                tv.insertText("\n", replacementRange: selection)
                tv.typingAttributes[.font] = RichText.bodyFont
                return true
            }
            return false
        }
    }
}
