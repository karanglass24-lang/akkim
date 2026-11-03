// Portions of this file are derived from ChargeWatching
// (https://github.com/TY-teo/ChargeWatching), MIT License,
// Copyright (c) 2026 TY-teo. See LICENSE and THIRD-PARTY-NOTICES.md.

import Foundation
import Combine

@MainActor
final class AppContainer {
    let sampleStream: SampleStream
    let chargeLimitController: ChargeLimitController
    let smcLimiter: SMCChargeLimiter
    let settings: AppSettings
    let healthHistory: BatteryHealthHistory
    let energyUsage: EnergyUsageStore
    private let sampler: PowerSampler

    init() {
        let sampler = PowerSampler()
        self.sampler = sampler
        self.sampleStream = SampleStream(sampler: sampler)
        self.healthHistory = BatteryHealthHistory()
        self.energyUsage = EnergyUsageStore()

        // 하나의 리미터 인스턴스를 공유해야 설정 파일 기록과 상태가 어긋나지 않습니다.
        let limiter = SMCChargeLimiter()
        self.smcLimiter = limiter
        self.chargeLimitController = ChargeLimitController(limiter: limiter, bridge: ShortcutBridge())
        self.settings = AppSettings.shared
    }

    func start() {
        sampler.start()
    }

    func stop() {
        sampler.stop()
    }
}
