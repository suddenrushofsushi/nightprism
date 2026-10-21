import CoreGraphics
import Testing

@testable import Nightprism

struct WindowVisibilityTests {
    private let frame = CGRect(x: 0, y: 0, width: 100, height: 100)

    @Test
    func leavesDisjointOccludersUnchanged() {
        let visible = WindowVisibility.visibleRects(
            in: frame,
            occludedBy: [CGRect(x: 120, y: 0, width: 20, height: 20)]
        )

        #expect(visible == [frame])
    }

    @Test
    func subtractsPartialOccluderIntoNonoverlappingRectangles() {
        let visible = WindowVisibility.visibleRects(
            in: frame,
            occludedBy: [CGRect(x: 25, y: 25, width: 50, height: 50)]
        )

        #expect(visible.count == 4)
        #expect(totalArea(visible) == 7500)
        #expect(
            visible.allSatisfy {
                $0.intersection(CGRect(x: 25, y: 25, width: 50, height: 50)).isEmpty
            })
        #expect(pairwiseDisjoint(visible))
    }

    @Test
    func completeOcclusionReturnsNoRectangles() {
        #expect(
            WindowVisibility.visibleRects(
                in: frame,
                occludedBy: [CGRect(x: -10, y: -10, width: 120, height: 120)]
            ).isEmpty
        )
    }

    @Test
    func overlappingOccludersKeepTheirUnionHidden() {
        let occluders = [
            CGRect(x: 20, y: 20, width: 50, height: 50),
            CGRect(x: 50, y: 20, width: 30, height: 50),
        ]
        let visible = WindowVisibility.visibleRects(in: frame, occludedBy: occluders)

        #expect(pairwiseDisjoint(visible))
        #expect(totalArea(visible) == 7000)
        #expect(
            visible.allSatisfy { rect in occluders.allSatisfy { rect.intersection($0).isEmpty } })
    }

    @Test
    func emptyAndInvalidBoundsReturnNoRectangles() {
        #expect(WindowVisibility.visibleRects(in: .zero, occludedBy: []).isEmpty)
        #expect(
            WindowVisibility.visibleRects(
                in: CGRect(x: 0, y: 0, width: 100, height: 100),
                occludedBy: [CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 10)]
            ) == [frame]
        )
    }

    private func totalArea(_ rects: [CGRect]) -> CGFloat {
        rects.reduce(0) { $0 + $1.width * $1.height }
    }

    private func pairwiseDisjoint(_ rects: [CGRect]) -> Bool {
        for first in rects.indices {
            for second in rects.indices where second > first {
                if !rects[first].intersection(rects[second]).isEmpty { return false }
            }
        }
        return true
    }
}
