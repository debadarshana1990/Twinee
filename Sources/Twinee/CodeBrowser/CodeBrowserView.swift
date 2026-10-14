import SwiftUI

struct CodeBrowserView: View {
    @ObservedObject var model: CodeBrowserModel
    @ObservedObject private var tools = DevToolsStore.shared
    let palette: Palette
    let theme: ThemeMode
    let toggleTheme: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            AppTopBar(title: "Code Browser", subtitle: model.root?.lastPathComponent ?? "C, C++ and Python", palette: palette, theme: theme, toggleTheme: toggleTheme)
            if model.root == nil {
                welcome
            } else {
                HStack(spacing: 0) {
                    sidebar.frame(width: 262)
                    Rectangle().fill(palette.border).frame(width: 1)
                    main
                }
            }
        }
        .background(palette.background)
        .preferredColorScheme(palette.isDark ? .dark : .light)
        .onAppear {
            if model.root == nil, let path = tools.codeFolder, FileManager.default.fileExists(atPath: path) {
                model.load(URL(fileURLWithPath: path))
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: 12) {
            Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 30, weight: .light)).foregroundStyle(palette.accent)
            Text("Browse a source tree").font(.system(size: 18, weight: .semibold, design: .rounded))
            Text("Open a folder to see its C, C++ and Python files with syntax highlighting,\nan outline of every function and class, and project-wide go to definition.")
                .font(.system(size: 11)).foregroundStyle(palette.muted).multilineTextAlignment(.center)
            Button { model.chooseFolder() } label: { Label("Open folder…", systemImage: "folder") }
                .buttonStyle(PillButtonStyle(palette: palette, prominent: true)).padding(.top, 4)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 8) {
            Picker("Browse", selection: $model.tab) {
                ForEach(CodeBrowserModel.Tab.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(palette.muted)
                TextField(model.tab == .files ? "Filter files" : "Filter symbols", text: $model.query).textFieldStyle(.plain).font(.system(size: 11))
                if model.tab != .files {
                    Menu {
                        Button("All kinds") { model.kindFilter = nil }
                        Divider()
                        ForEach(SymbolKind.allCases) { kind in Button(kind.label) { model.kindFilter = kind } }
                    } label: {
                        Image(systemName: model.kindFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }.menuStyle(.borderlessButton).fixedSize().help("Filter by kind")
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.border, lineWidth: 1))

            Group {
                switch model.tab {
                case .files: filesList
                case .outline: symbolList(model.filteredSymbols(model.outline), showFile: false, empty: "No symbols in this file")
                case .symbols: symbolList(model.filteredSymbols(model.symbols), showFile: true, empty: model.isIndexing ? "Indexing…" : "No matching symbols")
                }
            }.frame(maxHeight: .infinity)

            HStack(spacing: 6) {
                if model.isIndexing { ProgressView().controlSize(.mini) }
                Text("\(model.fileCount) files · \(model.symbols.count) symbols").font(.system(size: 9)).foregroundStyle(palette.muted)
                Spacer()
                Button { model.chooseFolder() } label: { Image(systemName: "folder") }.buttonStyle(.plain).help("Open another folder")
                    .foregroundStyle(palette.muted)
            }
        }
        .padding(10)
        .background(palette.sidebar)
    }

    @ViewBuilder
    private var filesList: some View {
        if model.query.isEmpty {
            List(model.tree, children: \.children, selection: Binding(
                get: { model.currentPath },
                set: { if let path = $0, model.isFile(path) { model.open(path: path) } }
            )) { node in
                Label(node.name, systemImage: node.children == nil ? "doc.text" : "folder")
                    .font(.system(size: 11)).lineLimit(1)
            }
            .listStyle(.sidebar).scrollContentBackground(.hidden)
        } else {
            let matches = model.filteredFiles()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(matches.prefix(400), id: \.self) { path in
                        Button { model.open(path: path) } label: {
                            Text(model.relativePath(path)).font(.system(size: 11)).lineLimit(1).truncationMode(.head)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(model.currentPath == path ? palette.selected : .clear, in: RoundedRectangle(cornerRadius: 5))
                        }.buttonStyle(.plain)
                    }
                    if matches.isEmpty { Text("No matching files").font(.system(size: 10)).foregroundStyle(palette.muted).padding(10) }
                }
            }
        }
    }

    private func symbolList(_ list: [CodeSymbol], showFile: Bool, empty: String) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(list) { symbol in
                    Button { model.open(symbol) } label: {
                        HStack(spacing: 7) {
                            Image(systemName: symbol.kind.symbol).font(.system(size: 12)).foregroundStyle(symbol.kind.tint).frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(symbol.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                Text(secondary(symbol, showFile: showFile)).font(.system(size: 9)).foregroundStyle(palette.muted).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                if list.isEmpty { Text(empty).font(.system(size: 10)).foregroundStyle(palette.muted).padding(10) }
            }
        }
    }

    private func secondary(_ symbol: CodeSymbol, showFile: Bool) -> String {
        var parts: [String] = [symbol.kind.label]
        if let container = symbol.container { parts.append(container) }
        parts.append(showFile ? "\((symbol.path as NSString).lastPathComponent):\(symbol.line + 1)" : "line \(symbol.line + 1)")
        return parts.joined(separator: " · ")
    }

    // MARK: Main

    private var main: some View {
        VStack(spacing: 0) {
            if let path = model.currentPath {
                fileHeader(path)
                CodeViewer(text: model.text, language: model.language, jump: model.jump,
                           onDefinition: { model.goToDefinition(of: $0) },
                           onUsages: { model.findUsages(of: $0) })
                    .background(palette.surface)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass").font(.system(size: 26, weight: .light)).foregroundStyle(palette.accent)
                    Text(model.isIndexing ? "Reading the source tree…" : "Choose a file to start reading").font(.system(size: 13)).foregroundStyle(palette.muted)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let message = model.message {
                Text(message).font(.system(size: 10)).foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 6)
            }
            if !model.hits.isEmpty || model.isSearching { hitsPanel }
        }
    }

    private func fileHeader(_ path: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text").foregroundStyle(palette.accent)
            Text(model.relativePath(path)).font(.system(size: 11, weight: .semibold)).lineLimit(1).truncationMode(.head)
            Text(model.language.name).font(.system(size: 9, weight: .semibold)).foregroundStyle(palette.accent)
                .padding(.horizontal, 7).padding(.vertical, 2).background(palette.selected, in: Capsule())
            Spacer()
            Text("⌘-click a name to jump to its definition").font(.system(size: 9)).foregroundStyle(palette.muted)
            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) } label: { Image(systemName: "magnifyingglass.circle") }
                .buttonStyle(.plain).help("Reveal in Finder").foregroundStyle(palette.muted)
        }
        .padding(.horizontal, 14).frame(height: 38)
        .background(palette.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }
    }

    private var hitsPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.hitsTitle).font(.system(size: 11, weight: .semibold))
                if model.isSearching { ProgressView().controlSize(.mini) }
                Spacer()
                Button { model.hits = [] } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(palette.muted)
            }
            .padding(.horizontal, 14).frame(height: 32)
            .background(palette.sidebar)
            .overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 1) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.hits) { hit in
                        Button { model.open(hit) } label: {
                            HStack(spacing: 8) {
                                if let kind = hit.kind { Image(systemName: kind.symbol).foregroundStyle(kind.tint).frame(width: 16) }
                                Text("\(model.relativePath(hit.path)):\(hit.line + 1)").font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.accent)
                                Text(hit.text).font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.muted).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 160)
            .background(palette.surface)
        }
    }
}
