// Portions of this file are derived from ChargeWatching
// (https://github.com/TY-teo/ChargeWatching), MIT License,
// Copyright (c) 2026 TY-teo. See LICENSE and THIRD-PARTY-NOTICES.md.

import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let container: AppContainer
    private var statusBarController: StatusBarController?
    private var settingsWindow: NSWindow?

    override init() {
        self.container = AppContainer()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted {
                print("Notification authorization granted")
            }
        }
        container.start()

        container.chargeLimitController.onOpenOnboarding = { [weak self] in
            self?.showOnboarding()
        }

        statusBarController = StatusBarController(
            stream: container.sampleStream,
            chargeLimit: container.chargeLimitController,
            settings: container.settings,
            healthHistory: container.healthHistory,
            energyUsage: container.energyUsage,
            onQuit: { NSApp.terminate(nil) },
            onOpenSettings: { [weak self] in self?.openSettings() }
        )

        #if DEBUG
        if CommandLine.arguments.contains("--screenshot") {
            container.healthHistory.seedPreviewData()
            container.energyUsage.seedPreviewData()
            scheduleDocsScreenshot()
        }
        #endif
    }

    #if DEBUG
    /// Development helper: open the popover, snapshot it, then quit.
    /// Used to produce the README screenshots without screen-recording permission.
    private func scheduleDocsScreenshot() {
        // Let the power sampler and helper state settle before snapshotting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self else { return }
            self.statusBarController?.openPopoverForCapture()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                self.statusBarController?.resizePopoverToFitContent()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if let view = self.statusBarController?.popoverContentView {
                        self.writeSnapshot(of: view, to: "/private/var/tmp/akkim-panel.png")
                    }
                    // Capture the settings window in light appearance: the dark
                    // window material is not included in a view snapshot.
                    NSApp.appearance = NSAppearance(named: .aqua)
                    self.openSettings()
                    if let window = self.settingsWindow {
                        // The snapshot does not include the window material, so force
                        // a light appearance with an opaque background for the capture.
                        window.appearance = NSAppearance(named: .aqua)
                        window.backgroundColor = .white
                        window.contentView?.wantsLayer = true
                        window.contentView?.layer?.backgroundColor = NSColor.white.cgColor
                        window.displayIfNeeded()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if let view = self.settingsWindow?.contentView {
                            self.writeSnapshot(of: view, to: "/private/var/tmp/akkim-settings.png")
                        }
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }

    private func writeSnapshot(of view: NSView, to path: String) {
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    #endif

    /// macOS 26.4+ 네이티브 경로에서 Shortcuts 액션을 안내합니다.
    private func showOnboarding() {
        let alert = NSAlert()
        alert.messageText = L10n.t(.setupRequiredTitle)
        alert.informativeText = L10n.t(.setupRequiredBody)
        alert.addButton(withTitle: L10n.t(.openShortcuts))
        alert.addButton(withTitle: L10n.t(.openSystemSettings))
        alert.addButton(withTitle: L10n.t(.cancel))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if let url = URL(string: "shortcuts://") { NSWorkspace.shared.open(url) }
        case .alertSecondButtonReturn:
            container.chargeLimitController.openSystemBatterySettings()
        default:
            break
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        container.stop()
        container.energyUsage.flush()
        // The helper daemon keeps enforcing the last config after the app quits.
        // Turning the limit off here made the toggle look like it disabled itself
        // on every restart; the user can turn it off explicitly instead.
    }

    private func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
                .environmentObject(container.settings)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 700),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.contentView = NSHostingView(rootView: settingsView)
            window.title = L10n.t(.settings)
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
