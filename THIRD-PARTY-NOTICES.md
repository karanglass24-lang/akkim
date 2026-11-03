# Third-Party Notices

Akkim is a derivative work based on **ChargeWatching**. The original
project and this derivative are distributed under the MIT License (see
[LICENSE](LICENSE)).

The MIT requirement is that the copyright notice and permission notice are
included in all copies or substantial portions of the software. They are
reproduced in [LICENSE](LICENSE) and shipped with every distributed copy,
including the `.app` bundle.

## ChargeWatching (required attribution)

- Project: ChargeWatching (application name: ChargeWatch)
- Source: <https://github.com/TY-teo/ChargeWatching>
- License: MIT
- Copyright (c) 2026 TY-teo

Substantial portions of the following files are derived from ChargeWatching:

- `Package.swift`
- `scripts/install-helper.sh`
- `Sources/Akkim/AppContainer.swift`
- `Sources/Akkim/AppDelegate.swift`
- `Sources/Akkim/AkkimApp.swift`
- `Sources/Akkim/ChargeLimitController.swift`
- `Sources/Akkim/ChargeLimitTypes.swift`
- `Sources/Akkim/MenuBarPanel.swift`
- `Sources/Akkim/ProcessRunner.swift`
- `Sources/Akkim/SMCChargeLimiter.swift`
- `Sources/Akkim/SampleStream.swift`
- `Sources/Akkim/SettingsView.swift`
- `Sources/Akkim/ShortcutBridge.swift`
- `Sources/Akkim/StatusBarController.swift`
- `Sources/Akkim/PowerCore/IORegistryReader.swift`
- `Sources/Akkim/PowerCore/PowerSample.swift`
- `Sources/Akkim/PowerCore/PowerSampler.swift`
- `Sources/AkkimHelper/main.swift`

Files that are original to Akkim (not derived from ChargeWatching):

- `Sources/Akkim/AppSettings.swift`
- `Sources/Akkim/BatteryGaugeView.swift`
- `Sources/Akkim/HistoryChartView.swift`
- `Resources/Info.plist`
- `scripts/package-app.sh`
- `ui-mockup.html`

## Technical references

The following projects were used as references for the publicly documented
Apple SMC interface and the macOS charge-control mechanism. See the
ChargeWatching attribution above for the code lineage.

- **batt** — <https://github.com/actuallymentor/battery> — MIT License,
  Copyright (c) 2022 Mentor Palokaj.
- **SMCKit** — <https://github.com/beltex/SMCKit> — MIT License,
  Copyright (c) 2014-2017 beltex.
- **smcFanControl** — <https://github.com/hholtmann/smcFanControl> — GPL-2.0.
  Not included and not linked. No GPL-2.0 code or binary is distributed with
  this project.

## Trademarks

The project name is **아낌 (Akkim)**, a common Korean noun meaning "saving /
sparing". It was chosen as a descriptive brand for this app. It is not
affiliated with, endorsed by, or sponsored by any financial institution or
financial product that uses a similar word (for example "아낌e보금자리론"),
nor with any other company or product.

"Al Dente" / "AlDente" is a product and trademark of AppHouseKitchen
(David Wernhart and Matthias Kerbl). Akkim is an independent project.
It is not affiliated with, endorsed by, or sponsored by AppHouseKitchen. The
name is mentioned only to describe the general category of battery charge
limiting software.

Apple, macOS, MacBook, and SF Symbols are trademarks of Apple Inc. This
project uses Apple system frameworks and SF Symbols through their public
runtime APIs on Apple platforms only.
