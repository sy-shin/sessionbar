import SwiftUI
import SessionbarCore

struct SessionTerminationButton: View {
    @ObservedObject var store: SessionStore
    let session: SessionRecord
    @State private var confirming = false
    @State private var actionError: String?

    var body: some View {
        Button(L10n.text("세션 종료…"), role: .destructive) { confirming = true }
            .disabled(session.runtime?.processStartTime == nil || session.runtime?.processMode != .dedicatedCLI || store.terminatingSessionIDs.contains(session.id))
            .modifier(SessionTerminationDialog(store: store, session: session,
                confirming: $confirming, actionError: $actionError))
    }
}

struct SessionTerminationDialog: ViewModifier {
    @ObservedObject var store: SessionStore
    let session: SessionRecord?
    @Binding var confirming: Bool
    @Binding var actionError: String?

    func body(content: Content) -> some View {
        content
            .alert(L10n.text("이 세션을 종료할까요?"), isPresented: $confirming) {
                Button(L10n.text("취소"), role: .cancel) { }
                Button(L10n.text("세션 종료"), role: .destructive) {
                    guard let session else { return }
                    Task { actionError = await store.terminateSession(session) }
                }
            } message: {
                Text((session?.projectName ?? "") + "\n" + (session?.title ?? "") + "\n" + L10n.text("선택한 세션이 종료됩니다. 대화 기록은 남습니다."))
            }
            .alert(L10n.text("세션 종료 실패"), isPresented: Binding(
                get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
                Button(L10n.text("확인")) { actionError = nil }
            } message: { Text(L10n.text(actionError ?? "")) }
    }
}
