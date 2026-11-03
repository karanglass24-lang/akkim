import Foundation

/// Mirror of `/Users/Shared/Akkim/helper-state.json`, written by `AkkimHelper`
/// on every control-loop iteration (about once every 10 s).
///
/// The app uses this to explain *why* charging is paused and to know whether the
/// machine supports discharge mode, instead of guessing from the config file.
struct HelperStatus: Equatable {
    enum Reason: String {
        case off
        case noBattery
        case adapterOff
        case discharge
        case topUp
        case heat
        case calibration
        case limit
        case charging
        case systemHold
    }

    let timestamp: Date
    let holding: Bool
    let discharging: Bool
    let actuator: String
    let chieAvailable: Bool
    let soc: Int?
    let temperatureCelsius: Double?
    let reason: Reason
    let enabled: Bool
    let limit: Int
    let topUp: Bool

    static let path = "/Users/Shared/Akkim/helper-state.json"

    /// The helper writes every 10 s; anything older than 30 s means it is not running.
    var isStale: Bool { Date().timeIntervalSince(timestamp) > 30 }

    private static var cachedMTime: Date?
    private static var cachedStatus: HelperStatus?

    /// Reads the state file, reusing the last parse when the modification date is unchanged.
    /// Call from the main actor only (the cache is not synchronized).
    static func readCached() -> HelperStatus? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let mtime = attrs?[.modificationDate] as? Date
        if let mtime, mtime == cachedMTime { return cachedStatus }
        cachedMTime = mtime
        cachedStatus = read()
        return cachedStatus
    }

    static func read() -> HelperStatus? {
        guard let data = FileManager.default.contents(atPath: path),
              let raw = try? JSONSerialization.jsonObject(with: data),
              let j = raw as? [String: Any],
              let ts = (j["ts"] as? Double), ts > 0 else { return nil }

        let socRaw = (j["soc"] as? Int) ?? -1
        let tempRaw = (j["tempC"] as? Double) ?? -1
        return HelperStatus(
            timestamp: Date(timeIntervalSince1970: ts),
            holding: (j["holding"] as? Bool) ?? false,
            discharging: (j["discharging"] as? Bool) ?? false,
            actuator: (j["actuator"] as? String) ?? "?",
            chieAvailable: (j["chieAvailable"] as? Bool) ?? false,
            soc: socRaw >= 0 ? socRaw : nil,
            temperatureCelsius: tempRaw > 0 ? tempRaw : nil,
            reason: Reason(rawValue: (j["reason"] as? String) ?? "") ?? .off,
            enabled: (j["enabled"] as? Bool) ?? false,
            limit: (j["limit"] as? Int) ?? 80,
            topUp: (j["topUp"] as? Bool) ?? false
        )
    }
}
