import SwiftUI
import AppKit

struct AIProvider: Identifiable, Equatable {
    let id: String
    let name: String
    let symbol: String
    let tint: Color
    let defaultCommand: String
    let installHint: String

    static let all: [AIProvider] = [
        AIProvider(id: "copilot", name: "GitHub Copilot", symbol: "sparkles", tint: Color(hex: 0x8957E5), defaultCommand: "copilot -s -p", installHint: "Install the Copilot CLI (npm install -g @github/copilot) and sign in with `copilot` once."),
        AIProvider(id: "gemini", name: "Gemini", symbol: "star.circle.fill", tint: Color(hex: 0x4285F4), defaultCommand: "gemini -p", installHint: "Install the Gemini CLI (npm install -g @google/gemini-cli) and sign in with `gemini` once."),
        AIProvider(id: "claude", name: "Claude", symbol: "text.bubble.fill", tint: Color(hex: 0xD97757), defaultCommand: "claude -p", installHint: "Install Claude Code (npm install -g @anthropic-ai/claude-code) and sign in with `claude` once."),
        AIProvider(id: "codex", name: "Codex", symbol: "chevron.left.forwardslash.chevron.right", tint: Color(hex: 0x10A37F), defaultCommand: "codex exec", installHint: "Install the Codex CLI (npm install -g @openai/codex) and sign in with `codex` once."),
    ]
}

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant, error }
    let id = UUID()
    let role: Role
    var text: String
    var provider: String?
    var attached: String?
}

struct PageContext: Equatable {
    var title: String
    var kind: String
    var text: String
    var note: String? = nil
}

// Runs each question through a command-line AI tool, so Twinee needs no API keys of its own.
final class AIChatModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isRunning = false
    @Published var input = ""
    @Published var attachPage = true
    @AppStorage("twinee.ai.provider") var providerID = "copilot"

    private var process: Process?
    private var cancelled = false
    private static let maxContextCharacters = 60_000

    var provider: AIProvider { AIProvider.all.first { $0.id == providerID } ?? AIProvider.all[0] }

    func command(for provider: AIProvider) -> String {
        let saved = UserDefaults.standard.string(forKey: "twinee.ai.cmd.\(provider.id)")
        return saved?.isEmpty == false ? saved! : provider.defaultCommand
    }

    func setCommand(_ value: String, for provider: AIProvider) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed == provider.defaultCommand ? nil : trimmed, forKey: "twinee.ai.cmd.\(provider.id)")
        objectWillChange.send()
    }

    func clear() {
        stop()
        messages = []
    }

    func stop() {
        guard isRunning else { return }
        cancelled = true
        process?.terminate()
    }

    func send(context: PageContext?) {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isRunning else { return }
        input = ""
        let provider = provider
        let attached = attachPage ? context : nil
        messages.append(ChatMessage(role: .user, text: question, attached: attached?.title))

        var prompt = ""
        if let attached {
            let body = attached.text.count > Self.maxContextCharacters ? String(attached.text.prefix(Self.maxContextCharacters)) + "\n…(truncated)" : attached.text
            prompt += "You are helping inside the Twinee app. The user is looking at the \(attached.kind) “\(attached.title)”.\(attached.note.map { " " + $0 } ?? "")\nAnswer only from this content and the question; do not run commands or edit files.\n\n<page>\n\(body)\n</page>\n\n"
        }
        // Earlier turns give the tool conversational memory, since each call is stateless.
        let history = messages.dropLast().suffix(8).filter { $0.role != .error }
        if !history.isEmpty {
            prompt += "Conversation so far:\n" + history.map { ($0.role == .user ? "User: " : "Assistant: ") + $0.text }.joined(separator: "\n") + "\n\n"
        }
        prompt += "Question: \(question)"

        isRunning = true
        cancelled = false
        let command = command(for: provider)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // The prompt travels in the environment, never inside the shell string, so it cannot be interpreted as code.
        process.arguments = ["-lc", "exec \(command) \"$TWINEE_PROMPT\""]
        var env = ProcessInfo.processInfo.environment
        env["TWINEE_PROMPT"] = prompt
        env["NO_COLOR"] = "1"
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        process.environment = env
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        self.process = process

        let reply = ChatMessage(role: .assistant, text: "", provider: provider.name)
        messages.append(reply)
        let replyID = reply.id
        var errorText = ""
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            let chunk = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { self?.append(chunk, to: replyID) }
        }
        err.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            errorText += String(decoding: data, as: UTF8.self)
        }
        process.terminationHandler = { [weak self] finished in
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            let rest = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            DispatchQueue.main.async {
                guard let self else { return }
                if !rest.isEmpty { self.append(rest, to: replyID) }
                self.isRunning = false
                self.process = nil
                let index = self.messages.firstIndex { $0.id == replyID }
                if self.cancelled {
                    if let index, self.messages[index].text.isEmpty { self.messages.remove(at: index) }
                } else if finished.terminationStatus != 0 {
                    if let index, self.messages[index].text.isEmpty { self.messages.remove(at: index) }
                    let hint = finished.terminationStatus == 127 ? "\n\n\(provider.installHint)" : ""
                    let detail = errorText.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.messages.append(ChatMessage(role: .error, text: "\(provider.name) couldn’t answer (exit \(finished.terminationStatus)).\(detail.isEmpty ? "" : "\n" + String(detail.suffix(600)))\(hint)"))
                } else if let index, self.messages[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.messages[index].text = "(No reply.)"
                }
            }
        }
        do {
            try process.run()
        } catch {
            isRunning = false
            self.process = nil
            messages.removeAll { $0.id == replyID }
            messages.append(ChatMessage(role: .error, text: "Could not start \(provider.name): \(error.localizedDescription)"))
        }
    }

    private func append(_ chunk: String, to id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text += chunk
    }
}

struct AIChatPanel: View {
    @ObservedObject var model: AIChatModel
    let context: PageContext?
    let palette: Palette
    let onClose: () -> Void
    @State private var editingCommand = false
    @State private var commandText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            if let context { contextBar(context) }
            transcript
            composer
        }
        .background(palette.sidebar)
        .preferredColorScheme(palette.isDark ? .dark : .light)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: model.provider.symbol).foregroundStyle(.white).frame(width: 22, height: 22)
                .background(model.provider.tint.gradient, in: RoundedRectangle(cornerRadius: 6))
            Menu {
                ForEach(AIProvider.all) { provider in
                    Button { model.providerID = provider.id } label: {
                        Label(provider.name, systemImage: model.providerID == provider.id ? "checkmark" : provider.symbol)
                    }
                }
                Divider()
                Button("Edit command…") { commandText = model.command(for: model.provider); editingCommand = true }
            } label: {
                Text(model.provider.name).font(.system(size: 12, weight: .semibold))
            }.menuStyle(.borderlessButton).fixedSize()
            Spacer()
            Button { model.clear() } label: { Image(systemName: "trash").font(.system(size: 11)) }
                .buttonStyle(.plain).foregroundStyle(palette.muted).help("Clear chat").disabled(model.messages.isEmpty)
            Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                .buttonStyle(.plain).foregroundStyle(palette.muted).help("Close AI chat")
        }
        .padding(.horizontal, 12).frame(height: 52)
        .background(palette.surface)
        .overlay(alignment: .top) { Rectangle().fill(Brand.gradient).frame(height: 3) }
        .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }
        .alert("Command for \(model.provider.name)", isPresented: $editingCommand) {
            TextField("e.g. gemini -p", text: $commandText)
            Button("Cancel", role: .cancel) {}
            Button("Reset") { model.setCommand("", for: model.provider) }
            Button("Save") { model.setCommand(commandText, for: model.provider) }
        } message: { Text("Run through your login shell. Twinee adds the question as the last argument.") }
    }

    private func contextBar(_ context: PageContext) -> some View {
        HStack(spacing: 6) {
            Image(systemName: model.attachPage ? "doc.text.fill" : "doc.text").font(.system(size: 10)).foregroundStyle(model.attachPage ? palette.accent : palette.muted)
            Text(model.attachPage ? "Reading: \(context.title)" : "Page not shared").font(.system(size: 10)).lineLimit(1).foregroundStyle(palette.muted)
            Spacer()
            Toggle("", isOn: $model.attachPage).toggleStyle(.switch).controlSize(.mini).labelsHidden().help("Share the open page with the assistant")
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(palette.selected.opacity(0.6))
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if model.messages.isEmpty { emptyState }
                    ForEach(model.messages) { message in bubble(message).id(message.id) }
                    if model.isRunning, model.messages.last?.text.isEmpty == true {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Thinking…").font(.system(size: 10)).foregroundStyle(palette.muted) }
                    }
                    Color.clear.frame(height: 1).id("end")
                }.padding(12)
            }
            .onChange(of: model.messages.last?.text) { _ in proxy.scrollTo("end") }
            .onChange(of: model.messages.count) { _ in proxy.scrollTo("end") }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles").font(.system(size: 22)).foregroundStyle(Brand.gradient)
            Text("Ask about the open page").font(.system(size: 13, weight: .semibold, design: .rounded))
            Text("Explain code, summarise notes or find bugs. The page you’re viewing is shared automatically.")
                .font(.system(size: 10)).foregroundStyle(palette.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.top, 30)
    }

    @ViewBuilder
    private func bubble(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            VStack(alignment: .trailing, spacing: 3) {
                Text(message.text).font(.system(size: 12)).textSelection(.enabled)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(palette.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                if let attached = message.attached { Label(attached, systemImage: "paperclip").font(.system(size: 9)).foregroundStyle(palette.muted).lineLimit(1) }
            }.frame(maxWidth: .infinity, alignment: .trailing)
        case .assistant:
            VStack(alignment: .leading, spacing: 3) {
                if let name = message.provider { Text(name).font(.system(size: 9, weight: .bold)).foregroundStyle(palette.muted) }
                if !message.text.isEmpty {
                    Text(Self.render(message.text)).font(.system(size: 12)).textSelection(.enabled)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(palette.surface, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.border, lineWidth: 1))
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        case .error:
            Text(message.text).font(.system(size: 11)).foregroundStyle(Color.red).textSelection(.enabled)
                .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private static func render(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    private var composer: some View {
        VStack(spacing: 6) {
            TextField("Ask \(model.provider.name)…", text: $model.input, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 12)).lineLimit(1...6)
                .padding(9).background(palette.surface, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(palette.border, lineWidth: 1))
                .onSubmit { model.send(context: context) }
            HStack {
                Text("Return to send").font(.system(size: 9)).foregroundStyle(palette.muted)
                Spacer()
                if model.isRunning {
                    Button { model.stop() } label: { Label("Stop", systemImage: "stop.fill") }.buttonStyle(PillButtonStyle(palette: palette))
                } else {
                    Button { model.send(context: context) } label: { Label("Send", systemImage: "paperplane.fill") }
                        .buttonStyle(PillButtonStyle(palette: palette, prominent: true))
                        .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(12)
        .overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 1) }
    }
}
