//
//  SessionOptions.swift
//  CanSee
//
//  The per-session options, battery saver and no lock screen, shared by the idle and active panels.
//

import AppKit
import SwiftUI

struct SessionOptions: View {
    let manager: AwakeManager
    let preferences: Preferences

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                OptionTile(icon: "leaf.fill", title: "Pil tasarrufu", subtitle: "Düşük Güç Modu",
                           tint: .green, isOn: preferences.batterySaver) {
                    let enabled = !preferences.batterySaver
                    Task { await manager.setBatterySaver(enabled) }
                }
                .help("Oturum boyunca macOS Düşük Güç Modu açılır: daha az ısı, daha uzun pil. İşler biraz yavaşlayabilir.")

                OptionTile(icon: "lock.open.fill", title: "Kilitlenmesin", subtitle: "Ekran kararmaz",
                           tint: Theme.accent, isOn: preferences.preventsLock) {
                    manager.setPreventsLock(!preferences.preventsLock)
                }
                .help("Oturum boyunca ekran kendiliğinden kararmaz; ekran koruyucu ve kilit devreye girmez.")
            }
            .disabled(manager.isBusy)

            if preferences.preventsLock && manager.hasLid {
                LockNote(delay: manager.lockDelay)
            }
        }
    }
}

/// What macOS still does once the lid closes, and a shortcut to the one setting that decides it.
struct LockNote: View {
    let delay: LockDelay?

    static func openLockScreenSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    var body: some View {
        switch delay {
        case .off?:
            Label("Kapak kapalıyken de kilitlenmez.", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .immediate?:
            note("Kapak kapanınca macOS ekranı hemen kilitler.")
        case .seconds(let seconds)?:
            note("Kapak kapalıyken macOS \(Format.shortDuration(seconds: seconds)) sonra yine kilitler.")
        case .unknown?, nil:
            note("Kapak kapalıyken kilidi macOS'un parola ayarı belirler.")
        }
    }

    private func note(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text("\(text) Bunu yalnızca “Parola iste: Asla” ayarı önler.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Kilit ekranı ayarını aç") { Self.openLockScreenSettings() }
                    .buttonStyle(.link)
            }
        }
        .font(.system(size: 11))
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.fill.quaternary))
    }
}
