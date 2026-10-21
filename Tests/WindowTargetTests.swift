import CoreGraphics
import Testing

@testable import Nightprism

struct WindowTargetTests {
    @Test
    func convertsQuartzCoordinatesUsingPrimaryScreenHeightAndKeepsOffsets() {
        let converted = WindowGeometry.appKitRect(
            from: CGRect(x: -1440, y: 80, width: 400, height: 300),
            primaryScreenHeight: 900
        )

        #expect(converted == CGRect(x: -1440, y: 520, width: 400, height: 300))
    }

    @Test
    func cropMapsProportionallyWhenTargetMovesAndResizes() throws {
        let source = CGRect(x: 120, y: 70, width: 200, height: 100)
        let originalTarget = CGRect(x: 20, y: 20, width: 400, height: 200)
        let crop = try #require(WindowGeometry.normalizedCrop(source, in: originalTarget))
        let movedTarget = CGRect(x: -80, y: 150, width: 800, height: 400)

        #expect(crop == CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        #expect(
            WindowGeometry.cropFrame(crop, in: movedTarget)
                == CGRect(x: 120, y: 250, width: 400, height: 200)
        )
    }

    @Test
    func normalizedCropClipsToTargetAndRejectsInvalidOrOutsideFrames() {
        let target = CGRect(x: 10, y: 20, width: 100, height: 80)

        #expect(
            WindowGeometry.normalizedCrop(
                CGRect(x: 0, y: 0, width: 40, height: 50), in: target
            ) == CGRect(x: 0, y: 0, width: 0.3, height: 0.375)
        )
        #expect(
            WindowGeometry.normalizedCrop(CGRect(x: 200, y: 20, width: 10, height: 10), in: target)
                == nil)
        #expect(
            WindowGeometry.normalizedCrop(CGRect(x: 10, y: 20, width: 0, height: 10), in: target)
                == nil)
        #expect(WindowGeometry.normalizedCrop(.zero, in: target) == nil)
    }

    @Test
    func invalidGeometryProducesSafeEmptyResults() {
        #expect(
            WindowGeometry.appKitRect(
                from: CGRect(x: CGFloat.infinity, y: 0, width: 1, height: 1),
                primaryScreenHeight: 100)
                == .zero)
        #expect(
            WindowGeometry.appKitRect(
                from: CGRect(
                    x: CGFloat.greatestFiniteMagnitude, y: 0,
                    width: CGFloat.greatestFiniteMagnitude, height: 1),
                primaryScreenHeight: 100
            ) == .zero
        )
        #expect(WindowGeometry.cropFrame(WindowGeometry.fullCrop, in: .zero) == .zero)
        #expect(
            WindowGeometry.cropFrame(
                CGRect(x: CGFloat.infinity, y: 0, width: 1, height: 1),
                in: CGRect(x: 0, y: 0, width: 100, height: 100)
            ) == .zero
        )
        #expect(WindowGeometry.fullCrop == CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}
