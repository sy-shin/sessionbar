import Foundation
import AppKit
import UserNotifications
import SessionbarCore

@MainActor
final class NotificationService {
    private let center = UNUserNotificationCenter.current()
    private let settings: AppSettings
    private let coordinator = NotificationCoordinator()
    private var tracker = NotificationTracker()
    private var currentRecords: [String: SessionRecord] = [:]
    private var authorizationInFlight = false
    var onOpenSession: ((String) -> Void)?
    var onPermissionGranted: (() -> Void)?

    init(settings: AppSettings) {
        self.settings = settings
        coordinator.onOpenSession = { [weak self] in self?.onOpenSession?($0) }
        center.delegate = coordinator
        refreshPermission()
    }

    private var preferences: NotificationPreferences {
        var value = NotificationPreferences()
        value.attention = settings.attentionNotifications
        value.completion = settings.completionNotifications
        value.error = settings.errorNotifications
        value.quietHours = settings.quietHours
        value.quietStart = settings.quietStart; value.quietEnd = settings.quietEnd
        value.pauseUntil = settings.pauseUntil; value.cooldownMinutes = settings.cooldownMinutes
        return value
    }

    private func updatePermission(_ configuration: UNNotificationSettings) {
        switch configuration.authorizationStatus {
        case .authorized, .provisional, .ephemeral: settings.notificationPermission = .allowed
        case .notDetermined: settings.notificationPermission = .notRequested
        case .denied: settings.notificationPermission = .denied
        @unknown default: settings.notificationPermission = .unavailable
        }
        settings.notificationBannersDisabled = settings.notificationPermission == .allowed && configuration.alertSetting == .disabled
        if settings.notificationPermission == .allowed { settings.notificationError = nil }
    }

    func refreshPermission() {
        Task { updatePermission(await center.notificationSettings()) }
    }

    func requestPermission(for state: SessionState? = nil) {
        guard !authorizationInFlight else { return }
        authorizationInFlight = true
        Task {
            defer { authorizationInFlight = false }
            let configuration = await center.notificationSettings()
            updatePermission(configuration)
            if configuration.authorizationStatus == .denied { openSystemSettings(); return }
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                updatePermission(await center.notificationSettings())
                if granted {
                    if state == .needsAttentionEstimate { tracker.resetAttention() }
                    onPermissionGranted?()
                }
            } catch {
                updatePermission(await center.notificationSettings())
                settings.notificationError = "알림 권한을 요청할 수 없습니다"
            }
        }
    }

    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?bundleId=io.sessionbar.app")!
        if !NSWorkspace.shared.open(url) { settings.notificationError = "알림 설정을 열 수 없습니다" }
    }

    func observe(_ records: [SessionRecord], now: Date = .now) {
        currentRecords = records.reduce(into: [:]) { $0[$1.id] = $1 }
        if let until = settings.pauseUntil, until <= now { settings.pauseUntil = nil }
        for record in tracker.observe(records, preferences: preferences, now: now) {
            Task { await deliver(record) }
        }
    }

    private func deliver(_ record: SessionRecord) async {
        let configuration = await center.notificationSettings()
        updatePermission(configuration)
        guard let current = currentRecords[record.id], current.eventToken == record.eventToken,
              !current.isRuntimeStale else { return }
        guard settings.notificationPermission == .allowed else {
            tracker.deliveryFailed(record)
            if settings.notificationPermission == .notRequested { requestPermission() }
            return
        }
        let enabled: Bool
        switch record.state {
        case .needsAttentionEstimate: enabled = settings.attentionNotifications && current.runtime != nil
        case .completed: enabled = settings.completionNotifications
        case .error: enabled = settings.errorNotifications
        default: enabled = false
        }
        guard enabled else { return }
        guard preferences.allowsDelivery(at: .now) else { tracker.deliveryFailed(record); return }
        let content = UNMutableNotificationContent()
        switch record.state {
        case .needsAttentionEstimate: content.title = L10n.text("Codex 확인 필요 추정")
        case .error: content.title = L10n.text("Codex 오류")
        default: content.title = L10n.text("Codex 작업 완료")
        }
        content.body = record.projectName.isEmpty ? L10n.text("Codex 세션") : record.projectName
        content.sound = settings.sound ? .default : nil
        content.userInfo = ["sessionID": record.id]
        let request = UNNotificationRequest(identifier: "sessionbar-\(record.id)-\(record.state.rawValue)", content: content, trigger: nil)
        do { try await center.add(request) }
        catch { tracker.deliveryFailed(record); settings.notificationError = "알림을 표시할 수 없습니다" }
    }
}
