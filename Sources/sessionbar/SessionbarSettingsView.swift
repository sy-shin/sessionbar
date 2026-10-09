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
                ForEach(Array([(L10n.text("일반"), "gearshape"), (L10n.text("알림"), "bell"), (L10n.text("폴더"), "folder")].enumerated()), id: \.offset) { index, item in
                    Button { selectedTab = index } label: {
                        Label(item.0, systemImage: item.1)
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(selectedTab == index ? SessionTheme.surface : .clear,
                                        in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).accessibilityValue(selectedTab == index ? L10n.text("선택됨") : "")
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
        .onAppear { settings.refreshLoginStatus(); store.refreshNotificationPermission() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in store.refreshNotificationPermission() }
    }

    private var generalSettings: some View {
        Form {
            Picker(L10n.text("언어"), selection: $settings.language) {
                Text(L10n.text("시스템")).tag(AppLanguage.system)
                Text("한국어").tag(AppLanguage.korean)
                Text("English").tag(AppLanguage.english)
            }
            Picker(L10n.text("화면 테마"), selection: $followSystemAppearance) {
                Text(L10n.text("크림")).tag(false)
                Text(L10n.text("시스템")).tag(true)
            }
            Toggle(L10n.text("Mac 시작 시 자동 실행"), isOn: Binding(get: { settings.launchAtLogin }, set: settings.setLaunchAtLogin))
            if settings.loginNeedsApproval {
                Button(L10n.text("자동 실행 설정 열기")) { SMAppService.openSystemSettingsLoginItems() }
            }
            if let error = settings.loginError { Text(L10n.text(error)).foregroundStyle(.red).font(.caption) }
            Toggle(L10n.text("간단한 메뉴 표시"), isOn: $settings.compactMenu)
            Toggle(L10n.text("파일 변경 시 새로고침"), isOn: $settings.watchFiles)
            Picker(L10n.text("완료·유휴 세션 보관 기간"), selection: $settings.retentionDays) {
                Text(L10n.text("7일")).tag(7); Text(L10n.text("30일")).tag(30); Text(L10n.text("90일")).tag(90); Text(L10n.text("모두 표시")).tag(0)
            }
            Picker(L10n.text("자동 새로고침"), selection: $settings.refreshInterval) {
                Text(L10n.text("5초")).tag(5); Text(L10n.text("15초")).tag(15); Text(L10n.text("30초")).tag(30); Text(L10n.text("60초")).tag(60)
            }
            Button(L10n.text("진단 보기")) { store.openDiagnostics() }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var notificationSettings: some View {
        Form {
            Section {
                HStack {
                    Text(L10n.text(settings.notificationPermission.label))
                    Spacer()
                    if settings.notificationPermission == .notRequested {
                        Button(L10n.text("알림 허용 요청")) { store.requestNotificationPermission() }
                    } else {
                        Button(L10n.text("macOS 알림 설정")) { store.openNotificationSettings() }
                    }
                }
                if settings.notificationBannersDisabled { Text(L10n.text("알림 표시 꺼짐")).font(.caption) }
                Toggle(L10n.text("확인 필요 추정 알림"), isOn: $settings.attentionNotifications)
                Toggle(L10n.text("작업 완료 알림"), isOn: $settings.completionNotifications)
                Toggle(L10n.text("오류 알림"), isOn: $settings.errorNotifications)
                Toggle(L10n.text("알림음"), isOn: $settings.sound)
                Picker(L10n.text("같은 세션의 알림 간격"), selection: $settings.cooldownMinutes) {
                    Text(L10n.text("1분")).tag(1); Text(L10n.text("5분")).tag(5); Text(L10n.text("10분")).tag(10); Text(L10n.text("30분")).tag(30)
                }
                if let error = settings.notificationError { Text(L10n.text(error)).font(.caption).foregroundStyle(.red) }
            }
            Section {
                Toggle(L10n.text("조용한 시간대"), isOn: $settings.quietHours)
                HStack {
                    Text(L10n.text("시작")); hourPicker($settings.quietStart)
                    Text(L10n.language.locale.identifier.hasPrefix("ko") ? "종료" : "End"); hourPicker($settings.quietEnd)
                }.disabled(!settings.quietHours)
                if let date = settings.pauseUntil, date > Date() {
                    Text(L10n.format("일시 중지 · %@까지", L10n.date(date, dateStyle: .none)))
                    Button(L10n.text("알림 다시 켜기")) { settings.resumeNotifications() }
                } else { Button(L10n.text("알림 1시간 일시 중지")) { settings.pauseForHour() } }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var folderSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("세션 폴더")).font(.headline)
            List {
                ForEach(settings.sessionDirectories, id: \.self) { directory in
                    HStack {
                        Text(directory).font(.caption).textSelection(.enabled)
                        Spacer()
                        Button { store.disconnectSessionFolder(directory) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).help(L10n.text("폴더 제외"))
                    }
                }
            }.scrollContentBackground(.hidden).sessionCard()
            HStack {
                Button(L10n.text("폴더 추가…")) { store.connectSessionFolder() }
                Button(L10n.text("기본 폴더")) {
                    let directory = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/sessions").path
                    if !settings.sessionDirectories.contains(directory) { settings.sessionDirectories.append(directory) }
                }
            }
            if let error = store.folderError { Text(L10n.text(error)).font(.caption).foregroundStyle(.red) }
        }.padding(20)
    }

    private func hourPicker(_ binding: Binding<Int>) -> some View {
        Picker(L10n.text("시각"), selection: binding) {
            ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
        }.labelsHidden().frame(width: 100)
    }

}
