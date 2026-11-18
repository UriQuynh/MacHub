import Foundation

/// Cấu hình vị trí cài đặt helper đặc quyền cho khóa sạc & quạt.
///
/// `/Library/PrivilegedHelperTools` luôn thuộc `root:wheel` (755), user thường không thể ghi đè.
enum PrivilegedHelper {
    static let powerPath = "/Library/PrivilegedHelperTools/com.machub.app.power"
    static let smcPath = "/Library/PrivilegedHelperTools/com.machub.app.smc"
    static let sudoersPath = "/etc/sudoers.d/machub_power"
    static let legacyPowerPath = "/usr/local/bin/machub-power"

    /// v3: đặt helper trong `/Library/PrivilegedHelperTools`, sudoers giới hạn đúng user cài, kiểm tra tham số đầu vào.
    static let requiredVersion = 3

    /// Lệnh `sudo` gọi helper theo đường dẫn tuyệt đối (không phụ thuộc `$PATH`).
    static func sudo(_ arguments: String) -> String {
        "sudo -n \(powerPath) \(arguments)"
    }
}

