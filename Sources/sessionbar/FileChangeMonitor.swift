import Foundation
import CoreServices

final class FileChangeMonitor {
    private final class State {
        var stream: FSEventStreamRef?
        var callback: (() -> Void)?

        func stop() {
            if let stream {
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
            }
            stream = nil
            callback = nil
        }
    }

    private let queue = DispatchQueue(label: "io.sessionbar.file-watch", qos: .utility)
    private let state = State()

    func start(paths: [String], onChange: @escaping () -> Void) {
        // Opening watched paths can wait on a cloud provider or an unavailable volume.
        // Keep stream creation and disposal off the main thread; polling remains active.
        queue.async { [state, queue] in
            state.stop()
            state.callback = onChange
            guard !paths.isEmpty else { return }
            var context = FSEventStreamContext(version: 0,
                info: Unmanaged.passUnretained(state).toOpaque(),
                retain: nil, release: nil, copyDescription: nil)
            let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot)
            state.stream = FSEventStreamCreate(kCFAllocatorDefault, { _, info, _, _, _, _ in
                guard let info else { return }
                let callback = Unmanaged<State>.fromOpaque(info).takeUnretainedValue().callback
                DispatchQueue.main.async { callback?() }
            }, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5, flags)
            if let stream = state.stream {
                FSEventStreamSetDispatchQueue(stream, queue)
                FSEventStreamStart(stream)
            }
        }
    }

    func stop() { queue.async { [state] in state.stop() } }
    deinit { queue.async { [state] in state.stop() } }
}
