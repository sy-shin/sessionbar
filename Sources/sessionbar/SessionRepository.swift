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

    func scan(directories: [String]) -> RepositoryResult {
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
        readers = readers.filter { visited.contains($0.key) }
        snapshots = snapshots.filter { visited.contains($0.key) }
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
        let items = readers.keys.flatMap { SessionHistoryReader.read(url: $0, from: start, to: end) }
        var byID: [String: SessionHistoryItem] = [:]
        for item in items { byID[item.id] = item }
        return byID.values.sorted { $0.date > $1.date }
    }
}
