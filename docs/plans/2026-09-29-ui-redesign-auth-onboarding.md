# UI 전면 교체 — 인증·온보딩 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 앱에 처음 들어오는 길 여섯 화면을 새 디자인으로 옮기고, 그 과정에서 `AppInputV2`를 만든다.

**Architecture:** 화면 하나가 PR 하나다. **입력이 없는 셋을 먼저** 옮겨 흐름을 확인하고, 그 다음 `AppInputV2`를 만들어 나머지 셋을 연다. 입력을 쓰는 화면이 앱 전체에 다섯이라, 그 부품 하나가 이 묶음 밖의 둘(프로필 편집·비밀번호 변경)까지 함께 연다.

**Tech Stack:** Flutter (fvm) · flutter_test · flutter_svg · Figma MCP

**Spec:** `docs/specs/2026-09-25-ui-redesign-workspace-design.md` (9~12절에 실측과 관문)

**Figma:** 파일 `MpJxkA7fPj6MJs5uL07CVb`, 화면은 전부 `149:791` 아래.

## Global Constraints

- 모든 flutter/dart 명령은 `.\.fvm\flutter_sdk\bin\flutter.bat` / `dart.bat` 으로 직접 부른다.
- 모든 커밋 시점에 `analyze` 경고 **0개**, `test` **전체 통과**(현재 941개).
- 커밋 메시지 `<이모지> <Type>: <설명>`. **AI를 공동 작성자로 넣지 않는다.**
- **PR 하나 = 화면 하나.** base는 `dev`. 앞 PR이 머지된 뒤 `upstream/dev`에서 새로 딴다.
- **한 화면은 한 세대의 토큰만 쓴다.** `test/theme_generation_test.dart`가 강제한다.
- 옮긴 화면은 `core/theme/v2/`와 `core/widgets/v2/`만 import한다. Lucide 대신 `AppIcon`.
- 화면마다 **다크 테마를 에뮬레이터에서 본다.** ⚠️ 라이트는 앱이 `ThemeMode.dark`로 고정돼 실행 경로가 없다(스펙 13절). 정의만 하고 확인은 건너뛴다 — PR에 그렇게 적는다.
- `Color(0x...)` 하드코딩은 `core/theme/` 안에서만. 시안의 값이 토큰에 없으면 **토큰에 넣고** 쓴다.
- 우리에게 없는 값을 **지어내지 않는다.**

### 앞선 두 묶음에서 배운 것 — 매 화면에 적용한다

1. **그 화면의 시안을 먼저 읽는다.** 토큰과 코드만 대조하면 틀린다.
2. **두 번째로 쓰이는 순간 `core/widgets/v2/`로 올린다.** 화면 안 private 클래스로 두면 다음 화면이 못 쓴다.
3. **깨진 테스트를 그 PR 안에서 고친다.** 구조 결합은 `find.text`로, 잠김은 눌러 보는 것으로.
4. **고친 뒤 화면을 일부러 부순다.** ⚠️ 안 빨개지면 **부수기가 헛것이었는지 먼저 의심한다** — 매칭 등록에서 이중 방어 때문에 한 번 헛돌았다.
5. **화면 클래스 단정(`find.byType(...Page)`)은 건드리지 않는다.**

## 이 묶음이 상대하는 것

**테스트 파일 9개 · 테스트 125개 · 구조 결합 77건.** 지금까지 옮긴 네 화면을 다 합친 것보다 많다.

| 테스트 파일 | 테스트 | 결합 |
|---|---|---|
| `sign_up_page_test` | 13 | **21** |
| `profile_setup_test` | 22 | **15** |
| `sign_in_page_test` | 16 | **13** |
| `home_page_test` | 12 | 11 |
| `onboarding_flow_test` | 14 | 11 |
| `profile_page_test` | 25 | 3 |
| `terms_agreement_test` | 9 | 2 |
| `kakao_terms_test` | 8 | 1 |
| `status_routing_test` | 6 | 0 |

⚠️ **한 파일이 여러 화면을 걸쳐 본다.** `onboarding_flow_test`는 스플래시·온보딩·회원가입·약관을 한 줄기로 통과한다. 화면 하나를 옮겨도 그 파일 전체가 흔들릴 수 있다 — **PR마다 전체 스위트를 돌린다.**

`home_page_test`·`profile_page_test`가 걸린 이유는 그 화면들이 프로필 등록을 거쳐 들어가기 때문이다. **홈·프로필 자체는 이 묶음에서 옮기지 않는다**(탭 4개 결정 대기).

---

### Task 1: 스플래시를 옮긴다

시안 `158:2695` → `lib/features/onboarding/presentation/splash_page.dart`

**가장 단순하다.** `AppButton` 하나만 쓰고 아이콘이 없다. 이 묶음의 흐름을 확인하는 자리다.

**Files:**
- Modify: `lib/features/onboarding/presentation/splash_page.dart`

**Interfaces:**
- Consumes: `AppColorsV2` `AppTypographyV2` `AppButtonV2`, v2 경로의 `AppSpacing`·`AppRadius`·`AppSizes`
- Produces: 없음이 목표

- [ ] **Step 1: 기준선**

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat test
Select-String -Path lib/features/onboarding/presentation/splash_page.dart -Pattern "core/theme|core/widgets|LucideIcons"
```

Expected: 941개 통과. import에 `core/theme/extensions`·`tokens`가 보인다.

- [ ] **Step 2: 시안을 읽는다**

`figma-design-to-code` 스킬을 먼저 불러온 뒤:

```
get_design_context(fileKey: "MpJxkA7fPj6MJs5uL07CVb", nodeId: "158:2695",
                   clientFrameworks: "flutter", clientLanguages: "dart",
                   skillNames: "figma-design-to-code")
```

- [ ] **Step 3: 토큰 import를 v2로 통째로 바꾸고 옮긴다**

한 줄이라도 남으면 세대 혼용 테스트가 막는다.

- [ ] **Step 4: 검증**

```powershell
.\.fvm\flutter_sdk\bin\dart.bat format lib test
.\.fvm\flutter_sdk\bin\flutter.bat analyze
.\.fvm\flutter_sdk\bin\flutter.bat test
```

⚠️ **전체 스위트를 돌린다.** `onboarding_flow_test`·`status_routing_test`가 이 화면을 지난다.

- [ ] **Step 5: 깨진 것을 세고 고친다**

깨진 수를 적어 둔다. Task 7이 쓴다.

- [ ] **Step 6: 에뮬레이터에서 본다**

앱을 지우고 다시 깔면 첫 화면이다.

```powershell
adb -s emulator-5556 uninstall com.swmaestro.runiverse
.\.fvm\flutter_sdk\bin\flutter.bat build apk --debug --dart-define-from-file=config/dev.json
adb -s emulator-5556 install build/app/outputs/flutter-apk/app-debug.apk
```

⚠️ **지우면 로그인 상태도 사라진다.** 다시 로그인해야 다음 화면들을 볼 수 있다.

- [ ] **Step 7: 커밋하고 PR, base 확인 후 머지**

---

### Task 2: 온보딩 소개를 옮긴다

시안 `158:2699` → `lib/features/onboarding/presentation/onboarding_intro_page.dart`

`AppButton`과 `PageIndicator`를 쓴다. **`PageIndicatorV2`가 여기서 나온다** — 실시간 기록 화면도 그것을 쓰므로 `core/widgets/v2/`에 만든다.

**Files:**
- Modify: `lib/features/onboarding/presentation/onboarding_intro_page.dart`
- Create: `lib/core/widgets/v2/page_indicator.dart`

**Interfaces:**
- Consumes: Task 1이 확정한 것들
- Produces: `PageIndicatorV2` — 실시간 기록이 나중에 쓴다

- [ ] **Step 1: 앞 PR 머지 후 `dev`에서 딴다**

```bash
git fetch upstream
git checkout -b style/onboarding-intro-redesign upstream/dev
```

- [ ] **Step 2: 시안을 읽는다** (`158:2699`)

- [ ] **Step 3: `PageIndicatorV2`를 만든다**

⚠️ **기존 것과 모양이 같으면 만들지 않는다.** 시안의 점 크기·간격·선택 색을 대조하고 판단한다. 같으면 `core/theme/v2` 재수출만으로 끝날 수도 있다.

- [ ] **Step 4~7: Task 1의 3~7과 같다**

---

### Task 3: 약관 동의를 옮긴다

시안 `158:2804` → `lib/features/onboarding/presentation/terms_agreement_page.dart`

`LegalDocument`를 쓴다. 체크박스가 있어 **선택 상태의 시각**이 중요하다.

**Files:**
- Modify: `lib/features/onboarding/presentation/terms_agreement_page.dart`
- Create: `lib/core/widgets/v2/legal_document.dart` (필요하면)

**Interfaces:**
- Consumes: 앞 작업들
- Produces: `LegalDocumentV2` (만들게 되면) — 설정 화면이 나중에 쓴다

- [ ] **Step 1: `dev`에서 딴다**
- [ ] **Step 2: 시안을 읽는다** (`158:2804`)
- [ ] **Step 3: 체크 아이콘을 정한다**

지금 `LucideIcons.check`·`chevronRight`·`info`·`arrowLeft`를 쓴다.
→ `check` · `right` · `guide` · `left`. **넷 다 디자인 아이콘에 있다.**

- [ ] **Step 4~7: Task 1의 3~7과 같다**

⚠️ 이 화면은 테스트가 세 파일에 걸쳐 있다(`terms_agreement_test` `kakao_terms_test` `onboarding_flow_test`). **전체 스위트를 반드시 돌린다.**

---

### Task 4: `AppInputV2`를 만든다

**화면을 옮기지 않는다.** 부품 하나만 만들고 그 PR로 끝낸다.

입력을 쓰는 화면이 다섯이다 — 로그인 · 회원가입 · 프로필등록 · 프로필편집 · 비밀번호변경. 화면에 딸려 만들면 첫 화면의 필요만 반영되고 나머지 넷이 각자 고치게 된다.

**Files:**
- Create: `lib/core/widgets/v2/app_input.dart`
- Test: `test/v2_app_input_test.dart`

**Interfaces:**
- Consumes: `AppColorsV2` `AppTypographyV2`
- Produces: `AppInputV2` — 기존 `AppInput`과 **같은 인자 이름**을 쓴다

- [ ] **Step 1: `dev`에서 딴다**

```bash
git checkout -b feat/app-input-v2 upstream/dev
```

- [ ] **Step 2: 기존 `AppInput`의 계약을 적는다**

```powershell
Select-String -Path lib/core/widgets/app_input.dart -Pattern "final |required this"
```

⚠️ **인자 이름을 하나도 바꾸지 않는다.** 화면을 옮길 때 import 한 줄만 바꾸면 되도록 한다 — `FactCard`·`PresetChipV2`에서 통한 방식이다.

- [ ] **Step 3: 시안에서 입력 모양을 읽는다**

회원가입(`158:2720`)과 로그인(`158:2913`)에 입력이 있다. **둘 다 읽고** 같은 모양인지 확인한다.

```
get_design_context(fileKey: "MpJxkA7fPj6MJs5uL07CVb", nodeId: "158:2720", …)
get_design_context(fileKey: "MpJxkA7fPj6MJs5uL07CVb", nodeId: "158:2913", …)
```

읽을 것: 면 색 · 반경 · 높이 · 안쪽 여백 · 라벨/힌트 크기 · **포커스와 오류 상태**.

⚠️ **오류 상태가 시안에 없으면 만들어야 한다.** 그때는 `AppColorsV2.error`를 쓰고 PR에 "시안에 없어 정한 값"으로 적는다.

- [ ] **Step 4: 만들고 테스트를 쓴다**

```dart
// test/v2_app_input_test.dart
// 이 부품이 지키는 약속만 본다.
// - 힌트는 비었을 때만 보인다
// - 오류 문구가 있으면 테두리 색이 바뀐다
// - `obscureText`가 글자를 가린다
```

⚠️ **입력을 찾는 손잡이를 정한다.** `profile_edit_page_test`에서 `ValueKey`로 찾기로 했다(스펙 9절). `AppInputV2`도 `key`를 그대로 내려보내는지 확인한다 — `super.key`면 `tester.enterText`가 닿는다.

- [ ] **Step 5: 검증하고 PR**

Expected: 941 + 새 테스트 수.

---

### Task 5: 로그인을 옮긴다

시안 `158:2913` → `lib/features/auth/presentation/sign_in_page.dart`

`AppInputV2`의 첫 사용처다. 테스트 16개 · 결합 13건.

아이콘: `circleAlert` → **`alert`**(우리가 그린 것) · `square`/`squareCheck` → `check`/`check_2`.

- [ ] **Step 1: `dev`에서 딴다**
- [ ] **Step 2: 시안을 읽는다** (`158:2913`)
- [ ] **Step 3: 체크박스 아이콘 둘을 확인한다**

⚠️ `square`(빈 네모)에 대응하는 디자인 아이콘이 있는지 본다. `check`·`check_2`가 체크 표시라면 **빈 상태를 그릴 것이 없다.** 없으면 테두리만 그린 사각형을 화면에서 만들고 PR에 적는다.

- [ ] **Step 4~7: Task 1의 3~7과 같다**

---

### Task 6: 회원가입과 프로필 등록을 옮긴다

시안 `158:2720` · `158:2758` → `sign_up_page.dart` · `profile_setup_page.dart`

**둘을 한 작업으로 묶되 PR은 따로 낸다.** 회원가입이 프로필 등록으로 이어지고, 같은 `onboarding_flow_test`가 둘을 한 줄기로 지난다.

⚠️ **이 묶음에서 가장 무겁다** — 결합 21 + 15건. 입력이 각각 12개다.

- [ ] **Step 1: 회원가입부터. `dev`에서 딴다**
- [ ] **Step 2: 시안을 읽는다** (`158:2720`)
- [ ] **Step 3~7: Task 1의 2~7과 같다**
- [ ] **Step 8: 머지 후 프로필 등록. `dev`에서 새로 딴다**
- [ ] **Step 9: 시안을 읽는다** (`158:2758`)

⚠️ 이 화면은 `PresetChip`도 쓴다 — `PresetChipV2`가 이미 있다.

- [ ] **Step 10~14: 같은 절차**

---

### Task 7: 잰 것을 적는다

**Files:**
- Modify: `docs/specs/2026-09-25-ui-redesign-workspace-design.md`

- [ ] **Step 1: 9절에 세 번째 묶음을 이어 적는다**

```markdown
### 세 번째 묶음 — 인증·온보딩 (2026-XX-XX~)

| 화면 | 시안 | 깨진 수 | 새로 만든 부품 |
|---|---|---|---|
| `splash_page` | `158:2695` | [실제] | [실제] |
| `onboarding_intro_page` | `158:2699` | [실제] | [실제] |
| `terms_agreement_page` | `158:2804` | [실제] | [실제] |
| `sign_in_page` | `158:2913` | [실제] | [실제] |
| `sign_up_page` | `158:2720` | [실제] | [실제] |
| `profile_setup_page` | `158:2758` | [실제] | [실제] |

**상대한 것:** 테스트 125개 · 구조 결합 77건.
**실제로 깨진 것:** [합계]

`AppInputV2`를 화면과 따로 만든 판단은 [옳았다/틀렸다] — [근거]
```

- [ ] **Step 2: 10절의 아이콘 목록을 갱신한다**

이 묶음에서 쓴 것과 여전히 없는 것을 가른다.

- [ ] **Step 3: 11절에서 옮긴 화면을 지운다**

- [ ] **Step 4: 검증하고 PR**

---

## 이 계획이 다루지 않는 것

**남은 9개 화면.**

| 묶음 | 화면 | 왜 뒤인가 |
|---|---|---|
| **탭 화면 3개** | 홈 · 기록 · 프로필 | **탭 5→4 결정이 CLAUDE.md 승인 대기 중.** `AppShell`·라우팅과 한꺼번에 얽힌다. ⚠️ 대회 아이콘이 필요한지도 이 결정에 달렸다 |
| **실시간 러닝 3개** | 실시간 기록 · 내 GPS · 파티원 비교 | 앱에서 가장 복잡하고, **연결 끊김·GPS 조준 아이콘이 없다**(스펙 10절) |
| **시안 없는 3개** | 기록 상세 · 설정 · 러닝 준비 | 토큰만 갈아끼운다. ⚠️ 러닝 준비는 GPS 조준 아이콘이 필요하다 |
| **프로필 편집 · 비밀번호 변경** | | 시안이 없지만 `AppInputV2`를 쓴다. Task 4 뒤에는 토큰 교체만 남는다 |
| **시안에만 있는 4개** | 친구 목록 · 친구초대 · 뱃지 획득 · 도감 상세 | 껍데기만 만든다. 라우팅 정리가 먼저 |

같이 미루는 것:

- **종료 후 대시보드**(`158:3602`) — 뱃지가 없다
- **마무리 정리**(스펙 7절) — 마지막 화면 뒤 `v2/`를 본래 자리로 올리고, 그때 `theme_generation_test`와 Pretendard·Lucide를 같이 뺀다
