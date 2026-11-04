// Portions of this file are derived from ChargeWatching
// (https://github.com/TY-teo/ChargeWatching), MIT License,
// Copyright (c) 2026 TY-teo. See LICENSE and THIRD-PARTY-NOTICES.md.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MenuBarPanel: View {
    @EnvironmentObject private var stream: SampleStream
    @EnvironmentObject private var chargeLimit: ChargeLimitController
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var healthHistory: BatteryHealthHistory
    @EnvironmentObject private var energyUsage: EnergyUsageStore
    @EnvironmentObject private var updater: UpdateChecker
    let onQuit: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider()
            panelTabPicker
            Divider()

            switch settings.panelTab {
            case .charge:
                let chargeVisible = settings.isSectionVisible(.limit)
                    || settings.isSectionVisible(.power)
                if chargeVisible {
                    if settings.isSectionVisible(.limit) {
                        chargeLimitSection
                        Divider()
                    }
                    if settings.isSectionVisible(.power) {
                        metricsSection
                        Divider()
                    }
                } else {
                    sectionsHiddenHint
                }
            case .monitor:
                let monitorVisible = settings.isSectionVisible(.energy)
                    || settings.isSectionVisible(.health)
                    || settings.isSectionVisible(.history)
                if monitorVisible {
                    if settings.isSectionVisible(.energy) {
                        energySection
                        Divider()
                    }
                    if settings.isSectionVisible(.health) {
                        batteryHealthSection
                        Divider()
                    }
                    if settings.isSectionVisible(.history) {
                        historySection
                        Divider()
                    }
                } else {
                    sectionsHiddenHint
                }
            }

            footerSection
        }
        .frame(width: 360)
        .akkimPanelBackdrop()
    }

    private var panelTabPicker: some View {
        Picker("", selection: $settings.panelTab) {
            ForEach(PanelTab.allCases) { tab in
                Text(L10n.t(tab.titleKey)).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var sectionsHiddenHint: some View {
        Text(L10n.t(.sectionsHiddenHint))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            BatteryGaugeView(
                percentage: stream.latest?.stateOfChargePercent,
                isCharging: stream.latest?.isCharging ?? false,
                size: 64
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(stream.latest?.status.displayName ?? L10n.t(.unknown))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)

                Text(headline)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()

                if let reason = reasonText {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                        Text(reason)
                            .lineLimit(1)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                } else if chargeLimit.helperUnresponsive {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                        Text(L10n.t(.helperNotResponding))
                            .lineLimit(1)
                    }
                    .font(.caption2)
                    .foregroundStyle(.orange)
                }
            }

            Spacer()

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.t(.settings))
        }
        .padding(16)
    }

    private var headline: String {
        guard let s = stream.latest else { return "--" }
        switch s.status {
        case .charging:
            return String(format: "%.1f W", s.batteryWatts)
        case .acPaused:
            return s.stateOfChargePercent.map { "AC · \($0)%" } ?? "AC"
        case .discharging:
            return s.stateOfChargePercent.map { String(format: L10n.t(.batteryPercent), $0) } ?? L10n.t(.dischargingShort)
        case .desktop:
            return s.systemLoadWatts.map { String(format: L10n.t(.systemWatts), $0) } ?? "AC"
        }
    }

    /// Reason line under the headline, e.g. "Holding at the limit · 80%".
    private var reasonText: String? {
        guard let key = chargeLimit.reasonKey else { return nil }
        let base = L10n.t(key)
        switch key {
        case .reasonLimit, .reasonLimitAdapterOff:
            return chargeLimit.helperStatus.map { "\(base) · \($0.limit)%" } ?? base
        case .reasonHeat:
            if let t = chargeLimit.helperStatus?.temperatureCelsius {
                return "\(base) · \(String(format: "%.1f°C", t))"
            }
            return base
        default:
            return base
        }
    }

    // MARK: - Metrics

    /// System-hold warning line: base hint plus the macOS limit we read back.
    private var systemHoldText: String {
        let base = L10n.t(.systemHoldHint)
        guard let sys = chargeLimit.systemLimit else { return base }
        return base + " " + String(format: L10n.t(.systemControlValue), sys)
    }

    /// Section header with a chevron; clicking it collapses the section and the
    /// collapsed state is persisted in `AppSettings`.
    @ViewBuilder
    private func sectionHeader<Accessory: View>(
        _ section: PanelSection,
        title: String,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) -> some View {
        let collapsed = settings.isSectionCollapsed(section)
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                settings.toggleSectionCollapsed(section)
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                accessory()
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, collapsed ? 8 : 2)
        .help(L10n.t(.panelSectionCollapseHelp))
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(.power, title: L10n.t(.power))

            if !settings.isSectionCollapsed(.power) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    MetricCard(
                        icon: "bolt.fill",
                        label: L10n.t((stream.latest?.batteryWatts ?? 0) < -0.5 ? .dischargingShort : .charging),
                        value: stream.latest.map { String(format: "%.1f W", abs($0.batteryWatts)) } ?? "--",
                        color: stream.latest?.status == .charging ? .green : .gray
                    )
                    MetricCard(
                        icon: "powerplug",
                        label: L10n.t(.wallOutput),
                        value: stream.latest.map { String(format: "%.1f W", $0.wallOutputWatts ?? 0) } ?? "--",
                        color: .blue
                    )
                    MetricCard(
                        icon: "cpu",
                        label: L10n.t(.systemLoad),
                        value: stream.latest.map { String(format: "%.1f W", $0.systemLoadWatts ?? 0) } ?? "--",
                        color: .purple
                    )
                    MetricCard(
                        icon: "battery.100",
                        label: L10n.t(.batteryLevel),
                        value: stream.latest.map { "\($0.stateOfChargePercent ?? 0)%" } ?? "--",
                        color: .teal
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Energy

    private var energySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(.energy, title: L10n.t(.energyUsage)) {
                Text(L10n.t(.last14Days))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if !settings.isSectionCollapsed(.energy) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        energyStat(title: L10n.t(.today),
                                   value: energyUsage.total(days: 1, \.wallWh))
                        energyStat(title: L10n.t(.last7Days),
                                   value: energyUsage.total(days: 7, \.wallWh))
                        energyStat(title: L10n.t(.last30Days),
                                   value: energyUsage.total(days: 30, \.wallWh))
                    }

                    HStack(spacing: 8) {
                        Picker("", selection: $settings.energyChartMode) {
                            Text(L10n.t(.last14DaysShort)).tag(AppSettings.EnergyChartMode.days)
                            Text(L10n.t(.today)).tag(AppSettings.EnergyChartMode.hours)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 150)

                        Spacer()

                        Button {
                            exportEnergyCSV()
                        } label: {
                            Label(L10n.t(.exportCSV), systemImage: "square.and.arrow.up")
                                .font(.caption2)
                        }
                        .buttonStyle(.link)
                    }

                    Group {
                        if settings.energyChartMode == .days {
                            EnergyUsageChart(days: energyUsage.series(days: 14))
                        } else {
                            HourlyEnergyChart(values: energyUsage.hourlyToday())
                        }
                    }
                    .frame(height: 56)
                    .clipped()

                    HStack(spacing: 14) {
                        Label("\(L10n.t(.charged)) \(energyText(energyUsage.today(\.chargedWh)))",
                              systemImage: "bolt.fill")
                        Label("\(L10n.t(.discharged)) \(energyText(energyUsage.today(\.dischargedWh)))",
                              systemImage: "battery.50")
                        Spacer()
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    private func energyStat(title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(energyText(value))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .akkimGlass(cornerRadius: 8)
    }

    private func exportEnergyCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "akkim-energy-\(DailyEnergy.formatter.string(from: Date())).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? energyUsage.csvString().write(to: url, atomically: true, encoding: .utf8)
    }

    private func energyText(_ wh: Double) -> String {
        if wh >= 1000 {
            return String(format: "%.2f kWh", wh / 1000)
        }
        return String(format: "%.1f Wh", wh)
    }

    // MARK: - Battery health

    private var batteryHealthSection: some View {
        let health = stream.latest?.batteryHealthPercent
        let trend = healthHistory.window(days: 30)

        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader(.health, title: L10n.t(.battery)) {
                Text(L10n.t(.last30Days))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if !settings.isSectionCollapsed(.health) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(health.map { "\($0)%" } ?? "--")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.pink)
                        Spacer()
                        if let condition = conditionLabel {
                            Text(condition.text)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(condition.color)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(condition.color.opacity(0.12)))
                        }
                    }

                    if trend.isEmpty {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.08))
                            .frame(height: 54)
                            .overlay(
                                Text(L10n.t(.collectingData))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            )
                    } else {
                        BatteryHealthChart(samples: trend)
                            .frame(height: 54)
                            .clipped()
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        StatChip(
                            icon: "battery.100",
                            label: L10n.t(.maximumCapacity),
                            value: capacityText(stream.latest?.maxCapacitymAh),
                            color: .teal
                        )
                        StatChip(
                            icon: "arrow.triangle.2.circlepath",
                            label: L10n.t(.cycles),
                            value: stream.latest?.cycleCount.map { "\($0)" } ?? "--",
                            color: .indigo
                        )
                        StatChip(
                            icon: "ruler",
                            label: L10n.t(.designCapacity),
                            value: capacityText(stream.latest?.designCapacitymAh),
                            color: .blue
                        )
                        StatChip(
                            icon: "thermometer",
                            label: L10n.t(.temp),
                            value: stream.latest?.temperatureCelsius.map { String(format: "%.1f°C", $0) } ?? "--",
                            color: .orange
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    private func capacityText(_ mAh: Int?) -> String {
        guard let mAh else { return "--" }
        return "\(mAh) mAh"
    }

    private var conditionLabel: (text: String, color: Color)? {
        guard let health = stream.latest?.batteryHealthPercent else { return nil }
        return health >= 80
            ? (L10n.t(.conditionNormal), .green)
            : (L10n.t(.conditionService), .orange)
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(.history, title: L10n.t(.batteryPower)) {
                Text(L10n.t(.lastTenMinutes))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if !settings.isSectionCollapsed(.history) {
                HistoryChartView(
                    samples: stream.rolling,
                    limit: chargeLimit.selectedStep,
                    deadband: settings.deadband
                )
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Charge Limit

    private var chargeLimitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(.limit, title: L10n.t(.chargeLimit)) {
                Text(currentLimitText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }

            if !settings.isSectionCollapsed(.limit) {
                VStack(spacing: 10) {
                switch chargeLimit.uiMode {
                case .control:
                    Toggle(L10n.t(.enableChargeLimit), isOn: Binding(
                        get: { chargeLimit.isLimitEnabled },
                        set: { newValue in Task { await chargeLimit.setLimitEnabled(newValue) } }
                    ))
                    .toggleStyle(.switch)
                    .disabled(chargeLimit.isSetting)
                    .padding(.horizontal, 16)

                    Picker(L10n.t(.limit), selection: Binding(
                        get: { chargeLimit.selectedStep },
                        set: { newValue in
                            if let value = newValue {
                                Task { await chargeLimit.set(value) }
                            }
                        }
                    )) {
                        ForEach(ChargeLimitConstants.steps, id: \.self) { step in
                            Text("\(step)%").tag(Optional(step))
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(chargeLimit.isSetting)
                    .padding(.horizontal, 16)

                    Button {
                        Task { await chargeLimit.toggleTopUp() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: chargeLimit.isTopUpActive ? "xmark.circle" : "arrow.up.to.line")
                            Text(L10n.t(chargeLimit.isTopUpActive ? .topUpActive : .topUp))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .akkimGlassButton()
                    .disabled(chargeLimit.isSetting || !chargeLimit.isTopUpAvailable)
                    .help(L10n.t(.topUpHelp))
                    .padding(.horizontal, 16)

                    VStack(spacing: 8) {
                        Toggle(L10n.t(.sailingMode), isOn: Binding(
                            get: { settings.sailingMode },
                            set: { newValue in
                                chargeLimit.setSailingMode(newValue)
                                settings.sailingMode = newValue
                                settings.save()
                            }
                        ))
                        .toggleStyle(.switch)
                        .help(L10n.t(.sailingModeHelp))

                        Toggle(L10n.t(.dischargeToLimit), isOn: Binding(
                            get: { settings.dischargeMode },
                            set: { newValue in
                                chargeLimit.setDischarge(newValue)
                                settings.dischargeMode = newValue
                                settings.save()
                            }
                        ))
                        .toggleStyle(.switch)
                        .disabled(chargeLimit.dischargeUnsupported)
                        .help(L10n.t(.dischargeHelp))

                        if chargeLimit.dischargeUnsupported {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle")
                                Text(L10n.t(.dischargeUnsupported))
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }

                        if settings.heatProtectionC > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "thermometer.medium")
                                Text("\(L10n.t(.heatProtection)) · \(settings.heatProtectionC)°C")
                                Spacer()
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }

                        if settings.heatProtectionC > 0,
                           let status = chargeLimit.helperStatus,
                           !status.isStale,
                           status.temperatureCelsius == nil {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle")
                                Text(L10n.t(.heatUnavailable))
                                Spacer()
                            }
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        }

                        calibrationRow
                    }
                    .padding(.horizontal, 16)

                case .enableInSystem:
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.t(.useSystemSettings))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(L10n.t(.openSystemSettings)) {
                            chargeLimit.openSystemBatterySettings()
                        }
                        .buttonStyle(.link)
                    }
                    .padding(.horizontal, 16)

                case .onboarding:
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.t(.oneTimeSetup))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(L10n.t(.openOnboarding)) {
                            chargeLimit.onOpenOnboarding?()
                        }
                        .buttonStyle(.link)
                    }
                    .padding(.horizontal, 16)

                case .deepLinkOnly, .permissionDenied, .hidden, .loading:
                    EmptyView()
                }

                if let error = chargeLimit.lastError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .padding(.horizontal, 16)
                }

                if chargeLimit.helperStatus?.reason == .systemHold || chargeLimit.systemHoldSuspected {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(systemHoldText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack(spacing: 12) {
                            if chargeLimit.capability.systemControl {
                                Button(L10n.t(.syncSystemLimit)) {
                                    Task { await chargeLimit.syncSystemLimit() }
                                }
                                .buttonStyle(.link)
                                .font(.caption2)
                            }
                            Button(L10n.t(.openSystemSettings)) {
                                chargeLimit.openSystemBatterySettings()
                            }
                            .buttonStyle(.link)
                            .font(.caption2)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                }
                .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private var calibrationRow: some View {
        if let cal = chargeLimit.calibrationStatus {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(calibrationText(cal))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private func calibrationText(_ cal: CalibrationStatus) -> String {
        if cal.isDisabled {
            return L10n.t(.calibrationOff)
        }
        if cal.lastFullChargeDate == nil {
            return String(format: L10n.t(.calibrationEveryNoRecord), cal.calibrationIntervalDays)
        }
        if cal.isDue {
            return L10n.t(.calibrationDue)
        }
        return String(format: L10n.t(.calibrationIn), cal.daysUntilCalibration)
    }

    private var currentLimitText: String {
        switch chargeLimit.state {
        case .limited(let n): return "\(n)%"
        case .unlimited: return L10n.t(.off)
        case .unknown, .unsupported: return "—"
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: 12) {
            Button(action: onQuit) {
                Text(L10n.t(.quitApp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            // Tap → Settings › About, where the update can be installed.
            if updater.isUpdateAvailable, let version = updater.availableVersion {
                Button {
                    settings.settingsTab = .about
                    onOpenSettings()
                } label: {
                    Text("\(version) \(L10n.t(.update))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help(String(format: L10n.t(.updateAvailableFormat), version))
            }

            Button(action: onOpenSettings) {
                Text(L10n.t(.settings))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
    }
}

// MARK: - Supporting Views

private struct MetricCard: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .akkimGlass(cornerRadius: 8)
    }
}

private struct StatChip: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .akkimGlass(cornerRadius: 8)
    }
}

/// macOS 비주얼 효과 뷰 (투명도/블러)
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}
