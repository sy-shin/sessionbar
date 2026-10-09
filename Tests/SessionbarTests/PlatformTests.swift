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

    @MainActor @Test func settingsDefaultsAndChangesPersistInIsolatedPreferences() throws {
        let name = "sessionbar-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.retentionDays == 30)
        #expect(settings.refreshInterval == 15)
        #expect(settings.attentionNotifications)
        #expect(!settings.completionNotifications)
        settings.retentionDays = 7; settings.watchFiles = false
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.retentionDays == 7)
        #expect(!reloaded.watchFiles)
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
