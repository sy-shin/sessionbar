import Foundation
import Testing
@testable import SessionbarCore

@Suite struct NotificationTests {
    private func record(_ state: SessionState, at date: Date) -> SessionRecord {
        SessionRecord(id: "sample", projectPath: "/tmp/project", title: "sample", lastActivity: date,
                      state: state, source: "cli", runtime: state == .needsAttentionEstimate ? SessionRuntime(processID: 1) : nil, stateRecordedAt: date)
    }

    @Test func historicalCompletionDoesNotNotifyAndNewTransitionsNotifyOnce() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var tracker = NotificationTracker(), preferences = NotificationPreferences()
        preferences.completion = true
        #expect(tracker.observe([record(.completed, at: now)], preferences: preferences, now: now).isEmpty)
        _ = tracker.observe([record(.runningEstimate, at: now.addingTimeInterval(1))], preferences: preferences, now: now)
        let complete = record(.completed, at: now.addingTimeInterval(2))
        #expect(tracker.observe([complete], preferences: preferences, now: now.addingTimeInterval(2)).count == 1)
        #expect(tracker.observe([complete], preferences: preferences, now: now.addingTimeInterval(3)).isEmpty)
    }

    @Test func pausedAttentionIsDeliveredWhenResumedAndClearedIfResolved() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var tracker = NotificationTracker(), preferences = NotificationPreferences()
        preferences.attention = true; preferences.pauseUntil = now.addingTimeInterval(60)
        let attention = record(.needsAttentionEstimate, at: now)
        #expect(tracker.observe([attention], preferences: preferences, now: now).isEmpty)
        #expect(tracker.observe([attention], preferences: preferences, now: now.addingTimeInterval(61)).count == 1)
        var resolved = NotificationTracker()
        _ = resolved.observe([attention], preferences: preferences, now: now)
        #expect(resolved.observe([record(.completed, at: now.addingTimeInterval(1))], preferences: preferences, now: now.addingTimeInterval(61)).isEmpty)
    }

    @Test func quietHoursAndCooldownDelayRepeatedRequests() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-10-08T23:00:00Z")!
        var tracker = NotificationTracker(), preferences = NotificationPreferences()
        preferences.attention = true; preferences.quietHours = true
        let attention = record(.needsAttentionEstimate, at: now)
        #expect(tracker.observe([attention], preferences: preferences, now: now, calendar: calendar).isEmpty)
        let morning = now.addingTimeInterval(9 * 3600)
        #expect(tracker.observe([attention], preferences: preferences, now: morning, calendar: calendar).count == 1)
        let second = record(.needsAttentionEstimate, at: morning.addingTimeInterval(1))
        #expect(tracker.observe([second], preferences: preferences, now: morning.addingTimeInterval(1), calendar: calendar).isEmpty)
        #expect(tracker.observe([second], preferences: preferences, now: morning.addingTimeInterval(601), calendar: calendar).count == 1)
    }
}

extension NotificationTests {
    @Test func lateHistoricalDiscoveryDoesNotNotifyAndFailedDeliveryRetries() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var tracker = NotificationTracker(), preferences = NotificationPreferences()
        preferences.completion = true
        _ = tracker.observe([], preferences: preferences, now: now)
        #expect(tracker.observe([record(.completed, at: now.addingTimeInterval(-100))], preferences: preferences, now: now.addingTimeInterval(1)).isEmpty)
        let current = record(.completed, at: now.addingTimeInterval(2))
        #expect(tracker.observe([current], preferences: preferences, now: now.addingTimeInterval(2)).count == 1)
        tracker.deliveryFailed(current)
        #expect(tracker.observe([current], preferences: preferences, now: now.addingTimeInterval(3)).count == 1)
    }

    @Test func queuedResultsCancelWhenNewWorkStartsAndStaleRequestsDoNotDeliver() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var tracker = NotificationTracker(), preferences = NotificationPreferences()
        preferences.completion = true; preferences.attention = true; preferences.pauseUntil = now.addingTimeInterval(60)
        _ = tracker.observe([], preferences: preferences, now: now)
        _ = tracker.observe([record(.completed, at: now.addingTimeInterval(1))], preferences: preferences, now: now.addingTimeInterval(2))
        #expect(tracker.observe([record(.runningEstimate, at: now.addingTimeInterval(3))], preferences: preferences, now: now.addingTimeInterval(61)).isEmpty)
        var attentionTracker = NotificationTracker()
        _ = attentionTracker.observe([record(.needsAttentionEstimate, at: now)], preferences: preferences, now: now)
        let stale = SessionRecord(id: "sample", projectPath: "/tmp/project", title: "sample", lastActivity: now, state: .unknown, source: nil, runtime: SessionRuntime(processID: 1), stateRecordedAt: now, isRuntimeStale: true)
        #expect(attentionTracker.observe([stale], preferences: preferences, now: now.addingTimeInterval(61)).isEmpty)
        #expect(attentionTracker.observe([record(.needsAttentionEstimate, at: now)], preferences: preferences, now: now.addingTimeInterval(62)).count == 1)
    }
}
