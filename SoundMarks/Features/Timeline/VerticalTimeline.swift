import SwiftUI

/// Year slider capsule on the right of the map.
/// The thumb shows the year; down — earlier, haptics on every step.
struct VerticalTimeline: View {
    let timeline: YearTimeline

    private let width: CGFloat = 52
    private let height: CGFloat = 196
    private let knob: CGFloat = 46

    var body: some View {
        GeometryReader { proxy in
            let travel = proxy.size.height - knob
            let steps = max(timeline.years.count - 1, 1)
            let offset = travel * CGFloat(timeline.selectedIndex) / CGFloat(steps)

            ZStack(alignment: .top) {
                // Dashed line — the thumb's track.
                Path { path in
                    path.move(to: CGPoint(x: proxy.size.width / 2, y: knob / 2))
                    path.addLine(to: CGPoint(x: proxy.size.width / 2, y: proxy.size.height - knob / 2))
                }
                .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 5]))
                .foregroundStyle(.secondary)

                Text(String(timeline.selectedYear))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(timeline.showsEverything ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
                    .frame(width: knob, height: knob)
                    .background {
                        Circle().fill(timeline.showsEverything
                                      ? AnyShapeStyle(.background.opacity(0.85))
                                      : AnyShapeStyle(DS.Colors.accent))
                    }
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                    .offset(y: offset)
                    .animation(DS.Motion.quick, value: timeline.selectedIndex)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let position = min(max(value.location.y - knob / 2, 0), travel)
                        let index = Int((position / max(travel, 1) * CGFloat(steps)).rounded())
                        if timeline.select(index: index) { Haptics.step() }
                    }
            )
        }
        .frame(width: width, height: height)
        .padding(6)
        .liquidGlass(in: Capsule())
        .accessibilityElement()
        .accessibilityLabel(Text("timeline.slider", comment: "Time slider"))
        .accessibilityValue(String(timeline.selectedYear))
        .accessibilityAdjustableAction { direction in
            let changed = switch direction {
            case .increment: timeline.select(index: timeline.selectedIndex - 1)
            case .decrement: timeline.select(index: timeline.selectedIndex + 1)
            @unknown default: false
            }
            if changed { Haptics.step() }
        }
    }
}
