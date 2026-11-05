// Portions of this file are derived from ChargeWatching
// (https://github.com/TY-teo/ChargeWatching), MIT License,
// Copyright (c) 2026 TY-teo. See LICENSE and THIRD-PARTY-NOTICES.md.

// AkkimHelper - root daemon that enforces the battery charge limit
// on Apple Silicon Macs (SMC charge-control keys).
//
// Mechanism (verified on this machine, aligned with the `batt` Tahoe path):
// - Charge control key CHTE (ui32): write 0x00000001 = hold charging (adapter
//   powered, battery not discharged; CHSC instantaneous 1->0). Write 0 = allow.
// - Fallback actuator CHIE (ui8): 0x00 = connect adapter, 0x08 = disconnect
//   (only used when CHTE is not available on the machine). With
//   `nativeHold = true` (macOS 26.4+ Charge Limit already equals ours) the
//   hold leaves the adapter connected and lets macOS stop charging; CHIE is
//   then used only for discharge mode and heat protection.
// - Sailing mode: hold when SoC >= limit; release when SoC <= limit - deadband
//   (default deadband 5, aligned with Apple's official "recharge after >5%").
// - Hard-stop mode (sailingMode = false): hold at the limit, recharge whenever
//   SoC drops below the limit.
// - Discharge mode (discharge = true): disconnect the adapter via CHIE and let
//   the battery discharge down to the limit, then reconnect and hold.
//   Requires the CHIE key (not available on all machines).
// - Auto full-charge calibration: release and let it charge to 100% every
//   `calibrationDays` days (default 7) to keep the SoC estimate accurate.
// - Heat protection: hold charging while the battery is at or above
//   `heatProtectionC` (0 = off) and an adapter is connected.
// - One-shot top-up: `topUp=true` charges to 100%, then clears the flag.
//
// Safety (fail-safe): on exit / crash / signal, restore charging (CHTE=0, CHIE=0).
// Configuration is read from the user-space app-writable JSON file:
//   /Users/Shared/Akkim/smc-limit.json
//   {"schemaVersion":1,"enabled":true,"limit":80,"deadband":5,"calibrationDays":7,
//    "sailingMode":true,"discharge":false,"heatProtectionC":0,"topUp":false,
//    "nativeHold":false}
// The daemon publishes its current state (reason, holding, CHIE availability,
// SoC, temperature) to /Users/Shared/Akkim/helper-state.json for the app.
import Foundation
import IOKit

// MARK: SMC (Apple Silicon interface verified on this machine)

enum SMC {
    static let kOpen: UInt32 = 0, kYPC: UInt32 = 2
    static let kRead: UInt8 = 5, kWrite: UInt8 = 6, kInfo: UInt8 = 9, kOK: UInt8 = 0
    static let SZ = 80, OKEY = 0, ODSIZE = 28, ORES = 40, OD8 = 42, OBYTES = 48
    static var conn: io_connect_t = 0

    static func start() -> Bool {
        let smc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard smc != 0 else { return false }
        defer { IOObjectRelease(smc) }
        guard IOServiceOpen(smc, mach_task_self_, 1, &conn) == KERN_SUCCESS else { return false }
        _ = IOConnectCallMethod(conn, kOpen, nil, 0, nil, 0, nil, nil, nil, nil)
        return true
    }

    static func fourCC(_ s: String) -> UInt32 {
        var r: UInt32 = 0
        for b in s.utf8 { r = (r << 8) | UInt32(b) }
        return r
    }

    private static func putU32(_ b: inout [UInt8], _ o: Int, _ v: UInt32) {
        b[o] = UInt8(v & 0xff)
        b[o + 1] = UInt8((v >> 8) & 0xff)
        b[o + 2] = UInt8((v >> 16) & 0xff)
        b[o + 3] = UInt8((v >> 24) & 0xff)
    }

    private static func call(_ input: [UInt8]) -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: SMC.SZ)
        var sz = SMC.SZ
        let kr = input.withUnsafeBytes { i in
            out.withUnsafeMutableBytes { o in
                IOConnectCallStructMethod(conn, SMC.kYPC, i.baseAddress, SMC.SZ, o.baseAddress, &sz)
            }
        }
        return kr == KERN_SUCCESS ? out : nil
    }

    static func keyInfoSize(_ key: String) -> UInt32? {
        var b = [UInt8](repeating: 0, count: SMC.SZ)
        putU32(&b, SMC.OKEY, fourCC(key))
        b[SMC.OD8] = SMC.kInfo
        guard let o = call(b), o[SMC.ORES] == SMC.kOK else { return nil }
        return UInt32(o[SMC.ODSIZE]) | (UInt32(o[SMC.ODSIZE + 1]) << 8) | (UInt32(o[SMC.ODSIZE + 2]) << 16) | (UInt32(o[SMC.ODSIZE + 3]) << 24)
    }

    static func read(_ key: String, _ size: UInt32) -> [UInt8]? {
        guard size > 0, size <= 32 else { return nil }
        var b = [UInt8](repeating: 0, count: SMC.SZ)
        putU32(&b, SMC.OKEY, fourCC(key))
        putU32(&b, SMC.ODSIZE, size)
        b[SMC.OD8] = SMC.kRead
        guard let o = call(b), o[SMC.ORES] == SMC.kOK else { return nil }
        return Array(o[SMC.OBYTES..<(SMC.OBYTES + Int(size))])
    }

    @discardableResult
    static func write(_ key: String, _ value: [UInt8]) -> Bool {
        var b = [UInt8](repeating: 0, count: SMC.SZ)
        putU32(&b, SMC.OKEY, fourCC(key))
        putU32(&b, SMC.ODSIZE, UInt32(value.count))
        b[SMC.OD8] = SMC.kWrite
        for (i, v) in value.enumerated() { b[SMC.OBYTES + i] = v }
        guard let o = call(b), o[SMC.ORES] == SMC.kOK else { return false }
        return read(key, UInt32(value.count)) == value
    }
}

// MARK: Battery read

struct Battery {
    let soc: Int
    let fullyCharged: Bool
    let adapterPresent: Bool
    let externalConnected: Bool
    let isCharging: Bool
    let tempC: Double?
}

func readBattery() -> Battery? {
    let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard svc != 0 else { return nil }
    defer { IOObjectRelease(svc) }
    var p: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(svc, &p, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let d = p?.takeRetainedValue() as? [String: Any] else { return nil }
    let soc = (d["CurrentCapacity"] as? NSNumber)?.intValue ?? -1
    let full = (d["FullyCharged"] as? Bool) ?? false
    let external = (d["ExternalConnected"] as? Bool) ?? false
    let charging = (d["IsCharging"] as? Bool) ?? false
    let tempC: Double? = readBatteryTemperature(fallback: d)
    return Battery(
        soc: soc,
        fullyCharged: full,
        adapterPresent: adapterPhysicallyPresent(fallback: d),
        externalConnected: external,
        isCharging: charging,
        tempC: tempC
    )
}

/// Battery temperature in °C.
///
/// macOS 26+ on Apple Silicon no longer exposes `Temperature` on
/// `AppleSmartBattery`; the live value lives in the child `AppleSmartBatteryPack`
/// node (`BatteryData.Temperature`, centi-°C). Fall back to the old locations so
/// older machines keep working.
func readBatteryTemperature(fallback d: [String: Any]) -> Double? {
    var raw: Int?
    if let n = d["Temperature"] as? NSNumber { raw = n.intValue }
    if raw == nil, let bd = d["BatteryData"] as? [String: Any],
       let n = bd["Temperature"] as? NSNumber { raw = n.intValue }
    if raw == nil { raw = batteryPackTemperatureRaw() }
    guard let raw, raw > 0 else { return nil }
    // Same unit heuristic as the app: centi-°C when large, deci-°C otherwise.
    let celsius = raw > 1000 ? Double(raw) / 100.0 : Double(raw) / 10.0
    return (celsius > -20 && celsius < 120) ? celsius : nil
}

func batteryPackTemperatureRaw() -> Int? {
    let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBatteryPack"))
    guard svc != 0 else { return nil }
    defer { IOObjectRelease(svc) }
    var p: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(svc, &p, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let d = p?.takeRetainedValue() as? [String: Any],
          let bd = d["BatteryData"] as? [String: Any],
          let n = bd["Temperature"] as? NSNumber else { return nil }
    return n.intValue
}

func adapterPhysicallyPresent(fallback d: [String: Any]) -> Bool {
    if let b = SMC.read("AC-W", 1) {
        return Int8(bitPattern: b[0]) >= 0
    }
    if let ad = d["AdapterDetails"] as? [String: Any], (ad["Watts"] as? NSNumber)?.intValue ?? 0 > 0 { return true }
    return (d["ExternalConnected"] as? Bool) ?? false
}

// MARK: Config

struct Config {
    var enabled: Bool
    var limit: Int
    var deadband: Int
    var calibrationDays: Int
    var sailingMode: Bool
    var discharge: Bool
    var heatProtectionC: Int
    var topUp: Bool
    /// The app keeps macOS's own Charge Limit equal to `limit`.
    var nativeHold: Bool
}

let configDir = "/Users/Shared/Akkim"
let configPath = "/Users/Shared/Akkim/smc-limit.json"

let defaultConfig = Config(enabled: false, limit: 80, deadband: 5, calibrationDays: 7,
                           sailingMode: true, discharge: false, heatProtectionC: 0, topUp: false,
                           nativeHold: false)
/// Last successfully parsed config. Used instead of instantly releasing the
/// charge limit when a read lands in the middle of a write.
var lastGoodConfig: Config?
var configParseFailures = 0
/// ~60 s at the 10 s poll cadence: only then do we assume the file is broken for good.
let maxConfigParseFailures = 6

func readConfig() -> Config {
    guard let data = FileManager.default.contents(atPath: configPath) else {
        // No config file at all means "not configured" — release control.
        configParseFailures = 0
        lastGoodConfig = nil
        return defaultConfig
    }
    guard let raw = try? JSONSerialization.jsonObject(with: data),
          let j = raw as? [String: Any] else {
        configParseFailures += 1
        if let last = lastGoodConfig, configParseFailures < maxConfigParseFailures {
            log("config unreadable (\(configParseFailures)/\(maxConfigParseFailures)); keeping last good config")
            return last
        }
        log("config unreadable \(configParseFailures)x; releasing charge control")
        return defaultConfig
    }
    configParseFailures = 0
    let limit = min(100, max(50, (j["limit"] as? Int) ?? 80))
    let dead = min(10, max(1, (j["deadband"] as? Int) ?? 5))
    let calib = min(60, max(0, (j["calibrationDays"] as? Int) ?? 7))
    let heatRaw = (j["heatProtectionC"] as? Int) ?? 0
    let heat = heatRaw == 0 ? 0 : min(60, max(30, heatRaw))
    let cfg = Config(
        enabled: (j["enabled"] as? Bool) ?? false,
        limit: limit,
        deadband: dead,
        calibrationDays: calib,
        sailingMode: (j["sailingMode"] as? Bool) ?? true,
        discharge: (j["discharge"] as? Bool) ?? false,
        heatProtectionC: heat,
        topUp: (j["topUp"] as? Bool) ?? false,
        nativeHold: (j["nativeHold"] as? Bool) ?? false
    )
    lastGoodConfig = cfg
    return cfg
}

let calibStatePath = "/Users/Shared/Akkim/calib-state.json"
let statePath = "/Users/Shared/Akkim/helper-state.json"

/// Clears the one-shot top-up request while preserving every other field.
func clearTopUpFlag(_ cfg: Config) {
    let obj: [String: Any] = [
        "schemaVersion": 1,
        "enabled": cfg.enabled,
        "limit": cfg.limit,
        "deadband": cfg.deadband,
        "calibrationDays": cfg.calibrationDays,
        "sailingMode": cfg.sailingMode,
        "discharge": cfg.discharge,
        "heatProtectionC": cfg.heatProtectionC,
        "topUp": false,
        "nativeHold": cfg.nativeHold,
    ]
    if let data = try? JSONSerialization.data(withJSONObject: obj) {
        try? data.write(to: URL(fileURLWithPath: configPath), options: .atomic)
    }
}

func readLastFullCharge() -> Date {
    if let data = FileManager.default.contents(atPath: calibStatePath),
       let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let t = j["lastFullChargeAt"] as? Double {
        return Date(timeIntervalSince1970: t)
    }
    let now = Date()
    writeLastFullCharge(now)
    return now
}

func writeLastFullCharge(_ date: Date) {
    let obj: [String: Any] = ["lastFullChargeAt": date.timeIntervalSince1970]
    if let data = try? JSONSerialization.data(withJSONObject: obj) {
        try? data.write(to: URL(fileURLWithPath: calibStatePath), options: .atomic)
    }
}

/// Upgrades installs created before the permission fix (dir 777 / json 666).
/// World-writable config tells a root daemon what to do, so drop it to
/// root:admin 775/664 — admin users (the app) can still write.
func hardenConfigPermissions() {
    let fm = FileManager.default
    let targets: [(path: String, mode: Int)] = [
        (configDir, 0o775),
        (configPath, 0o664),
        (calibStatePath, 0o664),
        (statePath, 0o644),
    ]
    for target in targets {
        guard fm.fileExists(atPath: target.path),
              let attrs = try? fm.attributesOfItem(atPath: target.path),
              let current = (attrs[.posixPermissions] as? NSNumber)?.intValue,
              current & 0o002 != 0 else { continue }
        let hardened: [FileAttributeKey: Any] = [
            .posixPermissions: NSNumber(value: target.mode),
            .ownerAccountID: NSNumber(value: 0),
            .groupOwnerAccountID: NSNumber(value: 80), // gid 80 = admin
        ]
        try? fm.setAttributes(hardened, ofItemAtPath: target.path)
        log("permissions hardened: \(target.path) \(String(current, radix: 8)) -> \(String(target.mode, radix: 8))")
    }
}

// MARK: Charging control (charge-disable semantics via CHTE, CHIE fallback)

let CHTE = "CHTE"
let CHTE_ALLOW: [UInt8] = [0x00, 0x00, 0x00, 0x00] // allow charging
let CHTE_HOLD:  [UInt8] = [0x01, 0x00, 0x00, 0x00] // hold charging (adapter powered, battery not discharged)
let CHIE = "CHIE"
let CHIE_CONNECT: [UInt8] = [0x00] // connect adapter
let CHIE_DISCONNECT: [UInt8] = [0x08] // disconnect adapter (fallback)

var useCHTE = false
var hasCHIE = false
/// CHIE-only machine whose macOS Charge Limit already holds at our limit:
/// holding must keep the adapter connected instead of running on battery.
var nativeHoldActive = false

func log(_ m: String) { FileHandle.standardError.write(("[akkim-helper] " + m + "\n").data(using: .utf8)!) }

func allowCharging() {
    if useCHTE { SMC.write(CHTE, CHTE_ALLOW) }
    SMC.write(CHIE, CHIE_CONNECT)
}

func holdCharging() {
    if useCHTE {
        SMC.write(CHTE, CHTE_HOLD)
        // 이전 방전 모드에서 남은 CHIE disconnect 를 확실히 해제합니다.
        if hasCHIE { SMC.write(CHIE, CHIE_CONNECT) }
    } else if nativeHoldActive {
        SMC.write(CHIE, CHIE_CONNECT)
    } else {
        SMC.write(CHIE, CHIE_DISCONNECT)
    }
}

/// Heat protection must stop charging below the limit too, which macOS's
/// Charge Limit does not do, so a CHIE-only machine still cuts the adapter.
func holdChargingForHeat() {
    if useCHTE { holdCharging() } else { SMC.write(CHIE, CHIE_DISCONNECT) }
}

/// 방전 모드: 어댑터를 SMC 레벨에서 분리합니다 (CHTE 는 allow 로 풀어 충돌 방지).
func disconnectAdapter() {
    if useCHTE { SMC.write(CHTE, CHTE_ALLOW) }
    SMC.write(CHIE, CHIE_DISCONNECT)
}

func failSafeExit(_ code: Int32) -> Never { allowCharging(); log("exit -> restore charging (CHTE=0, CHIE=0)"); exit(code) }

// MARK: Launch

guard SMC.start() else { log("AppleSMC open failed (need root)"); exit(3) }
hardenConfigPermissions()
useCHTE = (SMC.keyInfoSize(CHTE) == 4)
hasCHIE = (SMC.keyInfoSize(CHIE) == 1)
if !useCHTE && !hasCHIE {
    log("This machine has neither CHTE nor CHIE; cannot control charging; release and exit")
    allowCharging()
    exit(0)
}
signal(SIGTERM) { _ in failSafeExit(0) }
signal(SIGINT) { _ in failSafeExit(0) }
atexit { allowCharging() }
log("started; actuator=\(useCHTE ? "CHTE(charge-disable)" : "CHIE(adapter-disable fallback)"); discharge=\(hasCHIE ? "available" : "unavailable"); config=\(configPath)")

// MARK: Main loop

var holding = false
var discharging = false
var loggedNoCHIE = false
var lastFullCharge = readLastFullCharge()
var lastSoc = -1
var lastTempC: Double = -1
/// When charging is allowed but the battery is not charging, macOS may be
/// enforcing its own native Charge Limit. Track how long that lasts.
var notChargingSince: Date?
/// Last configured limit, so raising it can release an existing hold.
var lastConfiguredLimit = -1

/// Publishes what the daemon is doing so the app can explain the pause reason
/// and hide unsupported controls (e.g. discharge without CHIE).
func publishState(_ cfg: Config, _ reason: String) {
    let obj: [String: Any] = [
        "schemaVersion": 1,
        "ts": Date().timeIntervalSince1970,
        "holding": holding,
        "discharging": discharging,
        "actuator": useCHTE ? "CHTE" : "CHIE",
        "chieAvailable": hasCHIE,
        "soc": lastSoc,
        "tempC": lastTempC,
        "reason": reason,
        "enabled": cfg.enabled,
        "limit": cfg.limit,
        "topUp": cfg.topUp,
    ]
    if let data = try? JSONSerialization.data(withJSONObject: obj) {
        try? data.write(to: URL(fileURLWithPath: statePath), options: .atomic)
    }
}

func calibrationDue(_ cfg: Config) -> Bool {
    guard cfg.calibrationDays > 0, cfg.limit < 100, !cfg.discharge else { return false }
    return Date().timeIntervalSince(lastFullCharge) >= Double(cfg.calibrationDays) * 86_400
}

while true {
    let cfg = readConfig()
    nativeHoldActive = !useCHTE && cfg.nativeHold
    guard let bat = readBattery(), bat.soc >= 0 else {
        if holding || discharging { allowCharging(); holding = false; discharging = false }
        lastSoc = -1
        lastTempC = -1
        publishState(cfg, "noBattery")
        Thread.sleep(forTimeInterval: 10)
        continue
    }
    lastSoc = bat.soc
    lastTempC = bat.tempC ?? -1

    // Full charge -> record calibration baseline (also covers manual full charges)
    if bat.soc >= 100 || bat.fullyCharged { lastFullCharge = Date(); writeLastFullCharge(lastFullCharge) }

    // MARK: Heat protection
    // Independent of the limit: pause charging while the pack is too hot.
    // Safety wins over a pending top-up request.
    if cfg.heatProtectionC > 0, cfg.enabled, bat.externalConnected, let t = bat.tempC, t >= Double(cfg.heatProtectionC) {
        if discharging { discharging = false }
        if !holding {
            holding = true
            log("battery \(String(format: "%.1f", t))C >= \(cfg.heatProtectionC)C -> hold charging (heat)")
        }
        holdChargingForHeat()
        publishState(cfg, "heat")
        Thread.sleep(forTimeInterval: 10)
        continue
    }

    // Not enabled / limit = 100 / cable unplugged -> release and reconnect.
    // 주의: CHIE 로 어댑터를 끊거나 hold 중이면 SMC 가 ExternalConnected=false 로
    // 보이므로, 우리가 의도적으로 억제한 상태는 "케이블 뽑힘"으로 보지 않습니다.
    // A native hold keeps the adapter connected, so it hides nothing.
    let adapterSuppressed = (holding && !nativeHoldActive) || discharging
    if !cfg.enabled || cfg.limit >= 100 || (!bat.externalConnected && !adapterSuppressed) {
        if holding || discharging {
            allowCharging()
            holding = false
            discharging = false
        }
        publishState(cfg, (!bat.externalConnected && !adapterSuppressed) ? "adapterOff" : "off")
        Thread.sleep(forTimeInterval: 10)
        continue
    }

    // MARK: Discharge mode (adapter disconnect via CHIE)
    if cfg.discharge && hasCHIE {
        if bat.soc > cfg.limit {
            if !discharging {
                discharging = true
                holding = false
                disconnectAdapter()
                log("discharge -> adapter disconnected (SoC \(bat.soc)% > target \(cfg.limit)%)")
            } else {
                disconnectAdapter() // periodic re-assert (survive sleep/wake)
            }
            publishState(cfg, "discharge")
            Thread.sleep(forTimeInterval: 10)
            continue
        } else if discharging {
            discharging = false
            allowCharging()
            log("discharge target reached (SoC \(bat.soc)% <= \(cfg.limit)%) -> reconnect and hold")
            // fall through to normal hold logic
        }
    } else {
        if cfg.discharge && !hasCHIE && !loggedNoCHIE {
            loggedNoCHIE = true
            log("discharge requested but CHIE not available on this machine; ignoring")
        }
        if !cfg.discharge {
            loggedNoCHIE = false
            // 방전 도중 사용자가 토글을 끄면 즉시 어댑터를 다시 연결합니다.
            if discharging {
                discharging = false
                allowCharging()
                log("discharge cancelled -> adapter reconnected")
            }
        }
    }

    // MARK: One-shot top-up (charge to 100% once, then consume the request)
    if cfg.topUp {
        if bat.soc >= 100 {
            clearTopUpFlag(cfg)
            log("top-up complete (100%) -> clearing request")
            var done = cfg
            done.topUp = false
            publishState(done, "limit")
            Thread.sleep(forTimeInterval: 10)
            continue
        }
        if holding { holding = false }
        if discharging { discharging = false }
        allowCharging()
        publishState(cfg, "topUp")
        Thread.sleep(forTimeInterval: 10)
        continue
    }

    // MARK: Auto-calibration
    if calibrationDue(cfg) {
        if holding { allowCharging(); holding = false }
        log("calibrating -> release and charge to 100% (last full charge \(Int(Date().timeIntervalSince(lastFullCharge) / 86_400)) days ago)")
        publishState(cfg, "calibration")
        Thread.sleep(forTimeInterval: 30)
        continue
    }

    // MARK: Charge limit (sailing / hard-stop)
    let upper = cfg.limit
    let lower = max(20, cfg.limit - cfg.deadband)

    // Raising the limit must release a hold immediately, otherwise sailing
    // hysteresis keeps the adapter off until SoC falls below the old lower bound.
    if lastConfiguredLimit >= 0, cfg.limit > lastConfiguredLimit,
       bat.soc < cfg.limit, holding {
        holding = false
        allowCharging()
        log("limit raised \(lastConfiguredLimit)% -> \(cfg.limit)% -> release hold")
    }
    lastConfiguredLimit = cfg.limit

    if bat.soc >= upper {
        if !holding {
            holding = true
            holdCharging()
            log("SoC \(bat.soc)% >= \(upper)% -> hold charging")
        } else {
            holdCharging() // periodic rewrite to survive sleep/wake resets
        }
    } else if cfg.sailingMode {
        // Sailing: keep state inside the deadband, recharge only below the lower bound.
        if bat.soc <= lower {
            if holding {
                holding = false
                log("SoC \(bat.soc)% <= \(lower)% -> restore charging (sailing)")
            }
            allowCharging() // periodic re-assert
        } else {
            if holding { holdCharging() } else { allowCharging() }
        }
    } else {
        // Hard stop: recharge whenever SoC drops below the limit.
        if holding {
            holding = false
            log("SoC \(bat.soc)% < \(upper)% -> restore charging (hard stop)")
        }
        allowCharging() // periodic re-assert
    }
    if holding {
        notChargingSince = nil
        publishState(cfg, "limit")
    } else if bat.externalConnected, !bat.isCharging, bat.soc < upper {
        // We allow charging but the pack is not charging while plugged in.
        // macOS 26.4+ has its own Charge Limit that can be lower than ours.
        if notChargingSince == nil { notChargingSince = Date() }
        if nativeHoldActive {
            // Expected: macOS is holding at the same limit on our behalf.
            publishState(cfg, "limit")
        } else if let since = notChargingSince, Date().timeIntervalSince(since) >= 30 {
            publishState(cfg, "systemHold")
        } else {
            publishState(cfg, "charging")
        }
    } else {
        notChargingSince = nil
        publishState(cfg, "charging")
    }
    Thread.sleep(forTimeInterval: 10)
}
