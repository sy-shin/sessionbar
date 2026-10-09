import Foundation
import Testing
import AppKit
@testable import SessionbarCore
@testable import sessionbar

@Suite struct PlatformTests {
    @Test func openSessionFileMapsToProcessAndDisappearsAfterExit() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "sessionbar-process-\(UUID().uuidString)")
        let sessions = root.appending(path: "sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = sessions.appending(path: "rollout-test.jsonl")
        try Data("{}\n".utf8).write(to: file)
        let source = root.appending(path: "fixture.c"), executable = root.appending(path: "codex")
        try "#include <fcntl.h>\n#include <unistd.h>\nint main(int argc,char**argv){if(argc!=2||open(argv[1],O_RDONLY)<0)return 2;pause();return 0;}\n".write(to: source, atomically: true, encoding: .utf8)
        let compilation = CommandRunner.run("/usr/bin/clang", [source.path, "-o", executable.path])
        #expect(compilation.status == 0)
        let process = Process(); process.executableURL = executable; process.arguments = [file.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
        defer { if process.isRunning { process.terminate(); process.waitUntilExit() } }
        let observer = ProcessObserver()
        var snapshot = await observer.scan()
        for _ in 0..<5 where snapshot.byFile[file.standardizedFileURL] == nil {
            try await Task.sleep(nanoseconds: 100_000_000); snapshot = await observer.scan()
        }
        #expect(snapshot.available)
        #expect(snapshot.byFile[file.standardizedFileURL]?.processID == process.processIdentifier)
        process.terminate(); process.waitUntilExit()
        let ended = await observer.scan()
        #expect(ended.byFile[file.standardizedFileURL] == nil)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func activeFilesOutsideConfiguredFoldersAreReadOnlyAndRemainAfterExit() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "sessionbar-active-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let data = Data((#"{"type":"session_meta","payload":{"id":"outside","cwd":"/tmp/project"},"timestamp":"2026-10-08T10:00:00Z"}"# + "\n").utf8)
        try data.write(to: file)
        let repository = SessionRepository()
        let active = await repository.scan(directories: [], activeFiles: [file])
        #expect(active.snapshots.count == 1)
        let ended = await repository.scan(directories: [])
        #expect(ended.snapshots.count == 1)
        #expect(try Data(contentsOf: file) == data)
    }

    @Test func blockedActiveReadDoesNotEmptyOtherSessionsAndRecovers() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "sessionbar-delay-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let slow = root.appending(path: "slow.jsonl"), fast = root.appending(path: "fast.jsonl")
        let slowData = Data((#"{"type":"session_meta","payload":{"id":"slow","cwd":"/tmp/slow"}}"# + "\n").utf8)
        try slowData.write(to: slow)
        try Data((#"{"type":"session_meta","payload":{"id":"fast","cwd":"/tmp/fast"}}"# + "\n").utf8).write(to: fast)
        let gate = DispatchSemaphore(value: 0)
        let repository = SessionRepository(beforeRead: { url in if url == slow { gate.wait() } })
        let began = Date()
        let result = await repository.scan(directories: [], activeFiles: [slow, fast])
        #expect(Date().timeIntervalSince(began) < 2)
        #expect(result.snapshots[fast] != nil)
        #expect(result.pendingFiles.contains(slow))
        gate.signal()
        let recovered = await repository.scan(directories: [], activeFiles: [slow, fast])
        #expect(recovered.snapshots.count == 2)
        #expect(recovered.pendingFiles.isEmpty)
        #expect(try Data(contentsOf: slow) == slowData)
    }

    @Test func missingAndCorruptActiveFilesDoNotRemoveValidSession() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "sessionbar-invalid-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let corrupt = root.appending(path: "corrupt.jsonl"), valid = root.appending(path: "valid.jsonl")
        try Data("invalid\n".utf8).write(to: corrupt)
        try Data((#"{"type":"session_meta","payload":{"id":"valid","cwd":"/tmp/project"}}"# + "\n").utf8).write(to: valid)
        let repository = SessionRepository()
        let result = await repository.scan(directories: [], activeFiles: [valid, corrupt, root.appending(path: "missing.jsonl")])
        #expect(result.snapshots.count == 1)
        #expect(result.invalidFiles == 2)
    }

    @Test func translationsCoverStatesAndPreserveUserRequestText() {
        for state in SessionState.allCases {
            #expect(L10n.text(state.koreanLabel, language: .korean) == state.koreanLabel)
            #expect(L10n.text(state.koreanLabel, language: .english) != state.koreanLabel)
        }
        #expect(L10n.text("세션 폴더 연결…", language: .english) == "Connect session folder…")
        #expect(L10n.text("프로젝트 또는 세션 검색", language: .english) == "Search projects or sessions")
        #expect(L10n.text("실행 중~ %d · 활성 %d", language: .english) == "Running~ %d · Active %d")
        #expect(L10n.text("arbitrary user prompt", language: .korean) == "arbitrary user prompt")
        #expect(AppLanguage.korean.locale.identifier.hasPrefix("ko"))
        #expect(AppLanguage.english.locale.identifier.hasPrefix("en"))
    }

    @Test func activeCountsIncludeIdleAndUnreadableButDeduplicateSessionIDs() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "sessionbar-count-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appending(path: "first.jsonl"), duplicate = root.appending(path: "duplicate.jsonl"), done = root.appending(path: "done.jsonl")
        let running = #"{"type":"session_meta","payload":{"id":"running","cwd":"/tmp/project"},"timestamp":"2026-10-08T10:00:00Z"}"# + "\n" + #"{"type":"event_msg","payload":{"type":"task_started"},"timestamp":"2026-10-08T10:00:00Z"}"# + "\n"
        try Data(running.utf8).write(to: first); try Data(running.utf8).write(to: duplicate)
        try Data((#"{"type":"session_meta","payload":{"id":"done","cwd":"/tmp/project"},"timestamp":"2026-10-08T10:00:00Z"}"# + "\n" + #"{"type":"event_msg","payload":{"type":"task_complete"},"timestamp":"2026-10-08T10:00:00Z"}"# + "\n").utf8).write(to: done)
        var snapshots: [URL: SessionSnapshot] = [:]
        for file in [first, duplicate, done] { var reader = IncrementalSessionReader(url: file); let snapshot = reader.read(); snapshots[file] = snapshot }
        let unreadable = root.appending(path: "unreadable.jsonl")
        let runtime = ProcessSnapshot(byFile: [first: SessionRuntime(processID: 1), duplicate: SessionRuntime(processID: 2), done: SessionRuntime(processID: 3), unreadable: SessionRuntime(processID: 4)], codexCount: 8, available: true)
        var ids: [URL: String] = [:]
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-08T10:00:30Z"))
        let inventory = SessionInventory(snapshots: snapshots, runtime: runtime, now: now, placeholderIDs: &ids)
        #expect(inventory.records.count == 3)
        #expect(inventory.activeCount == 3)
        #expect(inventory.records.values.filter(\.isPlaceholder).count == 1)
        #expect(inventory.records.values.filter(\.isPlaceholder).first?.state == .unknown)
        let summary = SessionMenuSummary(records: Array(inventory.records.values), activeCount: inventory.activeCount)
        #expect(summary.running == 1)
        #expect(summary.title(compact: false, language: .korean) == "실행 중~ 1 · 활성 3")
        #expect(summary.title(compact: false, language: .english) == "Running~ 1 · Active 3")
        #expect(summary.title(compact: true) == "1/3")
        let later = SessionInventory(snapshots: snapshots, runtime: runtime, now: now.addingTimeInterval(300), placeholderIDs: &ids)
        #expect(SessionMenuSummary(records: Array(later.records.values), activeCount: later.activeCount).running == 0)
        #expect(later.activeCount == 3)
    }

    @MainActor @Test func fileChangeMonitorObservesUpdates() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "sessionbar-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let monitor = FileChangeMonitor()
        var changed = false
        monitor.start(paths: [root.path]) { changed = true }
        defer { monitor.stop() }
        try await Task.sleep(nanoseconds: 150_000_000)
        try Data("fixture".utf8).write(to: root.appending(path: "activity.jsonl"))
        for _ in 0..<15 where !changed { try await Task.sleep(nanoseconds: 200_000_000) }
        #expect(changed)
    }

    @MainActor @Test func folderConnectionsPersistReadOnlyBookmarksAndCanBeRemoved() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "sessionbar-folder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "sessionbar-folder-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let access = SessionFolderAccess(defaults: defaults)
        try access.connect(root)
        #expect((defaults.dictionary(forKey: "sessionbar.folderBookmarks") as? [String: Data])?[root.path] != nil)
        await access.restore()
        access.disconnect(path: root.path)
        #expect(defaults.dictionary(forKey: "sessionbar.folderBookmarks")?.isEmpty == true)
    }

    @Test func archiveLargerThanWorkerLimitIsEventuallyRead() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "sessionbar-archive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<70 {
            let line = "{\"type\":\"session_meta\",\"payload\":{\"id\":\"fixture-\(index)\",\"cwd\":\"/tmp/project\"}}\n"
            try Data(line.utf8).write(to: root.appending(path: "fixture-\(index).jsonl"))
        }
        let repository = SessionRepository()
        var count = 0
        for _ in 0..<5 {
            count = await repository.scan(directories: [root.path]).snapshots.count
            if count == 70 { break }
        }
        #expect(count == 70)
    }

    @MainActor @Test func settingsDefaultsAndChangesPersistInIsolatedPreferences() throws {
        let name = "sessionbar-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.retentionDays == 30)
        #expect(settings.refreshInterval == 15)
        #expect(settings.attentionNotifications)
        #expect(!settings.completionNotifications)
        settings.retentionDays = 7; settings.watchFiles = false; settings.language = .english
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.retentionDays == 7)
        #expect(!reloaded.watchFiles)
        #expect(reloaded.language == .english)
    }

    @MainActor @Test func terminalScriptsCompileAgainstInstalledDictionaries() {
        for bundleID in ["com.apple.Terminal", "com.googlecode.iterm2"] {
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else { continue }
            let source = TerminalConnector.scriptSource(bundleID: bundleID, tty: "/dev/ttys001")
            var error: NSDictionary?
            let compiled = NSAppleScript(source: source)?.compileAndReturnError(&error)
            #expect(compiled == true)
        }
    }

    @MainActor @Test func unsupportedTerminalUsesFallbackWithoutAutomation() async {
        let unsupported = SessionRuntime(processID: 1, tty: "/dev/ttys001", terminalName: "Other", terminalBundleID: "example.unsupported")
        #expect(!TerminalConnector.canReturn(unsupported))
        #expect(await TerminalConnector.focus(unsupported) != nil)
        let unsafeTTY = SessionRuntime(processID: 1, tty: "invalid\" input", terminalBundleID: "com.apple.Terminal")
        #expect(!TerminalConnector.canReturn(unsafeTTY))
    }
}
