import Foundation

public struct NotificationPreferences: Sendable {
    public var attention = false
    public var completion = false
    public var error = false
    public var quietHours = false
    public var quietStart = 22
    public var quietEnd = 8
    public var pauseUntil: Date?
    public var cooldownMinutes = 10
    public init() {}

    public func allowsDelivery(at now: Date, calendar: Calendar = .current) -> Bool {
        if let until = pauseUntil, until > now { return false }
        guard quietHours else { return true }
        let hour = calendar.component(.hour, from: now)
        return quietStart != quietEnd && !(quietStart < quietEnd ? hour >= quietStart && hour < quietEnd : hour >= quietStart || hour < quietEnd)
    }
}

public struct NotificationTracker {
    private var observed: [String: String] = [:]
    private var pending: [String: SessionRecord] = [:]
    private var lastDelivered: [String: Date] = [:]
    private var initialized = false
    private var startedAt: Date?
    public init() {}

    public mutating func resetAttention() {
        observed = observed.filter { !$0.value.hasPrefix(SessionState.needsAttentionEstimate.rawValue) }
    }

    public mutating func observe(_ records: [SessionRecord], preferences: NotificationPreferences,
                                 now: Date = .now, calendar: Calendar = .current) -> [SessionRecord] {
        let activeIDs = Set(records.map(\.id))
        if startedAt == nil { startedAt = now }
        pending = pending.filter { activeIDs.contains($0.key) }
        for record in records {
            let key = record.eventToken
            if record.isRuntimeStale { continue }
            if record.state == .needsAttentionEstimate && record.runtime != nil {
                if observed[record.id] != key && preferences.attention { pending[record.id] = record }
            } else if initialized && observed[record.id] != key && isEnabled(record.state, preferences) &&
                        record.stateRecordedAt > (startedAt ?? now) {
                if record.state == .completed || record.state == .error { pending[record.id] = record }
            }
            if let waiting = pending[record.id], waiting.eventToken != key ||
                (waiting.state == .needsAttentionEstimate && record.runtime == nil) {
                pending.removeValue(forKey: record.id)
            }
            observed[record.id] = key
        }
        initialized = true
        observed = observed.filter { activeIDs.contains($0.key) }
        lastDelivered = lastDelivered.filter { now.timeIntervalSince($0.value) < 86_400 }
        guard preferences.allowsDelivery(at: now, calendar: calendar) else { return [] }
        var result: [SessionRecord] = []
        let staleIDs = Set(records.filter { $0.isRuntimeStale }.map(\.id))
        for (id, record) in pending {
            guard !staleIDs.contains(id) else { continue }
            guard isEnabled(record.state, preferences) else { pending.removeValue(forKey: id); continue }
            let cooldownKey = id + record.state.rawValue
            guard now.timeIntervalSince(lastDelivered[cooldownKey] ?? .distantPast) >= Double(preferences.cooldownMinutes) * 60 else { continue }
            result.append(record)
            lastDelivered[cooldownKey] = now
            pending.removeValue(forKey: id)
        }
        return result
    }

    public mutating func deliveryFailed(_ record: SessionRecord) {
        guard observed[record.id] == record.eventToken else { return }
        pending[record.id] = record
        lastDelivered.removeValue(forKey: record.id + record.state.rawValue)
    }

    private func isEnabled(_ state: SessionState, _ preferences: NotificationPreferences) -> Bool {
        switch state {
        case .needsAttentionEstimate: preferences.attention
        case .completed: preferences.completion
        case .error: preferences.error
        default: false
        }
    }
}
