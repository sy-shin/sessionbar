import Foundation

struct CommandResult: Sendable {
    let status: Int32
    let output: String
    let timedOut: Bool
}

enum CommandRunner {
    private final class Buffer: @unchecked Sendable {
        var data = Data()
    }

    /// Called only from worker actors/queues. Output stays in memory and is never logged.
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 3) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let ended = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in ended.signal() }
        do { try process.run() } catch { return CommandResult(status: -1, output: "", timedOut: false) }
        let buffer = Buffer()
        let reader = DispatchGroup()
        reader.enter()
        DispatchQueue.global(qos: .utility).async {
            buffer.data = pipe.fileHandleForReading.readDataToEndOfFile()
            reader.leave()
        }
        let timedOut = ended.wait(timeout: .now() + timeout) == .timedOut
        if timedOut { process.terminate() }
        if timedOut && ended.wait(timeout: .now() + 1) == .timedOut { kill(process.processIdentifier, SIGKILL) }
        reader.wait()
        process.waitUntilExit()
        return CommandResult(status: process.terminationStatus, output: String(decoding: buffer.data, as: UTF8.self), timedOut: timedOut)
    }
}
