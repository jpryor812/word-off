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
    static let speed = Color(red: 0.20, green: 0.55, blue: 0.95)         // fast-submit blue
    static let subtleText = Color.white.opacity(0.7)
}

/// Small circular "X" button used to leave a game in progress (top-left corner).
struct ExitGameButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .black))
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.backgroundLight))
        }
        .accessibilityLabel("Exit game")
    }
}

struct TileView: View {
    let letter: Character
    var size: CGFloat = 44
    var flipped: Bool = true
    /// Emphasize the Scrabble point value (onboarding teach).
    var highlightPoints: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18)
                .fill(flipped ? Theme.tileFace : Theme.tileEdge)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
            if flipped {
                Text(String(letter))
                    .font(.system(size: size * 0.52, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.tileText)
                if let value = LetterBag.values[letter] {
                    Text("\(value)")
                        .font(.system(size: size * (highlightPoints ? 0.28 : 0.22), weight: .bold, design: .rounded))
                        .foregroundColor(highlightPoints ? Theme.accentDark : Theme.tileText.opacity(0.65))
                        .padding(highlightPoints ? 3 : 0)
                        .background {
                            if highlightPoints {
                                Circle().fill(Theme.accent.opacity(0.35))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, size * 0.06)
                        .padding(.trailing, size * 0.08)
                }
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if highlightPoints {
                RoundedRectangle(cornerRadius: size * 0.18)
                    .stroke(Theme.accent, lineWidth: 2.5)
            }
        }
        .rotation3DEffect(.degrees(flipped ? 0 : 180), axis: (x: 0, y: 1, z: 0))
    }
}

/// Word-tile badge: cream face, gold border, SF Symbol instead of a letter,
/// prestige in the top-right corner (same spot as letter point values).
struct BadgeTileView: View {
    let icon: String
    /// Prestige level 1…n; nil = not earned yet (dimmed tile, no number).
    var prestige: Int? = nil
    var size: CGFloat = 44
    var dimmed: Bool = false
    /// Stronger gold stroke for pre-game matchup badges on dark backgrounds.
    var strongGoldBorder: Bool = false

    private static let goldBorder = Color(red: 0.85, green: 0.68, blue: 0.18)

    var body: some View {
        let locked = dimmed || prestige == nil
        let corner = size * 0.18
        let borderWidth = strongGoldBorder
            ? max(2.0, size * 0.07)
            : max(1.5, size * 0.045)
        ZStack {
            RoundedRectangle(cornerRadius: corner)
                .fill(locked ? Theme.tileFace.opacity(0.5) : Theme.tileFace)
                .shadow(color: .black.opacity(locked ? 0.12 : 0.25), radius: 2, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: corner)
                        .strokeBorder(
                            Self.goldBorder.opacity(locked ? 0.35 : 1),
                            lineWidth: borderWidth)
                )

            Image(systemName: icon)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundColor(Theme.tileText.opacity(locked ? 0.35 : 0.9))

            if let prestige {
                Text("\(prestige)")
                    .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.tileText.opacity(0.65))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, size * 0.06)
                    .padding(.trailing, size * 0.08)
            }
        }
        .frame(width: size, height: size)
    }
}

struct RackView: View {
    let rack: [Character]
    var flipped: Bool = true
    var tileSize: CGFloat = 38
    /// Number of rows to wrap the tiles into (used for large daily racks).
    var wrapRows: Int = 1
    /// When true, tiles slide in from off-screen left (~0.75s), then `flipped` handles the reveal.
    var slideIn: Bool = false
    /// Highlight Scrabble points on these letters (onboarding practice teach).
    var highlightPointLetters: Set<Character> = []

    @State private var settled = true

    private var spacing: CGFloat { tileSize < 30 ? 3 : 5 }
    static let slideTotalDuration: Double = 0.75
    private static let perTileDuration: Double = 0.55

    var body: some View {
        Group {
            if wrapRows <= 1 {
                row(Array(rack.indices), rowStart: 0)
            } else {
                let perRow = Int(ceil(Double(rack.count) / Double(wrapRows)))
                VStack(spacing: spacing) {
                    ForEach(0..<wrapRows, id: \.self) { r in
                        let start = r * perRow
                        let end = min(start + perRow, rack.count)
                        if start < end {
                            row(Array(start..<end), rowStart: start)
                        }
                    }
                }
            }
        }
        .onAppear { runSlideInIfNeeded(force: slideIn) }
        .onChange(of: slideIn) { _, active in
            runSlideInIfNeeded(force: active)
        }
    }

    private func row(_ indices: [Int], rowStart: Int) -> some View {
        HStack(spacing: spacing) {
            ForEach(Array(indices.enumerated()), id: \.element) { order, i in
                let staggerIndex = rowStart + order
                TileView(
                    letter: rack[i],
                    size: tileSize,
                    flipped: flipped,
                    highlightPoints: highlightPointLetters.contains(rack[i]))
                    .offset(x: settled ? 0 : slideStartX(for: staggerIndex))
                    .animation(slideAnimation(for: staggerIndex), value: settled)
                    .animation(.easeInOut(duration: 0.35), value: flipped)
                    .animation(.easeInOut(duration: 0.25), value: highlightPointLetters)
            }
        }
    }

    /// Far enough left that the whole rack starts off-screen.
    private func slideStartX(for index: Int) -> CGFloat {
        let rackWidth = CGFloat(rack.count) * (tileSize + spacing)
        return -(rackWidth + 120 + CGFloat(index) * 12)
    }

    private func slideAnimation(for index: Int) -> Animation {
        let count = max(rack.count - 1, 1)
        // Light stagger so they still read as a pack sliding in together.
        let maxDelay = max(0, Self.slideTotalDuration - Self.perTileDuration)
        let delay = maxDelay * Double(index) / Double(count)
        return .easeOut(duration: Self.perTileDuration).delay(delay)
    }

    private func runSlideInIfNeeded(force: Bool) {
        guard force else {
            settled = true
            return
        }
        // Snap off-screen, then ease in with per-tile stagger (see slideAnimation).
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { settled = false }
        settled = true
    }
}

/// Computes rack tile size from available space — landscape uses the wider axis for bigger letters.
enum RackLayout {
    static func tileSize(
        letterCount: Int,
        in size: CGSize,
        minSize: CGFloat = 30,
        maxSize: CGFloat = 58
    ) -> CGFloat {
        let isLandscape = size.width > size.height
        let spacing: CGFloat = 5
        let horizontalPadding: CGFloat = 32
        let availableWidth = size.width - horizontalPadding
        let widthFit = (availableWidth - spacing * CGFloat(max(letterCount - 1, 0)))
            / CGFloat(max(letterCount, 1))

        if isLandscape {
            let heightCap = size.height * 0.38
            return min(maxSize, max(minSize, min(widthFit, heightCap)))
        }

        // Portrait: scale tiles to fit every letter on one row.
        return min(maxSize, max(minSize, widthFit))
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

/// Wraps subviews left-to-right onto as many rows as needed, sizing each to its
/// intrinsic width so content (e.g. a word chip) never wraps mid-item.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
