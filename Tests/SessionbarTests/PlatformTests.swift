import Foundation
import Testing
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

    @MainActor @Test func unsupportedTerminalUsesFallbackWithoutAutomation() async {
        let unsupported = SessionRuntime(processID: 1, tty: "/dev/ttys001", terminalName: "Other", terminalBundleID: "example.unsupported")
        #expect(!TerminalConnector.canReturn(unsupported))
        #expect(await TerminalConnector.focus(unsupported) != nil)
        let unsafeTTY = SessionRuntime(processID: 1, tty: "invalid\" input", terminalBundleID: "com.apple.Terminal")
        #expect(!TerminalConnector.canReturn(unsafeTTY))
    }
}
