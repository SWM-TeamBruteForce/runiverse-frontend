# UI 전면 교체 — 매칭·러닝 흐름 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 매칭 등록부터 러닝을 끝낼 때까지의 화면 셋을 새 디자인으로 옮기고, 파일럿이 만든 `widgets/v2`가 **실제로 재사용되는지** 확인한다.

**Architecture:** 화면 하나가 PR 하나다. 파일럿(`match_room_page`)이 만든 `AppButtonV2`·`AppIcon`·`theme/v2`를 그대로 쓰고, 모자란 부품만 그때 만든다. 쉬운 것부터 간다 — 재사용이 되는지 먼저 보고, 부품을 새로 만들어야 하는 화면을 뒤에 둔다.

**Tech Stack:** Flutter (fvm) · flutter_test · flutter_svg · Figma MCP

**Spec:** `docs/specs/2026-09-25-ui-redesign-workspace-design.md` (8·9절에 대응표와 파일럿 실측)

**Figma:** 파일 `MpJxkA7fPj6MJs5uL07CVb` (`runiverse_final2`), 화면은 전부 `149:791` 아래.

## Global Constraints

- 모든 flutter/dart 명령은 `.\.fvm\flutter_sdk\bin\flutter.bat` / `dart.bat` 으로 직접 부른다 — fvm이 PATH에 없다.
- 모든 커밋 시점에 `analyze` 경고 **0개**, `test` **전체 통과**(현재 941개). 빨간 것을 다음 PR로 넘기지 않는다.
- 커밋 메시지 `<이모지> <Type>: <설명>`. **AI를 공동 작성자로 넣지 않는다.**
- **PR 하나 = 화면 하나.** base는 `dev`. 앞 PR이 머지된 뒤 `upstream/dev`에서 새로 딴다 — 스택 PR을 만들지 않는다.
- **한 화면은 한 세대의 토큰만 쓴다.** `test/theme_generation_test.dart`가 강제한다.
- 옮긴 화면은 `core/theme/v2/`와 `core/widgets/v2/`만 import한다. Lucide를 쓰지 않는다 — `AppIcon`을 쓴다.
- 러닝 수치에 `FontFeature.tabularFigures()`.
- 화면마다 **다크·라이트 두 테마**를 에뮬레이터에서 본다.
- `Color(0x...)` 하드코딩은 `core/theme/` 안에서만. 시안의 값이 토큰에 없으면 **토큰에 넣고** 쓴다.
- **GPS 좌표·경로를 파티원에게 노출하지 않는다.** 파티원 비교에 **순위를 표시하지 않는다.**
- 우리에게 없는 값을 **지어내지 않는다.** 자리를 비우거나 항목을 빼고 백엔드 요청으로 적는다. 지금 거기 해당하는 것은 **뱃지 하나**다 — 케이던스·칼로리는 이미 있다(스펙 8절).
- **없다고 적기 전에 화면을 열어 본다.** 시안과 코드만 대조하다 두 개를 틀렸다.

### 파일럿에서 배운 것 — 매 화면에 적용한다

1. **그 화면의 시안을 먼저 읽는다.** 토큰만 보고 규칙을 세우면 틀린다. 파일럿에서 제목과 글자 위계를 두 번 고쳤다.
2. **깨진 테스트를 그 PR 안에서 고친다.** 구조 결합은 `find.text`로, 잠김은 눌러 보는 것으로 옮긴다.
3. **고친 뒤 화면을 일부러 부순다.** 테스트가 빨개지지 않으면 느슨해진 것이다.
4. **화면 클래스 단정(`find.byType(...Page)`)은 건드리지 않는다.** 파일럿에서 그대로 살았다.

---

### Task 1: 출발 대기실을 옮긴다

시안 `158:3453` `출발 대기실 페이지` → `lib/features/matching/presentation/match_countdown_page.dart`

**먼저 하는 이유는 재사용 검증이다.** 시안이 대기방(`158:3415`)과 거의 같다 — 같은 카운트다운, 같은 `시작 시간`·`목표 거리` 카드 두 장, 같은 참여자 표시. **새로 만들 부품이 없어야 정상이고, 필요해지면 파일럿이 만든 부품이 덜 일반적이었다는 뜻이다.**

⚠️ **이 화면에는 테스트가 하나도 없다.** 그물 없이 옮긴다. 에뮬레이터 확인이 유일한 검증이라 Step 6을 건너뛰지 않는다.

**Files:**
- Modify: `lib/features/matching/presentation/match_countdown_page.dart` (482줄)

**Interfaces:**
- Consumes: `AppColorsV2` `AppTypographyV2` `AppButtonV2` `AppIcon`, 그리고 v2 경로의 `AppSpacing`·`AppRadius`·`AppSizes` (재수출이라 이름은 그대로다)
- Produces: 없음이 목표. 새 부품이 생기면 그 사실 자체가 Task 4의 기록거리다

- [ ] **Step 1: 지금 상태를 확인한다**

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat test
Select-String -Path lib/features/matching/presentation/match_countdown_page.dart -Pattern "core/theme|core/widgets|LucideIcons"
```

Expected: 941개 통과. import 목록에 `core/theme/extensions`·`core/theme/tokens`가 보인다.

- [ ] **Step 2: 시안을 읽는다**

`figma-design-to-code` 스킬을 먼저 불러온 뒤:

```
get_design_context(fileKey: "MpJxkA7fPj6MJs5uL07CVb", nodeId: "158:3453",
                   clientFrameworks: "flutter", clientLanguages: "dart",
                   skillNames: "figma-design-to-code")
```

시안이 보여주는 것: `출발 대기실` · `시작까지 00 : 04 : 10` · `시작 시간 / 19:00` ·
`목표 거리 / 5 km` · `참여자 김지원`.

⚠️ **대기방과 무엇이 다른지에 집중해 읽는다.** 같은 것을 다시 만들지 않기 위해서다.

- [ ] **Step 3: 토큰 import를 v2로 통째로 바꾼다**

`core/theme/extensions/`·`core/theme/tokens/`를 가리키는 import를 **전부** `core/theme/v2/`로 바꾼다. `context.appColors` → `context.appColorsV2`, `AppTypography.x` → `AppTypographyV2.xx`.

한 줄이라도 남으면 `test/theme_generation_test.dart`가 막는다.

- [ ] **Step 4: 대기방과 같은 부품을 그대로 쓴다**

카운트다운·카드 두 장·참여자 표시는 `match_room_page.dart`가 이미 만든 모양이다.

⚠️ **다른 feature의 위젯을 import하지 않는다**(CLAUDE.md). 두 화면이 같은 부품을 쓴다면 `core/widgets/v2/`로 올린다. 대기방과 이 화면은 둘 다 `features/matching`이지만, `_FactCard`·`_PlayerChip`은 `match_room_page.dart` 안의 private 클래스다.

**판단:** 두 화면이 실제로 같은 모양을 쓰면 `core/widgets/v2/fact_card.dart`·`party_chip.dart`로 올린다. 미세하게 다르면 각자 둔다 — **쓰지도 않을 공용화가 더 비싸다.**

- [ ] **Step 5: 검증**

```powershell
.\.fvm\flutter_sdk\bin\dart.bat format lib test
.\.fvm\flutter_sdk\bin\flutter.bat analyze
.\.fvm\flutter_sdk\bin\flutter.bat test
```

Expected: analyze `No issues found!`, 941개 통과. **이 화면에는 테스트가 없으므로 숫자가 그대로다** — 그것이 이 작업의 위험이다.

- [ ] **Step 6: ⚠️ 에뮬레이터에서 본다 — 이 화면의 유일한 검증**

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat build apk --debug --dart-define-from-file=config/dev.json
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
```

⚠️ 이 화면은 **매칭이 확정되고 출발 30초 전**에 열린다. 바로 가기 어렵다. 실매칭으로 확인하거나, 어려우면 그 사실을 PR에 적는다 — **확인했다고 적지 않는다.**

볼 것: 카운트다운이 흔들리지 않는가 · 카드 두 장 · 참여자 · 다크·라이트 두 테마.

- [ ] **Step 7: 커밋하고 PR**

```bash
git checkout -b style/match-countdown-redesign upstream/dev
git add lib test
git commit -F - <<'EOF'
🎨 Style: 출발 대기실을 새 디자인으로 옮긴다

시안 158:3453. 대기방과 같은 모양이라 파일럿이 만든 부품이 실제로
재사용되는지 보는 것이 목적이다.

이 화면에는 테스트가 없다. 에뮬레이터 확인이 유일한 검증이다.
EOF
git push -u origin style/match-countdown-redesign
gh pr create --repo SWM-TeamBruteForce/runiverse-frontend --base dev \
  --head jihwanjo-98:style/match-countdown-redesign \
  --title "🎨 Style: 출발 대기실을 새 디자인으로 옮긴다"
```

PR 본문의 **💬 리뷰 포인트**에 적을 것:

- 새로 만든 부품이 있으면 **왜 재사용이 안 됐는지**
- 테스트가 없는 화면이라는 사실과, 에뮬레이터로 어디까지 봤는지

- [ ] **Step 8: base 확인 후 머지**

```bash
gh pr view --repo SWM-TeamBruteForce/runiverse-frontend --json baseRefName -q .baseRefName
```

Expected: `dev`.

---

### Task 2: 러닝 종료 요약을 옮긴다

시안 `158:3764` `러닝 종료 요약 페이지` → `lib/features/session/presentation/run_summary_page.dart`

시안이 단순하다 — `총거리 5.02 /km` · `소요 시간 27:28` · `평균 페이스 5'38" km` · `러닝종료` 버튼. **수치 카드가 셋**이라 Task 1이 올린 부품이 다시 쓰이는지 한 번 더 확인된다.

⚠️ **이 화면도 테스트가 없다.**

**Files:**
- Modify: `lib/features/session/presentation/run_summary_page.dart` (296줄)

**Interfaces:**
- Consumes: Task 1이 확정한 부품들
- Produces: 없음이 목표

- [ ] **Step 1: 앞 PR이 머지된 뒤 새로 딴다**

```bash
git fetch upstream
git checkout -b style/run-summary-redesign upstream/dev
```

⚠️ **`dev`에서 딴다.** 앞 브랜치에서 쌓으면 스택 PR이 되고, 앞 PR이 머지될 때 뒤 PR의 diff가 꼬인다(`docs/CONTRIBUTING.md`).

- [ ] **Step 2: 시안을 읽는다**

```
get_design_context(fileKey: "MpJxkA7fPj6MJs5uL07CVb", nodeId: "158:3764", …)
```

⚠️ **`종료 후 대시보드`(`158:3602`)와 다른 화면이다.** 대시보드는 뱃지·파티원 기록까지 담은 확장판이고 우리에게 그 데이터가 없다. **이번에는 요약만 옮긴다.**

- [ ] **Step 3: 아이콘을 바꾼다**

이 화면은 `LucideIcons.x` 하나를 쓴다. → `AppIcons.close`.

- [ ] **Step 4: 토큰 import를 v2로 바꾸고 옮긴다**

Task 1 Step 3과 같다.

- [ ] **Step 5: 검증**

```powershell
.\.fvm\flutter_sdk\bin\dart.bat format lib test
.\.fvm\flutter_sdk\bin\flutter.bat analyze
.\.fvm\flutter_sdk\bin\flutter.bat test
```

Expected: analyze `No issues found!`, 941개 통과.

- [ ] **Step 6: 에뮬레이터에서 본다**

이 화면은 **러닝을 끝내면** 나온다. 솔로 러닝으로 짧게 뛰고 끝내면 닿는다.

- [ ] **Step 7: 커밋하고 PR, base 확인 후 머지**

Task 1 Step 7·8과 같은 절차.

---

### Task 3: 매칭 등록을 옮긴다

시안 `158:3181` `매칭등록 페이지` → `lib/features/matching/presentation/match_register_page.dart`

**셋 중 가장 무겁다.** 테스트가 12개(구조 결합 10건) 걸려 있고, `PresetChip`을 쓰는 유일한 화면이며, **시안에 지금 없는 것이 셋** 들어온다.

**Files:**
- Modify: `lib/features/matching/presentation/match_register_page.dart` (386줄)
- Modify: `test/match_register_test.dart` (테스트 12개)
- Create: `lib/core/widgets/v2/preset_chip.dart` (필요하면)

**Interfaces:**
- Consumes: 앞 두 작업이 확정한 부품들
- Produces: `PresetChipV2` (만들게 되면)

- [ ] **Step 1: 앞 PR 머지 후 `dev`에서 딴다**

```bash
git fetch upstream
git checkout -b style/match-register-redesign upstream/dev
.\.fvm\flutter_sdk\bin\flutter.bat test test/match_register_test.dart
```

Expected: 12개 통과. **이 숫자를 적어 둔다.**

- [ ] **Step 2: 시안을 읽는다**

```
get_design_context(fileKey: "MpJxkA7fPj6MJs5uL07CVb", nodeId: "158:3181", …)
```

시안이 보여주는 것: `매칭등록` · `매칭 러닝 시간 17:00` · `현재 18:00에 3명의 러너가 대기중이에요` · `목표거리 3 km / 5 km` · `도움말` · `취소정책` · **`친구랑 같이 뛰기 / 친구를 초대해 함께 매칭에 참여해보세요`**

- [ ] **Step 3: ⚠️ 시안에만 있는 것 셋을 판정한다**

**멈추고 판단한 뒤 진행한다.** 셋 다 지금 우리에게 없다.

| 시안 | 판정 |
|---|---|
| `친구랑 같이 뛰기` 진입점 | ⚠️ **친구초대 화면이 아직 없다.** 사용자는 "화면만 껍데기로"라고 정했지만 그 화면은 이 계획 밖이다. 누르면 아무 데도 안 가는 버튼을 두지 않는다 — **이번에는 넣지 않고** PR에 사유를 적는다 |
| `도움말` | 지금 화면에 있는지 확인한다. 없으면 넣지 않는다 |
| `취소정책` | 지금 화면에 있는지 확인한다. 없으면 넣지 않는다 |

⚠️ **"친구"라는 말은 CLAUDE.md가 아직 금지하고 있다.** 수정안은 PR #85에 올렸고 승인 전이다. 그 승인 없이 이 문구를 넣지 않는다.

- [ ] **Step 4: 아이콘 넷을 판정한다**

이 화면은 Lucide를 넷 쓴다. **둘은 디자인 아이콘 33개에 없다.**

| 지금 | 디자인 아이콘 | 조치 |
|---|---|---|
| `chevronRight` | `right` | 바꾼다 |
| `info` | `guide` | 바꾼다 (대기방에서 이미 그렇게 했다) |
| `clock` | **없음** | 시안에 그 자리가 있는지 먼저 본다. 없으면 자리째 사라진 것이다 |
| `gauge` | **없음** | 같다 |

⚠️ **없는 아이콘을 Lucide로 남겨두지 않는다.** 한 화면에 두 아이콘 체계가 섞이면 선 굵기와 모서리가 달라 눈에 띈다. 시안에도 자리가 있는데 아이콘만 없으면 **거기서 멈추고 디자이너에게 요청한다.**

- [ ] **Step 5: 토큰 import를 v2로 바꾸고 옮긴다**

`PresetChip`이 v1 토큰을 읽으면 `core/widgets/v2/preset_chip.dart`를 만든다. 시안의 거리 칩(`3 km` / `5 km`) 모양과 대조해서 정한다 — **같으면 만들지 않는다.**

- [ ] **Step 6: 깨진 테스트를 센다**

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat test test/match_register_test.dart
```

⚠️ **여기서 나온 숫자를 적어 둔다.** 파일럿은 16개 중 6개였다. 구조 결합 10건이 상한이다.

- [ ] **Step 7: 고치고, 여전히 고장을 잡는지 확인한다**

Global Constraints의 "파일럿에서 배운 것" 2·3·4를 따른다.

- [ ] **Step 8: 검증**

```powershell
.\.fvm\flutter_sdk\bin\dart.bat format lib test
.\.fvm\flutter_sdk\bin\flutter.bat analyze
.\.fvm\flutter_sdk\bin\flutter.bat test
```

Expected: analyze `No issues found!`, 941개 통과.

- [ ] **Step 9: 에뮬레이터에서 본다**

홈에서 매칭 시작을 누르면 바로 이 화면이다. **셋 중 가장 확인하기 쉽다.**

- [ ] **Step 10: 커밋하고 PR, base 확인 후 머지**

---

### Task 4: 잰 것을 적고 다음 순서를 정한다

**Files:**
- Modify: `docs/specs/2026-09-25-ui-redesign-workspace-design.md` (9절에 이어 적는다)

**Interfaces:**
- Consumes: Task 1~3의 "새로 만든 부품", "깨진 테스트 수"
- Produces: 없음 (문서). 네 번째 계획이 이것을 근거로 순서를 정한다

- [ ] **Step 1: 9절 뒤에 이어 적는다**

```markdown
### 두 번째 묶음 — 매칭·러닝 흐름 (2026-09-29~)

| 화면 | 시안 | 테스트 | 깨진 수 | 새로 만든 부품 |
|---|---|---|---|---|
| `match_countdown_page` | `158:3453` | 없음 | — | [실제] |
| `run_summary_page` | `158:3764` | 없음 | — | [실제] |
| `match_register_page` | `158:3181` | 12 | [실제] | [실제] |

**재사용은 [됐다/안 됐다].** [근거]

⚠️ **테스트 없는 화면이 둘이었다.** 에뮬레이터 확인만으로 옮겼다.
남은 화면 중 테스트가 없는 것: [목록]

### 시안에만 있는 것을 만난 자리

`매칭등록`에 `친구랑 같이 뛰기` 진입점이 있다. **넣지 않았다** — 갈 곳이
없고, "친구" 문구도 CLAUDE.md 승인 전이다.

### 디자인 아이콘에 없는 것

`clock` · `gauge`. [시안에 자리가 있었는지 / 디자이너에게 요청했는지]
```

- [ ] **Step 2: 검증하고 커밋**

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat analyze
.\.fvm\flutter_sdk\bin\flutter.bat test
```

```bash
git checkout -b docs/redesign-second-batch upstream/dev
git add docs/specs
git commit -m "📝 Docs: 매칭·러닝 흐름 실측을 적는다"
```

- [ ] **Step 3: PR을 열고 base 확인 후 머지**

---

## 이 계획이 다루지 않는 것

**남은 화면 15개.** 다음 계획들이 나눠 맡는다. 순서의 근거는 이미 재어 뒀다.

| 묶음 | 화면 | 왜 뒤인가 |
|---|---|---|
| **인증·온보딩 6개** | 스플래시 · 온보딩 · 로그인 · 회원가입 · 약관동의 · 프로필등록 | 구조 결합이 **60건, 전체의 43%** 로 몰려 있다. `AppInputV2`가 필요하고(입력을 5개 화면이 쓴다), 한 테스트 파일이 여러 화면을 걸쳐 본다 |
| **실시간 러닝 3개** | 실시간 기록 · 내 GPS · 파티원 비교 | 앱에서 가장 복잡하다. ⚠️ 여기 적었던 "케이던스·칼로리가 없다"는 **틀린 말이었다** — 둘 다 이미 화면에 있다(스펙 8절) |
| **탭 화면 3개** | 홈 · 기록 · 프로필 | **탭 5→4 결정이 CLAUDE.md 승인 대기 중**이다. `AppShell`·라우팅과 한꺼번에 얽힌다 |
| **시안 없는 6개** | 프로필 편집 · 기록 상세 · 설정 · 비밀번호 변경 · 러닝 준비 · 준비중 | 토큰만 갈아끼운다. 레이아웃을 바꿀 근거가 없다 |
| **시안에만 있는 4개** | 친구 목록 · 친구초대 · 뱃지 획득 · 도감 상세 | 껍데기만 만든다. 라우팅이 먼저 정리돼야 한다 |

같이 미루는 것:

- **종료 후 대시보드**(`158:3602`) — 뱃지와 파티원 기록이 필요하다
- **마무리 정리**(스펙 7절) — 마지막 화면 뒤 `v2/`를 본래 자리로 올리고, 그때 `theme_generation_test`와 Pretendard·Lucide를 같이 뺀다
