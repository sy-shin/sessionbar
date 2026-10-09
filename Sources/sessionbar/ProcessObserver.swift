import Foundation
import SessionbarCore

struct ProcessSnapshot: Sendable {
    let byFile: [URL: SessionRuntime]
    let codexCount: Int
    let available: Bool
}

actor ProcessObserver {
    private struct Entry {
        let id: Int32
        let parent: Int32
        let tty: String?
        let command: String
    }

    func scan() -> ProcessSnapshot {
        let ps = CommandRunner.run("/bin/ps", ["-axo", "pid=,ppid=,tty=,comm="])
        guard ps.status == 0 else { return ProcessSnapshot(byFile: [:], codexCount: 0, available: false) }
        var processes: [Int32: Entry] = [:]
        for line in ps.output.split(whereSeparator: \.isNewline) {
            let fields = line.split(maxSplits: 3, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            guard fields.count == 4, let id = Int32(fields[0]), let parent = Int32(fields[1]) else { continue }
            let tty = fields[2] == "??" ? nil : "/dev/\(fields[2])"
            processes[id] = Entry(id: id, parent: parent, tty: tty, command: String(fields[3]))
        }
        let codex = processes.values.filter { URL(fileURLWithPath: $0.command).lastPathComponent == "codex" }
        guard !codex.isEmpty else { return ProcessSnapshot(byFile: [:], codexCount: 0, available: true) }
        let ids = codex.map { String($0.id) }.joined(separator: ",")
        let files = CommandRunner.run("/usr/sbin/lsof", ["-a", "-p", ids, "-n", "-P", "-F", "pftn"], timeout: 5)
        guard !files.timedOut, files.status == 0 || files.status == 1 else {
            return ProcessSnapshot(byFile: [:], codexCount: codex.count, available: false)
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
        let panes = tmuxPanes()
        var result: [URL: SessionRuntime] = [:]
        for (pid, url) in rollouts {
            guard let entry = processes[pid] else { continue }
            let tty = entry.tty ?? ttys[pid]
            var parent = entry.parent
            var terminalName: String?
            var bundleID: String?
            var seen = Set<Int32>()
            while let ancestor = processes[parent], seen.insert(parent).inserted {
                let name = URL(fileURLWithPath: ancestor.command).lastPathComponent
                switch name {
                case "Terminal": terminalName = "Terminal"; bundleID = "com.apple.Terminal"
                case "iTerm2": terminalName = "iTerm2"; bundleID = "com.googlecode.iterm2"
                case "ghostty": terminalName = "Ghostty"
                case "wezterm-gui": terminalName = "WezTerm"
                case "Code", "Code Helper", "Code Helper (Plugin)": terminalName = "VS Code"
                default: break
                }
                if terminalName != nil { break }
                parent = ancestor.parent
            }
            let pane = tty.flatMap { panes[$0] }
            if let clientTTY = pane?.clientTTY {
                for client in processes.values where client.tty == clientTTY {
                    var parentID = client.parent
                    var visited = Set<Int32>()
                    while let ancestor = processes[parentID], visited.insert(parentID).inserted {
                        let name = URL(fileURLWithPath: ancestor.command).lastPathComponent
                        if name == "Terminal" { bundleID = "com.apple.Terminal"; break }
                        if name == "iTerm2" { bundleID = "com.googlecode.iterm2"; break }
                        parentID = ancestor.parent
                    }
                    if bundleID != nil { break }
                }
            }
            let runtime = SessionRuntime(processID: pid, tty: tty, terminalName: pane == nil ? terminalName : "tmux",
                                         terminalBundleID: bundleID, tmuxPane: pane?.pane,
                                         tmuxSession: pane?.session, tmuxWindow: pane?.window, tmuxClientTTY: pane?.clientTTY, workingDirectory: workingDirectories[pid])
            if result[url]?.tty == nil || runtime.tty != nil { result[url] = runtime }
        }
        return ProcessSnapshot(byFile: result, codexCount: codex.count, available: true)
    }

    private struct Pane {
        let pane: String
        let session: String
        let window: String
        let clientTTY: String?
    }

    private func tmuxPanes() -> [String: Pane] {
        guard let executable = Self.tmuxExecutable else { return [:] }
        let paneList = CommandRunner.run(executable, ["list-panes", "-a", "-F", "#{pane_tty}\t#{pane_id}\t#{session_name}\t#{window_id}"])
        guard paneList.status == 0 else { return [:] }
        let clientList = CommandRunner.run(executable, ["list-clients", "-F", "#{session_name}\t#{client_tty}"])
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
