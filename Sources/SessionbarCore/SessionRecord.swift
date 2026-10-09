import Foundation

public enum SessionState: String, CaseIterable, Sendable {
    case runningEstimate, needsAttentionEstimate, completed, idleEstimate, error, unknown

    public var koreanLabel: String {
        switch self {
        case .runningEstimate: "실행 추정"
        case .needsAttentionEstimate: "확인 필요 추정"
        case .completed: "완료"
        case .idleEstimate: "유휴 추정"
        case .error: "오류"
        case .unknown: "상태 불명"
        }
    }

    public var symbol: String {
        switch self {
        case .runningEstimate: "arrow.triangle.2.circlepath"
        case .needsAttentionEstimate: "exclamationmark.bubble.fill"
        case .completed: "checkmark.circle.fill"
        case .idleEstimate: "pause.circle"
        case .error: "exclamationmark.triangle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    public var isEstimated: Bool {
        self == .runningEstimate || self == .needsAttentionEstimate || self == .idleEstimate
    }
}

public struct SessionRuntime: Equatable, Sendable {
    public let processID: Int32
    public let processStartTime: UInt64?
    public let originAppProcessID: Int32?
    public let tty: String?
    public let terminalName: String?
    public let terminalBundleID: String?
    public let tmuxPane: String?
    public let tmuxSession: String?
    public let tmuxWindow: String?
    public let tmuxClientTTY: String?
    public let workingDirectory: String?

    public init(processID: Int32, tty: String? = nil, terminalName: String? = nil,
                terminalBundleID: String? = nil, tmuxPane: String? = nil,
                tmuxSession: String? = nil, tmuxWindow: String? = nil, tmuxClientTTY: String? = nil, workingDirectory: String? = nil,
                processStartTime: UInt64? = nil, originAppProcessID: Int32? = nil) {
        self.processID = processID
        self.processStartTime = processStartTime
        self.originAppProcessID = originAppProcessID
        self.tty = tty
        self.terminalName = terminalName
        self.terminalBundleID = terminalBundleID
        self.tmuxPane = tmuxPane
        self.tmuxSession = tmuxSession
        self.tmuxWindow = tmuxWindow
        self.tmuxClientTTY = tmuxClientTTY
        self.workingDirectory = workingDirectory
    }
}

public struct SessionRecord: Identifiable, Equatable, Sendable {
    public let id: String
    public let projectPath: String
    public let title: String
    public let lastActivity: Date
    public let state: SessionState
    public let source: String?
    public let evidence: String
    public let runtime: SessionRuntime?
    public let stateRecordedAt: Date
    public let isPlaceholder: Bool
    public let isRuntimeStale: Bool

    public init(id: String, projectPath: String, title: String, lastActivity: Date,
                state: SessionState, source: String?, evidence: String = "", runtime: SessionRuntime? = nil, stateRecordedAt: Date? = nil, isPlaceholder: Bool = false, isRuntimeStale: Bool = false) {
        self.id = id
        self.projectPath = projectPath
        self.title = title
        self.lastActivity = lastActivity
        self.state = state
        self.source = source
        self.evidence = evidence
        self.runtime = runtime
        self.stateRecordedAt = stateRecordedAt ?? lastActivity
        self.isPlaceholder = isPlaceholder
        self.isRuntimeStale = isRuntimeStale
    }

    public var eventToken: String { "\(state.rawValue):\(stateRecordedAt.timeIntervalSince1970)" }

    public var projectName: String { URL(fileURLWithPath: projectPath).lastPathComponent }
}

public struct SessionActivity: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case request, started, completed, error, aborted }
    public let id: String
    public let date: Date
    public let label: String
    public let kind: Kind

    public init(id: String, date: Date, label: String, kind: Kind = .request) {
        self.id = id
        self.date = date
        self.label = label
        self.kind = kind
    }
}

public struct SessionDetail: Equatable, Sendable {
    public let latestResponse: String?
    public let activities: [SessionActivity]
    public let completedResponseToken: String?

    public init(latestResponse: String?, activities: [SessionActivity], completedResponseToken: String? = nil) {
        self.latestResponse = latestResponse
        self.activities = activities
        self.completedResponseToken = completedResponseToken
    }
}

public enum SessionFileParser {
    public static func parse(url: URL, now: Date = .now) -> SessionRecord? {
        var reader = IncrementalSessionReader(url: url)
        return reader.read()?.record(now: now)
    }

    public static func readDetail(url: URL) -> SessionDetail? {
        var reader = IncrementalSessionReader(url: url)
        return reader.read()?.detail
    }
}
