import Foundation
import UserNotifications
import SessionbarCore

@MainActor
final class NotificationService {
    private let center = UNUserNotificationCenter.current()
    private let settings: AppSettings
    private let coordinator = NotificationCoordinator()
    private var tracker = NotificationTracker()
    var onOpenSession: ((String) -> Void)?

    init(settings: AppSettings) {
        self.settings = settings
        coordinator.onOpenSession = { [weak self] in self?.onOpenSession?($0) }
        center.delegate = coordinator
    }

    func requestPermission(for state: SessionState) {
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            Task { @MainActor in
                guard let self else { return }
                self.settings.notificationError = granted ? nil : "알림 권한 없음"
                if granted && state == .needsAttentionEstimate { self.tracker.resetAttention() }
                if !granted {
                    switch state {
                    case .needsAttentionEstimate: self.settings.attentionNotifications = false
                    case .completed: self.settings.completionNotifications = false
                    case .error: self.settings.errorNotifications = false
                    default: break
                    }
                }
            }
        }
    }

    func observe(_ records: [SessionRecord], now: Date = .now) {
        if let until = settings.pauseUntil, until <= now { settings.pauseUntil = nil }
        var preferences = NotificationPreferences()
        preferences.attention = settings.attentionNotifications
        preferences.completion = settings.completionNotifications
        preferences.error = settings.errorNotifications
        preferences.quietHours = settings.quietHours
        preferences.quietStart = settings.quietStart
        preferences.quietEnd = settings.quietEnd
        preferences.pauseUntil = settings.pauseUntil
        preferences.cooldownMinutes = settings.cooldownMinutes
        for record in tracker.observe(records, preferences: preferences, now: now) { deliver(record) }
    }

    private func deliver(_ record: SessionRecord) {
        let content = UNMutableNotificationContent()
        switch record.state {
        case .needsAttentionEstimate: content.title = "Codex 확인 필요 추정"
        case .error: content.title = "Codex 오류"
        default: content.title = "Codex 작업 완료"
        }
        content.body = record.projectName.isEmpty ? "Codex 세션" : record.projectName
        content.sound = settings.sound ? .default : nil
        content.userInfo = ["sessionID": record.id]
        let request = UNNotificationRequest(identifier: "sessionbar-\(record.id)-\(record.state.rawValue)", content: content, trigger: nil)
        center.add(request) { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in self?.settings.notificationError = "알림을 표시할 수 없습니다" }
        }
    }
}
