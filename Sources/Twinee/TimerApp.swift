import SwiftUI
import AppKit

final class TimerModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case focus = "Focus"
        case stopwatch = "Stopwatch"
        var id: String { rawValue }
    }

    enum Phase: String {
        case focus = "Focus"
        case shortBreak = "Short break"
        case longBreak = "Long break"
    }

    @Published var mode = Mode.focus { didSet { if mode != oldValue { stop(); resetValues() } } }
    @Published private(set) var phase = Phase.focus
    @Published private(set) var remaining: TimeInterval = 25 * 60
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var isRunning = false
    @Published private(set) var cyclesDone = 0
    @Published var label = ""
    @Published var projectID: UUID?
    @Published var banner: String?

    private let tools = DevToolsStore.shared
    private var ticker: Timer?
    private var endDate: Date?
    private var resumedAt: Date?
    private var accumulated: TimeInterval = 0
    private var phaseStart: Date?

    init() {
        remaining = duration(of: .focus)
    }

    func duration(of phase: Phase) -> TimeInterval {
        switch phase {
        case .focus: return TimeInterval(max(1, tools.timer.focusMinutes) * 60)
        case .shortBreak: return TimeInterval(max(1, tools.timer.shortBreakMinutes) * 60)
        case .longBreak: return TimeInterval(max(1, tools.timer.longBreakMinutes) * 60)
        }
    }

    var total: TimeInterval { duration(of: phase) }

    var progress: Double {
        mode == .focus ? 1 - remaining / max(1, total) : (elapsed.truncatingRemainder(dividingBy: 3600)) / 3600
    }

    var displayString: String { Self.format(mode == .focus ? remaining : elapsed, roundUp: mode == .focus) }

    static func format(_ seconds: TimeInterval, roundUp: Bool = false) -> String {
        let value = max(0, Int(roundUp ? seconds.rounded(.up) : seconds.rounded(.down)))
        let hours = value / 3600, minutes = (value % 3600) / 60, secs = value % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%02d:%02d", minutes, secs)
    }

    func toggle() { isRunning ? pause() : start() }

    func start() {
        guard !isRunning else { return }
        banner = nil
        if phaseStart == nil { phaseStart = Date() }
        if mode == .focus {
            endDate = Date().addingTimeInterval(remaining)
        } else {
            resumedAt = Date()
        }
        isRunning = true
        ticker?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func pause() {
        guard isRunning else { return }
        tick()
        if mode == .stopwatch { accumulated = elapsed }
        stop()
    }

    func reset() {
        stop()
        resetValues()
        banner = nil
    }

    func skip() {
        guard mode == .focus else { return }
        stop()
        advance(logging: false)
    }

    // Saves the stopwatch time as a session and starts over.
    func logStopwatch() {
        guard mode == .stopwatch, elapsed >= 1 else { return }
        pause()
        record(seconds: Int(elapsed), start: phaseStart ?? Date().addingTimeInterval(-elapsed))
        banner = "Logged \(Self.format(elapsed))"
        reset()
    }

    func applySettings() {
        if !isRunning && mode == .focus && phaseStart == nil { remaining = duration(of: phase) }
    }

    private func stop() {
        ticker?.invalidate()
        ticker = nil
        isRunning = false
    }

    private func resetValues() {
        phase = .focus
        remaining = duration(of: .focus)
        elapsed = 0
        accumulated = 0
        phaseStart = nil
        endDate = nil
        resumedAt = nil
    }

    private func tick() {
        guard isRunning else { return }
        if mode == .stopwatch {
            elapsed = accumulated + Date().timeIntervalSince(resumedAt ?? Date())
        } else if let endDate {
            remaining = max(0, endDate.timeIntervalSinceNow)
            if remaining <= 0 { finishPhase() }
        }
    }

    private func finishPhase() {
        stop()
        NSSound(named: "Glass")?.play()
        NSApp.requestUserAttention(.informationalRequest)
        if phase == .focus {
            record(seconds: Int(duration(of: .focus)), start: phaseStart ?? Date())
            banner = "Focus session complete. Nice work!"
        } else {
            banner = "Break over. Ready for the next session?"
        }
        advance(logging: true)
        if tools.timer.autoStartNext { start() }
    }

    private func advance(logging: Bool) {
        if phase == .focus {
            if logging { cyclesDone += 1 }
            phase = (logging && cyclesDone % 4 == 0) ? .longBreak : .shortBreak
        } else {
            phase = .focus
        }
        remaining = duration(of: phase)
        phaseStart = nil
        endDate = nil
    }

    private func record(seconds: Int, start: Date) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        tools.sessions.insert(FocusSession(label: trimmed, projectID: projectID, start: start, seconds: seconds), at: 0)
        if tools.sessions.count > 500 { tools.sessions = Array(tools.sessions.prefix(500)) }
    }
}

struct TimerView: View {
    @ObservedObject var model: TimerModel
    @ObservedObject private var tools = DevToolsStore.shared
    let projects: [Project]
    let palette: Palette
    let theme: ThemeMode
    let toggleTheme: () -> Void

    private var phaseColor: Color {
        if model.mode == .stopwatch { return palette.accent }
        switch model.phase {
        case .focus: return palette.accent
        case .shortBreak: return Color(hex: 0x58A486)
        case .longBreak: return Color(hex: 0x638FC8)
        }
    }

    private var today: [FocusSession] { tools.sessions.filter { Calendar.current.isDateInToday($0.start) } }

    var body: some View {
        VStack(spacing: 0) {
            AppTopBar(title: "Timer", subtitle: "Focus sessions and stopwatch", palette: palette, theme: theme, toggleTheme: toggleTheme)
            ScrollView {
                VStack(spacing: 16) {
                    timerCard
                    settingsCard
                    historyCard
                }
                .frame(maxWidth: 720)
                .padding(.horizontal, 28).padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .background(palette.background)
        .preferredColorScheme(palette.isDark ? .dark : .light)
    }

    private var timerCard: some View {
        VStack(spacing: 18) {
            Picker("Mode", selection: $model.mode) {
                ForEach(TimerModel.Mode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().frame(width: 220).disabled(model.isRunning)

            ZStack {
                Circle().stroke(palette.border, lineWidth: 10)
                Circle().trim(from: 0, to: min(1, max(0.001, model.progress)))
                    .stroke(phaseColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: model.progress)
                VStack(spacing: 4) {
                    Text(model.displayString).font(.system(size: 50, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(model.mode == .focus ? model.phase.rawValue.uppercased() : "ELAPSED")
                        .font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(phaseColor)
                }
            }.frame(width: 230, height: 230)

            HStack(spacing: 10) {
                Button { model.toggle() } label: {
                    Label(model.isRunning ? "Pause" : "Start", systemImage: model.isRunning ? "pause.fill" : "play.fill").frame(width: 80)
                }.buttonStyle(PillButtonStyle(palette: palette, prominent: true)).keyboardShortcut(.space, modifiers: [])
                Button { model.reset() } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(PillButtonStyle(palette: palette))
                if model.mode == .focus {
                    Button { model.skip() } label: { Label("Skip", systemImage: "forward.end.fill") }
                        .buttonStyle(PillButtonStyle(palette: palette))
                } else {
                    Button { model.logStopwatch() } label: { Label("Log time", systemImage: "square.and.arrow.down") }
                        .buttonStyle(PillButtonStyle(palette: palette)).disabled(model.elapsed < 1)
                }
            }

            HStack(spacing: 10) {
                TextField("What are you working on?", text: $model.label).textFieldStyle(.roundedBorder)
                Picker("Project", selection: $model.projectID) {
                    Text("No project").tag(UUID?.none)
                    ForEach(projects) { Text($0.name).tag(UUID?.some($0.id)) }
                }.labelsHidden().frame(width: 170)
            }.font(.system(size: 11))

            if let banner = model.banner {
                Label(banner, systemImage: "bell.fill").font(.system(size: 11, weight: .medium)).foregroundStyle(phaseColor)
            }
            if model.mode == .focus {
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle().fill(index < model.cyclesDone % 4 || (model.cyclesDone > 0 && model.cyclesDone % 4 == 0 && model.phase == .longBreak) ? phaseColor : palette.border).frame(width: 8, height: 8)
                    }
                    Text("sessions until a long break").font(.system(size: 9)).foregroundStyle(palette.muted)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22).padding(.horizontal, 16)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.border, lineWidth: 1))
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FOCUS SETTINGS").font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(palette.muted)
            HStack(spacing: 22) {
                Stepper("Focus \(tools.timer.focusMinutes) min", value: $tools.timer.focusMinutes, in: 1...180)
                Stepper("Short break \(tools.timer.shortBreakMinutes) min", value: $tools.timer.shortBreakMinutes, in: 1...60)
                Stepper("Long break \(tools.timer.longBreakMinutes) min", value: $tools.timer.longBreakMinutes, in: 1...90)
            }.font(.system(size: 11)).disabled(model.isRunning)
            Toggle("Start the next session automatically", isOn: $tools.timer.autoStartNext).font(.system(size: 11))
        }
        .devCard(palette)
        .onChange(of: tools.timer) { _ in model.applySettings() }
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TODAY").font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(palette.muted)
                Spacer()
                Text("\(today.count) \(today.count == 1 ? "session" : "sessions") · \(minutes(today.reduce(0) { $0 + $1.seconds }))")
                    .font(.system(size: 11, weight: .semibold))
                if !tools.sessions.isEmpty {
                    Button("Clear history") { tools.sessions = [] }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(palette.muted)
                }
            }
            if tools.sessions.isEmpty {
                Text("Completed focus sessions and logged stopwatch time will appear here.").font(.system(size: 11)).foregroundStyle(palette.muted)
            }
            ForEach(tools.sessions.prefix(30)) { session in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(hex: 0x58A486))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.label.isEmpty ? "Focus session" : session.label).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        Text(projects.first { $0.id == session.projectID }?.name ?? "No project").font(.system(size: 9)).foregroundStyle(palette.muted)
                    }
                    Spacer()
                    Text(minutes(session.seconds)).font(.system(size: 11, weight: .medium))
                    Text(session.start.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 9)).foregroundStyle(palette.muted)
                    Button { tools.sessions.removeAll { $0.id == session.id } } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).font(.system(size: 9)).foregroundStyle(palette.muted)
                }
                .padding(.vertical, 4)
            }
        }.devCard(palette)
    }

    private func minutes(_ seconds: Int) -> String {
        seconds >= 3600 ? "\(seconds / 3600)h \((seconds % 3600) / 60)m" : "\(max(1, seconds / 60)) min"
    }
}
