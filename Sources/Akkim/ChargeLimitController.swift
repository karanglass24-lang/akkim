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
        canRead: false, platformSupportsSet: false, bridgeConfigured: false,
        systemControl: false, canSetInApp: false)
    /// macOS's own Charge Limit as reported by the system (nil when unsupported).
    @Published private(set) var systemLimit: Int?
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

        // macOS 26.4+ exposes its Charge Limit directly through PowerUI; prefer
        // that over the Shortcuts bridge (no setup required).
        capability = Self.computeCapability(
            bridgeConfigured: await bridgeAvailable(),
            helperInstalled: installed,
            systemControl: SystemChargeLimit.isAvailable)

        // 보정 상태 갱신
        calibrationStatus = limiter.readCalibrationStatus()

        // Derive once before the daemon sync (so reconcile sees a fresh app
        // limit) and once after (it may have moved the system limit).
        recomputeState(installed: installed, enabled: enabled, limit: limit)
        refreshHelperStatus()
        recomputeState(installed: installed, enabled: enabled, limit: limit)
    }

    /// Without the helper the system Charge Limit is the only actuator, so it
    /// alone decides whether a limit is active. (Before 1.7.2 `state` was
    /// derived from the helper only, which made the toggle snap back off on
    /// machines where the helper was never installed.)
    private func recomputeState(installed: Bool, enabled: Bool, limit: Int) {
        if capability.systemControl, let systemLimit, systemLimit < 100 {
            state = .limited(systemLimit)
        } else {
            state = (enabled && installed) ? .limited(limit) : .unlimited
        }
    }

    /// Reads the daemon's published state (mtime-cached) and reconciles local flags.
    /// Safe to call often: `HelperStatus.readCached()` only parses when the file changed.
    func refreshHelperStatus() {
        let status = HelperStatus.readCached()
        helperStatus = status
        isTopUpActive = limiter.topUpRequested

        if let status, !status.isStale {
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

        // Runs even without a helper: the system Charge Limit is the only
        // actuator on machines where the helper was never installed, so it must
        // be read and published here.
        reconcileSystemLimit()
    }

    /// Keeps macOS's own Charge Limit from fighting the app.
    ///
    /// - a top-up or calibration raises it to 100%, and it comes back by itself
    ///   when the daemon finishes (no bookkeeping needed),
    /// - otherwise the system limit follows the app's limit, so powerd can never
    ///   hold charging below what the app allows,
    /// - when the app limit is off the system value is left alone.
    private func reconcileSystemLimit() {
        guard SystemChargeLimit.isAvailable, let current = SystemChargeLimit.currentLimit() else {
            systemLimit = nil
            return
        }
        systemLimit = current

        let fresh = helperStatus.map { !$0.isStale } ?? false
        let daemonNeedsFull = fresh && (helperStatus?.reason == .topUp || helperStatus?.reason == .calibration)
        let needsFull = isTopUpActive || daemonNeedsFull

        var desired: Int?
        if needsFull {
            desired = 100
        } else if case .limited(let appLimit) = state {
            desired = appLimit
        }
        guard let desired, desired != current, ChargeLimitConstants.steps.contains(desired) else { return }
        do {
            try SystemChargeLimit.setLimit(desired)
            systemLimit = desired
        } catch {
            // powerd can be briefly busy; the next refresh retries.
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

    /// Clears the cached Shortcuts probe (e.g. after creating a shortcut).
    func recheckBridge() async {
        bridgeProbe = nil
        await refresh()
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
        // 100% means "no limit" for both the system Charge Limit and Shortcuts.
        if capability.systemControl {
            do { try SystemChargeLimit.setLimit(100) }
            catch { lastError = .failed(error.localizedDescription) }
        } else if !limiter.installed, capability.platformSupportsSet, let bridge, await bridgeAvailable() {
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

            // 1) Direct system control (macOS 26.4+, no Shortcuts setup).
            // 2) Shortcuts bridge.
            // 3) SMC helper. Each step falls back to the next one: the direct
            //    API can be refused on machines where the helper works fine.
            let useSystem = capability.systemControl
            var useBridge = false
            if !useSystem, capability.platformSupportsSet {
                useBridge = await bridgeAvailable()
            }

            var handled = false
            var helperHandled = false
            var systemError: Error?

            if useSystem {
                do {
                    try SystemChargeLimit.setLimit(percent)
                    handled = true
                } catch {
                    systemError = error
                }
            }

            if !handled, useBridge, let bridge {
                try await bridge.set(percent: percent)
                handled = true
            }

            if !handled, limiter.installed {
                if limiter.enabled {
                    limiter.setLimit(percent)
                } else {
                    await limiter.enable(limit: percent)
                }
                helperHandled = true
                handled = true
            }

            guard handled else {
                lastError = .failed(L10n.t(.errHelperNotInstalled))
                return
            }

            // When the system limit moved, keep the helper's own limit aligned:
            // on CHIE machines a stale helper limit would keep cutting AC.
            if useSystem, !helperHandled, limiter.installed {
                if limiter.enabled {
                    limiter.setLimit(percent)
                } else {
                    await limiter.enable(limit: percent)
                }
            }
            // Shortcuts has no synchronous result; give the system a moment and
            // refresh from the source of truth. The direct call is synchronous
            // but powerd still needs a beat to apply the new limit.
            try? await Task.sleep(nanoseconds: useBridge ? 1_500_000_000 : 400_000_000)

            // Surface a direct-control failure without hiding that the helper
            // may have taken over.
            if let systemError {
                lastError = .failed(systemError.localizedDescription)
            }
            await refresh()
        } catch {
            lastError = .failed(error.localizedDescription)
            await refresh()
        }
    }

    /// Brings macOS's own Charge Limit back in line with this app's limit.
    /// Only meaningful when the direct system control is available.
    func syncSystemLimit() async {
        guard capability.systemControl else { return }
        let target: Int
        if case .limited(let n) = state { target = n } else { target = 100 }
        do {
            try SystemChargeLimit.setLimit(target)
        } catch {
            lastError = .failed(error.localizedDescription)
        }
        try? await Task.sleep(nanoseconds: 400_000_000)
        await refresh()
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

    static func computeCapability(
        bridgeConfigured: Bool,
        helperInstalled: Bool,
        systemControl: Bool
    ) -> ChargeLimitCapability {
        let osOK = ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0)
        )
        let platformSupportsSet = osOK && isAppleSiliconHardware()
        // Direct system control needs no helper and no Shortcuts.
        let canSetInApp = helperInstalled || systemControl || (platformSupportsSet && bridgeConfigured)
        return ChargeLimitCapability(
            canRead: true,
            platformSupportsSet: platformSupportsSet,
            bridgeConfigured: bridgeConfigured,
            systemControl: systemControl,
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
