import Foundation
import Testing
@testable import SessionbarCore

@Suite
final class SessionFileParserTests {
    private var temporaryDirectories: [URL] = []
    deinit { for url in temporaryDirectories { try? FileManager.default.removeItem(at: url) } }
    private func makeSession(_ lines: [String], now: Date = Date(timeIntervalSince1970: 1_800_000_000)) throws -> (URL, Date) {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        let url = directory.appending(path: "rollout-test.jsonl")
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        return (url, now)
    }

    private func metadata(_ cwd: String = "/tmp/sample") -> String {
        #"{"type":"session_meta","payload":{"session_id":"test-session","cwd":"\#(cwd)","originator":"codex"},"timestamp":"2026-10-08T10:00:00Z"}"#
    }

    private func event(_ name: String, at time: String, message: String? = nil) -> String {
        var payload: [String: String] = ["type": name]
        if let message { payload["message"] = message }
        let object: [String: Any] = ["type": "event_msg", "payload": payload, "timestamp": time]
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private func finalResponse(_ text: String, at time: String) -> String {
        #"{"type":"response_item","payload":{"type":"message","role":"assistant","phase":"final_answer","content":[{"type":"output_text","text":"\#(text)"}]},"timestamp":"\#(time)"}"#
    }

    @Test func testRecognizesRecentStartAsEstimate() throws {
        let now = ISO8601DateFormatter().date(from: "2026-10-08T10:01:00Z")!
        let (url, _) = try makeSession([metadata(), event("task_started", at: "2026-10-08T10:00:30Z")], now: now)
        #expect(SessionFileParser.parse(url: url, now: now)?.state == .runningEstimate)
    }

    @Test func testRecognizesCompletionAndFirstUserRequest() throws {
        let now = ISO8601DateFormatter().date(from: "2026-10-08T10:01:00Z")!
        let (url, _) = try makeSession([
            metadata(),
            event("user_message", at: "2026-10-08T09:59:00Z", message: "Summarize this task"),
            event("task_complete", at: "2026-10-08T10:00:00Z")
        ], now: now)
        let session = SessionFileParser.parse(url: url, now: now)
        #expect(session?.state == .completed)
        #expect(session?.title == "Summarize this task")
    }

    @Test func testRecognizesRecordedTaskError() throws {
        let now = ISO8601DateFormatter().date(from: "2026-10-08T10:01:00Z")!
        let errorEvent = #"{"type":"event_msg","payload":{"type":"task_complete","error":{"message":"redacted"}},"timestamp":"2026-10-08T10:00:00Z"}"#
        let (url, _) = try makeSession([metadata(), errorEvent], now: now)
        #expect(SessionFileParser.parse(url: url, now: now)?.state == .error)
    }

    @Test func testAbortedTurnIsIdleEstimate() throws {
        let now = ISO8601DateFormatter().date(from: "2026-10-08T10:01:00Z")!
        let (url, _) = try makeSession([metadata(), event("turn_aborted", at: "2026-10-08T10:00:00Z")], now: now)
        #expect(SessionFileParser.parse(url: url, now: now)?.state == .idleEstimate)
    }

    @Test func testIgnoresMissingOrCorruptMetadata() throws {
        let (missingURL, now) = try makeSession([event("task_started", at: "2026-10-08T10:00:00Z")])
        #expect(SessionFileParser.parse(url: missingURL, now: now) == nil)
        let (corruptURL, _) = try makeSession(["{broken", "not-json"])
        #expect(SessionFileParser.parse(url: corruptURL, now: now) == nil)
    }

    @Test func testPartialLastLineKeepsEarlierValidRecord() throws {
        let (url, now) = try makeSession([metadata(), event("task_complete", at: "2026-10-08T10:00:00Z"), "{" ] )
        #expect(SessionFileParser.parse(url: url, now: now)?.state == .completed)
    }

    @Test func testApprovalWaitWithoutRuntimeEvidenceRemainsUnknown() throws {
        let (url, now) = try makeSession([metadata(), event("user_message", at: "2026-10-08T10:00:00Z", message: "Needs approval")])
        #expect(SessionFileParser.parse(url: url, now: now)?.state == .unknown)
    }

    @Test func testMultipleSessionFilesCanBeParsedIndependently() throws {
        let now = ISO8601DateFormatter().date(from: "2026-10-08T10:01:00Z")!
        let (first, _) = try makeSession([metadata(), event("task_started", at: "2026-10-08T10:00:30Z")], now: now)
        let (second, _) = try makeSession([metadata("/tmp/another"), event("task_complete", at: "2026-10-08T10:00:00Z")], now: now)
        #expect(SessionFileParser.parse(url: first, now: now)?.state == .runningEstimate)
        #expect(SessionFileParser.parse(url: second, now: now)?.state == .completed)
    }

    @Test func testUserMessageFallbackSkipsInjectedContext() throws {
        let (url, now) = try makeSession([
            metadata(),
            ##"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"# AGENTS.md instructions for sample"}]},"timestamp":"2026-10-08T10:00:00Z"}"##,
            #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Build a sample app"}]},"timestamp":"2026-10-08T10:00:01Z"}"#,
            event("task_complete", at: "2026-10-08T10:00:30Z")
        ])
        #expect(SessionFileParser.parse(url: url, now: now)?.title == "Build a sample app")
    }

    @Test func testDetailReturnsLatestFinalResponseAndRecentActivities() throws {
        let (url, _) = try makeSession([
            metadata(),
            event("user_message", at: "2026-10-08T09:59:00Z", message: "First request"),
            finalResponse("First answer", at: "2026-10-08T09:59:30Z"),
            event("task_started", at: "2026-10-08T10:00:00Z"),
            finalResponse("Latest answer", at: "2026-10-08T10:00:30Z")
        ])
        let detail = SessionFileParser.readDetail(url: url)
        #expect(detail?.latestResponse == "Latest answer")
        #expect(detail?.activities.count == 2)
        #expect(detail?.activities.first?.label == "작업 시작")
        #expect(detail?.activities.last?.label == "요청: First request")
    }
}
