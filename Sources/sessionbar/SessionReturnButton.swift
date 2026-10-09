import SwiftUI
import AppKit
import SessionbarCore

struct SessionReturnButton: View {
    @ObservedObject var store: SessionStore
    let session: SessionRecord
    @State private var returning = false
    @State private var result: WindowReturnResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button { returning = true; Task { result = await store.returnToSession(id: session.id); returning = false } } label: {
                Label(L10n.text("작업 창으로 이동"), systemImage: "arrow.up.forward.app")
            }.disabled(returning || session.isRuntimeStale)
            if let message = result?.message {
                Text(L10n.text(message)).font(.caption).foregroundStyle(SessionTheme.muted)
            }
            if needsRecovery {
                HStack {
                    if result == .accessibilityRequired {
                        Button(L10n.text("접근성 설정 열기")) { openPrivacySettings("Privacy_Accessibility") }
                    }
                    if result == .terminalFailure(.permissionDenied) {
                        Button(L10n.text("자동화 설정 열기")) { openPrivacySettings("Privacy_Automation") }
                    }
                    if session.runtime?.originAppProcessID != nil {
                        Button(L10n.text("앱으로 이동")) {
                            returning = true
                            Task { result = await store.activateOriginApp(id: session.id); returning = false }
                        }.disabled(returning || session.isRuntimeStale)
                    }
                }.font(.caption)
            }
        }
    }
    private var needsRecovery: Bool {
        switch result {
        case .accessibilityRequired, .terminalFailure, .failed: return true
        default: return false
        }
    }
    private func openPrivacySettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}
