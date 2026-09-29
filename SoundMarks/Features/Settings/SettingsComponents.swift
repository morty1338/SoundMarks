import SwiftUI

/// Settings palette: the app's space slightly lighter and the green accent of the "Marks" titles.
enum SettingsStyle {
    static let background = LinearGradient(
        colors: [Color(red: 0.07, green: 0.08, blue: 0.14), Color(red: 0.02, green: 0.02, blue: 0.05)],
        startPoint: .top, endPoint: .bottom
    )
    static let card = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.08)
    static let divider = Color.white.opacity(0.07)
    static let tint = DS.Colors.marks
}

/// Settings group: a title, a glass card and a hint below it.
struct SettingsCard<Content: View>: View {
    let title: Text?
    var footer: Text?
    @ViewBuilder let content: Content

    init(_ title: Text? = nil, footer: Text? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            if let title {
                title
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DS.Colors.onDarkSecondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, DS.Spacing.s)
            }
            VStack(spacing: 0) {
                content
            }
            .background(SettingsStyle.card, in: RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous)
                .strokeBorder(SettingsStyle.cardStroke, lineWidth: 1))
            if let footer {
                footer
                    .font(.footnote)
                    .foregroundStyle(DS.Colors.onDarkSecondary)
                    .padding(.horizontal, DS.Spacing.s)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A colored badge with an icon, like in system Settings — only in the app palette.
struct SettingsIcon: View {
    let systemName: String
    let color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(
                LinearGradient(colors: [color.opacity(0.95), color.opacity(0.7)],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

/// Card row: icon, title, explanation and anything on the right.
struct SettingsRow<Trailing: View>: View {
    let icon: String
    let color: Color
    let title: Text
    var subtitle: Text?
    var showsDivider = true
    @ViewBuilder let trailing: Trailing

    init(icon: String, color: Color, title: Text, subtitle: Text? = nil, showsDivider: Bool = true,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.icon = icon
        self.color = color
        self.title = title
        self.subtitle = subtitle
        self.showsDivider = showsDivider
        self.trailing = trailing()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Spacing.m) {
                SettingsIcon(systemName: icon, color: color)
                VStack(alignment: .leading, spacing: 2) {
                    title
                        .font(.body)
                        .foregroundStyle(DS.Colors.onDarkText)
                    if let subtitle {
                        subtitle
                            .font(.caption)
                            .foregroundStyle(DS.Colors.onDarkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: DS.Spacing.s)
                trailing
            }
            .padding(.horizontal, DS.Spacing.m)
            .padding(.vertical, 12)
            .frame(minHeight: 52)
            .contentShape(Rectangle())

            if showsDivider {
                SettingsStyle.divider
                    .frame(height: 1)
                    .padding(.leading, DS.Spacing.m + 30 + DS.Spacing.m)
            }
        }
    }
}

/// Toggle row.
struct SettingsToggleRow: View {
    let icon: String
    let color: Color
    let title: Text
    var subtitle: Text?
    var showsDivider = true
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(icon: icon, color: color, title: title, subtitle: subtitle, showsDivider: showsDivider) {
            Toggle(isOn: $isOn) { title }
                .labelsHidden()
                .tint(SettingsStyle.tint)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Choice tile with a picture — marker or pin look.
struct SettingsChoiceTile<Preview: View>: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let preview: Preview

    var body: some View {
        Button {
            Haptics.select()
            action()
        } label: {
            VStack(spacing: DS.Spacing.s) {
                preview
                    .frame(height: 64)
                    .frame(maxWidth: .infinity)
                Text(verbatim: title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? SettingsStyle.tint : DS.Colors.onDarkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.vertical, DS.Spacing.m)
            .padding(.horizontal, DS.Spacing.s)
            .background(Color.white.opacity(isSelected ? 0.1 : 0.03),
                        in: RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                .strokeBorder(isSelected ? SettingsStyle.tint : Color.clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Planet marker previews

/// Drawings for choosing the marker look: light, flag, pushpin — on a piece of planet.
struct MarkerPreview: View {
    let style: PlanetMarkerStyle

    var body: some View {
        ZStack(alignment: .bottom) {
            // A piece of planet.
            Ellipse()
                .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.62, blue: 0.86),
                                              Color(red: 0.2, green: 0.4, blue: 0.7)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 76, height: 24)
                .overlay(Ellipse().fill(Color(red: 0.53, green: 0.75, blue: 0.45)).frame(width: 36, height: 12).offset(x: -8))
                .offset(y: 8)

            switch style {
            case .glow:
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Color(red: 1, green: 0.95, blue: 0.82),
                                                      Color(red: 1, green: 0.6, blue: 0.3).opacity(0)],
                                             center: .center, startRadius: 1, endRadius: 16))
                        .frame(width: 32, height: 32)
                    Circle().fill(.white).frame(width: 7, height: 7)
                }
                .offset(y: -6)
            case .flag:
                FlagShape()
                    .offset(y: -4)
            case .pushpin:
                PushpinShape()
                    .offset(y: -3)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct FlagShape: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Capsule().fill(Color(white: 0.3)).frame(width: 16, height: 4).offset(x: -6, y: 1)
            Rectangle().fill(.white).frame(width: 2.5, height: 44).offset(x: 0)
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 24, y: 8))
                path.addLine(to: CGPoint(x: 0, y: 16))
                path.closeSubpath()
            }
            .fill(LinearGradient(colors: [Color(red: 1, green: 0.35, blue: 0.4), Color(red: 0.8, green: 0.12, blue: 0.2)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: 24, height: 16)
            .offset(x: 2.5, y: -28)
        }
        .frame(width: 30, height: 46, alignment: .bottomLeading)
    }
}

private struct PushpinShape: View {
    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.85, blue: 0.35), Color(red: 0.9, green: 0.6, blue: 0.1)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 22, height: 7)
            UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 4,
                                   bottomTrailingRadius: 4, topTrailingRadius: 2)
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.8, blue: 0.3), Color(red: 0.85, green: 0.55, blue: 0.1)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 12, height: 16)
            Path { path in
                path.move(to: CGPoint(x: 1, y: 0))
                path.addLine(to: CGPoint(x: 3, y: 0))
                path.addLine(to: CGPoint(x: 2, y: 20))
                path.closeSubpath()
            }
            .fill(Color(white: 0.75))
            .frame(width: 4, height: 20)
        }
    }
}

/// Map pin preview: record or turntable.
struct PinStylePreview: View {
    let style: PinStyle

    var body: some View {
        Image(uiImage: PinImageRenderer.image(style: style, artwork: nil, artworkKey: nil, diameter: 52))
            .accessibilityHidden(true)
    }
}
