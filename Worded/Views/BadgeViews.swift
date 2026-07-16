import SwiftUI

// MARK: - Pre-game VS screen

struct MatchupIntroView: View {
    let playerName: String
    let opponentName: String
    let playerBadges: [EarnedBadge]
    let opponentBadges: [EarnedBadge]

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            HStack(alignment: .center, spacing: 20) {
                playerColumn(name: playerName, badges: playerBadges, highlight: true)
                    .offset(x: appeared ? 0 : -80)
                    .opacity(appeared ? 1 : 0)

                Text("VS")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundColor(Theme.accent)
                    .scaleEffect(appeared ? 1 : 0.3)
                    .opacity(appeared ? 1 : 0)

                playerColumn(name: opponentName, badges: opponentBadges, highlight: false)
                    .offset(x: appeared ? 0 : 80)
                    .opacity(appeared ? 1 : 0)
            }

            Text("ROUND 1")
                .font(.system(.title3, design: .rounded).weight(.black))
                .foregroundColor(.white.opacity(0.7))
                .opacity(appeared ? 1 : 0)

            Spacer()
        }
        .padding()
        .onAppear {
            withAnimation(.spring(duration: 0.7)) {
                appeared = true
            }
        }
    }

    private func playerColumn(name: String, badges: [EarnedBadge], highlight: Bool) -> some View {
        VStack(spacing: 10) {
            BadgeAvatarView(name: name, badges: badges, highlight: highlight)
            Text(name)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Avatar with orbiting badges

struct BadgeAvatarView: View {
    let name: String
    let badges: [EarnedBadge]
    var highlight = false
    var size: CGFloat = 88

    private var initials: String {
        let parts = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var body: some View {
        ZStack {
            ForEach(Array(badges.enumerated()), id: \.element.id) { index, badge in
                BadgeTileView(
                    icon: badge.kind.icon,
                    prestige: badge.prestigeLevel,
                    size: 30)
                .offset(badgeOffset(index: index, count: badges.count))
                .accessibilityLabel(badge.title)
            }

            RoundedRectangle(cornerRadius: 16)
                .fill(highlight ? Theme.accent.opacity(0.25) : Theme.backgroundLight)
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(highlight ? Theme.accent : Color.white.opacity(0.25), lineWidth: 2.5)
                )

            Text(initials)
                .font(.system(size: size * 0.34, weight: .black, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: size + 44, height: size + 44)
    }

    /// Places badges evenly around the avatar square border.
    private func badgeOffset(index: Int, count: Int) -> CGSize {
        let slots = max(count, 1)
        let angle = (Double(index) / Double(slots)) * 2 * .pi - .pi / 2
        let radius = size / 2 + 18
        return CGSize(
            width: cos(angle) * radius,
            height: sin(angle) * radius)
    }
}

// MARK: - Stats badge progress

struct BadgeProgressRow: View {
    let track: BadgeTrackItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                BadgeTileView(
                    icon: track.kind.icon,
                    prestige: track.prestigeLevel,
                    size: 36,
                    dimmed: track.prestigeLevel == nil)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(track.kind.label)
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundColor(Theme.tileText)
                        if track.isMaxed {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.win)
                        } else if let level = track.prestigeLevel {
                            Text("· Level \(level)")
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundColor(Theme.tileText.opacity(0.55))
                        }
                    }
                    Text(track.detail)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundColor(Theme.tileText.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Text(track.progressLabel)
                    .font(.system(.caption, design: .rounded).weight(.black))
                    .foregroundColor(Theme.tileText.opacity(0.75))
                    .multilineTextAlignment(.trailing)
            }

            if !track.isMaxed, track.nextThreshold != nil {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Theme.tileText.opacity(0.1))
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: geo.size.width * track.progressFraction)
                    }
                }
                .frame(height: 6)

                if let next = track.nextTierLabel {
                    Text("Next: \(next)")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundColor(Theme.tileText.opacity(0.5))
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - End-game badge progress celebration

struct BadgeProgressCelebrationView: View {
    let deltas: [BadgeProgressDelta]
    let onNext: () -> Void

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                Text("BADGE PROGRESS")
                    .font(.system(.title2, design: .rounded).weight(.black))
                    .foregroundColor(.white)
                    .padding(.top, 36)
                    .padding(.bottom, 8)

                Text(deltas.isEmpty
                     ? "No badge progress this time — keep playing!"
                     : "Here's what you unlocked this game")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(Theme.subtleText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)

                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(Array(deltas.enumerated()), id: \.element.id) { index, delta in
                            BadgeProgressCelebrationRow(delta: delta, delay: Double(index) * 0.35)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }

                Button(action: onNext) {
                    Text("Next")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
                .padding(.top, 8)
            }
        }
    }
}

private struct BadgeProgressCelebrationRow: View {
    let delta: BadgeProgressDelta
    let delay: Double

    @State private var barFraction: Double = 0
    @State private var showNewNumber = false
    @State private var numberScale: CGFloat = 1
    @State private var numberShake: CGFloat = 0

    private var prestige: Int? {
        BadgeTier.prestigeLevel(earnedTier: delta.earnedTier, kind: delta.kind)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                BadgeTileView(
                    icon: delta.kind.icon,
                    prestige: prestige,
                    size: 42,
                    dimmed: prestige == nil && !delta.newlyEarned)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(delta.kind.label)
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundColor(Theme.tileText)
                        if delta.newlyEarned {
                            Text("NEW!")
                                .font(.system(.caption2, design: .rounded).weight(.black))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Theme.win))
                        } else if let prestige {
                            Text("· Level \(prestige)")
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundColor(Theme.tileText.opacity(0.55))
                        }
                    }
                    Text(delta.kind.detail)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundColor(Theme.tileText.opacity(0.55))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Text(showNewNumber ? delta.toLabel : delta.fromLabel)
                    .font(.system(.subheadline, design: .rounded).weight(.black))
                    .foregroundColor(Theme.tileText)
                    .scaleEffect(numberScale)
                    .offset(x: numberShake)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.tileText.opacity(0.12))
                    Capsule()
                        .fill(delta.newlyEarned ? Theme.win : Theme.accent)
                        .frame(width: max(4, geo.size.width * barFraction))
                }
            }
            .frame(height: 10)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.panel))
        .onAppear { runAnimation() }
    }

    private func runAnimation() {
        barFraction = delta.fromFraction
        showNewNumber = false
        numberScale = 1
        numberShake = 0

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.25 + delay))
            withAnimation(.easeInOut(duration: 0.85)) {
                barFraction = delta.toFraction
            }
            try? await Task.sleep(for: .seconds(0.9))
            showNewNumber = true
            withAnimation(.spring(response: 0.28, dampingFraction: 0.45)) {
                numberScale = 1.35
            }
            for _ in 0..<6 {
                withAnimation(.easeInOut(duration: 0.08)) { numberShake = 5 }
                try? await Task.sleep(for: .seconds(0.08))
                withAnimation(.easeInOut(duration: 0.08)) { numberShake = -5 }
                try? await Task.sleep(for: .seconds(0.08))
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                numberShake = 0
                numberScale = 1
            }
        }
    }
}
