// Portions of this file are derived from ChargeWatching
// (https://github.com/TY-teo/ChargeWatching), MIT License,
// Copyright (c) 2026 TY-teo. See LICENSE and THIRD-PARTY-NOTICES.md.

import Foundation

/// Read-only report for `Akkim --diagnose`. Needs no administrator privileges,
/// so a user can paste the output into an issue without touching the system.
@MainActor
enum Diagnostics {
    static func report(controller: ChargeLimitController, limiter: SMCChargeLimiter) async -> String {
        var out: [String] = []
        out.append("=== Akkim diagnose ===")

        let os = ProcessInfo.processInfo.operatingSystemVersion
        out.append("OS: macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) (\(machine))")

        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let path = bundle.bundleURL.path
        out.append("App: \(version) (\(build)) \(path)")
        let quarantine = await ProcessRunner.run("/usr/bin/xattr",
                                                 ["-p", "com.apple.quarantine", path], timeout: 5)
        out.append("Quarantine: \(quarantine.exitCode == 0 ? "YES (may block the helper)" : "no")")

        await controller.refresh()
        let cap = controller.capability
        out.append("Capability: platformSupportsSet=\(cap.platformSupportsSet)"
            + " systemControl=\(cap.systemControl) bridgeConfigured=\(cap.bridgeConfigured)"
            + " canSetInApp=\(cap.canSetInApp)")
        out.append("Limiter: installed=\(limiter.installed) enabled=\(limiter.enabled) limit=\(limiter.limit)")
        if let err = limiter.lastError { out.append("LimiterError: \(err)") }
        if let err = controller.lastError { out.append("LastError: \(err)") }

        let current = SystemChargeLimit.currentLimit()
        out.append("SystemLimit: available=\(SystemChargeLimit.isAvailable)"
            + " current=\(current.map(String.init) ?? "nil")"
            + " allowed=\(SystemChargeLimit.availableLimits())")

        let fm = FileManager.default
        let plist = fm.fileExists(atPath: "/Library/LaunchDaemons/com.akkim.helper.plist")
        let binary = fm.fileExists(atPath: "/Library/PrivilegedHelperTools/com.akkim.helper")
        let running = await ProcessRunner.run("/usr/bin/pgrep", ["-f", "com.akkim.helper"], timeout: 5)
        out.append("Helper: launchd=\(plist ? "yes" : "NO") binary=\(binary ? "yes" : "NO")"
            + " running=\(running.exitCode == 0 ? "yes" : "NO")")

        for (label, file) in [("Config", "/Users/Shared/Akkim/smc-limit.json"),
                              ("State", "/Users/Shared/Akkim/helper-state.json")] {
            if let text = try? String(contentsOfFile: file, encoding: .utf8) {
                out.append("\(label): \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
            } else {
                out.append("\(label): MISSING")
            }
        }

        let shortcuts = await ProcessRunner.run("/usr/bin/shortcuts", ["list"], timeout: 10)
        let names = shortcuts.stdout.split(separator: "\n")
            .filter { $0.contains("SetBatteryChargeLimit") }
        out.append("Shortcuts: \(names.isEmpty ? "none" : names.joined(separator: ", "))")

        out.append("---")
        if !cap.canSetInApp {
            out.append("Hint: the app cannot set the limit yet."
                + " Run `Akkim --install-helper` (admin prompt) or create the Shortcuts.")
        } else if plist && !binary {
            out.append("Hint: LaunchDaemon exists but the helper binary is missing."
                + " Run `Akkim --install-helper`.")
        } else if plist && binary && running.exitCode != 0 {
            out.append("Hint: helper is installed but not running."
                + " Check /var/log/akkim-helper.log or run `Akkim --install-helper`.")
        }

        return out.joined(separator: "\n")
    }

    /// `uname -m` equivalent without spawning a process.
    private static var machine: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }
}
