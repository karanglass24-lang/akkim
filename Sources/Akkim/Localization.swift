import Foundation

/// Every user-facing string in the app.
///
/// The switch in `LKey.text` is exhaustive, so adding a case forces you to add
/// both the English and the Korean text — a missing translation cannot compile.
enum LKey {
    // MARK: Panel — metrics
    case power
    case charging
    case wallOutput
    case systemLoad
    case batteryLevel

    // MARK: Panel — battery health
    case battery
    case health
    case cycles
    case temp
    case maximumCapacity
    case designCapacity
    case condition
    case conditionNormal
    case conditionService
    case last30Days

    // MARK: Panel — energy
    case energyUsage
    case last14Days
    case last14DaysShort
    case today
    case exportCSV
    case last7Days
    case charged
    case discharged

    // MARK: Panel — history
    case batteryPower
    case lastTenMinutes
    case collectingData
    case stateOfCharge

    // MARK: Panel — charge limit
    case chargeLimit
    case enableChargeLimit
    case limit
    case sailingMode
    case sailingModeHelp
    case dischargeToLimit
    case dischargeHelp
    case dischargeUnsupported
    case topUp
    case topUpActive
    case topUpHelp
    case cancelTopUp
    case helperNotResponding
    case useSystemSettings
    case openSystemSettings
    case oneTimeSetup
    case openOnboarding
    case quitApp
    case settings
    case unknown

    // MARK: Pause reasons (helper-state.json)
    case reasonLimit
    case reasonLimitAdapterOff
    case reasonHeat
    case reasonCalibration
    case reasonTopUp
    case reasonDischarge
    case reasonAdapterOff
    case reasonSystemHold
    case systemHoldHint

    // MARK: Status line
    case statusCharging
    case statusPaused
    case statusDischarging
    case statusDesktop
    case batteryPercent
    case systemWatts
    case dischargingShort

    // MARK: Shared words
    case off

    // MARK: Calibration
    case calibrationOff
    case calibrationEveryNoRecord
    case calibrationDue
    case calibrationIn

    // MARK: Settings window
    case notifications
    case chargingStateNotifications
    case notificationsDetail
    case general
    case launchAtLogin
    case launchAtLoginDetail
    case showMenuBarIcon
    case showMenuBarIconDetail
    case menuBarDisplay
    case menuBarPower
    case menuBarPercent
    case menuBarIconOnly
    case menuBarTemperature
    case menuBarIconStyle
    case iconStyleBattery
    case iconStyleBolt
    case iconStylePlug
    case systemLimit
    case systemLimitLinked
    case systemLimitNotLinked
    case systemLimitDetail
    case systemLimitSteps
    case systemControlLinked
    case systemControlValue
    case systemControlUnavailable
    case syncSystemLimit
    case alDenteWarning
    case openShortcutsApp
    case recheck
    case tabCharge
    case tabMonitor
    case about
    case sectionsHiddenHint
    case versionFormat
    case manual
    case panelSections
    case panelSectionsDetail
    case panelSectionCollapseHelp
    case heatProtection
    case heatProtectionDetail
    case heatUnavailable
    case heatPauseAt
    case calibration
    case calibrationDetail
    case fullChargeCalibration
    case chargeLimitBehavior
    case sailingModeLong
    case sailingModeLongDetail
    case days
    case done

    // MARK: Onboarding alert
    case setupRequiredTitle
    case setupRequiredBody
    case openShortcuts
    case cancel

    // MARK: Notifications
    case chargingStartedTitle
    case chargingStartedBody
    case chargingStoppedTitle
    case chargingStoppedBody
    case theLimit
    case notifyLimitReachedTitle
    case notifyLimitReachedBody
    case notifyHeatTitle
    case notifyHeatBody
    case notifyTopUpDoneTitle
    case notifyTopUpDoneBody

    // MARK: Errors
    case errPermissionDenied
    case errBridgeMisconfigured
    case errHelperNotInstalled
    case errShortcutBuild
    case errShortcutMissing
    case errSystemControlUnavailable
    case errSystemControlFailed
}

extension LKey {
    /// English and Korean text for this key.
    var text: (en: String, ko: String) {
        switch self {
        // Panel — metrics
        case .power:                    return ("Power", "전력")
        case .charging:                 return ("Charging", "충전")
        case .wallOutput:               return ("Wall Output", "어댑터 출력")
        case .systemLoad:               return ("System Load", "시스템 부하")
        case .batteryLevel:             return ("Battery Level", "배터리 잔량")

        // Panel — battery health
        case .battery:                  return ("Battery", "배터리")
        case .health:                   return ("Health", "건강도")
        case .cycles:                   return ("Cycles", "사이클")
        case .temp:                     return ("Temp", "온도")
        case .maximumCapacity:          return ("Max capacity", "최대 용량")
        case .designCapacity:           return ("Design capacity", "설계 용량")
        case .condition:                return ("Condition", "상태")
        case .conditionNormal:          return ("Normal", "정상")
        case .conditionService:         return ("Service Recommended", "서비스 권장")
        case .last30Days:               return ("last 30 days", "최근 30일")

        // Panel — energy
        case .energyUsage:              return ("Energy", "에너지")
        case .last14Days:               return ("last 14 days", "최근 14일")
        case .last14DaysShort:          return ("14 days", "14일")
        case .today:                    return ("Today", "오늘")
        case .exportCSV:                return ("Export CSV", "CSV 내보내기")
        case .last7Days:                return ("7 days", "7일")
        case .charged:                  return ("Charged", "충전량")
        case .discharged:               return ("Discharged", "방전량")

        // Panel — history
        case .batteryPower:             return ("Battery Power", "배터리 전력")
        case .lastTenMinutes:           return ("last 10 min", "최근 10분")
        case .collectingData:           return ("Collecting data…", "데이터 수집 중…")
        case .stateOfCharge:            return ("State of Charge", "충전 잔량")

        // Panel — charge limit
        case .chargeLimit:              return ("Charge Limit", "충전 제한")
        case .enableChargeLimit:        return ("Enable charge limit", "충전 제한 사용")
        case .limit:                    return ("Limit", "제한")
        case .sailingMode:              return ("Sailing Mode", "세일링 모드")
        case .sailingModeHelp:
            return ("Recharge after dropping by the deadband below the limit. When off, charging restarts as soon as the battery falls below the limit.",
                    "도달 후 deadband 만큼 떨어지면 다시 충전합니다. 끄면 제한치 아래로 내려갈 때마다 충전합니다.")
        case .dischargeToLimit:         return ("Discharge to Limit", "제한까지 방전")
        case .dischargeHelp:
            return ("Disconnects the adapter and lets the battery discharge down to the limit (requires SMC CHIE).",
                    "어댑터를 분리해 배터리를 제한치까지 방전시킵니다 (SMC CHIE 필요).")
        case .dischargeUnsupported:
            return ("Discharge mode is not supported on this Mac.",
                    "이 Mac에서는 방전 모드를 지원하지 않습니다.")
        case .topUp:                    return ("Charge to 100% once", "한 번만 100% 충전")
        case .topUpActive:              return ("Topping up… (cancel)", "만충전 중… (취소)")
        case .topUpHelp:
            return ("Ignores the limit until the battery reaches 100%, then restores it.",
                    "배터리가 100%에 도달할 때까지 제한을 무시한 뒤 자동으로 복원합니다.")
        case .cancelTopUp:              return ("Cancel top-up", "만충전 취소")
        case .helperNotResponding:
            return ("Charge-limit helper is not responding.", "충전 제한 도우미가 응답하지 않습니다.")
        case .useSystemSettings:
            return ("Use System Settings to enable battery charge limit on macOS 26.4+.",
                    "macOS 26.4 이상에서는 시스템 설정에서 배터리 충전 제한을 켜세요.")
        case .openSystemSettings:       return ("Open System Settings", "시스템 설정 열기")
        case .oneTimeSetup:
            return ("One-time setup required to control charging limit from this app.",
                    "이 앱에서 충전 제한을 제어하려면 최초 1회 설정이 필요합니다.")
        case .openOnboarding:           return ("Open Onboarding", "설정 안내 열기")
        case .quitApp:                  return ("Quit Akkim", "아낌 종료")
        case .settings:                 return ("Settings", "설정")
        case .unknown:                  return ("Unknown", "알 수 없음")

        // Pause reasons
        case .reasonLimit:              return ("Holding at the limit", "제한값에서 유지 중")
        case .reasonLimitAdapterOff:    return ("Holding by cutting AC power", "AC 전원을 끊어 제한 유지 중")
        case .reasonHeat:               return ("Paused: battery too hot", "일시정지: 배터리 과열")
        case .reasonCalibration:        return ("Calibrating to 100%", "보정을 위해 100%까지 충전 중")
        case .reasonTopUp:              return ("Topping up to 100%", "100%까지 만충전 중")
        case .reasonDischarge:          return ("Discharging to the limit", "제한값까지 방전 중")
        case .reasonAdapterOff:         return ("Adapter not connected", "어댑터가 연결되지 않음")
        case .reasonSystemHold:         return ("macOS is holding the charge", "macOS가 충전을 보류 중")
        case .systemHoldHint:
            return ("The system Charge Limit looks lower than this app's limit. Set it in Battery settings.",
                    "시스템 충전 제한이 앱 제한보다 낮을 수 있습니다. 배터리 설정에서 확인하세요.")

        // Status line
        case .statusCharging:           return ("Charging", "충전 중")
        case .statusPaused:             return ("AC / Paused", "AC / 일시 정지")
        case .statusDischarging:        return ("Battery / Discharging", "배터리 / 방전 중")
        case .statusDesktop:            return ("Desktop / AC Power", "데스크톱 / AC 전원")
        case .batteryPercent:           return ("Battery · %d%%", "배터리 · %d%%")
        case .systemWatts:              return ("System %.1f W", "시스템 %.1f W")
        case .dischargingShort:         return ("Discharging", "방전 중")

        // Shared words
        case .off:                      return ("Off", "꺼짐")

        // Calibration
        case .calibrationOff:           return ("Calibration: Off", "보정: 꺼짐")
        case .calibrationEveryNoRecord:
            return ("Calibration: every %dd (no record yet)", "보정: %d일마다 (기록 없음)")
        case .calibrationDue:           return ("Calibration due now", "보정 시기입니다")
        case .calibrationIn:            return ("Calibration in %dd", "보정까지 %d일")

        // Settings window
        case .notifications:            return ("Notifications", "알림")
        case .chargingStateNotifications:
            return ("Charging state change notifications", "충전 상태 변경 알림")
        case .notificationsDetail:
            return ("Notifies you when the charging state changes.",
                    "배터리 충전/방전 상태가 변할 때 알림을 보냅니다.")
        case .general:                  return ("General", "일반")
        case .launchAtLogin:            return ("Launch at login", "로그인 시 자동 실행")
        case .launchAtLoginDetail:
            return ("Starts the app automatically when you log in.",
                    "로그인 시 자동으로 앱을 시작합니다.")
        case .showMenuBarIcon:          return ("Show menu bar icon", "메뉴 막대 아이콘 표시")
        case .showMenuBarIconDetail:
            return ("Shows the icon in the menu bar.",
                    "메뉴 막대에 아이콘을 표시합니다.")
        case .menuBarDisplay:           return ("Menu bar value", "메뉴바 표시 값")
        case .menuBarPower:             return ("Power (W)", "전력(W)")
        case .menuBarPercent:           return ("Battery (%)", "잔량(%)")
        case .menuBarIconOnly:          return ("Icon only", "아이콘만")
        case .menuBarTemperature:       return ("Temperature", "온도")
        case .menuBarIconStyle:         return ("Menu bar icon", "메뉴바 아이콘")
        case .iconStyleBattery:         return ("Battery (charge level)", "배터리 (잔량)")
        case .iconStyleBolt:            return ("Charging battery", "충전 배터리")
        case .iconStylePlug:            return ("Power plug", "전원 플러그")
        case .systemLimit:              return ("System charge limit", "시스템 충전 제한")
        case .systemLimitLinked:        return ("Linked — changes apply to macOS too", "연동됨 — 변경이 macOS에도 적용됩니다")
        case .systemLimitNotLinked:     return ("Not linked", "연동되지 않음")
        case .systemLimitDetail:
            return ("macOS 26.4+ enforces its own Charge Limit. Link it through Shortcuts and Akkim can update the system limit from this app, without opening System Settings.",
                    "macOS 26.4+에는 자체 충전 제한이 있습니다. Shortcuts로 연동하면 앱에서 바꾼 값이 시스템 제한에도 적용되어 설정 앱을 열 필요가 없습니다.")
        case .systemLimitSteps:
            return ("In Shortcuts use Apple’s “Set Battery Charge Limit” action (not AlDente’s) and make five shortcuts named SetBatteryChargeLimit80, …85, …90, …95, …100.",
                    "Shortcuts에서 Apple의 ‘Set Battery Charge Limit’ 동작(AlDente의 ‘Set Charge Limit’ 아님)으로 값이 고정된 단축어 5개를 만들고 이름을 SetBatteryChargeLimit80, …85, …90, …95, …100으로 저장하세요.")
        case .systemControlLinked:
            return ("Direct control — Akkim also updates the macOS charge limit",
                    "직접 제어 — 앱에서 바꾸면 macOS 충전 제한도 함께 바뀝니다")
        case .systemControlValue:       return ("macOS charge limit: %d%%", "macOS 충전 제한: %d%%")
        case .systemControlUnavailable:
            return ("This macOS does not expose the charge limit API. Link it through Shortcuts instead.",
                    "이 macOS에서는 충전 제한 API를 사용할 수 없습니다. Shortcuts로 연동하세요.")
        case .syncSystemLimit:
            return ("Sync macOS limit", "시스템 제한 동기화")
        case .alDenteWarning:
            return ("AlDente is running. Two charge controllers can fight over the battery — quit AlDente while using Akkim.",
                    "AlDente가 실행 중입니다. 두 앱이 충전 제어를 두고 충돌할 수 있으니 Akkim 사용 중에는 AlDente를 종료하세요.")
        case .openShortcutsApp:         return ("Open Shortcuts", "Shortcuts 열기")
        case .recheck:                  return ("Check again", "다시 확인")
        case .tabCharge:                return ("Charge", "충전")
        case .tabMonitor:               return ("Monitor", "모니터")
        case .about:                    return ("About", "정보")
        case .sectionsHiddenHint:
            return ("No sections are visible. Turn them on in Settings › Panel sections.",
                    "표시할 섹션이 없습니다. 설정 › 패널 섹션에서 켜세요.")
        case .versionFormat:            return ("Version %@ (%@)", "버전 %@ (%@)")
        case .manual:                   return ("User manual", "사용 설명서")
        case .panelSections:            return ("Panel sections", "패널 섹션")
        case .panelSectionsDetail:
            return ("Choose which sections appear in the popover. Click a section title to collapse or expand it.",
                    "팝오버에 표시할 섹션을 선택합니다. 섹션 제목을 클릭하면 접거나 펼 수 있습니다.")
        case .panelSectionCollapseHelp: return ("Collapse or expand", "접기/펴기")
        case .heatProtection:           return ("Heat protection", "열 보호")
        case .heatProtectionDetail:
            return ("Pauses charging when the battery reaches this temperature (0 = off).",
                    "배터리가 이 온도에 도달하면 충전을 일시정지합니다 (0 = 끔).")
        case .heatUnavailable:
            return ("Battery temperature is unavailable on this Mac, so heat protection is inactive.",
                    "이 Mac에서는 배터리 온도를 읽을 수 없어 열 보호가 동작하지 않습니다.")
        case .heatPauseAt:              return ("Pause charging at", "충전 일시정지 온도")
        case .calibration:              return ("Calibration", "보정")
        case .calibrationDetail:
            return ("Periodically allows a full charge to keep battery health estimates accurate.",
                    "배터리 수명 추정 정확도를 위해 주기적으로 100% 충전을 허용합니다.")
        case .fullChargeCalibration:    return ("Full charge calibration (days)", "완충 보정 주기(일)")
        case .chargeLimitBehavior:      return ("Charge Limit Behavior", "충전 제한 동작")
        case .sailingModeLong:          return ("Sailing mode (hold at limit)", "세일링 모드 (제한값 유지)")
        case .sailingModeLongDetail:
            return ("At the limit, keeps the adapter connected and pauses charging.",
                    "충전 제한치에 도달하면 어댑터 연결 상태를 유지하면서 충전을 일시 정지합니다.")
        case .days:                     return ("%d days", "%d일")
        case .done:                     return ("Done", "완료")

        // Onboarding alert
        case .setupRequiredTitle:       return ("Charge limit setup is required", "충전 제한 설정이 필요합니다")
        case .setupRequiredBody:
            return ("macOS 26.4 and later use the system's native charge limit.\nCreate a shortcut named \"SetBatteryChargeLimit\" in the Shortcuts app.",
                    "macOS 26.4 이상에서는 시스템의 네이티브 충전 제한을 사용합니다.\n단축어(Shortcuts) 앱에서 \"SetBatteryChargeLimit\" 이름의 단축어를 만들어 주세요.")
        case .openShortcuts:            return ("Open Shortcuts", "Shortcuts 열기")
        case .cancel:                   return ("Cancel", "취소")

        // Notifications
        case .chargingStartedTitle:     return ("Charging started", "충전 시작")
        case .chargingStartedBody:
            return ("Battery charging at %.1f W.", "배터리를 %.1f W로 충전하고 있습니다.")
        case .chargingStoppedTitle:     return ("Charging stopped", "충전 중지")
        case .chargingStoppedBody:
            return ("Charging stopped at %@.", "충전이 %@에서 중지되었습니다.")
        case .theLimit:                 return ("the limit", "제한값")
        case .notifyLimitReachedTitle:  return ("Charge limit reached", "충전 제한 도달")
        case .notifyLimitReachedBody:
            return ("Charging paused at %d%%.", "%d%%에서 충전을 일시정지했습니다.")
        case .notifyHeatTitle:          return ("Charging paused: too hot", "충전 일시정지: 과열")
        case .notifyHeatBody:
            return ("Battery temperature reached %.1f°C.", "배터리 온도가 %.1f°C에 도달했습니다.")
        case .notifyTopUpDoneTitle:     return ("Top-up complete", "만충전 완료")
        case .notifyTopUpDoneBody:
            return ("The battery is fully charged.", "배터리가 100%가 되었습니다.")

        // Errors
        case .errPermissionDenied:
            return ("Administrator permission is required.",
                    "관리자 권한이 필요합니다.")
        case .errBridgeMisconfigured:
            return ("The charge limit helper is not set up correctly.",
                    "충전 제한 도우미가 올바르게 설정되지 않았습니다.")
        case .errHelperNotInstalled:
            return ("The charge limit helper is not installed.",
                    "충전 제한 도우미가 설치되어 있지 않습니다.")
        case .errShortcutBuild:
            return ("Could not build the shortcut URL.",
                    "단축어 URL을 만들지 못했습니다.")
        case .errShortcutMissing:
            return ("Could not open the shortcut. Create \"%@\" in the Shortcuts app.",
                    "단축어를 열지 못했습니다. Shortcuts 앱에서 \"%@\"을(를) 만들어 주세요.")
        case .errSystemControlUnavailable:
            return ("macOS charge limit control is not available on this system.",
                    "이 시스템에서는 macOS 충전 제한을 직접 제어할 수 없습니다.")
        case .errSystemControlFailed:
            return ("Could not change the macOS charge limit.",
                    "macOS 충전 제한을 변경하지 못했습니다.")
        }
    }
}

/// Resolves UI strings for the current system language.
///
/// macOS picks the app language from the first preferred language
/// (`ko*` → Korean, anything else → English). The choice is read once at
/// launch, so changing the system language takes effect after a restart.
enum L10n {
    enum Language {
        case ko
        case en
    }

    static let language: Language = {
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.lowercased().hasPrefix("ko") ? .ko : .en
    }()

    static func t(_ key: LKey) -> String {
        let text = key.text
        return language == .ko ? text.ko : text.en
    }
}
