import Foundation
import AppKit
import SessionbarCore

enum TerminalFocusFailure: Equatable {
    case unsupported, permissionDenied, timedOut, noMatchingTab, automationFailed, tmuxUnavailable
    var message: String {
        switch self {
        case .unsupported: return "터미널 위치를 확인할 수 없습니다"
        case .permissionDenied: return "터미널 자동화 권한이 필요합니다"
        case .timedOut: return "터미널이 응답하지 않습니다"
        case .noMatchingTab: return "세션이 열린 터미널 탭을 찾을 수 없습니다"
        case .automationFailed: return "터미널 창을 조회할 수 없습니다"
        case .tmuxUnavailable: return "tmux pane으로 이동할 수 없습니다"
        }
    }
}

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
        let failure = await focusFailure(runtime)
        return failure.map { L10n.text($0.message) }
    }

    static func focusFailure(_ runtime: SessionRuntime) async -> TerminalFocusFailure? {
        lastErrorCode = nil
        lastResultCode = nil
        guard canReturn(runtime) else { return .unsupported }
        if let pane = runtime.tmuxPane {
            guard let session = runtime.tmuxSession, let window = runtime.tmuxWindow,
                  let client = runtime.tmuxClientTTY, let executable = ProcessObserver.tmuxExecutable else { return .tmuxUnavailable }
            let ok = await Task.detached(priority: .userInitiated) {
                let first = CommandRunner.run(executable, ["select-pane", "-t", pane])
                let second = CommandRunner.run(executable, ["select-window", "-t", window])
                let third = CommandRunner.run(executable, ["switch-client", "-c", client, "-t", session])
                return first.status == 0 && second.status == 0 && third.status == 0
            }.value
            guard ok else { return .tmuxUnavailable }
        }
        guard let tty = runtime.tmuxPane == nil ? runtime.tty : runtime.tmuxClientTTY else { return .unsupported }
        let source = scriptSource(bundleID: runtime.terminalBundleID ?? "", tty: tty)
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        lastResultCode = result.map { Int($0.int32Value) }
        lastErrorCode = error?[NSAppleScript.errorNumber] as? Int
        return classifyFailure(errorCode: lastErrorCode, resultCode: lastResultCode, hadError: error != nil)
    }

    static func classifyFailure(errorCode: Int?, resultCode: Int?, hadError: Bool) -> TerminalFocusFailure? {
        if errorCode == -1743 { return .permissionDenied }
        if errorCode == -1712 { return .timedOut }
        if hadError || errorCode != nil { return .automationFailed }
        if resultCode == 0 { return .noMatchingTab }
        return resultCode == 1 ? nil : .automationFailed
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
