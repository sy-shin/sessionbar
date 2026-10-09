import Foundation
import Darwin

struct SessionFileMetadata {
    let size: UInt64
    let modified: Date

    static func read(_ url: URL) -> SessionFileMetadata? {
        // Foundation's full attribute lookup also reads extended attributes,
        // which can wait on a file provider. Only size and timestamp are needed.
        var info = stat()
        guard url.path.withCString({ lstat($0, &info) }) == 0,
              info.st_mode & S_IFMT == S_IFREG, info.st_size >= 0 else { return nil }
        let seconds = Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000
        return SessionFileMetadata(size: UInt64(info.st_size), modified: Date(timeIntervalSince1970: seconds))
    }
}
