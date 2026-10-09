import Foundation
import AppKit
import SessionbarCore

@MainActor
enum TerminalConnector {
    static func canReturn(_ runtime: SessionRuntime?) -> Bool {
        guard let runtime else { return false }
        let tty = runtime.tmuxPane == nil ? runtime.tty : runtime.tmuxClientTTY
        return validTTY(tty) && ["com.apple.Terminal", "com.googlecode.iterm2"].contains(runtime.terminalBundleID ?? "")
    }

    static func focus(_ runtime: SessionRuntime) async -> String? {
        guard canReturn(runtime) else { return "터미널 위치를 확인할 수 없습니다" }
        if let pane = runtime.tmuxPane, let session = runtime.tmuxSession, let window = runtime.tmuxWindow,
           let client = runtime.tmuxClientTTY, let executable = ProcessObserver.tmuxExecutable {
            let ok = await Task.detached(priority: .userInitiated) {
                let first = CommandRunner.run(executable, ["select-pane", "-t", pane])
                let second = CommandRunner.run(executable, ["select-window", "-t", window])
                let third = CommandRunner.run(executable, ["switch-client", "-c", client, "-t", session])
                return first.status == 0 && second.status == 0 && third.status == 0
            }.value
            guard ok else { return "tmux pane으로 이동할 수 없습니다" }
        }
        guard let tty = runtime.tmuxPane == nil ? runtime.tty : runtime.tmuxClientTTY else { return "터미널 위치를 확인할 수 없습니다" }
        let source: String
        if runtime.terminalBundleID == "com.apple.Terminal" {
            source = """
            with timeout of 10 seconds
                tell application id "com.apple.Terminal"
                    repeat with targetWindow in windows
                        repeat with targetTab in tabs of targetWindow
                            if tty of targetTab is "\(tty)" then
                                set selected tab of targetWindow to targetTab
                                set miniaturized of targetWindow to false
                                set index of targetWindow to 1
                                activate
                                return true
                            end if
                        end repeat
                    end repeat
                end tell
            end timeout
            return false
            """
        } else {
            source = """
            with timeout of 10 seconds
                tell application id "com.googlecode.iterm2"
                    repeat with targetWindow in windows
                        repeat with targetTab in tabs of targetWindow
                            repeat with targetSession in sessions of targetTab
                                if tty of targetSession is "\(tty)" then
                                    select targetSession
                                    select targetTab
                                    select targetWindow
                                    activate
                                    return true
                                end if
                            end repeat
                        end repeat
                    end repeat
                end tell
            end timeout
            return false
            """
        }
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let code = error?[NSAppleScript.errorNumber] as? Int, code == -1743 { return "터미널 자동화 권한이 필요합니다" }
        if error != nil || result?.booleanValue != true { return "터미널 창을 찾을 수 없습니다" }
        return nil
    }

    private static func validTTY(_ tty: String?) -> Bool {
        guard let tty else { return false }
        return tty.range(of: "^/dev/ttys[0-9A-Za-z]+$", options: .regularExpression) != nil
    }
}
