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
            if result == .accessibilityRequired {
                HStack {
                    Button(L10n.text("접근성 설정 열기")) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                    Button(L10n.text("앱으로 이동")) {
                        if let runtime = session.runtime { result = SessionWindowConnector.activateApp(runtime) }
                    }
                }.font(.caption)
            }
        }
    }
}
