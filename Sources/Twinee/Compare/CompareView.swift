import SwiftUI

struct DiffColors {
    let isDark: Bool
    var removedBg: Color { Color(hex: isDark ? 0x3A1F22 : 0xFFE5E5) }
    var addedBg: Color { Color(hex: isDark ? 0x1B3326 : 0xE0F6E7) }
    var removedStrong: Color { Color(hex: isDark ? 0x7A2F36 : 0xFFB8B8) }
    var addedStrong: Color { Color(hex: isDark ? 0x2C6B45 : 0xA9E6BF) }
    var filler: Color { Color(hex: isDark ? 0x17171C : 0xEFEFEA) }
    var addedText: Color { Color(hex: isDark ? 0x6FD08C : 0x2E8B57) }
    var removedText: Color { Color(hex: isDark ? 0xFF7B85 : 0xC23B45) }
    var changedText: Color { Color(hex: isDark ? 0xF0B35A : 0xC77A1B) }
}

struct CompareView: View {
    @ObservedObject var model: CompareModel
    let palette: Palette
    let theme: ThemeMode
    let toggleTheme: () -> Void

    private var colors: DiffColors { DiffColors(isDark: palette.isDark) }
    private var syntax: SyntaxColors { SyntaxColors(isDark: palette.isDark, plain: palette.text) }

    var body: some View {
        VStack(spacing: 0) {
            AppTopBar(title: "Compare", subtitle: "Text and files", palette: palette, theme: theme, toggleTheme: toggleTheme)
            VStack(spacing: 10) {
                toolbar
                if model.mode == .diff, let result = model.result { statusRow(result) }
                if let message = model.message {
                    Text(message).font(.system(size: 10)).foregroundStyle(Color.red).frame(maxWidth: .infinity, alignment: .leading)
                }
                headers
                content
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .background(palette.background)
        .preferredColorScheme(palette.isDark ? .dark : .light)
        .onChange(of: model.mode) { newMode in if newMode == .diff { model.showDifferences() } }
        .onChange(of: model.ignoreWhitespace) { _ in model.recompareIfShowing() }
        .onChange(of: model.ignoreCase) { _ in model.recompareIfShowing() }
        .onChange(of: model.languageID) { _ in model.recompareIfShowing() }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Picker("View", selection: $model.mode) {
                ForEach(CompareModel.Mode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().frame(width: 190)

            Menu {
                languageButton("auto", "Auto-detect")
                Divider()
                languageButton(LanguageRegistry.plain.id, LanguageRegistry.plain.name)
                ForEach(LanguageRegistry.all) { languageButton($0.id, $0.name) }
            } label: {
                Label(languageLabel, systemImage: "curlybraces").font(.system(size: 11))
            }.menuStyle(.borderlessButton).fixedSize()

            Menu {
                Toggle("Ignore whitespace", isOn: $model.ignoreWhitespace)
                Toggle("Ignore case", isOn: $model.ignoreCase)
                Toggle("Show only differences", isOn: $model.differencesOnly)
            } label: {
                Label("Options", systemImage: "slider.horizontal.3").font(.system(size: 11))
            }.menuStyle(.borderlessButton).fixedSize()

            Spacer()
            Button { model.openTwoFiles() } label: { Label("Open two files…", systemImage: "doc.on.doc") }
                .buttonStyle(PillButtonStyle(palette: palette))
            Button { model.swapSides() } label: { Image(systemName: "arrow.left.arrow.right") }
                .buttonStyle(PillButtonStyle(palette: palette)).help("Swap left and right").disabled(!model.canCompare)
            Button { model.clear() } label: { Image(systemName: "xmark.bin") }
                .buttonStyle(PillButtonStyle(palette: palette)).help("Clear both sides")
            Button { model.compare() } label: { Label("Compare", systemImage: "equal.square") }
                .buttonStyle(PillButtonStyle(palette: palette, prominent: true)).disabled(!model.canCompare)
                .keyboardShortcut(.return, modifiers: .command)
        }
    }

    private var languageLabel: String {
        if model.languageID == "auto" {
            if let result = model.result { return "Auto · \(result.language.name)" }
            return "Auto-detect"
        }
        return LanguageRegistry.spec(id: model.languageID)?.name ?? "Language"
    }

    private func languageButton(_ id: String, _ name: String) -> some View {
        Button { model.languageID = id } label: {
            if model.languageID == id { Label(name, systemImage: "checkmark") } else { Text(name) }
        }
    }

    private func statusRow(_ result: CompareResult) -> some View {
        HStack(spacing: 12) {
            if result.hunks.isEmpty {
                Label("The two sides are identical", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(colors.addedText)
            } else {
                HStack(spacing: 4) {
                    Button { model.step(-1) } label: { Image(systemName: "chevron.up") }
                        .keyboardShortcut(.upArrow, modifiers: .command).help("Previous difference (⌘↑)")
                    Button { model.step(1) } label: { Image(systemName: "chevron.down") }
                        .keyboardShortcut(.downArrow, modifiers: .command).help("Next difference (⌘↓)")
                    Text("Difference \(model.currentHunk + 1) of \(result.hunks.count)").font(.system(size: 11, weight: .medium))
                }.buttonStyle(.bordered).controlSize(.small)
                HStack(spacing: 10) {
                    Text("+\(result.added) added").foregroundStyle(colors.addedText)
                    Text("−\(result.removed) removed").foregroundStyle(colors.removedText)
                    Text("~\(result.changed) changed").foregroundStyle(colors.changedText)
                }.font(.system(size: 10, weight: .medium))
            }
            Spacer()
            if model.isComparing { ProgressView().controlSize(.small) }
        }
    }

    // MARK: Pane headers

    private var headers: some View {
        HStack(spacing: model.mode == .diff ? 0 : 10) {
            paneHeader(isLeft: true)
            if model.mode == .diff { Spacer().frame(width: 44) }
            paneHeader(isLeft: false)
            if model.mode == .diff { Spacer().frame(width: 12) }
        }
    }

    private func paneHeader(isLeft: Bool) -> some View {
        let side = isLeft ? model.left : model.right
        return HStack(spacing: 8) {
            Image(systemName: side.url == nil ? "doc.plaintext" : "doc.text").foregroundStyle(palette.accent)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(model.title(isLeft: isLeft)).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    if side.isModified { Circle().fill(Color.orange).frame(width: 6, height: 6).help("Unsaved changes") }
                }
                Text(side.url?.deletingLastPathComponent().path ?? "Pasted or typed text").font(.system(size: 9)).foregroundStyle(palette.muted)
                    .lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: 4)
            if side.url != nil {
                Button { model.reload(isLeft: isLeft) } label: { Image(systemName: "arrow.clockwise") }.help("Reload from disk")
            }
            Button { model.save(isLeft: isLeft) } label: { Image(systemName: "square.and.arrow.down") }
                .help(side.url == nil ? "Save as…" : "Save file")
                .disabled(side.text.isEmpty || (side.url != nil && !side.isModified))
            Button { model.openFile(isLeft: isLeft) } label: { Text("Open…") }
        }
        .buttonStyle(.borderless).font(.system(size: 10))
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border, lineWidth: 1))
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch model.mode {
        case .input:
            HStack(spacing: 10) {
                inputPane(isLeft: true)
                inputPane(isLeft: false)
            }
        case .diff:
            if let result = model.result {
                diffView(result)
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Comparing…").font(.system(size: 11)).foregroundStyle(palette.muted)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func inputPane(isLeft: Bool) -> some View {
        let text = isLeft ? model.left.text : model.right.text
        return CodeEditor(text: isLeft ? $model.left.text : $model.right.text) { model.handleDrop($0, isLeft: isLeft) }
            .padding(6)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.border, lineWidth: 1))
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Paste or type text here, or drop a file onto this pane")
                        .font(.system(size: 11)).foregroundStyle(palette.muted).padding(16).allowsHitTesting(false)
                }
            }
    }

    private func diffView(_ result: CompareResult) -> some View {
        let rows = result.displayRows(collapsed: model.differencesOnly)
        return HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { item in
                            switch item {
                            case .row(let row): rowView(row, result).id(row.id)
                            case .gap(let id, let count): gapView(count).id(id)
                            }
                        }
                    }
                }
                .onChange(of: model.jump) { target in
                    if let target { withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(target.rowID, anchor: .center) } }
                }
                .onAppear {
                    DispatchQueue.main.async {
                        if let target = model.jump { proxy.scrollTo(target.rowID, anchor: .center) }
                    }
                }
            }
            overview(result)
        }
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func rowView(_ row: DiffRow, _ result: CompareResult) -> some View {
        let isCurrent = row.hunk != nil && row.hunk == model.currentHunk
        return HStack(spacing: 0) {
            cell(row, result, left: true)
            centerColumn(row, result)
            cell(row, result, left: false)
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .leading) {
            if isCurrent { Rectangle().fill(palette.accent).frame(width: 3) }
        }
    }

    private func cell(_ row: DiffRow, _ result: CompareResult, left: Bool) -> some View {
        let index = left ? row.leftIndex : row.rightIndex
        let background: Color
        switch row.kind {
        case .equal: background = .clear
        case .removed: background = left ? colors.removedBg : colors.filler
        case .added: background = left ? colors.filler : colors.addedBg
        case .changed: background = left ? colors.removedBg : colors.addedBg
        }
        return HStack(alignment: .top, spacing: 0) {
            Text(index.map { String($0 + 1) } ?? "")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.muted)
                .frame(width: 40, alignment: .trailing).padding(.trailing, 6).padding(.vertical, 2)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(palette.sidebar.opacity(0.6))
            if index != nil {
                Text(result.attributed(left: left, row: row, colors: syntax, intraBackground: left ? colors.removedStrong : colors.addedStrong))
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6).padding(.vertical, 2)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background)
    }

    private func centerColumn(_ row: DiffRow, _ result: CompareResult) -> some View {
        let hunkIndex = row.hunk
        let isFirst = hunkIndex.map { result.hunks[$0].firstRow == row.id } ?? false
        return HStack(spacing: 2) {
            if isFirst, let hunkIndex {
                Button { model.copyHunk(hunkIndex, toRight: false) } label: { Image(systemName: "arrow.left") }
                    .help("Copy this change to the left side")
                Button { model.copyHunk(hunkIndex, toRight: true) } label: { Image(systemName: "arrow.right") }
                    .help("Copy this change to the right side")
            }
        }
        .buttonStyle(.plain).font(.system(size: 9, weight: .bold)).foregroundStyle(palette.accent)
        .frame(width: 44).frame(maxHeight: .infinity, alignment: .top).padding(.top, 4)
        .background(palette.sidebar.opacity(0.6))
    }

    private func gapView(_ count: Int) -> some View {
        Text("⋯ \(count) identical \(count == 1 ? "line" : "lines")")
            .font(.system(size: 10)).foregroundStyle(palette.muted)
            .frame(maxWidth: .infinity).padding(.vertical, 5)
            .background(palette.border.opacity(0.35))
    }

    private func hunkColor(_ hunk: Hunk) -> Color {
        if hunk.leftCount == 0 { return colors.addedText }
        if hunk.rightCount == 0 { return colors.removedText }
        return colors.changedText
    }

    private func overview(_ result: CompareResult) -> some View {
        GeometryReader { geometry in
            let total = CGFloat(max(1, result.rows.count))
            ZStack(alignment: .topLeading) {
                Rectangle().fill(palette.border.opacity(0.35))
                ForEach(result.hunks) { hunk in
                    Rectangle()
                        .fill(hunkColor(hunk))
                        .frame(height: max(3, geometry.size.height * CGFloat(hunk.rowCount) / total))
                        .offset(y: geometry.size.height * CGFloat(hunk.firstRow) / total)
                        .opacity(hunk.id == model.currentHunk ? 1 : 0.55)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                let row = Int(value.location.y / max(1, geometry.size.height) * total)
                if let nearest = result.hunks.indices.min(by: { abs(result.hunks[$0].firstRow - row) < abs(result.hunks[$1].firstRow - row) }) {
                    model.goToHunk(nearest)
                }
            })
        }
        .frame(width: 12)
    }
}
