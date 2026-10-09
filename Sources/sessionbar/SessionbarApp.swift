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
            LocalizedRoot(content: SessionListView(store: store, settings: store.settings))
                .frame(width: 430, height: 570)
        } label: {
            LocalizedRoot(content: SessionMenuLabel(store: store, settings: store.settings))
        }
        .menuBarExtraStyle(.window)

        Settings { LocalizedRoot(content: SessionbarSettingsView(store: store, settings: store.settings)) }
    }
}

private struct SessionMenuLabel: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var settings: AppSettings

    var body: some View {
        let summary = SessionMenuSummary(records: store.sessions, activeCount: store.activeSessionCount, unreviewedCount: store.unreviewed.count, processObservationAvailable: store.processObservationAvailable)
        let attention = summary.attention, errors = summary.errors
        HStack(spacing: 4) {
            Image(systemName: attention > 0 ? "exclamationmark.bubble.fill" : errors > 0 ? "exclamationmark.triangle.fill" : summary.unreviewed > 0 ? "circle.badge" : "terminal")
                .foregroundStyle(attention > 0 ? Color.orange : errors > 0 ? Color.red : summary.unreviewed > 0 ? SessionTheme.accent : Color.primary)
            Text(summary.title(compact: settings.compactMenu)).monospacedDigit()
        }
        .accessibilityLabel(summary.title(compact: false))
        .help(summary.title(compact: false))
    }
}

struct SessionListView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var settings: AppSettings
    @Environment(\.openSettings) private var openSettings
    @State private var filter = SessionListFilter.openSessions
    @State private var search = ""
    @State private var terminationTarget: SessionRecord?
    @State private var confirmingTermination = false
    @State private var terminationError: String?

    private var visibleSessions: [SessionRecord] {
        let records = store.sessions.filter { record in
            return filter.contains(record) && (filter != .unreviewed || store.unreviewed[record.id] != nil) && (search.isEmpty || (record.projectName + record.title + record.projectPath).localizedCaseInsensitiveContains(search))
        }
        guard filter == .unreviewed else { return records }
        return records.sorted {
            guard let first = store.unreviewed[$0.id], let second = store.unreviewed[$1.id] else { return false }
            let rank: [SessionReviewEvent.Kind: Int] = [.attention: 0, .error: 1, .completed: 2]
            if first.kind != second.kind { return (rank[first.kind] ?? 3) < (rank[second.kind] ?? 3) }
            return first.date < second.date
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "terminal")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(SessionTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(SessionTheme.inset, in: RoundedRectangle(cornerRadius: 12))
                Text("sessionbar").font(.system(size: 22, weight: .semibold)).tracking(-0.7)
                Spacer()
                Button { store.openHistory() } label: { Image(systemName: "clock.arrow.circlepath") }
                    .help(L10n.text("활동 기록")).accessibilityLabel(L10n.text("활동 기록"))
                Button(action: store.refresh) { Image(systemName: "arrow.clockwise") }
                    .disabled(store.isRefreshing).help(L10n.text("새로고침")).accessibilityLabel(L10n.text("새로고침"))
                Button { NSApp.activate(ignoringOtherApps: true); openSettings() } label: { Image(systemName: "gearshape") }
                    .help(L10n.text("설정")).accessibilityLabel(L10n.text("설정"))
            }
            .buttonStyle(SessionIconButtonStyle())
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 16)

            HStack(spacing: 9) {
                ForEach(SessionState.allCases, id: \.self) { state in
                    let count = (filter == .unreviewed ? visibleSessions : filter.summaryRecords(store.sessions)).filter { $0.state == state }.count
                    HStack(spacing: 3) {
                        Image(systemName: state.symbol).foregroundStyle(state.color)
                        Text("\(count)").monospacedDigit()
                    }
                    .padding(.horizontal, 9).padding(.vertical, 7)
                    .background(count > 0 ? state.color.opacity(0.08) : SessionTheme.surface, in: Capsule())
                    .help(L10n.format("%@ %d개", state.localizedLabel, count))
                    .accessibilityLabel(L10n.format("%@ %d개", state.localizedLabel, count))
                }
            }
            .font(.system(size: 12, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.bottom, 14)

            VStack(spacing: 10) {
                HStack(spacing: 4) {
                    ForEach(SessionListFilter.allCases, id: \.self) { option in
                        Button { filter = option } label: {
                            Text(option.title).font(.system(size: 12, weight: filter == option ? .semibold : .medium))
                                .foregroundStyle(filter == option ? SessionTheme.ink : SessionTheme.muted)
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(filter == option ? SessionTheme.surface : .clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain).accessibilityValue(filter == option ? L10n.text("선택됨") : "")
                    }
                }.padding(4).background(SessionTheme.inset, in: RoundedRectangle(cornerRadius: 11))
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(SessionTheme.muted)
                    TextField(L10n.text("프로젝트 또는 세션 검색"), text: $search).textFieldStyle(.plain)
                }.padding(11).sessionCard(radius: 10)
            }.padding(.horizontal, 20).padding(.bottom, 14)

            Divider()
            if store.isRefreshing && store.lastRefresh == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let diagnostic = store.diagnostic {
                ContentUnavailableView(L10n.text(diagnostic), systemImage: "folder.badge.questionmark")
            } else if visibleSessions.isEmpty {
                VStack(spacing: 12) {
                    ContentUnavailableView(search.isEmpty ? (filter == .openSessions && !store.processObservationAvailable ? L10n.text("프로세스 상태를 확인할 수 없습니다") : filter.emptyMessage) : L10n.text("표시할 세션이 없습니다"), systemImage: "terminal")
                    if filter == .openSessions && !store.sessions.isEmpty { Button(L10n.text("세션 기록 보기")) { filter = .allSessions }.padding(.bottom, 28) }
                }.frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(visibleSessions) { session in
                            SessionListCard(store: store, session: session) {
                                terminationTarget = session; confirmingTermination = true
                            }
                        }
                    }.padding(16)
                }
            }
            if store.sessions.contains(where: \.isPlaceholder) {
                Button(L10n.text("세션 폴더 연결…")) { store.connectSessionFolder() }.padding(10)
                if let error = store.folderError { Text(error).font(.caption).foregroundStyle(.red) }
            }
            Divider()
            HStack {
                if store.isRefreshing { ProgressView().controlSize(.small) }
                else if let date = store.lastRefresh {
                    Text(L10n.format("갱신 %@", L10n.date(date, dateStyle: .none)))
                        .foregroundStyle(SessionTheme.muted)
                }
                Spacer()
                if let until = settings.pauseUntil, until > Date() {
                    Button { settings.resumeNotifications() } label: { Image(systemName: "bell.slash.fill") }
                        .help(L10n.text("알림 다시 켜기")).accessibilityLabel(L10n.text("알림 다시 켜기"))
                } else {
                    Button { settings.pauseForHour() } label: { Image(systemName: "bell") }
                        .help(L10n.text("알림 1시간 일시 중지")).accessibilityLabel(L10n.text("알림 1시간 일시 중지"))
                }
                Button(L10n.text("종료")) { NSApp.terminate(nil) }
            }
            .font(.caption).buttonStyle(.borderless).padding(.horizontal, 20).padding(.vertical, 12)
        }
        .sessionTheme()
        .modifier(SessionTerminationDialog(store: store,
            session: terminationTarget,
            confirming: $confirmingTermination, actionError: $terminationError))
    }
}

private struct SessionListCard: View {
    @ObservedObject var store: SessionStore
    let session: SessionRecord
    let requestTermination: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { store.openDetail(for: session) } label: {
                SessionRow(session: session, review: store.unreviewed[session.id]).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if SessionWindowConnector.canReturn(session.runtime) || store.unreviewed[session.id] != nil {
                Divider()
                HStack(alignment: .top) {
                    if SessionWindowConnector.canReturn(session.runtime) { SessionReturnButton(store: store, session: session) }
                    Spacer()
                    if let review = store.unreviewed[session.id] {
                        Button(L10n.text("확인 완료")) { store.markReviewed(id: session.id, token: review.token) }
                    }
                }.font(.caption).buttonStyle(.borderless)
            }
        }.padding(15).sessionCard()
        .contextMenu {
            if session.runtime != nil {
                Button(L10n.text("Codex 종료…"), role: .destructive, action: requestTermination)
                    .disabled(session.runtime?.processStartTime == nil || store.terminatingSessionIDs.contains(session.id))
            }
        }
    }
}

private struct SessionRow: View {
    let session: SessionRecord
    let review: SessionReviewEvent?
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: session.state.symbol)
                .font(.system(size: 14, weight: .medium)).foregroundStyle(session.state.color)
                .frame(width: 30, height: 30)
                .background(session.state.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(session.projectName.isEmpty ? L10n.text("프로젝트 없음") : session.projectName)
                        .font(.headline).lineLimit(1)
                    Spacer()
                    SessionStatusBadge(state: session.state)
                }
                Text(session.isPlaceholder ? L10n.text(session.title) : session.title).font(.system(size: 12)).lineSpacing(3).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                Text(session.projectPath).font(.caption2).foregroundStyle(SessionTheme.muted).lineLimit(1)
                if let review {
                    HStack(spacing: 5) {
                        Image(systemName: "circle.fill").font(.system(size: 5))
                        Text(review.kind.localizedLabel)
                        if review.kind == .attention { Text(review.date, style: .relative) }
                    }.font(.caption2).foregroundStyle(SessionTheme.accent)
                }
                HStack {
                    if let terminal = session.runtime?.terminalName { Text(terminal) }
                    else if session.source != nil { Text("Codex") }
                    Spacer()
                    if session.isPlaceholder { Text(L10n.text("마지막 활동 불명")) }
                    else { Text(session.lastActivity, style: .relative) }
                }.font(.caption2).foregroundStyle(SessionTheme.muted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([session.projectName, session.state.localizedLabel, L10n.text(session.title), review?.kind.localizedLabel ?? "", activityTime].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityHint(L10n.text(session.evidence))
        .help(L10n.text(session.evidence) + " · " + activityTime)
    }
    private var activityTime: String {
        session.isPlaceholder ? L10n.text("마지막 활동 불명") : L10n.format("마지막 활동 %@", L10n.date(session.lastActivity))
    }
}

extension SessionState {
    var color: Color {
        switch self {
        case .needsAttentionEstimate: SessionTheme.adaptive(0xA36315, 0xE9BC76)
        case .error: SessionTheme.adaptive(0xB84038, 0xF19D92)
        case .runningEstimate: SessionTheme.adaptive(0x476D9E, 0xA1C1ED)
        case .completed: SessionTheme.adaptive(0x407A59, 0x9BD4B1)
        case .idleEstimate, .unknown: SessionTheme.muted
        }
    }
}
