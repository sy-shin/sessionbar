import Foundation
import AppKit
import SessionbarCore

struct ProcessSnapshot: Sendable {
    let byFile: [URL: SessionRuntime]
    let codexCount: Int
    let available: Bool

    func recovering(_ previous: [URL: SessionRuntime], matches: (SessionRuntime) -> Bool) -> ProcessSnapshot {
        available ? self : ProcessSnapshot(byFile: previous.filter { matches($0.value) }, codexCount: codexCount, available: false)
    }
}

actor ProcessObserver {
    private var lastKnownFiles: [URL: SessionRuntime] = [:]
    private var generation: UInt64 = 0

    private func unavailable(count: Int) -> ProcessSnapshot {
        ProcessSnapshot(byFile: [:], codexCount: count, available: false).recovering(lastKnownFiles) { runtime in
            guard let start = runtime.processStartTime else { return false }
            return SessionProcessController.startTime(of: runtime.processID) == start
        }
    }
    private struct Entry {
        let id: Int32
        let parent: Int32
        let tty: String?
        let command: String
        let startTime: UInt64?
    }

    func scan() async -> ProcessSnapshot {
        generation &+= 1
        let scanGeneration = generation
        let ps = await CommandRunner.runAsync("/bin/ps", ["-axo", "pid=,ppid=,tty=,comm="])
        guard ps.status == 0 else { return unavailable(count: 0) }
        var processes: [Int32: Entry] = [:]
        for line in ps.output.split(whereSeparator: \.isNewline) {
            let fields = line.split(maxSplits: 3, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            guard fields.count == 4, let id = Int32(fields[0]), let parent = Int32(fields[1]) else { continue }
            let tty = fields[2] == "??" ? nil : "/dev/\(fields[2])"
            let command = String(fields[3])
            let startTime = URL(fileURLWithPath: command).lastPathComponent == "codex" ? SessionProcessController.startTime(of: id) : nil
            processes[id] = Entry(id: id, parent: parent, tty: tty, command: command, startTime: startTime)
        }
        let codex = processes.values.filter { URL(fileURLWithPath: $0.command).lastPathComponent == "codex" }
        guard !codex.isEmpty else {
            if scanGeneration == generation { lastKnownFiles = [:] }
            return ProcessSnapshot(byFile: [:], codexCount: 0, available: true)
        }
        let ids = codex.map { String($0.id) }.joined(separator: ",")
        let files = await CommandRunner.runAsync("/usr/sbin/lsof", ["-a", "-p", ids, "-n", "-P", "-F", "pftn"], timeout: 5)
        guard !files.timedOut, files.status == 0 || files.status == 1 else {
            return unavailable(count: codex.count)
        }
        var currentPID: Int32?
        var descriptor = "", fileType = ""
        var workingDirectories: [Int32: String] = [:]
        var rollouts: [(Int32, URL)] = []
        var ttys: [Int32: String] = [:]
        for line in files.output.split(whereSeparator: \.isNewline) {
            guard let first = line.first else { continue }
            let value = String(line.dropFirst())
            if first == "p" { currentPID = Int32(value); descriptor = ""; fileType = "" }
            else if first == "f" { descriptor = value; fileType = "" }
            else if first == "t" { fileType = value }
            else if first == "n", let pid = currentPID {
                if descriptor == "cwd", fileType == "DIR" { workingDirectories[pid] = value }
                if value.hasPrefix("/dev/ttys") { ttys[pid] = value }
                if fileType == "REG", value.hasSuffix(".jsonl") && value.contains("/sessions/") {
                    rollouts.append((pid, URL(fileURLWithPath: value).standardizedFileURL))
                }
            }
        }
        let panes = await tmuxPanes()
        var result: [URL: SessionRuntime] = [:]
        for (pid, url) in rollouts {
            guard let entry = processes[pid] else { continue }
            let tty = entry.tty ?? ttys[pid]
            var parent = entry.parent
            var terminalName: String?
            var bundleID: String?
            var originAppPID: Int32?
            var seen = Set<Int32>()
            while let ancestor = processes[parent], seen.insert(parent).inserted {
                let name = URL(fileURLWithPath: ancestor.command).lastPathComponent
                if let app = NSRunningApplication(processIdentifier: parent), app.activationPolicy == .regular {
                    terminalName = app.localizedName ?? name
                    bundleID = app.bundleIdentifier; originAppPID = parent
                    break
                }
                switch name {
                case "Terminal": terminalName = "Terminal"; bundleID = "com.apple.Terminal"; originAppPID = parent
                case "iTerm2": terminalName = "iTerm2"; bundleID = "com.googlecode.iterm2"; originAppPID = parent
                case "ghostty": terminalName = "Ghostty"
                case "wezterm-gui": terminalName = "WezTerm"
                case "Code", "Code Helper", "Code Helper (Plugin)": terminalName = "VS Code"
                default: break
                }
                if originAppPID != nil { break }
                parent = ancestor.parent
            }
            let pane = tty.flatMap { panes[$0] }
            if let clientTTY = pane?.clientTTY {
                for client in processes.values where client.tty == clientTTY {
                    var parentID = client.parent
                    var visited = Set<Int32>()
                    while let ancestor = processes[parentID], visited.insert(parentID).inserted {
                        let name = URL(fileURLWithPath: ancestor.command).lastPathComponent
                        if let app = NSRunningApplication(processIdentifier: parentID), app.activationPolicy == .regular {
                            bundleID = app.bundleIdentifier; originAppPID = parentID; break
                        }
                        if name == "Terminal" { bundleID = "com.apple.Terminal"; originAppPID = parentID; break }
                        if name == "iTerm2" { bundleID = "com.googlecode.iterm2"; originAppPID = parentID; break }
                        parentID = ancestor.parent
                    }
                    if bundleID != nil { break }
                }
            }
            let runtime = SessionRuntime(processID: pid, tty: tty, terminalName: pane == nil ? terminalName : "tmux",
                                         terminalBundleID: bundleID, tmuxPane: pane?.pane,
                                         tmuxSession: pane?.session, tmuxWindow: pane?.window, tmuxClientTTY: pane?.clientTTY, workingDirectory: workingDirectories[pid], processStartTime: entry.startTime, originAppProcessID: originAppPID)
            if result[url]?.tty == nil || runtime.tty != nil { result[url] = runtime }
        }
        if scanGeneration == generation { lastKnownFiles = result }
        return ProcessSnapshot(byFile: result, codexCount: codex.count, available: true)
    }

    private struct Pane {
        let pane: String
        let session: String
        let window: String
        let clientTTY: String?
    }

    private func tmuxPanes() async -> [String: Pane] {
        guard let executable = Self.tmuxExecutable else { return [:] }
        let paneList = await CommandRunner.runAsync(executable, ["list-panes", "-a", "-F", "#{pane_tty}\t#{pane_id}\t#{session_name}\t#{window_id}"])
        guard paneList.status == 0 else { return [:] }
        let clientList = await CommandRunner.runAsync(executable, ["list-clients", "-F", "#{session_name}\t#{client_tty}"])
        var clients: [String: [String]] = [:]
        for line in clientList.output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            if fields.count == 2 { clients[String(fields[0]), default: []].append(String(fields[1])) }
        }
        var result: [String: Pane] = [:]
        for line in paneList.output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 4 else { continue }
            let session = String(fields[2])
            let client = clients[session]?.count == 1 ? clients[session]?.first : nil
            result[String(fields[0])] = Pane(pane: String(fields[1]), session: session, window: String(fields[3]), clientTTY: client)
        }
        return result
    }

    static var tmuxExecutable: String? {
        ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
