import SwiftUI
import AppKit
import SessionbarCore

@main
struct SessionbarApp: App {
    @NSApplicationDelegateAdaptor(SessionbarDelegate.self) private var delegate
    @StateObject private var store: SessionStore

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let store = SessionbarDelegate.store
        _store = StateObject(wrappedValue: store)
    }

    var body: some Scene {
        MenuBarExtra {
            SessionListView(store: store, settings: store.settings)
                .frame(width: 430, height: 570)
        } label: {
            SessionMenuLabel(store: store, settings: store.settings)
        }
        .menuBarExtraStyle(.window)

        Settings { SessionbarSettingsView(store: store, settings: store.settings) }
    }
}

private struct SessionMenuLabel: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var settings: AppSettings

    var body: some View {
        let attention = store.sessions.filter { $0.state == .needsAttentionEstimate }.count
        let running = store.sessions.filter { $0.state == .runningEstimate }.count
        let errors = store.sessions.filter { $0.state == .error }.count
        HStack(spacing: 4) {
            Image(systemName: attention > 0 ? "exclamationmark.bubble.fill" : errors > 0 ? "exclamationmark.triangle.fill" : "terminal")
                .foregroundStyle(attention > 0 ? Color.orange : errors > 0 ? Color.red : Color.primary)
            if !settings.compactMenu {
                if attention > 0 { Text("확인? \(attention) · 실행? \(running)") }
                else if running > 0 { Text("실행? \(running)") }
                else if store.sessions.isEmpty { Text("세션 없음") }
                else { Text("세션 \(store.sessions.count)") }
            } else if attention > 0 { Text("\(attention)") }
        }
        .accessibilityLabel("확인 필요 추정 \(attention)개, 실행 추정 \(running)개")
    }
}

struct SessionListView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var settings: AppSettings
    @Environment(\.openSettings) private var openSettings
    @State private var filter = 0
    @State private var search = ""

    private var visibleSessions: [SessionRecord] {
        store.sessions.filter { record in
            let matchesFilter = filter == 1 || (filter == 0 && record.runtime != nil) ||
                (filter == 2 && (record.state == .needsAttentionEstimate || record.state == .error))
            return matchesFilter && (search.isEmpty || (record.projectName + record.title + record.projectPath).localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "terminal.fill").foregroundStyle(.tint)
                Text("sessionbar").font(.headline)
                Spacer()
                Button { store.openHistory() } label: { Image(systemName: "clock.arrow.circlepath") }
                    .help("활동 기록").accessibilityLabel("활동 기록")
                Button(action: store.refresh) { Image(systemName: "arrow.clockwise") }
                    .disabled(store.isRefreshing).help("새로고침").accessibilityLabel("새로고침")
                Button { NSApp.activate(ignoringOtherApps: true); openSettings() } label: { Image(systemName: "gearshape") }
                    .help("설정").accessibilityLabel("설정")
            }
            .buttonStyle(.borderless)
            .padding(16)

            HStack(spacing: 9) {
                ForEach(SessionState.allCases, id: \.self) { state in
                    let count = store.sessions.filter { $0.state == state }.count
                    HStack(spacing: 3) {
                        Image(systemName: state.symbol).foregroundStyle(state.color)
                        Text("\(count)").monospacedDigit()
                    }
                    .help("\(state.koreanLabel) \(count)개")
                    .accessibilityLabel("\(state.koreanLabel) \(count)개")
                }
            }
            .font(.caption)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 14)

            VStack(spacing: 10) {
                Picker("세션", selection: $filter) {
                    Text("열린 세션").tag(0)
                    Text("전체").tag(1)
                    Text("주의 필요").tag(2)
                }.pickerStyle(.segmented)
                TextField("프로젝트 또는 세션 검색", text: $search)
                    .textFieldStyle(.roundedBorder)
            }.padding(.horizontal, 16).padding(.bottom, 12)

            Divider()
            if store.isRefreshing && store.lastRefresh == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let diagnostic = store.diagnostic {
                ContentUnavailableView(diagnostic, systemImage: "folder.badge.questionmark")
            } else if visibleSessions.isEmpty {
                VStack(spacing: 12) {
                    ContentUnavailableView(filter == 0 ? "열린 세션이 없습니다" : "표시할 세션이 없습니다", systemImage: "terminal")
                    if filter == 0 && !store.sessions.isEmpty { Button("세션 기록 보기") { filter = 1 }.padding(.bottom, 28) }
                }.frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleSessions) { session in
                            Button { store.openDetail(for: session) } label: {
                                SessionRow(session: session)
                                    .padding(.horizontal, 16).padding(.vertical, 12)
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Divider().padding(.leading, 46)
                        }
                    }
                }
            }
            Divider()
            HStack {
                if store.isRefreshing { ProgressView().controlSize(.small) }
                else if let date = store.lastRefresh {
                    Text("갱신 \(date.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let until = settings.pauseUntil, until > Date() {
                    Button { settings.resumeNotifications() } label: { Image(systemName: "bell.slash.fill") }
                        .help("알림 다시 켜기").accessibilityLabel("알림 다시 켜기")
                } else {
                    Button { settings.pauseForHour() } label: { Image(systemName: "bell") }
                        .help("알림 1시간 일시 중지").accessibilityLabel("알림 1시간 일시 중지")
                }
                Button("종료") { NSApp.terminate(nil) }
            }
            .font(.caption).buttonStyle(.borderless).padding(12)
        }
    }
}

private struct SessionRow: View {
    let session: SessionRecord
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: session.state.symbol)
                .font(.system(size: 17)).foregroundStyle(session.state.color)
                .frame(width: 20).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(session.projectName.isEmpty ? "프로젝트 없음" : session.projectName)
                        .font(.headline).lineLimit(1)
                    Spacer()
                    Text(session.state.koreanLabel)
                        .font(.caption).foregroundStyle(session.state.color)
                }
                Text(session.title).font(.subheadline).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                Text(session.projectPath).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                HStack {
                    if let terminal = session.runtime?.terminalName { Text(terminal) }
                    else if session.source != nil { Text("Codex") }
                    Spacer()
                    Text(session.lastActivity, style: .relative)
                }.font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.projectName), \(session.state.koreanLabel), \(session.title), 마지막 활동 \(session.lastActivity.formatted())")
        .accessibilityHint(session.evidence)
        .help("\(session.evidence) · 마지막 활동 \(session.lastActivity.formatted())")
    }
}

extension SessionState {
    var color: Color {
        switch self {
        case .needsAttentionEstimate: .orange
        case .error: .red
        case .runningEstimate: .blue
        case .completed: .green
        case .idleEstimate, .unknown: .secondary
        }
    }
}
