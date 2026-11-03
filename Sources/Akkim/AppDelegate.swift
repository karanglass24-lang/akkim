// Portions of this file are derived from ChargeWatching
// (https://github.com/TY-teo/ChargeWatching), MIT License,
// Copyright (c) 2026 TY-teo. See LICENSE and THIRD-PARTY-NOTICES.md.

import AppKit
import SwiftUI

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
        container.start()

        container.chargeLimitController.onOpenOnboarding = { [weak self] in
            self?.showOnboarding()
        }

        statusBarController = StatusBarController(
            stream: container.sampleStream,
            chargeLimit: container.chargeLimitController,
            settings: container.settings,
            healthHistory: container.healthHistory,
            onQuit: { NSApp.terminate(nil) },
            onOpenSettings: { [weak self] in self?.openSettings() }
        )
    }

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
        // On exit, restore normal charging via the helper (fail-safe).
        if container.smcLimiter.installed {
            container.smcLimiter.cancelTopUp()
            container.smcLimiter.disable()
        }
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
