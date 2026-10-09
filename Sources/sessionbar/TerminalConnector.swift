import Foundation
import AppKit
import SessionbarCore

@MainActor
enum TerminalConnector {
    private(set) static var lastErrorCode: Int?
    private(set) static var lastResultCode: Int?
    static func canReturn(_ runtime: SessionRuntime?) -> Bool {
        guard let runtime else { return false }
        let tty = runtime.tmuxPane == nil ? runtime.tty : runtime.tmuxClientTTY
        return validTTY(tty) && ["com.apple.Terminal", "com.googlecode.iterm2"].contains(runtime.terminalBundleID ?? "")
    }

    static func focus(_ runtime: SessionRuntime) async -> String? {
        lastErrorCode = nil
        lastResultCode = nil
        guard canReturn(runtime) else { return L10n.text("터미널 위치를 확인할 수 없습니다") }
        if let pane = runtime.tmuxPane, let session = runtime.tmuxSession, let window = runtime.tmuxWindow,
           let client = runtime.tmuxClientTTY, let executable = ProcessObserver.tmuxExecutable {
            let ok = await Task.detached(priority: .userInitiated) {
                let first = CommandRunner.run(executable, ["select-pane", "-t", pane])
                let second = CommandRunner.run(executable, ["select-window", "-t", window])
                let third = CommandRunner.run(executable, ["switch-client", "-c", client, "-t", session])
                return first.status == 0 && second.status == 0 && third.status == 0
            }.value
            guard ok else { return L10n.text("tmux pane으로 이동할 수 없습니다") }
        }
        guard let tty = runtime.tmuxPane == nil ? runtime.tty : runtime.tmuxClientTTY else { return L10n.text("터미널 위치를 확인할 수 없습니다") }
        let source = scriptSource(bundleID: runtime.terminalBundleID ?? "", tty: tty)
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        lastResultCode = result.map { Int($0.int32Value) }
        lastErrorCode = error?[NSAppleScript.errorNumber] as? Int
        if lastErrorCode == -1743 { return L10n.text("터미널 자동화 권한이 필요합니다") }
        if lastErrorCode == -1712 { return L10n.text("터미널이 응답하지 않습니다") }
        if error != nil || lastResultCode != 1 { return L10n.text("터미널 창을 찾을 수 없습니다") }
        return nil
    }

    static func scriptSource(bundleID: String, tty: String) -> String {
        let source: String
        if bundleID == "com.apple.Terminal" {
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
                                return 1
                            end if
                        end repeat
                    end repeat
                end tell
            end timeout
            return 0
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
                                    return 1
                                end if
                            end repeat
                        end repeat
                    end repeat
                end tell
            end timeout
            return 0
            """
        }
        return source
    }

    private static func validTTY(_ tty: String?) -> Bool {
        guard let tty else { return false }
        return tty.range(of: "^/dev/ttys[0-9A-Za-z]+$", options: .regularExpression) != nil
    }
}
