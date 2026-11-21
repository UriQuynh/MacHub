#!/bin/bash
# Đo CPU/RSS của lần quét log Agent đầu tiên (AgentUsageScanner) trên một thư mục log thật hoặc bản sao.
#   ./scripts/bench-agent-scan.sh                       # ~/.claude/projects và ~/.codex/sessions
#   ./scripts/bench-agent-scan.sh /đường/dẫn/claude /đường/dẫn/codex   # thư mục chứa projects/ và sessions/
# In: thời gian từng lần quét, mã băm kết quả (để so sánh trước/sau khi sửa), và `/usr/bin/time -l` (CPU, RSS tối đa).
# Mẹo: bản sao copy-on-write để đo trên dữ liệu đứng yên: cp -cpR ~/.claude/projects "$DIR/claude/projects"
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/Sources/bench"
ln -s "$ROOT/Sources/AgentKit" "$TMP/Sources/AgentKit"
ln -s "$ROOT/Sources/Agents/AgentUsageScanner.swift" "$TMP/Sources/bench/AgentUsageScanner.swift"
cat > "$TMP/Package.swift" <<'PKG'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "bench",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "AgentKit", path: "Sources/AgentKit"),
        .executableTarget(name: "bench", dependencies: ["AgentKit"], path: "Sources/bench"),
    ]
)
PKG
cat > "$TMP/Sources/bench/main.swift" <<'SWIFT'
import AgentKit
import Foundation

func run(_ label: String, _ scanner: AgentUsageScanner) -> AgentUsageScanner.Result {
    let sem = DispatchSemaphore(value: 0)
    var res: AgentUsageScanner.Result!
    let t0 = Date()
    scanner.scan { r in res = r; sem.signal() }
    sem.wait()
    FileHandle.standardError.write(Data(String(format: "%@: %.2fs\n", label, Date().timeIntervalSince(t0)).utf8))
    return res
}

/// Băm (FNV-1a) toàn bộ bản ghi và phiên Codex đã sắp xếp: hai bản mã cho cùng số liệu ⇔ cùng mã băm.
func digest(_ r: AgentUsageScanner.Result) -> String {
    func fnv(_ lines: [String]) -> String {
        var h: UInt64 = 14695981039346656037
        for l in lines.sorted() { for b in l.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }; h = (h ^ 10) &* 1099511628211 }
        return String(h, radix: 16)
    }
    let recs = r.records.map { "\($0.provider.rawValue)|\($0.timestamp.timeIntervalSince1970)|\($0.model)|\($0.project ?? "-")|\($0.sessionID ?? "-")|\($0.inputTokens)|\($0.outputTokens)|\($0.cacheWrite5mTokens)|\($0.cacheWrite1hTokens)|\($0.cacheReadTokens)" }
    let sess = r.codexSessions.map { "\($0.path)|\($0.sessionID)|\($0.state.rawValue)|\($0.totalTokens)|\($0.lastActivity?.timeIntervalSince1970 ?? 0)|\($0.lastUserMessage ?? "")|\($0.lastAgentMessage ?? "")|\($0.model ?? "")|\($0.cwd ?? "")" }
    return "records=\(r.records.count) tokens=\(r.records.reduce(0) { $0 + $1.totalTokens }) recDigest=\(fnv(recs)) codexSessions=\(r.codexSessions.count) sessDigest=\(fnv(sess))"
}

let scanner = AgentUsageScanner()
// Quét lặp tới khi ổn định (bản cũ chỉ đọc 64 MB mỗi file mỗi lần quét nên cần nhiều lần mới đủ).
var last = ""
for i in 1...6 {
    let d = digest(run("scan#\(i)", scanner))
    if d == last { break }
    last = d
}
print(last)
SWIFT
cd "$TMP" && swift build -c release 2>&1 | grep -E "error|warning: unre" || true
if [ $# -ge 2 ]; then export CLAUDE_CONFIG_DIR="$1" CODEX_HOME="$2"; fi
/usr/bin/time -l "$TMP/.build/release/bench"
