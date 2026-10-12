//
//  PowerMonitor.swift
//  CanSee
//
//  Battery, thermal and Low Power Mode state, pushed by the system rather than polled.
//

import Foundation
import IOKit.ps
import Observation
import notify

@Observable
final class PowerMonitor {
    struct Battery: Equatable {
        var percent: Int
        var isPluggedIn: Bool
        var isCharging: Bool
    }

    /// Nil on Macs without a battery.
    private(set) var battery: Battery? = PowerMonitor.readBattery()
    private(set) var thermalState = ProcessInfo.processInfo.thermalState
    private(set) var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    /// Called after every update; the session uses it to enforce its guards.
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private var clients: Set<String> = []
    @ObservationIgnored private var notifyTokens: [Int32] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// Subscriptions exist only while someone needs them (a running session, the open panel).
    func setNeeded(_ needed: Bool, by client: String) {
        if needed { clients.insert(client) } else { clients.remove(client) }
        clients.isEmpty ? stopObserving() : startObserving()
    }

    func refresh() {
        let battery = Self.readBattery()
        if battery != self.battery { self.battery = battery }
        let thermal = ProcessInfo.processInfo.thermalState
        if thermal != thermalState { thermalState = thermal }
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        if lowPower != isLowPowerMode { isLowPowerMode = lowPower }
        onChange?()
    }

    static func readBattery() -> Battery? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  description[kIOPSIsPresentKey] as? Bool ?? true
            else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = description[kIOPSMaxCapacityKey] as? Int ?? 100
            return Battery(
                percent: maximum > 0 ? Int((Double(current) / Double(maximum) * 100).rounded()) : current,
                isPluggedIn: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false
            )
        }
        return nil
    }

    // MARK: - Private

    private func startObserving() {
        guard notifyTokens.isEmpty, observers.isEmpty else { return }
        refresh()

        // Fires when the percentage or time estimate changes, or the Mac is (un)plugged.
        for name in [kIOPSNotifyTimeRemaining, kIOPSNotifyPowerSource] {
            var token: Int32 = 0
            let status = notify_register_dispatch(name, &token, .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            if status == 0 { notifyTokens.append(token) }
        }

        let center = NotificationCenter.default
        for name in [ProcessInfo.thermalStateDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    private func stopObserving() {
        notifyTokens.forEach { notify_cancel($0) }
        notifyTokens.removeAll()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }
}
