import SwiftUI
import AppKit
import ServiceManagement

struct SessionbarSettingsView: View {
    @AppStorage("sessionbar.followSystemAppearance") private var followSystemAppearance = false
    @ObservedObject var store: SessionStore
    @ObservedObject var settings: AppSettings

    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(Array([("일반", "gearshape"), ("알림", "bell"), ("폴더", "folder")].enumerated()), id: \.offset) { index, item in
                    Button { selectedTab = index } label: {
                        Label(item.0, systemImage: item.1)
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(selectedTab == index ? SessionTheme.surface : .clear,
                                        in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).accessibilityValue(selectedTab == index ? "선택됨" : "")
                }
            }.padding(4).background(SessionTheme.inset, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 24).padding(.top, 20)
            Group {
                switch selectedTab {
                case 1: notificationSettings
                case 2: folderSettings
                default: generalSettings
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 540, height: 520)
        .sessionTheme()
        .onAppear { settings.refreshLoginStatus() }
    }

    private var generalSettings: some View {
        Form {
            Picker("화면 테마", selection: $followSystemAppearance) {
                Text("크림").tag(false)
                Text("시스템").tag(true)
            }
            Toggle("로그인 시 실행", isOn: Binding(get: { settings.launchAtLogin }, set: settings.setLaunchAtLogin))
            if settings.loginNeedsApproval {
                Button("로그인 항목 승인") { SMAppService.openSystemSettingsLoginItems() }
            }
            if let error = settings.loginError { Text(error).foregroundStyle(.red).font(.caption) }
            Toggle("메뉴 막대에 아이콘만 표시", isOn: $settings.compactMenu)
            Toggle("파일 변경 시 새로고침", isOn: $settings.watchFiles)
            Picker("완료·유휴 세션 보관 기간", selection: $settings.retentionDays) {
                Text("7일").tag(7); Text("30일").tag(30); Text("90일").tag(90); Text("모두 표시").tag(0)
            }
            Picker("자동 새로고침", selection: $settings.refreshInterval) {
                Text("5초").tag(5); Text("15초").tag(15); Text("30초").tag(30); Text("60초").tag(60)
            }
            Button("진단 보기") { store.openDiagnostics() }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var notificationSettings: some View {
        Form {
            Section {
                Toggle("확인 필요 추정 알림", isOn: $settings.attentionNotifications)
                Toggle("작업 완료 알림", isOn: $settings.completionNotifications)
                Toggle("오류 알림", isOn: $settings.errorNotifications)
                Toggle("알림음", isOn: $settings.sound)
                Picker("같은 세션의 알림 간격", selection: $settings.cooldownMinutes) {
                    Text("1분").tag(1); Text("5분").tag(5); Text("10분").tag(10); Text("30분").tag(30)
                }
                if let error = settings.notificationError { Text(error).font(.caption).foregroundStyle(.red) }
            }
            Section {
                Toggle("조용한 시간대", isOn: $settings.quietHours)
                HStack {
                    Text("시작"); hourPicker($settings.quietStart)
                    Text("종료"); hourPicker($settings.quietEnd)
                }.disabled(!settings.quietHours)
                if let date = settings.pauseUntil, date > Date() {
                    Text("일시 중지 · \(date.formatted(date: .omitted, time: .shortened))까지")
                    Button("알림 다시 켜기") { settings.resumeNotifications() }
                } else { Button("알림 1시간 일시 중지") { settings.pauseForHour() } }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var folderSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("세션 폴더").font(.headline)
            List {
                ForEach(settings.sessionDirectories, id: \.self) { directory in
                    HStack {
                        Text(directory).font(.caption).textSelection(.enabled)
                        Spacer()
                        Button { settings.sessionDirectories.removeAll { $0 == directory } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).help("폴더 제외")
                    }
                }
            }.scrollContentBackground(.hidden).sessionCard()
            HStack {
                Button("폴더 추가…") { addDirectories() }
                Button("기본 폴더") {
                    let directory = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/sessions").path
                    if !settings.sessionDirectories.contains(directory) { settings.sessionDirectories.append(directory) }
                }
            }
        }.padding(20)
    }

    private func hourPicker(_ binding: Binding<Int>) -> some View {
        Picker("시각", selection: binding) {
            ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
        }.labelsHidden().frame(width: 100)
    }

    private func addDirectories() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        panel.prompt = "추가"; panel.message = "세션 폴더 선택"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            let child = url.appending(path: "sessions")
            let selected = FileManager.default.fileExists(atPath: child.path) ? child.path : url.path
            if !settings.sessionDirectories.contains(selected) { settings.sessionDirectories.append(selected) }
        }
    }
}
