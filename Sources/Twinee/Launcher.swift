import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum AppLauncher {
    // Returns an error message if the app can't be opened.
    static func open(_ app: LauncherApp, completion: @escaping (String?) -> Void = { _ in }) {
        guard FileManager.default.fileExists(atPath: app.path) else {
            completion("“\(app.name)” could not be found at \(app.path). It may have been moved or uninstalled.")
            return
        }
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path), configuration: NSWorkspace.OpenConfiguration()) { _, error in
            DispatchQueue.main.async { completion(error.map { "Could not open “\(app.name)”: \($0.localizedDescription)" }) }
        }
    }

    static func icon(for app: LauncherApp) -> NSImage {
        NSWorkspace.shared.icon(forFile: app.path)
    }

    static func makeApp(from url: URL) -> LauncherApp? {
        guard url.pathExtension.lowercased() == "app" else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return LauncherApp(name: name, path: url.path)
    }
}

struct LauncherView: View {
    @ObservedObject private var tools = DevToolsStore.shared
    let palette: Palette
    let theme: ThemeMode
    let toggleTheme: () -> Void
    @State private var message: String?
    @State private var isDropTarget = false

    private static let suggestions: [(name: String, paths: [String])] = [
        ("Xcode", ["/Applications/Xcode.app"]),
        ("Terminal", ["/System/Applications/Utilities/Terminal.app", "/Applications/Utilities/Terminal.app"]),
        ("Visual Studio Code", ["/Applications/Visual Studio Code.app"]),
        ("iTerm", ["/Applications/iTerm.app"]),
        ("Safari", ["/Applications/Safari.app", "/System/Cryptexes/App/System/Applications/Safari.app"]),
        ("Docker", ["/Applications/Docker.app"]),
        ("Postman", ["/Applications/Postman.app"]),
        ("Sublime Text", ["/Applications/Sublime Text.app"]),
    ]

    private var available: [LauncherApp] {
        Self.suggestions.compactMap { suggestion in
            guard let path = suggestion.paths.first(where: { FileManager.default.fileExists(atPath: $0) }),
                  !tools.apps.contains(where: { $0.path == path }) else { return nil }
            return LauncherApp(name: suggestion.name, path: path)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            AppTopBar(title: "Launcher", subtitle: "Open your desktop apps from here", palette: palette, theme: theme, toggleTheme: toggleTheme)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("YOUR APPS").font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(palette.muted)
                            Text("Link any application on your Mac, then open it with one click.").font(.system(size: 11)).foregroundStyle(palette.muted)
                        }
                        Spacer()
                        Button { chooseApps() } label: { Label("Add application…", systemImage: "plus") }
                            .buttonStyle(PillButtonStyle(palette: palette, prominent: true))
                    }

                    if let message {
                        Text(message).font(.system(size: 10)).foregroundStyle(Color.red)
                    }

                    if tools.apps.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 26, weight: .light)).foregroundStyle(palette.accent)
                            Text("Drop an application here").font(.system(size: 13, weight: .semibold))
                            Text("Or use “Add application…” to pick one from your Applications folder.").font(.system(size: 10)).foregroundStyle(palette.muted)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 118, maximum: 150), spacing: 12)], spacing: 12) {
                            ForEach(tools.apps) { app in tile(app) }
                        }
                    }

                    if !available.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("QUICK ADD").font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(palette.muted)
                            HStack(spacing: 8) {
                                ForEach(available, id: \.path) { app in
                                    Button { add(app) } label: {
                                        HStack(spacing: 6) {
                                            Image(nsImage: AppLauncher.icon(for: app)).resizable().frame(width: 16, height: 16)
                                            Text(app.name)
                                        }
                                    }.buttonStyle(PillButtonStyle(palette: palette))
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: 820, alignment: .leading)
                .padding(.horizontal, 28).padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4])).padding(10).opacity(isDropTarget ? 1 : 0))
            .onDrop(of: [UTType.fileURL], isTargeted: $isDropTarget) { providers in handleDrop(providers) }
        }
        .background(palette.background)
        .preferredColorScheme(palette.isDark ? .dark : .light)
    }

    private func tile(_ app: LauncherApp) -> some View {
        Button {
            AppLauncher.open(app) { message = $0 }
        } label: {
            VStack(spacing: 8) {
                Image(nsImage: AppLauncher.icon(for: app)).resizable().interpolation(.high).frame(width: 52, height: 52)
                Text(app.name).font(.system(size: 11, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14).padding(.horizontal, 8)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(app.path)
        .contextMenu {
            Button("Open") { AppLauncher.open(app) { message = $0 } }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)]) }
            Divider()
            Button("Remove from Launcher", role: .destructive) { tools.apps.removeAll { $0.id == app.id } }
        }
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose the applications to add to the launcher"
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { if let app = AppLauncher.makeApp(from: url) { add(app) } }
    }

    private func add(_ app: LauncherApp) {
        if tools.apps.contains(where: { $0.path == app.path }) {
            message = "“\(app.name)” is already in the launcher."
            return
        }
        tools.apps.append(app)
        message = nil
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            accepted = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                DispatchQueue.main.async {
                    guard let url, let app = AppLauncher.makeApp(from: url) else {
                        message = "Only application bundles (.app) can be added."
                        return
                    }
                    add(app)
                }
            }
        }
        return accepted
    }
}
