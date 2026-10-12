//
//  StatusEye.swift
//  CanSee
//
//  The animated template eye shown in the menu bar.
//

import AppKit
import QuartzCore

/// Monochrome (template) eye, so the menu bar tints it exactly like the system's own icons.
enum StatusEyeIcon {
    static let size = NSSize(width: 22, height: 16)

    static func image(openness: CGFloat, look: CGPoint) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: context, rect: rect, openness: openness, look: look)
            return true
        }
        image.isTemplate = true
        return image
    }

    nonisolated static func draw(in context: CGContext, rect: CGRect, openness: CGFloat, look: CGPoint, color: CGColor = .black) {
        let eye = EyeGeometry(in: rect.insetBy(dx: 1.5, dy: 0), openness: openness, look: look)
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(max(1.3, eye.unit * 0.15))

        if openness > 0.04 {
            context.saveGState()
            context.addPath(eye.opening)
            context.clip()
            context.fillEllipse(in: CGRect(center: eye.irisCenter, radius: eye.irisRadius))
            // A glint punched out of the iris keeps the eye alive even at 16 pt.
            let r = eye.irisRadius
            context.setBlendMode(.clear)
            context.fillEllipse(in: CGRect(center: CGPoint(x: eye.irisCenter.x + r * 0.36, y: eye.irisCenter.y + r * 0.36), radius: r * 0.30))
            context.restoreGState()
        }

        context.addPath(eye.upperLid)
        context.addPath(eye.lowerLid)
        context.strokePath()

        if eye.lashOpacity > 0 {
            context.setAlpha(eye.lashOpacity)
            context.addPath(eye.lashes)
            context.strokePath()
            context.setAlpha(1)
        }
    }
}

/// Drives the menu bar eye: it wakes up and falls asleep with the session, and blinks or glances
/// now and then while awake.
///
/// Frames are drawn only while an animation runs, on a display link capped at 60 Hz. Idle gestures
/// are one-shot timers with generous tolerance, and everything stops while the icon can't be seen
/// (display asleep, lid closed, menu bar hidden), so a long closed-lid session costs nothing here.
final class StatusEyeAnimator: NSObject {
    private weak var button: NSStatusBarButton?

    private var openness: CGFloat = 0
    private var look: CGPoint = .zero
    private var opennessTrack: Track?
    private var lookXTrack: Track?
    private var lookYTrack: Track?
    private var displayLink: CADisplayLink?
    private var idleTimer: Timer?

    private(set) var isAwake = false

    /// Whether the icon is actually on screen; set by the owner from occlusion and display sleep.
    var isVisible = true {
        didSet {
            guard isVisible != oldValue else { return }
            if !isVisible { finishAnimations() }
            scheduleIdleGesture()
        }
    }

    /// The user's "eye animations" preference.
    var allowsMotion = true {
        didSet {
            guard allowsMotion != oldValue else { return }
            if !allowsMotion { finishAnimations() }
            scheduleIdleGesture()
        }
    }

    /// Looks down toward the open panel.
    var isLookingDown = false {
        didSet {
            guard isLookingDown != oldValue else { return }
            animateLook(to: CGPoint(x: 0, y: isLookingDown ? -0.85 : 0), duration: isLookingDown ? 0.28 : 0.34)
        }
    }

    private var canAnimate: Bool {
        isVisible && allowsMotion && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    init(button: NSStatusBarButton?) {
        self.button = button
        super.init()
        render()
    }

    func setAwake(_ awake: Bool, animated: Bool) {
        guard awake != isAwake else { return }
        isAwake = awake

        if animated && canAnimate {
            opennessTrack = awake ? .wake(from: openness) : .sleep(from: openness)
            if !awake {
                lookXTrack = Track(from: look.x, keys: [(0.3, 0, .easeInOut)])
                lookYTrack = Track(from: look.y, keys: [(0.3, 0, .easeInOut)])
            }
            startDisplayLink()
        } else {
            openness = awake ? 1 : 0
            if !awake { look = .zero }
            opennessTrack = nil
            render()
        }
        scheduleIdleGesture()
    }

    /// Re-evaluates idle gestures after the system's Reduce Motion setting changes.
    func refreshMotion() {
        if !canAnimate { finishAnimations() }
        scheduleIdleGesture()
    }

    // MARK: - Idle gestures

    private func scheduleIdleGesture() {
        idleTimer?.invalidate()
        idleTimer = nil
        guard isAwake, canAnimate else { return }

        let delay = Double.random(in: 9...24)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.performIdleGesture() }
        }
        timer.tolerance = delay * 0.2
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    private func performIdleGesture() {
        defer { scheduleIdleGesture() }
        guard isAwake, canAnimate, opennessTrack == nil, lookXTrack == nil else { return }

        let roll = Double.random(in: 0..<1)
        if roll < 0.6 || isLookingDown {
            opennessTrack = .blink(double: roll < 0.12)
        } else {
            let side: CGFloat = Bool.random() ? 1 : -1
            lookXTrack = Track(from: look.x, keys: [(0.24, 0.85 * side, .easeInOut), (1.15, 0.85 * side, .linear), (1.42, 0, .easeInOut)])
            lookYTrack = Track(from: look.y, keys: [(0.24, 0.2, .easeInOut), (1.15, 0.2, .linear), (1.42, 0, .easeInOut)])
        }
        startDisplayLink()
    }

    private func animateLook(to target: CGPoint, duration: CFTimeInterval) {
        guard isAwake, canAnimate else {
            look = isAwake ? target : .zero
            render()
            return
        }
        lookXTrack = Track(from: look.x, keys: [(duration, target.x, .easeOut)])
        lookYTrack = Track(from: look.y, keys: [(duration, target.y, .easeOut)])
        startDisplayLink()
    }

    // MARK: - Frames

    private func startDisplayLink() {
        guard displayLink == nil, let button else { return }
        let link = button.displayLink(target: self, selector: #selector(tick(_:)))
        // A 16 pt icon gains nothing from 120 Hz; capping halves the work on ProMotion screens.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        var running = false

        if let track = opennessTrack {
            openness = track.value(at: now)
            if now >= track.end { opennessTrack = nil } else { running = true }
        }
        if let track = lookXTrack {
            look.x = track.value(at: now)
            if now >= track.end { lookXTrack = nil } else { running = true }
        }
        if let track = lookYTrack {
            look.y = track.value(at: now)
            if now >= track.end { lookYTrack = nil } else { running = true }
        }

        render()
        if !running {
            link.invalidate()
            displayLink = nil
        }
    }

    /// Jumps every running animation to its end state, e.g. when the icon disappears mid-blink.
    private func finishAnimations() {
        if let track = opennessTrack { openness = track.finalValue }
        if let track = lookXTrack { look.x = track.finalValue }
        if let track = lookYTrack { look.y = track.finalValue }
        opennessTrack = nil
        lookXTrack = nil
        lookYTrack = nil
        displayLink?.invalidate()
        displayLink = nil
        render()
    }

    private func render() {
        button?.image = StatusEyeIcon.image(openness: openness, look: look)
    }
}

// MARK: - Keyframes

private enum Curve {
    case linear, easeIn, easeOut, easeInOut

    func apply(_ x: CGFloat) -> CGFloat {
        switch self {
        case .linear: x
        case .easeIn: x * x * x
        case .easeOut: 1 - pow(1 - x, 3)
        case .easeInOut: x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
        }
    }
}

private struct Track {
    let start: CFTimeInterval
    let initial: CGFloat
    let keys: [(time: CFTimeInterval, value: CGFloat, curve: Curve)]

    init(from initial: CGFloat, keys: [(CFTimeInterval, CGFloat, Curve)]) {
        self.start = CACurrentMediaTime()
        self.initial = initial
        self.keys = keys.map { (time: $0.0, value: $0.1, curve: $0.2) }
    }

    var end: CFTimeInterval { start + (keys.last?.time ?? 0) }
    var finalValue: CGFloat { keys.last?.value ?? initial }

    func value(at now: CFTimeInterval) -> CGFloat {
        let elapsed = now - start
        var previousTime: CFTimeInterval = 0
        var previousValue = initial
        for key in keys {
            if elapsed < key.time {
                let progress = (elapsed - previousTime) / max(key.time - previousTime, 0.0001)
                return previousValue + (key.value - previousValue) * key.curve.apply(CGFloat(max(0, progress)))
            }
            previousTime = key.time
            previousValue = key.value
        }
        return finalValue
    }

    /// Half-opens, blinks once, then opens fully: waking up rather than switching on.
    static func wake(from openness: CGFloat) -> Track {
        Track(from: openness, keys: [(0.22, 0.55, .easeOut), (0.32, 0.55, .linear), (0.42, 0.1, .easeIn), (0.70, 1, .easeOut)])
    }

    static func sleep(from openness: CGFloat) -> Track {
        Track(from: openness, keys: [(0.18, 0.4, .easeInOut), (0.30, 0.45, .linear), (0.62, 0, .easeIn)])
    }

    static func blink(double: Bool) -> Track {
        double
            ? Track(from: 1, keys: [(0.07, 0, .easeIn), (0.17, 1, .easeOut), (0.25, 1, .linear), (0.32, 0, .easeIn), (0.46, 1, .easeOut)])
            : Track(from: 1, keys: [(0.075, 0, .easeIn), (0.21, 1, .easeOut)])
    }
}
