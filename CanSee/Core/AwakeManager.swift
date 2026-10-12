//
//  AwakeManager.swift
//  CanSee
//
//  Keeps the Mac awake (including with the lid closed) for a fixed duration, and makes sure every
//  system change comes back: on expiry, stop, quit, crash, low battery or overheating.
//

import AppKit
import Observation

enum EndReason {
    case finished, stopped, lowBattery, overheated

    var summary: String {
        switch self {
        case .finished: "Süre doldu"
        case .stopped: "Durduruldu"
        case .lowBattery: "Pil azaldığı için durdu"
        case .overheated: "Mac çok ısındığı için durdu"
        }
    }
}

@Observable
final class AwakeManager {
    struct Session: Equatable {
        var start: Date
        var end: Date
        var mode: AwakeMode
        var ownsSleepSetting: Bool
        /// The Low Power Mode values to put back; nil when CanSee didn't change them.
        var lowPowerRestore: LowPowerSettings?

        var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    struct Notice: Equatable {
        enum Kind { case info, warning, error }

        var kind: Kind
        var text: String
    }

    struct LastEnd: Equatable {
        var reason: EndReason
        var date: Date
    }

    static let maximumDuration: TimeInterval = 365 * 86_400

    private(set) var session: Session?
    private(set) var isBusy = false
    var notice: Notice?
    private(set) var lastEnd: LastEnd?
    /// The silent sudoers rule; nil until checked, and on Macs without a lid.
    private(set) var ruleStatus: RuleStatus?
    /// `disablesleep` is on although no CanSee session owns it (another tool, or a 1.0 leftover).
    private(set) var isSleepDisabledElsewhere = false
    /// macOS's own lock delay, which alone decides when a closed lid locks the screen.
    private(set) var lockDelay: LockDelay?

    let hasLid = PowerRegistry.hasLid
    var isActive: Bool { session != nil }

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let power: PowerMonitor
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var displayActivity: NSObjectProtocol?
    @ObservationIgnored private var expiryTimer: DispatchSourceTimer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// A stop that arrived while another operation (say, an admin prompt) was in flight.
    @ObservationIgnored private var pendingStop: EndReason?
    @ObservationIgnored private var lockDelayCheckedAt: Date?

    init(preferences: Preferences, power: PowerMonitor) {
        self.preferences = preferences
        self.power = power
    }

    // MARK: - Lifecycle

    /// Resumes a session that outlived the previous launch, or cleans up after one that expired.
    func bootstrap() async {
        observeSystemEvents()
        power.onChange = { [weak self] in self?.enforceGuards() }

        if let stored = SessionStore.load(), beginBusy() {
            if stored.end > .now {
                await resume(stored)
            } else {
                // Silent on purpose: this runs at launch, often with nobody at the Mac.
                if let restore = stored.lowPowerRestore {
                    _ = await SleepControl.applyLowPower(restore)
                }
                if stored.ownsSleepSetting && PowerRegistry.isSleepDisabled {
                    _ = await SleepControl.setSleepDisabled(false)
                }
                SessionStore.clear()
                lastEnd = LastEnd(reason: .finished, date: stored.end)
            }
            endBusy()
        }
        refreshSystemState()
        if hasLid {
            ruleStatus = await SleepControl.ruleStatus()
        }
    }

    /// Called from `applicationWillTerminate` (quit, logout, restart); must finish synchronously.
    func endForTermination() {
        guard let session else { return }
        expiryTimer?.cancel()
        if let restore = session.lowPowerRestore {
            SleepControl.applyLowPowerSync(restore)
        }
        if session.ownsSleepSetting {
            SleepControl.restoreSleepSync()
        }
        SessionStore.clear()
        endActivities()
    }

    // MARK: - Session control

    func start(duration: TimeInterval) async {
        guard !isActive else { return }
        if let reason = startBlocker() {
            notice = Notice(kind: .error, text: reason)
            return
        }
        guard beginBusy() else { return }
        defer { endBusy() }
        notice = nil

        var mode = AwakeMode.lidOpenOnly
        var owns = false
        if hasLid {
            if PowerRegistry.isSleepDisabled {
                // Already off system-wide by someone else: rely on it, but never be the one to undo it.
                mode = .systemWide
            } else if await SleepControl.setSleepDisabled(true) {
                mode = .systemWide
                owns = true
            } else {
                do {
                    try await SleepControl.installRule(applying: true)
                    ruleStatus = .full
                    mode = .systemWide
                    owns = true
                } catch {
                    notice = Notice(kind: .warning, text: "\(error.localizedDescription) Mac yalnızca kapak açıkken uyanık kalacak.")
                }
            }
        }

        var lowPowerRestore: LowPowerSettings?
        if preferences.batterySaver, case .applied(let original) = await enableLowPower() {
            lowPowerRestore = original
        }

        let now = Date.now
        let duration = min(max(duration, 60), Self.maximumDuration)
        activate(Session(start: now, end: now.addingTimeInterval(duration), mode: mode, ownsSleepSetting: owns, lowPowerRestore: lowPowerRestore))
    }

    func extend(by seconds: TimeInterval) {
        guard var session else { return }
        session.end = min(session.end.addingTimeInterval(seconds), Date.now.addingTimeInterval(Self.maximumDuration))
        self.session = session
        persist()
        scheduleExpiry()
    }

    func stop(_ reason: EndReason = .stopped) async {
        guard let session else { return }
        guard beginBusy() else {
            pendingStop = pendingStop ?? reason
            return
        }
        defer { endBusy() }
        pendingStop = nil

        expiryTimer?.cancel()
        expiryTimer = nil
        power.setNeeded(false, by: "session")
        self.session = nil
        endActivities()
        lastEnd = LastEnd(reason: reason, date: .now)
        if reason != .stopped {
            Notifier.post(title: reason.summary, body: "Mac artık normal şekilde uyuyabilir.")
        }

        if let restore = session.lowPowerRestore {
            _ = await SleepControl.applyLowPower(restore)
        }
        // Last on purpose: with the lid closed the Mac falls asleep the moment this succeeds.
        if session.ownsSleepSetting {
            await restoreSleep(promptIfNeeded: reason == .stopped)
        }
        SessionStore.clear()
        refreshSystemState()
    }

    /// Upgrades a lid-open-only session once the user grants the permission.
    func enableClosedLidMode() async {
        guard session?.mode == .lidOpenOnly, beginBusy() else { return }
        defer { endBusy() }
        do {
            try await SleepControl.installRule(applying: true)
            ruleStatus = .full
            notice = nil
            // Re-read after the prompt: the session may have been extended meanwhile. It can't have
            // ended, since stops wait while busy.
            guard var session else { return }
            session.mode = .systemWide
            session.ownsSleepSetting = true
            self.session = session
            persist()
            SessionGuard.ensureRunning()
        } catch SleepControl.Failure.cancelled {
        } catch {
            notice = Notice(kind: .error, text: error.localizedDescription)
        }
    }

    /// The battery saver option: remembered for the next session, applied at once to a running one.
    func setBatterySaver(_ enabled: Bool) async {
        preferences.batterySaver = enabled
        guard let session, (session.lowPowerRestore != nil) != enabled, beginBusy() else { return }
        defer { endBusy() }

        var restore: LowPowerSettings?
        if enabled {
            switch await enableLowPower() {
            case .applied(let original): restore = original
            case .alreadyOn: break
            case .failed: preferences.batterySaver = false
            }
        } else if let original = session.lowPowerRestore {
            _ = await SleepControl.applyLowPower(original)
        }

        // Re-read: the session may have been extended during an admin prompt.
        guard var current = self.session else { return }
        current.lowPowerRestore = restore
        self.session = current
        persist()
        if current.ownsSleepSetting || restore != nil {
            SessionGuard.ensureRunning()
        }
    }

    /// The lock option: remembered for the next session, applied at once to a running one.
    func setPreventsLock(_ enabled: Bool) {
        preferences.preventsLock = enabled
        updateDisplayActivity()
        if enabled {
            Task { await refreshLockDelay(force: true) }
        }
    }

    /// Reading the delay spawns `sysadminctl`, so callers ask only when it is shown, and repeated
    /// asks within a few seconds reuse the last answer.
    func refreshLockDelay(force: Bool = false) async {
        guard hasLid else { return }
        if !force, let checked = lockDelayCheckedAt, Date.now.timeIntervalSince(checked) < 15 { return }
        lockDelayCheckedAt = .now
        let delay = await SleepControl.lockDelay()
        if delay != lockDelay { lockDelay = delay }
    }

    /// Turns `disablesleep` off when something other than a CanSee session left it on.
    func reenableSleep() async {
        guard !isActive, beginBusy() else { return }
        defer { endBusy() }
        await restoreSleep(promptIfNeeded: true)
        refreshSystemState()
    }

    func installRule() async {
        guard beginBusy() else { return }
        defer { endBusy() }
        do {
            try await SleepControl.installRule()
        } catch SleepControl.Failure.cancelled {
        } catch {
            notice = Notice(kind: .error, text: error.localizedDescription)
        }
        ruleStatus = await SleepControl.ruleStatus()
    }

    func removeRule() async {
        guard !isActive, beginBusy() else { return }
        defer { endBusy() }
        do {
            try await SleepControl.removeRule()
        } catch SleepControl.Failure.cancelled {
        } catch {
            notice = Notice(kind: .error, text: error.localizedDescription)
        }
        ruleStatus = await SleepControl.ruleStatus()
    }

    /// One IORegistry read, cheap enough to run every time the panel opens.
    func refreshSystemState() {
        let disabledElsewhere = !isActive && hasLid && PowerRegistry.isSleepDisabled
        if disabledElsewhere != isSleepDisabledElsewhere {
            isSleepDisabledElsewhere = disabledElsewhere
        }
    }

    /// Ends the session when the battery or temperature guard trips.
    func enforceGuards() {
        guard isActive else { return }
        if preferences.batteryGuard, let battery = power.battery, !battery.isPluggedIn,
           battery.percent <= preferences.batteryThreshold {
            Task { await stop(.lowBattery) }
        } else if preferences.thermalGuard, power.thermalState == .critical {
            Task { await stop(.overheated) }
        }
    }

    // MARK: - Private

    private enum LowPowerChange {
        case applied(original: LowPowerSettings)
        case alreadyOn
        case failed
    }

    /// Turns Low Power Mode on for every power source, upgrading an older sleep-only rule with one
    /// admin prompt if needed.
    private func enableLowPower() async -> LowPowerChange {
        guard let current = await SleepControl.lowPowerSettings() else {
            notice = Notice(kind: .warning, text: "Bu Mac'te Düşük Güç Modu ayarı bulunamadı; pil tasarrufu kullanılamıyor.")
            return .failed
        }
        let target = LowPowerSettings(battery: current.battery.map { _ in true }, ac: current.ac.map { _ in true })
        guard current != target else { return .alreadyOn }
        if await SleepControl.applyLowPower(target) { return .applied(original: current) }

        do {
            try await SleepControl.installRule()
            ruleStatus = .full
            if await SleepControl.applyLowPower(target) { return .applied(original: current) }
        } catch {}
        // Undo a half-applied change, then explain.
        _ = await SleepControl.applyLowPower(current)
        notice = Notice(kind: .warning, text: "Pil tasarrufu açılamadı; Düşük Güç Modu için yönetici izni gerekiyor.")
        return .failed
    }

    private func resume(_ stored: StoredSession) async {
        var session = Session(start: stored.start, end: stored.end, mode: stored.mode,
                              ownsSleepSetting: stored.ownsSleepSetting, lowPowerRestore: stored.lowPowerRestore)
        if session.mode == .systemWide && !PowerRegistry.isSleepDisabled {
            // Typically after a restart. Re-apply silently; never prompt during launch.
            if await SleepControl.setSleepDisabled(true) {
                session.ownsSleepSetting = true
            } else {
                session.mode = .lidOpenOnly
                session.ownsSleepSetting = false
                notice = Notice(kind: .warning, text: "Oturum sürüyor ama kapak kapalı modu geri yüklenemedi. Mac yalnızca kapak açıkken uyanık kalacak.")
            }
        }
        activate(session)
        enforceGuards()
    }

    private func activate(_ session: Session) {
        self.session = session
        persist()
        if activity == nil {
            // Holds the idle-sleep assertion (listed by `pmset -g assertions`) and keeps CanSee out
            // of App Nap and safe from sudden or automatic termination while the session runs.
            // ASCII only: with Turkish characters the assertion shows up with an empty name.
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated], reason: "CanSee keeps this Mac awake for running agents")
        }
        updateDisplayActivity()
        scheduleExpiry()
        if session.ownsSleepSetting || session.lowPowerRestore != nil {
            SessionGuard.ensureRunning()
        }
        power.setNeeded(true, by: "session")
    }

    /// With the lock option on, keeps the display from idling off. macOS starts its "require
    /// password" countdown when the display turns off, so with the lid open the screen never locks.
    /// A closing lid still switches the panel off; per IOPMLib.h no assertion can stop that, which
    /// leaves the closed-lid lock to the user's own delay setting.
    private func updateDisplayActivity() {
        let wanted = isActive && preferences.preventsLock
        if wanted, displayActivity == nil {
            displayActivity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled], reason: "CanSee keeps the display on so the screen does not lock")
        } else if !wanted, let displayActivity {
            ProcessInfo.processInfo.endActivity(displayActivity)
            self.displayActivity = nil
        }
    }

    private func persist() {
        guard let session else { return }
        SessionStore.save(StoredSession(start: session.start, end: session.end, mode: session.mode,
                                        ownsSleepSetting: session.ownsSleepSetting, lowPowerRestore: session.lowPowerRestore))
    }

    /// One wall-clock timer for the whole session: no wakeups until expiry, it keeps counting
    /// through sleep and follows clock changes, and the leeway lets the system batch the wakeup.
    private func scheduleExpiry() {
        expiryTimer?.cancel()
        guard let end = session?.end else { return }
        let leeway = min(15, max(1, end.timeIntervalSinceNow * 0.002))
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(wallDeadline: DispatchWallTime(date: end), leeway: .milliseconds(Int(leeway * 1_000)))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.checkExpiry() }
        }
        timer.resume()
        expiryTimer = timer
    }

    private func checkExpiry() {
        guard let end = session?.end else { return }
        if end.timeIntervalSinceNow <= 0.5 {
            Task { await stop(.finished) }
        } else {
            scheduleExpiry()
        }
    }

    private func restoreSleep(promptIfNeeded: Bool) async {
        if await SleepControl.setSleepDisabled(false) { return }
        guard promptIfNeeded else {
            notice = Notice(kind: .error, text: "Uyku ayarı geri yüklenemedi. Paneldeki “Uykuyu aç” ile düzeltebilirsiniz.")
            return
        }
        do {
            try await SleepControl.restoreSleepWithPrompt()
        } catch SleepControl.Failure.cancelled {
        } catch {
            notice = Notice(kind: .error, text: error.localizedDescription)
        }
    }

    private func startBlocker() -> String? {
        if preferences.batteryGuard, let battery = PowerMonitor.readBattery(), !battery.isPluggedIn,
           battery.percent <= preferences.batteryThreshold {
            return "Pil %\(battery.percent). Pil koruması %\(preferences.batteryThreshold) ve altında başlatmaya izin vermiyor; şarja takın ya da eşiği Ayarlar'dan düşürün."
        }
        if preferences.thermalGuard, ProcessInfo.processInfo.thermalState == .critical {
            return "Mac şu an çok sıcak. Biraz soğumasını bekleyin."
        }
        return nil
    }

    private func beginBusy() -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        return true
    }

    private func endBusy() {
        isBusy = false
        if let reason = pendingStop {
            pendingStop = nil
            Task { await stop(reason) }
        }
    }

    private func endActivities() {
        for case let token? in [activity, displayActivity] {
            ProcessInfo.processInfo.endActivity(token)
        }
        activity = nil
        displayActivity = nil
    }

    private func observeSystemEvents() {
        guard observers.isEmpty else { return }
        // A clock change, or a wake if the Mac slept anyway, may have moved past the deadline.
        let handler: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkExpiry()
                self?.refreshSystemState()
            }
        }
        observers.append(NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main, using: handler))
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: handler))
    }
}

#if DEBUG
extension AwakeManager {
    /// Puts the manager into a given state for SwiftUI previews; touches nothing on the system.
    func preview(session: Session? = nil, notice: Notice? = nil, lastEnd: LastEnd? = nil,
                 ruleStatus: RuleStatus? = .full, sleepDisabledElsewhere: Bool = false,
                 lockDelay: LockDelay? = nil) -> Self {
        self.session = session
        self.notice = notice
        self.lastEnd = lastEnd
        self.ruleStatus = ruleStatus
        self.isSleepDisabledElsewhere = sleepDisabledElsewhere
        self.lockDelay = lockDelay
        return self
    }
}
#endif

private extension DispatchWallTime {
    init(date: Date) {
        let interval = date.timeIntervalSince1970
        let seconds = interval.rounded(.down)
        self.init(timespec: timespec(tv_sec: Int(seconds), tv_nsec: Int((interval - seconds) * 1_000_000_000)))
    }
}
