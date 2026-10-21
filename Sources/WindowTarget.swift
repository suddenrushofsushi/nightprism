import CoreGraphics
import Foundation

struct WindowTarget: Identifiable, Hashable, Sendable {
    let id: CGWindowID
    let ownerPID: pid_t
    let appName: String
    let title: String
    let frame: CGRect
}

enum WindowGeometry {
    static let fullCrop = CGRect(x: 0, y: 0, width: 1, height: 1)

    static func appKitRect(from quartzRect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        guard isValid(quartzRect), primaryScreenHeight.isFinite else { return .zero }
        let converted = CGRect(
            x: quartzRect.minX,
            y: primaryScreenHeight - quartzRect.minY - quartzRect.height,
            width: quartzRect.width,
            height: quartzRect.height
        )
        return isValid(converted) ? converted : .zero
    }

    static func normalizedCrop(_ frame: CGRect, in target: CGRect) -> CGRect? {
        guard isValid(frame), isValid(target) else { return nil }
        let clipped = frame.intersection(target)
        guard isValid(clipped) else { return nil }

        let normalized = CGRect(
            x: (clipped.minX - target.minX) / target.width,
            y: (clipped.minY - target.minY) / target.height,
            width: clipped.width / target.width,
            height: clipped.height / target.height
        )
        return isValid(normalized) ? normalized : nil
    }

    static func cropFrame(_ crop: CGRect, in target: CGRect) -> CGRect {
        guard isValid(crop), isValid(target) else { return .zero }
        let frame = CGRect(
            x: target.minX + crop.minX * target.width,
            y: target.minY + crop.minY * target.height,
            width: crop.width * target.width,
            height: crop.height * target.height
        )
        return isValid(frame) ? frame : .zero
    }

    private static func isValid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.minX.isFinite && rect.minY.isFinite
            && rect.maxX.isFinite && rect.maxY.isFinite && rect.width.isFinite
            && rect.height.isFinite && rect.width > 0 && rect.height > 0
    }
}
