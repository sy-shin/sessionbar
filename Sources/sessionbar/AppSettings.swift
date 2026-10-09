import Foundation
import Combine
import ServiceManagement
import SessionbarCore

@MainActor
final class AppSettings: ObservableObject {
    @Published var language: AppLanguage { didSet { persist() } }
    @Published var retentionDays: Int { didSet { persist() } }
    @Published var refreshInterval: Int { didSet { persist() } }
    @Published var compactMenu: Bool { didSet { persist() } }
    @Published var watchFiles: Bool { didSet { persist() } }
    @Published var sessionDirectories: [String] { didSet { persist() } }
    @Published var attentionNotifications: Bool {
        didSet { persist(); if attentionNotifications { onEnableNotifications?(.needsAttentionEstimate) } }
    }
    @Published var completionNotifications: Bool {
        didSet { persist(); if completionNotifications { onEnableNotifications?(.completed) } }
    }
    @Published var errorNotifications: Bool {
        didSet { persist(); if errorNotifications { onEnableNotifications?(.error) } }
    }
    @Published var sound: Bool { didSet { persist() } }
    @Published var quietHours: Bool { didSet { persist() } }
    @Published var quietStart: Int { didSet { persist() } }
    @Published var quietEnd: Int { didSet { persist() } }
    @Published var cooldownMinutes: Int { didSet { persist() } }
    @Published var pauseUntil: Date? { didSet { persist() } }
    @Published private(set) var launchAtLogin = false
    @Published private(set) var loginNeedsApproval = false
    @Published private(set) var loginError: String?
    @Published var notificationError: String?
    var onChange: (() -> Void)?
    var onEnableNotifications: ((SessionState) -> Void)?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let prefix = "sessionbar."
        language = AppLanguage(rawValue: defaults.string(forKey: prefix + "language") ?? "system") ?? .system
        defaults.register(defaults: [prefix + "retentionDays": 30, prefix + "refreshInterval": 15,
            prefix + "sound": true, prefix + "quietStart": 22, prefix + "quietEnd": 8,
            prefix + "cooldownMinutes": 10, prefix + "watchFiles": true, prefix + "attentionNotifications": true])
        retentionDays = max(0, defaults.integer(forKey: prefix + "retentionDays"))
        refreshInterval = max(5, defaults.integer(forKey: prefix + "refreshInterval"))
        compactMenu = defaults.bool(forKey: prefix + "compactMenu")
        watchFiles = defaults.bool(forKey: prefix + "watchFiles")
        sessionDirectories = defaults.stringArray(forKey: prefix + "sessionDirectories") ??
            [FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/sessions").path]
        attentionNotifications = defaults.bool(forKey: prefix + "attentionNotifications")
        completionNotifications = defaults.bool(forKey: prefix + "completionNotifications")
        errorNotifications = defaults.bool(forKey: prefix + "errorNotifications")
        sound = defaults.bool(forKey: prefix + "sound")
        quietHours = defaults.bool(forKey: prefix + "quietHours")
        quietStart = min(23, max(0, defaults.integer(forKey: prefix + "quietStart")))
        quietEnd = min(23, max(0, defaults.integer(forKey: prefix + "quietEnd")))
        cooldownMinutes = max(1, defaults.integer(forKey: prefix + "cooldownMinutes"))
        let timestamp = defaults.double(forKey: prefix + "pauseUntil")
        pauseUntil = timestamp > Date().timeIntervalSince1970 ? Date(timeIntervalSince1970: timestamp) : nil
        refreshLoginStatus()
    }

    private func persist() {
        let values: [String: Any] = ["language": language.rawValue, "retentionDays": retentionDays, "refreshInterval": refreshInterval,
            "compactMenu": compactMenu, "watchFiles": watchFiles, "sessionDirectories": sessionDirectories,
            "attentionNotifications": attentionNotifications, "completionNotifications": completionNotifications,
            "errorNotifications": errorNotifications, "sound": sound, "quietHours": quietHours,
            "quietStart": quietStart, "quietEnd": quietEnd, "cooldownMinutes": cooldownMinutes,
            "pauseUntil": pauseUntil?.timeIntervalSince1970 ?? 0]
        for (key, value) in values { defaults.set(value, forKey: "sessionbar." + key) }
        onChange?()
    }

    func pauseForHour() { pauseUntil = Date().addingTimeInterval(3_600) }
    func resumeNotifications() { pauseUntil = nil }

    func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled || status == .requiresApproval
        loginNeedsApproval = status == .requiresApproval
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch { loginError = "자동 실행 설정을 변경할 수 없습니다" }
        refreshLoginStatus()
    }
}
