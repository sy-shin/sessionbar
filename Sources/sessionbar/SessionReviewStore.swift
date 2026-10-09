import Foundation
import SessionbarCore

@MainActor
final class SessionReviewStore {
    private let defaults: UserDefaults
    private var tracker: SessionReviewTracker
    private let key = "sessionbar.reviewMarkers"

    init(defaults: UserDefaults = .standard, now: Date = .now) {
        self.defaults = defaults
        tracker = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(SessionReviewTracker.self, from: $0) } ?? SessionReviewTracker(now: now)
    }

    func observe(_ records: [SessionRecord]) { tracker.observe(records); save() }
    func pending(id: String) -> SessionReviewEvent? { tracker.pending(id: id) }
    func markReviewed(id: String, token: String) { tracker.markReviewed(id: id, token: token); save() }
    private func save() {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(tracker), defaults.data(forKey: key) != data else { return }
        defaults.set(data, forKey: key)
    }
}
