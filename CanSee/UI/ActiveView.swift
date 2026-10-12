//
//  ActiveView.swift
//  CanSee
//
//  The panel while a session runs: countdown ring, extend, stop and live status.
//

import SwiftUI

struct ActiveView: View {
    let session: AwakeManager.Session
    let manager: AwakeManager
    let power: PowerMonitor
    let preferences: Preferences
    let isVisible: Bool

    var body: some View {
        VStack(spacing: 14) {
            Group {
                if isVisible {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        CountdownRing(session: session, now: context.date)
                    }
                } else {
                    CountdownRing(session: session, now: .now)
                }
            }
            .padding(.top, 2)

            Text("Bitiş: \(Format.endTime(session.end))")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(DurationPreset.extensions) { option in
                    Button {
                        manager.extend(by: option.seconds)
                    } label: {
                        Text("+\(option.value) \(option.shortUnit)")
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    }
                    .buttonStyle(SoftButtonStyle())
                    .help("\(option.title) uzat")
                }
            }

            SessionOptions(manager: manager, preferences: preferences)

            if session.mode == .lidOpenOnly && manager.hasLid {
                LidOpenOnlyCard(isBusy: manager.isBusy) {
                    Task { await manager.enableClosedLidMode() }
                }
            }

            StatusChips(session: session, power: power, preferences: preferences, hasLid: manager.hasLid)

            Button(role: .destructive) {
                Task { await manager.stop() }
            } label: {
                Label("Durdur", systemImage: "stop.fill")
            }
            .buttonStyle(ProminentButtonStyle(colors: Theme.stop))
            .disabled(manager.isBusy)
        }
    }
}

private struct CountdownRing: View {
    let session: AwakeManager.Session
    let now: Date

    var body: some View {
        let remaining = max(0, session.end.timeIntervalSince(now))
        let progress = session.duration > 0 ? min(1, remaining / session.duration) : 0

        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 10)
            arc(progress)
                .blur(radius: 8)
                .opacity(0.5)
            arc(progress)
            VStack(spacing: 2) {
                Text(Format.countdown(remaining))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy(duration: 0.35), value: Int(remaining))
                Text("KALAN")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 168, height: 168)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kalan süre: \(Format.duration(remaining))")
    }

    /// The gradient spans only the remaining arc, so its bright head always marks "now".
    private func arc(_ progress: Double) -> some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(
                AngularGradient(colors: Theme.aurora, center: .center, startAngle: .zero, endAngle: .degrees(360 * max(progress, 0.01))),
                style: StrokeStyle(lineWidth: 10, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
    }
}

private struct StatusChips: View {
    let session: AwakeManager.Session
    let power: PowerMonitor
    let preferences: Preferences
    let hasLid: Bool

    var body: some View {
        HStack(spacing: 6) {
            if hasLid {
                if session.mode == .systemWide {
                    Chip(icon: "laptopcomputer", text: "Kapak kapanabilir", tint: .green)
                } else {
                    Chip(icon: "exclamationmark.triangle.fill", text: "Kapağı kapatmayın", tint: .orange)
                }
            }
            if let battery = power.battery {
                Chip(icon: batteryIcon(battery), text: "%\(battery.percent)", tint: batteryTint(battery))
            }
            switch power.thermalState {
            case .serious: Chip(icon: "thermometer.high", text: "Sıcak", tint: .orange)
            case .critical: Chip(icon: "thermometer.high", text: "Çok sıcak", tint: .red)
            default: EmptyView()
            }
            if power.isLowPowerMode {
                Chip(icon: "leaf.fill", text: "Düşük güç", tint: .yellow)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func batteryIcon(_ battery: PowerMonitor.Battery) -> String {
        if battery.isPluggedIn { return "battery.100percent.bolt" }
        switch battery.percent {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    private func batteryTint(_ battery: PowerMonitor.Battery) -> Color? {
        guard !battery.isPluggedIn else { return .green }
        return battery.percent <= preferences.batteryThreshold + 10 ? .orange : nil
    }
}

private struct LidOpenOnlyCard: View {
    let isBusy: Bool
    let enable: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 18))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Kapak kapalı modu kapalı")
                    .font(.system(size: 12, weight: .semibold))
                Text("Kapağı kapatırsanız Mac uyur. Bir kez izin verin, kapalıyken de çalışsın.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("İzin ver", action: enable)
                .controlSize(.small)
                .disabled(isBusy)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange.opacity(0.1)))
    }
}
