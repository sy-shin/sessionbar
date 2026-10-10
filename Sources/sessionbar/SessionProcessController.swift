import Foundation
import Darwin
import SessionbarCore

/// Signals only the same owned Codex process observed when the session was listed.
actor SessionProcessController {
    enum Result: Equatable {
        case terminated, unavailable, changed, ambiguous, unsupported, failed, stillRunning

        var error: String? {
            switch self {
            case .terminated: return nil
            case .unavailable: return "종료할 세션을 확인할 수 없습니다"
            case .changed: return "세션이 변경되었습니다. 새로고침해 주세요"
            case .ambiguous: return "여러 세션이 연결되어 종료할 수 없습니다"
            case .unsupported: return "이 세션은 실행한 앱에서 종료해 주세요"
            case .failed: return "세션을 종료할 수 없습니다"
            case .stillRunning: return "세션이 아직 실행 중입니다"
            }
        }
    }

    /// Read arguments only, never the process environment. Do not log the output:
    /// an interactive prompt may be present in the command line.
    nonisolated static func mode(of pid: Int32) async -> SessionProcessMode {
        await modes(of: [pid])[pid] ?? .unknown
    }

    nonisolated static func modes(of pids: [Int32]) async -> [Int32: SessionProcessMode] {
        guard !pids.isEmpty else { return [:] }
        let result = await CommandRunner.runAsync("/bin/ps", ["-ww", "-p", pids.map(String.init).joined(separator: ","), "-o", "pid=", "-o", "tty=", "-o", "args="], timeout: 2)
        guard !result.timedOut, result.status == 0 else { return [:] }
        let requested = Set(pids)
        var modes: [Int32: SessionProcessMode] = [:]
        for line in result.output.split(whereSeparator: \.isNewline) {
            let fields = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard fields.count == 2, let pid = Int32(fields[0]), requested.contains(pid), startTime(of: pid) != nil else { continue }
            var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { continue }
            modes[pid] = classify(String(fields[1]), executable: String(cString: path))
        }
        return modes
    }

    nonisolated static func classify(_ output: String, executable: String) -> SessionProcessMode {
        let fields = output.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard fields.count == 2 else { return .unknown }
        let hasTTY = fields[0] != "??" && fields[0] != "?" && fields[0] != "-"
        let command = String(fields[1])
        let arguments: String
        if command == executable || command == "codex" { arguments = "" }
        else if command.hasPrefix(executable + " ") { arguments = String(command.dropFirst(executable.count + 1)) }
        else if command.hasPrefix("codex ") { arguments = String(command.dropFirst(6)) }
        else {
            // macOS can report /private/var in proc_pidpath while argv[0]
            // retains /var. Match the resolved executable, not a string prefix.
            let parts = command.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard let first = parts.first,
                  URL(fileURLWithPath: String(first)).resolvingSymlinksInPath().path == URL(fileURLWithPath: executable).resolvingSymlinksInPath().path else { return .unknown }
            arguments = parts.count == 2 ? String(parts[1]) : ""
        }
        let words = arguments.split(whereSeparator: \.isWhitespace).map(String.init)
        // ps flattens argument boundaries. Reject service/remote markers anywhere
        // rather than risk classifying a shared backend as a single-session CLI.
        let services: Set<String> = ["app-server", "exec-server", "mcp-server", "mcp", "remote-control", "agents", "daemon", "proxy"]
        if words.contains(where: { services.contains($0) || $0 == "--remote" || $0.hasPrefix("--remote=") }) { return .sharedService }
        let valueOptions: Set<String> = ["-c", "--config", "-m", "--model", "-C", "--cd", "-p", "--profile", "-s", "--sandbox", "-a", "--ask-for-approval", "--enable", "--disable", "--local-provider", "--add-dir"]
        let switches: Set<String> = ["--oss", "--search", "--no-alt-screen", "--no-daemon", "--strict-config", "--worktree", "--approve-for-me", "--dangerously-bypass-approvals-and-sandbox", "--dangerously-bypass-hook-trust"]
        var index = 0
        while index < words.count, words[index].hasPrefix("-") {
            let option = words[index]
            if option == "--" { return hasTTY ? .dedicatedCLI : .unknown }
            if switches.contains(option) { index += 1; continue }
            if valueOptions.contains(option) {
                guard index + 1 < words.count else { return .unknown }
                index += 2; continue
            }
            if let equal = option.firstIndex(of: "="), valueOptions.contains(String(option[..<equal])) { index += 1; continue }
            return .unknown
        }
        guard index < words.count else { return hasTTY ? .dedicatedCLI : .unknown }
        if ["exec", "e", "review", "resume", "fork"].contains(words[index]) { return .dedicatedCLI }
        // An initial prompt is allowed only in an actual terminal. Headless
        // processes must explicitly identify a supported single-session command.
        let otherCommands: Set<String> = ["app", "archive", "delete", "unarchive", "queue", "migrate-rollouts", "login", "logout", "completion", "update", "doctor", "sandbox", "debug", "apply", "a", "features", "help"]
        if otherCommands.contains(words[index]) { return .unknown }
        return hasTTY ? .dedicatedCLI : .unknown
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
        guard await Self.mode(of: pid) == .dedicatedCLI else { return .unsupported }
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
