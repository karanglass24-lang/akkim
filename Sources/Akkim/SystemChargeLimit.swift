// Portions of this file are derived from ChargeWatching
// (https://github.com/TY-teo/ChargeWatching), MIT License,
// Copyright (c) 2026 TY-teo. See LICENSE and THIRD-PARTY-NOTICES.md.

import Foundation
import ObjectiveC

/// Apple's private `PowerUISmartChargeClient` (PowerUI.framework) — the very
/// object the Shortcuts action **Set Battery Charge Limit** talks to.
///
/// Calling it directly lets Akkim move macOS's own Charge Limit with no
/// Shortcuts setup at all. Everything is feature-detected: if a future macOS
/// renames the class or its methods, the app reports "unsupported" and falls
/// back to the Shortcuts bridge instead of crashing.
///
/// The framework binary lives in the dyld shared cache (no file on disk), so
/// it is loaded with `dlopen` by path and driven through the Objective-C
/// runtime. No private headers, no link-time dependency.
@objc private protocol SmartChargeClient {
    func isMCLSupported() -> Bool
    func getMCLLimitWithError(_ error: AutoreleasingUnsafeMutablePointer<NSError?>?) -> Int32
    func setMCLLimit(_ limit: Int32, error: AutoreleasingUnsafeMutablePointer<NSError?>?) -> Bool
    func availableChargeLimitsWithError(_ error: AutoreleasingUnsafeMutablePointer<NSError?>?) -> Any?
}

enum SystemChargeLimit {
    static let powerUIPath = "/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI"
    /// Client name reported to powerd (shows up in its logs).
    static let clientName = "com.akkim.app"

    private static let lock = NSLock()
    private static var cachedClient: SmartChargeClient?
    private static var probed = false

    // MARK: Client

    private static func client() -> SmartChargeClient? {
        lock.lock()
        defer { lock.unlock() }
        if probed { return cachedClient }
        probed = true

        guard dlopen(powerUIPath, RTLD_LAZY) != nil else { return nil }
        guard let cls = NSClassFromString("PowerUISmartChargeClient") else { return nil }

        // objc_msgSend is variadic (and therefore unavailable in Swift), so the
        // init IMP is fetched from the method list instead.
        let allocSelector = sel_registerName("alloc")
        guard let allocMethod = class_getInstanceMethod(object_getClass(cls), allocSelector),
              let initMethod = class_getInstanceMethod(cls, sel_registerName("initWithClientName:"))
        else { return nil }

        typealias AllocFn = @convention(c) (AnyClass, Selector) -> Unmanaged<AnyObject>
        typealias InitFn = @convention(c) (AnyObject, Selector, NSString) -> Unmanaged<AnyObject>
        let allocate = unsafeBitCast(method_getImplementation(allocMethod), to: AllocFn.self)
        let initialize = unsafeBitCast(method_getImplementation(initMethod), to: InitFn.self)

        let raw = allocate(cls, allocSelector).takeUnretainedValue()
        let object = initialize(raw,
                                sel_registerName("initWithClientName:"),
                                clientName as NSString).takeRetainedValue()

        // The class does not declare our protocol, so verify every selector we
        // are about to send before reinterpreting the object.
        let required = ["isMCLSupported", "getMCLLimitWithError:", "setMCLLimit:error:"]
        guard required.allSatisfy({ object.responds(to: sel_registerName($0)) }) else { return nil }

        let typed = unsafeBitCast(object, to: SmartChargeClient.self)
        cachedClient = typed
        return typed
    }

    /// `true` when this macOS exposes the charge-limit API and it reports support.
    static var isAvailable: Bool {
        guard let client = client() else { return false }
        return client.isMCLSupported()
    }

    // MARK: Read

    /// The macOS charge limit (80–100), or `nil` when unavailable.
    static func currentLimit() -> Int? {
        guard let client = client() else { return nil }
        var error: NSError?
        let value = client.getMCLLimitWithError(&error)
        guard error == nil, value > 0 else { return nil }
        return Int(value)
    }

    /// Values the system accepts (80, 85, 90, 95, 100 on supported hardware).
    static func availableLimits() -> [Int] {
        guard let client = client() else { return [] }
        var error: NSError?
        guard let raw = client.availableChargeLimitsWithError(&error), error == nil else { return [] }
        guard let list = raw as? [Any] else { return [] }
        return list.compactMap { ($0 as? NSNumber)?.intValue }
    }

    // MARK: Write

    static func setLimit(_ percent: Int) throws {
        guard let client = client() else {
            throw SystemChargeLimitError.unavailable
        }
        var error: NSError?
        guard client.setMCLLimit(Int32(percent), error: &error) else {
            throw error ?? SystemChargeLimitError.failed("setMCLLimit(\(percent))")
        }
    }
}

enum SystemChargeLimitError: LocalizedError {
    case unavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return L10n.t(.errSystemControlUnavailable)
        case .failed(let detail):
            return L10n.t(.errSystemControlFailed) + " (\(detail))"
        }
    }
}
