import SwiftUI
import AppKit

struct DiagnosticsView: View {
    @ObservedObject var store: SessionStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L10n.text("진단")).font(.title2)
                Spacer()
                Button(L10n.text("새로고침"), action: store.refresh)
            }
            HStack(spacing: 20) {
                Text(L10n.format("세션 %d", store.sessions.count))
                Text(L10n.format("Codex 프로세스 %d", store.processCount))
                Text(L10n.format("읽기 실패 %d", store.invalidFileCount))
            }.font(.subheadline)
            Divider()
            ScrollView {
                Text(store.diagnostics.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.padding(16).sessionCard()
            Button(L10n.text("진단 복사")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("sessionbar 0.1.0\n" + store.diagnostics.joined(separator: "\n"), forType: .string)
            }
        }.padding(24).frame(minWidth: 560, minHeight: 360).sessionTheme()
    }
}
