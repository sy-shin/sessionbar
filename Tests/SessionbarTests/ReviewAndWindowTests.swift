import Foundation
import Testing
@testable import SessionbarCore
@testable import sessionbar

@Suite struct ReviewAndWindowTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func record(_ state: SessionState, offset: Double = 0, live: Bool = true, stale: Bool = false) -> SessionRecord {
        SessionRecord(id: "fixture", projectPath: "/tmp/project", title: "Fixture", lastActivity: now.addingTimeInterval(offset), state: state, source: nil, runtime: live ? SessionRuntime(processID: 42) : nil, stateRecordedAt: now.addingTimeInterval(offset), isRuntimeStale: stale)
    }

    @Test func oldArchivesAreExcludedButLiveResultsAndNewArchivesNeedReview() {
        var tracker = SessionReviewTracker(now: now)
        tracker.observe([record(.error, offset: -60, live: false)])
        #expect(tracker.pending(id: "fixture") == nil)
        tracker.observe([record(.completed, offset: -30)])
        #expect(tracker.pending(id: "fixture")?.kind == .completed)
        tracker.observe([record(.error, offset: 1, live: false)])
        #expect(tracker.pending(id: "fixture")?.kind == .error)
    }

    @Test func reviewIsPersistentAndOlderAcknowledgementCannotClearNewResult() throws {
        var tracker = SessionReviewTracker(now: now)
        let first = record(.completed), second = record(.completed, offset: 10)
        tracker.observe([first]); tracker.markReviewed(id: first.id, token: first.eventToken)
        tracker = try JSONDecoder().decode(SessionReviewTracker.self, from: JSONEncoder().encode(tracker))
        tracker.observe([first]); #expect(tracker.pending(id: first.id) == nil)
        tracker.observe([second]); tracker.markReviewed(id: first.id, token: first.eventToken)
        #expect(tracker.pending(id: first.id)?.token == second.eventToken)
        tracker.observe([record(.runningEstimate, offset: 11)])
        #expect(tracker.pending(id: first.id)?.kind == .completed)
    }

    @Test func requestsClearOnResolutionAndStaleRecordsDoNotInventResults() {
        var tracker = SessionReviewTracker(now: now)
        tracker.observe([record(.needsAttentionEstimate)])
        #expect(tracker.pending(id: "fixture")?.kind == .attention)
        tracker.observe([record(.unknown, stale: true)])
        #expect(tracker.pending(id: "fixture")?.kind == .attention)
        tracker.observe([record(.runningEstimate, offset: 1)])
        #expect(tracker.pending(id: "fixture") == nil)
        tracker.observe([record(.completed, offset: 2, stale: true)])
        #expect(tracker.pending(id: "fixture") == nil)
        tracker.observe([record(.needsAttentionEstimate, offset: 3, live: false)])
        #expect(tracker.pending(id: "fixture") == nil)
    }

    @MainActor @Test func reviewStoreRestoresMarkersWithoutConversationOrPaths() throws {
        let suite = "sessionbar-review-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SessionReviewStore(defaults: defaults, now: now)
        let completion = record(.completed)
        store.observe([completion]); store.markReviewed(id: completion.id, token: completion.eventToken)
        let restored = SessionReviewStore(defaults: defaults, now: now.addingTimeInterval(100))
        restored.observe([completion]); #expect(restored.pending(id: completion.id) == nil)
        let data = try #require(defaults.data(forKey: "sessionbar.reviewMarkers"))
        #expect(!String(decoding: data, as: UTF8.self).contains("/tmp/project"))
        #expect(!String(decoding: data, as: UTF8.self).contains("Fixture"))
    }

    @Test func observationFailureKeepsOnlyMatchingProcessesAndMarksCountEstimated() {
        let url = URL(fileURLWithPath: "/tmp/sessions/fixture.jsonl")
        let previous = [url: SessionRuntime(processID: 42, processStartTime: 123)]
        let unavailable = ProcessSnapshot(byFile: [:], codexCount: 1, available: false)
        let recovered = unavailable.recovering(previous) { $0.processStartTime == 123 }
        #expect(recovered.byFile.count == 1)
        #expect(unavailable.recovering(previous) { _ in false }.byFile.isEmpty)
        var ids: [URL: String] = [:]
        let inventory = SessionInventory(snapshots: [:], runtime: recovered, now: now, placeholderIDs: &ids)
        #expect(inventory.records.values.first?.isRuntimeStale == true)
        #expect(inventory.records.values.first?.state == .unknown)
        #expect(inventory.activeCount == 1)
        let menu = SessionMenuSummary(records: [], activeCount: 0, processObservationAvailable: false)
        #expect(menu.activeEstimated)
        #expect(menu.title(compact: true) == "0/?")
    }

    @MainActor @Test func windowMatchingUsesPathBoundariesAndExactTitleSegments() {
        let windows = [SessionWindowConnector.WindowDescription(title: "main.swift — project — Code", document: "file:///tmp/project/main.swift"),
                       .init(title: "other — Code", document: "file:///tmp/project-other/a.swift"),
                       .init(title: "project — Code", document: nil)]
        #expect(SessionWindowConnector.matchingWindows(windows, projectPath: "/tmp/project") == [0])
        #expect(SessionWindowConnector.matchingWindows(Array(windows.dropFirst()), projectPath: "/tmp/project") == [1])
        #expect(SessionWindowConnector.matchingWindows(windows, projectPath: "/") == [])
        #expect(SessionWindowConnector.matchingWindows(windows, projectPath: "project") == [])
        #expect(SessionWindowConnector.matchingWindows([.init(title: "project - Code", document: nil), .init(title: "project — Code", document: nil)], projectPath: "/tmp/project").count == 2)
        #expect(!SessionWindowConnector.canReturn(SessionRuntime(processID: 1)))
        #expect(SessionWindowConnector.canReturn(SessionRuntime(processID: 1, terminalBundleID: "example.editor", originAppProcessID: 2)))
    }
}
extension ReviewAndWindowTests {
    @MainActor @Test func terminalFailuresAreDistinctAndMissingTabsRecoverHonestly() {
        #expect(TerminalConnector.classifyFailure(errorCode: -1743, resultCode: nil, hadError: true) == .permissionDenied)
        #expect(TerminalConnector.classifyFailure(errorCode: -1712, resultCode: nil, hadError: true) == .timedOut)
        #expect(TerminalConnector.classifyFailure(errorCode: -1708, resultCode: 0, hadError: true) == .automationFailed)
        #expect(TerminalConnector.classifyFailure(errorCode: nil, resultCode: nil, hadError: false) == .automationFailed)
        #expect(TerminalConnector.classifyFailure(errorCode: nil, resultCode: 0, hadError: false) == .noMatchingTab)
        #expect(TerminalConnector.classifyFailure(errorCode: nil, resultCode: 1, hadError: false) == nil)
        #expect(SessionWindowConnector.terminalRecovery(.noMatchingTab, activation: .appActivated) == .appActivatedWithoutTab)
        #expect(SessionWindowConnector.terminalRecovery(.noMatchingTab, activation: .failed("Fixture")) == .terminalFailure(.noMatchingTab))
        #expect(SessionWindowConnector.terminalRecovery(.permissionDenied, activation: nil) == .terminalFailure(.permissionDenied))
        #expect(L10n.text(TerminalFocusFailure.automationFailed.message, language: .english) == "Unable to read terminal windows")
    }

    @MainActor @Test func incompleteTmuxConnectionDoesNotClaimPaneFocus() async {
        let runtime = SessionRuntime(processID: 42, terminalBundleID: "com.apple.Terminal", tmuxPane: "%1", tmuxClientTTY: "/dev/ttys001")
        #expect(await TerminalConnector.focusFailure(runtime) == .tmuxUnavailable)
    }
}
