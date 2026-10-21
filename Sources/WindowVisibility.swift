import CoreGraphics
import Foundation

enum WindowVisibility {
    static func visibleRects(in frame: CGRect, occludedBy occluders: [CGRect]) -> [CGRect] {
        guard isValid(frame) else { return [] }
        var visible = [frame]

        for occluder in occluders where isValid(occluder) {
            visible = visible.flatMap { subtract(occluder, from: $0) }
            if visible.isEmpty { return [] }
        }

        return visible
    }

    private static func subtract(_ occluder: CGRect, from rect: CGRect) -> [CGRect] {
        let overlap = rect.intersection(occluder)
        guard isValid(overlap) else { return [rect] }

        var pieces: [CGRect] = []
        append(
            CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: overlap.minY - rect.minY),
            to: &pieces)
        append(
            CGRect(
                x: rect.minX, y: overlap.maxY, width: rect.width, height: rect.maxY - overlap.maxY),
            to: &pieces)
        append(
            CGRect(
                x: rect.minX, y: overlap.minY, width: overlap.minX - rect.minX,
                height: overlap.height), to: &pieces)
        append(
            CGRect(
                x: overlap.maxX, y: overlap.minY, width: rect.maxX - overlap.maxX,
                height: overlap.height), to: &pieces)
        return pieces
    }

    private static func append(_ rect: CGRect, to rects: inout [CGRect]) {
        if isValid(rect) { rects.append(rect) }
    }

    private static func isValid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.minX.isFinite && rect.minY.isFinite
            && rect.maxX.isFinite && rect.maxY.isFinite && rect.width.isFinite
            && rect.height.isFinite && rect.width > 0 && rect.height > 0
    }
}
