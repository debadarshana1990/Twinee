import SwiftUI
import AppKit

enum PanelKind: String, CaseIterable, Identifiable {
    case info = "Info", note = "Note", success = "Success", warning = "Warning", error = "Error"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .info: return "ℹ️"
        case .note: return "📝"
        case .success: return "✅"
        case .warning: return "⚠️"
        case .error: return "⛔️"
        }
    }
    var color: NSColor {
        switch self {
        case .info: return NSColor(srgbRed: 0.22, green: 0.55, blue: 0.95, alpha: 0.18)
        case .note: return NSColor(srgbRed: 0.60, green: 0.40, blue: 0.95, alpha: 0.18)
        case .success: return NSColor(srgbRed: 0.15, green: 0.70, blue: 0.45, alpha: 0.18)
        case .warning: return NSColor(srgbRed: 0.95, green: 0.65, blue: 0.10, alpha: 0.22)
        case .error: return NSColor(srgbRed: 0.90, green: 0.30, blue: 0.30, alpha: 0.18)
        }
    }
}

enum StatusKind: String, CaseIterable, Identifiable {
    case todo = "TO DO", inProgress = "IN PROGRESS", done = "DONE", blocked = "BLOCKED", review = "IN REVIEW"

    var id: String { rawValue }
    var color: NSColor {
        switch self {
        case .todo: return NSColor(srgbRed: 0.45, green: 0.48, blue: 0.55, alpha: 1)
        case .inProgress: return NSColor(srgbRed: 0.18, green: 0.45, blue: 0.95, alpha: 1)
        case .done: return NSColor(srgbRed: 0.12, green: 0.62, blue: 0.40, alpha: 1)
        case .blocked: return NSColor(srgbRed: 0.88, green: 0.28, blue: 0.28, alpha: 1)
        case .review: return NSColor(srgbRed: 0.90, green: 0.55, blue: 0.10, alpha: 1)
        }
    }
}

struct OutlineItem: Identifiable, Equatable {
    let id: Int
    let title: String
    let level: Int
}

extension EditorController {
    func insertPanel(_ kind: PanelKind) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let ns = tv.string as NSString
        var paragraph = ns.paragraphRange(for: tv.selectedRange())
        if paragraph.length == 0 || ns.substring(with: paragraph) == "\n" {
            let insertAt = paragraph.location
            let text = "\(kind.icon)  Write here…"
            guard tv.shouldChangeText(in: NSRange(location: insertAt, length: 0), replacementString: text) else { return }
            storage.replaceCharacters(in: NSRange(location: insertAt, length: 0), with: NSAttributedString(string: text, attributes: RichText.bodyAttributes))
            tv.didChangeText()
            paragraph = (tv.string as NSString).paragraphRange(for: NSRange(location: insertAt, length: 0))
        }
        var content = paragraph
        if content.length > 0, (tv.string as NSString).character(at: NSMaxRange(content) - 1) == 10 { content.length -= 1 }
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        style.paragraphSpacingBefore = 6
        style.paragraphSpacing = 6
        style.firstLineHeadIndent = 8
        style.headIndent = 8
        guard tv.shouldChangeText(in: paragraph, replacementString: nil) else { return }
        storage.beginEditing()
        storage.addAttribute(.backgroundColor, value: kind.color, range: content)
        storage.addAttribute(.paragraphStyle, value: style, range: paragraph)
        storage.endEditing()
        let existing = (tv.string as NSString).substring(with: content)
        if !PanelKind.allCases.contains(where: { existing.hasPrefix($0.icon) }) {
            storage.replaceCharacters(in: NSRange(location: content.location, length: 0), with: NSAttributedString(string: kind.icon + "  ", attributes: [.font: RichText.bodyFont, .backgroundColor: kind.color, .paragraphStyle: style, .foregroundColor: NSColor.labelColor]))
        }
        tv.didChangeText()
        tv.window?.makeFirstResponder(tv)
    }

    func insertStatus(_ kind: StatusKind) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = tv.selectedRange()
        let tag = NSAttributedString(string: " \(kind.rawValue) ", attributes: [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .heavy),
            .foregroundColor: NSColor.white,
            .backgroundColor: kind.color,
            .paragraphStyle: RichText.baseParagraph,
        ])
        guard tv.shouldChangeText(in: range, replacementString: tag.string) else { return }
        let combined = NSMutableAttributedString(attributedString: tag)
        combined.append(NSAttributedString(string: " ", attributes: RichText.bodyAttributes))
        storage.replaceCharacters(in: range, with: combined)
        tv.setSelectedRange(NSRange(location: range.location + combined.length, length: 0))
        tv.typingAttributes = RichText.bodyAttributes
        tv.didChangeText()
        tv.window?.makeFirstResponder(tv)
    }

    func insertDivider() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = tv.selectedRange()
        let line = NSAttributedString(string: "\n" + String(repeating: "─", count: 48) + "\n", attributes: [.font: RichText.bodyFont, .foregroundColor: NSColor.tertiaryLabelColor, .paragraphStyle: RichText.baseParagraph])
        guard tv.shouldChangeText(in: range, replacementString: line.string) else { return }
        storage.replaceCharacters(in: range, with: line)
        tv.setSelectedRange(NSRange(location: range.location + line.length, length: 0))
        tv.typingAttributes = RichText.bodyAttributes
        tv.didChangeText()
        tv.window?.makeFirstResponder(tv)
    }

    func outline() -> [OutlineItem] {
        guard let tv = textView, let storage = tv.textStorage else { return [] }
        let ns = tv.string as NSString
        var items: [OutlineItem] = []
        var location = 0
        while location < ns.length {
            let paragraph = ns.paragraphRange(for: NSRange(location: location, length: 0))
            if let level = RichText.headingLevel(of: storage.attribute(.font, at: paragraph.location, effectiveRange: nil) as? NSFont) {
                let title = ns.substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty { items.append(OutlineItem(id: paragraph.location, title: title, level: level)) }
            }
            location = NSMaxRange(paragraph)
            if paragraph.length == 0 { break }
        }
        return items
    }

    func reveal(_ location: Int) {
        guard let tv = textView, location <= (tv.string as NSString).length else { return }
        let range = (tv.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
        tv.setSelectedRange(NSRange(location: range.location, length: 0))
        if let lm = tv.layoutManager, let container = tv.textContainer, let scroll = tv.enclosingScrollView {
            let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = lm.boundingRect(forGlyphRange: glyphs, in: container)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, rect.minY - 12)))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        tv.window?.makeFirstResponder(tv)
    }
}

struct InsertMenu: View {
    let editor: EditorController
    let palette: Palette

    var body: some View {
        Menu {
            Section("Panels") {
                ForEach(PanelKind.allCases) { kind in Button("\(kind.icon) \(kind.rawValue) panel") { editor.insertPanel(kind) } }
            }
            Section("Status") {
                ForEach(StatusKind.allCases) { kind in Button(kind.rawValue) { editor.insertStatus(kind) } }
            }
            Divider()
            Button("Divider") { editor.insertDivider() }
        } label: {
            Label("Insert", systemImage: "plus.rectangle.on.rectangle").font(.system(size: 11, weight: .semibold))
        }
        .menuStyle(.borderlessButton).fixedSize().foregroundStyle(palette.accent)
        .help("Insert a panel, status tag or divider")
    }
}

struct OutlineRail: View {
    let items: [OutlineItem]
    let palette: Palette
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("ON THIS PAGE").font(.system(size: 9, weight: .bold)).tracking(1.1).foregroundStyle(palette.muted).padding(.bottom, 6)
            ForEach(items) { item in
                Button { onSelect(item.id) } label: {
                    Text(item.title).font(.system(size: 11, weight: item.level == 0 ? .semibold : .regular)).lineLimit(2).multilineTextAlignment(.leading)
                        .foregroundStyle(item.level == 0 ? palette.text : palette.muted)
                        .padding(.leading, CGFloat(item.level) * 12).padding(.vertical, 3)
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.leading, 14).padding(.trailing, 10).padding(.top, 26)
        .overlay(alignment: .leading) { Rectangle().fill(Brand.gradient).frame(width: 2) }
    }
}

struct LabelChips: View {
    @Binding var labels: [String]
    let palette: Palette
    @State private var newLabel = ""

    private func tint(_ label: String) -> Color { ProjectPalette.color(abs(label.hashValue) % 5) }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "tag").font(.system(size: 10)).foregroundStyle(palette.muted)
            ForEach(labels, id: \.self) { label in
                HStack(spacing: 4) {
                    Text(label).font(.system(size: 10, weight: .semibold))
                    Button { labels.removeAll { $0 == label } } label: { Image(systemName: "xmark").font(.system(size: 7, weight: .bold)) }.buttonStyle(.plain)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .foregroundStyle(tint(label)).background(tint(label).opacity(0.15), in: Capsule())
            }
            TextField("Add label", text: $newLabel).textFieldStyle(.plain).font(.system(size: 10)).frame(width: 80)
                .onSubmit {
                    let value = newLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: " ", with: "-")
                    if !value.isEmpty, !labels.contains(value) { labels.append(value) }
                    newLabel = ""
                }
        }
    }
}
