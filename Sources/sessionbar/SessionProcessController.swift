import Foundation
import Darwin
import SessionbarCore

/// Signals only the same owned Codex process observed when the session was listed.
actor SessionProcessController {
    enum Result: Equatable {
        case terminated, unavailable, changed, ambiguous, failed, stillRunning

        var error: String? {
            switch self {
            case .terminated: return nil
            case .unavailable: return "종료할 세션을 확인할 수 없습니다"
            case .changed: return "세션이 변경되었습니다. 새로고침해 주세요"
            case .ambiguous: return "여러 세션이 연결되어 종료할 수 없습니다"
            case .failed: return "세션을 종료할 수 없습니다"
            case .stillRunning: return "세션이 아직 실행 중입니다"
            }
        }
    }

    nonisolated static func startTime(of pid: Int32) -> UInt64? {
        guard pid > 1 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_uid == geteuid(), info.pbi_status != SZOMB else { return nil }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0,
              URL(fileURLWithPath: String(cString: path)).lastPathComponent == "codex" else { return nil }
        return info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec
    }

    func terminate(runtime: SessionRuntime, file: URL) async -> Result {
        let pid = runtime.processID
        guard let expected = runtime.processStartTime else { return .unavailable }
        guard Self.startTime(of: pid) == expected else { return .changed }
        let owners = await CommandRunner.runAsync("/usr/sbin/lsof", ["-n", "-P", "-F", "p", "--", file.path], timeout: 3)
        guard !owners.timedOut, owners.status == 0 else { return .unavailable }
        let codexOwners = Set(owners.output.split(whereSeparator: \.isNewline).compactMap { line -> Int32? in
            guard line.first == "p", let owner = Int32(line.dropFirst()), Self.startTime(of: owner) != nil else { return nil }
            return owner
        })
        guard codexOwners == [pid] else { return codexOwners.count > 1 ? .ambiguous : .changed }
        let files = await CommandRunner.runAsync("/usr/sbin/lsof", ["-a", "-p", String(pid), "-n", "-P", "-F", "ftn"], timeout: 3)
        guard !files.timedOut, files.status == 0 else { return .unavailable }
        if let error = Self.validationError(files.output, expected: file) { return error }
        // Recheck birth time after lsof so a stale or reused PID is rejected.
        guard Self.startTime(of: pid) == expected else { return .changed }
        guard Darwin.kill(pid, SIGTERM) == 0 else { return .failed }
        for _ in 0..<30 {
            if Self.hasExited(pid, expected: expected) { return .terminated }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return .stillRunning
    }

    private nonisolated static func hasExited(_ pid: Int32, expected: UInt64) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size {
            return info.pbi_status == SZOMB || info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec != expected
        }
        return Darwin.kill(pid, 0) == -1 && errno == ESRCH
    }

    nonisolated static func validationError(_ output: String, expected: URL) -> Result? {
        var type = "", paths = Set<URL>()
        for line in output.split(whereSeparator: \.isNewline) {
            let value = String(line.dropFirst())
            switch line.first {
            case "f": type = ""
            case "t": type = value
            case "n" where type == "REG" && value.hasSuffix(".jsonl") && value.contains("/sessions/"):
                paths.insert(URL(fileURLWithPath: value).standardizedFileURL)
            default: break
            }
        }
        guard paths.contains(expected.standardizedFileURL) else { return .changed }
        return paths.count == 1 ? nil : .ambiguous
    }
}
