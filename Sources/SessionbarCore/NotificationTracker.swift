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
}

public struct NotificationTracker {
    private var observed: [String: String] = [:]
    private var pending: [String: SessionRecord] = [:]
    private var lastDelivered: [String: Date] = [:]
    private var initialized = false
    public init() {}

    public mutating func resetAttention() {
        observed = observed.filter { !$0.value.hasPrefix(SessionState.needsAttentionEstimate.rawValue) }
    }

    public mutating func observe(_ records: [SessionRecord], preferences: NotificationPreferences,
                                 now: Date = .now, calendar: Calendar = .current) -> [SessionRecord] {
        let activeIDs = Set(records.map(\.id))
        pending = pending.filter { activeIDs.contains($0.key) }
        for record in records {
            let key = "\(record.state.rawValue):\(record.stateRecordedAt.timeIntervalSince1970)"
            if record.state == .needsAttentionEstimate {
                if observed[record.id] != key && preferences.attention { pending[record.id] = record }
            } else if initialized && observed[record.id] != key && isEnabled(record.state, preferences) {
                if record.state == .completed || record.state == .error { pending[record.id] = record }
            }
            if let waiting = pending[record.id], waiting.state == .needsAttentionEstimate && record.state != .needsAttentionEstimate {
                pending.removeValue(forKey: record.id)
            }
            observed[record.id] = key
        }
        initialized = true
        observed = observed.filter { activeIDs.contains($0.key) }
        lastDelivered = lastDelivered.filter { now.timeIntervalSince($0.value) < 86_400 }
        if let until = preferences.pauseUntil, until > now { return [] }
        if preferences.quietHours {
            let hour = calendar.component(.hour, from: now)
            let start = preferences.quietStart, end = preferences.quietEnd
            let quiet = start == end || (start < end ? hour >= start && hour < end : hour >= start || hour < end)
            if quiet { return [] }
        }
        var result: [SessionRecord] = []
        for (id, record) in pending {
            guard isEnabled(record.state, preferences) else { pending.removeValue(forKey: id); continue }
            let cooldownKey = id + record.state.rawValue
            guard now.timeIntervalSince(lastDelivered[cooldownKey] ?? .distantPast) >= Double(preferences.cooldownMinutes) * 60 else { continue }
            result.append(record)
            lastDelivered[cooldownKey] = now
            pending.removeValue(forKey: id)
        }
        return result
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
