import SwiftUI
import AppKit

struct DemoScene: View {
    @ObservedObject var store: SessionStore
    let scene: Int
    let english: Bool
    let progress: Double
    private var title: String {
        let ko = ["여러 Codex 세션을 한곳에서 확인", "확인할 요청과 결과 모아 보기", "완료된 응답 읽기", "확인한 결과 정리", "작업 창으로 돌아가기"]
        let en = ["See your Codex sessions together", "Find requests and unread results", "Read the completed reply", "Clear the result you reviewed", "Return to your task window"]
        return (english ? en : ko)[scene]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("sessionbar").font(.system(size: 21, weight: .semibold))
                Spacer()
                Text(english ? "macOS · Codex CLI" : "macOS · Codex CLI").font(.system(size: 14)).foregroundStyle(SessionTheme.muted)
            }
            Text(title).font(.system(size: 30, weight: .semibold))
            HStack(spacing: 24) {
                Group {
                    if scene == 2 || scene == 4 {
                        SessionDetailView(store: store, sessionID: "example-session-3")
                    } else {
                        SessionListView(store: store, settings: store.settings,
                            initialFilter: scene == 0 ? .openSessions : .unreviewed)
                    }
                }.id(scene).frame(width: scene == 2 || scene == 4 ? 1120 : 600, height: 640)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(SessionTheme.border))
                if scene != 2 && scene != 4 {
                    VStack(alignment: .leading, spacing: 22) {
                        Label(english ? "Attention requests" : "승인·입력 요청", systemImage: "exclamationmark.bubble")
                        Label(english ? "Unread results" : "아직 읽지 않은 결과", systemImage: "circle.badge")
                        Label(english ? "One session list" : "하나의 세션 목록", systemImage: "list.bullet")
                    }.font(.system(size: 20)).foregroundStyle(SessionTheme.accent)
                }
            }
            HStack {
                Text(english ? "Example projects and conversations · No desktop recording" : "예시 프로젝트와 대화 · 앱 화면만 표시")
                    .font(.system(size: 12)).foregroundStyle(SessionTheme.muted)
                Spacer()
                Text("\(scene + 1) / 5").font(.system(size: 13).monospacedDigit()).foregroundStyle(SessionTheme.muted)
            }
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 2).fill(SessionTheme.accent)
                    .frame(width: geometry.size.width * progress, height: 3)
            }.frame(height: 3)
        }.padding(40).frame(width: 1200, height: 900).background(SessionTheme.canvas)
    }
}

@MainActor final class CaptureDelegate: NSObject, NSApplicationDelegate {
    let output: URL
    let english: Bool
    var window: NSWindow?
    var host: NSHostingView<DemoScene>?
    var frame = 0
    var currentScene = -1
    var store: SessionStore!
    let fps = 12
    let totalFrames = 24 * 12
    init(output: URL, english: Bool) { self.output = output; self.english = english }
    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(english ? "en" : "ko", forKey: "sessionbar.language")
        UserDefaults.standard.set(false, forKey: "sessionbar.followSystemAppearance")
        store = SessionStore(english: english)
        // Keep a concise example list; all records are invented.
        store.sessions = store.sessions.filter { ["example-session-0", "example-session-1", "example-session-3"].contains($0.id) }
        store.activeSessionCount = store.sessions.count
        store.processCount = store.sessions.count
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 900),
            styleMask: [.borderless], backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        let view = NSHostingView(rootView: sceneView(0))
        view.frame = win.contentView!.bounds
        win.contentView = view; win.backgroundColor = NSColor(SessionTheme.canvas)
        window = win; host = view
        win.orderFront(nil)
        captureNext()
    }
    func sceneView(_ index: Int) -> DemoScene {
        DemoScene(store: store, scene: index, english: english, progress: Double(frame) / Double(totalFrames - 1))
    }
    func captureNext() {
        guard frame < totalFrames, let host else { NSApp.terminate(nil); return }
        let scene = min(4, frame / (fps * 5))
        if scene == 3 && currentScene != 3 {
            if let review = store.unreviewed["example-session-3"] { store.markReviewed(id: "example-session-3", token: review.token) }
        }
        currentScene = scene
        host.rootView = sceneView(scene)
        // Give SwiftUI tasks/layout time to load the synthetic detail and update the list.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [self] in
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Cannot render frame") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode frame") }
            do { try png.write(to: output.appendingPathComponent(String(format: "%04d.png", frame))) }
            catch { fatalError("Cannot save frame") }
            frame += 1
            captureNext()
        }
    }
}

@main struct CaptureMain {
    @MainActor static func main() {
        guard CommandLine.arguments.count == 3 else { fatalError("Output directory and language required") }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let delegate = CaptureDelegate(output: URL(fileURLWithPath: CommandLine.arguments[1]), english: CommandLine.arguments[2] == "en")
        app.delegate = delegate; app.run(); _ = delegate
    }
}
