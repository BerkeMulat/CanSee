//
//  StatusItemController.swift
//  CanSee
//
//  The menu bar item: the animated eye, the optional remaining time, the panel on click and a
//  quick menu on right-click.
//

import AppKit
import Observation
import SwiftUI

final class StatusItemController: NSObject, NSPopoverDelegate {
    private let item: NSStatusItem
    private let popover = NSPopover()
    private let panel = PanelState()
    private let manager: AwakeManager
    private let preferences: Preferences
    private let power: PowerMonitor
    private let eye: StatusEyeAnimator
    private var titleTimer: Timer?
    private var releaseTimer: Timer?
    private var screensAsleep = false
    private var lastPopoverClose: CFTimeInterval = 0
    private var observers: [NSObjectProtocol] = []

    init(manager: AwakeManager, preferences: Preferences, power: PowerMonitor) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.item = item
        self.manager = manager
        self.preferences = preferences
        self.power = power
        eye = StatusEyeAnimator(button: item.button)
        super.init()

        if let button = item.button {
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.setAccessibilityLabel("CanSee")
        }
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        observeSystem()
        apply(animated: false)
        observeState()
        visibilityChanged()
    }

    func showPanel(page: PanelState.Page = .main) {
        panel.page = page
        guard !popover.isShown, let button = item.button else { return }
        releaseTimer?.invalidate()
        releaseTimer = nil
        if popover.contentViewController == nil {
            // Built on first open, so a session that never opens the panel never loads SwiftUI views.
            let host = NSHostingController(rootView: PanelView(manager: manager, preferences: preferences, power: power, panel: panel))
            host.sizingOptions = .preferredContentSize
            popover.contentViewController = host
        }
        manager.refreshSystemState()
        if preferences.preventsLock {
            Task { await manager.refreshLockDelay() }
        }
        power.setNeeded(true, by: "panel")
        panel.isVisible = true
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.highlight(true)
        eye.isLookingDown = true
    }

    func popoverDidClose(_ notification: Notification) {
        lastPopoverClose = CACurrentMediaTime()
        item.button?.highlight(false)
        panel.isVisible = false
        panel.page = .main
        power.setNeeded(false, by: "panel")
        eye.isLookingDown = false

        // Drop the SwiftUI view graph a little after closing; reopening right away stays instant.
        let timer = Timer(timeInterval: 20, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.popover.isShown else { return }
                self.popover.contentViewController = nil
            }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        releaseTimer = timer
    }

    // MARK: - Clicks

    @objc private func handleClick() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showQuickMenu()
        } else if popover.isShown {
            popover.performClose(nil)
        } else if CACurrentMediaTime() - lastPopoverClose > 0.3 {
            // The click that just closed the transient popover lands here too; don't reopen it.
            showPanel()
        }
    }

    private func showQuickMenu() {
        if popover.isShown { popover.performClose(nil) }

        let menu = NSMenu()
        if let session = manager.session {
            menu.addItem(.sectionHeader(title: "Kalan: \(Format.duration(session.end.timeIntervalSinceNow))"))
            for option in DurationPreset.extensions {
                menu.addItem(ActionMenuItem(title: "+\(option.title) uzat") { [weak self] in
                    self?.manager.extend(by: option.seconds)
                })
            }
            menu.addItem(.separator())
            menu.addItem(ActionMenuItem(title: "Durdur") { [weak self] in
                Task { await self?.manager.stop() }
            })
        } else {
            menu.addItem(.sectionHeader(title: "Uyanık tut"))
            for preset in DurationPreset.quickStarts {
                menu.addItem(ActionMenuItem(title: preset.title) { [weak self] in
                    Task { await self?.manager.start(duration: preset.seconds) }
                })
            }
        }
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: "Ayarlar…") { [weak self] in self?.showPanel(page: .settings) })
        menu.addItem(ActionMenuItem(title: manager.isActive ? "Durdur ve Çık" : "Çık", keyEquivalent: "q") {
            NSApp.terminate(nil)
        })

        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    // MARK: - State

    private func observeState() {
        withObservationTracking {
            _ = manager.session
            _ = preferences.showsTimeInMenuBar
            _ = preferences.animatesEye
        } onChange: { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.apply(animated: true)
                self.observeState()
            }
        }
    }

    private func apply(animated: Bool) {
        eye.allowsMotion = preferences.animatesEye
        eye.setAwake(manager.isActive, animated: animated)
        updateTitle()
        updateToolTip()
    }

    private func updateToolTip() {
        guard let button = item.button else { return }
        if let session = manager.session {
            let mode = session.mode == .systemWide ? "kapak kapalıyken de uyanık" : "yalnızca kapak açıkken uyanık"
            button.toolTip = "CanSee: \(mode) · bitiş \(Format.endTime(session.end))"
            button.setAccessibilityValue("Uyanık, bitiş \(Format.endTime(session.end))")
        } else {
            button.toolTip = "CanSee: uyku normal"
            button.setAccessibilityValue("Uyku normal")
        }
    }

    /// The optional remaining time. It is redrawn only when the shown minute changes, and not at
    /// all while nobody can see the menu bar.
    private func updateTitle() {
        titleTimer?.invalidate()
        titleTimer = nil
        guard let button = item.button else { return }
        guard preferences.showsTimeInMenuBar, let session = manager.session else {
            if !button.title.isEmpty { button.title = "" }
            return
        }

        let remaining = max(0, session.end.timeIntervalSinceNow)
        button.attributedTitle = NSAttributedString(
            string: Format.menuBarRemaining(remaining),
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)]
        )
        guard isIconVisible else { return }

        let intoMinute = remaining.truncatingRemainder(dividingBy: 60)
        let delay = (intoMinute < 0.5 ? intoMinute + 60 : intoMinute) + 0.05
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateTitle() }
        }
        timer.tolerance = min(3, delay * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        titleTimer = timer
    }

    // MARK: - Visibility

    private var isIconVisible: Bool {
        guard !screensAsleep, let window = item.button?.window else { return false }
        return window.occlusionState.contains(.visible)
    }

    private func visibilityChanged() {
        eye.isVisible = isIconVisible
        updateTitle()
    }

    private func observeSystem() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let window = note.object as? NSWindow, window === self.item.button?.window else { return }
                self.visibilityChanged()
            }
        })
        observers.append(center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateToolTip() }
        })

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screensAsleep = true
                self?.visibilityChanged()
            }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screensAsleep = false
                self?.visibilityChanged()
            }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.eye.refreshMotion() }
        })
    }
}

private final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, keyEquivalent: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func fire() {
        handler()
    }
}
