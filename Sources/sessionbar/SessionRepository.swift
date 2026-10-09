import Foundation
import SessionbarCore

struct RepositoryResult: Sendable {
    let snapshots: [URL: SessionSnapshot]
    let failedDirectories: Int
    let invalidFiles: Int
    let malformedLines: Int
}

actor SessionRepository {
    private var readers: [URL: IncrementalSessionReader] = [:]
    private var snapshots: [URL: SessionSnapshot] = [:]
    private var trackedLiveFiles = Set<URL>()
    private var historyIndexes: [URL: SessionHistoryIndex] = [:]

    func scan(directories: [String], activeFiles: [URL] = []) -> RepositoryResult {
        trackedLiveFiles.formUnion(activeFiles)
        var visited = Set<URL>(), failed = 0, invalid = 0
        for directory in directories {
            let root = URL(fileURLWithPath: directory, isDirectory: true)
            guard let enumerator = FileManager.default.enumerator(at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { failed += 1; continue }
            for case let candidate as URL in enumerator where candidate.pathExtension == "jsonl" {
                let url = candidate.standardizedFileURL
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                      values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                visited.insert(url)
                var reader = readers[url] ?? IncrementalSessionReader(url: url)
                if let snapshot = reader.read() { snapshots[url] = snapshot } else { invalid += 1; snapshots.removeValue(forKey: url) }
                readers[url] = reader
            }
        }
        for url in trackedLiveFiles where !visited.contains(url) {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            visited.insert(url)
            var reader = readers[url] ?? IncrementalSessionReader(url: url)
            if let snapshot = reader.read() { snapshots[url] = snapshot } else { invalid += 1; snapshots.removeValue(forKey: url) }
            readers[url] = reader
        }
        trackedLiveFiles = trackedLiveFiles.filter { visited.contains($0) }
        readers = readers.filter { visited.contains($0.key) }
        snapshots = snapshots.filter { visited.contains($0.key) }
        historyIndexes = historyIndexes.filter { visited.contains($0.key) }
        return RepositoryResult(snapshots: snapshots, failedDirectories: failed, invalidFiles: invalid,
                                malformedLines: snapshots.values.reduce(0) { $0 + $1.malformedLines })
    }

    func detail(url: URL) -> SessionDetail? {
        var reader = readers[url] ?? IncrementalSessionReader(url: url)
        let snapshot = reader.read()
        readers[url] = reader
        return snapshot?.detail
    }

    func history(from start: Date, to end: Date) -> [SessionHistoryItem] {
        var items: [SessionHistoryItem] = []
        for url in readers.keys {
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
