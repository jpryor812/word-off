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
                badgeChip(badge)
                    .offset(badgeOffset(index: index, count: badges.count))
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

    private func badgeChip(_ badge: EarnedBadge) -> some View {
        ZStack {
            Circle()
                .fill(badge.tierColor)
                .frame(width: 28, height: 28)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            Image(systemName: badge.kind.icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
        }
        .accessibilityLabel(badge.title)
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

    private var accentColor: Color {
        if track.isMaxed, let tier = track.earnedTier {
            return BadgeTier.color(for: tier)
        }
        if let next = track.nextThreshold {
            return BadgeTier.color(for: next)
        }
        return Theme.tileText.opacity(0.35)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accentColor.opacity(track.earnedTier != nil ? 1 : 0.2))
                        .frame(width: 34, height: 34)
                    Image(systemName: track.kind.icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(track.earnedTier != nil ? .white : accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(track.kind.label)
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundColor(Theme.tileText)
                        if track.isMaxed {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                                .foregroundColor(accentColor)
                        } else if let earned = track.earnedTier {
                            Text("· \(tierTitle(earned))")
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundColor(BadgeTier.color(for: earned))
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
                            .fill(accentColor)
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

    private func tierTitle(_ tier: Int) -> String {
        switch track.kind {
        case .dailyPercentile: return "Top \(tier)%"
        case .flawlessDaily, .cleanSweep, .fullMenuDaily: return "Earned"
        default: return "Tier \(tier)"
        }
    }
}
