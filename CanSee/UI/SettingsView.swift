//
//  SettingsView.swift
//  CanSee
//

import SwiftUI

struct SettingsView: View {
    let manager: AwakeManager
    @Bindable var preferences: Preferences

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?

    var body: some View {
        // Scrolls rather than growing the panel past a small laptop screen.
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                sessionGroup
                protectionGroup
                menuBarGroup
                systemGroup
            }
            .padding(.bottom, 4)
        }
        .frame(height: 500)
        .toggleStyle(.switch)
        .controlSize(.small)
        .task { await manager.refreshLockDelay() }
        .onChange(of: launchAtLogin) { _, enabled in
            guard enabled != LoginItem.isEnabled else { return }
            do {
                try LoginItem.setEnabled(enabled)
                loginItemError = nil
            } catch {
                loginItemError = error.localizedDescription
                launchAtLogin = LoginItem.isEnabled
            }
        }
        .onChange(of: preferences.batteryGuard) { manager.enforceGuards() }
        .onChange(of: preferences.batteryThreshold) { manager.enforceGuards() }
        .onChange(of: preferences.thermalGuard) { manager.enforceGuards() }
    }

    private var sessionGroup: some View {
        SettingsGroup("Oturum") {
            SettingRow(icon: "leaf.fill", title: "Pil tasarrufu",
                       detail: "Oturum boyunca macOS Düşük Güç Modu açık kalır: daha az ısı, daha uzun pil.") {
                Toggle("Pil tasarrufu", isOn: Binding(
                    get: { preferences.batterySaver },
                    set: { enabled in Task { await manager.setBatterySaver(enabled) } }
                ))
            }
            RowDivider()
            SettingRow(icon: "lock.open.fill", title: "Kilitlenmesin",
                       detail: "Kapak açıkken ekran kararmaz, ekran koruyucu ve kilit devreye girmez.") {
                Toggle("Kilitlenmesin", isOn: Binding(
                    get: { preferences.preventsLock },
                    set: { manager.setPreventsLock($0) }
                ))
            }
            if manager.hasLid {
                RowDivider()
                SettingRow(icon: "laptopcomputer", title: "Kapak kapalıyken kilit", detail: closedLidLockDetail) {
                    Button("Ayarla") { LockNote.openLockScreenSettings() }
                }
            }
        }
    }

    private var protectionGroup: some View {
        SettingsGroup("Koruma") {
            SettingRow(icon: "battery.25percent", title: "Pil koruması",
                       detail: "Şarjda değilken pil %\(preferences.batteryThreshold) ve altına inerse oturumu bitirir.") {
                Toggle("Pil koruması", isOn: $preferences.batteryGuard)
            }
            if preferences.batteryGuard {
                Picker("Eşik", selection: $preferences.batteryThreshold) {
                    ForEach(Preferences.batteryThresholds, id: \.self) { value in
                        Text("%\(value)").tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.leading, 34)
            }
            RowDivider()
            SettingRow(icon: "thermometer.medium", title: "Isı koruması",
                       detail: "Mac kritik sıcaklığa ulaşırsa oturumu bitirir.") {
                Toggle("Isı koruması", isOn: $preferences.thermalGuard)
            }
        }
    }

    private var menuBarGroup: some View {
        SettingsGroup("Menü çubuğu") {
            SettingRow(icon: "timer", title: "Kalan süreyi göster", detail: nil) {
                Toggle("Kalan süreyi göster", isOn: $preferences.showsTimeInMenuBar)
            }
            RowDivider()
            SettingRow(icon: "eye", title: "Göz animasyonları",
                       detail: "Ara sıra göz kırpar; ekran kapalıyken hiç çalışmaz.") {
                Toggle("Göz animasyonları", isOn: $preferences.animatesEye)
            }
        }
    }

    private var systemGroup: some View {
        SettingsGroup("Sistem") {
            SettingRow(icon: "power", title: "Girişte başlat", detail: loginItemDetail) {
                Toggle("Girişte başlat", isOn: $launchAtLogin)
            }
            if manager.hasLid {
                RowDivider()
                SettingRow(icon: "lock.shield", title: "Yönetici izni", detail: permissionDetail) {
                    switch manager.ruleStatus {
                    case .full?:
                        Button("Kaldır") { Task { await manager.removeRule() } }
                            .disabled(manager.isActive || manager.isBusy)
                            .help(manager.isActive ? "Önce oturumu durdurun" : "Şifresiz pmset iznini kaldırır")
                    case .sleepOnly?:
                        Button("Güncelle") { Task { await manager.installRule() } }
                            .disabled(manager.isBusy)
                    case .missing?, nil:
                        Button("Kur") { Task { await manager.installRule() } }
                            .disabled(manager.isBusy || manager.ruleStatus == nil)
                    }
                }
            }
        }
    }

    private var closedLidLockDetail: String {
        switch manager.lockDelay {
        case .off?: "Kilitlenmez."
        case .immediate?: "macOS kapak kapanınca hemen kilitler; “Asla” için ayarı değiştirin."
        case .seconds(let seconds)?: "macOS \(Format.shortDuration(seconds: seconds)) sonra kilitler; “Asla” için ayarı değiştirin."
        case .unknown?, nil: "macOS'un “Parola iste” ayarına bağlıdır."
        }
    }

    private var loginItemDetail: String {
        if let loginItemError { return loginItemError }
        if LoginItem.needsApproval { return "Sistem Ayarları › Genel › Giriş Öğeleri'nden onay verin." }
        if LoginItem.isTranslocated { return "Önce CanSee'yi Uygulamalar klasörüne taşıyın." }
        return "Yeniden başlatmadan sonra uyku ayarını düzeltir."
    }

    private var permissionDetail: String {
        switch manager.ruleStatus {
        case .full?: "Kurulu. Yalnızca uyku ve Düşük Güç Modu ayarlarına şifresiz izin verir."
        case .sleepOnly?: "Eski sürüm. Pil tasarrufu için bir kez güncellenmeli."
        case .missing?: "Kurulu değil. İlk başlatmada bir kez yönetici şifresi sorulur."
        case nil: "Denetleniyor…"
        }
    }
}
