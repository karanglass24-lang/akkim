# 아낌(Akkim) 인수인계 문서

- 작성일: 2026-11-03
- 목적: Windows에서 작성한 코드를 macOS 실기기로 옮겨 컴파일·설치·검증을 이어가기 위한 핸드오프
- 현재 코드 위치(Windows): `C:\Users\karan\OneDrive\문서\기본 프로젝트\battery-limit`
- 목표 저장소: <https://github.com/karanglass24-lang/akkim>
- 현재 폴더명은 `battery-limit`이지만 앱/번들/브랜드는 모두 **Akkim(아낌)** 입니다.

> **현재 상태**: 2026-11-03에 macOS 27.0.1 / Swift 6.4.2에서 debug·release 빌드와
> `dist/Akkim.app` 패키징·서명 검증까지 통과했습니다. 다음 단계는 실기기 체크리스트(6장)와
> 헬퍼 설치 후 SMC 동작 확인입니다.

---

## 0. 한 줄 요약

Apple Silicon Mac용 메뉴바 앱. SMC `CHTE`/`CHIE`를 제어하는 root LaunchDaemon 헬퍼로
충전 제한·세일링·방전·만충전·열 보호를 수행하고, 앱은 전력/건강도/차트/알림을 보여줍니다.
최신 배치에서 **헬퍼 상태 IPC, 원샷 만충전, 열 보호, 메뉴바 우클릭 메뉴, 표시 옵션,
SoC 차트, 사유 기반 알림**을 추가했습니다.

---

## 1. 현재 상태

### 1.1 완료된 것

| 영역 | 내용 |
|---|---|
| 앱 기본 | 충전 제한, 세일링/하드스톱, 방전, 자동 보정, 전력·건강도 모니터링 |
| 안정성(P0) | JSON 원자적 쓰기, 데몬 last-good-config(약 60초), 권한 775/664 자동 교정, 서명 순서, 알림 게이팅, 구 데몬(`com.batterylimit.helper`) 제거 |
| UX(P1) | 관리자 인증 비블로킹(`Process.terminationHandler`), 제한 on/off 토글, `shortcuts list` 프로브 캐싱 |
| 이번 배치 | 헬퍼 상태 파일, 일시정지 사유, 원샷 만충전, 열 보호, 우클릭 빠른 메뉴, 메뉴바 표시 옵션, SoC 스파크라인, 알림 세분화 |
| 지역화 | `LKey` **120개**, `LKey.text` exhaustive switch |
| 패키징 | `scripts/package-app.sh`, ad-hoc 서명, MIT 고지 파일 번들 포함 |
| CI | `.github/workflows/build.yml` (macos-14, build → package → signature/bundle 검증 → artifact) |

### 1.2 아직 검증되지 않은 것

- 실제 SMC `CHTE`/`CHIE` 동작, 열 보호, 만충전, 방전
- 메뉴바 우클릭 이벤트 전달
- GitHub 저장소 push 및 CI 실행

### 1.3 Mac 빌드 검증 결과 (2026-11-03)

- 환경: macOS 27.0.1, Apple Swift 6.4.2 (arm64), Command Line Tools
- `swift build`: 성공
- `swift build -c release` + `bash scripts/package-app.sh`: 성공
- `codesign --verify --deep --strict dist/Akkim.app`: 성공
- 번들 내용 확인: `MacOS/Akkim`,
  `Resources/{LICENSE, THIRD-PARTY-NOTICES.md, akkim-helper, install-helper.sh}`,
  `Info.plist`(`com.akkim.app`, `아낌`, `LSUIElement=true`)
- 컴파일 오류 3건 수정 (5.1 참고). Swift Charts와 `Process.terminationHandler`에서는
  오류가 나오지 않았습니다.
- 실행 스모크 테스트: `open dist/Akkim.app` → 6초 후 프로세스 유지, 크래시 리포트 없음,
  `osascript` 종료 정상.

---

## 2. Mac에서 시작하기

### 2.1 필요 환경

- Apple Silicon Mac (M1–M4)
- macOS 13 이상
- Xcode 15 이상 또는 Command Line Tools (Swift 5.9)
- 관리자 계정 (헬퍼 설치 시 비밀번호 필요)

확인:

```bash
swift --version
xcodebuild -version
uname -m          # arm64 여야 함
```

### 2.2 코드 가져오기

OneDrive 동기화 폴더를 그대로 쓰거나, zip/복사로 옮깁니다.

```bash
cd ~/path/to/battery-limit
# 또는 저장소를 새로 만들 경우
git init
git add .
git commit -m "Initial Akkim import"
git remote add origin https://github.com/karanglass24-lang/akkim.git
```

> 폴더명을 `akkim`으로 바꾸는 것은 선택 사항입니다. README의 예시는 `cd akkim` 기준입니다.

### 2.3 빌드

```bash
cd battery-limit
swift build                 # debug
swift build -c release      # release
```

컴파일 오류가 나오면 **이 단계에서 먼저 수정**합니다. (아래 11장 참고)

### 2.4 앱 번들 패키징 및 실행

```bash
chmod +x scripts/package-app.sh scripts/install-helper.sh
bash scripts/package-app.sh
open dist/Akkim.app
```

권장: 로그인 시 자동 실행(`SMAppService`)을 쓰려면 앱을 `/Applications`로 옮겨서 실행하세요.

```bash
cp -R dist/Akkim.app /Applications/
open /Applications/Akkim.app
```

### 2.5 헬퍼 설치

앱에서 충전 제한을 처음 켜면 관리자 인증 창이 뜨고 자동 설치됩니다.
수동 설치:

```bash
sudo bash scripts/install-helper.sh install "$(pwd)/dist/Akkim.app/Contents/Resources/akkim-helper"
```

확인:

```bash
sudo launchctl print system/com.akkim.helper | grep -E "state =|pid ="
tail -n 50 /var/log/akkim-helper.log
cat /Users/Shared/Akkim/smc-limit.json
cat /Users/Shared/Akkim/helper-state.json
```

---

## 3. 프로젝트 구조

```
battery-limit/
├── Package.swift                 # tools 5.9, macOS 13, Charts/IOKit/AppKit 링크
├── README.md
├── LICENSE                       # MIT + ChargeWatching 고지
├── THIRD-PARTY-NOTICES.md
├── Resources/Info.plist
├── Resources/AppIcon.icns      # 앱 아이콘
├── ui-mockup.html                # UI 참고용 목업
├── scripts/
│   ├── package-app.sh            # release build → dist/Akkim.app → ad-hoc 서명
│   └── install-helper.sh         # LaunchDaemon 설치/제거, 구 데몬 마이그레이션
├── .github/workflows/build.yml   # macOS CI (컴파일/서명/번들 검증)
├── Sources/Akkim/
│   ├── AppMain.swift             # AppKit @main 엔트리포인트
│   ├── AppDelegate.swift         # 상태바/설정 창, 종료 처리
│   ├── AppContainer.swift        # 의존성 조립
│   ├── AppSettings.swift         # UserDefaults 설정 + MenuBarDisplay
│   ├── ChargeLimitController.swift
│   ├── ChargeLimitTypes.swift
│   ├── SMCChargeLimiter.swift    # 설정 파일 쓰기, 헬퍼 설치, topUp/heat
│   ├── HelperStatus.swift        # helper-state.json 모델 + mtime 캐시
│   ├── ShortcutBridge.swift      # macOS 26.4+ Shortcuts 경로
│   ├── StatusBarController.swift # 메뉴바, 우클릭 메뉴, 알림, 표시 모드
│   ├── MenuBarPanel.swift        # 팝오버 UI
│   ├── SettingsView.swift
│   ├── HistoryChartView.swift    # 전력 + SoC 차트
│   ├── Localization.swift        # LKey 120개 (ko/en)
│   ├── MenuBarIcon.swift         # 메뉴바 배터리 글리프(AppKit 직접 그리기)
│   ├── BatteryHealthHistory.swift # 건강도 샘플 저장/추이
│   ├── BatteryHealthChart.swift   # Swift Charts 건강도 영역 그래프
│   ├── EnergyUsageStore.swift     # 일별 에너지 적분/저장
│   ├── EnergyUsageChart.swift     # 14일 막대 차트
│   ├── BatteryGaugeView.swift
│   ├── SampleStream.swift
│   ├── ProcessRunner.swift
│   └── PowerCore/
│       ├── IORegistryReader.swift
│       ├── PowerSample.swift
│       └── PowerSampler.swift
└── Sources/AkkimHelper/
    └── main.swift                # root 데몬: SMC 제어 + 상태 발행
```

---

## 4. 동작 원리

### 4.1 데몬 제어 우선순위

`Sources/AkkimHelper/main.swift`의 메인 루프는 매 10초마다 설정을 다시 읽고 아래 순서로 판단합니다.

1. **열 보호** — `heatProtectionC > 0 && enabled && 어댑터 연결 && temp >= 임계값` → 충전 홀드
2. **비활성/어댑터 없음** — `!enabled || limit >= 100 || 케이블 뽑힘` → 충전 허용
3. **방전** — `discharge && CHIE 사용 가능 && soc > limit` → 어댑터 분리
4. **원샷 만충전** — `topUp && soc < 100` → 충전 허용, 100% 도달 시 플래그 해제
5. **자동 보정** — `calibrationDays` 경과 → 100%까지 충전 허용
6. **일반 제한** — 세일링(하한 `limit - deadband`) 또는 하드스톱

### 4.2 SMC 키

- `CHTE` (ui32): `0x00000001` = 충전 홀드, `0` = 허용 (주 제어)
- `CHIE` (ui8): `0x00` = 어댑터 연결, `0x08` = 분리 (폴백/방전)
- 종료/시그널/크래시 시 `atexit` + signal handler로 충전 허용 복구

### 4.3 파일 IPC

**설정** `/Users/Shared/Akkim/smc-limit.json` (앱이 원자적으로 씀, 데몬이 읽음)

```json
{
  "schemaVersion": 1,
  "enabled": true,
  "limit": 80,
  "deadband": 5,
  "calibrationDays": 7,
  "sailingMode": true,
  "discharge": false,
  "heatProtectionC": 0,
  "topUp": false
}
```

- `heatProtectionC`: 0=끔, 유효 범위 30–60
- `topUp`: 원샷. 데몬이 100% 도달 시 `topUp:false`로 다시 씀
- `enabled:false`이면 `topUp`은 무시되고, 앱도 재시작 시 플래그를 정리

**상태** `/Users/Shared/Akkim/helper-state.json` (데몬이 씀, 앱이 읽음)

```json
{
  "schemaVersion": 1,
  "ts": 1767225600,
  "holding": true,
  "discharging": false,
  "actuator": "CHTE",
  "chieAvailable": true,
  "soc": 80,
  "tempC": 33.4,
  "reason": "limit",
  "enabled": true,
  "limit": 80,
  "topUp": false
}
```

- `reason`: `off`, `noBattery`, `adapterOff`, `discharge`, `topUp`, `heat`, `calibration`, `limit`, `charging`
- 앱은 5초마다 mtime 캐시로 읽고, 30초 초과 시 stale로 간주

**보정** `/Users/Shared/Akkim/calib-state.json`

```json
{"lastFullChargeAt": 1767225600}
```

### 4.4 앱 폴링

| 타이머 | 주기 | 역할 |
|---|---|---|
| `ChargeLimitController.helperTimer` | 5초 | `helper-state.json` 읽기, topUp 동기화, CHIE 미지원 시 방전 토글 자동 해제 |
| `startPolling()` (팝오버 열림) | 3초 | 전체 상태 refresh, `shortcuts list` 캐시 사용 |
| `PowerSampler` | 샘플 주기 | 전력/온도/건강도 스트림 |

### 4.5 만충전(top-up) 수명주기

1. 앱: `topUp:true`, `enabled:true` 기록 (`discharge:false`로 자동 전환)
2. 데몬: 최대 10초 내 읽고 충전 허용, `reason:"topUp"` 발행
3. 100% 도달: 데몬이 `topUp:false`로 설정 파일 재작성, `reason:"limit"`
4. 앱: 5초 폴링에서 동기화. 요청 직후 15초는 stale 상태를 무시하는 유예 구간

---

## 5. 이번 배치에서 바뀐 파일

| 파일 | 변경 |
|---|---|
| `Sources/AkkimHelper/main.swift` | `Battery.tempC`, `Config.heatProtectionC/topUp`, 상태 발행, 열 보호/만충전 분기, 권한 대상 추가 |
| `Sources/Akkim/HelperStatus.swift` | 신규. 상태 파일 모델 + `readCached()` |
| `Sources/Akkim/AppSettings.swift` | `heatProtectionC`, `menuBarDisplay`, `MenuBarDisplay` enum |
| `Sources/Akkim/SMCChargeLimiter.swift` | `heatProtectionC`/`topUp` 쓰기·읽기, `requestTopUp/cancelTopUp/syncTopUp`, `disable()` 시 topUp 정리 |
| `Sources/Akkim/ChargeLimitController.swift` | `helperStatus`, `isTopUpActive`, `toggleTopUp`, `dischargeUnsupported`, `helperUnresponsive`, `reasonKey`, 5초 헬퍼 타이머 |
| `Sources/Akkim/MenuBarPanel.swift` | 사유 표시, 만충전 버튼, 방전 비활성/안내, 열 보호 힌트, SoC 차트 연결 |
| `Sources/Akkim/SettingsView.swift` | 열 보호 피커, 메뉴바 표시 피커, 창 높이 650 |
| `Sources/Akkim/StatusBarController.swift` | 우클릭 메뉴, 표시 모드, 사유 기반 알림 |
| `Sources/Akkim/HistoryChartView.swift` | SoC 스파크라인 + 제한선/하한선 |
| `Sources/Akkim/Localization.swift` | 키 68 → 95개 |
| `Sources/Akkim/AppDelegate.swift` | 종료 시 topUp 취소, 설정 창 높이 |
| `scripts/install-helper.sh` | 기본 설정 JSON에 새 필드 추가 |
| `README.md` | 기능/스키마/상태 파일/업그레이드 안내 |

### 5.1 Mac 첫 빌드에서 수정한 컴파일 오류

| 파일 | 오류 | 수정 |
|---|---|---|
| `Sources/Akkim/ChargeLimitController.swift` | `@MainActor`인 `SMCChargeLimiter()`를 기본 인자값에서 생성 → nonisolated 동기 컨텍스트 호출 오류 | 기본값 제거, 공유 리미터를 주입받도록 `init(limiter:bridge:)`로 변경 |
| `Sources/Akkim/StatusBarController.swift` | `PowerSample?`를 `notifyIfNeeded(sample:)`의 비옵셔널 인자로 전달 | `if let sample { ... }`로 언랩 후 호출 |
| `Sources/Akkim/StatusBarController.swift` | `super.init()` 이전에 `popover.delegate = self`로 `self` 사용 | `super.init()` 이후로 이동 |

> 동작 변경은 없습니다. 세 건 모두 타입/초기화 순서 문제입니다.

### 5.2 후속 배치: CHIE 폴백 표시 + 온도 소스 (2026-11-03)

| 파일 | 변경 |
|---|---|
| `Sources/Akkim/Localization.swift` | `reasonLimitAdapterOff`, `heatUnavailable` 추가 (LKey 95 → 97) |
| `Sources/Akkim/ChargeLimitController.swift` | `reasonKey`: `reason == .limit && actuator == "CHIE"`이면 어댑터 분리 문구 반환 |
| `Sources/Akkim/MenuBarPanel.swift` | 새 제한 사유에도 `· 80%` 표시, 온도를 읽을 수 없을 때 열 보호 경고 |
| `Sources/Akkim/PowerCore/IORegistryReader.swift` | 온도를 `AppleSmartBatteryPack.BatteryData.Temperature`에서도 읽기 |
| `Sources/AkkimHelper/main.swift` | 동일한 온도 폴백 (`readBatteryTemperature`) |

- `AppleSmartBatteryPack`의 `BatteryData.Temperature`는 centi-°C입니다 (예: `3109` → 31.09℃).
- 상위 `AppleSmartBattery`의 `Temperature`/`BatteryData`가 있는 구형 기기는 기존 경로를 먼저 사용합니다.

### 5.3 메뉴바 배터리 아이콘 (2026-11-03)

- 기존 코드는 `battery.fill`, `battery.2`, `magnet`을 사용했지만 모두 존재하지 않는
  SF Symbol이라 메뉴바에 아이콘이 표시되지 않았습니다.
- `Sources/Akkim/MenuBarIcon.swift` 추가: AppKit으로 직접 그리는 template 배터리 글리프.
  - 잔량에 비례해 채워지는 둥근 외곽 + 단자
  - 충전 중에는 번개를 cutout(메뉴바 배경색이 비쳐 보임)
  - template 이미지라 라이트/다크 메뉴바에 자동 대응
  - 배터리가 없는 데스크톱은 `powerplug` SF Symbol 사용
- `StatusBarController.applyDisplay`가 `MenuBarIcon.image(for:)`를 사용하도록 변경.
- Settings > General에 **메뉴바 아이콘** 피커 추가: `배터리(잔량)` / `충전 배터리` / `전원 플러그`.
  선택값은 `AppSettings.menuBarIconStyle`(UserDefaults `menuBarIconStyle`)에 저장되고,
  `StatusBarController`가 `$menuBarIconStyle`을 구독해 즉시 다시 그립니다.
- 기존 **메뉴 막대 표시** 피커(전력 / 잔량 / 아이콘만 / 온도)와 독립적으로 조합할 수 있습니다.

검증: 80% 충전/유지, 15%, 0%, 100%를 오프스크린 렌더로 확인했습니다.
(화면 기록 권한이 없어 실제 메뉴바 스크린샷은 촬영하지 못했습니다.)

### 5.4 배터리 건강도 추이 (2026-11-03)

- `Sources/Akkim/BatteryHealthHistory.swift`: `~/Library/Application Support/Akkim/health-history.json`에
  (시각, 최대 용량, 설계 용량) 샘플을 저장합니다.
  - 최대 용량이 바뀌면 즉시, 그렇지 않으면 6시간 간격으로 추가
  - 180일 보관, JSON 원자적 쓰기
- `Sources/Akkim/BatteryHealthChart.swift`: Swift Charts 영역 그래프(민트)와
  80% 서비스 임계선(점선). 샘플이 3개 이하일 때는 점으로 표시합니다.
- `MenuBarPanel`: 큰 건강도 %, 상태 배지(정상/서비스 권장), 30일 추이 그래프,
  최대 용량·설계 용량·사이클·온도 2×2 그리드.
- macOS 26+에서는 `DesignCapacity`/`FullChargeCapacity`가 `BatteryData` 안에 있어
  `IORegistryReader`가 그쪽도 읽도록 보완했습니다 (6564 / 8694 mAh → 76%).
- 디자인·색상·레이아웃은 이 프로젝트에서 새로 작성한 것이며, AlDente 화면을 복제하지
  않았습니다. (제품명/아이콘/문구도 사용하지 않음)

### 5.5 패널 섹션 접기/숨기기 (2026-11-03)

- `AppSettings.PanelSection`: `power`, `health`, `history`, `limit`.
- **접기**: 각 섹션 제목줄이 버튼이 되어 chevron(⌄/›)으로 접고 펼칩니다.
  상태는 `panelCollapsedSections`에 저장되어 재실행 후에도 유지됩니다.
- **숨기기**: Settings > Panel sections 토글. `panelVisibleSections`에 저장됩니다.
- 숨긴 섹션은 패널에서 렌더링하지 않고, 접힌 섹션은 제목줄만 남깁니다.
- 상단 상태/게이지와 하단(보증·종료·설정)은 항상 표시합니다.
- 설정 창은 섹션이 늘어나도 잘리지 않도록 `ScrollView`로 감쌌습니다 (420×700).

### 5.6 문서용 스크린샷 (2026-11-03)

- `README.md` 상단에 `docs/images/panel.png`, `docs/images/settings.png` 추가.
- 화면 기록 권한 없이 촬영하려고 DEBUG 빌드에 `--screenshot` 모드를 넣었습니다.

  ```bash
  bash scripts/package-app.sh debug
  dist/Akkim.app/Contents/MacOS/Akkim --screenshot
  # -> /private/var/tmp/akkim-panel.png, akkim-settings.png
  ```

  팝오버와 설정 창을 스스로 스냅샷한 뒤 종료합니다.
- 건강도 추이 그래프는 캡처용으로만 메모리에서 샘플을 생성합니다
  (`seedPreviewData`, `#if DEBUG`). 디스크에 저장하지 않고 릴리스 빌드에는 포함되지 않습니다.
- 릴리스 빌드는 기존처럼 `bash scripts/package-app.sh`로 만듭니다.

### 5.7 에너지 사용량 (2026-11-03)

- `Sources/Akkim/EnergyUsageStore.swift`: 1초 전력 샘플을 시간으로 적분해 **일별 버킷**으로
  저장합니다 (`~/Library/Application Support/Akkim/energy-usage.json`).
  - 수면/중단으로 생긴 큰 시간 점프는 **최대 5초**로 제한해 과대 계산을 막습니다.
  - 30초마다 저장, 종료 시 `flush()`, 400일 보관.
- `Sources/Akkim/EnergyUsageChart.swift`: 최근 14일 AC 사용량 막대 차트.
- 패널에 **에너지** 섹션 추가: 오늘 / 7일 / 30일 AC 사용량(Wh·kWh),
  14일 차트, 오늘의 충전량·방전량.
- `PanelSection.energy` 추가. 기존 설치에서는 `panelSectionsVersion` 마이그레이션으로
  에너지 섹션이 자동으로 표시됩니다.
- **한계**: 앱이 실행 중인 동안만 집계합니다. 앱 종료·잠자기 구간은 제외됩니다.
- 스크린샷용 `seedPreviewData()`는 `isPreview` 플래그로 **디스크에 저장하지 않습니다**.

### 5.8 시간대별 보기 + CSV 내보내기 (2026-11-03)

- `DailyEnergy.hourlyWallWh`: 오늘의 시간대별(0–23) AC 사용량을 함께 저장합니다
  (기존 파일에는 없으므로 optional, 새 기록부터 채워짐).
- 패널 에너지 섹션에 **14일 / 오늘** 세그먼트와 **CSV 내보내기** 링크 추가.
  - 선택한 보기는 `AppSettings.energyChartMode`에 저장됩니다.
  - CSV는 `date,wall_wh,system_wh,charged_wh,discharged_wh` 형식으로 저장 패널을 통해 내보냅니다.
- 참고: Command Line Tools만 있는 환경에서는 SwiftUI `@State` 매크로 플러그인이 없어
  빌드가 실패할 수 있습니다. 이 프로젝트는 화면 상태도 `AppSettings`(@Published)로
  관리합니다.

### 5.9 설정 창 유령 수정 (2026-11-04)

- **원인**: SwiftUI `Settings { EmptyView() }` 씬이 별도의 빈 "아낌 Settings" 창을 만들었고,
  설정 창을 열었다 닫으면 이 빈 창이 유령처럼 남았습니다.
- **수정**: SwiftUI App/Scene을 제거하고 `Sources/Akkim/AppMain.swift`의 AppKit `@main`으로 전환.
  알림 권한 요청은 `AppDelegate.applicationDidFinishLaunching`으로 이동했습니다.
- **검증**: 설정 열기 → 닫기 → 다시 열기 후 `NSApp.windows`에 상태바 창과 설정 창만 존재.

### 5.10 앱 아이콘 (2026-11-04)

- `Resources/AppIcon.icns` 추가, `Info.plist`에 `CFBundleIconFile = AppIcon`.
- 디자인: 민트→틸 그라데이션 타일, 80% 채워진 배터리, 중앙 하트 컷아웃
  (아낌 = 배터리를 아끼다). 텍스트/타사 아트워크 없음.
- `docs/images/icon.png`(1024)는 README 상단에 사용.
- `scripts/package-app.sh`가 `.icns`를 번들 `Contents/Resources`로 복사합니다.

### 5.11 macOS 자체 충전 제한 감지 + 토글 동기화 (2026-11-04)

- macOS 26.4+에는 시스템 자체 **Charge Limit**이 있습니다. 시스템 제한이 앱 제한보다 낮으면
  (예: 시스템 80%, 앱 85%) 앱이 충전을 허용해도 OS가 충전을 시작하지 않습니다.
- 헬퍼가 `externalConnected && !isCharging && soc < limit` 상태가 30초 이상 지속되면
  `reason:"systemHold"`를 발행합니다. 패널은 이때 "macOS가 충전을 보류 중"과
  **시스템 설정 열기** 버튼을 표시합니다.
- 앱에서도 1초 샘플로 같은 상태를 감지합니다(30초 유예). 헬퍼를 재설치하지 않아도 안내가 뜹니다.
- 토글 상태 동기화: 헬퍼 상태 파일이 최대 10초 늦게 갱신되므로, 로컬 설정을 쓴 뒤 15초 동안은
  데몬 상태로 `enabled/limit`을 되돌리지 않습니다 (`lastConfigWriteAt`).
- 해결 방법(사용자): 시스템 설정 → 배터리 → 충전(ⓘ) → **Charge Limit**을 앱 제한과 같거나
  높게 설정하거나 100%로 변경.

---

## 6. 실기기 테스트 체크리스트

> 각 항목을 통과/실패로 기록하고, 실패 시 로그(`/var/log/akkim-helper.log`)와
> `helper-state.json`을 함께 보관하세요.

### 6.1 빌드/패키징

- [x] `swift build` 성공
- [x] `swift build -c release` 성공
- [x] `bash scripts/package-app.sh` 성공
- [x] `codesign --verify --deep --strict dist/Akkim.app` 성공
- [x] `dist/Akkim.app/Contents/Resources/`에 `LICENSE`, `THIRD-PARTY-NOTICES.md`, `akkim-helper`, `install-helper.sh` 존재

### 6.2 헬퍼 설치/상태

- [ ] 앱에서 제한을 처음 켤 때 관리자 인증 창이 뜨고 설치 완료
- [x] `sudo launchctl print system/com.akkim.helper`에서 `state = running`
- [x] `/Users/Shared/Akkim/helper-state.json` 생성
- [x] `ts`가 10초 내로 갱신됨
- [x] `ls -l /Users/Shared/Akkim` → 디렉터리 `775 root:admin`, `smc-limit.json` `664`
- [ ] 헬퍼 중지 후 패널에 "helper is not responding" 표시 (30초 후)

### 6.3 충전 제한/세일링

- [x] 제한 80% 설정 → 80%에서 실제 충전 홀드
- [ ] 패널 사유 `Holding at the limit · 80%`
- [ ] 75% 이하로 떨어지면 재충전(세일링)
- [ ] 세일링 끄면 80% 미만에서 바로 재충전
- [x] 제한 off → 충전 재개

### 6.4 만충전

- [ ] 80% 상태에서 `Charge to 100% once` 클릭
- [ ] 사유가 `Topping up to 100%`로 바뀜
- [ ] 100% 도달 후 `smc-limit.json`의 `topUp`이 `false`
- [ ] 알림 "Top-up complete"
- [ ] 이후 다시 80% 홀드
- [ ] 도중에 버튼을 다시 눌러 취소 가능

### 6.5 열 보호

- [ ] 설정에서 열 보호 45℃ 설정
- [ ] 배터리 온도가 45℃ 이상일 때 충전 홀드
- [ ] 사유 `Paused: battery too hot · xx.x°C`
- [ ] 온도가 내려가면 충전 재개
- [ ] 0(끔)에서는 동작하지 않음

### 6.6 방전

- [ ] CHIE 지원 기기: 방전 토글 → 어댑터 분리, 제한값까지 방전
- [ ] 제한 도달 시 재연결 후 홀드
- [ ] CHIE 미지원 기기: 토글 비활성 + 안내 문구
- [ ] 방전 중 만충전 요청 시 방전이 취소되고 충전 시작

### 6.7 메뉴바

- [ ] 좌클릭 → 팝오버
- [ ] 우클릭 → 80/85/90/95/100/끄기/설정/종료 메뉴
- [ ] 현재 단계에 체크 표시
- [ ] 표시 모드: 전력 / 잔량 / 아이콘만 / 온도 전환 즉시 반영
- [ ] 아이콘 스타일: 배터리 / 충전 배터리 / 플러그 전환 즉시 반영
- [ ] 섹션 제목 클릭 → 접기/펴기, 재실행 후에도 유지
- [ ] 설정 › 패널 섹션 토글로 섹션 표시/숨김
- [ ] 설정 변경 후 재실행해도 유지

### 6.8 차트/알림

- [ ] 전력 차트 정상
- [ ] SoC 차트 표시, 제한선/하한선 오버레이
- [ ] 에너지 섹션: 오늘/7일/30일 합계, 14일 막대 차트
- [ ] 앱 재실행 후 에너지 누적이 유지됨
- [ ] 제한 도달 알림 1회
- [ ] 과열 알림 1회
- [ ] 알림 끄면 울리지 않음
- [ ] 앱 재실행 직후 과거 사유를 재알림하지 않음

### 6.9 로그인/종료

- [ ] 로그인 시 자동 실행 (`/Applications`에 둔 경우)
- [ ] 앱 종료 후에도 제한이 유지되는지 확인 (헬퍼가 계속 적용)
- [ ] 앱 재실행 시 제한이 켜진 상태로 복원되는지 확인

### 6.10 1차 실기기 확인 결과 (2026-11-03)

대상: macOS 27.0.1, Apple Silicon (arm64). 헬퍼는 `/private/var/tmp`로 복사한 뒤 수동 설치.

| 항목 | 결과 |
|---|---|
| 헬퍼 설치/기동 | 성공 (`launchctl print` → `state = running`) |
| `helper-state.json` 발행 | 성공, 10초 주기로 `ts` 갱신 |
| 제한 on(80%) | `reason:"limit"`, `holding:true` |
| 제한 off | `reason:"off"`, 어댑터 재연결 |
| CHTE | **이 기기에서 사용 불가** → `actuator:"CHIE"` 폴백 |
| CHIE(방전) | 사용 가능 (`chieAvailable:true`) |
| 배터리 온도 | `tempC:31.09` (`AppleSmartBatteryPack.BatteryData.Temperature`) |
| 열 보호 | 임계 30℃ 설정 시 `reason:"heat"`, `holding:true` 확인 |

> **중요**: 이 기기에서는 `CHTE`가 없어 `CHIE` 폴백으로 제한을 구현합니다. 즉 "충전 홀드"가
> 아니라 **어댑터를 분리**하는 방식이라, 제한값에 도달하면 배터리로 동작하다가
> `limit - deadband` 아래로 내려가면 다시 충전합니다. 이 경우 UI는
> "Holding by cutting AC power"(한국어: "AC 전원을 끊어 제한 유지 중")로 표시됩니다.
>
> `AppleSmartBattery`에는 `Temperature` 키가 없지만, 자식 노드
> `AppleSmartBatteryPack`의 `BatteryData.Temperature`(centi-°C)에서 읽도록 보완했습니다.
> 열 보호가 이 값으로 동작하는 것은 2026-11-03에 확인했습니다.

---

## 7. 문제 해결

### 7.1 "helper is not responding"

```bash
sudo launchctl print system/com.akkim.helper
tail -n 100 /var/log/akkim-helper.log
ls -l /Users/Shared/Akkim
```

- 구버전 헬퍼면 `helper-state.json`을 쓰지 않습니다. 재설치:

```bash
sudo bash scripts/install-helper.sh install "$(pwd)/dist/Akkim.app/Contents/Resources/akkim-helper"
```

### 7.2 설정 파일 권한 문제

```bash
ls -ld /Users/Shared/Akkim
ls -l /Users/Shared/Akkim/*.json
```

정상: 디렉터리 `drwxrwxr-x root admin`, JSON `-rw-rw-r-- root admin`.
데몬이 시작할 때 world-writable이면 자동 교정합니다.

### 7.3 서명/Gatekeeper

```bash
codesign --verify --deep --strict dist/Akkim.app
xattr -dr com.apple.quarantine dist/Akkim.app
```

ad-hoc 서명이므로 배포용이 아닙니다. 배포 시 Developer ID + notarization 필요.

### 7.4 Shortcuts 경로 (macOS 26.4+)

- Shortcuts 앱에서 이름이 정확히 `SetBatteryChargeLimit`인 단축어 생성
- 앱이 onboarding 알림으로 안내
- 헬퍼 없이 Shortcuts만 쓰는 경우 top-up/열 보호는 동작하지 않음

### 7.5 로그

```bash
tail -f /var/log/akkim-helper.log
log stream --predicate 'process == "Akkim"' --level debug
```

### 7.6 클라우드 동기화 폴더에서 실행하는 경우

Google Drive/iCloud 같은 보호된 경로에 있는 앱 번들에서 헬퍼를 설치하면, root로 실행되는
설치 스크립트가 해당 경로를 읽지 못해 `Operation not permitted (126)`로 실패할 수 있습니다.
이 환경에서는 다음 중 하나를 사용하세요.

- `cp -R dist/Akkim.app /Applications/` 후 `/Applications/Akkim.app` 실행 (권장)
- 또는 스크립트와 헬퍼를 `/private/var/tmp`로 복사한 뒤 그 경로로 수동 설치

```bash
TMP=/private/var/tmp/akkim-install
mkdir -p "$TMP"
cp scripts/install-helper.sh "$TMP/"
cp dist/Akkim.app/Contents/Resources/akkim-helper "$TMP/"
osascript -e 'do shell script "bash " & quoted form of "/private/var/tmp/akkim-install/install-helper.sh" & " install " & quoted form of "/private/var/tmp/akkim-install/akkim-helper" with administrator privileges'
```

Google Drive 동기화가 `.build` 안의 dSYM 번들을 0바이트 파일로 바꾸면 빌드가
`cannot create bundle: Not a directory`로 실패할 수 있습니다. 이때는 빌드 경로를
드라이브 밖으로 지정하세요.

```bash
AKKIM_BUILD_PATH=/private/var/tmp/akkim-build bash scripts/package-app.sh
```

---

## 8. 비상 복구 (충전이 멈춘 경우)

가장 확실한 방법은 헬퍼 제거입니다. 제거 시 `atexit`/signal 경로로 충전이 복구됩니다.

```bash
sudo bash scripts/install-helper.sh uninstall
```

또는 설정 파일만 수정:

```bash
sudo tee /Users/Shared/Akkim/smc-limit.json >/dev/null <<'EOF'
{"schemaVersion":1,"enabled":false,"limit":80,"deadband":5,"calibrationDays":7,"sailingMode":true,"discharge":false,"heatProtectionC":0,"topUp":false}
EOF
```

그래도 안 되면 SMC 재설정을 위해 Mac을 재부팅하세요.

---

## 9. 남은 작업

### 9.1 즉시

- [x] Mac에서 `swift build` / `swift build -c release` 통과 (2026-11-03)
- [x] `bash scripts/package-app.sh` + `codesign --verify` 통과
- [ ] 실기기 체크리스트 6장 수행
- [ ] GitHub push → CI 녹색 확인

### 9.2 저장소/배포

- [x] 릴리스 워크플로 추가 (`.github/workflows/release.yml`, 태그 `v*` → zip + Release)
- [x] 앱 버전 `CFBundleShortVersionString 1.3.1` / `CFBundleVersion 8`
- [x] `git init` 및 `https://github.com/karanglass24-lang/akkim` push
- [ ] 폴더명 `battery-limit` → `akkim` 정리 (선택)
- [x] 태그 푸시(`v1.0.0`, `v1.0.1`) 후 Release 자산(`Akkim.zip`, `.sha256`) 확인
- [x] 고정 다운로드 URL 확인: `/releases/latest/download/Akkim.zip`
- [ ] 경고 없는 배포가 필요하면 Developer ID 서명 + notarization

### 9.3 법무/브랜드

- [ ] KIPRIS class 9 상표 조사
- [ ] USPTO 상표 조사
- [ ] "Al Dente" 무관 고지 유지 (README/앱)

### 9.4 제품 결정 필요

- [ ] 앱 종료 시 `enabled:false`로 제한을 끄는 현재 동작 유지 여부
- [ ] 열 보호를 제한이 꺼져 있을 때도 적용할지 (현재는 `enabled`일 때만)
- [ ] 방전 중 만충전 요청 시 방전 자동 취소 정책 확정
- [ ] top-up 완료 후 원래 제한 단계로 복귀하는지 확인

---

## 10. 개발 규칙

- **UI 문자열**: 반드시 `Sources/Akkim/Localization.swift`의 `LKey`에 추가.
  `LKey.text`는 exhaustive switch이므로 번역 누락 시 컴파일 실패.
  현재 120개.
- **리소스 없음**: `.lproj`를 쓰지 않으므로 `Package.swift`에 `resources:`를 추가하지 말 것.
- **동시성**: `SMCChargeLimiter`, `ChargeLimitController`, `AppSettings`,
  `StatusBarController`, `SampleStream`은 `@MainActor`.
- **파일 쓰기**: 설정/상태/보정 JSON은 반드시 `.atomic` 옵션.
- **인코딩**: UTF-8, BOM 없음, LF. (기존 파일과 동일하게 유지)
- **의존성**: 서드파티 없음. Apple 프레임워크만 사용.
- **네트워크/텔레메트리**: 없음. 추가하지 말 것.
- **서명**: 개인 사용은 ad-hoc. 번들 내 헬퍼를 **먼저** 서명한 뒤 앱 번들 서명.

---

## 11. 알려진 제약 / 미검증

1. **컴파일 검증 완료 (2026-11-03)** — macOS 27.0.1 / Swift 6.4.2에서 debug·release 빌드,
   번들 패키징, ad-hoc 서명 검증까지 통과했습니다. 수정 내역은 5.1 참고.
2. **Swift Charts** — macOS 27 SDK에서는 정상 컴파일됩니다. CI(macos-14, macOS 14 SDK)에서도
   통과하는지는 push 후 확인이 필요합니다.
3. **`Process.terminationHandler`** — Swift 5 모드(tools 5.9)에서는 경고 없이 컴파일됩니다.
   Swift 6 언어 모드로 올릴 때 `done.signal()` 캡처를 다시 점검해야 합니다.
4. **실제 SMC 동작** — 이 테스트 기기(macOS 27.0.1)에는 `CHTE`가 없어 `CHIE` 폴백
   (어댑터 분리)으로 동작합니다. 기기별 차이가 크므로 다른 Mac에서도 6.10과 같은 확인이
   필요합니다. 방전 모드와 열 보호는 실기기 확인이 필수.
5. **구버전 헬퍼** — 새 앱 + 구 헬퍼 조합에서는 상태 파일이 없어 경고가 뜹니다.
   재설치 필요.
6. **앱 종료 시 제한 유지** — `applicationWillTerminate`에서 `disable()`을 호출하지 않습니다.
   앱을 끄면 헬퍼가 마지막 설정을 계속 적용합니다. 사용자가 패널에서 직접 꺼야 복구됩니다.
7. **상태 파일 최신성** — 데몬은 10초 주기라 UI 반영에 최대 10초 지연이 있습니다.
8. **top-up 경합** — 앱과 데몬이 같은 설정 파일을 원자적으로 쓰므로, 아주 드물게
   마지막 writer가 이길 수 있습니다. 5초 동기화로 수렴합니다.

---

## 12. 참고

- 원본/파생: ChargeWatching (MIT, Copyright (c) 2026 TY-teo)
- SMC 참고: batt, SMCKit
- CI: `.github/workflows/build.yml`
- 라이선스 고지: `LICENSE`, `THIRD-PARTY-NOTICES.md`
