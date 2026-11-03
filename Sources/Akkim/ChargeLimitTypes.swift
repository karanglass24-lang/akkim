// Portions of this file are derived from ChargeWatching
// (https://github.com/TY-teo/ChargeWatching), MIT License,
// Copyright (c) 2026 TY-teo. See LICENSE and THIRD-PARTY-NOTICES.md.

import Foundation

enum ChargeLimitState: Equatable {
    case unlimited
    case limited(Int)
    case unsupported
    case unknown
}

enum ChargeLimitError: Error, Equatable {
    case permissionDenied
    case failed(String)
    case bridgeMisconfigured
}

extension ChargeLimitError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return L10n.t(.errPermissionDenied)
        case .bridgeMisconfigured:
            return L10n.t(.errBridgeMisconfigured)
        case .failed(let message):
            return message
        }
    }
}

/// 배터리 보정(calibration) 상태
struct CalibrationStatus: Equatable {
    let lastFullChargeDate: Date?
    let daysSinceLastFull: Int
    let daysUntilCalibration: Int
    let calibrationIntervalDays: Int

    var isDue: Bool { calibrationIntervalDays > 0 && daysUntilCalibration <= 0 }
    var isCalibrating: Bool { lastFullChargeDate != nil && daysSinceLastFull == 0 }
    var isDisabled: Bool { calibrationIntervalDays <= 0 }

    var nextCalibrationDate: Date? {
        guard let last = lastFullChargeDate, calibrationIntervalDays > 0 else { return nil }
        return Calendar.current.date(byAdding: .day, value: calibrationIntervalDays, to: last)
    }
}

struct ChargeLimitCapability: Equatable {
    let canRead: Bool
    let platformSupportsSet: Bool
    let bridgeConfigured: Bool
    let canSetInApp: Bool
}

enum ChargeLimitUIMode: Equatable {
    case control
    case enableInSystem
    case deepLinkOnly
    case onboarding
    case permissionDenied
    case hidden
    case loading
}

struct ChargeLimitConstants {
    static let steps: [Int] = [80, 85, 90, 95, 100]
    static let shortcutName: String = "SetBatteryChargeLimit"
}

protocol ChargeLimitReading {
    func read() async -> ChargeLimitState
}

protocol ChargeLimitSetting {
    func isBridgeAvailable() async -> Bool
    func set(percent: Int) async throws
}
