//
//  Preferences.swift
//  CanSee
//
//  User settings, persisted in UserDefaults.
//

import Foundation
import Observation

enum DurationUnit: String, CaseIterable, Identifiable {
    case minutes, hours, days

    var id: Self { self }

    var title: String {
        switch self {
        case .minutes: "Dakika"
        case .hours: "Saat"
        case .days: "Gün"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .minutes: 60
        case .hours: 3_600
        case .days: 86_400
        }
    }

    /// Each range tops out near `AwakeManager.maximumDuration` (one year).
    var range: ClosedRange<Int> {
        switch self {
        case .minutes: 1...1_440
        case .hours: 1...720
        case .days: 1...365
        }
    }
}

@Observable
final class Preferences {
    static let batteryThresholds = [5, 10, 15, 20, 30]

    /// End the session when the battery drops to `batteryThreshold` while unplugged.
    var batteryGuard: Bool { didSet { defaults.set(batteryGuard, forKey: Key.batteryGuard) } }
    var batteryThreshold: Int { didSet { defaults.set(batteryThreshold, forKey: Key.batteryThreshold) } }
    /// End the session when macOS reports a critical thermal state.
    var thermalGuard: Bool { didSet { defaults.set(thermalGuard, forKey: Key.thermalGuard) } }
    /// Turn macOS Low Power Mode on for the length of each session.
    var batterySaver: Bool { didSet { defaults.set(batterySaver, forKey: Key.batterySaver) } }
    /// Keep the display from idling off during sessions, so the screen doesn't lock with the lid open.
    var preventsLock: Bool { didSet { defaults.set(preventsLock, forKey: Key.preventsLock) } }
    var showsTimeInMenuBar: Bool { didSet { defaults.set(showsTimeInMenuBar, forKey: Key.showsTimeInMenuBar) } }
    var animatesEye: Bool { didSet { defaults.set(animatesEye, forKey: Key.animatesEye) } }
    var customAmount: Int { didSet { defaults.set(customAmount, forKey: Key.customAmount) } }
    var customUnit: DurationUnit { didSet { defaults.set(customUnit.rawValue, forKey: Key.customUnit) } }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.batteryGuard: true,
            Key.batteryThreshold: 10,
            Key.thermalGuard: true,
            Key.batterySaver: false,
            Key.preventsLock: false,
            Key.showsTimeInMenuBar: false,
            Key.animatesEye: true,
            Key.customAmount: 2,
            Key.customUnit: DurationUnit.hours.rawValue,
        ])
        batteryGuard = defaults.bool(forKey: Key.batteryGuard)
        batteryThreshold = defaults.integer(forKey: Key.batteryThreshold)
        thermalGuard = defaults.bool(forKey: Key.thermalGuard)
        batterySaver = defaults.bool(forKey: Key.batterySaver)
        preventsLock = defaults.bool(forKey: Key.preventsLock)
        showsTimeInMenuBar = defaults.bool(forKey: Key.showsTimeInMenuBar)
        animatesEye = defaults.bool(forKey: Key.animatesEye)
        let unit = DurationUnit(rawValue: defaults.string(forKey: Key.customUnit) ?? "") ?? .hours
        customUnit = unit
        customAmount = min(max(defaults.integer(forKey: Key.customAmount), unit.range.lowerBound), unit.range.upperBound)
    }

    private enum Key {
        static let batteryGuard = "batteryGuard"
        static let batteryThreshold = "batteryThreshold"
        static let thermalGuard = "thermalGuard"
        static let batterySaver = "batterySaver"
        static let preventsLock = "preventsLock"
        static let showsTimeInMenuBar = "showsTimeInMenuBar"
        static let animatesEye = "animatesEye"
        static let customAmount = "customAmount"
        static let customUnit = "customUnit"
    }
}
