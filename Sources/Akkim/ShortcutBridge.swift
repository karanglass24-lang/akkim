// Portions of this file are derived from ChargeWatching
// (https://github.com/TY-teo/ChargeWatching), MIT License,
// Copyright (c) 2026 TY-teo. See LICENSE and THIRD-PARTY-NOTICES.md.

import Foundation
import AppKit

/// macOS 26.4+ 의 시스템 네이티브 배터리 충전 제한을
/// Shortcuts 액션(`SetBatteryChargeLimit`)을 통해 제어하는 bridge.
final class ShortcutBridge {
    let shortcutName: String

    init(shortcutName: String = ChargeLimitConstants.shortcutName) {
        self.shortcutName = shortcutName
    }

    func isBridgeAvailable() async -> Bool {
        let result = await ProcessRunner.run("/usr/bin/shortcuts", ["list"], timeout: 3)
        guard result.exitCode == 0 else { return false }
        return result.stdout
            .split(separator: "\n")
            .contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == shortcutName }
    }

    func set(percent: Int) async throws {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "run-shortcut"
        components.queryItems = [
            URLQueryItem(name: "name", value: shortcutName),
            URLQueryItem(name: "input", value: "text"),
            URLQueryItem(name: "text", value: String(percent)),
        ]
        guard let url = components.url else {
            throw ChargeLimitError.failed(L10n.t(.errShortcutBuild))
        }
        let opened = await MainActor.run { NSWorkspace.shared.open(url) }
        if !opened {
            throw ChargeLimitError.failed(String(format: L10n.t(.errShortcutMissing), shortcutName))
        }
    }
}
