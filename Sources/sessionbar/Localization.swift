import Foundation
import SwiftUI
import SessionbarCore

enum AppLanguage: String, CaseIterable {
    case system, korean = "ko", english = "en"
    var locale: Locale {
        if self == .system {
            return Locale(identifier: Locale.preferredLanguages.first?.hasPrefix("ko") == true ? "ko" : "en")
        }
        return Locale(identifier: rawValue)
    }
}

enum L10n {
    static var language: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "sessionbar.language") ?? "system") ?? .system
    }
    static func text(_ key: String, language: AppLanguage? = nil) -> String {
        let selected = language ?? self.language
        return selected.locale.identifier.hasPrefix("ko") ? key : english[key] ?? key
    }
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: language.locale, arguments: arguments)
    }
    static func date(_ date: Date, dateStyle: DateFormatter.Style = .short, timeStyle: DateFormatter.Style = .short) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateStyle = dateStyle; formatter.timeStyle = timeStyle
        return formatter.string(from: date)
    }
    static func activity(_ activity: SessionActivity) -> String {
        if activity.kind == .request, activity.label.hasPrefix("요청: ") {
            return text("요청: ") + activity.label.dropFirst(4)
        }
        return text(activity.label)
    }
    static let english: [String: String] = [
        "미확인": "Unreviewed",
        "미확인 요청": "Unreviewed request",
        "미확인 결과": "Unread result",
        "미확인 오류": "Unreviewed error",
        "확인 완료": "Mark reviewed",
        "확인할 작업이 없습니다": "Nothing to review",
        "미확인 %d · %@": "Unreviewed %d · %@",
        "실행 중~ %d · 활성 ?": "Running~ %d · Active ?",
        "실행 중~ %d · 활성~ %d": "Running~ %d · Active~ %d",
        "프로세스 상태를 확인할 수 없습니다": "Process status unavailable",
        "작업 창으로 이동": "Go to window",
        "앱으로 이동": "Go to app",
        "접근성 설정 열기": "Open accessibility settings",
        "창 이동에 접근성 권한이 필요합니다": "Accessibility permission required to select the window",
        "앱을 열었습니다. 작업 창을 선택해 주세요": "App opened. Select the task window",
        "세션을 연 앱을 찾을 수 없습니다": "Could not find the app that opened the session",
        "앱 창으로 이동할 수 없습니다": "Could not switch to the app window",
        "알림 권한 확인 중": "Checking notification permission",
        "알림 권한 미요청": "Notification permission not requested",
        "알림 허용됨": "Notifications allowed",
        "알림 차단됨": "Notifications blocked",
        "알림 권한 확인 불가": "Notification permission unavailable",
        "알림 표시 꺼짐": "Notification alerts disabled",
        "알림 허용 요청": "Allow notifications",
        "macOS 알림 설정": "macOS notification settings",
        "알림 권한을 요청할 수 없습니다": "Could not request notification permission",
        "알림 설정을 열 수 없습니다": "Could not open notification settings",
        "Codex 종료…": "Quit Codex…",
        "Codex 종료": "Quit Codex",
        "Codex 세션을 종료할까요?": "Quit this Codex session?",
        "Codex가 종료됩니다. 대화 기록은 유지됩니다.": "Codex will quit. Conversation history will be kept.",
        "Codex 종료 실패": "Could not quit Codex",
        "종료할 세션을 확인할 수 없습니다": "Could not identify the session to quit",
        "세션이 변경되었습니다. 새로고침해 주세요": "The session has changed. Please refresh",
        "여러 세션이 연결되어 종료할 수 없습니다": "Cannot quit a process connected to multiple sessions",
        "세션을 종료할 수 없습니다": "Could not quit the session",
        "세션이 아직 실행 중입니다": "The session is still running",
        "세션 종료 중입니다": "The session is being closed",
        "일반": "General",
        "알림": "Notifications",
        "폴더": "Folders",
        "선택됨": "Selected",
        "화면 테마": "Appearance",
        "크림": "Cream",
        "시스템": "System",
        "언어": "Language",
        "Mac 시작 시 자동 실행": "Start automatically on Mac startup",
        "자동 실행 설정 열기": "Open startup settings",
        "자동 실행 설정을 변경할 수 없습니다": "Could not change automatic startup",
        "간단한 메뉴 표시": "Compact menu counts",
        "파일 변경 시 새로고침": "Refresh on file changes",
        "완료·유휴 세션 보관 기간": "Keep completed and idle sessions",
        "7일": "7 days",
        "30일": "30 days",
        "90일": "90 days",
        "모두 표시": "Keep all",
        "자동 새로고침": "Refresh interval",
        "5초": "5 seconds",
        "15초": "15 seconds",
        "30초": "30 seconds",
        "60초": "60 seconds",
        "진단 보기": "Open diagnostics",
        "확인 필요 추정 알림": "Notify on attention estimates",
        "작업 완료 알림": "Notify on completion",
        "오류 알림": "Notify on errors",
        "알림음": "Notification sound",
        "같은 세션의 알림 간격": "Repeat notification interval",
        "1분": "1 minute",
        "5분": "5 minutes",
        "10분": "10 minutes",
        "30분": "30 minutes",
        "조용한 시간대": "Quiet hours",
        "시작": "Start",
        "종료": "Quit",
        "알림 다시 켜기": "Resume notifications",
        "알림 1시간 일시 중지": "Pause notifications for 1 hour",
        "세션 폴더": "Session folders",
        "폴더 제외": "Remove folder",
        "폴더 추가…": "Connect folder…",
        "기본 폴더": "Default folder",
        "시각": "Time",
        "추가": "Connect",
        "세션 폴더 선택": "Select a session folder",
        "세션 폴더 연결…": "Connect session folder…",
        "읽기 권한이 필요합니다": "Folder access required",
        "세션 기록 접근 필요": "Session record unavailable",
        "마지막 활동 불명": "Last activity unknown",
        "세션 폴더를 연결할 수 없습니다": "Could not connect session folder",
        "Codex 세션": "Codex session",
        "세션 기록을 읽을 수 없습니다": "Session record unavailable",
        "세션 기록을 찾을 수 없습니다": "Session record not found",
        "실행 중인 세션을 찾을 수 없습니다": "No running session found",
        "세션 폴더를 읽을 수 없습니다": "Session folder unavailable",
        "세션을 찾을 수 없습니다": "Session not found",
        "활동 기록": "Activity history",
        "최근 활동": "Recent activity",
        "최신 Codex 응답": "Latest Codex reply",
        "아직 표시할 응답이 없습니다": "No reply yet",
        "표시할 활동이 없습니다": "No activity yet",
        "터미널로 돌아가기": "Return to terminal",
        "프로젝트 폴더 열기": "Open project folder",
        "프로젝트 폴더를 열 수 없습니다": "Could not open project folder",
        "복사": "Copy",
        "재개 명령": "Resume command",
        "세션 ID": "Session ID",
        "프로젝트 경로": "Project path",
        "새로고침": "Refresh",
        "상세 새로고침": "Refresh details",
        "날짜": "Date",
        "CSV 내보내기…": "Export CSV…",
        "이 날짜의 완료 기록이 없습니다": "No completed tasks on this date",
        "프로젝트 없음": "No project",
        "세션 보기": "View session",
        "활동 기록 내보내기": "Export activity history",
        "시작 날짜": "Start date",
        "종료 날짜": "End date",
        "완료·오류 기록 · 시각, 프로젝트명, 상태": "Completed and failed tasks · Time, project, status",
        "프로젝트 경로 포함": "Include project paths",
        "세션 ID 포함": "Include session IDs",
        "요청 요약 포함": "Include request summaries",
        "취소": "Cancel",
        "저장 위치 선택…": "Choose save location…",
        "활동 기록 저장": "Save activity history",
        "파일을 저장할 수 없습니다": "Could not save file",
        "진단": "Diagnostics",
        "진단 복사": "Copy diagnostics",
        "세션 상세": "Session details",
        "설정": "Settings",
        "열린 세션": "Open sessions",
        "전체": "All",
        "주의 필요": "Attention",
        "프로젝트 또는 세션 검색": "Search projects or sessions",
        "열린 세션이 없습니다": "No open sessions",
        "표시할 세션이 없습니다": "No sessions to display",
        "주의가 필요한 세션이 없습니다": "No sessions need attention",
        "세션 기록 보기": "View session history",
        "세션 없음": "No sessions",
        "제목 없음": "Untitled",
        "알림 권한 없음": "Notification permission unavailable",
        "알림을 표시할 수 없습니다": "Could not display notification",
        "Codex 확인 필요 추정": "Codex may need attention",
        "Codex 오류": "Codex error",
        "Codex 작업 완료": "Codex task completed",
        "프로세스 정보를 읽을 수 없습니다": "Process information unavailable",
        "tmux pane으로 이동할 수 없습니다": "Could not switch to tmux pane",
        "터미널 위치를 확인할 수 없습니다": "Terminal location unavailable",
        "터미널 자동화 권한이 필요합니다": "Terminal automation permission required",
        "터미널이 응답하지 않습니다": "Terminal is not responding",
        "터미널 창을 찾을 수 없습니다": "Terminal window not found",
        "세션이 열린 터미널 탭을 찾을 수 없습니다": "Session terminal tab not found",
        "터미널 창을 조회할 수 없습니다": "Unable to read terminal windows",
        "앱으로 이동했습니다. 세션 탭을 선택해 주세요": "App opened. Select the session tab",
        "자동화 설정 열기": "Open automation settings",
        "실행 추정": "Running estimate",
        "확인 필요 추정": "Attention estimate",
        "완료": "Completed",
        "유휴 추정": "Idle estimate",
        "오류": "Error",
        "상태 불명": "Unknown",
        "사용자 요청": "User request",
        "작업 시작": "Task started",
        "오류 발생": "Error occurred",
        "작업 완료": "Task completed",
        "작업 중단": "Task interrupted",
        "작업 완료 기록": "Task completion recorded",
        "작업 오류 기록": "Task error recorded",
        "작업 중단 · 실행 프로세스 미확인": "Task interrupted · No running process confirmed",
        "작업 중단 기록": "Task interruption recorded",
        "응답이 기록되지 않은 사용자 입력 요청": "User input requested without a recorded response",
        "결과가 기록되지 않은 권한 요청": "Approval requested without a recorded result",
        "실행 프로세스 미확인": "No running process confirmed",
        "최근 작업 활동 기록": "Recent task activity recorded",
        "프로세스 실행 중 · 최근 작업 활동 없음": "Process alive · No recent task activity",
        "현재 상태를 확인할 근거 없음": "Insufficient evidence for current status",
        "실행 중~ %d · 활성 %d": "Running~ %d · Active %d",
        "확인~ %d · %@": "Attention~ %d · %@",
        "실행 추정 %d개, 활성 세션 %d개, 확인 필요 추정 %d개": "%d estimated running, %d active sessions, %d attention estimates",
        "%@ %d개": "%@ %d",
        "갱신 %@": "Updated %@",
        "마지막 활동 %@": "Last activity %@",
        "일시 중지 · %@까지": "Paused until %@",
        "%d개 작업": "%d tasks",
        "세션 %d": "Sessions %d",
        "Codex 프로세스 %d": "Codex processes %d",
        "읽기 실패 %d": "Read failures %d",
        "세션 %d · Codex 프로세스 %d · 읽기 문제 %d": "Sessions %d · Codex processes %d · Read issues %d",
        "요청: ": "Request: ",
        "없음": "None"
    ]
}

extension SessionState {
    var localizedLabel: String { L10n.text(koreanLabel) }
}

struct LocalizedRoot<Content: View>: View {
    @AppStorage("sessionbar.language") private var language = AppLanguage.system.rawValue
    let content: Content
    var body: some View {
        content.id(language).environment(\.locale, (AppLanguage(rawValue: language) ?? .system).locale)
    }
}

extension SessionReviewEvent.Kind {
    var localizedLabel: String {
        switch self {
        case .attention: return L10n.text("미확인 요청")
        case .completed: return L10n.text("미확인 결과")
        case .error: return L10n.text("미확인 오류")
        }
    }
}
