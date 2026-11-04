# 아낌(Akkim) 사용 설명서

macOS 메뉴바에서 배터리 충전을 제한하고, 전력·건강도·에너지 사용량을 보여주는 앱입니다.
이 문서는 설치부터 일상 사용, 문제 해결까지 다룹니다.

- 저장소: <https://github.com/karanglass24-lang/akkim>
- 다운로드: <https://github.com/karanglass24-lang/akkim/releases/latest>

---

## 1. 설치

1. 최신 릴리스에서 `Akkim.zip`을 내려받습니다.
2. 압축을 풀고 `Akkim.app`을 `/Applications`로 옮깁니다.
3. 앱을 엽니다. (메뉴바에 아이콘이 생기고 Dock에는 표시되지 않습니다.)

릴리스 빌드는 ad-hoc 서명이라 첫 실행 시 경고가 뜰 수 있습니다.

```bash
# 경고가 계속될 때
xattr -dr com.apple.quarantine /Applications/Akkim.app
```

### 헬퍼(관리자 데몬)

충전 제한은 root 권한이 필요해 `com.akkim.helper` LaunchDaemon을 사용합니다.
앱에서 처음 제한을 켜면 관리자 인증 창이 뜨고 자동 설치됩니다.
수동 설치:

```bash
sudo bash /Applications/Akkim.app/Contents/Resources/install-helper.sh install \
  /Applications/Akkim.app/Contents/Resources/akkim-helper
```

확인:

```bash
sudo launchctl print system/com.akkim.helper | grep -E "state =|pid ="
tail -n 20 /var/log/akkim-helper.log
```

---

## 2. 메뉴바와 패널

패널 상단에는 **충전 / 모니터** 두 탭이 있습니다.

- **충전**: 충전 제한 사용, 80/85/90/95/100%, 만충전, 세일링, 방전
- **모니터**: 전력, 에너지 사용량, 배터리 건강도, 최근 전력/잔량 차트

### 메뉴바

- **왼쪽 클릭**: 패널 열기
- **오른쪽 클릭**: 80/85/90/95/100%, 끄기, 설정, 종료
- 표시 값과 아이콘은 **설정 › 일반**에서 선택합니다.
  - 표시 값: 전력(W) / 잔량(%) / 아이콘만 / 온도
  - 아이콘: 배터리(잔량) / 충전 배터리 / 전원 플러그
- 패널의 각 섹션은 **제목을 클릭해 접고 펼 수** 있으며, 설정에서 표시 여부를 끌 수 있습니다.

---

## 3. 충전 제한

1. 패널에서 **충전 제한 사용**을 켭니다.
2. 제한 값을 선택합니다 (80/85/90/95/100%).
3. 현재 상태와 사유가 패널 상단에 표시됩니다.

### 세일링 모드 (기본 켜짐)

- 제한값에서 충전을 멈추고, `제한 - deadband(5%)` 아래로 내려가면 다시 충전합니다.
- 예: 제한 80% → 75%까지 떨어지면 재충전.
- 끄면(하드스톱) 제한 아래로 내려갈 때마다 바로 재충전합니다.

### 제한을 올렸을 때

제한을 80% → 85%로 올리면, 현재 잔량이 새 제한보다 낮을 경우 **즉시 충전을 재개**합니다.
(1.4.1부터 적용, 헬퍼 재설치 필요)

### 이 Mac의 제어 방식

- `CHTE` 키가 있으면 배터리 충전만 멈춥니다(어댑터 유지).
- `CHTE`가 없으면 `CHIE` 폴백으로 **어댑터를 분리**합니다. 이 경우 패널에
  "AC 전원을 끊어 제한 유지 중"으로 표시됩니다.

---

## 4. macOS 기본 충전 제한과 함께 쓰기 (macOS 26.4+)

macOS 26.4부터는 시스템 자체 **Charge Limit**(80–100%)이 있습니다. 이 값은 `powerd`가
강제하며, 앱이 직접 바꿀 수 있는 공개 API/CLI는 없습니다. 대신 **Shortcuts**로 연동할 수 있습니다.

### 왜 필요한가

시스템 제한이 앱 제한보다 낮으면(예: 시스템 80%, 앱 85%) 앱이 충전을 허용해도
OS가 충전을 시작하지 않습니다. 이때 패널은 **"macOS가 충전을 보류 중"** 경고와
**시스템 설정 열기** 버튼을 표시합니다.

### 값이 고정된 단축어 5개 만들기

“Set Charge Limit” 동작은 값이 **고정 퍼센트**만 지원합니다. 그래서 80/85/90/95/100용
단축어를 5개 만듭니다.

1. Shortcuts에서 새 단축어 → 동작 **“Set Charge Limit”** 추가 → 값 **80%**
2. 이름을 **`SetBatteryChargeLimit80`** 로 저장
3. 같은 방법으로 85/90/95/100을 만들어 이름을
   `SetBatteryChargeLimit85`, `…90`, `…95`, `…100` 으로 저장
4. 앱 설정 › 시스템 충전 제한 › **다시 확인** → “연동됨”
5. 앱에서 제한을 바꾸면 해당 단축어가 실행되어 시스템 제한이 바뀝니다

> 예전에 만든 `SetBatteryChargeLimit`(값 입력형) 단축어가 있으면, 5개 단축어가
> 모두 있을 때 앱은 **고정 단축어를 우선** 사용합니다.

### 연동 확인

```bash
shortcuts list | grep SetBatteryChargeLimit
shortcuts run SetBatteryChargeLimit85     # 85%로 고정된 단축어
```

실행 후 `ioreg`에서 충전이 재개되는지 확인할 수 있습니다.

```bash
ioreg -rn AppleSmartBattery | grep -E '"(IsCharging|CurrentCapacity)"'
```

---

## 5. 방전 · 만충전 · 열 보호

- **제한까지 방전**: 어댑터를 분리해 제한값까지 방전합니다 (`CHIE` 지원 기기만).
- **한 번 만 100% 충전**: 여행 전 등에 사용합니다. 100% 도달 시 자동 해제됩니다.
- **열 보호**: 설정한 배터리 온도 이상이면 충전을 일시정지합니다 (30–60℃, 0=끔).
  온도를 읽을 수 없는 기기에서는 패널에 경고가 표시됩니다.
- **자동 보정**: 설정한 주기(0/7/14/30/60일)마다 100%까지 충전해 추정 정확도를 유지합니다.

---

## 6. 에너지 사용량

패널 **에너지** 섹션:

- 오늘 / 7일 / 최근 30일 **AC 사용량**(Wh·kWh)
- **14일** 막대 차트와 **오늘(시간대별)** 보기
- 오늘의 충전량 / 방전량
- **CSV 내보내기**: `date,wall_wh,system_wh,charged_wh,discharged_wh`

값은 앱이 실행 중일 때 1초 샘플을 적분해 계산합니다. 잠자기·종료 구간은 제외되며,
수면 후 큰 시간 점프는 최대 5초까지만 반영합니다.

---

## 7. 배터리 건강도

- 건강도 %, 상태 배지(정상/서비스 권장, 80% 기준)
- 최대 용량 / 설계 용량 / 사이클 / 온도
- 최근 30일 건강도 추이 (하루 수회 샘플 저장)

데이터 위치:

```
~/Library/Application Support/Akkim/health-history.json
~/Library/Application Support/Akkim/energy-usage.json
```

---

## 8. 설정

설정 창은 **일반 / 충전 제한 / 패널 섹션 / 정보** 4개 탭으로 나뉩니다.

| 항목 | 설명 |
|---|---|
| 알림 | 충전 상태/제한 도달/과열/만충전 완료 알림 |
| 로그인 시 자동 실행 | `SMAppService` 등록 (앱이 `/Applications`에 있어야 함) |
| 메뉴바 아이콘 표시 | 아이콘 숨기기 |
| 메뉴바 표시 값 | 전력 / 잔량 / 아이콘만 / 온도 |
| 메뉴바 아이콘 | 배터리 / 충전 배터리 / 플러그 |
| 시스템 충전 제한 | macOS 기본 제한 연동 상태 |
| 패널 섹션 | 전력·에너지·건강도·기록·충전 제한 표시/숨김 |
| 보정 | 완충 보정 주기 |
| 충전 제한 동작 | 세일링 모드 |
| 열 보호 | 일시정지 온도 |

---

## 9. 문제 해결

### "helper is not responding"

```bash
sudo launchctl print system/com.akkim.helper
tail -n 50 /var/log/akkim-helper.log
ls -l /Users/Shared/Akkim
```

헬퍼를 재설치합니다.

```bash
sudo bash /Applications/Akkim.app/Contents/Resources/install-helper.sh install \
  /Applications/Akkim.app/Contents/Resources/akkim-helper
```

### 제한을 올려도 충전이 시작되지 않음

1. 시스템 제한이 더 낮은지 확인: **시스템 설정 → 배터리 → 충전(ⓘ) → Charge Limit**
2. 앱에 "macOS가 충전을 보류 중" 경고가 뜨면 시스템 제한을 앱 제한 이상으로 올립니다.
3. 헬퍼가 1.4.1 이상인지 확인하고 재설치합니다.

### Shortcuts 연동이 안 됨 / "Error: 비어있는 단축어"

단축어에 동작이 없거나 이름이 다릅니다.

```bash
shortcuts list | grep -i battery
```

- 이름이 정확히 `SetBatteryChargeLimit`인지 확인
- 단축어를 열어 **Set Battery Charge Limit** 동작이 들어 있는지 확인
- 동작의 값이 **Shortcut Input**으로 설정되어 있는지 확인

### 설정 창을 닫았는데 빈 창이 남음

1.2.1에서 수정되었습니다. 최신 버전으로 업데이트하세요.

### 앱이 손상되었다고 나옴

```bash
xattr -dr com.apple.quarantine /Applications/Akkim.app
```

### Google Drive 폴더에서 빌드가 실패함

dSYM 번들이 동기화로 손상될 수 있습니다. 빌드 경로를 드라이브 밖으로 지정하세요.

```bash
AKKIM_BUILD_PATH=/private/var/tmp/akkim-build bash scripts/package-app.sh
```

---

## 10. 안전 및 라이선스

- SMC 키(`CHTE`/`CHIE`)는 문서화되지 않은 영역입니다. 기기별 동작 차이가 있을 수 있습니다.
- 헬퍼는 종료·크래시·시그널 시 충전을 복구합니다.
- MIT 라이선스. ChargeWatching(MIT)에서 파생되었으며, 자세한 고지는
  `LICENSE`, `THIRD-PARTY-NOTICES.md`를 참고하세요.
- "Al Dente"는 AppHouseKitchen의 상표이며, 이 앱과 무관합니다.
