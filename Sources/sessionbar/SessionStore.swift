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
    @Published private(set) var invalidFileCount = 0
    let settings: AppSettings
    private let repository = SessionRepository()
    private let processObserver = ProcessObserver()
    private let monitor = FileChangeMonitor()
    private let notifications: NotificationService
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
            var byID: [String: (SessionRecord, URL)] = [:]
            let now = Date()
            for (url, snapshot) in result.snapshots {
                guard let record = snapshot.record(now: now, runtime: runtime.byFile[url], processObservationAvailable: runtime.available) else { continue }
                if let old = byID[record.id], old.0.lastActivity >= record.lastActivity { continue }
                byID[record.id] = (record, url)
            }
            allRecords = byID.mapValues { $0.0 }
            sessionURLs = byID.mapValues { $0.1 }
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
            diagnostic = result.snapshots.isEmpty && result.failedDirectories == directories.count ? "세션 폴더를 읽을 수 없습니다" : nil
            if sessions.isEmpty && runtime.codexCount > 0 && result.invalidFiles > 0 {
                diagnostic = "세션 기록을 읽을 수 없습니다"
            }
            lastRefresh = now
            let issues = result.failedDirectories + result.invalidFiles + result.malformedLines
            let message = "세션 \(allRecords.count) · Codex 프로세스 \(runtime.codexCount) · 읽기 문제 \(issues)"
            if diagnostics.last?.contains(message) != true {
                diagnostics.append("\(now.formatted(date: .omitted, time: .standard)) · \(message)")
                if diagnostics.count > 200 { diagnostics.removeFirst(diagnostics.count - 200) }
            }
            if !runtime.available { diagnostics.append("프로세스 정보를 읽을 수 없습니다") }
            isRefreshing = false
            if refreshAgain { refreshAgain = false; refresh() }
        }
    }

    func record(id: String) -> SessionRecord? { allRecords[id] }

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
        showWindow(id: sessionID, title: allRecords[sessionID]?.projectName ?? "세션 상세", width: 760, height: 660,
                   view: SessionDetailView(store: self, sessionID: sessionID))
    }

    func openHistory() {
        showWindow(id: "history", title: "활동 기록", width: 850, height: 650, view: SessionHistoryView(store: self))
    }

    func openListWindow() {
        showWindow(id: "sessions", title: "sessionbar", width: 480, height: 570,
                   view: SessionListView(store: self, settings: settings))
    }

    func openDiagnostics() {
        showWindow(id: "diagnostics", title: "진단", width: 660, height: 420, view: DiagnosticsView(store: self))
    }

    func returnToSession(id: String) async -> String? {
        guard let url = sessionURLs[id] else { return "세션 기록을 찾을 수 없습니다" }
        let snapshot = await processObserver.scan()
        guard let runtime = snapshot.byFile[url] else { refresh(); return "실행 중인 세션을 찾을 수 없습니다" }
        let error = await TerminalConnector.focus(runtime)
        if let error {
            diagnostics.append("\(error) · 오류 \(TerminalConnector.lastErrorCode.map(String.init) ?? "없음") · 결과 \(TerminalConnector.lastResultCode.map(String.init) ?? "없음")")
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
        window.contentView = NSHostingView(rootView: view)
        windows[id] = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
