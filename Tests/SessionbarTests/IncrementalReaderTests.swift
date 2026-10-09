import Foundation
import Testing
@testable import SessionbarCore

@Suite
struct IncrementalReaderTests {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "sessionbar-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appending(path: "rollout-test.jsonl")
        try Data(#"{"type":"session_meta","payload":{"id":"sample","cwd":"/tmp/project"},"timestamp":"2026-10-08T10:00:00Z"}"#.utf8).write(to: url)
        return url
    }
    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf: Data(text.utf8))
    }
    private let now = ISO8601DateFormatter().date(from: "2026-10-08T10:01:00Z")!

    @Test func partialWritesAreParsedOnceAndUnchangedFilesAreNotReadAgain() throws {
        let url = try fixture(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try append("\n" + #"{"type":"event_msg","payload":{"type":"task_started"},"timestamp":"2026-10-08T10:00:30Z"}"# + "\n", to: url)
        var reader = IncrementalSessionReader(url: url)
        let firstOptional = reader.read()
        let first = try #require(firstOptional)
        #expect(first.record(now: now)?.state == .runningEstimate)
        let count = reader.bytesRead
        _ = reader.read(); #expect(reader.bytesRead == count)
        let partial = #"{"type":"event_msg","payload":{"type":"task_complete"},"timestamp":"2026-10-08T10:00:50Z"}"#
        try append(String(partial.prefix(50)), to: url)
        #expect(reader.read()?.record(now: now)?.state == .runningEstimate)
        try append(String(partial.dropFirst(50)) + "\n", to: url)
        let completeOptional = reader.read()
        let complete = try #require(completeOptional)
        #expect(complete.record(now: now)?.state == .completed)
        #expect(complete.detail.activities.filter { $0.kind == .completed }.count == 1)
        #expect(reader.bytesRead == count + UInt64(partial.utf8.count + 1))
    }

    @Test func tokenEventsDoNotEraseCompletionAndDeadProcessesAreNotRunning() throws {
        let url = try fixture(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try append("\n" + #"{"type":"event_msg","payload":{"type":"task_started"},"timestamp":"2026-10-08T10:00:30Z"}"# + "\n", to: url)
        var reader = IncrementalSessionReader(url: url)
        let startedOptional = reader.read()
        let started = try #require(startedOptional)
        #expect(started.record(now: now, processObservationAvailable: true)?.state == .unknown)
        #expect(started.record(now: now, runtime: SessionRuntime(processID: 42), processObservationAvailable: true)?.state == .runningEstimate)
        #expect(started.record(now: now.addingTimeInterval(180), runtime: SessionRuntime(processID: 42), processObservationAvailable: true)?.state == .idleEstimate)
        try append(#"{"type":"event_msg","payload":{"type":"task_complete"},"timestamp":"2026-10-08T10:00:50Z"}"# + "\n" + #"{"type":"event_msg","payload":{"type":"token_count"},"timestamp":"2026-10-08T10:00:51Z"}"# + "\n", to: url)
        #expect(reader.read()?.record(now: now, processObservationAvailable: true)?.state == .completed)
    }

    @Test func pendingInputAndApprovalRequireLiveProcessAndClearOnOutput() throws {
        let url = try fixture(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try append("\n" + #"{"type":"response_item","payload":{"type":"function_call","call_id":"input-call","name":"functions.request_user_input","arguments":"{}"},"timestamp":"2026-10-08T10:00:30Z"}"# + "\n", to: url)
        var reader = IncrementalSessionReader(url: url)
        let inputOptional = reader.read()
        let input = try #require(inputOptional)
        #expect(input.record(now: now, processObservationAvailable: true)?.state == .unknown)
        #expect(input.record(now: now, runtime: SessionRuntime(processID: 42), processObservationAvailable: true)?.state == .needsAttentionEstimate)
        try append(#"{"type":"response_item","payload":{"type":"function_call_output","call_id":"input-call","output":"answer"},"timestamp":"2026-10-08T10:00:40Z"}"# + "\n", to: url)
        #expect(reader.read()?.record(now: now, runtime: SessionRuntime(processID: 42))?.state == .runningEstimate)
        try append(#"{"type":"response_item","payload":{"type":"function_call","call_id":"approval-call","name":"exec_command","arguments":"{\"sandbox_permissions\":\"require_escalated\"}"},"timestamp":"2026-10-08T10:00:45Z"}"# + "\n", to: url)
        #expect(reader.read()?.record(now: now, runtime: SessionRuntime(processID: 42))?.state == .needsAttentionEstimate)
    }

    @Test func largeFilesKeepMetadataAndTruncationResetsOldState() throws {
        let url = try fixture(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try append("\n" + String(repeating: #"{"type":"event_msg","payload":{"type":"token_count"},"timestamp":"2026-10-08T10:00:00Z"}"# + "\n", count: 9000) + #"{"type":"event_msg","payload":{"type":"task_complete"},"timestamp":"2026-10-08T10:00:30Z"}"# + "\n", to: url)
        var reader = IncrementalSessionReader(url: url)
        #expect(reader.read()?.record(now: now)?.state == .completed)
        #expect(reader.bytesRead <= 640 * 1024)
        let new = #"{"type":"session_meta","payload":{"id":"replacement","cwd":"/tmp/replacement"},"timestamp":"2026-10-08T10:00:00Z"}"# + "\n"
        try Data(new.utf8).write(to: url)
        let record = reader.read()?.record(now: now)
        #expect(record?.id == "replacement")
        #expect(record?.state == .unknown)
    }

    @Test func missingFileReturnsNil() {
        var reader = IncrementalSessionReader(url: FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID().uuidString).jsonl"))
        #expect(reader.read() == nil)
    }
}
