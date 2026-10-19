import SwiftUI
import AppKit
import SwiftTerm

// A real interactive terminal running the user's own login shell, so any compiler on their Mac is available.
@MainActor
final class TSTerminal: NSObject, ObservableObject, LocalProcessTerminalViewDelegate {
    let view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
    @Published private(set) var isAlive = false
    private var started = false

    override init() {
        super.init()
        view.processDelegate = self
        view.nativeBackgroundColor = NSColor(red: 0.055, green: 0.051, blue: 0.078, alpha: 1)
        view.nativeForegroundColor = NSColor(red: 0.855, green: 0.843, blue: 0.918, alpha: 1)
        view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    }

    func start(in directory: URL) {
        guard !started else { return }
        started = true
        isAlive = true
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        view.startProcess(executable: shell, args: ["-l"], environment: nil, execName: "-" + (shell as NSString).lastPathComponent, currentDirectory: directory.path)
    }

    func restart(in directory: URL) {
        view.terminate()
        started = false
        view.feed(text: "\u{1b}c")
        start(in: directory)
    }

    func run(_ command: String, in directory: URL) {
        let line = "cd \(Self.quote(directory.path)) && clear && \(command)\n"
        if started {
            type(line)
            focus()
        } else {
            // A brand-new shell needs the view on screen first, otherwise it starts with a zero-width window.
            start(in: directory)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { self.type(line); self.focus() }
        }
    }

    func interrupt() { send([0x03]) }

    func cd(_ directory: URL) {
        guard isAlive else { return }
        type(" cd \(Self.quote(directory.path))\n")
    }

    func say(_ text: String) { view.feed(text: "\r\n" + text.replacingOccurrences(of: "\n", with: "\r\n")) }

    func focus() { view.window?.makeFirstResponder(view) }

    private func type(_ text: String) { send(Array(text.utf8)) }
    private func send(_ bytes: [UInt8]) { view.send(data: ArraySlice(bytes)) }

    private static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { self.isAlive = false }
    }
}

struct TSTerminalView: NSViewRepresentable {
    let terminal: TSTerminal
    func makeNSView(context: Context) -> LocalProcessTerminalView { terminal.view }
    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
}
