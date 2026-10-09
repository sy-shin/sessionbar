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
        records = byID.mapValues { entry in
            let record = entry.0
            guard !runtime.available, record.runtime != nil else { return record }
            return SessionRecord(id: record.id, projectPath: record.projectPath, title: record.title,
                lastActivity: record.lastActivity, state: .unknown, source: record.source,
                evidence: "프로세스 상태를 확인할 수 없습니다", runtime: record.runtime,
                stateRecordedAt: record.stateRecordedAt, isPlaceholder: record.isPlaceholder, isRuntimeStale: true)
        }
        urls = byID.mapValues { $0.1 }
        activeCount = activeIDs.count
    }
}

enum SessionListFilter: CaseIterable {
    case openSessions, allSessions, attention, unreviewed

    var title: String {
        switch self {
        case .openSessions: return L10n.text("열린 세션")
        case .allSessions: return L10n.text("전체")
        case .attention: return L10n.text("주의 필요")
        case .unreviewed: return L10n.text("미확인")
        }
    }

    var emptyMessage: String {
        switch self {
        case .openSessions: return L10n.text("열린 세션이 없습니다")
        case .allSessions: return L10n.text("표시할 세션이 없습니다")
        case .attention: return L10n.text("주의가 필요한 세션이 없습니다")
        case .unreviewed: return L10n.text("확인할 작업이 없습니다")
        }
    }

    func contains(_ record: SessionRecord) -> Bool {
        switch self {
        case .openSessions: return record.runtime != nil
        case .allSessions: return true
        case .attention:
            return record.runtime != nil &&
                (record.state == .needsAttentionEstimate || record.state == .error)
        case .unreviewed: return true
        }
    }

    func summaryRecords(_ records: [SessionRecord]) -> [SessionRecord] {
        self == .allSessions ? records : records.filter { $0.runtime != nil }
    }
}

struct SessionMenuSummary {
    let running: Int
    let active: Int
    let attention: Int
    let errors: Int
    let unreviewed: Int
    let activeEstimated: Bool
    init(records: [SessionRecord], activeCount: Int, unreviewedCount: Int = 0, processObservationAvailable: Bool = true) {
        let unique = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values
        running = unique.filter { $0.state == .runningEstimate && $0.runtime != nil }.count
        active = activeCount
        unreviewed = unreviewedCount
        activeEstimated = !processObservationAvailable || unique.contains { $0.isRuntimeStale }
        attention = unique.filter { $0.state == .needsAttentionEstimate && $0.runtime != nil }.count
        errors = unique.filter { $0.state == .error && $0.runtime != nil }.count
    }
    func title(compact: Bool, language: AppLanguage = L10n.language) -> String {
        if activeEstimated && active == 0 {
            return compact ? "\(running)/?" : String(format: L10n.text("실행 중~ %d · 활성 ?", language: language), running)
        }
        if compact { return "\(running)/\(activeEstimated ? "~" : "")\(active)" }
        let counts = String(format: L10n.text(activeEstimated ? "실행 중~ %d · 활성~ %d" : "실행 중~ %d · 활성 %d", language: language), running, active)
        if attention > 0 { return String(format: L10n.text("확인~ %d · %@", language: language), attention, counts) }
        return unreviewed > 0 ? String(format: L10n.text("미확인 %d · %@", language: language), unreviewed, counts) : counts
    }
}
