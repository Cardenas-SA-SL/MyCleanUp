import SwiftUI

enum Theme {
    static let accent = Color(red: 0.42, green: 0.27, blue: 0.91)
    static let blue = Color(red: 0.18, green: 0.61, blue: 0.97)
    static let gradient = LinearGradient(colors: [accent, blue], startPoint: .topLeading, endPoint: .bottomTrailing)
}

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}

enum Fmt {
    static let date: DateFormatter = {
        let value = DateFormatter()
        value.locale = Locale(identifier: "es")
        value.dateStyle = .medium
        value.timeStyle = .none
        return value
    }()
}
