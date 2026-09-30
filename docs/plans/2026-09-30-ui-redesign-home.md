# UI 전면 교체 — 홈 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 홈 화면을 새 디자인으로 옮긴다. 시안이 상태 넷(기본·대기·완료·실패)을 따로 그려서, **상태 하나가 PR 하나**다.

**Architecture:** 앞 묶음들은 "화면 하나 = PR 하나"였는데 홈은 그게 안 된다 — 히어로 하나가 상태에 따라 완전히 다른 화면이 되고, 넷을 한 PR에 넣으면 1,000줄을 넘는다. **골격과 기본 상태를 먼저 세우고, 나머지 상태를 하나씩 얹는다.** 골격(상단 바·하단 2칸·프로필 안내)은 넷이 공유하므로 PR 1에서 끝낸다.

**Tech Stack:** Flutter (fvm) · flutter_test · flutter_svg · Figma MCP

**Spec:** `docs/specs/2026-09-25-ui-redesign-workspace-design.md` (9~12절에 실측과 관문)

**Figma:** 파일 `MpJxkA7fPj6MJs5uL07CVb`. 기본 `158:2848` · 대기 `158:2951` · 실패 `158:3029` · 완료 `158:3102`

## Global Constraints

- 모든 flutter/dart 명령은 `.\.fvm\flutter_sdk\bin\flutter.bat` / `dart.bat` 으로 직접 부른다.
- 모든 커밋 시점에 `analyze` 경고 **0개**, `test` **전체 통과**(현재 993개).
- 커밋 메시지 `<이모지> <Type>: <설명>`. **AI를 공동 작성자로 넣지 않는다.**
- base는 `dev`. 앞 PR이 머지된 뒤 `upstream/dev`에서 새로 딴다.
- **한 화면은 한 세대의 토큰만 쓴다.** `test/theme_generation_test.dart`가 강제한다.
- 옮긴 화면은 `core/theme/v2/`와 `core/widgets/v2/`만 import한다. Lucide 대신 `AppIcon`.
- `Color(0x...)` 하드코딩은 `core/theme/` 안에서만. 시안의 값이 토큰에 없으면 **토큰에 넣고** 쓴다.
- 우리에게 없는 값을 **지어내지 않는다.**
- 에뮬레이터는 `emulator-5556`. 확인 전에 `adb shell svc wifi disable`.

### 앞선 세 묶음에서 배운 것 — 매 PR에 적용한다

1. **그 상태의 시안을 먼저 읽는다.** 토큰과 코드만 대조하면 틀린다.
2. **두 번째로 쓰이는 순간 `core/widgets/v2/`로 올린다.**
3. **깨진 테스트를 그 PR 안에서 고친다.** 구조 결합은 `find.text`로, 잠김은 눌러 보는 것으로.
4. **고친 뒤 화면을 일부러 부순다.** ⚠️ 안 빨개지면 **부수기가 헛것이었는지 먼저 의심한다.**
5. **크기를 재지 말고 눌러 본다.** #102가 가짜 44px 터치 영역을 통과시켰다.
6. **⚠️ 부품만 만드는 PR도 임시 경로로 한 번 띄워 본다.** #102가 결함 둘을 다음 PR에 넘겼다.

---

## 이 묶음이 상대하는 것

**테스트 파일 3개 · 테스트 36개 · 구조 결합 13건.**

| 테스트 파일 | 테스트 | 결합 |
|---|---|---|
| `home_hero_test` | 17 | 3 |
| `home_page_test` | 12 | **10** |
| `home_started_run_test` | 7 | 0 |

인증·온보딩 묶음(125개 / 77건)의 **3분의 1이 안 된다.** 다만 홈은 **상태가 다섯**이라 깨지는 자리가 흩어져 있다.

---

## ⚠️ 시작 전에 알아야 할 것 다섯

### 1. 시안의 상태 넷은 우리 상태 다섯과 1:1이 아니다

| 시안 | 우리 코드(`home_hero.dart`) | |
|---|---|---|
| 기본 `158:2848` | `_Idle` | ✅ |
| 매칭 대기 중 `158:2951` | `_Waiting` (`RoomStatus.matching`) | ✅ |
| 매칭 완료 `158:3102` | `_Confirmed` (`RoomStatus.matched`) | ✅ |
| 매칭실패 `158:3029` | **없다** | ⚠️ 5절 |
| — | `_Pending` (스냅샷 대기) | 시안에 없다 |
| — | `_Started` (`RoomStatus.started`) | 시안에 없다 |

⚠️ **시안에 없다고 `_Pending`·`_Started`를 지우지 않는다.** 둘 다 **실제 사고를 막으려고 생긴 것**이고 코드에 그 이유가 적혀 있다.

- `_Started` — 예약 시각이 지나 서버가 러닝을 시작했는데 사용자가 홈에 있으면, 이걸 비운 순간 홈이 "지금 매칭하기"가 되고 **그사이 거리가 통째로 빠진다.**
- `_Pending` — 상태는 매칭 중인데 스냅샷이 아직 안 온 구간. 비우면 신청한 사람이 기본 히어로를 보고 **다시 누른다.**

시안은 행복 경로만 그린다. **시안에 없는 상태는 기본 상태의 토큰을 따라 만든다.**

### 2. 시안 상단에 `서울 강남구 · 맑음 18°`가 있다 — 우리에게 없는 데이터

상태 넷 **전부**에 있다. 위치는 러닝용 GPS 권한으로 얻을 수 있지만 **날씨는 외부 API가 필요하다.**

→ **이 묶음에서는 넣지 않는다.** 새 패키지·새 외부 의존은 따로 승인받는다(CLAUDE.md). PR 1에 그렇게 적고 묻는다.

### 3. 알림 벨도 갈 곳이 없다

시안 우상단에 벨이 있는데 **알림 화면이 시안 26개에 없다.** 닿을 데 없는 버튼을 두지 않는다.

→ **이 묶음에서는 넣지 않는다.** 기록카드 탭처럼 `ComingSoonPage`로 보낼지는 알림 기능을 정할 때 함께 정한다.

### 4. ⚠️ 시안 홈에 `최근 러닝`과 `다가오는 대회`가 없다

지금 홈에 있는 두 섹션이다. 시안에는 히어로 아래가 **프로필 안내 카드 + 하단 2칸**뿐이다.

→ **뺀다.** 대회일정 탭을 뺀 결정(#106)과 같은 방향이고, 그 결정의 근거였던 "새 홈에 대회 카드가 없다"가 바로 이것이다.

⚠️ **그러면 홈에서 `EmptyStateCard`가 사라진다.** 지금 이 부품을 쓰는 곳은 홈의 두 자리와 프로필뿐이라, **스펙 11절의 "`EmptyStateCard`가 홈·프로필 2개를 묶는다"는 전제가 무너진다.** Task 5에서 스펙을 고친다.

### 5. ⚠️ 매칭실패를 서버가 어떤 값으로 주는지 모른다

`RoomStatus`는 `matching` `matched` `started` `finished` `cancelled` 다섯이고, `cancelled`의 뜻은 **"참가자가 모두 빠졌다"**로 적혀 있다. 시안의 매칭실패는 **"모집 마감까지 조건에 맞는 러너를 못 찾았다"**로, 같은 것인지 알 수 없다.

→ **Task 4를 시작하기 전에 백엔드에 확인한다.** 답이 오기 전에는 Task 1~3만 간다. 지어내서 만들면 서버가 다른 값을 줄 때 화면이 영영 안 뜬다.

---

## Task 1: 골격과 기본 상태

시안 `158:2848` → `home_page.dart` · `home_hero.dart`의 `_Idle`

넷이 공유하는 바깥(프로필 안내 카드 · 하단 2칸)을 여기서 끝낸다. 상태별 PR이 히어로 안쪽만 건드리게 된다.

**Files:**
- Modify: `lib/features/home/presentation/home_page.dart`
- Modify: `lib/features/home/presentation/home_hero.dart` (`_Idle`만)
- Create: `lib/core/widgets/v2/action_tile.dart` — 하단 2칸(아이콘 + 라벨)
- Modify: `lib/core/strings/app_strings.dart`
- Test: `test/home_page_test.dart` · `test/home_hero_test.dart`

**Interfaces:**
- Produces: `ActionTileV2({required String icon, required String label, required VoidCallback onTap})` — 프로필·기록이 나중에 같은 모양을 쓴다

- [ ] **Step 1: `upstream/dev`에서 딴다**

```bash
git fetch upstream
git checkout -b style/home-idle-redesign upstream/dev
```

- [ ] **Step 2: 시안을 읽는다** (`158:2848`)

`get_design_context`로 히어로 카드의 반경·여백·빛 그러데이션 값을 받는다. **아이콘은 먼저 `assets/icons/`와 대조한다** — #106에서 탭 아이콘 넷이 바이트까지 같았다.

- [ ] **Step 3: `ActionTileV2`를 만든다**

하단 `혼자연습하기` · `친구랑 뛰기` 두 칸. 아이콘 타일 + 라벨이 가로로 붙는다.

```dart
class ActionTileV2 extends StatelessWidget {
  const ActionTileV2({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });
  final String icon;
  final String label;
  final VoidCallback onTap;
}
```

- [ ] **Step 4: 부품 테스트를 쓴다**

`test/v2_action_tile_test.dart`. **크기를 재지 말고 눌러 본다**(배운 것 5번).

```dart
testWidgets('아이콘 밖 · 칸 안을 눌러도 눌린다', (tester) async {
  var tapped = 0;
  await pump(tester, onTap: () => tapped++);
  final tile = tester.getRect(find.byType(ActionTileV2));
  await tester.tapAt(Offset(tile.right - 8, tile.center.dy));
  expect(tapped, 1);
});
```

- [ ] **Step 5: `_Idle`을 옮긴다**

제목·부제·`매칭시작` 버튼. **쿨다운 잠김 로직은 건드리지 않는다** — 지금 값이 맞다.

- [ ] **Step 6: `home_page.dart`에서 두 섹션을 뺀다**

`최근 러닝`·`다가오는 대회`와 그 `EmptyStateCard` 둘, `_SectionLabel`, 관련 `AppStrings`를 지운다. 자리에 `ActionTileV2` 둘과 프로필 안내 카드를 넣는다.

- [ ] **Step 7: 깨진 테스트를 고친다**

`home_page_test`가 두 섹션을 보고 있다. **지운 기능의 단정은 지우고, 남은 것은 `find.text`로 옮긴다.**

- [ ] **Step 8: 일부러 부순다**

`매칭시작` 버튼을 잠가 본다. ⚠️ 안 빨개지면 **부수기가 헛것이었는지 먼저 의심한다.**

- [ ] **Step 9: 검증**

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat analyze
.\.fvm\flutter_sdk\bin\flutter.bat test
```

- [ ] **Step 10: 에뮬레이터에서 본다**

로그인 상태가 아니면 `app_router.dart`의 `initialLocation`을 `AppRoutes.home`으로 **잠깐** 바꿔 들어간다. **확인 뒤 반드시 되돌린다.**

- [ ] **Step 11: 커밋하고 PR**

**💬 리뷰 포인트에 반드시 적을 것:**
- ⚠️ **`친구랑 뛰기`를 시안 문구 그대로 뒀다.** CLAUDE.md의 `"친구"라는 말은 쓰지 않는다 (요청→수락 모델)`와 정면으로 어긋난다. **기획 확인이 필요하다** — 프로필 시안의 `팔로워/팔로우`와 한 덩어리 결정이다.
- **`최근 러닝`·`다가오는 대회`를 뺐다.** 시안에 없다. 기능을 지운 것이라 확인이 필요하다.
- **위치·날씨와 알림 벨을 안 넣었다.** 2·3절의 이유.

---

## Task 2: 매칭 완료 상태

시안 `158:3102` → `home_hero.dart`의 `_Confirmed`

**Files:**
- Modify: `lib/features/home/presentation/home_hero.dart` (`_Confirmed` · `_Avatars`)
- Create: `lib/core/widgets/v2/fact_row.dart` — 3칸(시작 시간 · 목표거리 · 시작까지)
- Test: `test/home_hero_test.dart`

**Interfaces:**
- Consumes: Task 1이 확정한 히어로 카드의 면·반경
- Produces: `FactRowV2` — Task 3(실패)이 같은 3칸을 쓴다

- [ ] **Step 1: 앞 PR 머지 후 `upstream/dev`에서 딴다**

- [ ] **Step 2: 시안을 읽는다** (`158:3102`)

⚠️ **파란 면이다.** 기본·대기·실패는 어두운데 완료만 `primary` 계열 배경을 쓴다. 그 위의 글자는 `textOnPrimary`다.

- [ ] **Step 3: `FactRowV2`를 만든다**

```dart
class FactRowV2 extends StatelessWidget {
  const FactRowV2({required this.facts, super.key});
  final List<({String label, String value})> facts;
}
```

⚠️ **값에 `FontFeature.tabularFigures()`를 준다.** `시작까지 01:19:00`이 초마다 바뀌어서, 안 주면 자릿수가 흔들린다(CLAUDE.md).

- [ ] **Step 4: 부품 테스트**

`test/v2_fact_row_test.dart` — 세 칸이 균등하게 나뉘는가, 숫자가 tabular인가.

- [ ] **Step 5: `_Confirmed`를 옮긴다**

참여자 아바타 3명 + 이름. 기존 `_Avatars`를 v2 토큰으로 옮긴다.

⚠️ **순위를 붙이지 않는다**(CLAUDE.md). 시안도 이름만 있고 등수가 없다.

- [ ] **Step 6: 깨진 테스트를 고치고 일부러 부순다**

`로비이동`을 안 부르게 만들어 본다.

- [ ] **Step 7: 검증하고 에뮬레이터에서 본다**

⚠️ **매칭이 확정돼야 보이는 상태다.** 실제로 만들기 어려우면 임시 경로 + 가짜 `RoomInfo`로 띄운다. 어떻게 봤는지 PR에 적는다.

- [ ] **Step 8: 커밋하고 PR**

---

## Task 3: 매칭 대기 상태

시안 `158:2951` → `home_hero.dart`의 `_Waiting`

**이 묶음에서 제일 큰 작업이다.** 동심원 링 + 중앙에 본인 사진 + 파티원 아바타가 궤도에 앉는다.

**Files:**
- Modify: `lib/features/home/presentation/home_hero.dart` (`_Waiting`)
- Create: `lib/features/home/presentation/waiting_orbit.dart` — 동심원과 궤도
- Test: `test/home_hero_test.dart`

- [ ] **Step 1: 앞 PR 머지 후 `upstream/dev`에서 딴다**

- [ ] **Step 2: 시안을 읽는다** (`158:2951`)

동심원이 몇 겹인지, 반지름과 선 색, 아바타가 어느 각도에 앉는지를 잰다.

- [ ] **Step 3: 궤도를 만든다**

⚠️ **아바타 수가 3명으로 고정이 아니다.** 시안은 3명을 그리지만 방 인원은 달라진다. **각도를 하드코딩하지 말고 인원으로 나눈다.**

```dart
/// 인원이 몇이든 고르게 앉힌다. 시안의 3명은 예시일 뿐이다.
double _angleOf(int index, int total) => -math.pi / 2 + 2 * math.pi * index / total;
```

- [ ] **Step 4: 사람이 없을 때를 정한다**

⚠️ **모집 직후에는 나뿐이다.** 중앙만 있고 궤도가 비는 상태를 **시안이 안 그렸다.** 궤도 없이 중앙만 두고, 아래 문구가 인원을 말한다.

- [ ] **Step 5: 테스트를 쓴다**

```dart
testWidgets('⚠️ 인원이 셋이 아니어도 고르게 앉는다', ...);
testWidgets('⚠️ 나뿐이면 궤도가 비어도 죽지 않는다', ...);
```

- [ ] **Step 6: 깨진 테스트를 고치고 일부러 부순다**

- [ ] **Step 7: 검증하고 에뮬레이터에서 본다**

- [ ] **Step 8: 커밋하고 PR**

**💬 리뷰 포인트:** 중앙의 본인 사진이 없을 때(프로필 사진 미등록) 무엇을 그리는지 적는다.

---

## Task 4: 매칭 실패 상태

시안 `158:3029` → `home_hero.dart`

> ⚠️ **먼저 5절의 확인이 끝나야 한다.** 서버가 매칭 실패를 어떤 값으로 주는지 모른 채로 만들면 화면이 영영 안 뜬다.

**Files:**
- Modify: `lib/features/matching/domain/room_info.dart` (서버 값에 따라)
- Modify: `lib/features/home/presentation/home_hero.dart`
- Test: `test/home_hero_test.dart`

- [ ] **Step 1: 백엔드에 확인한다**

매칭이 마감까지 안 찼을 때 방 상태가 무엇인가. `cancelled`인가 다른 값인가. **`dev-issue-report` 스킬로 문서를 써서 올린다.**

- [ ] **Step 2: 답을 받은 뒤 `upstream/dev`에서 딴다**

- [ ] **Step 3: 시안을 읽는다** (`158:3029`)

`대안 매칭하기`와 `매칭 재등록` 두 버튼이 무엇을 하는지 정한다. ⚠️ **`대안 매칭하기`가 무슨 동작인지 시안만으로는 모른다** — 다른 시간대를 제안하는 것인지, 조건을 넓히는 것인지. 기획 확인이 필요하다.

- [ ] **Step 4: 상태를 더하고 화면을 만든다**

`FactRowV2`(Task 2)를 그대로 쓴다.

- [ ] **Step 5: 테스트 · 부수기 · 검증 · 에뮬레이터**

- [ ] **Step 6: 커밋하고 PR**

---

## Task 5: 잰 것을 적는다

**Files:**
- Modify: `docs/specs/2026-09-25-ui-redesign-workspace-design.md`

- [ ] **Step 1: 9절에 네 번째 묶음을 이어 적는다**

```markdown
### 네 번째 묶음 — 홈 (2026-XX-XX~)

| 상태 | 시안 | 테스트 | 깨진 수 | 새로 만든 부품 |
|---|---|---|---|---|
...
**상대한 것:** 테스트 36개 · 구조 결합 13건.
**실제로 깨진 것:** [합계]

상태 하나를 PR 하나로 가른 판단은 [옳았다/틀렸다] — [근거]
```

- [ ] **Step 2: ⚠️ 11절의 `EmptyStateCard` 줄을 고친다**

홈에서 뺐으므로 **프로필 하나만 남는다.** "2개 화면을 묶는다"가 더 이상 사실이 아니다.

- [ ] **Step 3: 12절의 다음 묶음을 다시 쓴다**

- [ ] **Step 4: 검증하고 PR**

---

## 이 계획이 다루지 않는 것

**프로필.** 시안(`158:3905` `158:4143`)이 다시 그린 화면이 아니라 **다른 화면**이다.

| 시안이 요구 | 우리에게 | 성격 |
|---|---|---|
| **팔로워 24 · 팔로우 32** | `friendCount` 하나 | ⚠️ **제품 모델 변경.** 양방향(요청→수락) → 단방향 팔로우 |
| 뱃지도감 `1/10` | 없음 | 백엔드 데이터 없음 |
| 커버 사진 | 없음 | 백엔드 데이터 없음 |
| 인증 뱃지(파란 체크) | 없음 | 뜻을 모름 |

그리고 지금 프로필의 **블렌드 컬렉션 · 피드** 섹션이 시안에 없다.

→ **팔로우 모델 결정 전에는 손대지 않는다.** 틀리면 `profile_page_test` 25개를 포함해 통째로 버려진다. 홈의 `친구랑 뛰기`와 **같은 하나의 결정**이라, Task 1의 PR에서 함께 묻는다.

같이 미루는 것:

- **알림 화면** — 시안에 없다. 벨의 목적지가 정해지면 판단한다
- **위치·날씨** — 외부 API가 필요하다. 새 의존은 따로 승인받는다
- **마무리 정리**(스펙 7절) — 마지막 화면 뒤 `v2/`를 본래 자리로 올린다
