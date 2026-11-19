// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import Darwin
import Foundation

/// Socket Unix cục bộ, giao thức: mỗi thông điệp là MỘT dòng JSON kết thúc bằng `\n`.
///
/// An toàn:
/// - File socket quyền 0600 trong thư mục 0700 của user.
/// - Mỗi kết nối được kiểm tra `getpeereid`: chỉ chấp nhận tiến trình cùng UID.
/// - Giới hạn kích thước thông điệp (`maxMessageBytes`).
public final class UnixSocketServer: @unchecked Sendable {
    /// Kênh trả lời cho một kết nối. Gọi `send(nil)` để đóng mà không trả lời.
    public final class Reply: @unchecked Sendable {
        fileprivate weak var connection: Connection?
        private let lock = NSLock()
        private var closeHandlers: [() -> Void] = []
        private var finished = false

        public var isOpen: Bool {
            lock.lock(); defer { lock.unlock() }
            return !finished
        }

        /// Gọi khi phía hook đóng kết nối (vd. hết thời gian chờ) trước khi app trả lời.
        public func onClose(_ handler: @escaping () -> Void) {
            lock.lock()
            if finished { lock.unlock(); handler(); return }
            closeHandlers.append(handler)
            lock.unlock()
        }

        public func send(_ data: Data?) {
            lock.lock()
            guard !finished else { lock.unlock(); return }
            finished = true
            closeHandlers.removeAll()
            lock.unlock()
            connection?.finish(reply: data)
        }

        fileprivate func peerClosed() {
            lock.lock()
            guard !finished else { lock.unlock(); return }
            finished = true
            let handlers = closeHandlers
            closeHandlers.removeAll()
            lock.unlock()
            handlers.forEach { $0() }
        }
    }

    public typealias Handler = (_ message: Data, _ reply: Reply) -> Void

    public static let maxMessageBytes = 8 * 1024 * 1024

    public let path: String
    private let handler: Handler
    private let queue = DispatchQueue(label: "com.machub.app.agent-socket")
    private var listenFD: Int32 = -1
    private var listenSource: DispatchSourceRead?
    private var connections: [ObjectIdentifier: Connection] = [:]

    public init(path: String, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    deinit { stop() }

    public enum SocketError: Error, CustomStringConvertible {
        case pathTooLong
        case system(String, Int32)
        public var description: String {
            switch self {
            case .pathTooLong: return "Đường dẫn socket quá dài"
            case .system(let call, let code): return "\(call) lỗi: \(String(cString: strerror(code)))"
            }
        }
    }

    public func start() throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        chmod(dir, 0o700)
        unlink(path) // socket cũ từ lần chạy trước

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.system("socket", errno) }

        var addr = sockaddr_un()
        guard UnixSocketServer.fill(&addr, path: path) else {
            close(fd)
            throw SocketError.pathTooLong
        }
        let oldMask = umask(0o177)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        umask(oldMask)
        guard bound == 0 else {
            let e = errno
            close(fd)
            throw SocketError.system("bind", e)
        }
        chmod(path, 0o600)
        guard listen(fd, 32) == 0 else {
            let e = errno
            close(fd)
            throw SocketError.system("listen", e)
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        listenFD = fd

        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in self?.acceptAll() }
        src.resume()
        listenSource = src
    }

    public func stop() {
        listenSource?.cancel()
        listenSource = nil
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
            unlink(path)
        }
        queue.sync {
            connections.values.forEach { $0.cancel() }
            connections.removeAll()
        }
    }

    static func fill(_ addr: inout sockaddr_un, path: String) -> Bool {
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count < capacity else { return false }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return true
    }

    private func acceptAll() {
        while true {
            let client = accept(listenFD, nil, nil)
            if client < 0 { return }
            var uid: uid_t = 0
            var gid: gid_t = 0
            guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else {
                close(client)
                continue
            }
            var one: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) | O_NONBLOCK)
            let conn = Connection(fd: client, queue: queue, handler: handler) { [weak self] c in
                self?.connections.removeValue(forKey: ObjectIdentifier(c))
            }
            connections[ObjectIdentifier(conn)] = conn
            conn.start()
        }
    }

    fileprivate final class Connection {
        let fd: Int32
        let queue: DispatchQueue
        let handler: Handler
        let onDone: (Connection) -> Void
        var source: DispatchSourceRead?
        var buffer = Data()
        var reply: Reply?
        var closed = false

        init(fd: Int32, queue: DispatchQueue, handler: @escaping Handler, onDone: @escaping (Connection) -> Void) {
            self.fd = fd
            self.queue = queue
            self.handler = handler
            self.onDone = onDone
        }

        func start() {
            let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            src.setEventHandler { [weak self] in self?.readAvailable() }
            src.resume()
            source = src
        }

        private func readAvailable() {
            var chunk = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let n = read(fd, &chunk, chunk.count)
                if n > 0 {
                    if reply != nil { continue } // đã nhận đủ 1 thông điệp: bỏ qua dữ liệu thừa
                    buffer.append(contentsOf: chunk[0..<n])
                    if buffer.count > UnixSocketServer.maxMessageBytes { cancel(); return }
                    if let nl = buffer.firstIndex(of: 0x0A) {
                        let message = buffer.subdata(in: buffer.startIndex..<nl)
                        buffer.removeAll()
                        let r = Reply()
                        r.connection = self
                        reply = r
                        handler(message, r)
                    }
                } else if n == 0 {
                    // Phía hook đóng kết nối.
                    reply?.peerClosed()
                    cancel()
                    return
                } else {
                    if errno == EAGAIN || errno == EWOULDBLOCK { return }
                    reply?.peerClosed()
                    cancel()
                    return
                }
            }
        }

        func finish(reply data: Data?) {
            queue.async { [self] in
                guard !closed else { return }
                if var data {
                    data.append(0x0A)
                    // Trả lời nhỏ (<64KB): chuyển sang chế độ blocking để ghi gọn.
                    _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
                    data.withUnsafeBytes { raw in
                        var off = 0
                        while off < raw.count {
                            let w = write(fd, raw.baseAddress! + off, raw.count - off)
                            if w <= 0 { break }
                            off += w
                        }
                    }
                }
                cancel()
            }
        }

        func cancel() {
            guard !closed else { return }
            closed = true
            source?.cancel()
            source = nil
            close(fd)
            onDone(self)
        }
    }
}

/// Phía hook: gửi một dòng JSON và (tùy chọn) chờ một dòng trả lời.
public enum UnixSocketClient {
    public enum Result: Equatable {
        case notRunning          // không có app nào lắng nghe
        case sent                // đã gửi, không chờ trả lời
        case reply(Data)
        case noReply             // app đóng kết nối không trả lời, hoặc hết giờ
    }

    public static func send(_ message: Data, to path: String, waitReply: Bool, timeout: TimeInterval) -> Result {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return .notRunning }
        defer { close(fd) }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_un()
        guard UnixSocketServer.fill(&addr, path: path) else { return .notRunning }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard ok == 0 else { return .notRunning }

        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - floor(timeout)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var payload = message
        payload.append(0x0A)
        let written = payload.withUnsafeBytes { raw -> Bool in
            var off = 0
            while off < raw.count {
                let w = write(fd, raw.baseAddress! + off, raw.count - off)
                if w <= 0 { return false }
                off += w
            }
            return true
        }
        guard written else { return .notRunning }
        guard waitReply else { return .sent }

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(contentsOf: chunk[0..<n])
            if let nl = buffer.firstIndex(of: 0x0A) {
                return .reply(buffer.subdata(in: buffer.startIndex..<nl))
            }
            if buffer.count > UnixSocketServer.maxMessageBytes { break }
        }
        return .noReply
    }
}
