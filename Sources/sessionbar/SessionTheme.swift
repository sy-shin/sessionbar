import SwiftUI
import AppKit
import SessionbarCore

enum SessionTheme {
    static let canvas = adaptive(0xF8F5EF, 0x211F1B)
    static let surface = adaptive(0xFFFFFF, 0x2C2923)
    static let inset = adaptive(0xEEE8DD, 0x373229)
    static let border = adaptive(0xDED5C6, 0x51493C)
    static let ink = adaptive(0x2C2923, 0xF5F0E7)
    static let muted = adaptive(0x756D60, 0xBFB5A5)
    static let accent = adaptive(0x806545, 0xD8BD94)

    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                           green: Double((value >> 8) & 255) / 255,
                           blue: Double(value & 255) / 255, alpha: 1)
        })
    }
}

private struct SessionThemeModifier: ViewModifier {
    @AppStorage("sessionbar.followSystemAppearance") private var followSystem = false

    func body(content: Content) -> some View {
        content
            .foregroundStyle(SessionTheme.ink)
            .tint(SessionTheme.accent)
            .background(SessionTheme.canvas)
            .preferredColorScheme(followSystem ? nil : .light)
            .onChange(of: followSystem, initial: true) { _, system in
                NSApp.appearance = system ? nil : NSAppearance(named: .aqua)
            }
    }
}

private struct SessionCardModifier: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    let radius: CGFloat
    func body(content: Content) -> some View {
        content
            .background(SessionTheme.surface, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius)
                .strokeBorder(SessionTheme.border, lineWidth: contrast == .increased ? 1.5 : 0.6))
    }
}

struct SessionIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(SessionTheme.accent)
            .frame(width: 32, height: 32)
            .background(configuration.isPressed ? SessionTheme.inset : SessionTheme.surface,
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(SessionTheme.border, lineWidth: 0.6))
    }
}

struct SessionStatusBadge: View {
    let state: SessionState
    var body: some View {
        Label(state.koreanLabel, systemImage: state.symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(state.color)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(state.color.opacity(0.08), in: Capsule())
    }
}

extension View {
    func sessionTheme() -> some View { modifier(SessionThemeModifier()) }
    func sessionCard(radius: CGFloat = 14) -> some View { modifier(SessionCardModifier(radius: radius)) }
}
