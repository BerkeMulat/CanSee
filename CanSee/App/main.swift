//
//  main.swift
//  CanSee
//
//  AppKit entry point. A menu bar app needs no SwiftUI scenes, and skipping them keeps launch and
//  memory lean; SwiftUI is only loaded into the panel when it is first opened.
//

import AppKit

MainActor.assumeIsolated {
    let delegate = AppDelegate()
    // Menu bar only: no Dock icon, no Command-Tab entry. Info.plist says so too (LSUIElement);
    // setting it here keeps it true even if the key goes missing from a build.
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApplication.shared.delegate = delegate
    NSApplication.shared.run()
}
