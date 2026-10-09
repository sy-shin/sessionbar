import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SessionbarCore

struct SessionHistoryView: View {
    @ObservedObject var store: SessionStore
    @State private var date = Date()
    @State private var items: [SessionHistoryItem] = []
    @State private var loading = false
    @State private var showingExport = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("활동 기록").font(.title2.weight(.semibold))
                Spacer()
                DatePicker("날짜", selection: $date, displayedComponents: .date).frame(width: 240)
                Button("CSV 내보내기…") { showingExport = true }
            }
            Divider()
            if loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if items.isEmpty { ContentUnavailableView("이 날짜의 완료 기록이 없습니다", systemImage: "calendar") }
            else {
                List(items) { item in
                    HStack(alignment: .top, spacing: 14) {
                        Text(item.date, style: .time).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 76)
                        Image(systemName: item.state.symbol).foregroundStyle(item.state.color)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.projectName.isEmpty ? "프로젝트 없음" : item.projectName).font(.headline)
                            Text(item.title).font(.subheadline).lineLimit(2)
                        }
                        Spacer()
                        Text(item.state.koreanLabel).font(.caption).foregroundStyle(item.state.color)
                        Button("세션 보기") { store.openDetail(sessionID: item.sessionID) }
                    }.padding(.vertical, 7)
                }.listStyle(.plain)
            }
            HStack {
                Text("\(items.count)개 작업").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("새로고침") { Task { await load() } }
            }
        }
        .padding(24).frame(minWidth: 650, minHeight: 420)
        .task(id: date) { await load() }
        .sheet(isPresented: $showingExport) { HistoryExportView(store: store, initialDate: date) }
    }

    private func load() async {
        loading = true
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        let result = await store.history(from: start, to: end)
        guard !Task.isCancelled else { return }
        items = result; loading = false
    }
}

private struct HistoryExportView: View {
    @ObservedObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    @State private var options = HistoryExportOptions()
    @State private var loading = false
    @State private var error: String?

    init(store: SessionStore, initialDate: Date) {
        self.store = store
        _start = State(initialValue: initialDate); _end = State(initialValue: initialDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("활동 기록 내보내기").font(.title3.weight(.semibold))
            DatePicker("시작 날짜", selection: $start, displayedComponents: .date)
            DatePicker("종료 날짜", selection: $end, in: start..., displayedComponents: .date)
            Text("완료·오류 기록 · 시각, 프로젝트명, 상태").font(.callout)
            Toggle("프로젝트 경로 포함", isOn: $options.includeProjectPath)
            Toggle("세션 ID 포함", isOn: $options.includeSessionID)
            Toggle("요청 요약 포함", isOn: $options.includeTitle)
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack {
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if loading { ProgressView().controlSize(.small) }
                Button("저장 위치 선택…") { Task { await save() } }
                    .disabled(loading || end < start).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 420)
    }

    private func save() async {
        loading = true; error = nil
        let first = Calendar.current.startOfDay(for: start)
        let last = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end)) ?? end
        let items = await store.history(from: first, to: last)
        let panel = NSSavePanel()
        panel.title = "활동 기록 저장"; panel.nameFieldStringValue = "000_활동기록.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.message = "\(first.formatted(date: .numeric, time: .omitted)) ~ \(end.formatted(date: .numeric, time: .omitted)) · \(items.count)개 작업"
        if panel.runModal() == .OK, let url = panel.url {
            do { try HistoryCSV.data(items: items, options: options).write(to: url, options: .atomic); dismiss() }
            catch { self.error = "파일을 저장할 수 없습니다" }
        }
        loading = false
    }
}
