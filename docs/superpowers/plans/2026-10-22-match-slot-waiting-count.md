# 매칭 슬롯 대기 인원 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 매칭 등록 화면이 슬롯 목록과 대기 인원을 `GET /api/v1/running-matches/slots`에서 받아, 거리를 먼저 고르고 시간을 고르게 한다.

**Architecture:** 목록의 주인이 앱(`MatchSlot.todayRange`)에서 서버로 넘어간다. 상태는 기존 `MatchRegisterController` 하나가 계속 쥐고, 조회 실패는 신청용 `MatchFailure`와 섞지 않고 별도 enum·별도 필드로 둔다. 화면은 거리 → 시간 순으로 뒤집히고, 거리만 고른 동안에만 합계 줄이 선다.

**Tech Stack:** Flutter · Riverpod 3 (`NotifierProvider`) · dio · `KstTime`

**Spec:** `docs/specs/2026-10-22-match-slot-waiting-count-design.md`

## Global Constraints

- 모든 flutter/dart 명령 앞에 `fvm` — 이 저장소에서는 `./.fvm/flutter_sdk/bin/flutter.bat`
- 작성 후 `fvm flutter analyze` 경고 **0개**
- `StateProvider` / `StateNotifierProvider` 금지 (Riverpod 3)
- 색·치수·타이포·문자열은 전부 토큰 (`context.appColorsV2` `AppSpacing` `AppTypographyV2` `AppStrings`)
- 아이콘은 Lucide만 (`AppIcons`)
- UI 텍스트는 한국어
- `GET` 쿼리: `targetDistanceMeters`는 **필수**, 3000·5000·10000 중 하나. `date`는 **보내지 않는다**
- 서버 시각은 오프셋이 없다 — **`KstTime.parse`로만 읽는다.** `DateTime.parse` 금지
- 등록 버튼 위 줄 문구: `현재 3km에 7명의 러너가 대기중이에요`
- 시트 줄 문구: `3명 대기` (`AppStrings.matchWaitingCount`, 지금 그대로)

## Review Focus

사양이 암시하지만 어느 task의 테스트도 건드리지 않는 입력·실패 — 각 줄의 테스트를 소유 task에 넣었다.

1. **같은 `raw`가 응답에 두 번 온다** — 서버가 같은 시각을 두 줄로 주면 합계가 두 배가 되고 시트에 같은 시각이 두 줄 선다. (Task 1)
2. **`waitingCount`가 음수이거나 `scheduledStartAt`이 못 읽는 문자열** — 한 줄이 깨졌다고 목록 전체를 버리면 화면이 통째로 멈춘다. (Task 1)
3. **거리를 고른 직후 화면을 떠난다** — 응답이 돌아올 때 `Notifier`가 이미 버려져 있다. (Task 3)
4. **전부 `selectable: false`인 응답** — 목록은 비지 않았지만 고를 것이 없다. 4-3의 "비었다"와 같은 화면이어야 한다. (Task 4)
5. **합계가 `int` 범위를 넘보는 큰 값** — 자릿수가 늘어도 줄이 깨지지 않는가. (Task 4, `tabularFigures`)

---

## File Structure

| 파일 | 책임 |
|---|---|
| `matching/domain/slot_load_failure.dart` | **신규.** 조회 실패 갈래 + 예외 |
| `matching/data/slot_dto.dart` | **신규.** 응답 한 줄 → `MatchSlot`, 목록 → `List<MatchSlot>` |
| `matching/domain/match_slot.dart` | `todayRange` 삭제, `waitingCount` 비널화 |
| `matching/domain/match_repository.dart` | `slots()` 추가 |
| `matching/data/http_match_repository.dart` | `slots()` 구현 + 조회 전용 에러 매핑 |
| `matching/data/fake_match_repository.dart` | `slots()` 구현, 주입 가능한 목록·실패 |
| `matching/presentation/match_register_provider.dart` | 상태 필드 셋 추가, `selectDistance`가 조회한다 |
| `matching/presentation/match_register_page.dart` | 거리↔시간 순서, 선택기 잠금, 합계 줄 |
| `core/strings/app_strings.dart` | 문구 넷 |

---

### Task 1: 응답을 읽는다 (DTO)

**Files:**
- Create: `lib/features/matching/data/slot_dto.dart`
- Modify: `lib/features/matching/domain/match_slot.dart`
- Test: `test/match_slot_dto_test.dart`

**Interfaces:**
- Produces: `List<MatchSlot> matchSlotsFromJson(Object? body)` — 응답 몸통(`{"slots": [...]}`)을 받아 목록을 준다. 못 읽는 줄은 **건너뛴다.**
- Produces: `MatchSlot`의 `waitingCount`가 `int?` → **`int`**
- Produces: `MatchSlot.todayRange` **삭제**

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `test/match_slot_dto_test.dart`

```dart
test('세 필드를 읽는다', () {
  final slots = matchSlotsFromJson({
    'slots': [
      {'scheduledStartAt': '2026-07-25T18:00:00', 'waitingCount': 0, 'selectable': false},
      {'scheduledStartAt': '2026-07-25T18:30:00', 'waitingCount': 3, 'selectable': true},
    ],
  });

  expect(slots, hasLength(2));
  expect(slots.first.raw, '2026-07-25T18:00:00');
  expect(slots.first.waitingCount, 0);
  expect(slots.first.selectable, isFalse);
  expect(slots[1].waitingCount, 3);
});

test('⚠️ 시각을 KST로 읽는다 — 기기 시간대와 무관하다', () {
  // `DateTime.parse`로 읽으면 UTC 기기에서 `matchSlotTime`이 +9h를 한 번 더
  // 해 18:00 슬롯이 03:00으로 뜬다(설계 8-5).
  final slot = matchSlotsFromJson({
    'slots': [
      {'scheduledStartAt': '2026-07-25T18:00:00', 'waitingCount': 1, 'selectable': true},
    ],
  }).single;

  expect(AppStrings.matchSlotTime(slot.startAt), '18:00');
});

test('⚠️ 못 읽는 줄은 건너뛰고 나머지를 준다', () {
  // 한 줄이 깨졌다고 목록을 통째로 버리면 화면이 멈춘다.
  final slots = matchSlotsFromJson({
    'slots': [
      {'scheduledStartAt': '어쩌구', 'waitingCount': 1, 'selectable': true},
      {'scheduledStartAt': '2026-07-25T18:30:00', 'waitingCount': 3, 'selectable': true},
      {'waitingCount': 2, 'selectable': true},
    ],
  });

  expect(slots, hasLength(1));
  expect(slots.single.raw, '2026-07-25T18:30:00');
});

test('⚠️ 같은 시각이 두 번 오면 한 번만 남긴다', () {
  // 그대로 두면 합계가 두 배가 되고 시트에 같은 시각이 두 줄 선다.
  final slots = matchSlotsFromJson({
    'slots': [
      {'scheduledStartAt': '2026-07-25T18:00:00', 'waitingCount': 3, 'selectable': true},
      {'scheduledStartAt': '2026-07-25T18:00:00', 'waitingCount': 5, 'selectable': true},
    ],
  });

  expect(slots, hasLength(1));
  expect(slots.single.waitingCount, 3, reason: '먼저 온 줄을 쓴다');
});

test('⚠️ 음수 대기 인원은 0으로 본다', () {
  final slots = matchSlotsFromJson({
    'slots': [
      {'scheduledStartAt': '2026-07-25T18:00:00', 'waitingCount': -1, 'selectable': true},
    ],
  });

  expect(slots.single.waitingCount, 0);
});

test('빈 목록도 실패가 아니다', () {
  expect(matchSlotsFromJson({'slots': <Object>[]}), isEmpty);
  expect(matchSlotsFromJson(null), isEmpty);
});
```

- [ ] **Step 2: 실패를 확인한다**

Run: `./.fvm/flutter_sdk/bin/flutter.bat test test/match_slot_dto_test.dart`
Expected: FAIL — `matchSlotsFromJson` 이 정의되지 않았다

- [ ] **Step 3: `matchSlotsFromJson(Object? body) -> List<MatchSlot>` 를 `slot_dto.dart`에 만든다**

`body['slots']`가 `List`가 아니면 빈 목록. 각 줄에서 `scheduledStartAt`을 `KstTime.parse`로 읽어
`null`이면 건너뛴다. `raw`는 **읽기 전 원본 문자열** 그대로. `waitingCount`는 `int`가 아니거나 음수면
`0`, `selectable`은 `bool`이 아니면 `false`. 이미 본 `raw`는 건너뛴다.

- [ ] **Step 4: `MatchSlot`에서 `todayRange`를 지우고 `waitingCount`를 `int`로 바꾼다**

`match_slot.dart`에서 `todayRange`·미사용이 된 `KstTime` import를 지운다. 클래스 상단 문서(5~11행)의
"앱이 만든 것이면"과 `waitingCount`의 "조회 API가 아직 없어서 … 전부 `null`이다"를 **서버가 준다**로
고친다. "0과 모름은 다르다" 설명은 **DTO로 옮긴다** — 모름을 만드는 주체가 거기뿐이다.

- [ ] **Step 5: 통과를 확인한다**

Run: `./.fvm/flutter_sdk/bin/flutter.bat test test/match_slot_dto_test.dart`
Expected: PASS 6/6

- [ ] **Step 6: `todayRange`에 매달린 테스트를 정리한다**

`test/match_repository_test.dart`에서

- 벽시계 테스트 여덟(`:169 :179 :188 :196 :201 :227 :240 :249` 부근)은 **지운다** — 앱이 시각을
  계산하지 않게 되어 지킬 대상이 없다
- ⚠️ **`:259`(잠근 사본)와 `:268-280`(raw 패스스루)은 지우지 않는다.** `todayRange` 대신 손으로
  만든 `MatchSlot`을 쓰도록 고친다

Run: `./.fvm/flutter_sdk/bin/flutter.bat test test/match_repository_test.dart`
Expected: PASS

- [ ] **Step 7: 커밋**

```bash
git add lib/features/matching/data/slot_dto.dart lib/features/matching/domain/match_slot.dart test/match_slot_dto_test.dart test/match_repository_test.dart
git commit -m "📍 Feat: 서버가 준 슬롯을 읽는다"
```

---

### Task 2: 저장소가 목록을 가져온다

**Files:**
- Create: `lib/features/matching/domain/slot_load_failure.dart`
- Modify: `lib/features/matching/domain/match_repository.dart`
- Modify: `lib/features/matching/data/http_match_repository.dart`
- Modify: `lib/features/matching/data/fake_match_repository.dart`
- Test: `test/match_slots_repository_test.dart`

**Interfaces:**
- Consumes: `matchSlotsFromJson` (Task 1)
- Produces: `enum SlotLoadFailure { network, sessionExpired, invalidRequest, unknown }` + `class SlotLoadException implements Exception { const SlotLoadException(this.failure); final SlotLoadFailure failure; }`
- Produces: `MatchRepository.slots({required TargetDistance distance}) -> Future<List<MatchSlot>>`
- Produces: `FakeMatchRepository`의 `List<MatchSlot> slotList` · `SlotLoadFailure? slotsFailure` · `int slotsCalls` · `TargetDistance? slotsDistance`

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `test/match_slots_repository_test.dart`

`_RecordingAdapter`는 `test/http_profile_image_repository_test.dart`의 것과 같은 모양으로 둔다.

```dart
test('16번은 거리를 쿼리로 보낸다', () async {
  final repo = await repository();
  api.jsonFor['/api/v1/running-matches/slots'] = {'slots': <Object>[]};

  await repo.slots(distance: TargetDistance.km5);

  expect(api.pathOf('GET'), '/api/v1/running-matches/slots');
  expect(api.queryOf('GET')?['targetDistanceMeters'], 5000);
});

test('⚠️ date는 보내지 않는다 — 오늘뿐이다', () async {
  final repo = await repository();
  api.jsonFor['/api/v1/running-matches/slots'] = {'slots': <Object>[]};

  await repo.slots(distance: TargetDistance.km3);

  expect(api.queryOf('GET')?.containsKey('date'), isFalse);
});

test('Authorization을 붙인다', () async {
  final repo = await repository();
  api.jsonFor['/api/v1/running-matches/slots'] = {'slots': <Object>[]};

  await repo.slots(distance: TargetDistance.km3);

  expect(api.headerOf('GET', 'Authorization'), 'Bearer a-1');
});

test('⚠️ 404를 "취소할 신청이 없다"로 읽지 않는다', () async {
  // 신청용 `exceptionOf`가 404를 `nothingToCancel`로 묶는다. 그대로 쓰면
  // 목록 조회 실패에 "취소할 활성 신청이 없어요"가 뜬다(설계 7-4).
  final repo = await repository(status: 404);

  await expectLater(
    repo.slots(distance: TargetDistance.km3),
    throwsA(isA<SlotLoadException>().having((e) => e.failure, 'failure', SlotLoadFailure.unknown)),
  );
});

test('401은 세션 만료다', () async {
  final repo = await repository(status: 401, refreshFails: true);

  await expectLater(
    repo.slots(distance: TargetDistance.km3),
    throwsA(isA<SlotLoadException>().having((e) => e.failure, 'failure', SlotLoadFailure.sessionExpired)),
  );
});

test('400은 invalidRequest다', () async {
  final repo = await repository(status: 400);

  await expectLater(
    repo.slots(distance: TargetDistance.km3),
    throwsA(isA<SlotLoadException>().having((e) => e.failure, 'failure', SlotLoadFailure.invalidRequest)),
  );
});
```

- [ ] **Step 2: 실패를 확인한다**

Run: `./.fvm/flutter_sdk/bin/flutter.bat test test/match_slots_repository_test.dart`
Expected: FAIL — `slots` 가 `MatchRepository`에 없다

- [ ] **Step 3: `SlotLoadFailure`·`SlotLoadException`을 만들고 인터페이스에 `slots()`를 더한다**

`MatchFailure`와 **합치지 않는다.** 신청·취소의 갈래(`slotClosed` `cooldown` `nothingToCancel` …)가
조회에는 하나도 해당되지 않는다.

- [ ] **Step 4: `HttpMatchRepository.slots()`를 구현한다**

`_authorized`로 감싸고 `GET '$_path/slots'`에 `queryParameters: {'targetDistanceMeters': distance.meters}`.
몸통은 `matchSlotsFromJson`에 넘긴다. 실패는 **`exceptionOf`를 쓰지 않고** 전용 매핑을 쓴다 —
`badResponse`가 아니면 `network`, 401이면 `sessionExpired`, `code == 'INVALID_REQUEST'`면
`invalidRequest`, 나머지는 `unknown`. `invalidRequest`는 **정상 경로에서 나오지 않으므로**
`debugPrint`로 한 줄 남긴다.

- [ ] **Step 5: `FakeMatchRepository.slots()`를 구현한다**

`slotList`·`slotsFailure`·`slotsCalls`·`slotsDistance`를 더한다.

⚠️ **기본 `slotList`에 18:00~22:00을 쓰지 않는다.** 운영값을 fake에 박으면 이번 작업이 없애려던
하드코딩이 테스트 쪽으로 옮겨갈 뿐이다. **`10:00` · `10:30` · `11:00` 세 칸**을 기본으로 두고,
셋 다 `selectable: true`, `waitingCount`는 `3` · `0` · `4`로 둔다 — 0이 섞여 있어야 "0이면 안
그린다"를 그냥 테스트할 수 있다.

- [ ] **Step 6: 통과를 확인한다**

Run: `./.fvm/flutter_sdk/bin/flutter.bat test test/match_slots_repository_test.dart`
Expected: PASS 6/6

- [ ] **Step 7: `FakeMatchRepository`를 쓰는 다른 테스트를 컴파일시킨다**

인터페이스가 늘었으므로 fake를 쓰는 파일들이 먼저 깨진다 — `analytics_events_test.dart` ·
`home_page_test.dart` · `home_started_run_test.dart` · `match_room_page_test.dart` ·
`match_room_test.dart` · `nickname_home_sync_test.dart`. fake가 구현을 들고 있으므로 **대부분 손댈
것이 없다.** 컴파일 오류가 나는 곳만 고친다.

Run: `./.fvm/flutter_sdk/bin/flutter.bat analyze`
Expected: No issues found!

- [ ] **Step 8: 커밋**

```bash
git add lib/features/matching test/match_slots_repository_test.dart
git commit -m "📍 Feat: 슬롯 목록을 서버에서 받는다"
```

---

### Task 3: 상태가 거리로 목록을 받는다

**Files:**
- Modify: `lib/features/matching/presentation/match_register_provider.dart`
- Test: `test/match_slots_state_test.dart`

**Interfaces:**
- Consumes: `MatchRepository.slots(...)` · `SlotLoadFailure` (Task 2)
- Produces: `MatchRegisterState`에 `bool loadingSlots` · `SlotLoadFailure? loadFailure` 추가
- Produces: `MatchRegisterState.slotsReady` — `!loadingSlots && loadFailure == null && slots.any((s) => s.selectable)`
- Produces: `MatchRegisterState.waitingTotal` — `slots.fold(0, (sum, s) => sum + s.waitingCount)`
- Produces: `MatchRegisterController.selectDistance(TargetDistance)`가 `Future<void>`가 된다
- Produces: `MatchRegisterController.loadSlots()` **삭제** (화면 진입 조회가 없어진다)
- Produces: `matchClockProvider` **삭제**

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `test/match_slots_state_test.dart`

```dart
test('거리를 고르면 그 거리로 한 번 부른다', () async {
  await container.read(matchRegisterProvider.notifier).selectDistance(TargetDistance.km5);

  expect(repo.slotsCalls, 1);
  expect(repo.slotsDistance, TargetDistance.km5);
  expect(container.read(matchRegisterProvider).slots, hasLength(3));
});

test('거리를 바꾸면 다시 부른다', () async { /* km3 → km10, slotsCalls == 2 */ });

test('⚠️ 같은 거리를 다시 눌러도 부른다 — 실패 복구 길이다', () async { /* km3 두 번, slotsCalls == 2 */ });

test('⚠️ 시간을 고르는 것으로는 부르지 않는다', () async {
  // 한 번의 응답에 그날의 모든 시각이 들어 있다.
});

test('⚠️ 늦게 온 앞 요청이 나중 거리의 답을 덮지 않는다', () async {
  // 칩은 10km인데 숫자는 3km가 되는 것을 막는다(설계 5절).
  // repo.latency를 두고 km3 → km10을 연달아 고른 뒤, 상태의 목록이 km10의 것인지 본다.
});

test('⚠️ 거리를 바꾸면 고른 시간이 새 목록의 같은 raw로 교체된다', () async {
  // 옛 객체를 그대로 두면 `waitingCount`가 옛 거리의 값으로 남는다(설계 6절).
  // km3에서 10:00(3명)을 고르고 km10(10:00이 9명)으로 바꾼 뒤:
  expect(container.read(matchRegisterProvider).selected!.waitingCount, 9);
});

test('새 목록에 없거나 잠긴 시간이면 선택이 풀린다', () async { /* selected == null */ });

test('⚠️ 조회가 실패하면 목록이 비고 이유가 남는다', () async {
  repo.slotsFailure = SlotLoadFailure.network;
  await container.read(matchRegisterProvider.notifier).selectDistance(TargetDistance.km3);

  final state = container.read(matchRegisterProvider);
  expect(state.slots, isEmpty);
  expect(state.loadFailure, SlotLoadFailure.network);
  // ⚠️ 신청용 실패와 섞이지 않는다 — 섞이면 스낵바가 띄우고 바로 지운다.
  expect(state.failure, isNull);
});

test('⚠️ 받는 중에는 slotsReady가 거짓이다', () async { /* latency 중 확인 */ });

test('⚠️ 전부 마감이면 slotsReady가 거짓이다', () async {
  // 목록은 비지 않았지만 고를 것이 없다. "비었다"와 같은 화면이어야 한다.
});

test('waitingTotal은 모든 시각을 더한다', () async {
  // 기본 fake 목록 3 + 0 + 4
  expect(container.read(matchRegisterProvider).waitingTotal, 7);
});

test('⚠️ 거리를 고른 직후 화면을 떠나도 죽지 않는다', () async {
  // 응답이 돌아올 때 Notifier가 이미 버려져 있다.
  final future = container.read(matchRegisterProvider.notifier).selectDistance(TargetDistance.km3);
  container.dispose();
  await future;  // throws 하지 않는다
});
```

- [ ] **Step 2: 실패를 확인한다**

Run: `./.fvm/flutter_sdk/bin/flutter.bat test test/match_slots_state_test.dart`
Expected: FAIL — `loadingSlots` 가 없다

- [ ] **Step 3: 상태와 `selectDistance`를 고친다**

`MatchRegisterState`에 필드 둘과 게터 둘을 더한다. `copyWith`는 `selected`를 `null`로 만들지 못하므로
(`:76`) 선택을 푸는 자리는 **생성자를 직접 쓴다** — 409 분기(`:172`)가 이미 그렇게 한다. 새 필드를
더하면 **그 두 자리가 조용히 초기화되므로** 둘 다 손댄다.

`selectDistance`는 상태를 `loadingSlots: true`로 세우고 저장소를 부른다. 응답이 오면 **`state.distance`가
여전히 그 거리인지 확인하고**, 아니면 버린다. 버려진 뒤라면(`ref.mounted`가 거짓) 아무것도 하지
않는다.

고른 시간은 새 목록에서 **같은 `raw`를 찾아 그 객체로 교체**한다. 없거나 `selectable`이 아니면 푼다.

- [ ] **Step 4: 409가 목록을 다시 받게 한다**

`submit()`의 `slotClosed` 분기(`:167-179`)가 지금은 그 슬롯만 잠근다. 주석이 이유를 *"목록을 다시
받아도 앱이 만든 것이면 같은 값이 온다"*로 적어 뒀는데, 그 전제가 깨졌다. **잠그고 나서 그 거리로
목록을 다시 받는다.** 주석도 고친다.

- [ ] **Step 5: `loadSlots`·`matchClockProvider`를 지운다**

`test/match_register_test.dart:50`의 `matchClockProvider.overrideWithValue`도 같이 지운다.

- [ ] **Step 6: 통과를 확인한다**

Run: `./.fvm/flutter_sdk/bin/flutter.bat test test/match_slots_state_test.dart`
Expected: PASS 12/12

- [ ] **Step 7: 커밋**

```bash
git add lib/features/matching/presentation/match_register_provider.dart test/
git commit -m "📍 Feat: 거리를 고르면 그 거리의 슬롯을 받는다"
```

---

### Task 4: 화면이 거리부터 묻는다

**Files:**
- Modify: `lib/features/matching/presentation/match_register_page.dart`
- Modify: `lib/core/strings/app_strings.dart`
- Test: `test/match_register_test.dart`

**Interfaces:**
- Consumes: `slotsReady` · `waitingTotal` · `loadingSlots` · `loadFailure` (Task 3)
- Produces: `AppStrings.matchSlotsLockedByDistance` = `'거리를 먼저 골라주세요'`
- Produces: `AppStrings.matchSlotsEmpty` = `'오늘은 신청할 수 있는 시간이 없어요'`
- Produces: `AppStrings.matchSlotsLoadFailed` = `'시간대를 불러오지 못했어요'`
- Produces: `AppStrings.matchSlotsRetry` = `'다시 시도'`
- Produces: `AppStrings.matchWaitingTotal(int km, int count)` = `'현재 ${km}km에 ${count}명의 러너가 대기중이에요'`
- 테스트 안에서 쓸 지역 헬퍼 둘을 먼저 만든다 — `MatchSlot slot(String hhmm, {int waiting = 0, bool selectable = true})`
  (오늘 날짜의 `raw`를 만들어 `MatchSlot`을 세운다)과 `Future<void> pickDistance(WidgetTester, TargetDistance)`

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `test/match_register_test.dart`에 추가

```dart
testWidgets('⚠️ 거리가 시간보다 위에 있다', (tester) async {
  await pumpRegister(tester);

  expect(
    tester.getTopLeft(find.text(AppStrings.matchDistanceLabel)).dy,
    lessThan(tester.getTopLeft(find.text(AppStrings.matchTimeLabel)).dy),
  );
});

testWidgets('⚠️ 거리를 고르기 전에는 시간을 못 고른다', (tester) async {
  await pumpRegister(tester);

  await tester.tap(find.text(AppStrings.matchTimePlaceholder));
  await tester.pumpAndSettle();

  // ⚠️ 시트 위젯(`_SlotSheet`)은 비공개다. 기존 테스트처럼 **제목으로** 찾는다.
  expect(find.text(AppStrings.matchSlotSheetTitle), findsNothing);
  expect(find.text(AppStrings.matchSlotsLockedByDistance), findsOneWidget);
});

testWidgets('거리를 고르면 시간을 고를 수 있다', (tester) async { /* 시트가 열린다 */ });

testWidgets('⚠️ 거리만 골랐을 때 합계가 등록 버튼 위에 선다', (tester) async {
  // 기본 fake 목록 3 + 0 + 4 = 7
  await pumpRegister(tester);
  await pickDistance(tester, TargetDistance.km3);

  final banner = find.text(AppStrings.matchWaitingTotal(3, 7));
  expect(banner, findsOneWidget);
  expect(
    tester.getTopLeft(banner).dy,
    lessThan(tester.getTopLeft(find.text(AppStrings.matchRegisterCta)).dy),
  );
});

testWidgets('⚠️ 시간까지 고르면 그 줄이 사라진다', (tester) async {
  // 시트에서 이미 보고 고른 값이라 한 번 더 적을 이유가 없다(설계 4-2).
  await pumpRegister(tester);
  await pickDistance(tester, TargetDistance.km3);
  await pickSlot(tester, '10:00');

  expect(find.textContaining('대기중이에요'), findsNothing);
});

testWidgets('⚠️ 합계가 0이면 그 줄이 아예 없다', (tester) async {
  repo.slotList = [slot('10:00', waiting: 0), slot('10:30', waiting: 0)];
  ...
  expect(find.textContaining('대기중이에요'), findsNothing);
});

testWidgets('시트는 시각마다 그 거리의 수를 그린다', (tester) async {
  // 0인 시각에는 숫자가 안 붙는다.
  expect(find.text(AppStrings.matchWaitingCount(3)), findsOneWidget);
  expect(find.text(AppStrings.matchWaitingCount(0)), findsNothing);
});

testWidgets('⚠️ 전부 마감이면 비었음과 같은 화면이다', (tester) async {
  repo.slotList = [slot('10:00', selectable: false)];
  ...
  expect(find.text(AppStrings.matchSlotsEmpty), findsOneWidget);
});

testWidgets('⚠️ 조회가 실패하면 이유가 머문다 — 스낵바로 사라지지 않는다', (tester) async {
  repo.slotsFailure = SlotLoadFailure.network;
  await pumpRegister(tester);
  await pickDistance(tester, TargetDistance.km3);
  await tester.pump(const Duration(seconds: 5));

  expect(find.text(AppStrings.matchSlotsLoadFailed), findsOneWidget);
  expect(find.text(AppStrings.matchSlotsRetry), findsOneWidget);
});

testWidgets('다시 시도를 누르면 또 부른다', (tester) async { /* slotsCalls == 2 */ });

testWidgets('⚠️ 합계 숫자가 자릿수대로 선다', (tester) async {
  // 실시간으로 갱신되지는 않지만, 거리를 바꾸며 자릿수가 흔들린다.
  final text = tester.widget<Text>(find.textContaining('대기중이에요'));
  expect(text.style?.fontFeatures, contains(const FontFeature.tabularFigures()));
});
```

- [ ] **Step 2: 실패를 확인한다**

Run: `./.fvm/flutter_sdk/bin/flutter.bat test test/match_register_test.dart`
Expected: FAIL — 순서·잠금·합계 줄이 전부 없다

- [ ] **Step 3: 문구 다섯을 `app_strings.dart`의 S08 구획에 더한다**

- [ ] **Step 4: 화면을 고친다**

`ListView`의 자식 순서를 **거리 블록 → 시간 블록**으로 바꾼다. `_SlotTrigger`의 `onTap`은
`state.slotsReady`가 참일 때만 준다. 트리거 아래에 상태별 한 줄을 둔다(설계 4-3의 다섯 칸).
`_WaitingBanner`를 `ListView` 밖 **고정 영역의 CTA 바로 위**로 옮기고, `state.distance != null &&
state.selected == null && state.waitingTotal > 0`일 때만 그린다. 문구는 `matchWaitingTotal`.

⚠️ **자리를 미리 잡지 않는다.** 늘 비워 두면 0명일 때 화면에 구멍이 남는다.

- [ ] **Step 5: 낡은 테스트를 고친다**

같은 파일에서 *시간 → 거리* 순으로 고르는 여덟 곳(`:126 :136 :195 :207 :222 :240 :255 :272` 부근)을
**거리부터** 고르도록 뒤집는다. `:114`(들어오면 시간대를 갖춘다)와 `:141`(벽시계 마감 판정)은 전제가
사라져 **지운다.** ⚠️ **`:159`(시트의 대기 인원)는 살린다** — 주입 방식만 fake 쪽으로 바꾼다.

- [ ] **Step 6: 통과를 확인한다**

Run: `./.fvm/flutter_sdk/bin/flutter.bat test test/match_register_test.dart`
Expected: PASS

- [ ] **Step 7: 전체와 analyze**

Run: `./.fvm/flutter_sdk/bin/flutter.bat analyze && ./.fvm/flutter_sdk/bin/flutter.bat test`
Expected: No issues found! · All tests passed!

- [ ] **Step 8: 커밋**

```bash
git add lib test
git commit -m "📍 Feat: 거리를 먼저 묻고 대기 인원을 보여준다"
```

---

### Task 5: 낡은 주석을 고친다

**Files:**
- Modify: `lib/features/matching/domain/match_slot.dart`
- Modify: `lib/features/matching/presentation/match_register_provider.dart`

- [ ] **Step 1: "14번 · MVP 범위 밖" 두 곳을 고친다**

`match_slot.dart:47` 부근과 `match_register_provider.dart:101` 부근이 이 API를 **14번**이라 부르고
*"대기 인원을 세는 것이 목적이라 MVP 범위 밖이다"*라고 적어 뒀다. 실제는 **No 16**이고 **개발완료**다.
`todayRange`가 사라지면서 두 주석이 붙어 있던 코드도 대부분 사라지므로, 남은 자리만 고친다.

`selectDistance`의 주석(*"대기 인원 조회가 들어오면 그때 거리별로 다시 받아야 한다"*)은 **그 일이
일어난 자리**가 되었으므로 현재형으로 고친다.

- [ ] **Step 2: `grep`으로 남은 것이 없는지 본다**

Run: `grep -rn "14번\|MVP 범위 밖" lib/features/matching/`
Expected: 출력 없음

- [ ] **Step 3: analyze와 전체 테스트**

Run: `./.fvm/flutter_sdk/bin/flutter.bat analyze && ./.fvm/flutter_sdk/bin/flutter.bat test`
Expected: No issues found! · All tests passed!

- [ ] **Step 4: 커밋**

```bash
git add lib/features/matching
git commit -m "📝 Docs: 슬롯 조회가 더 이상 MVP 범위 밖이 아니다"
```
