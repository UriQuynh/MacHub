// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import AgentKit
import AppKit
import Combine
import Foundation

/// Theo dõi phiên agent (Claude Code, Codex), hạn mức, token/chi phí và yêu cầu duyệt quyền.
@MainActor
final class AgentMonitor: ObservableObject {
    static let shared = AgentMonitor()

    enum UsageRange: Int, CaseIterable, Identifiable {
        case today, week, month
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .today: return tr("Hôm nay", "Today")
            case .week: return tr("7 ngày", "7 days")
            case .month: return tr("30 ngày", "30 days")
            }
        }
        func start(now: Date, calendar: Calendar = .current) -> Date {
            let today = calendar.startOfDay(for: now)
            switch self {
            case .today: return today
            case .week: return calendar.date(byAdding: .day, value: -6, to: today) ?? today
            case .month: return calendar.date(byAdding: .day, value: -29, to: today) ?? today
            }
        }
    }

    // MARK: Trạng thái công khai

    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var approvals: [PendingApproval] = []
    @Published private(set) var claudeLimits: LimitSnapshot?
    @Published private(set) var codexLimits: LimitSnapshot?
    @Published private(set) var summary: UsageSummary?
    @Published private(set) var hookState = ClaudeSettingsInstaller.State()
    @Published private(set) var oauthError: String?
    @Published private(set) var setupMessage: String?
    @Published private(set) var serverError: String?
    @Published private(set) var isScanning = false
    @Published var range: UsageRange = .today { didSet { rebuildSummary() } }

    @Published var oauthEnabled: Bool = UserDefaults.standard.bool(forKey: Keys.oauth) {
        didSet {
            UserDefaults.standard.set(oauthEnabled, forKey: Keys.oauth)
            oauthError = nil
            if oauthEnabled { refreshOAuth(force: true) } else { claudeOAuthLimits = nil; publishLimits() }
        }
    }

    @Published var approvalsEnabled: Bool = UserDefaults.standard.object(forKey: Keys.approvals) as? Bool ?? true {
        didSet { UserDefaults.standard.set(approvalsEnabled, forKey: Keys.approvals) }
    }

    /// Giây chờ bạn quyết định trước khi trả quyền hỏi về terminal.
    @Published var approvalTimeout: Double = UserDefaults.standard.object(forKey: Keys.approvalTimeout) as? Double ?? 120 {
        didSet { UserDefaults.standard.set(approvalTimeout, forKey: Keys.approvalTimeout) }
    }

    var runningCount: Int { sessions.filter(\.isActive).count }

    // MARK: Nội bộ

    private enum Keys {
        static let oauth = "agent_oauth_enabled"
        static let approvals = "agent_approvals_enabled"
        static let approvalTimeout = "agent_approval_timeout"
    }

    private var server: UnixSocketServer?
    private var claudeSessions: [String: AgentSession] = [:]
    private var codexSessions: [AgentSession] = []
    private var records: [UsageRecord] = []
    private var prices = PriceBook()
    private let scanner = AgentUsageScanner()
    private var claudeStatusLineLimits: LimitSnapshot?
    private var claudeOAuthLimits: LimitSnapshot?
    private var timer: Timer?
    private var popoverVisible = false
    private var tabVisible = false
    private var lastScanAt = Date.distantPast
    private var lastOAuthAt = Date.distantPast
    private var oauthBackoffUntil = Date.distantPast
    private var started = false

    private init() {}

    // MARK: Vòng đời

    func start() {
        guard !started else { return }
        started = true
        let env = ProcessInfo.processInfo.environment

        if env["MACHUB_AGENT_FIXTURES"] == "1" {
            loadFixtures()
            return
        }

        prices.applyOverrides(from: AgentPaths.supportDirectory.appendingPathComponent("pricing.json"))
        startServer()
        refreshHookState()
        if hookState.installed { try? AgentHookSetup.refreshHookBinary() }

        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        tick()
    }

    func stop() {
        server?.stop()
        server = nil
        timer?.invalidate()
        approvals.forEach { $0.respond(.askInTerminal) }
    }

    func setPopoverVisible(_ visible: Bool) {
        popoverVisible = visible
        if visible { tick() }
    }

    func setTabVisible(_ visible: Bool) {
        tabVisible = visible
        if visible, ProcessInfo.processInfo.environment["MACHUB_AGENT_FIXTURES"] != "1" {
            refreshHookState()
            scanNow()
        }
    }

    private func tick() {
        let now = Date()
        // Quét file: 10s khi đang xem tab Agent, 60s khi chạy nền.
        let interval: TimeInterval = (popoverVisible && tabVisible) ? 10 : 60
        if now.timeIntervalSince(lastScanAt) >= interval { scanNow() }
        if oauthEnabled { refreshOAuth(force: false) }
        pruneDeadSessions(now: now)
    }

    private func startServer() {
        let s = UnixSocketServer(path: AgentPaths.socketURL.path) { [weak self] data, reply in
            guard let env = try? AgentCoding.decoder().decode(AgentEnvelope.self, from: data) else {
                reply.send(nil)
                return
            }
            Task { @MainActor in self?.handle(env, reply: reply) }
        }
        do {
            try s.start()
            server = s
        } catch {
            serverError = String(describing: error)
            appLog("⚠️ AgentMonitor: không mở được socket: \(error)")
        }
    }

    // MARK: Sự kiện từ hook

    private func handle(_ env: AgentEnvelope, reply: UnixSocketServer.Reply) {
        switch env.kind {
        case .claudeStatusLine:
            reply.send(nil)
            handleStatusLine(env.payload, at: env.sentAt)
        case .claudeHook:
            handleClaudeHook(env, reply: reply)
        }
    }

    private func handleStatusLine(_ payload: JSONValue, at date: Date) {
        let sl = ClaudeStatusLine(payload: payload, observedAt: date)
        if let limits = sl.limits {
            claudeStatusLineLimits = limits
            publishLimits()
        }
        if let sid = sl.sessionID, var s = claudeSessions["claude:\(sid)"] {
            if let m = sl.modelID ?? sl.modelName { s.model = m }
            claudeSessions[s.id] = s
            publishSessions()
        }
    }

    private func handleClaudeHook(_ env: AgentEnvelope, reply: UnixSocketServer.Reply) {
        let p = env.payload
        let event = p["hook_event_name"]?.string ?? ""
        let sid = p["session_id"]?.string ?? "unknown"
        let key = "claude:\(sid)"
        let now = Date()
        var s = claudeSessions[key] ?? AgentSession(provider: .claude, sessionID: sid, now: now)
        s.updatedAt = now
        s.parentPID = env.parentPID
        if let cwd = p["cwd"]?.string, cwd != s.cwd {
            s.cwd = cwd
            let git = GitInfo.lookup(cwd: cwd)
            s.repo = git.repo
            s.branch = git.branch
        }
        if let t = p["session_title"]?.string, !t.isEmpty { s.title = t }

        switch event {
        case "SessionStart":
            s.state = .idle
            if let m = p["model"]?.string { s.model = m }
        case "UserPromptSubmit":
            s.state = .running
            s.runningSubagents = 0
            if let prompt = p["prompt"]?.string { s.lastPrompt = Self.clip(prompt) }
        case "SubagentStart":
            s.runningSubagents += 1
            if !s.isActive { s.state = .running }
        case "SubagentStop":
            s.runningSubagents = max(0, s.runningSubagents - 1)
            if let m = p["last_assistant_message"]?.string { s.lastMessage = Self.clip(m) }
            if s.state == .running || s.state == .subagentDone { s.state = .subagentDone }
        case "Stop":
            s.state = .finished
            s.runningSubagents = 0
            if let m = p["last_assistant_message"]?.string { s.lastMessage = Self.clip(m) }
            if let path = p["transcript_path"]?.string { updateModelFromTranscript(key: key, path: path) }
        case "Notification":
            switch p["notification_type"]?.string {
            case "permission_prompt": s.state = .waitingApproval
            case "idle_prompt", "agent_needs_input", "elicitation_dialog": s.state = .waitingInput
            default: break
            }
        case "PermissionRequest":
            s.state = .waitingApproval
        case "SessionEnd":
            s.state = .ended
            s.runningSubagents = 0
        default:
            break
        }
        claudeSessions[key] = s
        publishSessions()

        guard event == "PermissionRequest", env.wantsReply else {
            reply.send(nil)
            return
        }
        guard approvalsEnabled else {
            reply.send(encodeReply(.askInTerminal))
            return
        }
        enqueueApproval(p, sessionKey: key, reply: reply)
    }

    // MARK: Duyệt quyền

    private func enqueueApproval(_ p: JSONValue, sessionKey: String, reply: UnixSocketServer.Reply) {
        let tool = p["tool_name"]?.string ?? "Tool"
        let (summary, detail) = PendingApproval.describe(tool: tool, input: p["tool_input"])
        let suggestions = p["permission_suggestions"]
        let id = UUID()
        let latch = ApprovalLatch()

        let respond: (PermissionDecision) -> Void = { [weak self] decision in
            guard latch.claim() else { return }
            reply.send(self?.encodeReply(decision))
            Task { @MainActor in self?.finishApproval(id: id, sessionKey: sessionKey, decision: decision) }
        }
        let approval = PendingApproval(id: id, sessionKey: sessionKey, toolName: tool, summary: summary, detail: detail,
                                       cwd: p["cwd"]?.string,
                                       suggestions: (suggestions?.array?.isEmpty == false) ? suggestions : nil,
                                       createdAt: Date(), respond: respond)
        approvals.append(approval)
        AgentApprovalPanel.shared.update(with: approvals)
        NSSound(named: "Tink")?.play()

        // Hook bỏ cuộc (hết giờ phía hook / Claude Code bị đóng) → gỡ thẻ.
        reply.onClose { [weak self] in
            guard latch.claim() else { return }
            Task { @MainActor in self?.finishApproval(id: id, sessionKey: sessionKey, decision: nil) }
        }
        // Hết giờ phía app: trả quyền hỏi về terminal.
        let timeout = max(10, approvalTimeout)
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { respond(.askInTerminal) }
    }

    private func finishApproval(id: UUID, sessionKey: String, decision: PermissionDecision?) {
        approvals.removeAll { $0.id == id }
        AgentApprovalPanel.shared.update(with: approvals)
        if var s = claudeSessions[sessionKey], s.state == .waitingApproval {
            switch decision {
            case .allow?, .allowAlways?: s.state = .running
            case .deny?: s.state = .running
            default: break
            }
            claudeSessions[sessionKey] = s
            publishSessions()
        }
    }

    nonisolated private func encodeReply(_ d: PermissionDecision) -> Data? {
        try? AgentCoding.encoder().encode(AgentReply(output: d.hookOutput))
    }

    // MARK: Quét file & hạn mức

    func scanNow() {
        guard !isScanning, ProcessInfo.processInfo.environment["MACHUB_AGENT_FIXTURES"] != "1" else { return }
        isScanning = true
        lastScanAt = Date()
        scanner.scan { [weak self] result in
            Task { @MainActor in self?.apply(result) }
        }
    }

    private func apply(_ r: AgentUsageScanner.Result) {
        isScanning = false
        records = r.records
        if let l = r.codexLimits { codexLimits = l }
        let now = Date()
        codexSessions = r.codexSessions.compactMap { info in
            guard let last = info.lastActivity, now.timeIntervalSince(last) < 12 * 3_600 else { return nil }
            var s = AgentSession(provider: .codex, sessionID: info.sessionID, now: info.startedAt ?? last)
            s.cwd = info.cwd
            if let cwd = info.cwd {
                let git = GitInfo.lookup(cwd: cwd)
                s.repo = git.repo
                s.branch = info.branch ?? git.branch
            }
            s.model = info.model
            s.lastPrompt = info.lastUserMessage.map { Self.clip($0) }
            s.lastMessage = info.lastAgentMessage.map { Self.clip($0) }
            s.updatedAt = last
            switch info.state {
            // Codex bị tắt ngang có thể để lại "running" mãi: quá 15 phút không ghi gì → coi như xong.
            case .running: s.state = now.timeIntervalSince(last) < 15 * 60 ? .running : .finished
            case .finished: s.state = .finished
            case .idle: s.state = .idle
            }
            return s
        }
        publishSessions()
        rebuildSummary()
    }

    func refreshOAuth(force: Bool) {
        let now = Date()
        guard oauthEnabled, now >= oauthBackoffUntil else { return }
        // 5 phút một lần khi đang mở bảng, 15 phút khi chạy nền.
        let interval: TimeInterval = popoverVisible ? 300 : 900
        guard force || now.timeIntervalSince(lastOAuthAt) >= interval else { return }
        lastOAuthAt = now
        Task {
            let result = await ClaudeOAuthUsageClient.fetch()
            await MainActor.run {
                switch result {
                case .success(let snap):
                    self.claudeOAuthLimits = snap
                    self.oauthError = nil
                    self.publishLimits()
                case .failure(let e):
                    self.oauthError = e.message
                    if case .http(429) = e { self.oauthBackoffUntil = Date().addingTimeInterval(900) }
                    if case .keychainDenied = e { self.oauthBackoffUntil = .distantFuture }
                }
            }
        }
    }

    /// Ghép hạn mức Claude từ statusLine và OAuth: mỗi cửa sổ lấy bản mới nhất.
    private func publishLimits() {
        let snaps = [claudeStatusLineLimits, claudeOAuthLimits].compactMap { $0 }
        guard let newest = snaps.max(by: { $0.observedAt < $1.observedAt }) else {
            claudeLimits = nil
            return
        }
        var byID: [String: (LimitWindow, Date)] = [:]
        for snap in snaps {
            for w in snap.windows where byID[w.id].map({ $0.1 < snap.observedAt }) ?? true {
                byID[w.id] = (w, snap.observedAt)
            }
        }
        let windows = ClaudeOAuthUsage.sortClaude(byID.values.map(\.0))
        claudeLimits = LimitSnapshot(provider: .claude, windows: windows, observedAt: newest.observedAt, source: newest.source)
        writeDumpIfNeeded()
    }

    private func rebuildSummary() {
        let now = Date()
        summary = UsageSummary.build(records: records, from: range.start(now: now), to: now, prices: prices)
    }

    // MARK: Phiên

    private func pruneDeadSessions(now: Date) {
        var changed = false
        for (key, var s) in claudeSessions {
            if s.isActive, let pid = s.parentPID, pid > 1, kill(pid, 0) != 0, errno == ESRCH {
                s.state = .ended
                claudeSessions[key] = s
                changed = true
            }
            let age = now.timeIntervalSince(s.updatedAt)
            if (s.state == .ended && age > 30 * 60) || (!s.isActive && age > 12 * 3_600) {
                claudeSessions.removeValue(forKey: key)
                changed = true
            }
        }
        if changed { publishSessions() }
    }

    private func publishSessions() {
        let all = Array(claudeSessions.values) + codexSessions
        sessions = all.sorted {
            if $0.isActive != $1.isActive { return $0.isActive }
            return $0.updatedAt > $1.updatedAt
        }
        writeDumpIfNeeded()
    }

    private func updateModelFromTranscript(key: String, path: String) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let h = FileHandle(forReadingAtPath: path) else { return }
            defer { try? h.close() }
            let size = (try? h.seekToEnd()) ?? 0
            try? h.seek(toOffset: size > 65_536 ? size - 65_536 : 0)
            guard let data = try? h.readToEnd(),
                  let model = ClaudeTranscript.lastModel(inTail: String(decoding: data, as: UTF8.self)) else { return }
            Task { @MainActor in
                guard let self, var s = self.claudeSessions[key] else { return }
                s.model = model
                self.claudeSessions[key] = s
                self.publishSessions()
            }
        }
    }

    static func clip(_ s: String, max: Int = 280) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        return t.count > max ? String(t.prefix(max)) + "…" : t
    }

    // MARK: Cài đặt hook

    func refreshHookState() {
        hookState = AgentHookSetup.currentState()
    }

    func installHooks(statusLine: Bool) {
        do {
            let opts = ClaudeSettingsInstaller.Options(observe: true, approvals: approvalsEnabled, statusLine: statusLine)
            let backup = try AgentHookSetup.install(options: opts, approvalTimeout: approvalTimeout)
            setupMessage = tr("Đã cài hook. Mở phiên Claude Code mới để bắt đầu theo dõi.", "Hooks installed. Start a new Claude Code session to begin tracking.")
                + (backup.map { tr(" Bản sao lưu: \($0.lastPathComponent)", " Backup: \($0.lastPathComponent)") } ?? "")
        } catch let e as AgentHookSetup.SetupError {
            setupMessage = e.message
        } catch {
            setupMessage = error.localizedDescription
        }
        refreshHookState()
    }

    func uninstallHooks() {
        do {
            try AgentHookSetup.uninstall()
            setupMessage = tr("Đã gỡ hook MacHub khỏi Claude Code.", "Removed MacHub hooks from Claude Code.")
        } catch let e as AgentHookSetup.SetupError {
            setupMessage = e.message
        } catch {
            setupMessage = error.localizedDescription
        }
        refreshHookState()
    }

    // MARK: Kiểm thử

    /// `MACHUB_AGENT_DUMP=/path.json`: ghi trạng thái ra file mỗi khi đổi (dùng cho E2E).
    private func writeDumpIfNeeded() {
        guard let path = ProcessInfo.processInfo.environment["MACHUB_AGENT_DUMP"], !path.isEmpty else { return }
        let dump: JSONValue = [
            "sessions": .array(sessions.map { s in
                ["id": .string(s.id), "state": .string(s.state.rawValue), "title": .string(s.displayTitle),
                 "model": s.model.map(JSONValue.string) ?? .null, "repo": s.repo.map(JSONValue.string) ?? .null,
                 "branch": s.branch.map(JSONValue.string) ?? .null, "prompt": s.lastPrompt.map(JSONValue.string) ?? .null]
            }),
            "claudeLimits": .array((claudeLimits?.windows ?? []).map { ["id": .string($0.id), "used": .number($0.usedPercent)] }),
            "approvals": .number(Double(approvals.count)),
        ]
        try? dump.encoded().write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    /// `MACHUB_AGENT_FIXTURES=1`: dữ liệu mẫu để chụp giao diện (không đọc máy thật).
    private func loadFixtures() {
        let now = Date()
        var a = AgentSession(provider: .claude, sessionID: "fixture-a", now: now.addingTimeInterval(-840))
        a.title = "Duyệt bộ giá drop"; a.repo = "FTL_NTL"; a.branch = "main"; a.model = "claude-sonnet-5-5"
        a.state = .subagentDone; a.lastPrompt = "đã duyệt xong bộ giá, tính lại tiền drop đi"
        a.lastMessage = "Đã tính lại 459 đơn, chênh lệch 1,2 triệu."; a.updatedAt = now.addingTimeInterval(-60)
        var b = AgentSession(provider: .claude, sessionID: "fixture-b", now: now.addingTimeInterval(-3_600))
        b.title = "Migration Supabase sang self-host"; b.repo = "FTL_NTL"; b.branch = "main"; b.model = "claude-sonnet-5-5"
        b.state = .finished; b.lastPrompt = "chuyển FTL_NTL về main đi"; b.updatedAt = now.addingTimeInterval(-900)
        var c = AgentSession(provider: .codex, sessionID: "fixture-c", now: now.addingTimeInterval(-1_800))
        c.repo = "MacHub"; c.branch = "agent-monitor"; c.model = "gpt-5.3-codex"; c.state = .running
        c.lastPrompt = "viết test cho bộ đọc rollout"; c.updatedAt = now.addingTimeInterval(-20)
        codexSessions = [c]
        claudeSessions = [a.id: a, b.id: b]

        claudeStatusLineLimits = LimitSnapshot(provider: .claude, windows: [
            LimitWindow(id: "five_hour", label: "5H", usedPercent: 7, resetsAt: now.addingTimeInterval(3 * 3_600 + 540)),
            LimitWindow(id: "seven_day", label: "7D", usedPercent: 28, resetsAt: now.addingTimeInterval(4 * 86_400 + 13 * 3_600)),
            LimitWindow(id: "seven_day_fable", label: "7D Fable", usedPercent: 0, resetsAt: now.addingTimeInterval(4 * 86_400 + 13 * 3_600)),
        ], observedAt: now, source: .statusLine)
        codexLimits = LimitSnapshot(provider: .codex, windows: [
            LimitWindow(id: "primary", label: "5H", usedPercent: 4, resetsAt: now.addingTimeInterval(2 * 3_600), windowMinutes: 300),
            LimitWindow(id: "secondary", label: "7D", usedPercent: 13, resetsAt: now.addingTimeInterval(5 * 86_400 + 6 * 3_600), windowMinutes: 10_080),
        ], observedAt: now, source: .codexLog, plan: "pro")

        let cal = Calendar.current
        records = (0..<30).flatMap { d -> [UsageRecord] in
            let day = cal.date(byAdding: .day, value: -d, to: now)!
            let k = Double((d * 37) % 11 + 3)
            return [
                UsageRecord(provider: .claude, timestamp: day, model: "claude-sonnet-5-5", project: "/x/FTL_NTL",
                            inputTokens: Int(k * 40_000), outputTokens: Int(k * 12_000), cacheWrite5mTokens: Int(k * 90_000),
                            cacheReadTokens: Int(k * 900_000)),
                UsageRecord(provider: .claude, timestamp: day, model: "claude-haiku-4-5-20251001", project: "/x/MacHub",
                            inputTokens: Int(k * 8_000), outputTokens: Int(k * 3_000)),
                UsageRecord(provider: .codex, timestamp: day, model: "gpt-5.3-codex", project: "/x/MacHub",
                            inputTokens: Int(k * 30_000), outputTokens: Int(k * 9_000), cacheReadTokens: Int(k * 200_000)),
            ]
        }
        hookState = ClaudeSettingsInstaller.State(observe: true, approvals: true, statusLine: true)
        publishLimits()
        publishSessions()
        rebuildSummary()
    }
}

/// Bảo đảm mỗi yêu cầu quyền chỉ được trả lời MỘT lần (nút bấm, hết giờ, hoặc hook đóng kết nối).
final class ApprovalLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
