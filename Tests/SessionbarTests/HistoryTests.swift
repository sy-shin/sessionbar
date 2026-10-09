import Foundation
import Testing
@testable import SessionbarCore

@Suite struct HistoryTests {
    @Test func historyUsesDateRangeAndCSVExcludesOptionalDataByDefault() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "sessionbar-history-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let records = [
            #"{"type":"session_meta","payload":{"id":"test-session","cwd":"/tmp/project"}}"#,
            #"{"type":"event_msg","payload":{"type":"user_message","message":"=DANGEROUS"},"timestamp":"2026-10-07T10:00:00Z"}"#,
            #"{"type":"event_msg","payload":{"type":"task_complete"},"timestamp":"2026-10-07T10:30:00Z"}"#,
            #"{"type":"event_msg","payload":{"type":"task_complete","error":{"message":"redacted"}},"timestamp":"2026-10-08T10:30:00Z"}"#,
            #"{"type":"event_msg","payload":{"type":"task_complete"},"timestamp":"2026-10-09T00:00:00Z"}"#
        ]
        try Data((records.joined(separator: "\n") + "\n").utf8).write(to: url)
        let formatter = ISO8601DateFormatter()
        let items = SessionHistoryReader.read(url: url, from: formatter.date(from: "2026-10-08T00:00:00Z")!, to: formatter.date(from: "2026-10-09T00:00:00Z")!)
        #expect(items.count == 1); #expect(items.first?.state == .error)
        let standard = String(decoding: HistoryCSV.data(items: items, options: HistoryExportOptions()), as: UTF8.self)
        #expect(!standard.contains("/tmp/project")); #expect(!standard.contains("test-session")); #expect(!standard.contains("DANGEROUS"))
        var options = HistoryExportOptions(); options.includeTitle = true; options.includeSessionID = true; options.includeProjectPath = true
        let explicit = String(decoding: HistoryCSV.data(items: items, options: options), as: UTF8.self)
        #expect(explicit.contains("/tmp/project")); #expect(explicit.contains("test-session")); #expect(explicit.contains("'=DANGEROUS"))
    }
}
