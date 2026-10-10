import Foundation
import Darwin
import Testing
import SessionbarCore
@testable import sessionbar

@Suite struct SessionTerminationTests {
    private func fixture() async throws -> (URL, URL, URL, Data) {
        let root = FileManager.default.temporaryDirectory.appending(path: "sessionbar-quit-\(UUID().uuidString)")
        let sessions = root.appending(path: "sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let source = root.appending(path: "fixture.c"), executable = root.appending(path: "codex")
        try """
        #include <fcntl.h>
        #include <unistd.h>
        #include <signal.h>
        #include <string.h>
        int main(int argc,char**argv){
          for(int i=1;i<argc;i++){
            if(strcmp(argv[i],"exec")==0||strcmp(argv[i],"app-server")==0)continue;
            else if(strcmp(argv[i],"--ignore-term")==0)signal(SIGTERM,SIG_IGN);
            else if(open(argv[i],O_RDONLY)<0)return 2;
          }
          write(STDOUT_FILENO,"ready",5);
          for(;;)pause();
        }
        """.write(to: source, atomically: true, encoding: .utf8)
        let compilation = await CommandRunner.runAsync("/usr/bin/clang", [source.path, "-o", executable.path])
        #expect(compilation.status == 0)
        let data = Data("{\"type\":\"session_meta\",\"payload\":{\"id\":\"fixture\",\"cwd\":\"/tmp/project\"}}\n".utf8)
        let file = sessions.appending(path: "rollout-fixture.jsonl")
        try data.write(to: file)
        return (root, executable, file, data)
    }

    private func launch(_ executable: URL, _ arguments: [String], mode: String = "exec") throws -> Process {
        let process = Process()
        process.executableURL = executable; process.arguments = [mode] + arguments
        let ready = Pipe()
        process.standardOutput = ready; process.standardError = FileHandle.nullDevice
        try process.run()
        try #require(ready.fileHandleForReading.read(upToCount: 5) == Data("ready".utf8))
        return process
    }

    private func cleanup(_ process: Process) {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        Darwin.kill(pid, SIGKILL)
        var status: Int32 = 0
        for _ in 0..<100 {
            if waitpid(pid, &status, WNOHANG) != 0 { break }
            usleep(10_000)
        }
    }

    @Test func quitsOnlySelectedProcessAndKeepsSessionFile() async throws {
        let (root, executable, file, data) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let otherFile = file.deletingLastPathComponent().appending(path: "rollout-other.jsonl")
        try data.write(to: otherFile)
        let selected = try launch(executable, [file.path])
        defer { cleanup(selected) }
        let other = try launch(executable, [otherFile.path])
        defer { cleanup(other) }
        let observer = ProcessObserver()
        var snapshot = await observer.scan()
        for _ in 0..<5 where snapshot.byFile[file] == nil {
            try await Task.sleep(nanoseconds: 100_000_000); snapshot = await observer.scan()
        }
        let runtime = try #require(snapshot.byFile[file])
        #expect(runtime.processStartTime != nil)
        let controller = SessionProcessController()
        #expect(await controller.terminate(runtime: runtime, file: otherFile) == .changed)
        #expect(selected.isRunning && other.isRunning)
        let result = await controller.terminate(runtime: runtime, file: file)
        #expect(result == .terminated)
        #expect(SessionProcessController.startTime(of: selected.processIdentifier) == nil)
        #expect(other.isRunning)
        #expect(try Data(contentsOf: file) == data)
        let after = await observer.scan()
        #expect(after.byFile[file] == nil)
        #expect(after.byFile[otherFile]?.processID == other.processIdentifier)
    }

    @Test func rejectsStaleIdentityWrongFileAndSharedProcess() async throws {
        let (root, executable, file, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let process = try launch(executable, [file.path])
        defer { cleanup(process) }
        let start = try #require(SessionProcessController.startTime(of: process.processIdentifier))
        let controller = SessionProcessController()
        let stale = SessionRuntime(processID: process.processIdentifier, processStartTime: start + 1)
        #expect(await controller.terminate(runtime: stale, file: file) == .changed)
        let unidentified = SessionRuntime(processID: process.processIdentifier)
        #expect(await controller.terminate(runtime: unidentified, file: file) == .unavailable)
        let runtime = SessionRuntime(processID: process.processIdentifier, processStartTime: start)
        #expect(await controller.terminate(runtime: runtime, file: root.appending(path: "missing.jsonl")) == .unavailable)
        #expect(await controller.terminate(runtime: runtime, file: file.deletingLastPathComponent().appending(path: "rollout-other.jsonl")) == .unavailable)
        #expect(process.isRunning)
        let sameFile = try launch(executable, [file.path])
        defer { cleanup(sameFile) }
        #expect(await controller.terminate(runtime: runtime, file: file) == .ambiguous)
        #expect(process.isRunning && sameFile.isRunning)
        let second = file.deletingLastPathComponent().appending(path: "rollout-second.jsonl")
        try Data("{}\n".utf8).write(to: second)
        let shared = try launch(executable, [file.path, second.path])
        defer { cleanup(shared) }
        let sharedStart = try #require(SessionProcessController.startTime(of: shared.processIdentifier))
        let sharedRuntime = SessionRuntime(processID: shared.processIdentifier, processStartTime: sharedStart)
        #expect(await controller.terminate(runtime: sharedRuntime, file: file) == .ambiguous)
        #expect(shared.isRunning)
        #expect(SessionProcessController.validationError("f1\ntCHR\nn\(file.path)\n", expected: file) == .changed)
        #expect(SessionProcessController.validationError("f1\ntREG\nn\(file.path)\nf2\ntREG\nn\(second.path)\n", expected: file) == .ambiguous)
        #expect(await controller.terminate(runtime: SessionRuntime(processID: getpid(), processStartTime: start), file: file) == .changed)
        #expect(SessionProcessController.startTime(of: getpid()) == nil)
        let serviceFile = file.deletingLastPathComponent().appending(path: "rollout-service.jsonl")
        let serviceData = Data("{}\n".utf8)
        try serviceData.write(to: serviceFile)
        let service = try launch(executable, [serviceFile.path], mode: "app-server")
        defer { cleanup(service) }
        let serviceStart = try #require(SessionProcessController.startTime(of: service.processIdentifier))
        let serviceRuntime = SessionRuntime(processID: service.processIdentifier, processStartTime: serviceStart)
        #expect(await SessionProcessController.mode(of: service.processIdentifier) == .sharedService)
        #expect(await controller.terminate(runtime: serviceRuntime, file: serviceFile) == .unsupported)
        #expect(service.isRunning && process.isRunning)
        #expect(try Data(contentsOf: serviceFile) == serviceData)
        let command = "/example/codex"
        #expect(SessionProcessController.classify("ttys001 \(command)", executable: command) == .dedicatedCLI)
        #expect(SessionProcessController.classify("?? \(command) exec task", executable: command) == .dedicatedCLI)
        #expect(SessionProcessController.classify("ttys001 \(command) -c model=example resume sample", executable: command) == .dedicatedCLI)
        #expect(SessionProcessController.classify("ttys001 \(command) app-server --stdio", executable: command) == .sharedService)
        #expect(SessionProcessController.classify("?? \(command) exec-server", executable: command) == .sharedService)
        #expect(SessionProcessController.classify("ttys001 \(command) --remote unix://", executable: command) == .sharedService)
        #expect(SessionProcessController.classify("?? \(command)", executable: command) == .unknown)
        #expect(SessionProcessController.classify("ttys001 \(command) --unrecognized", executable: command) == .unknown)
        #expect(SessionProcessController.classify("bad output", executable: command) == .unknown)
    }

    @Test func reportsTimeoutWithoutForceKilling() async throws {
        let (root, executable, file, data) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let process = try launch(executable, [file.path, "--ignore-term"])
        defer { cleanup(process) }
        // lsof also gives the fixture enough time to install its signal handler.
        let snapshot = await ProcessObserver().scan()
        let runtime = try #require(snapshot.byFile[file])
        #expect(await SessionProcessController().terminate(runtime: runtime, file: file) == .stillRunning)
        #expect(process.isRunning)
        #expect(try Data(contentsOf: file) == data)
        #expect(L10n.text("세션 종료…", language: .english) == "End session…")
    }
}
