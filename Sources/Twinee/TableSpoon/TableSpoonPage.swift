import SwiftUI
import AppKit

extension RichText {
    // Turns Markdown (used for starter content and for notes from earlier versions) into a rich document.
    static func document(fromMarkdown markdown: String) -> NSAttributedString {
        let doc = NSMutableAttributedString()
        var inFence = false
        for raw in markdown.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            var attrs = bodyAttributes
            var line = raw
            if trimmed.hasPrefix("```") { inFence.toggle(); continue }
            if inFence {
                attrs[.font] = codeFont
            } else if let hashes = trimmed.prefix(while: { $0 == "#" }).count as Int?, hashes > 0, hashes <= 3, trimmed.dropFirst(hashes).hasPrefix(" ") {
                line = String(trimmed.dropFirst(hashes + 1))
                attrs[.font] = font(heading: hashes - 1)
            } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                line = "☑ " + trimmed.dropFirst(6)
            } else if trimmed.hasPrefix("- [ ] ") || trimmed == "- [ ]" {
                line = "☐ " + trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                line = "• " + trimmed.dropFirst(2)
            } else if trimmed.hasPrefix("> ") {
                line = String(trimmed.dropFirst(2))
                attrs[.font] = NSFontManager.shared.convert(bodyFont, toHaveTrait: .italicFontMask)
            }
            if !inFence { line = line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "") }
            doc.append(NSAttributedString(string: line + "\n", attributes: attrs))
        }
        return doc
    }
}

// A Confluence-style page: formatting bar, rich text, panels and status tags, and an "On this page" outline.
struct TSPageView: View {
    @ObservedObject var model: TableSpoonModel
    let palette: Palette
    @StateObject private var editor = EditorController()
    @State private var data: Data
    @State private var plain: String
    @State private var outline: [OutlineItem] = []
    @AppStorage("twinee.pageFullWidth") private var fullWidth = false

    init(model: TableSpoonModel, palette: Palette) {
        self.model = model
        self.palette = palette
        _data = State(initialValue: model.currentPageData)
        _plain = State(initialValue: model.text)
    }

    private var wordCount: Int { plain.split { $0.isWhitespace || $0.isNewline }.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    FormatBar(editor: editor, palette: palette, showsTip: false, trailing: { InsertMenu(editor: editor, palette: palette) })
                }
                Button { fullWidth.toggle() } label: { Image(systemName: fullWidth ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right").font(.system(size: 11)).foregroundStyle(palette.muted).frame(width: 26, height: 26) }
                    .buttonStyle(.plain).help(fullWidth ? "Use a readable page width" : "Use the full width")
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
            .background(palette.surface)
            .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }
            HStack(spacing: 0) {
                paper
                    .frame(maxWidth: fullWidth ? .infinity : 900, maxHeight: .infinity)
                    .frame(maxWidth: .infinity)
                if !outline.isEmpty {
                    OutlineRail(items: outline, palette: palette) { editor.reveal($0) }.frame(width: 180)
                }
            }
            .background(palette.background)
        }
        .onChange(of: data) { model.editedPage($0, plain: plain) }
        .onChange(of: plain) { _ in outline = editor.outline() }
        .onAppear { DispatchQueue.main.async { outline = editor.outline() } }
    }

    private var paper: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(wordCount) words").font(.system(size: 10)).foregroundStyle(palette.muted)
            Rectangle().fill(palette.border).frame(height: 1)
            RichTextEditor(data: $data, plainText: $plain, controller: editor)
        }
        .padding(.horizontal, 40).padding(.top, 22).padding(.bottom, 12)
        .background(palette.surface)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(palette.border, lineWidth: 1))
        .shadow(color: .black.opacity(palette.isDark ? 0.4 : 0.07), radius: 10, y: 3)
        .padding(.horizontal, 24).padding(.vertical, 16)
    }
}
