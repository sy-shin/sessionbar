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
        var index = SessionHistoryIndex(url: url)
        return index.read(from: start, to: end)
    }
}

public struct SessionHistoryIndex: Sendable {
    public let url: URL
    public private(set) var bytesRead: UInt64 = 0
    private var offset: UInt64 = 0
    private var modification: Date?
    private var buffer = Data()
    private var items: [SessionHistoryItem] = []
    private var sessionID: String?
    private var cwd = ""
    private var title = "제목 없음"
    private var skippingLongLine = false

    public init(url: URL) { self.url = url }

    public mutating func read(from start: Date, to end: Date) -> [SessionHistoryItem] {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let changed = attributes[.modificationDate] as? Date else { return [] }
        if size < offset || (size == offset && modification != nil && modification != changed) {
            self = SessionHistoryIndex(url: url)
        }
        if size > offset, let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            do {
                try handle.seek(toOffset: offset)
                let completionMarker = Data("\"task_complete\"".utf8)
                let metadataMarker = Data("\"session_meta\"".utf8)
                let newlineMarker = Data([10])
                while offset < size, !Task.isCancelled {
                    guard let data = try handle.read(upToCount: Int(min(65_536, size - offset))), !data.isEmpty else { break }
                    offset += UInt64(data.count); bytesRead += UInt64(data.count)
                    buffer.append(data)
                    var consumed = buffer.startIndex
                    while let newline = buffer.range(of: newlineMarker, in: consumed..<buffer.endIndex)?.lowerBound {
                        let line = buffer[consumed..<newline]
                        consumed = newline + 1
                        if skippingLongLine { skippingLongLine = false; continue }
                        // Skip response bodies and tool output after the first request is known.
                        if title != "제목 없음", line.range(of: completionMarker) == nil,
                           line.range(of: metadataMarker) == nil { continue }
                        consume(Data(line))
                    }
                    if consumed != buffer.startIndex { buffer = Data(buffer[consumed...]) }
                    if buffer.count > 4 * 1024 * 1024 { buffer.removeAll(); skippingLongLine = true }
                }
            } catch { /* Retain already parsed records and retry from the last read offset. */ }
        }
        modification = changed
        return items.filter { $0.date >= start && $0.date < end }
    }

    private mutating func consume(_ line: Data) {
        guard let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = record["payload"] as? [String: Any] else { return }
        let type = record["type"] as? String
        if type == "session_meta" {
            sessionID = payload["id"] as? String ?? payload["session_id"] as? String
            cwd = payload["cwd"] as? String ?? ""
        } else if type == "event_msg", payload["type"] as? String == "user_message", title == "제목 없음" {
            title = String((payload["message"] as? String ?? "").split(whereSeparator: \.isNewline).joined(separator: " ").prefix(100))
        } else if type == "response_item", payload["role"] as? String == "user", title == "제목 없음",
                  let request = SessionSnapshot.userRequestText(payload) {
            title = String(request.split(whereSeparator: \.isNewline).joined(separator: " ").prefix(100))
        } else if type == "event_msg", payload["type"] as? String == "task_complete",
                  let sessionID, let date = SessionSnapshot.parseDate(record["timestamp"]) {
            let state: SessionState = payload["error"] as? [String: Any] == nil ? .completed : .error
            items.append(SessionHistoryItem(sessionID: sessionID, projectPath: cwd, title: title, date: date, state: state))
        }
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
