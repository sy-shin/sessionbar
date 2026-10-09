import Foundation
import SwiftUI
import Combine
import AppKit
import SessionbarCore

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [SessionRecord] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var diagnostic: String?
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var diagnostics: [String] = []
    @Published private(set) var processCount = 0
    @Published private(set) var activeSessionCount = 0
    @Published private(set) var folderError: String?
    @Published private(set) var terminatingSessionIDs = Set<String>()
    private let folderAccess = SessionFolderAccess()
    private var suggestedSessionFolder: URL?
    @Published private(set) var invalidFileCount = 0
    let settings: AppSettings
    private let repository = SessionRepository()
    private let processObserver = ProcessObserver()
    private let processController = SessionProcessController()
    private let monitor = FileChangeMonitor()
    private let notifications: NotificationService
    private var placeholderIDs: [URL: String] = [:]
    private var allRecords: [String: SessionRecord] = [:]
    private var sessionURLs: [String: URL] = [:]
    private var windows: [String: NSWindow] = [:]
    private var timer: Timer?
    private var refreshAgain = false
    private var watchedDirectories: [String] = []
    private var liveDirectories: [String] = []
    private var scheduledInterval = 0

    init() {
        let settings = AppSettings()
        self.settings = settings
        notifications = NotificationService(settings: settings)
        settings.onChange = { [weak self] in self?.configure() }
        settings.onEnableNotifications = { [weak self] state in self?.notifications.requestPermission(for: state) }
        notifications.onOpenSession = { [weak self] in self?.openDetail(sessionID: $0) }
        configure()
        Task { await folderAccess.restore(); await repository.retryAfterFolderConnection(); refresh() }
    }

    private func configure() {
        if scheduledInterval != settings.refreshInterval {
            scheduledInterval = settings.refreshInterval
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: Double(max(5, settings.refreshInterval)), repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
        updateWatcher()
        refresh()
    }

    private func updateWatcher() {
        let paths = settings.watchFiles ? Array(Set(settings.sessionDirectories + liveDirectories)).sorted() : []
        if watchedDirectories != paths {
            watchedDirectories = paths
            monitor.start(paths: watchedDirectories) { [weak self] in self?.refresh() }
        }
    }

    func refresh() {
        guard !isRefreshing else { refreshAgain = true; return }
        isRefreshing = true
        let directories = settings.sessionDirectories
        Task {
            let runtime = await processObserver.scan()
            let result = await repository.scan(directories: directories, activeFiles: Array(runtime.byFile.keys))
            liveDirectories = result.snapshots.keys.filter { runtime.byFile[$0] != nil }
                .map { $0.deletingLastPathComponent().path }
            updateWatcher()
            let now = Date()
            let inventory = SessionInventory(snapshots: result.snapshots, runtime: runtime, now: now, placeholderIDs: &placeholderIDs)
            activeSessionCount = inventory.activeCount
            suggestedSessionFolder = runtime.byFile.keys.sorted(by: { $0.path < $1.path }).first.flatMap(Self.sessionRoot)
            allRecords = inventory.records
            sessionURLs = inventory.urls
            let cutoff = now.addingTimeInterval(-Double(settings.retentionDays) * 86_400)
            sessions = allRecords.values.filter {
                settings.retentionDays == 0 || $0.runtime != nil ||
                ($0.state != .completed && $0.state != .idleEstimate) || $0.lastActivity >= cutoff
            }.sorted {
                let first = priority($0.state), second = priority($1.state)
                return first == second ? $0.lastActivity > $1.lastActivity : first < second
            }
            notifications.observe(Array(allRecords.values), now: now)
            processCount = runtime.codexCount
            invalidFileCount = result.invalidFiles
            diagnostic = sessions.isEmpty && result.snapshots.isEmpty && result.failedDirectories == directories.count ? L10n.text("세션 폴더를 읽을 수 없습니다") : nil
            if sessions.isEmpty && runtime.codexCount > 0 && result.invalidFiles > 0 {
                diagnostic = L10n.text("세션 기록을 읽을 수 없습니다")
            }
            lastRefresh = now
            let issues = result.failedDirectories + result.invalidFiles + result.malformedLines
            let message = L10n.format("세션 %d · Codex 프로세스 %d · 읽기 문제 %d", allRecords.count, runtime.codexCount, issues)
            if diagnostics.last?.contains(message) != true {
                diagnostics.append("\(now.formatted(date: .omitted, time: .standard)) · \(message)")
                if diagnostics.count > 200 { diagnostics.removeFirst(diagnostics.count - 200) }
            }
            if !runtime.available { diagnostics.append(L10n.text("프로세스 정보를 읽을 수 없습니다")) }
            isRefreshing = false
            if refreshAgain { refreshAgain = false; refresh() }
        }
    }

    func record(id: String) -> SessionRecord? { allRecords[id] }

    func terminateSession(_ session: SessionRecord) async -> String? {
        guard let runtime = session.runtime, let url = sessionURLs[session.id] else {
            return "종료할 세션을 확인할 수 없습니다"
        }
        guard terminatingSessionIDs.insert(session.id).inserted else { return "세션 종료 중입니다" }
        defer { terminatingSessionIDs.remove(session.id); refresh() }
        return await processController.terminate(runtime: runtime, file: url).error
    }

    func detail(id: String) async -> SessionDetail? {
        guard let url = sessionURLs[id] else { return nil }
        return await repository.detail(url: url)
    }

    func history(from start: Date, to end: Date) async -> [SessionHistoryItem] {
        _ = await repository.scan(directories: settings.sessionDirectories)
        return await repository.history(from: start, to: end)
    }

    func openDetail(for session: SessionRecord) { openDetail(sessionID: session.id) }

    func openDetail(sessionID: String) {
        guard allRecords[sessionID] != nil else { return }
        showWindow(id: sessionID, title: allRecords[sessionID]?.projectName ?? L10n.text("세션 상세"), width: 760, height: 660,
                   view: SessionDetailView(store: self, sessionID: sessionID))
    }

    func openHistory() {
        showWindow(id: "history", title: L10n.text("활동 기록"), width: 850, height: 650, view: SessionHistoryView(store: self))
    }

    func openListWindow() {
        showWindow(id: "sessions", title: "sessionbar", width: 480, height: 570,
                   view: SessionListView(store: self, settings: settings))
    }

    func openDiagnostics() {
        showWindow(id: "diagnostics", title: L10n.text("진단"), width: 660, height: 420, view: DiagnosticsView(store: self))
    }

    func returnToSession(id: String) async -> String? {
        guard let url = sessionURLs[id] else { return L10n.text("세션 기록을 찾을 수 없습니다") }
        let snapshot = await processObserver.scan()
        guard let runtime = snapshot.byFile[url] else { refresh(); return L10n.text("실행 중인 세션을 찾을 수 없습니다") }
        let error = await TerminalConnector.focus(runtime)
        if let error {
            diagnostics.append(error + " · " + String(TerminalConnector.lastErrorCode ?? 0) + " / " + String(TerminalConnector.lastResultCode ?? 0))
        }
        return error
    }

    private func showWindow<V: View>(id: String, title: String, width: CGFloat, height: CGFloat, view: V) {
        if let existing = windows[id], existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = windows[id] ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: min(width, 650), height: min(height, 460))
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(SessionTheme.canvas)
        window.title = title.isEmpty ? "sessionbar" : title
        window.contentView = NSHostingView(rootView: LocalizedRoot(content: view))
        windows[id] = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func sessionRoot(_ file: URL) -> URL? {
        var url = file.deletingLastPathComponent()
        while url.path != "/" {
            if url.lastPathComponent == "sessions" { return url }
            url.deleteLastPathComponent()
        }
        return nil
    }

    func connectSessionFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = suggestedSessionFolder
        panel.prompt = L10n.text("추가"); panel.message = L10n.text("세션 폴더 선택")
        guard panel.runModal() == .OK else { return }
        do {
            for url in panel.urls {
                try folderAccess.connect(url)
                if !settings.sessionDirectories.contains(url.path) { settings.sessionDirectories.append(url.path) }
            }
            folderError = nil
            Task { await repository.retryAfterFolderConnection(); refresh() }
        } catch { folderError = L10n.text("세션 폴더를 연결할 수 없습니다") }
    }

    func disconnectSessionFolder(_ path: String) {
        folderAccess.disconnect(path: path)
        settings.sessionDirectories.removeAll { $0 == path }
    }

    private func priority(_ state: SessionState) -> Int {
        switch state {
        case .needsAttentionEstimate: 0
        case .error: 1
        case .runningEstimate: 2
        case .unknown: 3
        case .idleEstimate: 4
        case .completed: 5
        }
    }
}
