import SwiftUI
import AppKit

struct DiagnosticsView: View {
    @ObservedObject var store: SessionStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("진단").font(.title2)
                Spacer()
                Button("새로고침", action: store.refresh)
            }
            HStack(spacing: 20) {
                Text("세션 \(store.sessions.count)")
                Text("Codex 프로세스 \(store.processCount)")
                Text("읽기 실패 \(store.invalidFileCount)")
            }.font(.subheadline)
            Divider()
            ScrollView {
                Text(store.diagnostics.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.padding(16).sessionCard()
            Button("진단 복사") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("sessionbar 0.1.0\n" + store.diagnostics.joined(separator: "\n"), forType: .string)
            }
        }.padding(24).frame(minWidth: 560, minHeight: 360).sessionTheme()
    }
}
