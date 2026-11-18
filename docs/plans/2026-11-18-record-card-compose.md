# 기록카드 작성 1 — 기록 고르기 · 유형 · 회고 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 기록카드 작성의 첫 화면을 세워, 그날 뛴 기록 하나에 유형과 회고를 붙인 **초안**을 만든다.

**Architecture:** 초안은 `cardDraftProvider` 하나가 들고 세 화면을 따라다닌다(수정 모드는 카드 번호별 family). 그날 고를 수 있는 기록은 **러닝 기록 조회와 기록카드 조회를 동시에 부른 뒤 `runningRecordId`로 맞춰** 카드 유무를 가린다 — 서버가 그 값을 실어 주지 않기 때문이다. 화면은 셸 밖 라우트(`/record-card/new`)이고, 탭에서 들어가는 입구를 셋 만든다.

**Tech Stack:** Flutter · Riverpod 3(수동 provider, 코드 생성 없음) · go_router · 기존 `showWheelPickerSheet` · `StatRowV2` · `RouteArtView`

**Spec:** `docs/specs/2026-11-16-record-card-design.md` (6-1 마지막 두 항 · **6-2** · 7절 "작성 중인 것의 수명" · 10절 질문 3)

## Global Constraints

- **UI 텍스트는 한국어.** 전부 `AppStrings`에. `"친구"라는 말은 쓰지 않는다`
- 색·치수·타이포는 토큰만 — `core/theme/tokens/` 밖에서 `Color(0x...)` 금지
- 아이콘은 **Lucide만**. `Icons.*` 혼용 금지
- `StateProvider` / `StateNotifierProvider` 금지 (Riverpod 3 레거시)
- 화면은 **loading / data / error 3분기를 반드시 처리**. empty 상태와 **다크·라이트 두 테마**를 함께 정의
- 러닝 수치에는 `FontFeature.tabularFigures()`
- `presentation → domain ← data`. presentation은 data를 import하지 않는다. `domain/`은 순수 Dart만
- 다른 feature의 **화면·위젯**은 import하지 않는다. **provider와 domain은 예외다**(CLAUDE.md)
- 모든 flutter/dart 명령은 `.fvm/flutter_sdk/bin/flutter.bat` (PowerShell에서 직접 부른다. `fvm`은 PATH에 없다)
- 한 커밋에 논리적 변경 하나. 커밋 메시지는 `📍 Feat:` `✅ Test:` 같은 이모지 type 접두사
- 회고는 **1000자**, 사진은 뒤 PR

## 이 계획이 설계와 다르게 가는 것 (Ruling)

실행자가 설계 문서와 어긋난다고 멈추지 않게 미리 적는다. 셋 다 **설계 문서를 이쪽으로 고치는 것**이 맞고, 사용자에게 보고한다.

1. **카드 유무를 서버에 묻지 않는다.** 설계 10절 질문 3이 "기록 목록 응답에 카드 유무를 실어 달라"인데 그 값은 아직 없다. **내 카드 목록을 그날치만 받아 `runningRecordId`로 맞춘다** — 왕복 하나가 늘지만 백엔드를 기다리지 않아도 되고, 조회가 그날로 좁혀져 비용이 작다.
2. **빈 날을 눌렀을 때 기록 유무를 미리 보지 않는다.** 설계 6-1은 "그날 러닝 기록이 있을 때만 작성으로 간다"지만, 그러려면 **칸을 누를 때마다 네트워크 왕복**이 생겨 탭이 멈춘 듯 보인다. 작성 화면으로 보내고, 그 화면이 6-2가 이미 정한 "이 날에는 러닝 기록이 없어요" 한 줄을 띄운다. 날짜를 그 자리에서 바꿀 수 있으므로 막히지 않는다.
3. **카드가 이미 있는 기록을 누르면 `수정`이 아니라 `상세`로 보낸다.** 수정 화면은 뒤 PR이다. 누를 수 있는데 아무 일도 안 일어나는 것을 또 만들지 않는다(1번 PR의 교훈). 수정 PR이 이 한 줄을 바꾼다.

## 이 계획이 다루지 않는 것

- **러닝 요약(S15)에서 들어오는 길.** 설계 6-2 첫 항("러닝 요약에서 왔으면 날짜와 기록이 골라져 있다")과 6-8절은 **6번 PR**이다. 이 계획의 화면은 날짜만 받으므로, 그때 `cardId` 자리와 같은 방식으로 기록을 꽂아 넣으면 된다.
- **`다음`이 가는 곳.** 사진 화면은 다음 묶음이다. 이 계획에서 `다음`은 켜지고 꺼지는 것까지만 만든다 — 그래서 **혼자 PR로 올리지 않는다**(아래 "끝낸 뒤").

## Review Focus

설계가 전제하지만 어느 작업의 테스트도 짚지 않는 것들. 각 줄의 테스트를 그 코드를 가진 작업에 넣어 두었다.

1. **회고 1000자를 넘겨 붙여넣기.** 잘라서 담고 글자 수를 보여 준다 — 조용히 통째로 담으면 저장에서 거절당하고 쓴 글을 잃는다 → Task 3
2. **그날 기록이 전부 카드를 가진 날.** 고를 것이 없어도 목록은 보이고 `다음`은 꺼진 채다 → Task 5
3. **기록 조회 실패(세션 만료·망).** 목록 자리에 오류와 다시 시도. 날짜 행과 유형·회고는 그대로 살아 있다 → Task 5
4. **미래 날짜.** 휠에서 오늘 이후를 고를 수 없다 — 뛰지 않은 날의 카드는 없다 → Task 5
5. **쓰던 초안이 있는데 다른 날짜로 또 들어옴.** 덮어쓰기 전에 확인을 받는다(설계 7절) → Task 6

---

## 파일 구조

| 파일 | 책임 |
|---|---|
| `lib/features/record_card/domain/card_draft.dart` | 초안 값 하나. 무엇이 차면 `다음`이 켜지나, 무엇이 차면 버릴 때 묻나 |
| `lib/features/record_card/domain/composable_record.dart` | 고를 수 있는 기록 한 줄 + 기록과 카드를 맞추는 순수 함수 |
| `lib/features/record_card/presentation/card_draft_provider.dart` | 초안을 들고 있는 family notifier (`null` = 새 카드) |
| `lib/features/record_card/presentation/compose_records_provider.dart` | 그날 기록 + 카드 유무를 한 번에 받는 조회 |
| `lib/features/record_card/presentation/card_compose_page.dart` | 작성 1 화면 |
| `lib/app/router/app_routes.dart` (수정) | `/record-card/new` 상수 |
| `lib/app/router/app_router.dart` (수정) | 셸 **밖** 라우트 |
| `lib/features/record_card/presentation/record_card_page.dart` (수정) | 입구 셋 — 탭 머리 ✎ · 빈 상태 버튼 · 빈 날 탭 |
| `lib/core/strings/app_strings.dart` (수정) | 이 화면의 한국어 |

---

### Task 1: 초안 값

**Files:**
- Create: `lib/features/record_card/domain/card_draft.dart`
- Test: `test/record_card_draft_test.dart`

**Interfaces:**
- Consumes: `RunRecord`(`features/record/domain/run_record.dart`) · `RouteArt`(`record_card/domain/route_art.dart`) · `RecordCardActivity`
- Produces:
```dart
class CardDraft {
  const CardDraft({this.record, this.route, this.activity, this.reviewText = ''});
  final RunRecord? record;
  final RouteArt? route;          // 못 받았거나 경로가 없는 러닝이면 null
  final RecordCardActivity? activity;
  final String reviewText;
  static const reviewMaxLength = 1000;
  bool get canProceed;            // 기록·유형·회고가 다 찼나
  bool get isDirty;               // 버릴 때 물어야 하나
  CardDraft copyWith({
    RunRecord? record, bool clearRecord = false,
    RouteArt? route, bool clearRoute = false,
    RecordCardActivity? activity,
    String? reviewText,
  });
}
```

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `test/record_card_draft_test.dart`

```dart
test('⚠️ 다음은 기록·유형·회고가 다 차야 켜진다', () {
  expect(const CardDraft().canProceed, isFalse);
  expect(_draft(record: _record()).canProceed, isFalse);
  expect(_draft(record: _record(), activity: RecordCardActivity.daily).canProceed, isFalse);
  expect(_draft(record: _record(), activity: RecordCardActivity.daily, reviewText: '좋았다').canProceed, isTrue);
});

test('⚠️ 공백뿐인 회고는 쓴 것이 아니다', () {
  expect(_draft(record: _record(), activity: RecordCardActivity.daily, reviewText: '   \n ').canProceed, isFalse);
});

test('⚠️ 경로가 없어도 쓸 수 있다 — 트레드밀 러닝이다', () {
  final draft = _draft(record: _record(), activity: RecordCardActivity.daily, reviewText: '실내');
  expect(draft.route, isNull);
  expect(draft.canProceed, isTrue);
});

test('⚠️ 꽂혀 들어온 기록만으로는 버릴 때 묻지 않는다', () {
  // 진입할 때 앱이 꽂아 준 기록은 사용자가 쓴 것이 아니다.
  expect(_draft(record: _record()).isDirty, isFalse);
  expect(_draft(record: _record(), activity: RecordCardActivity.race).isDirty, isTrue);
  expect(_draft(reviewText: '한 글자').isDirty, isTrue);
});

test('clearRecord·clearRoute가 값을 비운다', () { /* copyWith(clearRoute: true).route == null */ });
```

- [ ] **Step 2: 실패를 확인한다**

Run: `.fvm/flutter_sdk/bin/flutter.bat test test/record_card_draft_test.dart`
Expected: FAIL — `card_draft.dart`가 없어 컴파일되지 않는다

- [ ] **Step 3: `CardDraft`를 구현한다**

`copyWith`의 `clear*` 깃발은 이 저장소가 이미 쓰는 꼴이다(`RecordCardData.copyWith(clearFilter:)`). 클래스 문서에 **왜 `isDirty`가 기록을 세지 않는지** 한 줄 적는다.

- [ ] **Step 4: 통과를 확인한다**

Run: `.fvm/flutter_sdk/bin/flutter.bat test test/record_card_draft_test.dart`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add lib/features/record_card/domain/card_draft.dart test/record_card_draft_test.dart
git commit -m "📍 Feat: 기록카드 초안 값과 다음 버튼 규칙"
```

---

### Task 2: 기록과 카드를 맞춘다

**Files:**
- Create: `lib/features/record_card/domain/composable_record.dart`
- Test: `test/record_card_composable_record_test.dart`

**Interfaces:**
- Consumes: `RunRecord` · `RecordCard`(`runningRecordId`를 가진다)
- Produces:
```dart
class ComposableRecord {
  const ComposableRecord({required this.record, this.existingCardId});
  final RunRecord record;
  final int? existingCardId;
  bool get hasCard => existingCardId != null;
}

List<ComposableRecord> joinCards({
  required List<RunRecord> records,
  required List<RecordCard> cards,
});
```

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `test/record_card_composable_record_test.dart`

```dart
test('카드가 있는 기록에는 그 카드 번호가 붙는다', () {
  final joined = joinCards(
    records: [_record(id: 11), _record(id: 12)],
    cards: [_card(id: 500, runningRecordId: 12)],
  );
  expect(joined.map((r) => r.record.id), [11, 12]);   // ⚠️ 기록 순서를 유지한다
  expect(joined[0].existingCardId, isNull);
  expect(joined[0].hasCard, isFalse);
  expect(joined[1].existingCardId, 500);
});

test('⚠️ 한 기록에 카드가 둘로 오면 첫 카드를 쓴다', () {
  // 서버에 unique(running_record_id)가 있지만 앱은 그것을 믿고 터지지 않는다.
  final joined = joinCards(
    records: [_record(id: 11)],
    cards: [_card(id: 500, runningRecordId: 11), _card(id: 501, runningRecordId: 11)],
  );
  expect(joined.single.existingCardId, 500);
});

test('기록이 없으면 빈 목록이다 — 카드가 있어도', () {
  expect(joinCards(records: [], cards: [_card(id: 500, runningRecordId: 11)]), isEmpty);
});
```

- [ ] **Step 2: 실패를 확인한다**

Run: `.fvm/flutter_sdk/bin/flutter.bat test test/record_card_composable_record_test.dart`
Expected: FAIL — `joinCards`가 없다

- [ ] **Step 3: `joinCards`를 구현한다**

카드를 `runningRecordId` → 첫 카드 Map으로 접고 기록을 훑는다. 함수 문서에 **왜 서버 깃발을 안 쓰는지**(이 계획의 Ruling 1) 한 줄 적는다.

- [ ] **Step 4: 통과를 확인한다**

Run: `.fvm/flutter_sdk/bin/flutter.bat test test/record_card_composable_record_test.dart`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add lib/features/record_card/domain/composable_record.dart test/record_card_composable_record_test.dart
git commit -m "📍 Feat: 그날 기록에 이미 쓴 카드를 맞춰 붙인다"
```

---

### Task 3: 초안 provider

**Files:**
- Create: `lib/features/record_card/presentation/card_draft_provider.dart`
- Test: `test/record_card_draft_provider_test.dart`

**Interfaces:**
- Consumes: Task 1의 `CardDraft`
- Produces:
```dart
/// 인자는 카드 번호. **`null`이 새 카드다.**
final cardDraftProvider =
    NotifierProvider.family<CardDraftController, CardDraft, int?>(
      CardDraftController.new,
    );

class CardDraftController extends Notifier<CardDraft> {
  CardDraftController(this.cardId);
  final int? cardId;
  @override CardDraft build();
  void pickRecord(RunRecord record);   // 경로를 함께 비운다
  void setRoute(RouteArt? route);
  void setActivity(RecordCardActivity activity);
  void setReview(String text);         // reviewMaxLength로 자른다
  void clear();
}
```

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `test/record_card_draft_provider_test.dart`

```dart
test('새 초안은 비어 있다', () { /* container.read(cardDraftProvider(null)) == const CardDraft() */ });

test('⚠️ 기록을 바꾸면 앞 기록의 경로가 남지 않는다', () {
  final notifier = container.read(cardDraftProvider(null).notifier);
  notifier.pickRecord(_record(id: 11));
  notifier.setRoute(_someRoute());
  notifier.pickRecord(_record(id: 12));
  expect(container.read(cardDraftProvider(null)).route, isNull);
});

test('⚠️ 회고가 1000자를 넘으면 잘라서 담는다', () {
  container.read(cardDraftProvider(null).notifier).setReview('가' * 1200);
  expect(container.read(cardDraftProvider(null)).reviewText.length, CardDraft.reviewMaxLength);
});

test('⚠️ 보던 화면이 떠나도 초안은 남는다', () {
  // 작성이 세 화면이라 라우트를 넘나든다. autoDispose면 사진 화면으로 가는
  // 순간 작성 1의 구독이 끊겨 쓴 것이 사라진다(implementation-notes 5-1).
  final sub = container.listen(cardDraftProvider(null), (_, _) {});
  container.read(cardDraftProvider(null).notifier).setReview('쓴 글');
  sub.close();
  expect(container.read(cardDraftProvider(null)).reviewText, '쓴 글');
});

test('⚠️ 새 카드와 수정 중인 카드는 섞이지 않는다', () {
  container.read(cardDraftProvider(null).notifier).setReview('새 카드');
  container.read(cardDraftProvider(7).notifier).setReview('7번 수정');
  expect(container.read(cardDraftProvider(null)).reviewText, '새 카드');
});

test('clear가 비운다', () { /* ... */ });
```

- [ ] **Step 2: 실패를 확인한다**

Run: `.fvm/flutter_sdk/bin/flutter.bat test test/record_card_draft_provider_test.dart`
Expected: FAIL — `cardDraftProvider`가 없다

- [ ] **Step 3: `CardDraftController`를 구현한다**

**`autoDispose`를 붙이지 않는다.** 이 저장소의 수동 provider는 기본이 keepAlive이고(`isAutoDispose = false`), 붙이면 화면 사이에서 초안이 사라진다. 클래스 문서에 그 사실과 설계 7절의 수명 표를 한 줄로 적는다.

- [ ] **Step 4: 통과를 확인한다**

Run: `.fvm/flutter_sdk/bin/flutter.bat test test/record_card_draft_provider_test.dart`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add lib/features/record_card/presentation/card_draft_provider.dart test/record_card_draft_provider_test.dart
git commit -m "📍 Feat: 작성 세 화면이 함께 쓰는 초안 provider"
```

---

### Task 4: 그날 고를 수 있는 기록 조회

**Files:**
- Create: `lib/features/record_card/presentation/compose_records_provider.dart`
- Test: `test/record_card_compose_records_test.dart`

**Interfaces:**
- Consumes: `runRecordRepositoryProvider`(`features/record/presentation/record_provider.dart`) · `recordCardRepositoryProvider` · Task 2의 `joinCards`
- Produces:
```dart
/// 인자는 **날짜**다. 시·분이 붙어 와도 날짜만 보고 조회한다.
final composeRecordsProvider =
    FutureProvider.autoDispose.family<List<ComposableRecord>, DateTime>(...);
```

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `test/record_card_compose_records_test.dart`

`FakeRunRecordRepository`(`today:`·`delay:`를 받는다)와 `FakeRecordCardRepository`를 override해 쓴다. 카드 쪽 실패는 `failWith`로 만들고, **러닝 기록 쪽에는 실패 손잡이가 없다** — 테스트 파일에 `class _FailingRunRecords implements RunRecordRepository`를 작은 스텁으로 둔다. 가짜 저장소에 손잡이를 더하지 않는다(다른 화면의 테스트가 함께 흔들린다).

```dart
test('그날 기록에 카드 유무가 붙어 온다', () { /* ... */ });

test('⚠️ 시각이 붙은 날짜를 넘겨도 그날 것을 준다', () {
  // family 키가 시·분으로 흔들리면 같은 날이 provider 여러 개가 된다.
  final withTime = await container.read(composeRecordsProvider(DateTime(2026, 9, 2, 19, 30)).future);
  expect(withTime.map((r) => r.record.id), [11, 12]);
});

test('⚠️ 두 조회를 줄 세우지 않는다', () {
  // 왕복이 두 배가 된다(runDetailProvider가 같은 이유를 적어 뒀다).
  // 가짜 저장소에 지연을 주고, 전체 소요가 두 지연의 합보다 작음을 본다.
});

test('기록 조회가 실패하면 오류가 올라온다', () { /* expect(..., throwsA(isA<RunRecordException>())) */ });

test('⚠️ 카드 조회 실패도 오류다 — 없는 척하지 않는다', () {
  // 카드가 있는 기록을 "없음"으로 보여 주면 중복 작성으로 끌고 가고,
  // 저장에서 거절당해 쓴 글을 잃는다. 한 줄 오류와 다시 시도가 낫다.
});
```

- [ ] **Step 2: 실패를 확인한다**

Run: `.fvm/flutter_sdk/bin/flutter.bat test test/record_card_compose_records_test.dart`
Expected: FAIL — `composeRecordsProvider`가 없다

- [ ] **Step 3: `composeRecordsProvider`를 구현한다**

날짜를 `DateTime(day.year, day.month, day.day)`로 깎아 `byDateRange(from: day, to: day)`를 **두 저장소에 `Future.wait`로 동시에** 던지고 `joinCards`로 합친다. 화면을 닫으면 버린다(`autoDispose` — 날짜를 옮겨 다니는 조회라 들고 있을 이유가 없다).

- [ ] **Step 4: 통과를 확인한다**

Run: `.fvm/flutter_sdk/bin/flutter.bat test test/record_card_compose_records_test.dart`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add lib/features/record_card/presentation/compose_records_provider.dart test/record_card_compose_records_test.dart
git commit -m "📍 Feat: 그날 러닝 기록과 카드 유무를 한 번에 받는다"
```

---

### Task 5: 작성 1 화면

**Files:**
- Create: `lib/features/record_card/presentation/card_compose_page.dart`
- Modify: `lib/core/strings/app_strings.dart` (기록카드 문자열 묶음 뒤에 이어 붙인다)
- Test: `test/record_card_compose_page_test.dart`

**Interfaces:**
- Consumes: Task 1·3·4 전부 · `RouteArtView` · `runDetailProvider`(`features/record/presentation/record_provider.dart`) · `normalizeRoute`
- Produces: `class CardComposePage extends ConsumerStatefulWidget { const CardComposePage({required this.day, this.cardId, super.key}); final DateTime day; final int? cardId; }`

**화면** (설계 6-2):

```
←      기록카드 쓰기      다음      ← 다음은 canProceed일 때만 켜짐
러닝 불러오기
[ 2026.09.02 (화)            📅 ]   ← 누르면 년·월·일 휠, 오늘까지
( ) 18:54 시작 · 5.4 km · 28분 소요
(•) 07:12 시작 · 3.1 km · 18분 소요   [카드]   ← [카드]면 상세로 보낸다
[      경로 선 아트 (9:16)      ]
 총 거리    평균 페이스    총 소요시간
러닝 유형   [일상] [대회] [여행]
러닝 메모   [ 오늘의 러닝은 어떤 순간으로 기억되나요? ]   0/1000
```

**새 문자열** — 값은 그대로 쓴다:

| 이름 | 값 |
|---|---|
| `recordCardComposeTitle` | `기록카드 쓰기` |
| `recordCardComposeNext` | `다음` |
| `recordCardComposeRecordSection` | `러닝 불러오기` |
| `recordCardComposeDateSheet` | `날짜 고르기` |
| `recordCardComposeNoRecords` | `이 날에는 러닝 기록이 없어요` |
| `recordCardComposeRecordsError` | `러닝 기록을 불러오지 못했어요` |
| `recordCardComposeHasCard` | `카드` |
| `recordCardComposeRouteNone` | `경로가 없는 러닝이에요` |
| `recordCardComposeActivitySection` | `러닝 유형` |
| `recordCardComposeReviewHint` | `오늘의 러닝은 어떤 순간으로 기억되나요?` |
| `recordCardComposeReviewCounter(int n)` | `$n/1000` |
| `recordCardComposeDateLabel(DateTime d)` | `2026.09.02 (화)` |

회고 묶음 머리는 **기존 `recordCardReview`(`러닝 메모`)를 쓴다** — 상세와 같은 말이어야 한다. 지표 이름도 기존 `recordCardDistance` · `recordCardPace` · `recordCardDuration`을 쓰고, 값은 `kmFloor` · `recordRunDuration` + `runPartyUnitKm` · `runPartyUnitPerKm`으로 찍는다. 기록 한 줄은 기존 `recordRunLine(startedAt, km, took)`이다.

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `test/record_card_compose_page_test.dart`

```dart
testWidgets('기록을 고르고 유형·회고를 채우면 다음이 켜진다', (tester) async { /* ... */ });

testWidgets('⚠️ 그날 기록이 없으면 한 줄로 알린다 — 날짜는 그대로 바꿀 수 있다', (tester) async {
  expect(find.text(AppStrings.recordCardComposeNoRecords), findsOne);
  expect(find.text(AppStrings.recordCardComposeDateLabel(DateTime(2026, 9, 3))), findsOne);
});

testWidgets('⚠️ 기록 조회가 실패하면 목록 자리에만 오류가 뜬다', (tester) async {
  // 날짜 행과 유형·회고는 살아 있어야 한다 — 화면 전체를 오류로 덮으면
  // 날짜를 바꿀 길까지 사라진다.
  expect(find.text(AppStrings.recordCardComposeRecordsError), findsOne);
  expect(find.text(AppStrings.recordRetry), findsOne);
  expect(find.text(AppStrings.recordCardComposeActivitySection), findsOne);
});

testWidgets('⚠️ 기록이 전부 카드를 가진 날 — 목록은 보이고 다음은 꺼져 있다', (tester) async {
  expect(find.text(AppStrings.recordCardComposeHasCard), findsNWidgets(2));
  // 다음 버튼 onPressed == null
});

testWidgets('⚠️ 카드가 있는 기록을 누르면 그 카드 상세로 간다', (tester) async { /* 라우트 기록을 본다 */ });

testWidgets('⚠️ 날짜 휠에 오늘 이후가 없다', (tester) async {
  // 뛰지 않은 날의 카드는 없다. 고른 뒤 막는 것이 아니라 못 고르게 한다.
});

testWidgets('⚠️ 회고는 1000자에서 멈춘다', (tester) async {
  await tester.enterText(find.byType(AppInputV2), '가' * 1200);
  expect(find.text(AppStrings.recordCardComposeReviewCounter(1000)), findsOne);
});

testWidgets('경로가 없는 기록이면 선 아트 자리에 한 줄이 든다', (tester) async { /* ... */ });

testWidgets('라이트 테마에서도 그려진다', (tester) async { /* takeException() == null */ });
```

- [ ] **Step 2: 실패를 확인한다**

Run: `.fvm/flutter_sdk/bin/flutter.bat test test/record_card_compose_page_test.dart`
Expected: FAIL — `CardComposePage`가 없다

- [ ] **Step 3: `CardComposePage`를 구현한다**

- 날짜 행은 `showWheelPickerSheet`에 년·월·일 세 칸. **`WheelColumn.valuesFor`로 일수를 그 달에 맞춘다**(`settings_page.dart:138`이 생일에 쓰는 것과 같은 꼴). 년의 상한과 오늘 달·오늘 일의 상한은 `recordCardClockProvider`가 주는 "오늘"로 깎는다.
- 기록 목록은 `composeRecordsProvider(그 날짜)`의 `AsyncValue`를 3분기로 그린다. **오류는 목록 자리에서만** — `switch`를 목록 묶음 안에 둔다.
- 기록을 고르면 `pickRecord` 후 `runDetailProvider(record.runningRoomId)`를 watch해 `normalizeRoute(detail.track)`을 `setRoute`에 넣는다. 받는 중에는 선 아트 자리에 진행 표시, 못 받으면 `recordCardComposeRouteNone`.
- 유형 칩은 **`ActivityFilter`를 쓰지 않는다** — 그쪽은 `null`(전체)을 허용하고 다시 누르면 꺼진다. 작성에서는 하나가 반드시 켜져야 하므로 같은 모양의 `_ActivityChoice`를 이 파일에 둔다. 그 이유를 주석에 적는다.
- 회고 칸은 `AppInputV2(maxLines: 5, counter: ...)` + `LengthLimitingTextInputFormatter(CardDraft.reviewMaxLength)`.
- 지표는 `StatRowV2(stats: [Stat(label:, value:)])` 세 칸.
- 수치에 `FontFeature.tabularFigures()`.
- **`다음`은 켜지기만 하고 아직 아무 데도 보내지 않는다.** 없는 라우트(`/record-card/new/photos`)를 미리 밀어 넣으면 go_router가 오류 화면을 띄운다. 다음 묶음이 이 한 줄을 꽂는다 — 주석에 **그 묶음과 함께 올린다**고 적어, 이대로 내보내지 않게 못 박는다.

- [ ] **Step 4: 통과를 확인한다**

Run: `.fvm/flutter_sdk/bin/flutter.bat test test/record_card_compose_page_test.dart`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add lib/features/record_card/presentation/card_compose_page.dart lib/core/strings/app_strings.dart test/record_card_compose_page_test.dart
git commit -m "📍 Feat: 기록카드 작성 1 — 기록 고르기·유형·회고"
```

---

### Task 6: 라우트와 입구 셋

**Files:**
- Modify: `lib/app/router/app_routes.dart` (`recordCardDetail` 바로 아래 — **정렬 위치에 넣는다.** 맨 끝에 붙이면 머지 충돌이 난다)
- Modify: `lib/app/router/app_router.dart` (`recordCardDetail` 라우트 옆, 셸 **밖**)
- Modify: `lib/features/record_card/presentation/record_card_page.dart`
- Modify: `lib/core/strings/app_strings.dart`
- Test: `test/record_card_page_test.dart` (기존 파일에 더한다)

**Interfaces:**
- Produces:
```dart
static const recordCardNew = '/record-card/new';
/// 날짜를 쿼리로 싣는다 — `extra`로 넘기면 딥링크·복구에서 사라진다.
static String recordCardNewOn(DateTime day);   // '/record-card/new?date=2026-09-02'
```

**새 문자열:** `recordCardComposeDiscardTitle` = `쓰던 기록카드를 버릴까요?`, `recordCardComposeDiscardBody` = `적은 내용이 사라져요`, `recordCardComposeDiscardConfirm` = `버리기`, `recordCardComposeKeep` = `이어 쓰기`. 빈 상태 버튼은 기존 `recordCardEmptyAction`(`기록카드 쓰기`)을 쓴다 — **지금 아무도 안 쓰는 문자열이고, 이 자리가 그 자리다.**

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `test/record_card_page_test.dart`

```dart
testWidgets('⚠️ 탭 머리의 쓰기 버튼으로 작성에 들어간다', (tester) async { /* 라우트 기록을 본다 */ });

testWidgets('⚠️ 카드가 한 장도 없으면 빈 안내에 쓰기 버튼이 선다', (tester) async {
  expect(find.text(AppStrings.recordCardEmptyAction), findsOne);
});

testWidgets('⚠️ 빈 날을 누르면 그 날짜로 작성에 간다', (tester) async {
  // 1번 PR에서는 아무 일도 하지 않았다 — 눌리는데 반응이 없는 칸이었다.
  expect(pushed, AppRoutes.recordCardNewOn(DateTime(2026, 9, 3)));
});

test('recordCardNewOn이 날짜를 쿼리로 싣는다', () {
  expect(AppRoutes.recordCardNewOn(DateTime(2026, 9, 3)), '/record-card/new?date=2026-09-03');
});
```

그리고 `test/record_card_compose_page_test.dart`에 초안 덮어쓰기를 더한다:

```dart
testWidgets('⚠️ 쓰던 초안이 있는데 다른 날짜로 들어오면 확인을 받는다', (tester) async {
  // 설계 7절: draft가 있는데 새로 진입하면 덮어쓰기 전에 알린다.
  expect(find.text(AppStrings.recordCardComposeDiscardTitle), findsOne);
  // `이어 쓰기`를 고르면 쓴 글이 남고 날짜도 초안의 것으로 돌아온다
});

testWidgets('⚠️ 쓴 것이 있을 때 뒤로 가면 확인을 받는다', (tester) async { /* ... */ });
```

- [ ] **Step 2: 실패를 확인한다**

Run: `.fvm/flutter_sdk/bin/flutter.bat test test/record_card_page_test.dart test/record_card_compose_page_test.dart`
Expected: FAIL — `recordCardNewOn`이 없고 쓰기 버튼이 없다

- [ ] **Step 3: 라우트와 입구를 구현한다**

- 라우트는 `recordCardDetail`과 같은 자리(셸 밖). `date` 쿼리가 없거나 못 읽으면 **오늘**로 떨어진다 — 404를 내지 않는다.
- 탭에 `AppBar(title: 기록카드, actions: [IconButton(LucideIcons.pencil)])`. 라벨 없는 아이콘이라 `Semantics(label:)`를 반드시 붙인다(CLAUDE.md). **보기 전환은 이 PR이 아니다** — 1.5가 이 머리에 더한다.
- 빈 상태의 `_Empty`에 `AppButtonV2` 하나를 더한다.
- `onEmptyDay`를 `context.push(AppRoutes.recordCardNewOn(day))`로 바꾸고, 1번 PR이 적어 둔 "아직 아무 데도 가지 않는다" 주석을 **지운다** — 낡은 주석을 남기지 않는다.
- 뒤로·덮어쓰기 확인은 바텀시트 하나(`showModalBottomSheet`)로 둔다. **`PopScope`로 시스템 뒤로 제스처도 함께 막는다** — AppBar 버튼만 막으면 안드로이드에서 그냥 빠져나간다.

- [ ] **Step 4: 통과를 확인한다**

Run: `.fvm/flutter_sdk/bin/flutter.bat test test/record_card_page_test.dart test/record_card_compose_page_test.dart`
Expected: PASS

- [ ] **Step 5: 전체 테스트와 analyze**

Run: `.fvm/flutter_sdk/bin/flutter.bat test` 그리고 `.fvm/flutter_sdk/bin/flutter.bat analyze`
Expected: 전부 PASS · 경고 0개

- [ ] **Step 6: 커밋**

```bash
git add lib/app/router/app_routes.dart lib/app/router/app_router.dart lib/features/record_card/presentation/record_card_page.dart lib/core/strings/app_strings.dart test/
git commit -m "📍 Feat: 기록카드 작성 입구 셋 — 탭 머리·빈 상태·빈 날"
```

---

## 끝낸 뒤

- **이 묶음은 혼자 PR로 올리지 않는다.** `다음`을 누를 사진 화면이 아직 없어, 혼자 올리면 **또 막힌 버튼**을 내보낸다. 다음 묶음(작성 2·3 — 사진·공개범위·저장)과 **한 PR로 합쳐** 올린다. 커밋 경계가 여기서 끊겨 있으니, 쪼개야 할 이유가 생기면 그때 쪼갤 수 있다.
- 설계 문서(`docs/specs/2026-11-16-record-card-design.md`)를 이 계획의 **Ruling 세 줄**대로 고친다 — 10절 질문 3을 지우고, 6-1의 "기록이 있을 때만"을 바꾸고, 6-2의 "수정으로 보낸다"에 PR 순서를 적는다.
- 기기 확인: 에뮬레이터의 **실제 기록이 있는 날짜**로 들어가야 목록이 찬다(가짜 카드와 실제 러닝 기록은 서로 맞지 않는다). 기록이 없으면 GPS 주입으로 하나 만든다.
