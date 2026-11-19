// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import AgentKit
import SwiftUI

/// Tab "Agent": phiên Claude Code / Codex, hạn mức 5H/7D, token và chi phí ước tính.
struct AgentTabView: View {
    @ObservedObject var monitor: AgentMonitor
    @State private var section = 0
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 8) {
            header
            if showSettings {
                ScrollView { AgentSettingsView(monitor: monitor) }
            } else {
                if !monitor.hookState.installed {
                    setupBanner
                }
                Picker("", selection: $section) {
                    Text(tr("Phiên", "Sessions")).tag(0)
                    Text(tr("Hạn mức", "Limits")).tag(1)
                    Text("Token").tag(2)
                    Text(tr("Chi phí", "Cost")).tag(3)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 12)

                ScrollView {
                    Group {
                        switch section {
                        case 0: AgentSessionsList(monitor: monitor)
                        case 1: AgentLimitsView(monitor: monitor)
                        case 2: AgentUsageView(monitor: monitor, showCost: false)
                        default: AgentUsageView(monitor: monitor, showCost: true)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }
        }
        .padding(.top, 8)
        .onAppear { monitor.setTabVisible(true) }
        .onDisappear { monitor.setTabVisible(false) }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(tr("\(monitor.runningCount) đang chạy", "\(monitor.runningCount) running"))
                .font(.system(size: FS.title, weight: .semibold))
                .foregroundStyle(monitor.runningCount > 0 ? Color.accentColor : Color.primary)
            Text("· \(monitor.sessions.count)")
                .font(.system(size: FS.title))
                .foregroundStyle(.secondary)
            Spacer()
            LimitChip(provider: .claude, snapshot: monitor.claudeLimits)
            LimitChip(provider: .codex, snapshot: monitor.codexLimits)
            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: showSettings ? "xmark.circle.fill" : "gearshape")
                    .font(.system(size: FS.title))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(tr("Cài đặt theo dõi agent", "Agent monitor settings"))
        }
        .padding(.horizontal, 12)
    }

    private var setupBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.horizontal.circle").foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("Kết nối Claude Code", "Connect Claude Code"))
                    .font(.system(size: FS.body, weight: .semibold))
                Text(tr("Cài hook để thấy phiên đang chạy, hạn mức 5H/7D và duyệt quyền tại đây. Codex được đọc tự động.",
                        "Install hooks to see live sessions, 5H/7D limits and approve permissions here. Codex is read automatically."))
                    .font(.system(size: FS.label)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button(tr("Cài", "Install")) { showSettings = true }
                .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Rad.md).fill(Color.accentColor.opacity(0.08)))
        .padding(.horizontal, 12)
    }
}

// MARK: - Thành phần dùng chung

enum AgentStyle {
    static func color(_ p: AgentProvider) -> Color {
        switch p {
        case .claude: return Color(red: 0.80, green: 0.47, blue: 0.36)
        case .codex: return Color(red: 0.36, green: 0.55, blue: 0.95)
        }
    }

    static func icon(_ p: AgentProvider) -> String {
        switch p {
        case .claude: return "asterisk"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        }
    }

    static func barColor(_ pct: Double, provider: AgentProvider) -> Color {
        if pct >= 95 { return Tone.bad }
        if pct >= 80 { return Tone.warn }
        return color(provider)
    }
}

struct LimitChip: View {
    let provider: AgentProvider
    let snapshot: LimitSnapshot?

    var body: some View {
        if let w = snapshot?.headline {
            HStack(spacing: 3) {
                Image(systemName: AgentStyle.icon(provider)).font(.system(size: FS.caption, weight: .bold))
                    .foregroundStyle(AgentStyle.color(provider))
                Text("\(Int(w.usedPercent.rounded()))%").font(.system(size: FS.label, weight: .semibold).monospacedDigit())
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .help("\(provider.displayName) \(w.label): \(Int(w.usedPercent.rounded()))%")
        }
    }
}

/// Thanh 20 ô như đồng hồ đo.
struct SegmentBar: View {
    let percent: Double
    let color: Color
    var segments = 20

    var body: some View {
        let filled = percent <= 0 ? 0 : max(1, Int((percent / 100 * Double(segments)).rounded(.up)))
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < filled ? color : Color.primary.opacity(0.1))
            }
        }
        .frame(height: 12)
    }
}

// MARK: - Phiên

struct AgentSessionsList: View {
    @ObservedObject var monitor: AgentMonitor

    var body: some View {
        VStack(spacing: 6) {
            ForEach(monitor.approvals) { a in
                ApprovalCard(approval: a)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: Rad.md).fill(Tone.warn.opacity(0.10)))
            }
            if monitor.sessions.isEmpty {
                emptyState
            }
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                VStack(spacing: 6) {
                    ForEach(monitor.sessions) { s in
                        AgentSessionRow(session: s, now: ctx.date)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "terminal").font(.system(size: FS.display)).foregroundStyle(.secondary)
            Text(tr("Chưa có phiên nào", "No sessions yet")).font(.system(size: FS.body, weight: .semibold))
            Text(monitor.hookState.installed
                 ? tr("Mở `claude` hoặc `codex` trong terminal, phiên sẽ hiện ở đây.", "Run `claude` or `codex` in a terminal; sessions appear here.")
                 : tr("Cài hook Claude Code (nút ⚙) để theo dõi. Phiên Codex hiện tự động.", "Install the Claude Code hooks (⚙). Codex sessions appear automatically."))
                .font(.system(size: FS.label)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

struct AgentSessionRow: View {
    let session: AgentSession
    let now: Date

    private var stateColor: Color {
        switch session.state {
        case .running: return Color.accentColor
        case .waitingApproval, .waitingInput: return Tone.warn
        case .subagentDone: return Color.purple
        case .finished: return Tone.good
        case .idle, .ended: return .secondary
        }
    }

    private var stateIcon: String {
        switch session.state {
        case .running: return "circle.dotted"
        case .waitingApproval: return "hand.raised.fill"
        case .waitingInput: return "ellipsis.bubble.fill"
        case .subagentDone: return "sparkles"
        case .finished: return "checkmark.circle.fill"
        case .idle: return "circle"
        case .ended: return "stop.circle"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: AgentStyle.icon(session.provider))
                .font(.system(size: FS.value, weight: .bold))
                .foregroundStyle(AgentStyle.color(session.provider))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: stateIcon).font(.system(size: FS.caption))
                    Text(session.stateLabel).font(.system(size: FS.label, weight: .semibold))
                    Spacer(minLength: 4)
                    if let m = session.shortModel {
                        Text(m).font(.system(size: FS.caption)).foregroundStyle(AgentStyle.color(session.provider)).lineLimit(1)
                    }
                    Text("· " + UsageFormat.elapsed(since: session.startedAt, now: now))
                        .font(.system(size: FS.caption).monospacedDigit()).foregroundStyle(.secondary)
                }
                .foregroundStyle(stateColor)
                Text(session.displayTitle).font(.system(size: FS.body, weight: .semibold)).lineLimit(1)
                HStack(spacing: 8) {
                    if let repo = session.repo {
                        Label(repo, systemImage: "arrow.up.square").lineLimit(1)
                    }
                    if let branch = session.branch {
                        Label(branch, systemImage: "arrow.triangle.branch").lineLimit(1)
                    }
                }
                .font(.system(size: FS.caption))
                .foregroundStyle(.secondary)
                if let text = session.lastPrompt ?? session.lastMessage {
                    Text(text).font(.system(size: FS.label)).foregroundStyle(.primary.opacity(0.8)).lineLimit(2)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Rad.md).fill(Color.primary.opacity(0.04)))
        .help(session.lastMessage ?? "")
    }
}

// MARK: - Hạn mức

struct AgentLimitsView: View {
    @ObservedObject var monitor: AgentMonitor

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            VStack(spacing: 8) {
                ProviderLimitsCard(provider: .claude, snapshot: monitor.claudeLimits, now: ctx.date,
                                   emptyHint: monitor.hookState.statusLine || monitor.oauthEnabled
                                       ? tr("Chưa có số liệu: gửi một lệnh trong Claude Code để statusLine cập nhật.", "No data yet: send one prompt in Claude Code so the status line reports limits.")
                                       : tr("Bật statusLine hoặc OAuth trong ⚙ để xem hạn mức Claude.", "Enable the status line or OAuth in ⚙ to see Claude limits."),
                                   error: monitor.oauthEnabled ? monitor.oauthError : nil)
                ProviderLimitsCard(provider: .codex, snapshot: monitor.codexLimits, now: ctx.date,
                                   emptyHint: tr("Chưa thấy log Codex có hạn mức. Chạy một lượt Codex CLI.", "No Codex rate-limit data in logs yet. Run one Codex CLI turn."),
                                   error: nil)
            }
        }
    }
}

struct ProviderLimitsCard: View {
    let provider: AgentProvider
    let snapshot: LimitSnapshot?
    let now: Date
    let emptyHint: String
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: AgentStyle.icon(provider)).foregroundStyle(AgentStyle.color(provider))
                    .font(.system(size: FS.title, weight: .bold))
                Text(provider.displayName).font(.system(size: FS.title, weight: .semibold))
                if let plan = snapshot?.plan {
                    Text(plan.uppercased()).font(.system(size: FS.caption, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
                }
                Spacer()
                if let snapshot {
                    Text("\(snapshot.source.rawValue) · \(UsageFormat.elapsed(since: snapshot.observedAt, now: now))")
                        .font(.system(size: FS.caption)).foregroundStyle(.secondary)
                }
            }
            if let windows = snapshot?.windows, !windows.isEmpty {
                ForEach(windows) { w in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(w.label.uppercased()).font(.system(size: FS.label, weight: .semibold)).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(w.usedPercent.rounded()))%").font(.system(size: FS.title, weight: .semibold).monospacedDigit())
                        }
                        SegmentBar(percent: w.usedPercent, color: AgentStyle.barColor(w.usedPercent, provider: provider))
                        if let c = UsageFormat.countdown(to: w.resetsAt, now: now) {
                            Label(c, systemImage: "clock.arrow.circlepath")
                                .font(.system(size: FS.caption)).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text(emptyHint).font(.system(size: FS.label)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").font(.system(size: FS.caption)).foregroundStyle(Tone.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Rad.md).fill(Color.primary.opacity(0.04)))
    }
}

// MARK: - Token & chi phí

struct AgentUsageView: View {
    @ObservedObject var monitor: AgentMonitor
    let showCost: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("", selection: $monitor.range) {
                    ForEach(AgentMonitor.UsageRange.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
                Spacer()
                if monitor.isScanning { ProgressView().controlSize(.small) }
                Button { monitor.scanNow() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help(tr("Quét lại transcript", "Rescan transcripts"))
            }
            if let s = monitor.summary {
                totals(s)
                if s.days.count > 1 { DayBars(days: s.days, showCost: showCost) }
                list(title: tr("Theo model", "By model"), rows: Array(s.byModel.prefix(6)))
                list(title: tr("Theo dự án", "By project"), rows: Array(s.byProject.prefix(5)))
                if showCost {
                    Text(tr("Ước tính theo giá API niêm yết; gói thuê bao (Claude Max, ChatGPT Plus/Pro) không tính tiền theo token. “≈” = giá theo dòng model. Sửa giá trong ~/Library/Application Support/MacHub/pricing.json.",
                            "Estimated at public API prices; subscriptions are not billed per token. “≈” = family price. Override in ~/Library/Application Support/MacHub/pricing.json."))
                        .font(.system(size: FS.caption)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding()
            }
        }
    }

    private func value(_ t: UsageSummary.Totals) -> String {
        if showCost {
            return (t.hasEstimate ? "≈" : "") + UsageFormat.usd(t.costUSD)
        }
        return UsageFormat.tokens(t.total)
    }

    @ViewBuilder
    private func totals(_ s: UsageSummary) -> some View {
        HStack(spacing: 8) {
            ForEach(AgentProvider.allCases, id: \.self) { p in
                let t = s.byProvider[p] ?? UsageSummary.Totals()
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: AgentStyle.icon(p)).foregroundStyle(AgentStyle.color(p))
                        Text(p.displayName).font(.system(size: FS.label, weight: .semibold))
                    }
                    Text(value(t)).font(.system(size: FS.display, weight: .bold).monospacedDigit())
                    if showCost {
                        if t.unpricedTokens > 0 {
                            Text(tr("\(UsageFormat.tokens(t.unpricedTokens)) token chưa có giá", "\(UsageFormat.tokens(t.unpricedTokens)) tokens unpriced"))
                                .font(.system(size: FS.caption)).foregroundStyle(Tone.warn)
                        } else {
                            Text(tr("\(t.requests) phản hồi", "\(t.requests) responses")).font(.system(size: FS.caption)).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("in \(UsageFormat.tokens(t.input)) · out \(UsageFormat.tokens(t.output))\ncache \(UsageFormat.tokens(t.cacheRead + t.cacheWrite))")
                            .font(.system(size: FS.caption)).foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Rad.md).fill(Color.primary.opacity(0.04)))
            }
        }
    }

    @ViewBuilder
    private func list(title: String, rows: [UsageSummary.Row]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: FS.label, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(rows) { r in
                    HStack(spacing: 6) {
                        Circle().fill(AgentStyle.color(r.provider)).frame(width: 6, height: 6)
                        Text(PriceBook.normalize(r.name)).font(.system(size: FS.label)).lineLimit(1)
                        Spacer()
                        Text(value(r.totals)).font(.system(size: FS.label, weight: .semibold).monospacedDigit())
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: Rad.md).fill(Color.primary.opacity(0.04)))
        }
    }
}

struct DayBars: View {
    let days: [UsageSummary.Day]
    let showCost: Bool

    private func amount(_ d: UsageSummary.Day, _ p: AgentProvider) -> Double {
        showCost ? (d.cost[p] ?? 0) : Double(d.tokens[p] ?? 0)
    }

    var body: some View {
        let maxV = max(1, days.map { d in AgentProvider.allCases.reduce(0) { $0 + amount(d, $1) } }.max() ?? 1)
        HStack(alignment: .bottom, spacing: days.count > 10 ? 2 : 4) {
            ForEach(days) { d in
                VStack(spacing: 0) {
                    ForEach(AgentProvider.allCases.reversed(), id: \.self) { p in
                        Rectangle().fill(AgentStyle.color(p))
                            .frame(height: CGFloat(amount(d, p) / maxV) * 56)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .bottom)
                .frame(height: 56, alignment: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .help(d.day.formatted(date: .abbreviated, time: .omitted))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Rad.md).fill(Color.primary.opacity(0.04)))
    }
}

// MARK: - Cài đặt

struct AgentSettingsView: View {
    @ObservedObject var monitor: AgentMonitor
    @State private var includeStatusLine = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            section(tr("Claude Code", "Claude Code")) {
                status(tr("Theo dõi phiên", "Session tracking"), on: monitor.hookState.observe)
                status(tr("Duyệt quyền qua MacHub", "Approvals via MacHub"), on: monitor.hookState.approvals)
                status(tr("statusLine (hạn mức 5H/7D)", "Status line (5H/7D limits)"), on: monitor.hookState.statusLine)
                Toggle(tr("Gồm statusLine (vẫn chạy statusLine cũ của bạn bên trong)", "Include status line (your existing one keeps running inside)"),
                       isOn: $includeStatusLine)
                    .font(.system(size: FS.label))
                HStack {
                    Button(monitor.hookState.installed ? tr("Cập nhật hook", "Update hooks") : tr("Cài hook", "Install hooks")) {
                        monitor.installHooks(statusLine: includeStatusLine)
                    }
                    if monitor.hookState.installed {
                        Button(tr("Gỡ", "Remove")) { monitor.uninstallHooks() }
                    }
                }
                .controlSize(.small)
                Text(tr("Sửa ~/.claude/settings.json (có sao lưu). Chỉ thêm mục của MacHub, giữ nguyên cấu hình khác.",
                        "Edits ~/.claude/settings.json (backed up). Only MacHub entries are added; everything else is kept."))
                    .font(.system(size: FS.caption)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let m = monitor.setupMessage {
                    Text(m).font(.system(size: FS.caption)).foregroundStyle(Color.accentColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let e = monitor.serverError {
                    Label(e, systemImage: "exclamationmark.triangle").font(.system(size: FS.caption)).foregroundStyle(Tone.bad)
                }
            }

            section(tr("Duyệt quyền", "Approvals")) {
                Toggle(tr("Hiện yêu cầu quyền của Claude Code trên MacHub", "Show Claude Code permission requests in MacHub"),
                       isOn: $monitor.approvalsEnabled)
                    .font(.system(size: FS.label))
                Stepper(value: $monitor.approvalTimeout, in: 30...300, step: 15) {
                    Text(tr("Chờ \(Int(monitor.approvalTimeout)) giây rồi trả về terminal", "Wait \(Int(monitor.approvalTimeout))s, then fall back to the terminal"))
                        .font(.system(size: FS.label))
                }
                Text(tr("Không trả lời kịp → Claude Code tự hỏi trong terminal như bình thường. MacHub không bao giờ tự cho phép.",
                        "No answer in time → Claude Code asks in the terminal as usual. MacHub never auto-allows."))
                    .font(.system(size: FS.caption)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            section(tr("Hạn mức Claude qua OAuth (tùy chọn)", "Claude limits via OAuth (optional)")) {
                Toggle(tr("Đọc hạn mức từ tài khoản (kể cả 7D theo model)", "Fetch limits from the account (incl. per-model 7D)"),
                       isOn: $monitor.oauthEnabled)
                    .font(.system(size: FS.label))
                Text(tr("Dùng token Claude Code trong Keychain (macOS sẽ hỏi bạn) để gọi api.anthropic.com/api/oauth/usage — endpoint không có tài liệu chính thức, có thể thay đổi. Token không được lưu hay gửi đi nơi khác.",
                        "Uses the Claude Code token from Keychain (macOS will ask) to call api.anthropic.com/api/oauth/usage — an undocumented endpoint that may change. The token is never stored or sent elsewhere."))
                    .font(.system(size: FS.caption)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let e = monitor.oauthError, monitor.oauthEnabled {
                    Label(e, systemImage: "exclamationmark.triangle").font(.system(size: FS.caption)).foregroundStyle(Tone.warn)
                }
            }

            section("Codex") {
                Text(tr("Tự đọc ~/.codex/sessions (phiên, token, hạn mức). Không cần cài gì, không gọi mạng.",
                        "Reads ~/.codex/sessions automatically (sessions, tokens, limits). Nothing to install, no network."))
                    .font(.system(size: FS.caption)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .onAppear {
            monitor.refreshHookState()
            includeStatusLine = monitor.hookState.statusLine || !monitor.hookState.installed
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: FS.body, weight: .semibold))
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Rad.md).fill(Color.primary.opacity(0.04)))
    }

    private func status(_ title: String, on: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Tone.good : .secondary)
            Text(title).font(.system(size: FS.label))
        }
    }
}
