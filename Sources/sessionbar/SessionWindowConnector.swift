import AppKit
import ApplicationServices
import SessionbarCore

enum WindowReturnResult: Equatable {
    case focused, appActivated, accessibilityRequired, terminalFailure(TerminalFocusFailure), appActivatedWithoutTab, failed(String)
    var message: String? {
        switch self {
        case .focused: return nil
        case .appActivated: return "앱을 열었습니다. 작업 창을 선택해 주세요"
        case .terminalFailure(let failure): return failure.message
        case .appActivatedWithoutTab: return "앱으로 이동했습니다. 세션 탭을 선택해 주세요"
        case .accessibilityRequired: return "창 이동에 접근성 권한이 필요합니다"
        case .failed(let message): return message
        }
    }
}

@MainActor
enum SessionWindowConnector {
    struct WindowDescription { let title: String; let document: String? }

    static func canReturn(_ runtime: SessionRuntime?) -> Bool {
        guard let runtime else { return false }
        return TerminalConnector.canReturn(runtime) || (runtime.originAppProcessID != nil && runtime.terminalBundleID != nil)
    }

    static func focus(_ runtime: SessionRuntime, projectPath: String) async -> WindowReturnResult {
        if TerminalConnector.canReturn(runtime) {
            guard let failure = await TerminalConnector.focusFailure(runtime) else { return .focused }
            let activation = failure == .noMatchingTab ? activateApp(runtime) : nil
            return terminalRecovery(failure, activation: activation)
        }
        guard let app = application(runtime) else { return .failed("세션을 연 앱을 찾을 수 없습니다") }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return .accessibilityRequired }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 2)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return activateApp(runtime) }
        let descriptions = windows.map { WindowDescription(title: attribute($0, kAXTitleAttribute) ?? "",
                                                            document: attribute($0, kAXDocumentAttribute)) }
        let matches = matchingWindows(descriptions, projectPath: projectPath)
        guard matches.count == 1, let index = matches.first else { return activateApp(runtime) }
        let window = windows[index]
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        guard AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success else { return activateApp(runtime) }
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        return app.activate() ? .focused : .failed("앱 창으로 이동할 수 없습니다")
    }

    static func terminalRecovery(_ failure: TerminalFocusFailure, activation: WindowReturnResult?) -> WindowReturnResult {
        failure == .noMatchingTab && activation == .appActivated ? .appActivatedWithoutTab : .terminalFailure(failure)
    }

    static func activateApp(_ runtime: SessionRuntime) -> WindowReturnResult {
        guard let app = application(runtime), app.activate() else {
            return .failed("세션을 연 앱을 찾을 수 없습니다")
        }
        return .appActivated
    }

    private static func application(_ runtime: SessionRuntime) -> NSRunningApplication? {
        guard let pid = runtime.originAppProcessID, let bundleID = runtime.terminalBundleID,
              let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
              app.bundleIdentifier == bundleID else { return nil }
        return app
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func matchingWindows(_ windows: [WindowDescription], projectPath: String) -> [Int] {
        guard projectPath.hasPrefix("/"), projectPath != "/" else { return [] }
        let root = URL(fileURLWithPath: projectPath).standardizedFileURL.path
        let documentMatches = windows.indices.filter { index in
            guard let document = windows[index].document, let url = URL(string: document), url.isFileURL else { return false }
            let path = url.standardizedFileURL.path
            return path == root || path.hasPrefix(root + "/")
        }
        if !documentMatches.isEmpty { return documentMatches }
        let name = URL(fileURLWithPath: root).lastPathComponent
        return windows.indices.filter { index in
            let title = windows[index].title.replacingOccurrences(of: " - ", with: "—")
            return title.components(separatedBy: CharacterSet(charactersIn: "—–|·"))
                .contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == name }
        }
    }
}
