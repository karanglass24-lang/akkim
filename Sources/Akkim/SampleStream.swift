// Portions of this file are derived from ChargeWatching
// (https://github.com/TY-teo/ChargeWatching), MIT License,
// Copyright (c) 2026 TY-teo. See LICENSE and THIRD-PARTY-NOTICES.md.

import Foundation
import Combine

@MainActor
final class SampleStream: ObservableObject {
    @Published private(set) var latest: PowerSample?
    @Published private(set) var rolling: [PowerSample] = []

    private var bag: Set<AnyCancellable> = []

    init(sampler: PowerSampler) {
        sampler.$latest
            .receive(on: RunLoop.main)
            .assign(to: \.latest, on: self)
            .store(in: &bag)
        sampler.$rolling
            .receive(on: RunLoop.main)
            .assign(to: \.rolling, on: self)
            .store(in: &bag)
    }
}
