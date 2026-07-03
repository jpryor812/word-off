import SwiftUI

/// Words With Friends–adjacent palette: warm woody oranges, cream tiles,
/// deep teal accents.
enum Theme {
    static let background = Color(red: 0.13, green: 0.32, blue: 0.39)      // deep teal
    static let backgroundLight = Color(red: 0.18, green: 0.42, blue: 0.50)
    static let panel = Color(red: 0.96, green: 0.93, blue: 0.86)           // cream
    static let tileFace = Color(red: 0.98, green: 0.92, blue: 0.78)        // tile cream
    static let tileEdge = Color(red: 0.72, green: 0.52, blue: 0.28)        // wood edge
    static let tileText = Color(red: 0.28, green: 0.18, blue: 0.08)
    static let accent = Color(red: 0.95, green: 0.56, blue: 0.19)          // orange
    static let accentDark = Color(red: 0.80, green: 0.42, blue: 0.10)
    static let win = Color(red: 0.35, green: 0.72, blue: 0.36)
    static let lose = Color(red: 0.85, green: 0.33, blue: 0.30)
    static let subtleText = Color.white.opacity(0.7)
}

struct TileView: View {
    let letter: Character
    var size: CGFloat = 44
    var flipped: Bool = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18)
                .fill(flipped ? Theme.tileFace : Theme.tileEdge)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
            if flipped {
                VStack(spacing: 0) {
                    Text(String(letter))
                        .font(.system(size: size * 0.52, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.tileText)
                    if let value = LetterBag.values[letter] {
                        Text("\(value)")
                            .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.tileText.opacity(0.65))
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .rotation3DEffect(.degrees(flipped ? 0 : 180), axis: (x: 0, y: 1, z: 0))
    }
}

struct RackView: View {
    let rack: [Character]
    var flipped: Bool = true
    var tileSize: CGFloat = 38

    var body: some View {
        HStack(spacing: tileSize < 30 ? 3 : 5) {
            ForEach(Array(rack.enumerated()), id: \.offset) { _, letter in
                TileView(letter: letter, size: tileSize, flipped: flipped)
            }
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.bold))
            .foregroundColor(.white)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(configuration.isPressed ? Theme.accentDark : color)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct PanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.panel))
    }
}

extension View {
    func panel() -> some View { modifier(PanelModifier()) }
}
