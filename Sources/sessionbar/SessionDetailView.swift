import SwiftUI
import SessionbarCore
import AppKit

struct SessionDetailView: View {
    @ObservedObject var store: SessionStore
    let sessionID: String
    @State private var detail: SessionDetail?
    @State private var loading = true
    @State private var actionError: String?
    @State private var returning = false

    var body: some View {
        let session = store.record(id: sessionID)
        VStack(alignment: .leading, spacing: 16) {
            if let session {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(session.projectName.isEmpty ? L10n.text("Codex 세션") : session.projectName).font(.title2.weight(.semibold))
                        Text(session.isPlaceholder ? L10n.text(session.title) : session.title).font(.subheadline).textSelection(.enabled)
                        Text(session.projectPath).font(.caption).foregroundStyle(SessionTheme.muted).textSelection(.enabled)
                    }
                    Spacer()
                    SessionStatusBadge(state: session.state)
                }
                HStack {
                    Text(session.isPlaceholder ? L10n.text("마지막 활동 불명") : L10n.format("마지막 활동 %@", L10n.date(session.lastActivity)))
                    Spacer()
                    if let terminal = session.runtime?.terminalName { Text(terminal) }
                }.font(.caption).foregroundStyle(SessionTheme.muted)
                Text(L10n.text(session.evidence)).font(.caption).foregroundStyle(SessionTheme.muted)
                Divider()
                if loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                else if let detail {
                    VSplitView {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(L10n.text("최신 Codex 응답")).font(.headline)
                                MarkdownResponseView(text: detail.latestResponse ?? L10n.text("아직 표시할 응답이 없습니다"))
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                                .sessionCard()
                        }.frame(minHeight: 160)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.text("최근 활동")).font(.headline)
                            if detail.activities.isEmpty { Text(L10n.text("표시할 활동이 없습니다")).foregroundStyle(SessionTheme.muted) }
                            List(detail.activities) { activity in
                                HStack(alignment: .firstTextBaseline, spacing: 14) {
                                    Text(L10n.date(activity.date))
                                        .font(.caption.monospacedDigit()).foregroundStyle(SessionTheme.muted).frame(width: 160, alignment: .leading)
                                    Text(L10n.activity(activity)).font(.callout).textSelection(.enabled)
                                }
                            }.listStyle(.plain).scrollContentBackground(.hidden)
                        }.padding(18).frame(minHeight: 100, idealHeight: 180).sessionCard()
                    }
                } else { ContentUnavailableView(L10n.text("세션 기록을 읽을 수 없습니다"), systemImage: "doc.badge.ellipsis") }
                if session.isPlaceholder {
                    Button(L10n.text("세션 폴더 연결…")) { store.connectSessionFolder() }
                }
                Divider()
                HStack {
                    if TerminalConnector.canReturn(session.runtime) {
                        Button(L10n.text("터미널로 돌아가기")) {
                            returning = true
                            Task { actionError = await store.returnToSession(id: sessionID); returning = false }
                        }.disabled(returning)
                    }
                    Button(L10n.text("프로젝트 폴더 열기")) {
                        if !session.projectPath.isEmpty {
                            if !NSWorkspace.shared.open(URL(fileURLWithPath: session.projectPath, isDirectory: true)) {
                                actionError = L10n.text("프로젝트 폴더를 열 수 없습니다")
                            }
                        }
                    }.disabled(session.projectPath.isEmpty)
                    Menu(L10n.text("복사")) {
                        Button(L10n.text("재개 명령")) { copy("codex resume \(shellQuoted(sessionID))") }.disabled(session.isPlaceholder)
                        Button(L10n.text("세션 ID")) { copy(sessionID) }.disabled(session.isPlaceholder)
                        Button(L10n.text("프로젝트 경로")) { copy(session.projectPath) }
                    }
                    Spacer()
                    if session.runtime != nil { SessionTerminationButton(store: store, session: session) }
                    Button { store.refresh(); Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
                        .help(L10n.text("새로고침")).accessibilityLabel(L10n.text("상세 새로고침"))
                }
                if let actionError { Text(L10n.text(actionError)).font(.caption).foregroundStyle(.red) }
            } else { ContentUnavailableView(L10n.text("세션을 찾을 수 없습니다"), systemImage: "doc.badge.questionmark") }
        }
        .padding(24).frame(minWidth: 600, minHeight: 460)
        .sessionTheme()
        .task(id: session?.lastActivity) { await reload() }
    }

    private func reload() async { detail = await store.detail(id: sessionID); loading = false }
    private func copy(_ value: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string) }
    private func shellQuoted(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

private struct MarkdownResponseView: View {
    let text: String
    private struct Block: Identifiable { let id: Int; let text: String; let code: Bool }
    private var blocks: [Block] {
        var blocks: [Block] = [], current: [String] = [], code = false
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("```") {
                if !current.isEmpty { blocks.append(Block(id: blocks.count, text: current.joined(separator: "\n"), code: code)); current = [] }
                code.toggle()
            } else { current.append(line) }
        }
        if !current.isEmpty { blocks.append(Block(id: blocks.count, text: current.joined(separator: "\n"), code: code)) }
        return blocks
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in
                if block.code {
                    ScrollView(.horizontal) {
                        Text(block.text).font(.system(.callout, design: .monospaced)).textSelection(.enabled).padding(12)
                    }.background(SessionTheme.inset, in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Text(.init(block.text)).font(.body).lineSpacing(4).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
