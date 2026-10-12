//
//  Format.swift
//  CanSee
//
//  Turkish formatting for durations and times, and the duration presets shared by panel and menu.
//

import Foundation

enum Format {
    private static let locale = Locale(identifier: "tr_TR")

    /// Panel countdown: "1:23:45", "05:09", or "2g 04:13" past a day.
    static func countdown(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval).rounded(.up))
        let days = total / 86_400
        let hours = total % 86_400 / 3_600
        let minutes = total % 3_600 / 60
        let seconds = total % 60
        if days > 0 { return "\(days)g \(twoDigits(hours)):\(twoDigits(minutes))" }
        if hours > 0 { return "\(hours):\(twoDigits(minutes)):\(twoDigits(seconds))" }
        return "\(twoDigits(minutes)):\(twoDigits(seconds))"
    }

    /// Menu bar title in whole minutes, rounded up: "2:13", or "1g 4sa" past a day.
    static func menuBarRemaining(_ interval: TimeInterval) -> String {
        let minutes = Int((max(0, interval) / 60).rounded(.up))
        if minutes >= 1_440 { return "\(minutes / 1_440)g \(minutes % 1_440 / 60)sa" }
        return "\(minutes / 60):\(twoDigits(minutes % 60))"
    }

    /// In words: "45 dakika", "2 saat 30 dakika", "1 gün 3 saat".
    static func duration(_ interval: TimeInterval) -> String {
        let minutes = Int((max(0, interval) / 60).rounded(.up))
        let days = minutes / 1_440
        let hours = minutes % 1_440 / 60
        let rest = minutes % 60
        var parts: [String] = []
        if days > 0 { parts.append("\(days) gün") }
        if hours > 0 { parts.append("\(hours) saat") }
        if rest > 0, days == 0 { parts.append("\(rest) dakika") }
        return parts.isEmpty ? "1 dakikadan az" : parts.joined(separator: " ")
    }

    /// Compact: "5 sn", "5 dk", "1 sa".
    static func shortDuration(seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) sn" }
        if seconds < 3_600 { return "\(seconds / 60) dk" }
        return "\(seconds / 3_600) sa"
    }

    static func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(locale))
    }

    /// "bugün 18:30", "yarın 03:45", "15 Eki Çar 03:45".
    static func endTime(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "bugün \(clock(date))" }
        if calendar.isDateInTomorrow(date) { return "yarın \(clock(date))" }
        return "\(date.formatted(.dateTime.day().month(.abbreviated).weekday(.abbreviated).locale(locale))) \(clock(date))"
    }

    /// Short enough for a preset tile: "18:30", "yarın 18:30" or "15 Eki".
    static func shortEndTime(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return clock(date) }
        if calendar.isDateInTomorrow(date) { return "yarın \(clock(date))" }
        return date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

struct DurationPreset: Identifiable {
    let value: Int
    let unit: DurationUnit

    var id: TimeInterval { seconds }
    var seconds: TimeInterval { TimeInterval(value) * unit.seconds }

    var shortUnit: String {
        switch unit {
        case .minutes: "dk"
        case .hours: "sa"
        case .days: "gün"
        }
    }

    /// "30 dakika", "1 saat", "1 gün".
    var title: String { "\(value) \(unit.title.lowercased(with: Locale(identifier: "tr_TR")))" }

    static let quickStarts = [
        DurationPreset(value: 30, unit: .minutes), DurationPreset(value: 1, unit: .hours),
        DurationPreset(value: 2, unit: .hours), DurationPreset(value: 4, unit: .hours),
        DurationPreset(value: 8, unit: .hours), DurationPreset(value: 1, unit: .days),
    ]

    static let extensions = [
        DurationPreset(value: 15, unit: .minutes), DurationPreset(value: 1, unit: .hours),
        DurationPreset(value: 4, unit: .hours),
    ]
}
