//
//  SystemServices.swift
//  CanSee
//
//  Thin wrappers over login items and user notifications.
//

import Foundation
import ServiceManagement
import UserNotifications

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// A login item needs a stable path; a translocated (downloaded, never moved) copy or a build
    /// folder would register a location that later disappears.
    static var isInstalledLocation: Bool {
        let path = Bundle.main.bundleURL.path
        guard !path.contains("/AppTranslocation/") else { return false }
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    static var isTranslocated: Bool { Bundle.main.bundleURL.path.contains("/AppTranslocation/") }

    /// Turned on once for an installed copy: after a crash or power loss, launching at login is
    /// what lets CanSee notice a stale session and put the sleep setting back.
    static func enableOnFirstInstalledLaunch() {
        let key = "didEnableLoginItemOnce"
        guard isInstalledLocation, !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        try? setEnabled(true)
    }
}

enum Notifier {
    /// Provisional authorization delivers quietly to Notification Center, without a prompt.
    static func post(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .provisional]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: "session-ended", content: content, trigger: nil))
        }
    }
}
