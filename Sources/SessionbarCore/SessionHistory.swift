import Foundation

public struct SessionHistoryItem: Identifiable, Sendable {
    public let id: String
    public let sessionID: String
    public let projectPath: String
    public let title: String
    public let date: Date
    public let state: SessionState
    public var projectName: String { URL(fileURLWithPath: projectPath).lastPathComponent }

    public init(sessionID: String, projectPath: String, title: String, date: Date, state: SessionState) {
        id = "\(sessionID)-\(date.timeIntervalSince1970)"
        self.sessionID = sessionID; self.projectPath = projectPath; self.title = title
        self.date = date; self.state = state
    }
}

public enum SessionHistoryReader {
    public static func read(url: URL, from start: Date, to end: Date) -> [SessionHistoryItem] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        var buffer = Data(), result: [SessionHistoryItem] = []
        var id: String?, cwd = "", title = "제목 없음"
        var skippingLongLine = false
        while let data = try? handle.read(upToCount: 64 * 1024), !data.isEmpty {
            buffer.append(data)
            while let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
                if skippingLongLine { skippingLongLine = false; continue }
                guard let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let payload = record["payload"] as? [String: Any] else { continue }
                let type = record["type"] as? String
                if type == "session_meta" {
                    id = payload["id"] as? String ?? payload["session_id"] as? String
                    cwd = payload["cwd"] as? String ?? ""
                } else if type == "event_msg", payload["type"] as? String == "user_message", title == "제목 없음" {
                    title = String((payload["message"] as? String ?? "").split(whereSeparator: \.isNewline).joined(separator: " ").prefix(100))
                } else if type == "event_msg", payload["type"] as? String == "task_complete",
                          let id, let date = SessionSnapshot.parseDate(record["timestamp"]), date >= start, date < end {
                    let state: SessionState = payload["error"] as? [String: Any] == nil ? .completed : .error
                    result.append(SessionHistoryItem(sessionID: id, projectPath: cwd, title: title, date: date, state: state))
                }
            }
            if buffer.count > 4 * 1024 * 1024 { buffer.removeAll(); skippingLongLine = true }
        }
        return result
    }
}

public struct HistoryExportOptions: Sendable {
    public var includeProjectPath = false
    public var includeSessionID = false
    public var includeTitle = false
    public init() {}
}

public enum HistoryCSV {
    public static func data(items: [SessionHistoryItem], options: HistoryExportOptions) -> Data {
        var headers = ["timestamp", "project", "status"]
        if options.includeProjectPath { headers.append("project_path") }
        if options.includeSessionID { headers.append("session_id") }
        if options.includeTitle { headers.append("title") }
        let formatter = ISO8601DateFormatter()
        var rows = [headers]
        for item in items {
            var row = [formatter.string(from: item.date), item.projectName, item.state.rawValue]
            if options.includeProjectPath { row.append(item.projectPath) }
            if options.includeSessionID { row.append(item.sessionID) }
            if options.includeTitle { row.append(item.title) }
            rows.append(row)
        }
        let text = "\u{FEFF}" + rows.map { $0.map(cell).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
        return Data(text.utf8)
    }

    private static func cell(_ value: String) -> String {
        // Keep spreadsheet apps from evaluating user text as a formula.
        let risky = value.trimmingCharacters(in: .whitespacesAndNewlines).first.map { "=+-@".contains($0) } ?? false
        let safe = risky ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
