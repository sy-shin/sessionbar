import Foundation
import SwiftUI
import Combine
import SessionbarCore

// Synthetic data only. This documentation renderer never creates process observers,
// file readers, notifications, or folder access and never reads real sessions.
@MainActor final class SessionStore: ObservableObject {
    @Published var sessions: [SessionRecord] = []
    @Published var isRefreshing = false
    @Published var diagnostic: String?
    @Published var lastRefresh: Date? = Date()
    @Published var diagnostics: [String] = []
    @Published var activeSessionCount = 5
    @Published var processCount = 5
    @Published var invalidFileCount = 0
    @Published var folderError: String?
    @Published var unreviewed: [String: SessionReviewEvent] = [:]
    @Published var processObservationAvailable = true
    @Published var terminatingSessionIDs = Set<String>()
    let settings: AppSettings
    let english: Bool
    var historyItems: [SessionHistoryItem] = []
    init(english: Bool) {
        self.english = english
        settings = AppSettings()
        settings.sessionDirectories = ["/workspace/example-sessions"]
        let now = Date()
        let projects = ["checkout-api", "website", "mobile-app", "design-system", "docs"]
        let titles = english ? ["Approve the dependency update", "Add search and pagination", "Build the settings screen", "Update button components", "Review the installation guide"] : ["의존성 업데이트를 승인해 주세요", "검색과 페이지네이션 구현", "설정 화면 구현", "버튼 컴포넌트 정리", "설치 가이드 검토"]
        let states: [SessionState] = [.needsAttentionEstimate, .runningEstimate, .runningEstimate, .completed, .idleEstimate]
        let evidence = ["결과가 기록되지 않은 권한 요청", "최근 작업 활동 기록", "최근 작업 활동 기록", "작업 완료 기록", "프로세스 실행 중 · 최근 작업 활동 없음"]
        let terminals = ["Terminal", "iTerm2", "VS Code", "Terminal", "tmux"]
        let seconds = [24, 12, 38, 180, 840]
        for i in 0..<5 {
            sessions.append(SessionRecord(id: "example-session-\(i)", projectPath: "/workspace/\(projects[i])", title: titles[i],
                lastActivity: now.addingTimeInterval(-Double(seconds[i])), state: states[i], source: "cli", evidence: evidence[i],
                runtime: SessionRuntime(processID: Int32(10_000+i), terminalName: terminals[i], processStartTime: 1)))
        }
        for record in sessions where record.state == .needsAttentionEstimate || record.state == .completed { unreviewed[record.id] = SessionReviewEvent(record: record) }
        let historyTitles = english ? ["Update button components", "Add a CSV export", "Fix the empty search state", "Add keyboard shortcuts", "Update the installation guide"] : ["버튼 컴포넌트 정리", "CSV 내보내기 추가", "검색 결과가 없을 때 화면 수정", "키보드 단축키 추가", "설치 가이드 업데이트"]
        for i in 0..<5 {
            historyItems.append(SessionHistoryItem(sessionID: "example-session-\(i)", projectPath: "/workspace/\(projects[i])",
                title: historyTitles[i], date: now.addingTimeInterval(-Double(600+i*1200)), state: .completed))
        }
    }
    func refresh() {}
    func record(id: String) -> SessionRecord? { sessions.first { $0.id == id } }
    func detail(id: String) async -> SessionDetail? {
        let now = Date()
        let response = english ? "Updated the button components.\n\n• Matched spacing across three sizes.\n• Improved keyboard focus visibility.\n• Matched light and dark appearances.\n\nThe build and interaction checks passed." : "버튼 컴포넌트를 수정했습니다.\n\n• 간격과 세 가지 크기를 맞췄습니다.\n• 키보드 포커스 표시를 개선했습니다.\n• 밝은 화면과 어두운 화면의 색상을 맞췄습니다.\n\n빌드와 상호작용 검증을 완료했습니다."
        return SessionDetail(latestResponse: response, activities: [
            SessionActivity(id: "a3", date: now.addingTimeInterval(-180), label: "작업 완료", kind: .completed),
            SessionActivity(id: "a2", date: now.addingTimeInterval(-480), label: "작업 시작", kind: .started),
            SessionActivity(id: "a1", date: now.addingTimeInterval(-500), label: english ? "Request: Update button components" : "요청: 버튼 컴포넌트 정리", kind: .request)
        ])
    }
    func history(from: Date, to: Date) async -> [SessionHistoryItem] { historyItems }
    func openDetail(for session: SessionRecord) {}
    func openDetail(sessionID: String) {}
    func openHistory() {}
    func openDiagnostics() {}
    func connectSessionFolder() {}
    func disconnectSessionFolder(_ path: String) {}
    func returnToSession(id: String) async -> WindowReturnResult { .focused }
    func markReviewed(id: String, token: String) { unreviewed.removeValue(forKey: id) }
    func isDetailVisible(id: String) -> Bool { false }
    func activateOriginApp(id: String) async -> WindowReturnResult { .appActivated }
    func terminateSession(_ session: SessionRecord) async -> String? { nil }
    func refreshNotificationPermission() {}
    func requestNotificationPermission() {}
    func openNotificationSettings() {}
}
