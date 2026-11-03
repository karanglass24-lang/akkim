// Portions of this file are derived from ChargeWatching
// (https://github.com/TY-teo/ChargeWatching), MIT License,
// Copyright (c) 2026 TY-teo. See LICENSE and THIRD-PARTY-NOTICES.md.

import Foundation
import Combine
import AppKit

@MainActor
final class SMCChargeLimiter: ObservableObject {
    @Published private(set) var installed: Bool = false
    @Published private(set) var enabled: Bool = false
    @Published private(set) var limit: Int = 80
    @Published private(set) var busy: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var sailingMode: Bool = false
    @Published private(set) var dischargeEnabled: Bool = false
    @Published private(set) var heatProtectionC: Int = 0
    @Published private(set) var topUpRequested: Bool = false

    private let configDir = "/Users/Shared/Akkim"
    private let configPath = "/Users/Shared/Akkim/smc-limit.json"
    private let calibStatePath = "/Users/Shared/Akkim/calib-state.json"
    private let plistLabel = "com.akkim.helper"
    private let plistPath = "/Library/LaunchDaemons/com.akkim.helper.plist"

    /// Hysteresis: align with Apple's official behavior ("recharge after dropping > 5%").
    /// AppSettings 값을 사용하여 설정 화면과 일치시킵니다.
    private var deadband: Int { AppSettings.shared.deadband }
    /// Auto full-charge calibration interval (days).
    private var calibrationDays: Int { AppSettings.shared.calibrationDays }

    private var settingsBag: Set<AnyCancellable> = []
    /// Keeps the running `osascript` alive until its termination handler fires.
    private var adminProcess: Process?
    /// When the user asked for a top-up. The daemon polls every 10 s, so a
    /// "topUp: false" state file seen right after the request is simply stale.
    private var topUpRequestedAt: Date?

    init() {
        reload()
        bindSettings()
    }

    /// 설정 변경 시 헬퍼 설정 파일을 다시 기록합니다.
    private func bindSettings() {
        let s = AppSettings.shared
        s.$calibrationDays.dropFirst()
            .sink { [weak self] _ in Task { @MainActor in self?.writeConfig() } }
            .store(in: &settingsBag)
        s.$deadband.dropFirst()
            .sink { [weak self] _ in Task { @MainActor in self?.writeConfig() } }
            .store(in: &settingsBag)
        s.$sailingMode.dropFirst()
            .sink { [weak self] value in
                Task { @MainActor in
                    self?.sailingMode = value
                    self?.writeConfig()
                }
            }
            .store(in: &settingsBag)
        s.$dischargeMode.dropFirst()
            .sink { [weak self] value in
                Task { @MainActor in
                    self?.dischargeEnabled = value
                    self?.writeConfig()
                }
            }
            .store(in: &settingsBag)
        s.$heatProtectionC.dropFirst()
            .sink { [weak self] value in
                Task { @MainActor in
                    self?.heatProtectionC = value
                    self?.writeConfig()
                }
            }
            .store(in: &settingsBag)
    }

    /// Refresh install state and configuration from disk.
    func reload() {
        installed = FileManager.default.fileExists(atPath: plistPath)
        if let data = FileManager.default.contents(atPath: configPath),
           let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            enabled = (j["enabled"] as? Bool) ?? false
            limit = (j["limit"] as? Int) ?? 80
            sailingMode = (j["sailingMode"] as? Bool) ?? AppSettings.shared.sailingMode
            dischargeEnabled = (j["discharge"] as? Bool) ?? AppSettings.shared.dischargeMode
            heatProtectionC = (j["heatProtectionC"] as? Int) ?? AppSettings.shared.heatProtectionC
            topUpRequested = (j["topUp"] as? Bool) ?? false
            // A top-up without an enabled limit can never be enforced.
            if !enabled { topUpRequested = false }
            // 설정 파일이 기준값입니다. 앱 토글 상태도 같은 값으로 맞춰 UI 불일치를 막습니다.
            // (아직 bindSettings() 이전이므로 중복 write 는 발생하지 않습니다.)
            AppSettings.shared.sailingMode = sailingMode
            AppSettings.shared.dischargeMode = dischargeEnabled
            AppSettings.shared.heatProtectionC = heatProtectionC
            AppSettings.shared.save()
        } else {
            // 설정 파일이 아직 없으면 앱 설정 기본값을 사용합니다.
            sailingMode = AppSettings.shared.sailingMode
            dischargeEnabled = AppSettings.shared.dischargeMode
            heatProtectionC = AppSettings.shared.heatProtectionC
            topUpRequested = false
        }
    }

    /// 보정 상태 읽기 (헬퍼가 기록한 calib-state.json 기준).
    /// 기록이 없어도 현재 보정 주기 정보를 담아 항상 값을 돌려줍니다.
    func readCalibrationStatus() -> CalibrationStatus {
        let interval = calibrationDays
        guard let data = FileManager.default.contents(atPath: calibStatePath),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t = j["lastFullChargeAt"] as? Double else {
            return CalibrationStatus(
                lastFullChargeDate: nil,
                daysSinceLastFull: 0,
                daysUntilCalibration: interval,
                calibrationIntervalDays: interval
            )
        }
        let lastFull = Date(timeIntervalSince1970: t)
        let daysSince = Int(Date().timeIntervalSince(lastFull) / 86_400)
        let daysUntil = interval > 0 ? max(0, interval - daysSince) : 0
        return CalibrationStatus(
            lastFullChargeDate: lastFull,
            daysSinceLastFull: daysSince,
            daysUntilCalibration: daysUntil,
            calibrationIntervalDays: interval
        )
    }

    /// Enable the charge limit at the given percentage (installs helper on first use).
    /// 비동기: 헬퍼 설치(osascript 인증)가 완료된 후에야 enabled 상태가 반영됩니다.
    func enable(limit percent: Int) async {
        lastError = nil
        if installed {
            self.limit = percent
            self.enabled = true
            writeConfig()
        } else {
            let ok = await install()
            if ok {
                self.limit = percent
                self.enabled = true
                self.writeConfig()
            } else {
                lastError = "Helper installation failed"
            }
        }
    }

    /// Set the limit while enabled.
    func setLimit(_ percent: Int) {
        limit = percent
        if enabled { writeConfig() }
    }

    func setSailingMode(_ enabled: Bool) {
        sailingMode = enabled
        writeConfig()
    }

    /// 방전 모드: 어댑터를 SMC 레벨에서 분리해 제한치까지 배터리를 방전시킵니다.
    func setDischarge(_ enabled: Bool) {
        dischargeEnabled = enabled
        writeConfig()
    }

    /// Heat protection threshold (℃). 0 disables it.
    func setHeatProtection(_ celsius: Int) {
        let clamped = celsius <= 0 ? 0 : min(60, max(30, celsius))
        guard clamped != heatProtectionC else { return }
        heatProtectionC = clamped
        AppSettings.shared.heatProtectionC = clamped
        writeConfig()
    }

    /// Ask the helper to charge to 100% once, then restore the limit.
    /// Returns false when the helper is not installed.
    @discardableResult
    func requestTopUp() -> Bool {
        guard installed else { return false }
        // Nothing to top up when the limit is already effectively unlimited.
        guard limit < 100 else { return true }
        topUpRequested = true
        topUpRequestedAt = Date()
        // A top-up only makes sense while the helper is enforcing something.
        enabled = true
        // Discharge and top-up are opposites; a top-up request cancels discharge.
        dischargeEnabled = false
        AppSettings.shared.dischargeMode = false
        writeConfig()
        return true
    }

    func cancelTopUp() {
        guard topUpRequested else { return }
        topUpRequested = false
        topUpRequestedAt = nil
        writeConfig()
    }

    /// Aligns the local flag with the daemon's published state.
    ///
    /// The daemon owns the flag once it consumes it, but the state file can be
    /// up to 10 s behind a fresh request — hence the grace window.
    func syncTopUp(fromDaemon requested: Bool) {
        if requested {
            if !topUpRequested {
                topUpRequested = true
                topUpRequestedAt = Date()
            }
            return
        }
        guard topUpRequested else { return }
        if let at = topUpRequestedAt, Date().timeIntervalSince(at) < 15 { return }
        topUpRequested = false
        topUpRequestedAt = nil
    }

    /// Disable the charge limit (restore normal charging).
    func disable() {
        enabled = false
        // A pending top-up belongs to the limit being enforced; drop it so
        // re-enabling the limit later does not silently charge to 100%.
        topUpRequested = false
        topUpRequestedAt = nil
        writeConfig()
    }

    /// Async wrapper for install() completion handler.
    private func install() async -> Bool {
        return await withCheckedContinuation { continuation in
            self.install { ok in
                continuation.resume(returning: ok)
            }
        }
    }

    // MARK: Install / uninstall (one-time admin authorization via osascript)

    func install(_ completion: @escaping (Bool) -> Void = { _ in }) {
        guard let script = bundledPath("install-helper", "sh"),
              let helper = bundledPath("akkim-helper", nil) else {
            lastError = "Helper / install script not found in bundle"
            completion(false)
            return
        }
        runAdmin("bash '\(script)' install '\(helper)'") { [weak self] ok, err in
            guard let self else { return }
            self.installed = FileManager.default.fileExists(atPath: self.plistPath)
            if !ok && !self.installed { self.lastError = err ?? "Install failed" }
            completion(self.installed)
        }
    }

    func uninstall() async {
        guard let script = bundledPath("install-helper", "sh") else { return }
        enabled = false
        writeConfig()
        _ = await runAdminAsync("bash '\(script)' uninstall")
        installed = FileManager.default.fileExists(atPath: plistPath)
    }

    /// Async wrapper for runAdmin() completion handler.
    private func runAdminAsync(_ shellCommand: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            self.runAdmin(shellCommand) { ok, _ in
                continuation.resume(returning: ok)
            }
        }
    }

    // MARK: Internal

    private func writeConfig() {
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        let obj: [String: Any] = [
            "schemaVersion": 1,
            "enabled": enabled,
            "limit": limit,
            "sailingMode": sailingMode,
            "discharge": dischargeEnabled,
            "deadband": deadband,
            "calibrationDays": calibrationDays,
            "heatProtectionC": heatProtectionC,
            "topUp": topUpRequested,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: obj) {
            // Atomic write: the daemon polls this file every 10 s and must never
            // observe a half-written (unparseable) JSON document.
            try? data.write(to: URL(fileURLWithPath: configPath), options: .atomic)
        }
    }

    /// Bundled resource path (.app/Contents/Resources); falls back to .build/release for dev.
    private func bundledPath(_ name: String, _ ext: String?) -> String? {
        if let res = Bundle.main.resourceURL {
            let url = ext == nil ? res.appendingPathComponent(name) : res.appendingPathComponent("\(name).\(ext!)")
            if FileManager.default.fileExists(atPath: url.path) { return url.path }
        }
        let dev = name == "akkim-helper"
            ? FileManager.default.currentDirectoryPath + "/.build/release/akkim-helper"
            : FileManager.default.currentDirectoryPath + "/scripts/\(name).\(ext ?? "")"
        return FileManager.default.fileExists(atPath: dev) ? dev : nil
    }

    private func runAdmin(_ shellCommand: String, _ completion: @escaping (Bool, String?) -> Void) {
        busy = true
        let escaped = shellCommand.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "do shell script \"\(escaped)\" with administrator privileges"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", appleScript]
        let errPipe = Pipe()
        p.standardError = errPipe
        // The install script echoes progress on stdout; drop it so a full pipe
        // buffer can never block the child process.
        p.standardOutput = FileHandle.nullDevice
        // terminationHandler runs off the main thread. The password prompt can stay
        // up for seconds, and blocking the main actor froze the whole app before.
        p.terminationHandler = { [weak self] proc in
            let ok = proc.terminationStatus == 0
            var err: String?
            if !ok {
                // Close our write end first, otherwise readToEnd() waits for EOF forever.
                try? errPipe.fileHandleForWriting.close()
                if let data = try? errPipe.fileHandleForReading.readToEnd() {
                    err = String(data: data, encoding: .utf8)
                }
            }
            Task { @MainActor in
                self?.adminProcess = nil
                self?.busy = false
                completion(ok, err)
            }
        }
        adminProcess = p
        do {
            try p.run()
        } catch {
            adminProcess = nil
            busy = false
            completion(false, error.localizedDescription)
        }
    }
}
