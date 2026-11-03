// Portions of this file are derived from ChargeWatching
// (https://github.com/TY-teo/ChargeWatching), MIT License,
// Copyright (c) 2026 TY-teo. See LICENSE and THIRD-PARTY-NOTICES.md.

import Foundation
import IOKit

/// Apple Silicon Mac 의 배터리/전력 정보를 IORegistry (AppleSmartBattery) 에서 읽어온다.
final class IORegistryReader {

    func read() -> PowerSample {
        let timestamp = Date()
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))

        guard service != 0 else {
            return desktopFallback(timestamp: timestamp)
        }
        defer { IOObjectRelease(service) }

        var propsRef: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS, let dict = propsRef?.takeRetainedValue() as? [String: Any] else {
            return desktopFallback(timestamp: timestamp)
        }

        let voltage = readInt(dict, "Voltage")
        let amperage = readSignedInt(dict, "Amperage")
        let instantAmperage = readSignedInt(dict, "InstantAmperage")
        let isCharging = (dict["IsCharging"] as? Bool) ?? false
        let externalConnected = (dict["ExternalConnected"] as? Bool) ?? false
        let soc = readInt(dict, "CurrentCapacity")

        // MARK: Battery health / environment
        // macOS 26+ Apple Silicon moves several values into the BatteryData
        // sub-dictionary, so fall back to it before giving up.
        let batteryData = dict["BatteryData"] as? [String: Any] ?? [:]
        let cycleCount = readInt(dict, "CycleCount") ?? readInt(batteryData, "CycleCount")
        let designCapacity = readInt(dict, "DesignCapacity") ?? readInt(batteryData, "DesignCapacity")
        let rawMaxCapacity = readInt(dict, "AppleRawMaxCapacity")
            ?? readInt(batteryData, "FullChargeCapacity")
        // Older Macs report MaxCapacity in mAh; Apple Silicon reports a percentage.
        let legacyMaxCapacity = readInt(dict, "MaxCapacity").flatMap { $0 > 1000 ? $0 : nil }
        let maxCapacity = rawMaxCapacity ?? legacyMaxCapacity
        let temperatureCelsius = readTemperature(dict)
        let healthPercent: Int? = {
            guard let design = designCapacity, design > 0, let maxCap = maxCapacity else { return nil }
            let pct = Int((Double(maxCap) / Double(design) * 100.0).rounded())
            return min(100, max(0, pct))
        }()

        let adapterDetails = dict["AdapterDetails"] as? [String: Any]
        let adapterRated = readInt(adapterDetails ?? [:], "Watts")
        let adapterDesc = formatAdapter(adapterDetails)

        let telemetry = dict["PowerTelemetryData"] as? [String: Any]
        let systemPowerInMilliwatts = readSignedInt(telemetry ?? [:], "SystemPowerIn").map { abs($0) }
        let adapterEfficiencyLossMilliwatts = readSignedInt(telemetry ?? [:], "AdapterEfficiencyLoss").map { abs($0) }

        // Battery charging power: voltage x instantaneous current (InstantAmperage
        // reflects real-time charging while plugged in; the top-level Amperage is an
        // average over seconds and is used as fallback).
        let batteryMagnitudeWatts: Double
        if let v = voltage, let a = instantAmperage, a != 0 {
            batteryMagnitudeWatts = abs(Double(v) * Double(a) / 1_000_000.0)
        } else if let v = voltage, let a = amperage {
            batteryMagnitudeWatts = abs(Double(v) * Double(a) / 1_000_000.0)
        } else {
            batteryMagnitudeWatts = 0
        }
        let batteryWatts = isCharging ? batteryMagnitudeWatts : -batteryMagnitudeWatts

        // Wall output (drawn from the outlet/adapter) = power into the Mac + adapter loss.
        let wallOutputWatts: Double?
        if externalConnected, let sysIn = systemPowerInMilliwatts, sysIn > 0 {
            let lossMw = adapterEfficiencyLossMilliwatts ?? 0
            wallOutputWatts = Double(sysIn + lossMw) / 1000.0
        } else {
            wallOutputWatts = nil
        }

        // System load (chip/display consumption) derived from energy conservation:
        // on AC = power into the Mac - power into the battery; on battery = discharge power.
        let systemLoadWatts: Double?
        if let sysIn = systemPowerInMilliwatts, sysIn > 0 {
            systemLoadWatts = max(0, Double(sysIn) / 1000.0 - batteryWatts)
        } else if !externalConnected {
            systemLoadWatts = batteryMagnitudeWatts
        } else {
            systemLoadWatts = nil
        }

        return PowerSample(
            timestamp: timestamp,
            isCharging: isCharging,
            externalConnected: externalConnected,
            hasBattery: true,
            batteryWatts: batteryWatts,
            wallOutputWatts: wallOutputWatts,
            systemLoadWatts: systemLoadWatts,
            voltageMillivolts: voltage,
            amperageMilliamps: amperage,
            stateOfChargePercent: soc,
            adapterRatedWatts: adapterRated,
            adapterDescription: adapterDesc,
            cycleCount: cycleCount,
            designCapacitymAh: designCapacity,
            maxCapacitymAh: maxCapacity,
            batteryHealthPercent: healthPercent,
            temperatureCelsius: temperatureCelsius
        )
    }

    private func desktopFallback(timestamp: Date) -> PowerSample {
        PowerSample(
            timestamp: timestamp,
            isCharging: false,
            externalConnected: true,
            hasBattery: false,
            batteryWatts: 0,
            wallOutputWatts: nil,
            systemLoadWatts: nil,
            voltageMillivolts: nil,
            amperageMilliamps: nil,
            stateOfChargePercent: nil,
            adapterRatedWatts: nil,
            adapterDescription: nil,
            cycleCount: nil,
            designCapacitymAh: nil,
            maxCapacitymAh: nil,
            batteryHealthPercent: nil,
            temperatureCelsius: nil
        )
    }

    /// AppleSmartBattery 의 Temperature 키는 기기/OS에 따라 단위가 다릅니다.
    /// 값이 1000보다 크면 centi-°C(예: 3031 → 30.31°C), 작으면 deci-°C 로 간주합니다.
    private func readTemperature(_ dict: [String: Any]) -> Double? {
        // macOS 26+ (Apple Silicon) no longer exposes `Temperature` on
        // AppleSmartBattery; the live value lives in the child
        // `AppleSmartBatteryPack` node (`BatteryData.Temperature`, centi-°C).
        var raw = readInt(dict, "Temperature")
        if raw == nil, let bd = dict["BatteryData"] as? [String: Any] {
            raw = readInt(bd, "Temperature")
        }
        if raw == nil { raw = batteryPackTemperatureRaw() }
        guard let raw, raw > 0 else { return nil }
        let celsius = raw > 1000 ? Double(raw) / 100.0 : Double(raw) / 10.0
        guard celsius > -20, celsius < 120 else { return nil }
        return celsius
    }

    /// Reads `BatteryData.Temperature` from the `AppleSmartBatteryPack` node.
    private func batteryPackTemperatureRaw() -> Int? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBatteryPack"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = propsRef?.takeRetainedValue() as? [String: Any],
              let batteryData = dict["BatteryData"] as? [String: Any] else { return nil }
        return readInt(batteryData, "Temperature")
    }

    private func readInt(_ dict: [String: Any], _ key: String) -> Int? {
        guard let n = dict[key] as? NSNumber else { return nil }
        return n.intValue
    }

    private func readSignedInt(_ dict: [String: Any], _ key: String) -> Int? {
        guard let n = dict[key] as? NSNumber else { return nil }
        let bits = n.int64Value
        return Int(truncatingIfNeeded: bits)
    }

    private func formatAdapter(_ details: [String: Any]?) -> String? {
        guard let d = details, let watts = readInt(d, "Watts") else { return nil }
        let mv = readInt(d, "AdapterVoltage")
        let ma = readInt(d, "Current")
        let desc = (d["Description"] as? String)?.uppercased() ?? "ADAPTER"
        if let mv, let ma {
            let v = Double(mv) / 1000.0
            let a = Double(ma) / 1000.0
            return String(format: "%dW %@ · %.0fV/%.1fA", watts, desc, v, a)
        }
        return "\(watts)W \(desc)"
    }
}
