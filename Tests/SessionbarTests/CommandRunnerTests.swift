import Foundation
import Testing
@testable import sessionbar

@Suite struct CommandRunnerTests {
    @Test func concurrentCommandsDoNotNeedAnotherCooperativeWorker() async {
        let results = await withTaskGroup(of: CommandResult.self, returning: [CommandResult].self) { group in
            for _ in 0..<8 { group.addTask { await CommandRunner.runAsync("/usr/bin/printf", ["%s", "fixture"]) } }
            var results: [CommandResult] = []
            for await result in group { results.append(result) }
            return results
        }
        #expect(results.count == 8)
        #expect(results.allSatisfy { $0.status == 0 && $0.output == "fixture" && !$0.timedOut })
    }

    @Test func outputLargerThanPipeBufferIsDrainedWhileCommandRuns() {
        let result = CommandRunner.run("/usr/bin/awk", ["BEGIN { for(i=0;i<100000;i++)printf \"x\" }"])
        #expect(result.status == 0 && !result.timedOut)
        #expect(result.output == String(repeating: "x", count: 100_000))
    }

    @Test func commandTimeoutReturnsPromptly() {
        let began = ProcessInfo.processInfo.systemUptime
        let result = CommandRunner.run("/bin/sleep", ["2"], timeout: 0.05)
        #expect(result.timedOut && result.status != 0)
        #expect(ProcessInfo.processInfo.systemUptime - began < 1.5)
    }
}
