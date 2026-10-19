import SwiftUI
import AppKit

// Editable text view with live syntax highlighting (code files) or light Markdown styling (notes).
struct TSCodeEditor: NSViewRepresentable {
    let text: String
    let fileName: String
    let isCode: Bool
    let jump: TSJump?
    let onChange: (String) -> Void
    let onDefinition: (String) -> Void
    let onUsages: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TSCodeEditor
        var handledJump: UUID?
        let spec: LanguageSpec?

        init(_ parent: TSCodeEditor) {
            self.parent = parent
            spec = parent.isCode ? LanguageRegistry.detect(fileNames: [parent.fileName], samples: []) : nil
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.onChange(tv.string)
            TSCodeEditor.style(tv, spec: spec, isCode: parent.isCode)
        }

        func textView(_ tv: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard parent.isCode else { return false }
            if selector == #selector(NSResponder.insertTab(_:)) {
                tv.insertText("    ", replacementRange: tv.selectedRange())
                return true
            }
            if selector == #selector(NSResponder.insertNewline(_:)) {
                let ns = tv.string as NSString
                let location = tv.selectedRange().location
                let lineRange = ns.lineRange(for: NSRange(location: location, length: 0))
                var indent = String(ns.substring(with: lineRange).prefix { $0 == " " || $0 == "\t" })
                let before = ns.substring(with: NSRange(location: lineRange.location, length: location - lineRange.location)).trimmingCharacters(in: .whitespaces)
                if before.hasSuffix("{") || before.hasSuffix(":") { indent += "    " }
                tv.insertText("\n" + indent, replacementRange: tv.selectedRange())
                return true
            }
            return false
        }
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll: NSScrollView
        let tv: NSTextView
        if isCode {
            scroll = NSScrollView()
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = true
            let code = CodeTextView(frame: .zero)
            code.onDefinition = onDefinition
            code.onUsages = onUsages
            code.textContainerInset = NSSize(width: 8, height: 8)
            code.minSize = .zero
            code.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            code.isVerticallyResizable = true
            code.isHorizontallyResizable = true
            code.autoresizingMask = []
            code.textContainer?.widthTracksTextView = false
            code.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            scroll.documentView = code
            scroll.hasVerticalRuler = true
            scroll.verticalRulerView = LineNumberRuler(scrollView: scroll, textView: code)
            scroll.rulersVisible = true
            tv = code
        } else {
            scroll = NSTextView.scrollableTextView()
            tv = scroll.documentView as! NSTextView
            tv.textContainerInset = NSSize(width: 26, height: 22)
        }
        scroll.drawsBackground = false
        tv.drawsBackground = false
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.insertionPointColor = .controlAccentColor
        tv.delegate = context.coordinator
        tv.string = text
        Self.style(tv, spec: context.coordinator.spec, isCode: isCode)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        if let code = tv as? CodeTextView {
            code.onDefinition = onDefinition
            code.onUsages = onUsages
        }
        if tv.string != text {
            tv.string = text
            Self.style(tv, spec: context.coordinator.spec, isCode: isCode)
        }
        if let jump, jump.token != context.coordinator.handledJump {
            context.coordinator.handledJump = jump.token
            DispatchQueue.main.async {
                let starts = (tv as? CodeTextView)?.lineStarts ?? [0]
                let ns = tv.string as NSString
                let location = min(starts[min(max(0, jump.line), starts.count - 1)], ns.length)
                let lineRange = ns.lineRange(for: NSRange(location: location, length: 0))
                tv.setSelectedRange(NSRange(location: location, length: 0))
                tv.scrollRangeToVisible(lineRange)
                tv.showFindIndicator(for: lineRange)
                tv.window?.makeFirstResponder(tv)
            }
        }
    }

    static func style(_ tv: NSTextView, spec: LanguageSpec?, isCode: Bool) {
        guard let storage = tv.textStorage else { return }
        let source = tv.string
        let length = (source as NSString).length
        let mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let font = isCode ? mono : NSFont.systemFont(ofSize: 14)
        let paragraph = NSMutableParagraphStyle()
        if isCode {
            paragraph.defaultTabInterval = ("    " as NSString).size(withAttributes: [.font: mono]).width
            paragraph.tabStops = []
        } else {
            paragraph.lineSpacing = 4
        }
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        let lines = source.components(separatedBy: "\n")
        let spans: [[SyntaxSpan]]? = isCode && length < 600_000 ? spec.map { SyntaxHighlighter.highlight(lines: lines, spec: $0) } : nil
        let bold = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
        var starts: [Int] = []
        var offset = 0
        var inFence = false

        storage.beginEditing()
        storage.setAttributes(base, range: NSRange(location: 0, length: length))
        for (index, line) in lines.enumerated() {
            starts.append(offset)
            let lineLength = (line as NSString).length
            let range = NSRange(location: offset, length: lineLength)
            if let spans {
                for span in spans[index] where span.kind != .plain && offset + span.start + span.length <= length {
                    let r = NSRange(location: offset + span.start, length: span.length)
                    storage.addAttribute(.foregroundColor, value: SyntaxColors.nsColor(span.kind), range: r)
                    if span.kind == .keyword { storage.addAttribute(.font, value: bold, range: r) }
                }
            } else if !isCode, lineLength > 0 {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("```") {
                    inFence.toggle()
                    storage.addAttributes([.font: mono, .foregroundColor: NSColor.systemTeal], range: range)
                } else if inFence {
                    storage.addAttributes([.font: mono, .foregroundColor: NSColor.systemTeal], range: range)
                } else if trimmed.hasPrefix("#") {
                    let level = trimmed.prefix { $0 == "#" }.count
                    let size: CGFloat = level == 1 ? 24 : level == 2 ? 19 : 16
                    storage.addAttributes([.font: NSFont.systemFont(ofSize: size, weight: .bold), .foregroundColor: NSColor.systemPurple], range: range)
                } else if trimmed.hasPrefix(">") {
                    storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
                } else if let marker = line.range(of: #"^\s*[-*] (\[[ xX]\] )?"#, options: .regularExpression) {
                    let r = NSRange(marker, in: line)
                    storage.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: NSRange(location: r.location + offset, length: r.length))
                }
            }
            offset += lineLength + 1
        }
        storage.endEditing()
        tv.typingAttributes = base
        if let code = tv as? CodeTextView {
            code.lineStarts = starts
            (tv.enclosingScrollView?.verticalRulerView as? LineNumberRuler)?.lineStarts = starts
        }
    }
}
