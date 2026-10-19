import SwiftUI

struct CodeBrowserView: View {
    @ObservedObject var model: CodeBrowserModel
    @ObservedObject private var tools = DevToolsStore.shared
    let palette: Palette
    let theme: ThemeMode
    let toggleTheme: () -> Void
    @AppStorage("twinee.codeSidebarWidth") private var sidebarWidth = 262.0
    @State private var showingGitSheet = false
    @State private var noteDraft: CodeNote?
    @State private var showPreview = false

    var body: some View {
        VStack(spacing: 0) {
            AppTopBar(title: "Code Browser", subtitle: model.root == nil ? "C, C++ and Python" : model.displayName, palette: palette, theme: theme, toggleTheme: toggleTheme)
            if model.root == nil {
                welcome
            } else {
                HStack(spacing: 0) {
                    sidebar.frame(width: sidebarWidth)
                    ResizeDivider(width: $sidebarWidth, range: 200...560, palette: palette)
                    main
                }
            }
        }
        .background(palette.background)
        .preferredColorScheme(palette.isDark ? .dark : .light)
        .onAppear {
            guard model.root == nil else { return }
            if tools.codeRemote != nil {
                model.restoreRemoteIfNeeded()
            } else if let path = tools.codeFolder, FileManager.default.fileExists(atPath: path) {
                model.load(URL(fileURLWithPath: path))
            }
        }
        .sheet(isPresented: $showingGitSheet) { GitBrowseSheet(model: model, palette: palette, isPresented: $showingGitSheet) }
        .sheet(item: $noteDraft) { draft in
            NoteEditor(note: draft, palette: palette,
                       onSave: { model.saveNote($0); noteDraft = nil },
                       onDelete: { model.deleteNote($0); noteDraft = nil },
                       onCancel: { noteDraft = nil })
        }
    }

    private var welcome: some View {
        VStack(spacing: 12) {
            Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 30, weight: .light)).foregroundStyle(palette.accent)
            Text("Browse a source tree").font(.system(size: 18, weight: .semibold, design: .rounded))
            Text("Paste a Git URL, pick a branch, and read its code — or open a folder — to see its C, C++ and Python files with syntax highlighting,\nan outline of every function and class, and project-wide go to definition.")
                .font(.system(size: 11)).foregroundStyle(palette.muted).multilineTextAlignment(.center)
            GitBrowseSheet(model: model, palette: palette, isPresented: .constant(true), inline: true)
                .padding(.top, 6)
            Text("or").font(.system(size: 10)).foregroundStyle(palette.muted)
            Button { model.chooseFolder() } label: { Label("Open a local folder…", systemImage: "folder") }
                .buttonStyle(PillButtonStyle(palette: palette))
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
                TextField(model.tab == .files ? "Filter files" : model.tab == .notes ? "Filter notes" : "Filter symbols", text: $model.query).textFieldStyle(.plain).font(.system(size: 11))
                if model.tab == .outline || model.tab == .symbols {
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
                case .notes: notesList
                }
            }.frame(maxHeight: .infinity)

            HStack(spacing: 6) {
                if model.isIndexing { ProgressView().controlSize(.mini) }
                Text("\(model.fileCount) files · \(model.symbols.count) symbols").font(.system(size: 9)).foregroundStyle(palette.muted)
                Spacer()
                Button { showingGitSheet = true } label: { Image(systemName: "arrow.triangle.branch") }.buttonStyle(.plain).help(model.remote == nil ? "Open from Git" : "Switch branch or repository")
                    .foregroundStyle(model.remote == nil ? palette.muted : palette.accent)
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

    private var notesList: some View {
        let needle = model.query.trimmingCharacters(in: .whitespaces)
        let list = model.notes.filter { needle.isEmpty || $0.text.localizedCaseInsensitiveContains(needle) || $0.path.localizedCaseInsensitiveContains(needle) }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(list) { note in
                    Button { model.open(note) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Image(systemName: "note.text").font(.system(size: 10)).foregroundStyle(Color.orange)
                                Text("\(note.path)\(note.line.map { ":\($0 + 1)" } ?? "")").font(.system(size: 10, weight: .medium)).lineLimit(1).truncationMode(.head)
                                if let branch = note.branch, branch != model.remote?.branch {
                                    Text(branch).font(.system(size: 8)).foregroundStyle(palette.muted)
                                }
                            }
                            Text(note.text).font(.system(size: 10)).foregroundStyle(palette.muted).lineLimit(3).multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 7).padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    .contextMenu {
                        Button("Edit note…") { noteDraft = note }
                        Button("Delete note", role: .destructive) { model.deleteNote(note.id) }
                    }
                }
                if list.isEmpty {
                    Text(model.notes.isEmpty ? "No notes yet. Right-click a line and choose “Add Note”, or use the Note button above the code." : "No matching notes")
                        .font(.system(size: 10)).foregroundStyle(palette.muted).padding(10)
                }
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
                if showPreview, SourceLanguage.isPreviewable(path: path), let root = model.root {
                    HTMLPreview(fileURL: URL(fileURLWithPath: path), root: root).id(path)
                } else {
                CodeViewer(text: model.text, language: model.language, jump: model.jump,
                           onDefinition: { model.goToDefinition(of: $0) },
                           onUsages: { model.findUsages(of: $0) },
                           noteLines: model.noteLines(in: model.currentPath),
                           onAddNote: { line in noteDraft = model.newNote(line: line) },
                           onSelectionLine: { model.setSelectedLine($0) })
                    .background(palette.surface)
                }
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
            if SourceLanguage.isPreviewable(path: path) {
                Picker("View", selection: $showPreview) {
                    Text("Code").tag(false)
                    Text("Preview").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 130).help("Read the HTML rendered, with scripts off")
            }
            Button { noteDraft = model.newNote(line: model.selectedLine) } label: { Label("Note", systemImage: "note.text.badge.plus").font(.system(size: 10)) }
                .buttonStyle(.plain).foregroundStyle(palette.accent).help("Add a note on the selected line (line \(model.selectedLine + 1))")
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

struct NoteEditor: View {
    @State var note: CodeNote
    let palette: Palette
    let onSave: (CodeNote) -> Void
    let onDelete: (UUID) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "note.text").foregroundStyle(Color.orange)
                Text("\(note.path)\(note.line.map { ":\($0 + 1)" } ?? "")").font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.head)
                if let branch = note.branch { Text(branch).font(.system(size: 10)).foregroundStyle(palette.muted) }
            }
            TextEditor(text: $note.text)
                .font(.system(size: 12)).scrollContentBackground(.hidden)
                .padding(6).background(palette.surface, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.border, lineWidth: 1))
                .frame(minHeight: 140)
            HStack {
                if DevToolsStore.shared.codeNotes.contains(where: { $0.id == note.id }) {
                    Button("Delete", role: .destructive) { onDelete(note.id) }
                }
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Save") { onSave(note) }.keyboardShortcut(.defaultAction)
                    .disabled(note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18).frame(width: 440)
        .preferredColorScheme(palette.isDark ? .dark : .light)
    }
}

struct GitBrowseSheet: View {
    @ObservedObject var model: CodeBrowserModel
    let palette: Palette
    @Binding var isPresented: Bool
    var inline = false
    @State private var url = ""
    @State private var branches: [String] = []
    @State private var branch = ""
    @State private var isFetching = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !inline {
                Text("Browse a Git repository").font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Pick a branch to read its code. Nothing is added to your repositories; a temporary shallow copy is used.")
                    .font(.system(size: 11)).foregroundStyle(palette.muted)
            }
            HStack {
                TextField("https://github.com/owner/repo.git or git@host:owner/repo", text: $url)
                    .textFieldStyle(.roundedBorder).onSubmit(fetch)
                    .onChange(of: url) { _ in branches = []; branch = ""; error = nil }
                Button("Branches", action: fetch).disabled(isFetching || url.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !branches.isEmpty {
                Picker("Branch", selection: $branch) { ForEach(branches, id: \.self) { Text($0).tag($0) } }
            }
            if let message = error ?? model.remoteError { Text(message).font(.system(size: 10)).foregroundStyle(Color.red) }
            HStack {
                if isFetching || model.isFetchingRemote { ProgressView().controlSize(.small); Text(model.isFetchingRemote ? "Fetching code…" : "Looking up branches…").font(.system(size: 10)).foregroundStyle(palette.muted) }
                Spacer()
                if !inline { Button("Cancel") { isPresented = false }.keyboardShortcut(.cancelAction) }
                Button("Open") { model.browseRemote(url: url, branch: branch) }
                    .keyboardShortcut(.defaultAction).disabled(branch.isEmpty || model.isFetchingRemote)
            }
        }
        .padding(inline ? 0 : 18).frame(width: inline ? 480 : 520)
        .preferredColorScheme(palette.isDark ? .dark : .light)
        .onAppear {
            model.remoteError = nil
            if let remote = model.remote ?? DevToolsStore.shared.codeRemote { url = remote.url; fetch() }
        }
        .onChange(of: model.root) { _ in if model.remote != nil && !model.isFetchingRemote { isPresented = false } }
    }

    private func fetch() {
        guard !isFetching else { return }
        isFetching = true
        error = nil
        model.fetchBranches(url: url) { result in
            isFetching = false
            switch result {
            case .success(let found):
                branches = found.branches
                let current = model.remote?.url == url.trimmingCharacters(in: .whitespacesAndNewlines) ? model.remote?.branch : nil
                branch = [current, found.defaultBranch].compactMap { $0 }.first { found.branches.contains($0) } ?? found.branches[0]
            case .failure(let failure):
                error = failure.localizedDescription
            }
        }
    }
}
