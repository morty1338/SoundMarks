import MapKit
import SwiftUI
import UIKit

/// Route mini map as an image: `ImageRenderer` can't draw MapKit,
/// so we take a map snapshot and draw the route line ourselves.
enum TripRouteSnapshot {
    static func render(route: [RouteSample], size: CGSize) async -> UIImage? {
        guard !route.isEmpty else { return nil }
        let coordinates = route.map(\.coordinate)

        let options = MKMapSnapshotter.Options()
        options.region = region(for: coordinates)
        options.size = size
        options.scale = 3
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        options.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)

        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            snapshot.image.draw(at: .zero)
            let points = coordinates.map(snapshot.point(for:))
            guard let first = points.first else { return }

            let path = UIBezierPath()
            path.move(to: first)
            points.dropFirst().forEach(path.addLine(to:))
            path.lineWidth = 4
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            UIColor(DS.Colors.accent).setStroke()
            path.stroke()

            for point in [first, points.last ?? first] {
                let dot = UIBezierPath(ovalIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
                UIColor.white.setFill()
                dot.fill()
            }
            _ = context
        }
    }

    /// A frame around the route with padding; a single point — a block around it.
    private static func region(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minLat = latitudes.min() ?? 0, maxLat = latitudes.max() ?? 0
        let minLon = longitudes.min() ?? 0, maxLon = longitudes.max() ?? 0
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.4, 0.02),
                                    longitudeDelta: max((maxLon - minLon) * 1.4, 0.02))
        return MKCoordinateRegion(center: center, span: span)
    }
}

/// A 9:16 card for a trip: route mini map, name, dates, records.
struct TripShareCard: View {
    let name: String
    let interval: DateInterval?
    let route: UIImage?
    let places: [PlaceSnapshot]
    let artworks: [UIImage]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.09), Color(white: 0.16), Color(white: 0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 18) {
                Spacer(minLength: 24)

                Group {
                    if let route {
                        Image(uiImage: route).resizable().scaledToFill()
                    } else {
                        Color.white.opacity(0.06)
                    }
                }
                .frame(width: 312, height: 312)
                .clipShape(RoundedRectangle(cornerRadius: 24))

                VStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 24, weight: .bold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    if let interval {
                        Text(interval.displayText)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(DS.Colors.vinyl)
                                if artworks.indices.contains(index) {
                                    Image(uiImage: artworks[index])
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 20, height: 20)
                                        .clipShape(Circle())
                                }
                                Circle().fill(Color.black).frame(width: 4, height: 4)
                            }
                            .frame(width: 36, height: 36)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(place.displayTitle)
                                    .font(.system(size: 14, weight: .semibold))
                                    .lineLimit(1)
                                Text(place.trackArtist ?? "")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.white)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, 36)

                Spacer(minLength: 20)
            }
        }
        .frame(width: ShareCardContent.size.width, height: ShareCardContent.size.height)
    }
}

extension DateInterval {
    /// "12–18 Sep 2026".
    var displayText: String {
        (start..<max(end, start)).formatted(.interval.day().month(.abbreviated).year())
    }
}
