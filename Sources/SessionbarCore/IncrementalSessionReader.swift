import Foundation

public struct SessionSnapshot: Sendable {
    enum Phase: Sendable { case working, complete, failed, aborted, unknown }
    enum Pending: Sendable { case input, approval }
    var id: String?
    var cwd = ""
    var title: String?
    var fallbackTitle: String?
    var source: String?
    var lastActivity = Date.distantPast
    var stateRecordedAt = Date.distantPast
    var phase: Phase = .unknown
    var pendingCalls: [String: Pending] = [:]
    var latestResponse: String?
    var activities: [SessionActivity] = []
    public internal(set) var malformedLines = 0

    public var detail: SessionDetail {
        SessionDetail(latestResponse: latestResponse, activities: Array(activities.suffix(40).reversed()))
    }

    public func record(now: Date = .now, runtime: SessionRuntime? = nil,
                       processObservationAvailable: Bool = false) -> SessionRecord? {
        guard let id else { return nil }
        let state: SessionState
        let evidence: String
        switch phase {
        case .complete:
            state = .completed; evidence = "작업 완료 기록"
        case .failed:
            state = .error; evidence = "작업 오류 기록"
        case .aborted:
            state = runtime == nil && processObservationAvailable ? .unknown : .idleEstimate
            evidence = runtime == nil && processObservationAvailable ? "작업 중단 · 실행 프로세스 미확인" : "작업 중단 기록"
        case .working, .unknown:
            if let _ = runtime, pendingCalls.values.contains(.input) {
                state = .needsAttentionEstimate; evidence = "응답이 기록되지 않은 사용자 입력 요청"
            } else if let _ = runtime, pendingCalls.values.contains(.approval) {
                state = .needsAttentionEstimate; evidence = "결과가 기록되지 않은 권한 요청"
            } else if runtime == nil && processObservationAvailable {
                state = .unknown; evidence = "실행 프로세스 미확인"
            } else if phase == .working && now.timeIntervalSince(lastActivity) <= 120 {
                state = .runningEstimate; evidence = "최근 작업 활동 기록"
            } else if runtime != nil {
                state = .idleEstimate; evidence = "프로세스 실행 중 · 최근 작업 활동 없음"
            } else {
                state = .unknown; evidence = "현재 상태를 확인할 근거 없음"
            }
        }
        return SessionRecord(id: id, projectPath: cwd, title: title ?? fallbackTitle ?? "제목 없음", lastActivity: lastActivity,
                             state: state, source: source, evidence: evidence, runtime: runtime, stateRecordedAt: stateRecordedAt)
    }

    mutating func consume(_ record: [String: Any], metadataOnly: Bool = false) {
        let type = record["type"] as? String
        guard let payload = record["payload"] as? [String: Any] else { return }
        if type == "session_meta" {
            id = payload["id"] as? String ?? payload["session_id"] as? String
            cwd = payload["cwd"] as? String ?? ""
            source = payload["source"] as? String ?? payload["originator"] as? String
        }
        if type == "event_msg", payload["type"] as? String == "user_message", title == nil,
           let message = payload["message"] as? String {
            title = String(message.split(whereSeparator: \.isNewline).joined(separator: " ").prefix(100))
        }
        if type == "response_item", payload["role"] as? String == "user", fallbackTitle == nil,
           let request = Self.userRequestText(payload) {
            fallbackTitle = String(request.split(whereSeparator: \.isNewline).joined(separator: " ").prefix(100))
        }
        guard !metadataOnly else { return }
        let date = Self.parseDate(record["timestamp"]) ?? lastActivity
        lastActivity = max(lastActivity, date)
        let kind = payload["type"] as? String ?? ""
        if type == "event_msg" {
            switch kind {
            case "task_started": phase = .working; pendingCalls.removeAll(); stateRecordedAt = date
            case "task_complete":
                phase = payload["error"] as? [String: Any] == nil ? .complete : .failed
                stateRecordedAt = date
                pendingCalls.removeAll()
            case "turn_aborted": phase = .aborted; pendingCalls.removeAll(); stateRecordedAt = date
            case "user_message": phase = .unknown; pendingCalls.removeAll()
            default: break
            }
            if let activity = Self.activity(payload: payload, date: date) {
                activities.append(activity)
                if activities.count > 200 { activities.removeFirst(activities.count - 200) }
            }
        } else if type == "response_item" {
            if ["reasoning", "function_call", "custom_tool_call"].contains(kind) { phase = .working }
            if kind == "function_call" || kind == "custom_tool_call" {
                if let callID = payload["call_id"] as? String {
                    let name = (payload["name"] as? String ?? "").split(separator: ".").last.map(String.init)
                    if name == "request_user_input" { pendingCalls[callID] = .input; stateRecordedAt = date }
                    else if let arguments = payload["arguments"] as? String,
                            let data = arguments.data(using: .utf8),
                            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                            object["sandbox_permissions"] as? String == "require_escalated" {
                        pendingCalls[callID] = .approval
                        stateRecordedAt = date
                    }
                }
            } else if kind == "function_call_output" || kind == "custom_tool_call_output" {
                if let callID = payload["call_id"] as? String { pendingCalls.removeValue(forKey: callID) }
            } else if kind == "message", payload["role"] as? String == "assistant",
                      payload["phase"] as? String == "final_answer",
                      let content = payload["content"] as? [[String: Any]] {
                let text = content.filter { $0["type"] as? String == "output_text" }
                    .compactMap { $0["text"] as? String }.joined(separator: "\n\n")
                if !text.isEmpty { latestResponse = text }
            }
        }
    }

    static func userRequestText(_ payload: [String: Any]) -> String? {
        guard let blocks = payload["content"] as? [[String: Any]] else { return nil }
        let markers = ["# AGENTS.md instructions", "<environment_context>", "<user_instructions>", "<INSTRUCTIONS>", "<permissions", "<codex_internal_context"]
        let texts = blocks.compactMap { block -> String? in
            guard block["type"] as? String == "input_text", let raw = block["text"] as? String else { return nil }
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !markers.contains(where: { text.hasPrefix($0) }) else { return nil }
            if let request = text.range(of: "## My request:") { return String(text[request.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines) }
            return text
        }
        return texts.isEmpty ? nil : texts.joined(separator: " ")
    }

    static func parseDate(_ value: Any?) -> Date? {
        guard let raw = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    static func activity(payload: [String: Any], date: Date) -> SessionActivity? {
        let type = payload["type"] as? String ?? ""
        let kind: SessionActivity.Kind
        let label: String
        switch type {
        case "user_message":
            kind = .request
            let text = (payload["message"] as? String ?? "").split(whereSeparator: \.isNewline).joined(separator: " ")
            label = text.isEmpty ? "사용자 요청" : "요청: \(text.prefix(180))"
        case "task_started": kind = .started; label = "작업 시작"
        case "task_complete":
            kind = payload["error"] as? [String: Any] == nil ? .completed : .error
            label = kind == .error ? "오류 발생" : "작업 완료"
        case "turn_aborted": kind = .aborted; label = "작업 중단"
        default: return nil
        }
        return SessionActivity(id: "\(type)-\(date.timeIntervalSince1970)", date: date, label: label, kind: kind)
    }
}

/// Reads bounded head/tail slices once, then only bytes appended after the last complete line.
public struct IncrementalSessionReader {
    public let url: URL
    public private(set) var bytesRead: UInt64 = 0
    private var cursor: UInt64 = 0
    private var modifiedAt: Date?
    private var snapshot = SessionSnapshot()
    private var pending = Data()
    private var initialized = false
    private static let headerLimit = 128 * 1024
    private static let tailLimit = 512 * 1024
    private static let chunkSize = 64 * 1024
    private static let maximumLineBytes = 4 * 1024 * 1024

    public init(url: URL) { self.url = url }

    public mutating func read() -> SessionSnapshot? {
        guard let metadata = SessionFileMetadata.read(url),
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = metadata.size
        let modified = metadata.modified
        if initialized && size == cursor && modified == modifiedAt { return snapshot.id == nil ? nil : snapshot }
        if !initialized || size < cursor || (size == cursor && modified != modifiedAt) || size - cursor > 2 * 1024 * 1024 {
            snapshot = SessionSnapshot(); pending = Data(); cursor = 0
            if size > UInt64(Self.tailLimit) {
                let header = (try? handle.read(upToCount: Self.headerLimit)) ?? Data()
                bytesRead += UInt64(header.count)
                for line in header.split(separator: 10) { decode(Data(line), metadataOnly: true) }
                cursor = size - UInt64(Self.tailLimit)
                try? handle.seek(toOffset: cursor)
                let tail = (try? handle.read(upToCount: Self.tailLimit)) ?? Data()
                bytesRead += UInt64(tail.count)
                if let newline = tail.firstIndex(of: 10) { consume(Data(tail[tail.index(after: newline)...])) }
                cursor += UInt64(tail.count)
            }
            initialized = true
        }
        if cursor < size {
            try? handle.seek(toOffset: cursor)
            while cursor < size {
                let count = min(Self.chunkSize, Int(size - cursor))
                guard let chunk = try? handle.read(upToCount: count), !chunk.isEmpty else { break }
                consume(chunk)
                cursor += UInt64(chunk.count)
                bytesRead += UInt64(chunk.count)
            }
        }
        modifiedAt = modified
        return snapshot.id == nil ? nil : snapshot
    }

    private mutating func consume(_ data: Data) {
        pending.append(data)
        while let newline = pending.firstIndex(of: 10) {
            let line = Data(pending[..<newline])
            pending.removeSubrange(...newline)
            decode(line)
        }
        if pending.count > Self.maximumLineBytes { pending.removeAll(); snapshot.malformedLines += 1 }
    }

    private mutating func decode(_ line: Data, metadataOnly: Bool = false) {
        guard !line.isEmpty else { return }
        guard let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            if !metadataOnly { snapshot.malformedLines += 1 }
            return
        }
        snapshot.consume(record, metadataOnly: metadataOnly)
    }
}
