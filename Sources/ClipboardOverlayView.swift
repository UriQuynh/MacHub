import SwiftUI
import AppKit

// MARK: - Clipboard HUD Overlay View (Hallmark Liquid Glass Design)

public struct ClipboardOverlayView: View {
    @ObservedObject var manager: ClipboardManager
    @Environment(\.colorScheme) private var scheme

    // Màu có chủ đích cho HUD: nền gần đặc theo sáng/tối nên chữ luôn đủ tương phản,
    // không phụ thuộc vào thứ nằm phía sau cửa sổ (blur mờ làm chữ chìm trên nền sáng/lộn xộn).
    private var panelBase: Color { scheme == .dark ? Color(white: 0.11) : Color(white: 0.97) }
    private var textSecondary: Color { Color.primary.opacity(scheme == .dark ? 0.72 : 0.66) }
    private var textTertiary: Color { Color.primary.opacity(0.5) }
    private var hairline: Color { Color.primary.opacity(scheme == .dark ? 0.16 : 0.12) }
    private var rowFill: Color { Color.primary.opacity(scheme == .dark ? 0.07 : 0.045) }

    public init(manager: ClipboardManager) {
        self.manager = manager
    }

    public var body: some View {
        ZStack {
            // Nền: blur nhẹ + lớp màu gần đặc để chữ nổi bật
            ZStack {
                VisualEffectBackground(material: .popover, blendingMode: .behindWindow)
                panelBase.opacity(0.9)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(scheme == .dark ? 0.28 : 0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.45), radius: 30, y: 10)

            VStack(spacing: 0) {
                // Top Search & Filter Header
                topSearchBar

                // Filter Category Bar
                categoryBar

                Rectangle().fill(hairline).frame(height: 1)

                // List of Clips
                if manager.filteredItems.isEmpty {
                    emptyStateView
                } else {
                    clipsListView
                }

                Rectangle().fill(hairline).frame(height: 1)

                // Bottom Footer & Hotkey Hints
                footerBar
            }
        }
        .frame(width: 480, height: 560)
    }

    // MARK: - Top Search Bar

    private var topSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: FS.title, weight: .semibold))
                .foregroundStyle(textSecondary)

            TextField("", text: $manager.searchText,
                      prompt: Text(tr("Tìm kiếm clipboard... (1-9 để dán nhanh)", "Search clipboard... (1-9 to paste)"))
                        .foregroundColor(textSecondary))
                .textFieldStyle(.plain)
                .font(.system(size: FS.subhead, weight: .medium))
                .foregroundStyle(.primary)
                .onSubmit {
                    manager.pasteSelectedItem()
                }

            if !manager.searchText.isEmpty {
                Button {
                    manager.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: FS.body))
                        .foregroundStyle(textSecondary)
                }
                .buttonStyle(.plain)
            }

            // Close HUD Button
            Button {
                manager.hideHUD()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: FS.label, weight: .semibold))
                    .foregroundStyle(textSecondary)
                    .padding(5)
                    .background(Circle().fill(Color.primary.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help(tr("Đóng (Esc)", "Close (Esc)"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.05))
    }

    // MARK: - Category Filter Bar

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach([ClipType.all, .text, .image, .url, .file, .color], id: \.self) { type in
                    Button {
                        manager.selectedFilter = type
                    } label: {
                        HStack(spacing: 4) {
                            // Chỉ chip đang chọn hiện icon để cả 6 chip vừa một hàng.
                            if manager.selectedFilter == type {
                                Image(systemName: type.icon)
                                    .font(.system(size: FS.label))
                            }
                            Text(type.title)
                                .font(.system(size: FS.label, weight: manager.selectedFilter == type ? .bold : .medium))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4.5)
                        .background(
                            Capsule().fill(manager.selectedFilter == type ? Color.accentColor : Color.primary.opacity(0.11))
                        )
                        .foregroundStyle(manager.selectedFilter == type ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Clips List View

    private var clipsListView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 5) {
                    ForEach(Array(manager.filteredItems.enumerated()), id: \.element.id) { index, item in
                        clipRow(index: index, item: item)
                            .id(item.id)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Single Clip Row

    private func clipRow(index: Int, item: ClipItem) -> some View {
        let isSelected = manager.selectedIndex == index
        let isHovered = manager.hoveredItemID == item.id
        let shortcutDigit = index < 9 ? "\(index + 1)" : nil

        return Button {
            manager.pasteItem(item)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                // Quick Paste Number Badge (1..9) + Pin Indicator
                ZStack(alignment: .topTrailing) {
                    if let digit = shortcutDigit {
                        Text(digit)
                            .font(.system(size: FS.caption, weight: .bold, design: .rounded))
                            .foregroundStyle(isSelected ? Color.white : (item.isPinned ? Color.orange : textSecondary))
                            .frame(width: 22, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: Rad.sm, style: .continuous)
                                    .fill(item.isPinned
                                          ? Color.orange.opacity(isSelected ? 0.35 : 0.15)
                                          : (isSelected ? Color.accentColor : Color.primary.opacity(0.12)))
                            )
                        if item.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(Color.orange)
                                .offset(x: 3, y: -3)
                        }
                    } else if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: FS.caption))
                            .foregroundStyle(.orange)
                            .frame(width: 22, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: Rad.sm, style: .continuous)
                                    .fill(Color.orange.opacity(isSelected ? 0.35 : 0.15))
                            )
                    } else {
                        Image(systemName: item.type.icon)
                            .font(.system(size: FS.caption))
                            .foregroundStyle(textSecondary)
                            .frame(width: 22, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: Rad.sm, style: .continuous)
                                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.12))
                            )
                    }
                }
                .padding(.top, 2)

                // Content Column
                VStack(alignment: .leading, spacing: 3) {
                    // Header: Source App + Timestamp
                    HStack(spacing: 4) {
                        if let appName = item.sourceAppName, !appName.isEmpty {
                            Text(appName)
                                .font(.system(size: FS.label, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                            Text("•")
                                .font(.system(size: FS.label))
                                .foregroundStyle(textSecondary)
                        }

                        Text(item.relativeTimeText)
                            .font(.system(size: FS.label))
                            .foregroundStyle(textSecondary)

                        Spacer()

                        // Action Buttons on Hover
                        if isHovered || isSelected {
                            HStack(spacing: 5) {
                                if item.isPinned {
                                    // Move Up (⌘↑)
                                    if manager.canMoveUp(id: item.id) {
                                        Button {
                                            manager.movePinnedItem(id: item.id, direction: .up)
                                        } label: {
                                            Image(systemName: "arrow.up")
                                                .font(.system(size: FS.caption, weight: .bold))
                                                .foregroundStyle(textSecondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help(tr("Đổi lên số trước (⌘↑)", "Move up (⌘↑)"))
                                    }

                                    // Move Down (⌘↓)
                                    if manager.canMoveDown(id: item.id) {
                                        Button {
                                            manager.movePinnedItem(id: item.id, direction: .down)
                                        } label: {
                                            Image(systemName: "arrow.down")
                                                .font(.system(size: FS.caption, weight: .bold))
                                                .foregroundStyle(textSecondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help(tr("Đổi xuống số sau (⌘↓)", "Move down (⌘↓)"))
                                    }
                                }

                                // Toggle Pin
                                Button {
                                    manager.togglePin(item)
                                } label: {
                                    Image(systemName: item.isPinned ? "pin.slash.fill" : "pin.fill")
                                        .font(.system(size: FS.caption))
                                        .foregroundStyle(item.isPinned ? .orange : .secondary)
                                }
                                .buttonStyle(.plain)
                                .help(item.isPinned ? tr("Bỏ ghim (⌥P)", "Unpin (⌥P)") : tr("Ghim lên đầu (⌥P)", "Pin to top (⌥P)"))

                                // Delete
                                Button {
                                    manager.deleteItem(item)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: FS.caption))
                                        .foregroundStyle(.red.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                                .help(tr("Xóa mục (⌥⌫)", "Delete item (⌥⌫)"))
                            }
                        }
                    }

                    // Main Content Render by Type
                    switch item.type {
                    case .image:
                        let previewImg: NSImage? = {
                            if let data = item.imageData, let img = NSImage(data: data) {
                                return img
                            }
                            if let data = manager.fullImageData(for: item) {
                                return NSImage(data: data)
                            }
                            return nil
                        }()

                        if let nsImg = previewImg {
                            HStack(spacing: 8) {
                                Image(nsImage: nsImg)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: 160, maxHeight: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: Rad.sm))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Rad.sm)
                                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.system(size: FS.label, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text(item.detail)
                                        .font(.system(size: FS.caption))
                                        .foregroundStyle(textSecondary)
                                }
                            }
                        }

                    case .color:
                        HStack(spacing: 8) {
                            if let hex = item.colorHex {
                                RoundedRectangle(cornerRadius: Rad.sm)
                                    .fill(Color(hex: hex))
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Rad.sm)
                                            .stroke(Color.primary.opacity(0.2), lineWidth: 0.5)
                                    )
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.system(size: FS.body, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.primary)
                                Text(item.detail)
                                    .font(.system(size: FS.caption))
                                    .foregroundStyle(textSecondary)
                            }
                        }

                    case .file:
                        HStack(spacing: 6) {
                            Image(systemName: "doc.fill")
                                .font(.system(size: FS.subhead))
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.system(size: FS.label, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(item.detail)
                                    .font(.system(size: FS.caption))
                                    .foregroundStyle(textSecondary)
                                    .lineLimit(1)
                            }
                        }

                    case .url:
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: "link")
                                    .font(.system(size: FS.caption))
                                    .foregroundStyle(textSecondary)
                                Text(item.title)
                                    .font(.system(size: FS.body, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .lineLimit(1)
                            }
                            Text(item.detail)
                                .font(.system(size: FS.label))
                                .foregroundStyle(textSecondary)
                        }

                    case .text, .rtf, .all:
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(size: FS.body, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            if let text = item.plainText, text != item.title {
                                Text(text.replacingOccurrences(of: "\n", with: " "))
                                    .font(.system(size: FS.label))
                                    .foregroundStyle(textSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Rad.md, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(scheme == .dark ? 0.30 : 0.18) : (isHovered ? Color.primary.opacity(0.10) : rowFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Rad.md, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : hairline.opacity(0.5), lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            manager.hoveredItemID = hovering ? item.id : nil
            if hovering {
                manager.selectedIndex = index
            }
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: FS.huge))
                .foregroundStyle(textTertiary)

            Text(tr("Lịch sử Clipboard trống", "Clipboard History is Empty"))
                .font(.system(size: FS.body, weight: .semibold))
                .foregroundStyle(textSecondary)

            Text(tr("Hãy sao chép (⌘C) văn bản, hình ảnh hoặc tệp tin để lưu vào MacHub.", "Copy (⌘C) text, images or files to save them in MacHub."))
                .font(.system(size: FS.caption))
                .foregroundStyle(textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bottom Footer Bar

    private var footerBar: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Phím tắt: tự xuống dòng theo từng mục, không bẻ chữ giữa chừng
            FlowLayout(spacing: 8) {
                legendItem(key: "↵", label: tr("Dán", "Paste"))
                legendItem(key: "1-9", label: tr("Dán nhanh", "Quick paste"))
                legendItem(key: "⌘↑↓", label: tr("Đổi vị trí", "Reorder"))
                legendItem(key: "⌥P", label: tr("Ghim", "Pin"))
                legendItem(key: "⌥⌫", label: tr("Xóa", "Delete"))
                legendItem(key: "⎋", label: tr("Đóng", "Close"))
            }

            HStack(spacing: 8) {
                Text(tr("\(manager.filteredItems.count) mục", "\(manager.filteredItems.count) items"))
                    .font(.system(size: FS.label, weight: .semibold))
                    .foregroundStyle(textSecondary)

                Spacer()

                Button(tr("Xóa hết", "Clear All")) {
                    manager.clearAllHistory()
                }
                .font(.system(size: FS.label, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Color.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.red.opacity(0.14)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.05))
    }

    private func legendItem(key: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: FS.label, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.primary.opacity(0.14)))
            Text(label)
                .font(.system(size: FS.label))
                .foregroundStyle(textSecondary)
        }
        .lineLimit(1)
        .fixedSize()
    }
}

// MARK: - Color Hex Initializer

private extension Color {
    init(hex: String) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleanHex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
