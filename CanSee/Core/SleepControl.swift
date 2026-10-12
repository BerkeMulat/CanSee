//
//  SleepControl.swift
//  CanSee
//
//  Lid-close sleep can only be blocked system-wide via `pmset disablesleep`, which needs root, and
//  so does Low Power Mode. Both go through one narrowly scoped sudoers rule.
//

import Foundation
import IOKit

/// Live power-management state read straight from the IORegistry: no process spawn, no polling.
nonisolated enum PowerRegistry {
    /// Only portables publish a clamshell state.
    static var hasLid: Bool { rootDomainProperty("AppleClamshellState") != nil }

    /// The system-wide `pmset disablesleep` flag, whoever set it.
    static var isSleepDisabled: Bool { (rootDomainProperty("SleepDisabled") as? Bool) ?? false }

    private static func rootDomainProperty(_ key: String) -> Any? {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(rootDomain) }
        return IORegistryEntryCreateCFProperty(rootDomain, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}

nonisolated enum RuleStatus {
    case missing
    /// Written by CanSee 1.0 or 2.0: sleep only, so Low Power Mode needs one more prompt.
    case sleepOnly
    case full
}

/// The `pmset` Low Power Mode values per power source; nil where the Mac has no such source.
nonisolated struct LowPowerSettings: Equatable {
    var battery: Bool?
    var ac: Bool?

    /// Two characters, battery then AC: "0", "1", or "-" for a missing source.
    var code: String {
        [battery, ac].map { $0.map { $0 ? "1" : "0" } ?? "-" }.joined()
    }

    init(battery: Bool?, ac: Bool?) {
        self.battery = battery
        self.ac = ac
    }

    init?(code: Substring) {
        let values = code.map { character -> Bool?? in
            switch character {
            case "1": true
            case "0": false
            case "-": .some(nil)
            default: nil
            }
        }
        guard values.count == 2, let battery = values[0], let ac = values[1] else { return nil }
        self.init(battery: battery, ac: ac)
    }
}

/// macOS's "require password after screen saver begins or display is turned off" delay.
nonisolated enum LockDelay: Equatable {
    case off, immediate, seconds(Int), unknown
}

/// On first use a narrowly scoped sudoers rule is installed (one admin prompt) that allows only the
/// `pmset` commands below, so later toggles are silent and keep working with nobody at the Mac.
nonisolated enum SleepControl {
    enum Failure: LocalizedError {
        case cancelled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .cancelled: "Yönetici izni verilmedi."
            case .failed(let message): "İşlem tamamlanamadı: \(message)"
            }
        }
    }

    private static let pmset = "/usr/bin/pmset"
    private static let sudo = "/usr/bin/sudo"
    private static let rulesDirectory = "/private/etc/sudoers.d"
    /// One file per user, named by uid: sudo silently skips file names that contain a dot.
    private static var ruleFile: String { "\(rulesDirectory)/cansee-\(getuid())" }
    /// The shared file CanSee 1.0 wrote, keyed by user name.
    private static let legacyRuleFile = "\(rulesDirectory)/cansee"

    private static let sleepCommands = ["\(pmset) -a disablesleep 0", "\(pmset) -a disablesleep 1"]
    private static let lowPowerCommands = [
        "\(pmset) -b lowpowermode 0", "\(pmset) -b lowpowermode 1",
        "\(pmset) -c lowpowermode 0", "\(pmset) -c lowpowermode 1",
    ]

    // MARK: - Sleep

    /// Toggles through the sudoers rule without any UI; false when the rule isn't installed.
    static func setSleepDisabled(_ disabled: Bool) async -> Bool {
        await run(sudo, ["-n", pmset, "-a", "disablesleep", disabled ? "1" : "0"]).status == 0
    }

    /// For app termination, where there is no chance to await.
    @discardableResult
    static func restoreSleepSync() -> Bool {
        runSync(sudo, ["-n", pmset, "-a", "disablesleep", "0"])
    }

    /// Fallback when the rule is gone (removed by hand) but sleep still has to come back.
    static func restoreSleepWithPrompt() async throws {
        try await runAsAdmin(
            "\(pmset) -a disablesleep 0",
            prompt: "CanSee, Mac'in normal uyku ayarını geri yüklemek için yönetici izni istiyor."
        )
    }

    // MARK: - Low Power Mode

    /// Current Low Power Mode values, or nil if this Mac's `pmset` has no `lowpowermode` setting.
    static func lowPowerSettings() async -> LowPowerSettings? {
        parseLowPower(await run(pmset, ["-g", "custom"]).output)
    }

    /// Applies the given values; false if any command failed, typically because the installed
    /// rule predates Low Power Mode.
    static func applyLowPower(_ settings: LowPowerSettings) async -> Bool {
        var succeeded = true
        for (flag, value) in [("-b", settings.battery), ("-c", settings.ac)] {
            guard let value else { continue }
            if await run(sudo, ["-n", pmset, flag, "lowpowermode", value ? "1" : "0"]).status != 0 {
                succeeded = false
            }
        }
        return succeeded
    }

    static func applyLowPowerSync(_ settings: LowPowerSettings) {
        for (flag, value) in [("-b", settings.battery), ("-c", settings.ac)] {
            guard let value else { continue }
            runSync(sudo, ["-n", pmset, flag, "lowpowermode", value ? "1" : "0"])
        }
    }

    static func parseLowPower(_ output: String) -> LowPowerSettings? {
        var settings = LowPowerSettings(battery: nil, ac: nil)
        var source: Character?
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            if line.hasSuffix(":") {
                source = line.hasPrefix("Battery Power") ? "b" : line.hasPrefix("AC Power") ? "c" : nil
            } else if fields.count == 2, fields[0] == "lowpowermode", let source {
                if source == "b" { settings.battery = fields[1] == "1" } else { settings.ac = fields[1] == "1" }
            }
        }
        return settings.battery == nil && settings.ac == nil ? nil : settings
    }

    // MARK: - Lock screen

    /// Readable without a password; changing it is not (`sysadminctl -screenLock` wants the user's).
    static func lockDelay() async -> LockDelay {
        parseLockDelay(await run("/usr/sbin/sysadminctl", ["-screenLock", "status"]).output)
    }

    static func parseLockDelay(_ output: String) -> LockDelay {
        let text = output.lowercased()
        if text.contains("screenlock is off") { return .off }
        if text.contains("immediate") { return .immediate }
        guard let range = text.range(of: #"delay is \d+ seconds"#, options: .regularExpression),
              let seconds = Int(text[range].filter(\.isNumber))
        else { return .unknown }
        return seconds == 0 ? .immediate : .seconds(seconds)
    }

    // MARK: - Rule

    /// `sudo -l <command>` also succeeds through an admin's password-protected `ALL` rule, so it
    /// can't tell whether ours is there. The full listing can: it needs no password once any
    /// NOPASSWD rule exists, and shows ours verbatim.
    static func ruleStatus() async -> RuleStatus {
        let result = await run(sudo, ["-n", "-l"])
        return result.status == 0 ? parseRuleStatus(result.output) : .missing
    }

    static func parseRuleStatus(_ listing: String) -> RuleStatus {
        // The listing wraps long lines, hence the whitespace folding.
        let text = listing.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard text.contains("NOPASSWD:"), sleepCommands.allSatisfy(text.contains) else { return .missing }
        return lowPowerCommands.allSatisfy(text.contains) ? .full : .sleepOnly
    }

    /// Installs the rule behind one admin prompt; `applying` also sets `disablesleep` in the same step.
    static func installRule(applying value: Bool? = nil) async throws {
        let rule = "#\(getuid()) ALL=(root) NOPASSWD: " + (sleepCommands + lowPowerCommands).joined(separator: ", ")
        var commands = [
            "/bin/mkdir -p -m 0755 \(rulesDirectory) && t=$(/usr/bin/mktemp) || exit 1",
            // visudo validates before anything lands in sudoers.d; a broken file there would lock sudo.
            "/usr/bin/printf '%s\\n' '\(rule)' > \"$t\" && /usr/sbin/visudo -cqf \"$t\" && /usr/bin/install -m 0440 -o root -g wheel \"$t\" \(ruleFile); s=$?",
            "/bin/rm -f \"$t\"",
            "[ $s -eq 0 ] || exit $s",
        ]
        if let value {
            commands.append("\(pmset) -a disablesleep \(value ? 1 : 0)")
        }
        try await runAsAdmin(
            commands.joined(separator: "; "),
            prompt: "CanSee, kapak kapalıyken Mac'i uyanık tutabilmek ve pil tasarrufunu açabilmek için bir kereliğine yönetici izni istiyor."
        )
    }

    static func removeRule() async throws {
        var commands = ["/bin/rm -f \(ruleFile)"]
        let user = NSUserName()
        if !user.isEmpty, user.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }) {
            // Only remove the 1.0 file if the rule inside is this user's.
            commands.append("if /usr/bin/grep -q '^\(user) ALL=(root) NOPASSWD: \(pmset) -a disablesleep' \(legacyRuleFile) 2>/dev/null; then /bin/rm -f \(legacyRuleFile); fi")
        }
        try await runAsAdmin(
            commands.joined(separator: "; "),
            prompt: "CanSee, kapak kapalı modu iznini kaldırmak için yönetici izni istiyor."
        )
    }

    // MARK: - Private

    private static func runAsAdmin(_ command: String, prompt: String) async throws {
        let script = "do shell script \(appleScriptString(command)) with prompt \(appleScriptString(prompt)) with administrator privileges"
        let result = await run("/usr/bin/osascript", ["-e", script])
        guard result.status == 0 else {
            let message = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw message.contains("-128") ? Failure.cancelled : Failure.failed(message)
        }
    }

    private static func appleScriptString(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Output is read after exit, which is fine for the few hundred bytes these commands print.
    private static func run(_ path: String, _ arguments: [String]) async -> (status: Int32, output: String) {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { finished in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: (finished.terminationStatus, String(decoding: data, as: UTF8.self)))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: (-1, error.localizedDescription))
            }
        }
    }

    @discardableResult
    private static func runSync(_ path: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
