// Portions of this file are derived from ChargeWatching
// (https://github.com/TY-teo/ChargeWatching), MIT License,
// Copyright (c) 2026 TY-teo. See LICENSE and THIRD-PARTY-NOTICES.md.

import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var chargeLimit: ChargeLimitController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                tabContent
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            footer
        }
        .frame(width: 420, height: 700)
        .onAppear {
            Task { await chargeLimit.recheckBridge() }
        }
        .onChange(of: settings.launchAtLogin) { _ in
            settings.applyLaunchAtLogin()
        }
        .onChange(of: settings.menuBarDisplay) { _ in
            settings.save()
        }
        .onChange(of: settings.menuBarIconStyle) { _ in
            settings.save()
        }
        .onChange(of: settings.heatProtectionC) { _ in
            settings.save()
        }
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t(.settings))
                .font(.title2.weight(.semibold))

            Picker("", selection: $settings.settingsTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(L10n.t(tab.titleKey)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            Text("아낌 (Akkim) · MIT License")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button(L10n.t(.done)) {
                settings.save()
                NSApp.keyWindow?.performClose(nil)
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    // MARK: - Tabs

    @ViewBuilder
    private var tabContent: some View {
        switch settings.settingsTab {
        case .general:
            VStack(alignment: .leading, spacing: 20) {
                notificationsBox
                generalBox
            }
        case .charging:
            VStack(alignment: .leading, spacing: 20) {
                systemLimitBox
                calibrationBox
                chargeBehaviorBox
                heatProtectionBox
            }
        case .panel:
            VStack(alignment: .leading, spacing: 20) {
                panelSectionsBox
            }
        case .about:
            VStack(alignment: .leading, spacing: 20) {
                aboutBox
            }
        }
    }

    // MARK: - General

    private var notificationsBox: some View {
        GroupBox(L10n.t(.notifications)) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(L10n.t(.chargingStateNotifications), isOn: $settings.notificationsEnabled)
                Text(L10n.t(.notificationsDetail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var generalBox: some View {
        GroupBox(L10n.t(.general)) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(L10n.t(.launchAtLogin), isOn: $settings.launchAtLogin)
                Text(L10n.t(.launchAtLoginDetail))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(L10n.t(.showMenuBarIcon), isOn: $settings.showMenuBarIcon)
                Text(L10n.t(.showMenuBarIconDetail))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text(L10n.t(.menuBarDisplay))
                    Spacer()
                    Picker("", selection: $settings.menuBarDisplay) {
                        ForEach(MenuBarDisplay.allCases) { display in
                            Text(L10n.t(display.titleKey)).tag(display)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }

                HStack {
                    Text(L10n.t(.menuBarIconStyle))
                    Spacer()
                    Picker("", selection: $settings.menuBarIconStyle) {
                        ForEach(MenuBarIconStyle.allCases) { style in
                            Text(L10n.t(style.titleKey)).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }
            }
        }
    }

    // MARK: - Charging

    private var systemLimitBox: some View {
        GroupBox(L10n.t(.systemLimit)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: chargeLimit.capability.bridgeConfigured
                          ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(chargeLimit.capability.bridgeConfigured ? .green : .orange)
                    Text(chargeLimit.capability.bridgeConfigured
                         ? L10n.t(.systemLimitLinked)
                         : L10n.t(.systemLimitNotLinked))
                    Spacer()
                    Button(L10n.t(.recheck)) {
                        Task { await chargeLimit.recheckBridge() }
                    }
                    .font(.caption)
                }
                Text(L10n.t(.systemLimitDetail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !chargeLimit.capability.bridgeConfigured {
                    Text(L10n.t(.systemLimitSteps))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button(L10n.t(.openShortcutsApp)) {
                        if let url = URL(string: "shortcuts://") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
    }

    private var calibrationBox: some View {
        GroupBox(L10n.t(.calibration)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.t(.fullChargeCalibration))
                    Spacer()
                    Picker("", selection: $settings.calibrationDays) {
                        ForEach([0, 7, 14, 30, 60], id: \.self) { days in
                            Text(days == 0 ? L10n.t(.off) : String(format: L10n.t(.days), days)).tag(days)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
                Text(L10n.t(.calibrationDetail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var chargeBehaviorBox: some View {
        GroupBox(L10n.t(.chargeLimitBehavior)) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(L10n.t(.sailingModeLong), isOn: Binding(
                    get: { settings.sailingMode },
                    set: { newValue in
                        settings.sailingMode = newValue
                        settings.save()
                    }
                ))
                Text(L10n.t(.sailingModeLongDetail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var heatProtectionBox: some View {
        GroupBox(L10n.t(.heatProtection)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.t(.heatPauseAt))
                    Spacer()
                    Picker("", selection: $settings.heatProtectionC) {
                        ForEach([0, 30, 35, 40, 45, 50, 55, 60], id: \.self) { celsius in
                            Text(celsius == 0 ? L10n.t(.off) : "\(celsius)°C").tag(celsius)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
                Text(L10n.t(.heatProtectionDetail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Panel

    private var panelSectionsBox: some View {
        GroupBox(L10n.t(.panelSections)) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(PanelSection.allCases) { section in
                    Toggle(isOn: Binding(
                        get: { settings.isSectionVisible(section) },
                        set: { settings.setSectionVisible(section, $0) }
                    )) {
                        Text(L10n.t(section.titleKey))
                    }
                }
                Text(L10n.t(.panelSectionsDetail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - About

    private var aboutBox: some View {
        GroupBox(L10n.t(.about)) {
            VStack(alignment: .leading, spacing: 10) {
                Text("아낌 (Akkim)")
                    .font(.headline)
                Text(String(format: L10n.t(.versionFormat), appVersion, buildNumber))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Link("GitHub",
                     destination: URL(string: "https://github.com/karanglass24-lang/akkim")!)
                Link(L10n.t(.manual),
                     destination: URL(string: "https://github.com/karanglass24-lang/akkim/blob/main/docs/MANUAL.md")!)

                Text("MIT License · derived from ChargeWatching (MIT)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "—"
    }

    private var buildNumber: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "—"
    }
}
