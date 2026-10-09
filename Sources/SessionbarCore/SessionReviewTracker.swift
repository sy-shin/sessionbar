import Foundation

public struct SessionReviewEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case attention, completed, error }
    public let kind: Kind
    public let date: Date
    public let token: String
    public var reviewed: Bool

    public init?(record: SessionRecord) {
        guard !record.isPlaceholder, !record.isRuntimeStale,
              record.stateRecordedAt > Date(timeIntervalSince1970: 0) else { return nil }
        switch record.state {
        case .needsAttentionEstimate where record.runtime != nil: kind = .attention
        case .completed: kind = .completed
        case .error: kind = .error
        default: return nil
        }
        date = record.stateRecordedAt
        token = record.eventToken
        reviewed = false
    }
}

/// Keeps review markers, never conversation contents or project paths.
public struct SessionReviewTracker: Codable, Sendable {
    private let trackingSince: Date
    private var events: [String: SessionReviewEvent] = [:]

    public init(now: Date = .now) { trackingSince = now }

    public mutating func observe(_ records: [SessionRecord]) {
        for record in records {
            guard let event = SessionReviewEvent(record: record) else {
                if events[record.id]?.kind == .attention && !record.isRuntimeStale { events.removeValue(forKey: record.id) }
                continue
            }
            if let previous = events[record.id] {
                if previous.token == event.token || previous.date > event.date { continue }
            } else if event.kind != .attention && record.runtime == nil && event.date < trackingSince {
                continue
            }
            events[record.id] = event
        }
        let live = Set(records.filter { $0.runtime != nil }.map(\.id))
        events = events.filter { $0.value.kind != .attention || live.contains($0.key) }
    }

    public func pending(id: String) -> SessionReviewEvent? {
        guard let event = events[id], !event.reviewed else { return nil }
        return event
    }

    public mutating func markReviewed(id: String, token: String) {
        guard events[id]?.token == token else { return }
        events[id]?.reviewed = true
    }
}
