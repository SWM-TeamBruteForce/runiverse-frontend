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

### ⚠️ 위 결합 수는 과한 추정이었다 (2026-09-30 실측)

세는 방법이 거칠었다. `find.byType(TextField)`까지 결합으로 셌는데 **`AppInputV2`도 안에서
`TextField`를 쓰므로 그대로 산다.** 실제로 손댄 것은 대부분 `AppButton` 한 종류였다.

| 파일 | 추정 | **실제로 깨진 수** |
|---|---|---|
| `sign_in_page_test` | 13 | **11** (전부 `AppButton`) |
| `terms_agreement_test` | 2 | **12** — ⚠️ 추정보다 많았다. CTA 단정이 화면마다 퍼져 있었다 |
| `kakao_terms_test` | 1 | **8** |
| `sign_up_page_test` | 21 | **2**(예상) |
| `profile_setup_test` | 15 | **9**(예상) |

→ **결합 수는 작업량의 지표가 아니었다.** 진짜 비용은 화면의 **구조가 바뀌는가**에 달렸다 —
프로필 등록은 결합이 9건인데 테스트 22개 중 다수를 새로 써야 한다(Task 6c).

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

### Task 6: 회원가입과 프로필 등록 — **네 PR로 나눈다**

시안 `158:2720` · `158:2758` → `sign_up_page.dart` · `profile_setup_page.dart`

⚠️ **이 묶음에서 가장 무겁고, 하나는 이관이 아니라 재작성이다.**

#### 2026-09-30 결정 세 가지

| 물은 것 | 정한 것 |
|---|---|
| 프로필 등록의 배치 | **시안대로 한 화면 폼으로 재작성.** 단계형 질문과 휠 피커를 버린다 |
| 가입 흐름 순서 | **지금 순서 유지**(약관 → 회원가입 → 프로필). 진행 바만 `1/3 · 2/3 · 3/3`으로 얹는다 |
| 비밀번호 확인 칸 | **넣는다.** 불일치 검증은 Flutter 클라이언트에서 한다 (서버는 확인값을 받지 않는다) |

#### 실측 — 계획서 첫 추정이 과했다

| 파일 | 테스트 | **실제** 구조 결합 | 첫 추정 |
|---|---|---|---|
| `sign_up_page_test` | 13 | **2** (`AppButton`) | 21 |
| `profile_setup_test` | 22 | **9** (`AppButton`) | 15 |

`find.byType(TextField)`가 15건인데 `AppInputV2`도 안에서 `TextField`를 쓰므로 **그대로 산다.**
다만 프로필 등록은 결합 수가 문제가 아니다 — **화면이 통째로 바뀌어 22개 중 다수가 전제부터 무너진다.**

---

#### Task 6a: 공용 부품 둘을 먼저 만든다 — 화면은 건드리지 않는다

`AppInputV2`를 화면과 따로 만든 것이 통했다(9절). 같은 이유로 **세 화면이 쓸 것을 먼저** 만든다.

**Files:**
- Create: `lib/core/widgets/v2/step_progress.dart` — `StepProgressV2`
- Create: `lib/core/widgets/v2/field_action.dart` — `FieldActionV2`
- Test: `test/v2_step_progress_test.dart` · `test/v2_field_action_test.dart`

**Interfaces:**
- Produces: `StepProgressV2({required int step, required int total})`
- Produces: `FieldActionV2({required String label, required VoidCallback? onPressed})`

- [ ] **Step 1: `dev`에서 딴다**

```bash
git checkout -b feat/step-progress-and-field-action
```

- [ ] **Step 2: 시안에서 두 부품의 값을 읽는다**

진행 바 — `158:2721`(회원가입) · `158:2767`(프로필) · `158:2840`(약관)

| 값 | 시안 |
|---|---|
| 트랙 | 높이 4 · 폭 364 · radius 100 · `#575757` |
| 채움 | 같은 높이 · `#227DFF` |
| 자리 | 상단 바 아래 (`top 116`) |

⚠️ **채움 폭이 시안마다 다르다** — 91 / 182 / 273 = 25 / 50 / 75%. 시안은 4단계를 전제하지만
**우리는 3단계다.** `step / total` 로 계산하고 시안의 픽셀을 그대로 옮기지 않는다.

칸 안 액션 버튼 — `158:2729`(인증하기) · `158:2742`(재전송) · `158:2778`(중복확인)

| 값 | 시안 |
|---|---|
| 글자 | 12 SemiBold · `#767676` |
| 면 | `#434343` · radius 10 |
| 여백 | 가로 14 · 세로 10.5 |

⚠️ **높이가 35라 44에 못 미친다.** 눈 아이콘과 같은 방법으로 푼다 — 자리는 35만 차지하고
누르는 영역만 44로 넘치게 `OverflowBox`를 쓴다 (`password_field_v2.dart`가 선례다).

- [ ] **Step 3: 실패하는 테스트를 쓴다**

```dart
// test/v2_step_progress_test.dart
testWidgets('⚠️ 채움 폭이 단계에 비례한다', (tester) async {
  await pump(tester, const StepProgressV2(step: 2, total: 3));

  final track = tester.getSize(find.byKey(StepProgressV2.trackKey));
  final fill = tester.getSize(find.byKey(StepProgressV2.fillKey));

  expect(fill.width / track.width, closeTo(2 / 3, 0.01));
});

testWidgets('마지막 단계는 꽉 찬다', (tester) async {
  await pump(tester, const StepProgressV2(step: 3, total: 3));

  final track = tester.getSize(find.byKey(StepProgressV2.trackKey));
  final fill = tester.getSize(find.byKey(StepProgressV2.fillKey));

  expect(fill.width, track.width);
});
```

```dart
// test/v2_field_action_test.dart
testWidgets('⚠️ 누르는 영역이 44를 지킨다', (tester) async {
  // 글자가 작아 칸을 밀지 않으면서도 손가락은 닿아야 한다.
  await pump(tester, FieldActionV2(label: '인증하기', onPressed: () {}));

  final tap = tester.getSize(find.byType(InkWell));
  expect(tap.height, greaterThanOrEqualTo(AppSizes.touchDefault));
});

testWidgets('⚠️ 그런데 칸의 높이는 밀지 않는다', (tester) async {
  await pump(tester, FieldActionV2(label: '인증하기', onPressed: () {}));

  expect(tester.getSize(find.byType(FieldActionV2)).height, lessThan(40));
});

testWidgets('onPressed 가 null 이면 눌리지 않는다', (tester) async {
  await pump(tester, const FieldActionV2(label: '재전송', onPressed: null));

  expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
});
```

- [ ] **Step 4: 돌려서 빨간지 본다**

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat test test/v2_step_progress_test.dart test/v2_field_action_test.dart
```

Expected: FAIL — 두 클래스가 없다.

- [ ] **Step 5: 만든다**

`step_progress.dart` — `LayoutBuilder` 로 트랙 폭을 재고 `FractionallySizedBox` 로 채운다.
`Semantics(value: '$step / $total')` 를 붙인다 — 막대만으로는 스크린리더가 읽을 것이 없다.

`field_action.dart` — `password_field_v2.dart` 의 `OverflowBox` 방식을 그대로 쓴다.

- [ ] **Step 6: 초록인지 보고, 일부러 부순다**

`FractionallySizedBox` 의 `widthFactor` 를 `1` 로 고정하면 비례 테스트가 빨개져야 한다.

- [ ] **Step 7: 검증하고 PR**

```powershell
.\.fvm\flutter_sdk\bin\dart.bat format lib test
.\.fvm\flutter_sdk\bin\flutter.bat analyze     # 경고 0개
.\.fvm\flutter_sdk\bin\flutter.bat test        # 956 + 새 테스트
```

⚠️ 화면에 붙지 않은 부품이라 에뮬레이터로 볼 자리가 없다. **PR 에 그렇게 적는다** —
`AppInputV2`(PR #96) 때와 같다.

---

#### Task 6b: 회원가입을 옮긴다

시안 `158:2720`. **이관이다** — 구조는 그대로고 토큰과 부품이 바뀐다.

**Files:**
- Modify: `lib/features/auth/presentation/sign_up_page.dart`
- Modify: `lib/features/onboarding/presentation/terms_agreement_page.dart` (진행 바 `1/3`)
- Modify: `lib/core/strings/app_strings.dart`
- Test: `test/sign_up_page_test.dart`

- [ ] **Step 1: `dev`에서 딴다** (6a 머지 후)
- [ ] **Step 2: 시안을 다시 읽는다** (`158:2720`)

- [ ] **Step 3: 바뀌는 것을 적어 두고 시작한다**

| 자리 | 지금 | 시안 |
|---|---|---|
| 이메일·인증번호 버튼 | 칸 **아래** `AppButton` | 칸 **안** `FieldActionV2` |
| 칸 모양 | 라벨 밖 | **라벨 있는 큰 칸**(71) — `AppInputV2` 에 `label` 을 넘기면 된다 |
| 비밀번호 확인 | **없다** | 있다 — 새로 만든다 |
| 진행 바 | 없다 | `2/3` |
| 뒤로 아이콘 | `LucideIcons.arrowLeft` | `AppIcons.left` |
| 인증 완료 표시 | `LucideIcons.circleCheck` | ⚠️ 디자인 아이콘에 **없다** — `AppIcons.verified` 로 대체하고 PR 에 적는다 |

- [ ] **Step 4: 비밀번호 확인의 실패하는 테스트를 먼저 쓴다**

```dart
testWidgets('⚠️ 비밀번호가 서로 다르면 가입할 수 없다', (tester) async {
  // 서버는 확인값을 받지 않는다. 막는 곳이 여기뿐이다.
  await pumpSignUp(tester);
  await fillVerifiedEmail(tester);

  await tester.enterText(passwordField, 'runiverse1!');
  await tester.enterText(confirmField, 'runiverse2!');
  await tester.pumpAndSettle();

  expect(ctaEnabled(tester), isFalse);
  expect(find.text(AppStrings.authPasswordMismatch), findsOneWidget);
});

testWidgets('같으면 가입할 수 있다', (tester) async {
  await pumpSignUp(tester);
  await fillVerifiedEmail(tester);

  await tester.enterText(passwordField, 'runiverse1!');
  await tester.enterText(confirmField, 'runiverse1!');
  await tester.pumpAndSettle();

  expect(ctaEnabled(tester), isTrue);
});
```

⚠️ **확인 칸이 비어 있을 때를 오류로 그리지 않는다.** 아직 안 친 것뿐이다 —
로그인의 이메일 형식 판정과 같은 규칙이다.

- [ ] **Step 5: 옮긴다**

`AppInput` → `AppInputV2` · `AppInputTone` → `AppInputToneV2` · `PasswordField` → `PasswordFieldV2` ·
`AppButton` → `AppButtonV2` · 토큰 전부 `v2`.

- [ ] **Step 6: 깨진 테스트를 고치고 화면을 부순다**

`AppButton` 2건을 `AppButtonV2` 로. 그다음 **불일치 판정을 항상 참으로 만들어** 새 테스트가
빨개지는지 본다.

- [ ] **Step 7: 검증 · 에뮬레이터 · PR**

⚠️ 에뮬레이터는 **로그아웃 상태**여야 이 화면에 닿는다. 로그인 → `가입하기` → 약관 → 회원가입.

---

#### Task 6c: ⚠️ 프로필 등록을 **다시 쓴다**

시안 `158:2758`. **이관이 아니다.** 1067줄이 통째로 바뀐다.

**Files:**
- Rewrite: `lib/features/onboarding/presentation/profile_setup_page.dart`
- Create: `lib/features/onboarding/domain/body_rule.dart`
- Create: `lib/core/widgets/v2/segmented_toggle.dart` (⚠️ 아래 판단 참고)
- Test: `test/body_rule_test.dart` · `test/profile_setup_test.dart` (대거 재작성)

- [ ] **Step 1: 버리는 것과 지키는 것을 먼저 가른다**

**버린다** — 단계형 질문 흐름(`_Question` `_AnsweredRow` `_PickerRow` `_ChipRow`),
휠 시트 세 개, `_rowHeight`.

**지킨다** — 닉네임 규칙(`NicknameRule`) · 중복확인 · 나이 하한(`AgeRule`) ·
`OnboardingProfile` 전송 · 실패 처리 · 페이스 건너뛰기.

⚠️ **지금 코드의 판단을 뒤집는 것이므로, 그 주석을 지우지 말고 고쳐 적는다.**
"여섯 항목을 한 화면에 늘어놓으면 이탈 신호"라고 적힌 자리에 **2026-09-30 에 시안을 따르기로
했다**고 남긴다. 다음 사람이 "왜 되돌렸나"를 묻지 않게.

- [ ] **Step 2: 휠 피커가 막아주던 것을 도메인 규칙으로 옮긴다 — 먼저 테스트**

⚠️ **여기가 이 작업의 핵심 위험이다.** 고르게 하던 값을 치게 하면 못 만들던 값이 만들어진다.

```dart
// test/body_rule_test.dart
test('⚠️ 없는 날짜를 막는다', () {
  // 지금 휠 피커도 이건 못 막는다 — 일 칸이 달과 무관하게 1~31 이다.
  expect(BodyRule.parseBirth('19990231'), isNull);
  expect(BodyRule.parseBirth('20230229'), isNull);   // 평년
  expect(BodyRule.parseBirth('20240229'), isNotNull); // 윤년
});

test('여덟 자리가 아니면 막는다', () {
  expect(BodyRule.parseBirth('1999116'), isNull);
  expect(BodyRule.parseBirth('199901160'), isNull);
  expect(BodyRule.parseBirth('1999-01-16'), isNull);
});

test('⚠️ 아직 오지 않은 날은 막는다', () {
  final now = DateTime(2026, 9, 30);
  expect(BodyRule.isAllowedBirth(DateTime(2027, 1, 1), now: now), isFalse);
});

test('키와 몸무게는 휠이 주던 범위를 그대로 쓴다', () {
  // 130~210 / 30~140 — 옛 화면의 휠 값이 근거다. 바꾸려면 그쪽도 같이 본다.
  expect(BodyRule.isAllowedHeight(129), isFalse);
  expect(BodyRule.isAllowedHeight(130), isTrue);
  expect(BodyRule.isAllowedHeight(210), isTrue);
  expect(BodyRule.isAllowedHeight(211), isFalse);
  expect(BodyRule.isAllowedWeight(29), isFalse);
  expect(BodyRule.isAllowedWeight(140), isTrue);
});
```

⚠️ 나이 하한은 `AgeRule` 이 이미 갖고 있다. **`BodyRule` 에 다시 적지 않는다** — 두 군데가
갈리면 프로필 수정 화면과 어긋난다.

- [ ] **Step 3: 돌려서 빨간지 보고 `body_rule.dart` 를 만든다**

- [ ] **Step 4: 성별 토글을 만든다**

시안 `158:2760` — 바깥 상자 `#171717` radius 16 높이 72, 안에 170×56 버튼 둘 radius 14.
켜진 쪽 `#227DFF` + 16 SemiBold `#fafafa`, 꺼진 쪽 투명 + 16 Medium `#575757`.

⚠️ **지금은 여기서만 쓴다.** "두 번째로 쓰이는 순간 올린다"는 규칙대로 **화면 안 private 으로
두고**, 프로필 수정 화면이 같은 것을 쓸 때 `core/widgets/v2/` 로 올린다.

- [ ] **Step 5: 화면을 쓴다**

```
진행 바 3/3
제목  기본 프로필을 / 등록해주세요
닉네임      + FieldActionV2(중복확인)
생년월일    직접 입력 · ex.19990116 · 숫자 8자리
[ 남자 ][ 여자 ]
키(cm)  |  몸무게(kg)     ← 나란히, 각 175
페이스 수준                ← 누르면 시트, 오른쪽 AppIcons.down
CTA  다음
```

⚠️ **키보드가 칸을 가린다.** 여섯 칸이 한 화면에 있고 아래 칸을 누르면 키보드가 덮는다 —
`SingleChildScrollView` + `MediaQuery.viewInsetsOf` 로 밀어 올린다. 단계형에서는 없던 문제다.

⚠️ 페이스는 선택지가 넷뿐이라 시트가 아깝지만, **시안이 칸 + 아래 화살표**다. 시트를 연다.
`PresetChipV2` 는 여기서 쓰지 않게 된다 — 매칭 등록이 계속 쓰므로 지우지 않는다.

- [ ] **Step 6: 테스트를 다시 쓴다**

⚠️ **22개 중 단계형을 전제한 것들이 무너진다.** "답하면 다음 질문이 붙는다" 류는 지우고,
**한 화면 폼에서 지켜야 할 것**으로 바꾼다.

| 지우는 것 | 대신 넣는 것 |
|---|---|
| 답한 줄이 위에 쌓인다 | 여섯 칸이 처음부터 다 보인다 |
| 쌓인 줄을 누르면 그 질문으로 돌아간다 | (없앤다 — 아무 칸이나 바로 고친다) |
| 다음 질문이 자동으로 붙는다 | 필수를 다 채워야 CTA 가 열린다 |
| — | ⚠️ 없는 날짜·범위 밖 키·몸무게를 치면 오류가 뜨고 CTA 가 잠긴다 |

**지키는 것** — 닉네임 중복확인 · 길이 제한 · 만 14세 · 페이스 건너뛰기 · 전송 실패 처리.

- [ ] **Step 7: 부순다**

`BodyRule.parseBirth` 가 항상 오늘을 돌려주게 만들고, 없는 날짜 테스트가 빨개지는지 본다.

- [ ] **Step 8: 검증 · 에뮬레이터 · PR**

⚠️ **PR 이 500줄을 넘는다.** 재작성이라 어쩔 수 없다 — `CLAUDE.md` 대로 **사유를 PR 에 적는다.**

---

#### Task 6d: 약관에 진행 바를 얹는다

**Files:**
- Modify: `lib/features/onboarding/presentation/terms_agreement_page.dart`

6b 에서 같이 해도 되지만, **약관은 이미 옮긴 화면**이라 되돌아가 손대는 것이 드러나게 따로 낸다.
`StepProgressV2(step: 1, total: 3)` 한 줄 + 제목 위 자리.

⚠️ 약관 화면의 세로가 이미 빡빡하다(PR #95). 진행 바 4 + 여백이 들어가면
**CTA 가 제스처 내비에 붙는지 에뮬레이터로 본다.**

---

### Task 7: 잰 것을 적는다

**Files:**
- Modify: `docs/specs/2026-09-25-ui-redesign-workspace-design.md`

- [x] **Step 1: 9절에 세 번째 묶음을 이어 적는다**

화면 10개(부품 PR 둘 포함) · **깨진 테스트 83개** · 테스트 941 → 985개.
`AppInputV2`를 따로 만든 판단은 **옳았지만 값을 치렀다** — 부품 PR을 기기에서
보지 않고 넘어가 결함 둘을 다음 PR에 넘겼다.

- [x] **Step 2: 10절의 아이콘 목록을 갱신한다**

`alert`는 직접 그려 해결, 동그라미 체크는 `check_2`로 대체.
빈 네모·재생을 새로 찾아 더했다.

- [x] **Step 3: 11절에서 옮긴 화면을 지운다**

15개 → **9개.** `AppInputV2`가 관문이라는 판단은 맞았다(다섯 중 셋을 열었다).

- [x] **Step 4: 검증하고 PR**

⚠️ 13절에 **새 미결 다섯**을 더했다 — 시안 회색 글자의 대비 · `bgControl`
토큰 · 아이디 저장 줄 · 온보딩 사진 출처 · `RunColorOrb`.

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
