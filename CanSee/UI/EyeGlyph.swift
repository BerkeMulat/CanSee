//
//  EyeGlyph.swift
//  CanSee
//
//  The panel's colored eye. SwiftUI interpolates openness and gaze, so it only redraws while
//  something actually moves.
//

import SwiftUI

struct EyeGlyph: View, Animatable {
    var openness: CGFloat
    var look: CGPoint

    @Environment(\.colorScheme) private var colorScheme

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(openness, AnimatablePair(look.x, look.y)) }
        set {
            openness = newValue.first
            look = CGPoint(x: newValue.second.first, y: newValue.second.second)
        }
    }

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 0)
            let eye = EyeGeometry(in: rect, openness: openness, look: look, flipped: true)
            let opening = Path(eye.opening)
            let line = StrokeStyle(lineWidth: max(1.6, eye.unit * 0.12), lineCap: .round, lineJoin: .round)

            if openness > 0.02 {
                let sclera = colorScheme == .dark ? [Color(white: 0.72), Color(white: 0.9)] : [Color(white: 0.85), .white]
                context.fill(opening, with: .linearGradient(Gradient(colors: sclera), startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))

                context.drawLayer { layer in
                    layer.clip(to: opening)
                    let center = eye.irisCenter
                    let radius = eye.irisRadius
                    let iris = Path(ellipseIn: CGRect(center: center, radius: radius))
                    layer.fill(iris, with: .radialGradient(Gradient(colors: Theme.aurora), center: center, startRadius: radius * 0.15, endRadius: radius))
                    layer.stroke(iris, with: .color(.black.opacity(0.35)), lineWidth: max(0.8, radius * 0.1))
                    layer.fill(Path(ellipseIn: CGRect(center: center, radius: radius * 0.44)), with: .color(Color(white: 0.06)))
                    layer.fill(Path(ellipseIn: CGRect(center: CGPoint(x: center.x + radius * 0.34, y: center.y - radius * 0.34), radius: radius * 0.2)), with: .color(.white.opacity(0.95)))
                    layer.fill(Path(ellipseIn: CGRect(center: CGPoint(x: center.x - radius * 0.3, y: center.y + radius * 0.36), radius: radius * 0.09)), with: .color(.white.opacity(0.6)))
                    // The upper lid's shadow gives the eyeball depth.
                    layer.fill(opening, with: .linearGradient(Gradient(colors: [.black.opacity(0.22), .clear]), startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.midY)))
                }
            }

            context.stroke(Path(eye.upperLid), with: .color(.primary), style: line)
            context.stroke(Path(eye.lowerLid), with: .color(.primary), style: line)
            if eye.lashOpacity > 0 {
                context.stroke(Path(eye.lashes), with: .color(.primary.opacity(eye.lashOpacity)), style: line)
            }
        }
    }
}
