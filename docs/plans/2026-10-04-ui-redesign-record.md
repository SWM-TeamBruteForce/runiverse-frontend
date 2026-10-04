# UI 전면 교체 — 기록·설정 계획 ✅ **끝남 (2026-10-04)**

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 기록 탭과 그 상세, 그리고 설정 화면을 새 디자인으로 옮긴다.

**Architecture:** 화면 하나가 PR 하나다. **설정을 먼저** 간다 — 셋 중 유일하게 위젯 테스트가 있고 제일 작아서, 그물 없는 둘에 들어가기 전에 흐름을 확인할 수 있다.

> ## ⚠️ 선행 조건 — `docs/plans/2026-10-04-record-api-contract.md`
>
> **기록 목록 API 가 이미 바뀌어 배포됐는데 앱이 옛 형식을 읽는다.** 그것을
> 맞추기 전에는 기록 탭이 **데이터를 못 읽어서 새 디자인을 눈으로 확인할 수
> 없다.** Task 2~5(기록·기록상세)는 그 계획이 끝난 뒤에 간다.
>
> 설정(Task 1)은 기록과 무관하므로 먼저 가도 된다.

**Tech Stack:** Flutter (fvm) · flutter_test · flutter_svg · Figma MCP

**Spec:** `docs/specs/2026-09-25-ui-redesign-workspace-design.md` (9~12절에 실측과 관문)

**Figma:** 기록 `158:3793`. ⚠️ **기록상세와 설정은 시안이 없다.**

## Global Constraints

- 모든 flutter/dart 명령은 `.\.fvm\flutter_sdk\bin\flutter.bat` / `dart.bat` 으로 직접 부른다.
- 모든 커밋 시점에 `analyze` 경고 **0개**, `test` **전체 통과**(현재 1,022개).
- 커밋 메시지 `<이모지> <Type>: <설명>`. **AI를 공동 작성자로 넣지 않는다.**
- base는 `dev`. 앞 PR이 머지된 뒤 `upstream/dev`에서 새로 딴다.
- **한 파일은 한 세대의 토큰만 쓴다.** `test/theme_generation_test.dart`가 강제한다.
- 옮긴 화면은 `core/theme/v2/`와 `core/widgets/v2/`만 import한다. Lucide 대신 `AppIcon`.
- `Color(0x...)` 하드코딩은 `core/theme/` 안에서만.
- 우리에게 없는 값을 **지어내지 않는다.**
- 에뮬레이터는 `emulator-5556`. 확인 전에 `adb shell svc wifi disable`.
- ⚠️ **확인이 끝나면 임시 경로를 반드시 되돌리고 깨끗한 빌드를 다시 설치한다.** 이 묶음 전에 두 번 빠뜨려 사용자가 탐침 빌드를 진짜 화면으로 착각했다.

### 앞선 네 묶음에서 배운 것 — 매 PR에 적용한다

1. **그 화면의 시안을 먼저 읽는다.** 토큰과 코드만 대조하면 틀린다.
2. **두 번째로 쓰이는 순간 `core/widgets/v2/`로 올린다.**
3. **깨진 테스트를 그 PR 안에서 고친다.**
4. **고친 뒤 화면을 일부러 부순다.** ⚠️ 안 빨개지면 **부수기가 헛것이었는지 먼저 의심하고, 부순 자리를 눈으로 확인한다**(`dart format`이 들여쓰기를 바꿔 치환이 안 먹은 적이 있다).
5. **크기를 재지 말고, 글자를 보지 말고 — 눌러 본다.**
6. **부품만 만드는 PR도 임시 경로로 한 번 띄워 본다.**
7. **시안은 화면의 정본이지 상태의 정본이 아니다.** 상태는 서버가 쥔다.
8. **배경을 눈으로 "비슷하다" 하고 넘기지 않는다.** 글자 없는 자리를 골라 수치로 맞춘다.

---

## 이 묶음이 상대하는 것

**⚠️ 세 화면 중 둘에 위젯 테스트가 하나도 없다.**

| 화면 | 줄 수 | 위젯 테스트 | 구조 결합 | 시안 |
|---|---|---|---|---|
| 설정 | `settings_page` | **9개** | 1 | ❌ 없다 |
| 기록 | `record_page` + `calendar` + `day_list` + `week_chart` = **854줄** | **0개** | — | ✅ `158:3793` |
| 기록상세 | `record_detail_page` + `run_result_view` + `split_line_chart` = **1,601줄** | **0개** | — | ❌ 없다 |

순수 로직 테스트는 따로 있다(`record_controller` 4 · `record_state` 5 · `record_summary` 10 · `settings_controller` 8). **그것들은 화면을 안 본다.**

→ 두 번째 묶음에서 같은 일이 있었고 스펙 9절이 **"그물 없이 옮긴 셈"**이라고 적었다. 이번에는 **옮기기 전에 그물부터 친다**(Task 2·4 Step 1).

---

## ⚠️ 시작 전에 알아야 할 것 넷

### 1. 기록 시안이 지금 화면과 **구성이 다르다**

| 시안 `158:3793` | 지금 |
|---|---|
| 상단 3칸 — 주간 누적 거리 · 누적 시간 · **누적 경사** | 없다 |
| 주간 기록 — **면적 그래프** + 요일 축 + 값 툴팁 | `record_week_chart` — **막대** |
| 기록 캘린더 — **가로 주간 스트립** | `record_calendar` — 월 달력 |
| 날짜별 목록 — 뱃지 획득 + 러닝 요약 | `record_day_list` — 러닝만 |
| `상세일정 더보기` | 없다 |

**부품 넷 중 셋을 다시 만든다.** 토큰 교체가 아니다.

### 2. 시안이 요구하는 값 중 둘이 ⚠️ 주의가 필요하다

| 시안 | 우리에게 | |
|---|---|---|
| 누적 경사 `312 m` | `totalElevationGainMeters` | ✅ **목록 응답에 있다**(없으면 `null`) |
| 주간 차트 툴팁 `173 spm` | **없다** | ⚠️ 목록 응답에 케이던스가 없다 |
| 날짜별 목록의 **뱃지 획득** | **없다** | ⚠️ **백엔드에 뱃지 기능이 아직 없다** |

→ **둘 다 빼고 만든다.** 연동 가이드가 둘을 명시했다 — 케이던스는 상세
(`averageCadenceSpm`)에만 있고, 뱃지는 "백엔드에 기능이 아직 없다"고 못 박았다.

⚠️ **누적 경사는 확정값처럼 그리지 않는다.** 기록 중 하나라도 `null` 이면
합계가 **실제보다 작다**(가이드 3-2). 상단 3칸에서 그것이 드러나야 한다.

### 3. ⚠️ 기록상세는 **시안이 없고 1,601줄이다**

`run_result_view.dart`(848) + `split_line_chart.dart`(593)가 거의 전부다. 시안이 없으므로 **토큰만 갈아끼운다** — 레이아웃을 건드리지 않는다.

`split_line_chart`는 `CustomPainter`라 색을 토큰에서 받는 지점만 바꾸면 된다. **곡선 계산에는 손대지 않는다.**

### 4. 설정도 시안이 없다

`LegalDocument`를 v2로 올려야 한다(11절). 약관 동의 화면을 옮길 때 만든 것이 있는지 먼저 확인한다 — 없으면 이 PR에서 만든다.

---

## Task 1: 설정

시안 없음 → **토큰 교체.** 셋 중 유일하게 그물이 있어 먼저 간다.

**Files:**
- Modify: `lib/features/settings/presentation/settings_page.dart`
- Create: `lib/core/widgets/v2/legal_document.dart` (기존 것이 없다면)
- Test: `test/settings_page_test.dart`

- [x] **Step 1: `upstream/dev`에서 딴다**

```bash
git fetch upstream
git checkout -b style/settings-redesign upstream/dev
```

- [x] **Step 2: `LegalDocumentV2`가 이미 있는지 본다**

```bash
grep -rn "LegalDocument" lib/
```

약관 동의 화면(#95)을 옮길 때 만들었을 수 있다. 있으면 그대로 쓰고, 없으면 만든다.

- [x] **Step 3: 토큰을 v2로 바꾼다**

`context.appColors` → `appColorsV2`, `AppTypography.x` → `AppTypographyV2.yy`,
`AppButton` → `AppButtonV2`, Lucide → `AppIcon`.

⚠️ **한 파일 안에서 전부 바꾼다.** 반만 바꾸면 `theme_generation_test`가 막는다.

- [x] **Step 4: 깨진 테스트를 고친다** (9개 중 구조 결합 1건)

- [x] **Step 5: 일부러 부순다**

로그아웃 버튼을 눌러도 아무 일이 없게 만들어 본다. ⚠️ 안 빨개지면 **부순 자리를 눈으로 확인한다.**

- [x] **Step 6: 검증하고 에뮬레이터에서 본다**

설정은 프로필 탭 → 톱니바퀴로 들어간다. 로그인이 필요하면 임시 경로를 쓴다.

- [x] **Step 7: 커밋하고 PR, 머지 뒤 탐침 되돌린 빌드를 다시 설치**

---

## Task 2: 기록 — 그물부터

⚠️ **옮기기 전에 테스트를 쓴다.** 854줄에 위젯 테스트가 0개다.

**Files:**
- Create: `test/record_page_test.dart`

**Interfaces:**
- Consumes: `recordControllerProvider` · `runRecordRepositoryProvider`(`FakeRunRecordRepository`가 이미 있다)

- [x] **Step 1: `upstream/dev`에서 딴다**

- [x] **Step 2: 지금 화면이 지키는 것을 찾아 적는다**

코드 주석이 근거다. 적어도 이 넷:

```dart
testWidgets('⚠️ 안 뛴 날에 막대가 서지 않는다', ...);   // "잔디가 아니다"
testWidgets('loading · data · error 셋을 다 그린다', ...);
testWidgets('기록이 없으면 빈 상태를 보여준다', ...);
testWidgets('날짜를 고르면 그날 목록이 바뀐다', ...);
```

- [x] **Step 3: 일부러 부숴 그물을 확인한다**

**넷을 하나씩** 부수고 각각 빨개지는지 본다. ⚠️ 여기서 헛도는 단정을 걸러내지 못하면 Task 3이 그물 없이 가는 것과 같다.

- [x] **Step 4: 커밋하고 PR**

**코드 변경 없음 · 테스트만.** 리뷰가 "무엇을 지키기로 했는가"를 먼저 보게 된다.

---

## Task 3: 기록

시안 `158:3793` → `record_page` · `record_week_chart` · `record_calendar` · `record_day_list`

**Files:**
- Modify: 위 넷
- Create: `lib/core/widgets/v2/stat_row.dart` — 상단 3칸(라벨 + 값)
- Test: `test/record_page_test.dart`(Task 2가 만든 것)

**Interfaces:**
- Consumes: Task 2의 그물
- Produces: `StatRowV2` — 프로필의 `컬러 1/30 · 뱃지 1/10` 줄이 나중에 쓸 수 있다

- [x] **Step 1: 앞 PR 머지 후 `upstream/dev`에서 딴다**

- [x] **Step 2: 시안을 읽는다** — ⚠️ **`get_design_context`까지 연다**

스크린샷만 보고 계획을 쓴 탓에 홈에서 전제가 둘 틀렸다(스펙 9절). 치수·색·불투명도를 받는다.

- [x] **Step 3: 상단 3칸을 만든다**

⚠️ `FactRowV2`와 **다른 것**이다 — 그쪽은 면이 깔린 패널이고 이쪽은 배경 없이 글자만 선다. 같은 부품으로 합치려 들지 않는다.

- [x] **Step 4: 주간 차트를 면적 그래프로 바꾼다**

⚠️ **"잔디가 아니다" 규칙은 그대로 지킨다**(`record_week_chart.dart:11`). 안 뛴 날을 결손으로 보이게 하지 않는다. 면적 그래프에서 0인 날을 어떻게 그릴지 **PR에 적고 디자인 확인을 받는다.**

⚠️ 시안의 `173 spm` 툴팁은 **빼고 만든다**(2절).

- [x] **Step 5: 캘린더를 가로 주간 스트립으로 바꾼다**

⚠️ **여기서 주 시작 요일이 저절로 통일된다.** 지금 월 달력
(`record_calendar.dart:148`)은 **일요일**, 주간 계산(`weekOf`)은 **월요일**로
한 탭에 둘이 섞여 있다. 월 달력이 사라지면 월요일만 남고, **시안의 주간 차트도
월요일 시작**이라 맞는다.

⚠️ 연동 가이드 4장은 **일요일을 권한다.** 근거가 "월 달력과 같은 기준"인데
그 달력이 사라지므로 전제가 바뀐다 — **PR 에 적어 확인받는다.**

- [x] **Step 6: 날짜별 목록을 옮긴다.** ⚠️ 뱃지 줄은 **빼고** 만든다(2절).

- [x] **Step 7: 깨진 테스트를 고치고 일부러 부순다**

- [x] **Step 8: 검증하고 에뮬레이터에서 본다**

⚠️ **데이터가 있어야 보인다.** 로그인해서 기록이 없으면 빈 상태만 확인된다 — `FakeRunRecordRepository`로 임시 override해서 데이터 상태도 본다. 어떻게 봤는지 PR에 적는다.

- [x] **Step 9: 커밋하고 PR**

---

## Task 4: 기록상세 — 그물부터

⚠️ **1,601줄에 위젯 테스트가 0개다.** 이 묶음에서 제일 큰 위험이다.

**Files:**
- Create: `test/record_detail_page_test.dart`

- [x] **Step 1: 앞 PR 머지 후 `upstream/dev`에서 딴다**

- [x] **Step 2: 지금 화면이 지키는 것을 찾아 적는다**

```dart
testWidgets('loading · data · error 셋을 다 그린다', ...);
testWidgets('⚠️ 파티원 GPS 를 그리지 않는다', ...);   // CLAUDE.md 금지
testWidgets('⚠️ 순위를 붙이지 않는다', ...);          // CLAUDE.md 금지
testWidgets('없는 값(케이던스·칼로리)을 0 으로 메우지 않는다', ...);
```

⚠️ **CLAUDE.md 금지 둘을 여기서 못 박는다.** 지금 지키고 있더라도, 토큰을 갈아끼우다 실수로 되살릴 수 있다.

- [x] **Step 3: 일부러 부숴 그물을 확인한다**
- [x] **Step 4: 커밋하고 PR** (테스트만)

---

## Task 5: 기록상세

시안 없음 → **토큰 교체만.** 레이아웃을 건드리지 않는다.

**Files:**
- Modify: `record_detail_page.dart` · `run_result_view.dart` · `split_line_chart.dart`

- [x] **Step 1: 앞 PR 머지 후 `upstream/dev`에서 딴다**

- [x] **Step 2: 세 파일의 토큰을 v2로 바꾼다**

⚠️ **`split_line_chart`는 `CustomPainter`다.** 색을 받는 지점만 바꾸고 **곡선 계산에는 손대지 않는다.**

⚠️ 세 파일이 서로를 import하므로 **한 PR에서 셋을 다 바꾼다.** 하나만 바꾸면 `theme_generation_test`가 막는다.

- [x] **Step 3: 깨진 테스트를 고치고 일부러 부순다**
- [x] **Step 4: 검증하고 에뮬레이터에서 본다** (기록 → 날짜 → 상세)
- [x] **Step 5: 커밋하고 PR**

⚠️ **파일 셋에 1,601줄이라 PR 한도(20파일 / 500줄)를 넘을 수 있다.** 넘으면 사유를 PR에 적는다(CLAUDE.md).

---

## Task 6: 잰 것을 적는다 ✅

- [x] 9절에 다섯 번째 묶음 — 깨진 것 **5개**, 테스트 1,022 → **1,070**
- [x] 8절에 **무엇이 정본인가** — 디자인 시스템 v1.1 은 교체 이전 것이다
- [x] 11절 8개 → **5개.** ⚠️ "부품이 화면을 묶는다"는 틀을 접었다
- [x] 12절 — **막는 것이 없는 화면이 하나도 안 남았다**

### ⚠️ 계획대로 안 간 것 둘

| 계획 | 실제 |
|---|---|
| 기록을 PR 하나로 | **셋으로 나눴다**(#119 · #120 · #121). 한 PR 에 900줄이 된다 |
| 기록 캘린더는 월 달력 유지 | 시안의 **가로 스트립**으로 바꾸고 월 달력을 **토글 뒤에** 뒀다 |

---

## 이 계획이 다루지 않는 것

**프로필.** 시안이 요구하는 **팔로워/팔로우**는 소셜 모델이 양방향(요청→수락)에서 단방향으로 바뀐 것이고, 홈의 `친구랑 뛰기`와 **같은 하나의 결정**이다. 결정 전에 손대면 `profile_page_test` 25개를 포함해 통째로 버려진다(스펙 12절).

같이 미루는 것:

- **러닝 준비** — GPS 조준 아이콘이 없다(스펙 10절)
- **실시간 기록** — 연결 끊김 아이콘이 없고 앱에서 가장 복잡하다
- **프로필 편집 · 비밀번호 변경** — 시안이 없고 휠 피커에 묶여 있다
- **시안에만 있는 화면 4개** — 친구 목록 · 친구초대 · 뱃지 획득 · 도감 상세
- **히어로 분기 정리** — `home_hero.dart`의 `if` 셋 + `switch`를 sealed union으로.
  지금 고장나 있지 않고, `_Pending`·`_Started`가 아직 v1이라 **그 둘을 옮길 때
  함께** 하는 것이 같은 파일을 두 번 안 연다
- **마무리 정리**(스펙 7절) — 마지막 화면 뒤 `v2/`를 본래 자리로 올린다
