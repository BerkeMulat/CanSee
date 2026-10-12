//
//  EyeGeometry.swift
//  CanSee
//
//  The one eye drawing shared by the menu bar icon, the panel header and the app icon.
//

import CoreGraphics

/// Paths for an almond-shaped eye spanning `rect` from corner to corner.
///
/// `openness` runs from 0 (closed, lashes visible) to 1 (wide open). `look` moves the iris,
/// each axis in -1...1. Geometry is computed in y-up "eye units" (corners at x = ±1) and then
/// mapped into `rect`; pass `flipped: true` for y-down contexts such as SwiftUI's Canvas.
nonisolated struct EyeGeometry {
    let opening: CGPath
    let upperLid: CGPath
    let lowerLid: CGPath
    let lashes: CGPath
    let lashOpacity: CGFloat
    let irisCenter: CGPoint
    let irisRadius: CGFloat
    /// Points per eye unit; handy for scaling stroke widths.
    let unit: CGFloat

    private static let upperOpen: CGFloat = 0.60
    private static let lowerOpen: CGFloat = -0.44
    private static let closedLine: CGFloat = -0.24
    /// How far the curve handles sit from the corners; larger values give a rounder eye.
    private static let handle: CGFloat = 0.62
    /// Shifts the drawing down so the open eye (taller upper lid) looks optically centered.
    private static let opticalOffset: CGFloat = -0.07

    init(in rect: CGRect, openness: CGFloat, look: CGPoint = .zero, flipped: Bool = false) {
        let t = min(max(openness, 0), 1)
        let unit = rect.width / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let ySign: CGFloat = flipped ? -1 : 1
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: center.x + x * unit, y: center.y + ySign * (y + Self.opticalOffset) * unit)
        }

        // A symmetric cubic peaks at 3/4 of its handle height, so scale handles to hit the bulge.
        let upper = (Self.closedLine + (Self.upperOpen - Self.closedLine) * t) / 0.75
        let lower = (Self.closedLine + (Self.lowerOpen - Self.closedLine) * t) / 0.75
        let k = Self.handle

        let upperLid = CGMutablePath()
        upperLid.move(to: point(-1, 0))
        upperLid.addCurve(to: point(1, 0), control1: point(-1 + k, upper), control2: point(1 - k, upper))

        let lowerLid = CGMutablePath()
        lowerLid.move(to: point(-1, 0))
        lowerLid.addCurve(to: point(1, 0), control1: point(-1 + k, lower), control2: point(1 - k, lower))

        let opening = CGMutablePath()
        opening.move(to: point(-1, 0))
        opening.addCurve(to: point(1, 0), control1: point(-1 + k, upper), control2: point(1 - k, upper))
        opening.addCurve(to: point(-1, 0), control1: point(1 - k, lower), control2: point(-1 + k, lower))
        opening.closeSubpath()

        // Lashes hang from the closed lid and fade out as the eye opens.
        let lashes = CGMutablePath()
        let closedHandle = Self.closedLine / 0.75
        for (x, angle) in [(-0.56, -0.62), (0.0, 0.0), (0.56, 0.62)] as [(CGFloat, CGFloat)] {
            let y = Self.cubicY(atX: x, handleHeight: closedHandle, handle: k) - 0.07
            let length: CGFloat = 0.25
            lashes.move(to: point(x, y))
            lashes.addLine(to: point(x + sin(angle) * length, y - cos(angle) * length))
        }

        let lookX = min(max(look.x, -1), 1)
        let lookY = min(max(look.y, -1), 1)

        self.opening = opening
        self.upperLid = upperLid
        self.lowerLid = lowerLid
        self.lashes = lashes
        self.lashOpacity = max(0, 1 - t / 0.22)
        self.irisCenter = point(lookX * 0.30, lookY * 0.16 + 0.04)
        self.irisRadius = 0.36 * unit
        self.unit = unit
    }

    /// Height of the symmetric lid curve at `x` (both in eye units), found by bisection on the
    /// curve parameter; cheap enough to run per frame.
    private static func cubicY(atX x: CGFloat, handleHeight h: CGFloat, handle k: CGFloat) -> CGFloat {
        let xs: [CGFloat] = [-1, -1 + k, 1 - k, 1]
        let ys: [CGFloat] = [0, h, h, 0]
        func bezier(_ v: [CGFloat], _ s: CGFloat) -> CGFloat {
            let m = 1 - s
            return m * m * m * v[0] + 3 * m * m * s * v[1] + 3 * m * s * s * v[2] + s * s * s * v[3]
        }
        var low: CGFloat = 0, high: CGFloat = 1
        for _ in 0..<18 {
            let mid = (low + high) / 2
            if bezier(xs, mid) < x { low = mid } else { high = mid }
        }
        return bezier(ys, (low + high) / 2)
    }
}

extension CGRect {
    nonisolated init(center: CGPoint, radius: CGFloat) {
        self.init(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}
