//
//  SessionStore.swift
//  CanSee
//
//  Persists the running session so it survives a relaunch, and backs it with a watchdog process.
//

import Foundation

nonisolated enum AwakeMode: String {
    /// `pmset disablesleep` is on: the Mac stays awake with the lid closed.
    case systemWide
    /// Only an idle-sleep assertion: awake while the lid is open (no admin rights, or no lid).
    case lidOpenOnly
}

nonisolated struct StoredSession: Equatable {
    var start: Date
    var end: Date
    var mode: AwakeMode
    /// True when CanSee itself turned `disablesleep` on and therefore must turn it off again.
    var ownsSleepSetting: Bool
    /// The Low Power Mode values to put back; nil when CanSee didn't change them.
    var lowPowerRestore: LowPowerSettings?

    /// Whether the watchdog has anything to undo if CanSee dies.
    var needsGuard: Bool { ownsSleepSetting || lowPowerRestore != nil }
}

/// One line on disk, simple enough for the zsh watchdog to `read`:
/// `<end epoch> <start epoch> <mode> <owns 0|1> <low power code or ->`.
nonisolated enum SessionStore {
    static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CanSee", isDirectory: true)
    static let file = directory.appendingPathComponent("session")
    static let lockFile = directory.appendingPathComponent("guard.lock")

    static func save(_ session: StoredSession) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let line = [
            String(Int(session.end.timeIntervalSince1970.rounded(.up))),
            String(Int(session.start.timeIntervalSince1970)),
            session.mode.rawValue,
            session.ownsSleepSetting ? "1" : "0",
            session.lowPowerRestore?.code ?? "-",
        ].joined(separator: " ")
        try? Data((line + "\n").utf8).write(to: file, options: .atomic)
    }

    static func load() -> StoredSession? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let fields = text.split(whereSeparator: \.isWhitespace)
        guard fields.count >= 4,
              let end = TimeInterval(fields[0]),
              let start = TimeInterval(fields[1]),
              let mode = AwakeMode(rawValue: String(fields[2]))
        else { return nil }
        return StoredSession(
            start: Date(timeIntervalSince1970: start),
            end: Date(timeIntervalSince1970: end),
            mode: mode,
            ownsSleepSetting: fields[3] == "1",
            lowPowerRestore: fields.count >= 5 ? LowPowerSettings(code: fields[4]) : nil
        )
    }

    static func clear() {
        try? FileManager.default.removeItem(at: file)
    }
}

/// A detached zsh loop that undoes CanSee's system changes at the deadline even if CanSee crashes
/// or is force-quit: Low Power Mode first, then sleep. It uses builtins only (no forks), wakes at
/// most once a minute at background QoS, holds a lock so only one ever runs, and exits by itself
/// as soon as the session file is gone. The 20 s grace leaves the normal expiry to a live app.
nonisolated enum SessionGuard {
    private static let script = #"""
    zmodload zsh/datetime zsh/zselect zsh/system || exit 1
    zsystem flock -t 0 $2 2>/dev/null || exit 0
    while [[ -r $1 ]]; do
      read -r deadline started mode owns lowpower < $1 || exit 0
      [[ $deadline == <-> ]] || exit 0
      [[ $owns == 1 || $lowpower == [01-][01-] ]] || exit 0
      (( left = deadline + 20 - EPOCHSECONDS ))
      if (( left <= 0 )); then
        if [[ $lowpower == [01-][01-] ]]; then
          [[ ${lowpower[1]} == [01] ]] && /usr/bin/sudo -n /usr/bin/pmset -b lowpowermode ${lowpower[1]}
          [[ ${lowpower[2]} == [01] ]] && /usr/bin/sudo -n /usr/bin/pmset -c lowpowermode ${lowpower[2]}
        fi
        if [[ $owns == 1 ]]; then
          /usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0 || exit 1
        fi
        /bin/rm -f $1
        exit 0
      fi
      zselect -t $(( (left < 60 ? left : 60) * 100 ))
    done
    """#

    static func ensureRunning() {
        guard !isRunning() else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // -f skips the user's startup files: faster, and none of their code runs in here.
        process.arguments = ["-f", "-c", script, "cansee-guard", SessionStore.file.path, SessionStore.lockFile.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.qualityOfService = .background
        try? process.run()
    }

    /// Probes the guard's lock without taking it (and creates the lock file for the guard).
    static func isRunning() -> Bool {
        let fd = open(SessionStore.lockFile.path, O_RDWR | O_CREAT, 0o600)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var probe = flock()
        probe.l_type = Int16(F_WRLCK)
        probe.l_whence = Int16(SEEK_SET)
        guard fcntl(fd, F_GETLK, &probe) == 0 else { return false }
        return probe.l_type != Int16(F_UNLCK)
    }
}
