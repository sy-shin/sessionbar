import Foundation
import SessionbarCore

struct RepositoryResult: Sendable {
    let snapshots: [URL: SessionSnapshot]
    let failedDirectories: Int
    let invalidFiles: Int
    let malformedLines: Int
}

private final class SessionReadJob: @unchecked Sendable {
    private let lock = NSLock()
    private var value: (IncrementalSessionReader, SessionSnapshot?)?

    init(reader: IncrementalSessionReader) {
        DispatchQueue.global(qos: .utility).async { [self] in
            var reader = reader
            let snapshot = reader.read()
            lock.lock(); value = (reader, snapshot); lock.unlock()
        }
    }

    var result: (IncrementalSessionReader, SessionSnapshot?)? {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}

actor SessionRepository {
    private var readers: [URL: IncrementalSessionReader] = [:]
    private var snapshots: [URL: SessionSnapshot] = [:]
    private var trackedLiveFiles = Set<URL>()
    private var historyIndexes: [URL: SessionHistoryIndex] = [:]
    private var activeJobs: [URL: SessionReadJob] = [:]

    func scan(directories: [String], activeFiles: [URL] = []) async -> RepositoryResult {
        trackedLiveFiles.formUnion(activeFiles)
        var visited = Set<URL>(), failed = 0, invalid = 0
        for directory in directories {
            let root = URL(fileURLWithPath: directory, isDirectory: true)
            guard let enumerator = FileManager.default.enumerator(at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { failed += 1; continue }
            while let candidate = enumerator.nextObject() as? URL {
                guard candidate.pathExtension == "jsonl" else { continue }
                let url = candidate.standardizedFileURL
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                      values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                visited.insert(url)
                var reader = readers[url] ?? IncrementalSessionReader(url: url)
                if let snapshot = reader.read() { snapshots[url] = snapshot } else { invalid += 1; snapshots.removeValue(forKey: url) }
                readers[url] = reader
            }
        }
        let extraFiles = trackedLiveFiles.filter { !visited.contains($0) }
        for url in extraFiles {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            visited.insert(url)
            // An active file outside the configured folders may wait indefinitely
            // on a provider or permission. One pending read must not delay other sessions.
            if activeJobs[url] == nil, activeJobs.count < 16 {
                activeJobs[url] = SessionReadJob(reader: readers[url] ?? IncrementalSessionReader(url: url))
            }
        }
        for _ in 0..<10 {
            guard extraFiles.contains(where: { activeJobs[$0]?.result == nil }) else { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        for url in extraFiles where visited.contains(url) {
            guard let result = activeJobs[url]?.result else { invalid += 1; continue }
            readers[url] = result.0
            if let snapshot = result.1 { snapshots[url] = snapshot }
            else { invalid += 1; snapshots.removeValue(forKey: url) }
            activeJobs.removeValue(forKey: url)
        }
        trackedLiveFiles = trackedLiveFiles.filter { visited.contains($0) }
        readers = readers.filter { visited.contains($0.key) }
        snapshots = snapshots.filter { visited.contains($0.key) }
        historyIndexes = historyIndexes.filter { visited.contains($0.key) }
        activeJobs = activeJobs.filter { visited.contains($0.key) }
        return RepositoryResult(snapshots: snapshots, failedDirectories: failed, invalidFiles: invalid,
                                malformedLines: snapshots.values.reduce(0) { $0 + $1.malformedLines })
    }

    func detail(url: URL) -> SessionDetail? {
        if activeJobs[url] != nil { return snapshots[url]?.detail }
        var reader = readers[url] ?? IncrementalSessionReader(url: url)
        let snapshot = reader.read()
        readers[url] = reader
        return snapshot?.detail
    }

    func history(from start: Date, to end: Date) -> [SessionHistoryItem] {
        var items: [SessionHistoryItem] = []
        for url in readers.keys where activeJobs[url] == nil {
            if Task.isCancelled { break }
            var index = historyIndexes[url] ?? SessionHistoryIndex(url: url)
            items.append(contentsOf: index.read(from: start, to: end))
            historyIndexes[url] = index
        }
        var byID: [String: SessionHistoryItem] = [:]
        for item in items { byID[item.id] = item }
        return byID.values.sorted { $0.date > $1.date }
    }
}
