// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import AgentKit
import AppKit
import SwiftUI

/// Bảng nổi góc trên-phải hiện yêu cầu duyệt quyền của Claude Code.
///
/// - Không cướp focus (non-activating), không có nút mặc định (Enter KHÔNG cho phép) để tránh bấm nhầm.
/// - Hiện nguyên văn lệnh / đường dẫn sẽ chạy.
@MainActor
final class AgentApprovalPanel {
    static let shared = AgentApprovalPanel()

    private var panel: NSPanel?
    private let model = ApprovalPanelModel()

    func update(with approvals: [PendingApproval]) {
        model.approvals = approvals
        if approvals.isEmpty {
            panel?.orderOut(nil)
            return
        }
        let p = panel ?? makePanel()
        panel = p
        position(p)
        p.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 220),
                        styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                        backing: .buffered, defer: true)
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isFloatingPanel = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = true
        p.standardWindowButton(.closeButton)?.isHidden = true
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden = true
        let host = NSHostingView(rootView: ApprovalPanelView(model: model))
        host.sizingOptions = [.preferredContentSize]
        p.contentView = host
        return p
    }

    private func position(_ p: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        p.layoutIfNeeded()
        let size = p.contentView?.fittingSize ?? NSSize(width: 380, height: 220)
        let f = screen.visibleFrame
        p.setFrame(NSRect(x: f.maxX - size.width - 12, y: f.maxY - size.height - 12, width: size.width, height: size.height),
                   display: true)
    }
}

@MainActor
final class ApprovalPanelModel: ObservableObject {
    @Published var approvals: [PendingApproval] = []
}

struct ApprovalPanelView: View {
    @ObservedObject var model: ApprovalPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill").foregroundStyle(Tone.warn)
                Text(tr("Claude Code xin quyền", "Claude Code needs permission"))
                    .font(.system(size: FS.title, weight: .semibold))
                Spacer()
                if model.approvals.count > 1 {
                    Text("+\(model.approvals.count - 1)").font(.system(size: FS.label)).foregroundStyle(.secondary)
                }
            }
            if let a = model.approvals.first {
                ApprovalCard(approval: a)
            }
        }
        .padding(14)
        .frame(width: 380)
    }
}

struct ApprovalCard: View {
    let approval: PendingApproval

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(approval.toolName)
                    .font(.system(size: FS.label, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
                if let project = approval.project {
                    Text(project).font(.system(size: FS.label)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(UsageFormat.elapsed(since: approval.createdAt, now: ctx.date))
                        .font(.system(size: FS.caption).monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            ScrollView {
                Text(approval.summary)
                    .font(.system(size: FS.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 90)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.primary.opacity(0.05)))
            if let detail = approval.detail, !detail.isEmpty {
                Text(detail).font(.system(size: FS.label)).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: 6) {
                Button(tr("Từ chối", "Deny")) {
                    approval.respond(.deny(message: tr("Người dùng từ chối từ MacHub.", "Denied by the user in MacHub.")))
                }
                Button(tr("Hỏi trong terminal", "Ask in terminal")) { approval.respond(.askInTerminal) }
                    .help(tr("Để Claude Code tự hỏi trong terminal như bình thường", "Let Claude Code prompt in the terminal as usual"))
                Spacer()
                if let s = approval.suggestions {
                    Button(tr("Luôn cho phép", "Always allow")) { approval.respond(.allowAlways(suggestions: s)) }
                        .help(tr("Cho phép và lưu quy tắc Claude Code gợi ý", "Allow and save the rule Claude Code suggested"))
                }
                Button(tr("Cho phép", "Allow")) { approval.respond(.allow) }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
    }
}
