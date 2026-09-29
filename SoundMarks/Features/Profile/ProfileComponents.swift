import SwiftUI

/// Strict profile elements: monochrome, thin lines, a single green accent.
/// Shared by my profile, a friend's profile and the friends screen.
enum ProfileStyle {
    static let background = LinearGradient(
        colors: [Color(red: 0.06, green: 0.065, blue: 0.08), Color(red: 0.015, green: 0.015, blue: 0.02)],
        startPoint: .top, endPoint: .bottom
    )
    static let hairline = Color.white.opacity(0.1)
    static let secondary = Color.white.opacity(0.55)
    static let tertiary = Color.white.opacity(0.35)
    static let panel = Color.white.opacity(0.04)

    /// Section caption: small uppercase with letter spacing.
    static func caption(_ text: Text) -> some View {
        text
            .font(.caption2.weight(.semibold))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Panel with a thin border — no colored badges or shadows.
struct ProfilePanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(ProfileStyle.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(ProfileStyle.hairline, lineWidth: 1))
    }
}

/// Profile header: avatar in a thin ring, name, caption and rank.
struct ProfileHeader: View {
    let nickname: String
    let colorHex: String?
    let avatarData: Data?
    /// Profile code, or "updated …" for a friend.
    var subtitle: String?
    let rank: Rank
    let placeCount: Int

    var body: some View {
        VStack(spacing: 14) {
            AvatarView(nickname: nickname, colorHex: colorHex, imageData: avatarData, size: 84)
                .padding(3)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))

            VStack(spacing: 4) {
                Text(verbatim: nickname)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(.caption.monospaced())
                        .foregroundStyle(ProfileStyle.secondary)
                }
            }

            RankSummary(rank: rank, placeCount: placeCount)
                .padding(.horizontal, DS.Spacing.xl)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Rank on one line: number and name in small caps, a thin progress line and how much is left.
struct RankSummary: View {
    let rank: Rank
    let placeCount: Int

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("profile.rank.level \(rank.level + 1)", comment: "Rank N")
                    .foregroundStyle(ProfileStyle.secondary)
                Rectangle().fill(ProfileStyle.hairline).frame(width: 1, height: 12)
                Text(verbatim: rank.title)
                    .foregroundStyle(DS.Colors.marks)
            }
            .font(.system(size: 13, weight: .semibold, design: .serif).smallCaps())
            .tracking(1.2)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(ProfileStyle.hairline)
                    Rectangle()
                        .fill(DS.Colors.marks)
                        .frame(width: max(2, proxy.size.width * rank.progress(placeCount: placeCount)))
                }
            }
            .frame(height: 2)

            Group {
                if let next = rank.nextThreshold {
                    Text("profile.rank.next \(next - placeCount)", comment: "Places left until the next rank")
                } else {
                    Text("profile.rank.max", comment: "Maximum rank")
                }
            }
            .font(.caption2)
            .foregroundStyle(ProfileStyle.tertiary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A 3×N grid of numbers in one panel, separated by thin lines.
struct StatGrid: View {
    struct Item: Identifiable {
        let value: Int
        let label: Text
        var id: Int
    }

    let items: [Item]

    var body: some View {
        ProfilePanel {
            let rows = stride(from: 0, to: items.count, by: 3).map { Array(items[$0..<min($0 + 3, items.count)]) }
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    ProfileStyle.hairline.frame(height: 1)
                }
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.element.id) { column, item in
                        if column > 0 {
                            ProfileStyle.hairline.frame(width: 1)
                        }
                        VStack(spacing: 4) {
                            Text(verbatim: "\(item.value)")
                                .font(.system(size: 26, weight: .light).monospacedDigit())
                                .foregroundStyle(.white)
                            item.label
                                .font(.caption2.weight(.semibold))
                                .tracking(0.8)
                                .textCase(.uppercase)
                                .foregroundStyle(ProfileStyle.tertiary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

/// Planet row: a small planet, its name, the number of records.
struct PlanetRow: View {
    let planet: PlanetInfo
    var showsChevron = true

    var body: some View {
        HStack(spacing: 12) {
            PlanetStackView(planets: [planet], diameter: 36, isDay: false)
            Text(verbatim: planet.title)
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            Text(verbatim: "\(planet.placeCount)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(ProfileStyle.secondary)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ProfileStyle.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Tabs with a thin underline.
struct UnderlineTabs<Value: Hashable>: View {
    let items: [(Value, Text)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                let isSelected = item.0 == selection
                Button {
                    Haptics.select()
                    withAnimation(.smooth(duration: 0.25)) { selection = item.0 }
                } label: {
                    VStack(spacing: 8) {
                        item.1
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .white : ProfileStyle.secondary)
                        Rectangle()
                            .fill(isSelected ? DS.Colors.marks : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .overlay(alignment: .bottom) {
            ProfileStyle.hairline.frame(height: 1)
        }
    }
}

/// Strict action row: a monochrome icon, text, red when needed.
struct ProfileActionRow: View {
    let icon: String
    let title: Text
    var isDestructive = false
    var showsDivider = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .regular))
                        .frame(width: 22)
                    title
                        .font(.subheadline)
                    Spacer()
                }
                .foregroundStyle(isDestructive ? Color(red: 1, green: 0.42, blue: 0.42) : .white)
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
                if showsDivider {
                    ProfileStyle.hairline.frame(height: 1).padding(.leading, 48)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
