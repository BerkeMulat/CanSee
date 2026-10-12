//
//  AppDelegate.swift
//  CanSee
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences()
    private let power = PowerMonitor()
    private lazy var manager = AwakeManager(preferences: preferences, power: power)
    private var statusItem: StatusItemController?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Two copies would fight over the same system-wide setting. The newest one wins, so an
        // updated or freshly built copy takes over; quitting lets the old one restore sleep first.
        let identifier = Bundle.main.bundleIdentifier ?? ""
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .filter { $0.processIdentifier != getpid() }
        guard !others.isEmpty else { return finishLaunching() }

        others.forEach { $0.terminate() }
        Task {
            for _ in 0..<30 where others.contains(where: { !$0.isTerminated }) {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if others.allSatisfy(\.isTerminated) {
                finishLaunching()
            } else {
                NSApp.terminate(nil)
            }
        }
    }

    private func finishLaunching() {
        // With no windows, a menu bar app would otherwise qualify for automatic termination.
        ProcessInfo.processInfo.disableAutomaticTermination("CanSee menü çubuğunda çalışıyor")
        terminateGracefullyOnSignals()
        statusItem = StatusItemController(manager: manager, preferences: preferences, power: power)
        LoginItem.enableOnFirstInstalledLaunch()
        Task { await manager.bootstrap() }
    }

    /// Opening the app again from Finder or Spotlight shows the panel instead of doing nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem?.showPanel()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard statusItem != nil else { return }
        manager.endForTermination()
    }

    /// `killall CanSee` or a command-line `shutdown` sends SIGTERM, which would otherwise end the
    /// process on the spot and leave sleep disabled until the watchdog's deadline.
    private func terminateGracefullyOnSignals() {
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated { NSApp.terminate(nil) }
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
