import Foundation
import Combine
import ServiceManagement

/// What the menu bar shows next to the icon.
enum MenuBarDisplay: String, CaseIterable, Identifiable {
    case power
    case percent
    case iconOnly
    case temperature

    var id: String { rawValue }

    var titleKey: LKey {
        switch self {
        case .power: return .menuBarPower
        case .percent: return .menuBarPercent
        case .iconOnly: return .menuBarIconOnly
        case .temperature: return .menuBarTemperature
        }
    }
}

/// Shape of the menu bar status icon.
enum MenuBarIconStyle: String, CaseIterable, Identifiable {    /// Outline battery whose fill follows the charge level, with a bolt cut out
    /// while charging (matches the system indicator).
    case battery
    /// Filled battery with a lightning bolt, regardless of the current state.
    case bolt
    /// Power plug symbol.
    case plug

    var id: String { rawValue }

    var titleKey: LKey {
        switch self {
        case .battery: return .iconStyleBattery
        case .bolt: return .iconStyleBolt
        case .plug: return .iconStylePlug
        }
    }
}

/// Collapsible sections of the popover panel.
enum PanelSection: String, CaseIterable, Identifiable {
    case power
    case health
    case history
    case limit

    var id: String { rawValue }

    var titleKey: LKey {
        switch self {
        case .power: return .power
        case .health: return .health
        case .history: return .batteryPower
        case .limit: return .chargeLimit
        }
    }
}

/// 사용자 설정 (UserDefaults 기반, 메인 액터에서 동기화)
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var notificationsEnabled: Bool = true
    @Published var launchAtLogin: Bool = false
    @Published var showMenuBarIcon: Bool = true
    @Published var calibrationDays: Int = 7
    @Published var deadband: Int = 5
    @Published var sailingMode: Bool = true
    @Published var dischargeMode: Bool = false
    /// Battery temperature (℃) at which charging pauses. 0 = off.
    @Published var heatProtectionC: Int = 0
    @Published var menuBarDisplay: MenuBarDisplay = .power
    @Published var menuBarIconStyle: MenuBarIconStyle = .battery
    /// Panel sections that are shown at all.
    @Published var visibleSections: Set<PanelSection> = Set(PanelSection.allCases)
    /// Panel sections the user has collapsed with the header chevron.
    @Published var collapsedSections: Set<PanelSection> = []

    private let defaults = UserDefaults.standard

    private init() {
        registerDefaults()
        load()
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            "notificationsEnabled": true,
            "launchAtLogin": false,
            "showMenuBarIcon": true,
            "calibrationDays": 7,
            "deadband": 5,
            "sailingMode": true,
            "dischargeMode": false,
            "heatProtectionC": 0,
            "menuBarDisplay": MenuBarDisplay.power.rawValue,
            "menuBarIconStyle": MenuBarIconStyle.battery.rawValue,
            "panelVisibleSections": PanelSection.allCases.map(\.rawValue),
            "panelCollapsedSections": [String](),
        ] as [String: Any])
    }

    private func load() {
        notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        showMenuBarIcon = defaults.bool(forKey: "showMenuBarIcon")
        calibrationDays = defaults.integer(forKey: "calibrationDays")
        deadband = defaults.integer(forKey: "deadband")
        sailingMode = defaults.bool(forKey: "sailingMode")
        dischargeMode = defaults.bool(forKey: "dischargeMode")
        heatProtectionC = defaults.integer(forKey: "heatProtectionC")
        if let raw = defaults.string(forKey: "menuBarDisplay"),
           let display = MenuBarDisplay(rawValue: raw) {
            menuBarDisplay = display
        }
        if let raw = defaults.string(forKey: "menuBarIconStyle"),
           let style = MenuBarIconStyle(rawValue: raw) {
            menuBarIconStyle = style
        }
        if let raw = defaults.stringArray(forKey: "panelVisibleSections") {
            let sections = raw.compactMap(PanelSection.init(rawValue:))
            visibleSections = Set(sections)
        }
        if let raw = defaults.stringArray(forKey: "panelCollapsedSections") {
            collapsedSections = Set(raw.compactMap(PanelSection.init(rawValue:)))
        }
    }

    func save() {
        defaults.set(notificationsEnabled, forKey: "notificationsEnabled")
        defaults.set(launchAtLogin, forKey: "launchAtLogin")
        defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon")
        defaults.set(calibrationDays, forKey: "calibrationDays")
        defaults.set(deadband, forKey: "deadband")
        defaults.set(sailingMode, forKey: "sailingMode")
        defaults.set(dischargeMode, forKey: "dischargeMode")
        defaults.set(heatProtectionC, forKey: "heatProtectionC")
        defaults.set(menuBarDisplay.rawValue, forKey: "menuBarDisplay")
        defaults.set(menuBarIconStyle.rawValue, forKey: "menuBarIconStyle")
        defaults.set(visibleSections.map(\.rawValue), forKey: "panelVisibleSections")
        defaults.set(collapsedSections.map(\.rawValue), forKey: "panelCollapsedSections")
    }

    // MARK: Panel sections

    func isSectionVisible(_ section: PanelSection) -> Bool {
        visibleSections.contains(section)
    }

    func setSectionVisible(_ section: PanelSection, _ visible: Bool) {
        if visible {
            visibleSections.insert(section)
        } else {
            visibleSections.remove(section)
            collapsedSections.remove(section)
        }
        save()
    }

    func isSectionCollapsed(_ section: PanelSection) -> Bool {
        collapsedSections.contains(section)
    }

    func toggleSectionCollapsed(_ section: PanelSection) {
        if collapsedSections.contains(section) {
            collapsedSections.remove(section)
        } else {
            collapsedSections.insert(section)
        }
        save()
    }

    /// 로그인 시 자동 시작을 시스템에 등록/해제합니다. (앱 번들이어야 동작)
    func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // SwiftPM 실행 파일(번들 아님) 등록 실패는 무시하고 설정만 유지합니다.
            print("launchAtLogin apply failed: \(error.localizedDescription)")
        }
    }
}
