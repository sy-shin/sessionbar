import Foundation
import Darwin

struct CommandResult: Sendable {
    let status: Int32
    let output: String
    let timedOut: Bool
}

enum CommandRunner {
    /// Called only from worker actors/queues. Output stays in memory and is never logged.
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 3) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            return CommandResult(status: -1, output: "", timedOut: false)
        }
        do { try process.run() } catch { return CommandResult(status: -1, output: "", timedOut: false) }
        try? pipe.fileHandleForWriting.close()
        defer { try? pipe.fileHandleForReading.close() }
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeout)
        var output = Data(), bytes = [UInt8](repeating: 0, count: 65_536)
        var timedOut = false, killed = false, invalidOutput = false
        while true {
            let count = bytes.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count > 0 {
                if output.count + count <= 16 * 1024 * 1024 { output.append(contentsOf: bytes.prefix(count)) }
                else { invalidOutput = true }
            } else if count < 0 && errno != EAGAIN && errno != EINTR {
                invalidOutput = true
            }
            // Drain buffered bytes after exit without waiting for descendants to close the pipe.
            if !process.isRunning && count <= 0 { break }
            let now = ProcessInfo.processInfo.systemUptime
            if process.isRunning && now >= deadline && !timedOut {
                timedOut = true
                process.terminate()
            }
            if process.isRunning && now >= deadline + 1 && !killed {
                killed = true
                Darwin.kill(process.processIdentifier, SIGKILL)
            }
            if now >= deadline + 2 { timedOut = true; break }
            if count <= 0 { usleep(10_000) }
        }
        // Avoid scheduling a pipe reader on the cooperative pool and then blocking that pool.
        let status: Int32 = process.isRunning || invalidOutput ? -1 : process.terminationStatus
        return CommandResult(status: status, output: String(decoding: output, as: UTF8.self), timedOut: timedOut)
    }
}
