// Portions of this file are derived from ChargeWatching
// (https://github.com/TY-teo/ChargeWatching), MIT License,
// Copyright (c) 2026 TY-teo. See LICENSE and THIRD-PARTY-NOTICES.md.

import Foundation
import AppKit

/// macOS 26.4+ 의 시스템 네이티브 배터리 충전 제한을
/// Shortcuts 액션으로 제어하는 bridge.
///
/// 두 가지 구성을 지원합니다.
/// 1. `SetBatteryChargeLimit` 하나에 “Set Charge Limit” 동작을 넣고 값을
///    Shortcut Input 으로 받는 방식 (텍스트 입력 전달)
/// 2. 값이 고정된 단축어 5개: `SetBatteryChargeLimit80`, `…85`, `…90`, `…95`, `…100`
final class ShortcutBridge {
    let shortcutName: String

    init(shortcutName: String = ChargeLimitConstants.shortcutName) {
        self.shortcutName = shortcutName
    }

    private func levelName(_ percent: Int) -> String {
        "\(shortcutName)\(percent)"
    }

    private func shortcutNames() async -> Set<String> {
        let result = await ProcessRunner.run("/usr/bin/shortcuts", ["list"], timeout: 3)
        guard result.exitCode == 0 else { return [] }
        return Set(
            result.stdout
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    func isBridgeAvailable() async -> Bool {
        let names = await shortcutNames()
        if names.contains(shortcutName) { return true }
        return ChargeLimitConstants.steps.allSatisfy { names.contains(levelName($0)) }
    }

    func set(percent: Int) async throws {
        let names = await shortcutNames()

        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "run-shortcut"

        let targetName: String
        // Prefer the fixed-value shortcuts: the “Set Charge Limit” action only
        // offers fixed percentages, so these are the reliable path.
        if names.contains(levelName(percent)) {
            targetName = levelName(percent)
            components.queryItems = [URLQueryItem(name: "name", value: targetName)]
        } else if names.contains(shortcutName) {
            targetName = shortcutName
            components.queryItems = [
                URLQueryItem(name: "name", value: shortcutName),
                URLQueryItem(name: "input", value: "text"),
                URLQueryItem(name: "text", value: String(percent)),
            ]
        } else {
            throw ChargeLimitError.failed(
                String(format: L10n.t(.errShortcutMissing), levelName(percent))
            )
        }

        guard let url = components.url else {
            throw ChargeLimitError.failed(L10n.t(.errShortcutBuild))
        }
        let opened = await MainActor.run { NSWorkspace.shared.open(url) }
        if !opened {
            throw ChargeLimitError.failed(String(format: L10n.t(.errShortcutMissing), targetName))
        }
    }
}
