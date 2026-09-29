import Foundation
import SwiftUI
import Testing
import UIKit

@testable import SoundMarks

/// The share card must render into a non-empty 9:16 image.
@Suite("Share card")
@MainActor
struct ShareCardTests {
    private func place(mediaCount: Int = 0) -> PlaceSnapshot {
        PlaceSnapshot(
            id: UUID(),
            latitude: 41.3874,
            longitude: 2.1686,
            placeName: "Pl. de Catalunya",
            city: "Barcelona",
            country: "Spain",
            note: nil,
            createdAt: Date(),
            eventDate: EventDate(year: 2023, month: 8, day: 14),
            pinStyleOverride: nil,
            geofenceEnabled: true,
            trackTitle: "Instant Crush",
            trackArtist: "Daft Punk & Julian Casablancas",
            artworkURL: nil,
            previewURL: nil,
            media: []
        )
    }

    private func solidImage(_ color: UIColor, side: CGFloat = 64) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    private func render(_ content: ShareCardContent, scale: CGFloat = 3) -> UIImage? {
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        return renderer.uiImage
    }

    @Test("The card renders in 9:16")
    func rendersNineBySixteen() throws {
        let image = try #require(render(ShareCardContent(place: place(), artwork: nil, photos: [])))
        #expect(image.size.width == ShareCardContent.size.width)
        #expect(image.size.height == ShareCardContent.size.height)

        let ratio = image.size.height / image.size.width
        #expect(abs(ratio - 16.0 / 9.0) < 0.01)
    }

    @Test("The card is not empty: the background is filled")
    func isNotBlank() throws {
        let image = try #require(render(ShareCardContent(place: place(), artwork: nil, photos: [])))
        let pixel = try #require(image.pixelColor(atUnit: CGPoint(x: 0.5, y: 0.08)))

        // The dark background gradient — neither transparent nor white.
        #expect(pixel.alpha > 0.9)
        #expect(pixel.brightness < 0.4)
    }

    @Test("The artwork lands on the record's label")
    func artworkLandsOnTheLabel() throws {
        // The exact label position depends on the Spacer layout, so
        // we count green pixels across the whole card instead of checking one point.
        let withArtwork = try #require(render(
            ShareCardContent(place: place(), artwork: solidImage(.systemGreen), photos: [])
        ))
        let withoutArtwork = try #require(render(
            ShareCardContent(place: place(), artwork: nil, photos: [])
        ))

        let green = withArtwork.countPixels { $0.green > $0.red + 0.1 && $0.green > $0.blue + 0.1 }
        let baseline = withoutArtwork.countPixels { $0.green > $0.red + 0.1 && $0.green > $0.blue + 0.1 }

        #expect(green > baseline)
        #expect(green > 50, "The label with the artwork should take a noticeable area")
    }

    @Test("Photos are added to the collage")
    func collageRenders() throws {
        let withPhotos = try #require(render(
            ShareCardContent(place: place(), artwork: nil, photos: [solidImage(.systemBlue)])
        ))
        let withoutPhotos = try #require(render(
            ShareCardContent(place: place(), artwork: nil, photos: [])
        ))
        #expect(withPhotos.pngData() != withoutPhotos.pngData())
    }
}

private extension UIImage {
    struct Pixel {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat

        var brightness: CGFloat { (red + green + blue) / 3 }
    }

    /// How many pixels of the scaled-down copy satisfy the condition.
    func countPixels(side: Int = 180, where matches: (Pixel) -> Bool) -> Int {
        guard let cgImage else { return 0 }
        let width = side
        let height = Int(CGFloat(side) * CGFloat(cgImage.height) / CGFloat(cgImage.width))
        var buffer = [UInt8](repeating: 0, count: width * height * 4)

        guard let context = CGContext(data: &buffer,
                                      width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 0 }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var count = 0
        for index in stride(from: 0, to: buffer.count, by: 4) {
            let pixel = Pixel(red: CGFloat(buffer[index]) / 255,
                              green: CGFloat(buffer[index + 1]) / 255,
                              blue: CGFloat(buffer[index + 2]) / 255,
                              alpha: CGFloat(buffer[index + 3]) / 255)
            if matches(pixel) { count += 1 }
        }
        return count
    }

    /// Pixel color at relative coordinates (0…1).
    func pixelColor(atUnit point: CGPoint) -> Pixel? {
        guard let cgImage else { return nil }
        let x = Int(CGFloat(cgImage.width) * point.x)
        let y = Int(CGFloat(cgImage.height) * point.y)
        guard (0..<cgImage.width).contains(x), (0..<cgImage.height).contains(y) else { return nil }

        var components = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &components,
                                      width: 1, height: 1,
                                      bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        context.draw(cgImage, in: CGRect(x: -CGFloat(x), y: -CGFloat(cgImage.height - y - 1),
                                         width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))

        return Pixel(red: CGFloat(components[0]) / 255,
                     green: CGFloat(components[1]) / 255,
                     blue: CGFloat(components[2]) / 255,
                     alpha: CGFloat(components[3]) / 255)
    }
}
