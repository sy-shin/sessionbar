import Foundation
import SessionbarCore

struct RepositoryResult: Sendable {
    let snapshots: [URL: SessionSnapshot]
    let failedDirectories: Int
    let invalidFiles: Int
    let malformedLines: Int
    let pendingFiles: Set<URL>
}

/// A filesystem operation can remain inside macOS access checks. Keep each operation
/// off the repository actor and bound the number of outstanding workers.
private final class FileJob<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?
    init(_ work: @escaping () -> Value) {
        DispatchQueue.global(qos: .utility).async { [self] in
            let result = work()
            lock.lock(); value = result; lock.unlock()
        }
    }
    var result: Value? { lock.lock(); defer { lock.unlock() }; return value }
}

actor SessionRepository {
    private var readers: [URL: IncrementalSessionReader] = [:]
    private var snapshots: [URL: SessionSnapshot] = [:]
    private var trackedLiveFiles = Set<URL>()
    private var historyIndexes: [URL: SessionHistoryIndex] = [:]
    private var fileJobs: [URL: FileJob<(IncrementalSessionReader, SessionSnapshot?)>] = [:]
    private var directoryJobs: [String: FileJob<(Set<URL>, Bool)>] = [:]
    private var directoryFiles: [String: Set<URL>] = [:]
    private var scheduledReads: [URL: Date] = [:]
    private var retiredJobs: [() -> Bool] = []
    private let beforeRead: @Sendable (URL) -> Void

    init(beforeRead: @escaping @Sendable (URL) -> Void = { _ in }) { self.beforeRead = beforeRead }

    func retryAfterFolderConnection() {
        // An old system call cannot be cancelled. Keep references bounded across retries.
        retiredJobs.removeAll { $0() }
        let pending = fileJobs.values.filter { $0.result == nil }.count + directoryJobs.values.filter { $0.result == nil }.count
        guard retiredJobs.count + pending <= 32 else { return }
        for job in fileJobs.values where job.result == nil { retiredJobs.append { job.result != nil } }
        for job in directoryJobs.values where job.result == nil { retiredJobs.append { job.result != nil } }
        fileJobs.removeAll(); directoryJobs.removeAll()
    }

    func scan(directories: [String], activeFiles: [URL] = []) async -> RepositoryResult {
        retiredJobs.removeAll { $0() }
        trackedLiveFiles.formUnion(activeFiles.map(\.standardizedFileURL))
        for path in directories where directoryJobs[path] == nil && directoryJobs.count < 16 {
            directoryJobs[path] = FileJob {
                let root = URL(fileURLWithPath: path, isDirectory: true)
                var failed = false, files = Set<URL>()
                guard let enumerator = FileManager.default.enumerator(at: root,
                    includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                    errorHandler: { _, _ in failed = true; return false }) else { return (files, true) }
                while let candidate = enumerator.nextObject() as? URL {
                    guard candidate.pathExtension == "jsonl",
                          let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                          values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                    files.insert(candidate.standardizedFileURL)
                }
                return (files, failed)
            }
        }
        // Wait briefly for fast local operations; never await a blocked open indefinitely.
        for _ in 0..<5 {
            if !directories.contains(where: { directoryJobs[$0]?.result == nil }) { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        var failed = 0
        for path in directories {
            if let result = directoryJobs[path]?.result {
                directoryFiles[path] = result.0
                if result.1 { failed += 1 }
                directoryJobs.removeValue(forKey: path)
            } else { failed += 1 }
        }
        directoryFiles = directoryFiles.filter { directories.contains($0.key) }
        directoryJobs = directoryJobs.filter { directories.contains($0.key) || $0.value.result == nil }
        let visited = directoryFiles.values.reduce(into: trackedLiveFiles) { $0.formUnion($1) }
        let live = Set(activeFiles.map(\.standardizedFileURL))
        let ordered = visited.sorted {
            if live.contains($0) != live.contains($1) { return live.contains($0) }
            let left = scheduledReads[$0] ?? .distantPast, right = scheduledReads[$1] ?? .distantPast
            return left == right ? $0.path < $1.path : left < right
        }
        var attempted = Set(fileJobs.keys), invalid = 0
        // Refill completed worker slots during a short scan budget. Historical files
        // rotate fairly across scans, so a large archive cannot starve newer records.
        for step in 0...15 {
            for url in ordered {
                guard let result = fileJobs[url]?.result else { continue }
                readers[url] = result.0
                if let snapshot = result.1 { snapshots[url] = snapshot }
                else { invalid += 1; snapshots.removeValue(forKey: url) }
                fileJobs.removeValue(forKey: url)
            }
            for url in ordered where !attempted.contains(url) && fileJobs.count < 16 {
                let reader = readers[url] ?? IncrementalSessionReader(url: url)
                let beforeRead = self.beforeRead
                fileJobs[url] = FileJob {
                    beforeRead(url)
                    var updated = reader
                    let snapshot = updated.read()
                    return (updated, snapshot)
                }
                attempted.insert(url); scheduledReads[url] = Date()
            }
            if step == 15 || (fileJobs.isEmpty && attempted.isSuperset(of: visited)) { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        let pending = Set(ordered.filter { fileJobs[$0] != nil || !attempted.contains($0) })
        scheduledReads = scheduledReads.filter { visited.contains($0.key) }
        readers = readers.filter { visited.contains($0.key) }
        snapshots = snapshots.filter { visited.contains($0.key) }
        historyIndexes = historyIndexes.filter { visited.contains($0.key) }
        fileJobs = fileJobs.filter { visited.contains($0.key) || $0.value.result == nil }
        return RepositoryResult(snapshots: snapshots, failedDirectories: failed, invalidFiles: invalid + pending.count,
            malformedLines: snapshots.values.reduce(0) { $0 + $1.malformedLines }, pendingFiles: pending)
    }

    func detail(url: URL) -> SessionDetail? { snapshots[url]?.detail }

    func history(from start: Date, to end: Date) -> [SessionHistoryItem] {
        var items: [SessionHistoryItem] = []
        for url in readers.keys where fileJobs[url] == nil {
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
