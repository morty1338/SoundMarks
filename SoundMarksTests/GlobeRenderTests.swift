import SceneKit
import Testing
import UIKit

@testable import SoundMarks

/// The planet must render instead of producing a SceneKit pink fill
/// (that's how SceneKit shows a shader that failed to compile).
@Suite("Planet rendering")
@MainActor
struct GlobeRenderTests {
    private func centerColor(of scene: GlobeScene, size: CGFloat = 160) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        let view = SCNView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        view.scene = scene.scene
        view.pointOfView = scene.cameraNode
        view.backgroundColor = .clear
        let image = view.snapshot()
        guard let cgImage = image.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return nil }
        let x = cgImage.width / 2, y = cgImage.height / 2
        let offset = y * cgImage.bytesPerRow + x * (cgImage.bitsPerPixel / 8)
        let order = cgImage.bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue
        let isBGRA = order == CGBitmapInfo.byteOrder32Little.rawValue
        let first = CGFloat(bytes[offset]) / 255, second = CGFloat(bytes[offset + 1]) / 255
        let third = CGFloat(bytes[offset + 2]) / 255
        return isBGRA ? (third, second, first) : (first, second, third)
    }

    private func isMagenta(_ color: (r: CGFloat, g: CGFloat, b: CGFloat)) -> Bool {
        color.r > 0.8 && color.b > 0.8 && color.g < 0.3
    }

    @Test("The mini planet renders by day and by night", arguments: [false, true])
    func mini(isDay: Bool) throws {
        let globe = GlobeScene(style: .mini)
        globe.setDaylight(isDay)
        globe.setPlaces([SphereMapping.Coordinate(latitude: 52.5, longitude: 13.4)])
        let color = try #require(centerColor(of: globe))
        #expect(!isMagenta(color), "center: \(color)")
    }

    @Test("Flags and pushpins render", arguments: [PlanetMarkerStyle.flag, .pushpin, .glow])
    func markers(style: PlanetMarkerStyle) throws {
        let globe = GlobeScene(style: .main)
        globe.setMarkerStyle(style)
        globe.setPlaces([SphereMapping.Coordinate(latitude: 0, longitude: 15)])
        let color = try #require(centerColor(of: globe, size: 300))
        #expect(!isMagenta(color), "center: \(color)")
        #expect(globe.markerStyle == style)
    }

    @Test("The main planet renders by day and by night", arguments: [false, true])
    func main(isDay: Bool) throws {
        let globe = GlobeScene(style: .main)
        globe.setDaylight(isDay)
        let color = try #require(centerColor(of: globe, size: 300))
        #expect(!isMagenta(color), "center: \(color)")
    }
}

@Suite("Mini planet size")
struct MiniGlobeSizeTests {
    @Test("The size is always in whole points — otherwise SceneKit on iPhone does not render the frame")
    func integerSize() {
        let size = MiniGlobeView.alignedSize(width: 68.508, height: 314.37)
        #expect(size == CGSize(width: 68, height: 314))
        #expect(MiniGlobeView.alignedSize(width: 0.2, height: 0.2) == CGSize(width: 1, height: 1))
    }
}
