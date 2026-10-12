//
//  SetupView.swift
//  CanSee
//
//  The panel while idle: quick presets and a custom duration in minutes, hours or days.
//

import SwiftUI

struct SetupView: View {
    let manager: AwakeManager
    @Bindable var preferences: Preferences
    let isVisible: Bool

    @State private var amountText = ""

    var body: some View {
        // End times in the tiles move with the clock, but only while the panel is open.
        if isVisible {
            TimelineView(.everyMinute) { context in
                content(now: context.date)
            }
        } else {
            content(now: .now)
        }
    }

    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if manager.isSleepDisabledElsewhere {
                SleepDisabledCard(isBusy: manager.isBusy) {
                    Task { await manager.reenableSleep() }
                }
            } else if let lastEnd = manager.lastEnd, lastEnd.reason != .stopped, lastEnd.date.timeIntervalSince(now) > -12 * 3_600 {
                LastEndRow(lastEnd: lastEnd)
            }

            SessionOptions(manager: manager, preferences: preferences)

            SectionLabel("Hızlı başlat")
                .padding(.top, 4)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(DurationPreset.quickStarts) { preset in
                    PresetTile(preset: preset, end: now.addingTimeInterval(preset.seconds)) {
                        Task { await manager.start(duration: preset.seconds) }
                    }
                    .disabled(manager.isBusy)
                }
            }

            SectionLabel("Özel süre")
                .padding(.top, 6)
            customRow

            VStack(spacing: 6) {
                Button(action: startCustom) {
                    HStack(spacing: 8) {
                        if manager.isBusy {
                            ProgressView().controlSize(.small)
                        }
                        Text("Başlat")
                        Text(Format.duration(customSeconds))
                            .font(.system(size: 12, weight: .medium))
                            .opacity(0.85)
                    }
                }
                .buttonStyle(ProminentButtonStyle(colors: Theme.start))
                .keyboardShortcut(.defaultAction)
                .disabled(manager.isBusy)

                Text("Bitiş: \(Format.endTime(now.addingTimeInterval(customSeconds)))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            if manager.hasLid {
                VStack(alignment: .leading, spacing: 4) {
                    if manager.ruleStatus == .missing {
                        Label("İlk başlatmada, kapak kapalı modu için bir kez yönetici şifresi sorulur.", systemImage: "lock")
                    } else if manager.ruleStatus == .sleepOnly && preferences.batterySaver {
                        Label("Pil tasarrufu için bir kez yönetici şifresi sorulacak.", systemImage: "lock")
                    }
                    Label("Kapak kapalıyken Mac'i çantaya koymayın; hava alması gerekir.", systemImage: "wind")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var customRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                // Text-backed so a typed value counts even if Başlat is clicked without pressing Return.
                TextField("Süre", text: $amountText)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 46)
                    .onSubmit(startCustom)
                    .accessibilityLabel("Süre")
                Stepper("Süre", value: $preferences.customAmount, in: preferences.customUnit.range)
                    .labelsHidden()
                    .controlSize(.small)
            }
            .padding(.leading, 4)
            .padding(.trailing, 2)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.fill.tertiary))

            Picker("Birim", selection: $preferences.customUnit) {
                ForEach(DurationUnit.allCases) { unit in
                    Text(unit.title).tag(unit)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .onAppear { amountText = String(preferences.customAmount) }
        .onChange(of: amountText) { _, text in
            let digits = text.filter(\.isASCII).filter(\.isNumber)
            if digits != text { amountText = digits }
            if let value = Int(digits), value > 0 {
                preferences.customAmount = min(value, preferences.customUnit.range.upperBound)
            }
        }
        .onChange(of: preferences.customAmount) { _, value in
            if Int(amountText) != value { amountText = String(value) }
        }
        .onChange(of: preferences.customUnit) { _, unit in
            preferences.customAmount = min(max(preferences.customAmount, unit.range.lowerBound), unit.range.upperBound)
        }
    }

    private var customSeconds: TimeInterval {
        let range = preferences.customUnit.range
        return TimeInterval(min(max(preferences.customAmount, range.lowerBound), range.upperBound)) * preferences.customUnit.seconds
    }

    private func startCustom() {
        let seconds = customSeconds
        Task { await manager.start(duration: seconds) }
    }
}

private struct PresetTile: View {
    let preset: DurationPreset
    let end: Date
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(preset.value)")
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                    Text(preset.shortUnit)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Text("→ \(Format.shortEndTime(end))")
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isHovered ? AnyShapeStyle(Theme.accent.opacity(0.16)) : AnyShapeStyle(.fill.quaternary))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isHovered ? AnyShapeStyle(Theme.accent.opacity(0.55)) : AnyShapeStyle(.separator), lineWidth: isHovered ? 1 : 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
        .help("\(preset.title) uyanık tut · bitiş \(Format.endTime(end))")
        .accessibilityLabel("\(preset.title) başlat")
    }
}

private struct SleepDisabledCard: View {
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 17))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Uyku sistem genelinde kapalı")
                    .font(.system(size: 12, weight: .semibold))
                Text("Başka bir uygulama ya da eski bir oturum kapatmış. Kapak kapansa da Mac uyumayacak.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Uykuyu aç", action: action)
                    .controlSize(.small)
                    .padding(.top, 4)
                    .disabled(isBusy)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange.opacity(0.1)))
    }
}

private struct LastEndRow: View {
    let lastEnd: AwakeManager.LastEnd

    var body: some View {
        Label("Son oturum: \(lastEnd.reason.summary.lowercased(with: Locale(identifier: "tr_TR"))) · \(Format.endTime(lastEnd.date))", systemImage: icon)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
    }

    private var icon: String {
        switch lastEnd.reason {
        case .lowBattery: "battery.25percent"
        case .overheated: "thermometer.high"
        case .finished, .stopped: "checkmark.circle"
        }
    }
}
