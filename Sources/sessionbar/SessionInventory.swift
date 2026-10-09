import Foundation
import SessionbarCore

struct SessionInventory {
    let records: [String: SessionRecord]
    let urls: [String: URL]
    let activeCount: Int

    init(snapshots: [URL: SessionSnapshot], runtime: ProcessSnapshot, now: Date,
         placeholderIDs: inout [URL: String]) {
        var byID: [String: (SessionRecord, URL)] = [:]
        for (url, snapshot) in snapshots {
            guard let record = snapshot.record(now: now, runtime: runtime.byFile[url],
                processObservationAvailable: runtime.available) else { continue }
            if let old = byID[record.id], old.0.lastActivity >= record.lastActivity { continue }
            byID[record.id] = (record, url)
        }
        var activeIDs = Set<String>()
        for (url, process) in runtime.byFile {
            if let live = snapshots[url]?.record(now: now, runtime: process) {
                activeIDs.insert(live.id)
                // A resumed session may have several files with the same ID.
                // Use the newest content, preserving its live process association.
                if let chosen = byID[live.id], chosen.0.runtime == nil {
                    let record = chosen.0
                    byID[record.id] = (SessionRecord(id: record.id, projectPath: record.projectPath,
                        title: record.title, lastActivity: record.lastActivity, state: record.state,
                        source: record.source, evidence: record.evidence, runtime: process,
                        stateRecordedAt: record.stateRecordedAt), url)
                }
            } else {
                let id = placeholderIDs[url] ?? "unreadable-\(UUID().uuidString)"
                placeholderIDs[url] = id
                activeIDs.insert(id)
                byID[id] = (SessionRecord(id: id, projectPath: process.workingDirectory ?? "",
                    title: "세션 기록 접근 필요", lastActivity: .distantPast, state: .unknown,
                    source: nil, evidence: "세션 기록을 읽을 수 없습니다", runtime: process, isPlaceholder: true), url)
            }
        }
        placeholderIDs = placeholderIDs.filter { runtime.byFile[$0.key] != nil }
        records = byID.mapValues { $0.0 }; urls = byID.mapValues { $0.1 }
        activeCount = activeIDs.count
    }
}

struct SessionMenuSummary {
    let running: Int
    let active: Int
    let attention: Int
    let errors: Int
    init(records: [SessionRecord], activeCount: Int) {
        let unique = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values
        running = unique.filter { $0.state == .runningEstimate && $0.runtime != nil }.count
        active = activeCount
        attention = unique.filter { $0.state == .needsAttentionEstimate }.count
        errors = unique.filter { $0.state == .error }.count
    }
    func title(compact: Bool, language: AppLanguage = L10n.language) -> String {
        if compact { return "\(running)/\(active)" }
        let counts = String(format: L10n.text("실행 중~ %d · 활성 %d", language: language), running, active)
        return attention > 0 ? String(format: L10n.text("확인~ %d · %@", language: language), attention, counts) : counts
    }
}
