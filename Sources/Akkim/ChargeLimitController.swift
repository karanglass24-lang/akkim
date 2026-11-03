// Portions of this file are derived from ChargeWatching
// (https://github.com/TY-teo/ChargeWatching), MIT License,
// Copyright (c) 2026 TY-teo. See LICENSE and THIRD-PARTY-NOTICES.md.

import Foundation
import SwiftUI
import AppKit
import Combine
import Darwin

@MainActor
final class ChargeLimitController: ObservableObject {
    @Published private(set) var state: ChargeLimitState = .unknown
    @Published private(set) var capability: ChargeLimitCapability = ChargeLimitCapability(
        canRead: false, platformSupportsSet: false, bridgeConfigured: false, canSetInApp: false)
    @Published private(set) var lastError: ChargeLimitError?
    @Published private(set) var isSetting = false
    @Published private(set) var calibrationStatus: CalibrationStatus?
    /// Last published daemon state (`helper-state.json`), refreshed on a 5 s timer.
    @Published private(set) var helperStatus: HelperStatus?
    @Published private(set) var isTopUpActive = false
    /// Charging is allowed but the pack is not charging while plugged in (likely
    /// macOS's own Charge Limit). Set after a short grace period.
    @Published private(set) var systemHoldSuspected = false

    private var systemHoldSince: Date?

    var onOpenOnboarding: (() -> Void)?

    private let limiter: SMCChargeLimiter
    private let bridge: ShortcutBridge?

    private var pollTimer: Timer?
    private var helperTimer: Timer?

    /// Cached `shortcuts list` probe. Spawning the shortcuts binary on every
    /// 3 s poll made the popover sluggish, so results are reused briefly.
    private var bridgeProbe: (available: Bool, at: Date)?
    private let bridgeProbeTTL: TimeInterval = 300
    private let bridgeProbeFailureTTL: TimeInterval = 60

    // `SMCChargeLimiter` is `@MainActor`, so it cannot be constructed in a
    // default-argument expression (evaluated in a nonisolated context).
    // Callers create the shared limiter and pass it in.
    init(limiter: SMCChargeLimiter, bridge: ShortcutBridge? = nil) {
        self.limiter = limiter
        self.bridge = bridge
        // The daemon writes its state every ~10 s; poll cheaply (mtime cache) even
        // while the popover is closed so notifications can react to reason changes.
        refreshHelperStatus()
        helperTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.refreshHelperStatus() }
        }
    }

    // MARK: Polling lifecycle (started/stopped when the popover shows/hides)

    func startPolling() {
        // Re-probe the shortcut once per popover open; the 3 s timer then uses the cache.
        bridgeProbe = nil
        Task { await self.refresh() }
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: Read / Set

    func refresh() async {
        let installed = limiter.installed
        let enabled = limiter.enabled
        let limit = limiter.limit
        state = (enabled && installed) ? .limited(limit) : .unlimited

        let bridgeConfigured = await bridgeAvailable()
        capability = Self.computeCapability(bridgeConfigured: bridgeConfigured, helperInstalled: installed)

        // 보정 상태 갱신
        calibrationStatus = limiter.readCalibrationStatus()
        refreshHelperStatus()
    }

    /// Reads the daemon's published state (mtime-cached) and reconciles local flags.
    /// Safe to call often: `HelperStatus.readCached()` only parses when the file changed.
    func refreshHelperStatus() {
        let status = HelperStatus.readCached()
        helperStatus = status
        isTopUpActive = limiter.topUpRequested

        guard let status, !status.isStale else { return }
        limiter.syncTopUp(fromDaemon: status.topUp)
        isTopUpActive = limiter.topUpRequested

        // The daemon owns the config file; align the toggle when the file changed
        // from another path (e.g. helper rewritten topUp). Skipped right after a
        // local write so a stale state file cannot flip the switch back.
        if limiter.syncFromDaemon(enabled: status.enabled, limit: status.limit) {
            state = (limiter.enabled && limiter.installed) ? .limited(limiter.limit) : .unlimited
        }

        // The daemon reports CHIE availability; keep the UI toggle honest.
        if !status.chieAvailable, limiter.dischargeEnabled {
            limiter.setDischarge(false)
            AppSettings.shared.dischargeMode = false
            AppSettings.shared.save()
        }
    }

    /// Cached bridge probe: at most one `shortcuts list` spawn per TTL window.
    private func bridgeAvailable() async -> Bool {
        guard let bridge else { return false }
        if let probe = bridgeProbe {
            let ttl = probe.available ? bridgeProbeTTL : bridgeProbeFailureTTL
            if Date().timeIntervalSince(probe.at) < ttl { return probe.available }
        }
        let available = await bridge.isBridgeAvailable()
        bridgeProbe = (available, Date())
        return available
    }

    /// Explicit on/off switch for the charge limit.
    func setLimitEnabled(_ enabled: Bool) async {
        if enabled {
            // Restore the previously chosen step instead of resetting to 80%.
            let fallback = ChargeLimitConstants.steps.contains(limiter.limit) ? limiter.limit : 80
            await set(selectedStep ?? fallback)
            return
        }
        isSetting = true
        lastError = nil
        defer { isSetting = false }
        limiter.disable()
        state = .unlimited   // optimistic: avoid the toggle snapping back before refresh
        // Shortcuts-only path (macOS 26.4+, no helper): 100% means "no limit".
        if !limiter.installed, capability.platformSupportsSet, let bridge, await bridgeAvailable() {
            do { try await bridge.set(percent: 100) }
            catch { lastError = .failed(error.localizedDescription) }
        }
        await refresh()
    }

    func set(_ percent: Int) async {
        guard ChargeLimitConstants.steps.contains(percent) else { return }
        isSetting = true
        lastError = nil
        defer { isSetting = false }
        do {
            // The user may have just created the shortcut, so force a fresh probe.
            bridgeProbe = nil
            if capability.platformSupportsSet, let bridge, await bridgeAvailable() {
                try await bridge.set(percent: percent)
                // Keep the helper in sync too: on CHIE machines a stale helper limit
                // would keep cutting AC even though the system limit changed.
                if limiter.installed {
                    if limiter.enabled { limiter.setLimit(percent) } else { await limiter.enable(limit: percent) }
                }
                // Shortcuts URL scheme does not return a result synchronously; give the
                // system a moment and refresh from the source of truth.
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            } else if limiter.installed {
                if limiter.enabled { limiter.setLimit(percent) } else { await limiter.enable(limit: percent) }
            } else {
                lastError = .failed(L10n.t(.errHelperNotInstalled))
                return
            }
            await refresh()
        } catch {
            lastError = .failed(error.localizedDescription)
            await refresh()
        }
    }

    /// Called from the sample stream so the panel can warn without waiting for
    /// the helper's 10-second state file.
    func updateSystemHold(suspected: Bool) {
        guard suspected else {
            systemHoldSince = nil
            if systemHoldSuspected { systemHoldSuspected = false }
            return
        }
        if systemHoldSince == nil { systemHoldSince = Date() }
        let elapsed = Date().timeIntervalSince(systemHoldSince ?? Date())
        let value = elapsed >= 30
        if systemHoldSuspected != value { systemHoldSuspected = value }
    }

    func setSailingMode(_ value: Bool) {
        limiter.setSailingMode(value)
    }

    func setDischarge(_ value: Bool) {
        limiter.setDischarge(value)
    }

    /// Top-up needs the SMC helper and only makes sense below 100%.
    var isTopUpAvailable: Bool {
        guard limiter.installed else { return false }
        if case .limited(let n) = state { return n < 100 }
        return false
    }

    /// One-shot "charge to 100% now" toggle.
    func toggleTopUp() async {
        if limiter.topUpRequested {
            limiter.cancelTopUp()
        } else if !limiter.requestTopUp() {
            lastError = .failed(L10n.t(.errHelperNotInstalled))
        }
        isTopUpActive = limiter.topUpRequested
        await refresh()
    }

    // MARK: UI mode

    var uiMode: ChargeLimitUIMode {
        switch state {
        case .unsupported:
            return .hidden
        case .unknown:
            return .loading
        case .unlimited:
            // 제한이 꺼진 상태라도 앱 내 제어가 가능하면(헬퍼 설치됨) 바로 다시 설정 가능.
            if capability.canSetInApp { return .control }
            // macOS 26.4+ 네이티브 설정은 시스템 설정 앱에서만 toggling 가능.
            return capability.platformSupportsSet ? .enableInSystem : .deepLinkOnly
        case .limited(let n):
            _ = n
            if capability.canSetInApp { return .control }
            if capability.platformSupportsSet { return .onboarding }
            return .deepLinkOnly
        }
    }

    var selectedStep: Int? {
        if case .limited(let n) = state, ChargeLimitConstants.steps.contains(n) { return n }
        return nil
    }

    /// Drives the explicit on/off switch in the panel.
    var isLimitEnabled: Bool {
        if case .unlimited = state { return false }
        return true
    }

    /// Discharge needs the SMC CHIE key. Until the daemon reports, assume it works.
    var dischargeUnsupported: Bool {
        guard let status = helperStatus, !status.isStale else { return false }
        return !status.chieAvailable
    }

    /// Helper installed but not publishing state -> show a "not responding" hint.
    var helperUnresponsive: Bool {
        guard limiter.installed else { return false }
        guard let status = helperStatus else { return true }
        return status.isStale
    }

    /// Human-readable pause reason, or nil when nothing notable is happening.
    var reasonKey: LKey? {
        guard let status = helperStatus, !status.isStale else { return nil }
        switch status.reason {
        case .limit:
            // CHIE fallback: the daemon cuts AC power instead of holding the charge.
            return status.actuator == "CHIE" ? .reasonLimitAdapterOff : .reasonLimit
        case .heat: return .reasonHeat
        case .calibration: return .reasonCalibration
        case .topUp: return .reasonTopUp
        case .discharge: return .reasonDischarge
        case .adapterOff: return .reasonAdapterOff
        case .systemHold: return .reasonSystemHold
        case .charging, .off, .noBattery: return nil
        }
    }

    var currentValueText: String {
        switch state {
        case .limited(let n): return "\(n)%"
        case .unlimited: return L10n.t(.off)
        case .unknown, .unsupported: return "—"
        }
    }

    func openSystemBatterySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Battery-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.battery",
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
        if let url = URL(string: "x-apple.systempreferences:") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Capability

    static func computeCapability(bridgeConfigured: Bool, helperInstalled: Bool) -> ChargeLimitCapability {
        let osOK = ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0)
        )
        let platformSupportsSet = osOK && isAppleSiliconHardware()
        let canSetInApp = helperInstalled || (platformSupportsSet && bridgeConfigured)
        return ChargeLimitCapability(
            canRead: true,
            platformSupportsSet: platformSupportsSet,
            bridgeConfigured: bridgeConfigured,
            canSetInApp: canSetInApp
        )
    }

    /// Apple Silicon 여부 (sysctl 로 판정 - Rosetta 바이너리 오탐 방지).
    private static func isAppleSiliconHardware() -> Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return result == 0 && value == 1
    }
}
