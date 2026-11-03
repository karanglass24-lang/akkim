// Portions of this file are derived from ChargeWatching
// (https://github.com/TY-teo/ChargeWatching), MIT License,
// Copyright (c) 2026 TY-teo. See LICENSE and THIRD-PARTY-NOTICES.md.

import Foundation

enum BatteryStatus: Equatable {
    case charging
    case acPaused
    case discharging
    case desktop

    var displayName: String {
        switch self {
        case .charging: return L10n.t(.statusCharging)
        case .acPaused: return L10n.t(.statusPaused)
        case .discharging: return L10n.t(.statusDischarging)
        case .desktop: return L10n.t(.statusDesktop)
        }
    }
}

struct PowerSample: Equatable {
    let timestamp: Date
    let isCharging: Bool
    let externalConnected: Bool
    let hasBattery: Bool
    let batteryWatts: Double
    let wallOutputWatts: Double?
    let systemLoadWatts: Double?
    let voltageMillivolts: Int?
    let amperageMilliamps: Int?
    let stateOfChargePercent: Int?
    let adapterRatedWatts: Int?
    let adapterDescription: String?

    // MARK: Battery health / environment
    let cycleCount: Int?
    let designCapacitymAh: Int?
    let maxCapacitymAh: Int?
    let batteryHealthPercent: Int?
    let temperatureCelsius: Double?

    var status: BatteryStatus {
        if !hasBattery { return .desktop }
        if isCharging && batteryWatts > 0.5 { return .charging }
        if externalConnected { return .acPaused }
        return .discharging
    }

    var displayWatts: Double {
        switch status {
        case .charging: return batteryWatts
        case .desktop: return systemLoadWatts ?? 0
        case .acPaused, .discharging: return abs(batteryWatts)
        }
    }
}
