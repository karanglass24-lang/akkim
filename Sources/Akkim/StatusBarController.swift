// Portions of this file are derived from ChargeWatching
// (https://github.com/TY-teo/ChargeWatching), MIT License,
// Copyright (c) 2026 TY-teo. See LICENSE and THIRD-PARTY-NOTICES.md.

import AppKit
import SwiftUI
import Combine
import UserNotifications

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let stream: SampleStream
    private let chargeLimit: ChargeLimitController
    private let settings: AppSettings
    private let healthHistory: BatteryHealthHistory
    private let energyUsage: EnergyUsageStore
    private let onQuit: () -> Void
    private let onOpenSettings: () -> Void
    private var bag: Set<AnyCancellable> = []
    private var eventMonitor: Any?
    private var lastNotifiedStatus: BatteryStatus?
    private var lastNotifiedReason: HelperStatus.Reason?
    private var lastNotificationDate: Date?
    /// 동일한 종류의 알림이 너무 자주 울리지 않도록 최소 간격(초)을 둡니다.
    private let notificationMinInterval: TimeInterval = 60

    init(stream: SampleStream, chargeLimit: ChargeLimitController, settings: AppSettings, healthHistory: BatteryHealthHistory, energyUsage: EnergyUsageStore, onQuit: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        self.stream = stream
        self.chargeLimit = chargeLimit
        self.settings = settings
        self.healthHistory = healthHistory
        self.energyUsage = energyUsage
        self.onQuit = onQuit
        self.onOpenSettings = onOpenSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = settings.showMenuBarIcon
        self.popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        super.init()
        // `self` cannot be used as a value before `super.init()`.
        popover.delegate = self

        let panel = MenuBarPanel(onQuit: onQuit, onOpenSettings: onOpenSettings)
            .environmentObject(stream)
            .environmentObject(chargeLimit)
            .environmentObject(settings)
            .environmentObject(healthHistory)
            .environmentObject(energyUsage)
        let hosting = NSHostingController(rootView: panel)
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        configureButton()
        observeStream()
        observeSettings()
        Task { await self.chargeLimit.refresh() }
    }

    /// 설정 변경(메뉴바 아이콘 표시 여부 / 표시 항목)을 반영합니다.
    private func observeSettings() {
        settings.$showMenuBarIcon
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in
                self?.statusItem.isVisible = visible
            }
            .store(in: &bag)

        settings.$menuBarDisplay
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.applyDisplay(sample: self.stream.latest)
            }
            .store(in: &bag)

        settings.$menuBarIconStyle
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.applyDisplay(sample: self.stream.latest)
            }
            .store(in: &bag)
    }

    func popoverWillShow(_ notification: Notification) {
        chargeLimit.startPolling()
    }

    func popoverDidClose(_ notification: Notification) {
        chargeLimit.stopPolling()
    }

    #if DEBUG
    /// Opens the popover so the app can snapshot its own view for documentation.
    func openPopoverForCapture() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.layoutSubtreeIfNeeded()
    }

    var popoverContentView: NSView? {
        popover.contentViewController?.view
    }

    /// Re-fit the popover after content height changes (documentation capture).
    func resizePopoverToFitContent() {
        guard let view = popover.contentViewController?.view else { return }
        view.layoutSubtreeIfNeeded()
        let height = max(view.fittingSize.height, 200)
        popover.contentSize = NSSize(width: 360, height: height)
        view.layoutSubtreeIfNeeded()
    }
    #endif

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        _ = button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageLeft
        applyDisplay(sample: nil)
    }

    private func observeStream() {
        stream.$latest
            .receive(on: RunLoop.main)
            .sink { [weak self] sample in
                guard let self else { return }
                self.applyDisplay(sample: sample)
                if let sample {
                    self.notifyIfNeeded(sample: sample)
                    self.healthHistory.record(sample)
                    self.energyUsage.record(sample)
                }
            }
            .store(in: &bag)
    }

    // MARK: Menu bar display

    private func applyDisplay(sample: PowerSample?) {
        guard let button = statusItem.button else { return }
        let mode = settings.menuBarDisplay
        button.image = MenuBarIcon.image(for: sample, style: settings.menuBarIconStyle)
        button.imagePosition = .imageLeft

        guard mode != .iconOnly else {
            button.attributedTitle = NSAttributedString(string: "")
            return
        }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let text: String
        switch mode {
        case .power:
            text = powerTitle(for: sample)
        case .percent:
            text = sample?.stateOfChargePercent.map { "\($0)%" } ?? "--"
        case .temperature:
            text = sample?.temperatureCelsius.map { String(format: "%.1f°C", $0) } ?? "--"
        case .iconOnly:
            text = ""
        }
        button.attributedTitle = NSAttributedString(string: " " + text, attributes: [.font: font])
    }

    private func powerTitle(for sample: PowerSample?) -> String {
        guard let s = sample else { return "--" }
        switch s.status {
        case .charging:
            return String(format: "%.1f W", abs(s.batteryWatts))
        case .acPaused:
            return s.stateOfChargePercent.map { "AC · \($0)%" } ?? "AC"
        case .discharging:
            return s.stateOfChargePercent.map { "\($0)%" } ?? "--"
        case .desktop:
            return s.systemLoadWatts.map { String(format: "%.0f W", $0) } ?? "--"
        }
    }

    // MARK: Right-click quick actions

    @objc private func statusItemClicked(_ sender: AnyObject?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showQuickMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func showQuickMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()

        for step in ChargeLimitConstants.steps {
            let item = NSMenuItem(title: "\(step)%", action: #selector(quickLimit(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: step)
            item.state = (chargeLimit.selectedStep == step) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let offItem = NSMenuItem(title: L10n.t(.off), action: #selector(quickDisableLimit(_:)), keyEquivalent: "")
        offItem.target = self
        offItem.state = chargeLimit.isLimitEnabled ? .off : .on
        menu.addItem(offItem)

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: L10n.t(.settings), action: #selector(openSettings(_:)), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: L10n.t(.quitApp), action: #selector(quitApp(_:)), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        _ = menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func quickLimit(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? NSNumber else { return }
        Task { await self.chargeLimit.set(value.intValue) }
    }

    @objc private func quickDisableLimit(_ sender: NSMenuItem) {
        Task { await self.chargeLimit.setLimitEnabled(false) }
    }

    @objc private func openSettings(_ sender: NSMenuItem) {
        onOpenSettings()
    }

    @objc private func quitApp(_ sender: NSMenuItem) {
        onQuit()
    }

    // MARK: Notifications

    private func notifyIfNeeded(sample: PowerSample) {
        let newStatus = sample.status
        let statusChanged = lastNotifiedStatus != newStatus
        // Remember the transition even while notifications are muted, so turning
        // them back on does not replay an old state change.
        lastNotifiedStatus = newStatus

        guard settings.notificationsEnabled else { return }

        // A specific reason (limit reached / heat / top-up done) wins over the
        // generic "charging stopped" message.
        if postReasonNotificationIfNeeded() { return }

        guard statusChanged else { return }

        // 디바운스: 같은 상태 변경 알림이 너무 자주 울리지 않도록 최소 간격을 둡니다.
        if isThrottled() { return }
        lastNotificationDate = Date()

        switch newStatus {
        case .charging:
            postNotification(
                title: L10n.t(.chargingStartedTitle),
                body: String(format: L10n.t(.chargingStartedBody), sample.batteryWatts)
            )
        case .acPaused, .discharging:
            let level = sample.stateOfChargePercent.map { "\($0)%" } ?? L10n.t(.theLimit)
            postNotification(
                title: L10n.t(.chargingStoppedTitle),
                body: String(format: L10n.t(.chargingStoppedBody), level)
            )
        case .desktop:
            break
        }
    }

    /// Posts a notification only when the daemon's reason changes to something
    /// worth telling the user about. Returns true when a notification was posted.
    private func postReasonNotificationIfNeeded() -> Bool {
        guard let status = HelperStatus.readCached(), !status.isStale else { return false }
        let reason = status.reason

        guard let previous = lastNotifiedReason else {
            // First observation after launch: adopt it silently.
            lastNotifiedReason = reason
            return false
        }
        guard previous != reason else { return false }
        lastNotifiedReason = reason

        guard !isThrottled() else { return false }

        let soc = status.soc ?? 0
        switch reason {
        case .limit where previous == .topUp && soc >= 99:
            lastNotificationDate = Date()
            postNotification(
                title: L10n.t(.notifyTopUpDoneTitle),
                body: L10n.t(.notifyTopUpDoneBody)
            )
            return true
        case .heat:
            lastNotificationDate = Date()
            let temp = status.temperatureCelsius ?? 0
            postNotification(
                title: L10n.t(.notifyHeatTitle),
                body: String(format: L10n.t(.notifyHeatBody), temp)
            )
            return true
        case .limit where previous == .charging:
            lastNotificationDate = Date()
            postNotification(
                title: L10n.t(.notifyLimitReachedTitle),
                body: String(format: L10n.t(.notifyLimitReachedBody), soc)
            )
            return true
        default:
            return false
        }
    }

    private func isThrottled() -> Bool {
        if let last = lastNotificationDate, Date().timeIntervalSince(last) < notificationMinInterval {
            return true
        }
        return false
    }

    private func postNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    // MARK: Popover

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
            stopEventMonitor()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            startEventMonitor()
        }
    }

    private func startEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover.performClose(nil)
            self?.stopEventMonitor()
        }
    }

    private func stopEventMonitor() {
        if let m = eventMonitor {
            NSEvent.removeMonitor(m)
            eventMonitor = nil
        }
    }
}
