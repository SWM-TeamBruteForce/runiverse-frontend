# 기록카드 1 — 캘린더 탭 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 기록카드 탭이 `ComingSoonPage`를 벗어나, 월 ⇄ 분기 캘린더로 카드를 모아 보고 한 장을 열어 읽을 수 있게 한다.

**Architecture:** 새 feature `lib/features/record_card/`를 판다. 서버가 없어 도메인 인터페이스 + `FakeRecordCardRepository`로 세우고, 명세가 채워지면 HTTP 구현체만 갈아끼운다. 경로는 지도 없이 **정규화 좌표를 `CustomPainter`로 긋는 선 아트**라 지도 패키지를 타지 않는다.

**Tech Stack:** Flutter · Riverpod 3 (`NotifierProvider`, 코드생성 없음) · go_router · Lucide 아이콘. freezed 미도입이라 상태는 `sealed class`로 직접 적는다.

**Spec:** `docs/specs/2026-11-16-record-card-design.md`

## Global Constraints

- 모든 flutter/dart 명령 앞에 `fvm`. **이 PC는 fvm이 PATH에 없다** — `.fvm/flutter_sdk/bin/flutter.bat`을 직접 부른다.
- 아이콘은 **Lucide만**(`AppIcons`의 문자열 이름). `Icons.*` 금지.
- `core/theme/tokens/` 밖에서 `Color(0x...)` 등 값 하드코딩 금지. `context.appColorsV2` · `AppSpacing` · `AppRadius` · `AppTypographyV2` · `AppMotion`만 쓴다.
- `StateProvider` / `StateNotifierProvider` 금지 (Riverpod 3 레거시).
- 화면은 **loading / data / error 3분기 필수**. **empty 상태와 다크·라이트 두 테마**를 함께 정의한다.
- UI 텍스트는 한국어이고 전부 `AppStrings`에 둔다. **정렬 위치에 넣는다** — 맨 끝에 붙이면 머지 충돌이 난다(`docs/CONTRIBUTING.md`). `app_routes.dart`도 같다.
- 내부 import는 항상 `package:runiverse/...` 절대경로.
- **의존 방향 `presentation → domain ← data`.** `domain/`은 순수 Dart만 — `dart:ui`의 `Offset`·`Size`도 쓰지 않는다.
- 다른 feature의 **화면·위젯**을 import하지 않는다. 도메인은 괜찮다.
- 탭 바에 글자 라벨이 없으므로 **`Semantics(label:)`을 반드시 붙인다.** `container: true`를 빼면 라벨이 자기 노드를 못 만들어 아무것도 읽히지 않는다(`runner_avatar.dart:41-46`).
- 커밋은 `<이모지> <type>: <설명>` — `📍 Feat` `🔨 Fix` `📝 Docs` `🎨 Style` `🤖 Refactor` `✅ Test` `🚚 Chore`. **AI 공동 작성자 트레일러를 넣지 않는다.** 끝에 `Claude-Session: https://claude.ai/code/session_01674ihhncD11zfJ6JUQvU1B`를 붙인다.
- 이 PR은 **20파일 / 500줄을 넘는다.** 사유를 PR 본문에 적는다 — 도메인·Fake·화면이 한 묶음이어야 눈으로 확인할 수 있고, 쪼개면 사용자에게 보이는 결과가 없는 PR이 생긴다.

## Review Focus

- **경로 점이 하나거나 전부 같은 좌표** (트레드밀·GPS 미수신). bounding box가 0이라 0으로 나눈다. 선 대신 점 하나를 가운데 그려야 한다. → Task 2
- **KST 자정 직전에 시작한 러닝.** 서버가 오프셋 없는 KST로 준다. 날짜 칸을 고를 때 시·분을 안 자르면 카드가 캘린더에서 사라진다. → Task 4
- **유형 필터를 걸어 그 달 카드가 0이 됨.** 달 머리가 `카드 0장`이고 칸이 전부 비는데, 이것은 "카드가 없는 사람"의 빈 상태와 다르다. 안내를 띄우면 안 된다. → Task 4·8
- **하루에 카드가 2장 이상.** 하루에 두 번 뛰면 정상이다. 배지와 그날 시트가 없으면 두 번째 카드가 갇힌다. → Task 7
- **조회 실패.** Fake가 성공만 하면 error 분기를 한 번도 못 본다. 실패를 눈으로 확인할 길이 있어야 한다. → Task 3·8

---

## 파일 구조

| 파일 | 책임 |
|---|---|
| `domain/record_card_activity.dart` | 일상·대회·여행 ↔ `DAILY`·`RACE`·`TRAVEL` |
| `domain/record_card_visibility.dart` | 공개범위 ↔ `PUBLIC`·`FRIENDS`·`PRIVATE` |
| `domain/route_art.dart` | `RoutePoint` · `RouteArt` · `normalizeRoute` · `fitRoute` (순수 계산) |
| `domain/record_card.dart` | `RecordCard` · `RecordCardPhoto` · `CardRunner` |
| `domain/record_card_repository.dart` | 인터페이스 · `RecordCardFailure` · `RecordCardException` |
| `data/fake_record_card_repository.dart` | 두 달치 가짜 카드 |
| `presentation/record_card_state.dart` | `RecordCardState` sealed union · `MonthCards` · `CalendarZoom` · `zoomFor` |
| `presentation/record_card_provider.dart` | 저장소 provider · `RecordCardController` |
| `presentation/route_art_view.dart` | 선 아트 `CustomPainter` 위젯 |
| `presentation/record_card_cell.dart` | 날짜 한 칸 |
| `presentation/record_card_calendar.dart` | 월 ⇄ 분기 그리드 |
| `presentation/day_cards_sheet.dart` | 하루에 둘 이상일 때 |
| `presentation/activity_filter.dart` | 유형 칩 |
| `presentation/record_card_page.dart` | 탭 화면 |
| `presentation/card_detail_page.dart` | 카드 상세 (읽기 전용) |
| `presentation/card_media_pager.dart` | 선 아트 + 사진 9:16 페이저 |

> ⚠️ **번호순으로 한다. 문서 순서가 아니다.** `RecordCard.route`가 `RouteArt`라
> 선 아트(Task 1)가 도메인(Task 2)보다 먼저다. 문서에는 도메인이 위에 있다.

---

### Task 2: 도메인 값과 엔티티

**Files:**
- Create: `lib/features/record_card/domain/record_card_activity.dart`
- Create: `lib/features/record_card/domain/record_card_visibility.dart`
- Create: `lib/features/record_card/domain/record_card.dart`
- Create: `lib/features/record_card/domain/record_card_repository.dart`
- Test: `test/record_card_domain_test.dart`

**Interfaces:**
- Consumes: Task 1의 `RouteArt` — `RecordCard.route`가 이 타입이다.
- Produces:
  - `enum RecordCardActivity { daily, race, travel }` · `static RecordCardActivity? of(Object? wire)` · `String get wire`
  - `enum RecordCardVisibility { public, friends, private }` · `static RecordCardVisibility of(Object? wire)` · `String get wire`
  - `class RecordCard` — 아래 Step 3의 필드
  - `class RecordCardPhoto({required int id, required String url, String? thumbnailUrl, String? caption})`
  - `class CardRunner({required String userId, required String nickname, String? profileImageUrl})`
  - `abstract interface class RecordCardRepository` · `Future<List<RecordCard>> byDateRange({required DateTime from, required DateTime to})`
  - `enum RecordCardFailure { invalidRequest, sessionExpired, notFound, forbidden, network, server }`
  - `class RecordCardException implements Exception { final RecordCardFailure failure; }`
  - `static const int RecordCardRepository.maxRangeDays = 31`

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `test/record_card_domain_test.dart`

```dart
test('활동 유형은 서버 코드로 오간다', () {
  expect(RecordCardActivity.of('TRAVEL'), RecordCardActivity.travel);
  expect(RecordCardActivity.of('DAILY'), RecordCardActivity.daily);
  expect(RecordCardActivity.of('RACE'), RecordCardActivity.race);
  expect(RecordCardActivity.travel.wire, 'TRAVEL');
});

test('⚠️ 모르는 활동 유형은 null이다 — 아무 값으로도 뭉개지 않는다', () {
  expect(RecordCardActivity.of('COMMUTE'), isNull);
  expect(RecordCardActivity.of(null), isNull);
});

test('공개범위는 FOLLOWERS도 friends로 읽는다', () {
  expect(RecordCardVisibility.of('FRIENDS'), RecordCardVisibility.friends);
  expect(RecordCardVisibility.of('FOLLOWERS'), RecordCardVisibility.friends);
  expect(RecordCardVisibility.friends.wire, 'FRIENDS');
});

test('⚠️ 모르는 공개범위는 private으로 떨어진다 — 모르면 안 보여준다', () {
  expect(RecordCardVisibility.of('EVERYONE'), RecordCardVisibility.private);
  expect(RecordCardVisibility.of(null), RecordCardVisibility.private);
});

test('썸네일은 첫 사진이고, 사진이 없으면 null이다', () { /* RecordCard 두 개로 */ });

test('day는 시·분을 자른다', () {
  // startedAt 2026-09-02 23:50 → day == DateTime(2026, 9, 2)
});
```

- [ ] **Step 2: 실패를 확인한다**

Run: `fvm flutter test test/record_card_domain_test.dart`
Expected: FAIL — `RecordCardActivity` 등이 없다는 컴파일 오류

- [ ] **Step 3: 도메인을 쓴다**

`RecordCardActivity.of`는 `RunKind.of`(`run_record.dart`)와 같은 방식이다 — **모르는 값은 `null`**이고 아무 값으로도 뭉개지 않는다. `RecordCardVisibility.of`만 다르다: **모르면 `private`**이다. 모르는 공개범위를 `public`으로 읽으면 안 보여야 할 카드를 보여주게 된다. 이 이유를 주석에 적는다.

`RecordCard` 필드:

```dart
final int id;
final int runningRecordId;
final DateTime startedAt;          // 오프셋 없는 KST
final RecordCardActivity activity;
final RecordCardVisibility visibility;
final String reviewText;
final List<RecordCardPhoto> photos;
final RouteArt route;
final int distanceMeters;
final Duration duration;
final Duration averagePace;
final List<CardRunner> runners;

DateTime get day;                  // startedAt에서 시·분을 자른 것
String? get thumbnailUrl;          // photos.first.thumbnailUrl ?? url, 없으면 null
```

`RecordCardFailure`는 `RunRecordFailure`와 같은 여섯 갈래다 — 예외를 화면까지 올리지 않고 값으로 답한다.

- [ ] **Step 4: 통과를 확인한다**

Run: `fvm flutter test test/record_card_domain_test.dart`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add lib/features/record_card/domain test/record_card_domain_test.dart
git commit -m "📍 Feat: 기록카드 도메인을 둔다"
```

---

### Task 1: 경로 선 아트의 계산

**Files:**
- Create: `lib/features/record_card/domain/route_art.dart`
- Test: `test/record_card_route_art_test.dart`

**Interfaces:**
- Consumes: `GeoPoint`(`features/session/domain/geo_point.dart`) — 위도·경도.
- Produces:
  - `class RoutePoint { final double x, y; }` — `0~1` 정규화 좌표. **`dart:ui`의 `Offset`을 쓰지 않는다**(domain은 순수 Dart).
  - `class RouteArt { final List<List<RoutePoint>> strokes; final double aspect; bool get isEmpty; static const RouteArt empty; }` — `aspect`는 **실세계 가로/세로 비**(`cos(위도)` 보정 끝난 값).
  - `RouteArt normalizeRoute(List<List<GeoPoint>> track)`
  - `List<List<RoutePoint>> fitRoute(RouteArt art, {required double width, required double height, required double padding})` — 반환 좌표는 **픽셀**이다.

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `test/record_card_route_art_test.dart`

```dart
test('⚠️ 경도에 cos(위도)를 곱한다 — 안 하면 동서로 늘어난다', () {
  // 서울(위도 37.5)에서 남북 0.01도, 동서 0.01도인 ㄱ자 경로.
  // cos(37.5) ≈ 0.7934 이므로 가로/세로 ≈ 0.7934 여야 한다.
  final art = normalizeRoute([[GeoPoint(...), ...]]);
  expect(art.aspect, closeTo(0.7934, 0.001));
});

test('조각 수를 지킨다 — 일시정지로 끊긴 선을 잇지 않는다', () {
  final art = normalizeRoute([[p1, p2], [p3, p4]]);
  expect(art.strokes, hasLength(2));
});

test('정규화하면 모든 좌표가 0과 1 사이다', () { /* 가장 먼 두 점이 0과 1 */ });

test('⚠️ 점이 하나뿐이면 가운데 한 점이다 — 0으로 나누지 않는다', () {
  final art = normalizeRoute([[GeoPoint(37.5, 127.0)]]);
  expect(art.strokes.single.single.x, 0.5);
  expect(art.strokes.single.single.y, 0.5);
  expect(art.aspect, 1.0);
});

test('⚠️ 모든 점이 같은 좌표여도 터지지 않는다 — 트레드밀', () { /* 같은 점 50개 */ });

test('빈 트랙은 RouteArt.empty다', () {
  expect(normalizeRoute(const []).isEmpty, isTrue);
  expect(normalizeRoute(const [[]]).isEmpty, isTrue);
});

test('fitRoute는 가로세로 비를 지키며 가운데에 앉힌다', () {
  // aspect 0.5인 경로를 100x100 상자(padding 0)에 넣으면
  // 세로로 꽉 차고(0~100) 가로는 가운데 50폭(25~75)을 쓴다.
});

test('fitRoute는 padding만큼 안쪽으로 들인다', () { /* padding 10 → 10~90 */ });

test('⚠️ 위도는 위로 갈수록 커지고 화면 y는 아래로 갈수록 커진다', () {
  // 북쪽 점이 작은 y로 나와야 한다. 안 뒤집으면 경로가 상하로 뒤집힌다.
});
```

- [ ] **Step 2: 실패를 확인한다**

Run: `fvm flutter test test/record_card_route_art_test.dart`
Expected: FAIL — `normalizeRoute`가 없다

- [ ] **Step 3: `route_art.dart`를 쓴다**

`normalizeRoute`의 알고리즘:

1. 모든 점의 위도·경도 최솟값·최댓값을 구한다.
2. 가운데 위도의 `cos`를 경도 폭에 곱해 **실세계 폭**을 낸다 (`dart:math`의 `cos`, 라디안 변환 필요).
3. 폭·높이 중 **긴 쪽**으로 둘 다 나눠 `0~1`에 넣는다. 짧은 쪽은 가운데 정렬한다.
4. 폭과 높이가 **둘 다 0에 가까우면**(`< 1e-9`) 모든 점을 `(0.5, 0.5)`로, `aspect`는 `1.0`으로 둔다.
5. `y`는 **위도를 뒤집어** 넣는다 — 북쪽이 작은 `y`다.
6. `aspect`는 `실세계 폭 / 실세계 높이`.

`fitRoute`는 `aspect`와 상자 비를 견줘 긴 쪽에 맞추고 짧은 쪽을 가운데로 민다.

- [ ] **Step 4: 통과를 확인한다**

Run: `fvm flutter test test/record_card_route_art_test.dart`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add lib/features/record_card/domain/route_art.dart test/record_card_route_art_test.dart
git commit -m "📍 Feat: 경로를 배경 없는 선으로 그릴 좌표를 낸다"
```

---

### Task 3: 가짜 저장소

**Files:**
- Create: `lib/features/record_card/data/fake_record_card_repository.dart`
- Test: `test/record_card_fake_repository_test.dart`

**Interfaces:**
- Consumes: Task 2의 `RecordCardRepository` · `RecordCard`, Task 1의 `normalizeRoute`.
- Produces: `FakeRecordCardRepository({DateTime? today, Duration delay = Duration.zero, RecordCardFailure? failWith})` · `int calls` · `List<({DateTime from, DateTime to})> queries`

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `test/record_card_fake_repository_test.dart`

```dart
test('구간 밖의 카드는 안 준다', () { /* 한 달만 물어보면 그 달 것만 */ });

test('⚠️ 31일을 넘기면 진짜처럼 거절한다', () {
  // from..to 가 maxRangeDays 이상이면 RecordCardFailure.invalidRequest
  // 가짜가 뭐든 받아 주면 화면이 구간을 넓혀도 테스트가 다 통과한다.
});

test('failWith를 주면 그 실패로 던진다', () { /* error 분기를 눈으로 보는 길 */ });

test('사진이 0장인 카드와 5장인 카드가 둘 다 있다', () {
  // 없으면 선 아트 칸과 썸네일 칸 중 하나를 한 번도 못 본다
});

test('하루에 카드가 둘인 날이 있다', () {
  // 없으면 개수 배지와 그날 시트를 한 번도 못 본다
});

test('활동 유형 셋이 모두 나온다', () { /* 필터를 눈으로 확인하는 길 */ });

test('모든 카드가 비어 있지 않은 경로를 들고 있다', () {
  // 선 아트가 안 그려지는 카드가 섞이면 칸이 빈 날처럼 보인다
});
```

- [ ] **Step 2: 실패를 확인한다**

Run: `fvm flutter test test/record_card_fake_repository_test.dart`
Expected: FAIL — `FakeRecordCardRepository`가 없다

- [ ] **Step 3: Fake를 쓴다**

`FakeRunRecordRepository`와 같은 모양이다 — `_today` 기준으로 값을 만들고, **진짜와 같은 규칙으로 거절한다**.

- **두 달치 20장.** 활동 유형 셋이 섞이고 공개범위도 섞인다.
- **사진 0장인 카드 · 5장인 카드 · 하루에 둘인 날**이 각각 있다.
- **사진은 번들 에셋**(`assets/`)을 쓴다. 네트워크를 타지 않는다.
- 경로는 손으로 적은 `GeoPoint` 몇 조각을 `normalizeRoute`에 통과시켜 만든다. 카드마다 모양이 달라야 칸이 구별된다.
- `RunRecordRepository`와 달리 **카드 Fake는 러닝 기록 Fake에 매이지 않는다.** `FakeRunRecordRepository._plan`을 건드리지 않는다 — 기록 탭의 주간·월 요약 눈검증 값이 같이 바뀐다.

- [ ] **Step 4: 통과를 확인한다**

Run: `fvm flutter test test/record_card_fake_repository_test.dart`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add lib/features/record_card/data test/record_card_fake_repository_test.dart
git commit -m "📍 Feat: 서버 없이 기록카드를 세울 가짜 저장소를 둔다"
```

---

### Task 4: 상태 — 달 묶기와 필터

**Files:**
- Create: `lib/features/record_card/presentation/record_card_state.dart`
- Test: `test/record_card_state_test.dart`

**Interfaces:**
- Consumes: Task 2의 `RecordCard` · `RecordCardActivity` · `RecordCardFailure`.
- Produces:
  - `sealed class RecordCardState` · `RecordCardLoading` · `RecordCardError(RecordCardFailure failure)` · `RecordCardData`
  - `class MonthCards({required DateTime month, required List<RecordCard> cards})` · `Map<DateTime, List<RecordCard>> get byDay` · `int get cardCount` · `MonthCards filtered(RecordCardActivity? activity)`
  - `enum CalendarZoom { month, quarter }`
  - `CalendarZoom zoomFor(CalendarZoom current, double scale)`
  - `RecordCardData({required List<MonthCards> months, RecordCardActivity? filter, CalendarZoom zoom})` · `final List<MonthCards> visible` · `RecordCardData copyWith({...})`

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `test/record_card_state_test.dart`

```dart
test('카드를 날짜별로 묶는다', () { /* byDay 키가 day 단위 */ });

test('⚠️ 자정 직전에 시작한 러닝도 그날 칸에 붙는다', () {
  // startedAt 2026-09-02 23:50 → byDay[DateTime(2026, 9, 2)] 에 있다
});

test('하루에 둘이면 한 키에 둘이 담긴다', () { /* hasLength(2) */ });

test('필터를 걸면 그 유형만 남고 카드 수도 따라 준다', () {
  // 일상 2 · 대회 1 인 달에 race 필터 → cardCount 1
});

test('⚠️ 필터로 0장이 된 달도 목록에 남는다 — 달이 사라지면 달력이 아니다', () {
  expect(data.visible, hasLength(2));
  expect(data.visible.first.cardCount, 0);
});

test('달은 오름차순이다', () { /* 2026.09 → 2026.10 */ });

test('많이 오므리면 분기로, 많이 벌리면 월로 간다', () {
  expect(zoomFor(CalendarZoom.month, 0.7), CalendarZoom.quarter);
  expect(zoomFor(CalendarZoom.quarter, 1.4), CalendarZoom.month);
});

test('⚠️ 조금 움직인 것으로는 안 바뀐다 — 스크롤하다 줌이 튄다', () {
  expect(zoomFor(CalendarZoom.month, 0.95), CalendarZoom.month);
  expect(zoomFor(CalendarZoom.quarter, 1.1), CalendarZoom.quarter);
});
```

- [ ] **Step 2: 실패를 확인한다**

Run: `fvm flutter test test/record_card_state_test.dart`
Expected: FAIL — `RecordCardState`가 없다

- [ ] **Step 3: 상태를 쓴다**

`RecordState`(`features/record/presentation/record_state.dart`)와 같은 방식이다 — freezed를 안 쓰므로 `sealed class`로 직접 적고, **묶는 일은 생성자에서 끝낸다.** 위젯이 매 빌드마다 다시 묶으면 스크롤할 때마다 같은 계산이 반복된다.

`RecordCardData`는 `months`(필터 전)를 받아 `visible`(필터 후)을 생성자에서 만든다.

`zoomFor`의 경계는 **오므리면 `0.8` 미만, 벌리면 `1.25` 초과**다. 그 사이는 지금 값을 그대로 둔다.

- [ ] **Step 4: 통과를 확인한다**

Run: `fvm flutter test test/record_card_state_test.dart`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add lib/features/record_card/presentation/record_card_state.dart test/record_card_state_test.dart
git commit -m "📍 Feat: 기록카드를 달로 묶고 유형으로 거른다"
```

---

### Task 5: 컨트롤러 — 월 캐시와 더 받기

**Files:**
- Create: `lib/features/record_card/presentation/record_card_provider.dart`
- Test: `test/record_card_provider_test.dart`

**Interfaces:**
- Consumes: Task 3의 `FakeRecordCardRepository`, Task 4의 `RecordCardState`.
- Produces:
  - `final recordCardRepositoryProvider = Provider<RecordCardRepository>(...)` — 지금은 `FakeRecordCardRepository`를 준다
  - `final recordCardClockProvider = Provider<DateTime Function()>((ref) => DateTime.now)`
  - `final recordCardControllerProvider = NotifierProvider<RecordCardController, RecordCardState>(RecordCardController.new)`
  - `RecordCardController` — `Future<void> load()` · `Future<void> loadOlder()` · `void setFilter(RecordCardActivity?)` · `void setZoom(CalendarZoom)`

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `test/record_card_provider_test.dart`

```dart
test('처음 열면 최근 세 달을 받는다', () {
  expect(fake.queries, hasLength(3));
});

test('⚠️ 달마다 따로 묻는다 — 한 번에 31일을 넘기면 서버가 400을 준다', () {
  for (final q in fake.queries) {
    expect(q.to.difference(q.from).inDays, lessThan(31));
  }
});

test('더 받으면 더 과거 세 달만 묻는다', () {
  await controller.loadOlder();
  expect(fake.queries, hasLength(6));   // 겹치는 달을 다시 묻지 않는다
});

test('⚠️ 줌을 바꿔도 서버를 다시 부르지 않는다', () {
  final before = fake.calls;
  controller.setZoom(CalendarZoom.quarter);
  expect(fake.calls, before);
});

test('⚠️ 필터를 바꿔도 서버를 다시 부르지 않는다', () { /* 같은 방식 */ });

test('실패하면 RecordCardError가 된다', () {
  // failWith: RecordCardFailure.network 인 Fake
});

test('clock을 고정하면 묻는 달이 고정된다', () {
  // recordCardClockProvider 를 2026-11-16 으로 덮어쓰면 9·10·11월
});
```

- [ ] **Step 2: 실패를 확인한다**

Run: `fvm flutter test test/record_card_provider_test.dart`
Expected: FAIL — `recordCardControllerProvider`가 없다

- [ ] **Step 3: 컨트롤러를 쓴다**

`RecordController`(`record_provider.dart`)와 같은 모양이다. 달라야 하는 것은 셋이다.

- **받은 달은 다시 안 받는다.** 컨트롤러가 이미 가진 `MonthCards`의 `month`를 보고 **없는 달만** 묻는다. 그래서 줌·필터는 요청을 만들지 않는다.
- **달마다 한 번씩 묻는다.** 한 번에 31일을 넘길 수 없다(`RecordCardRepository.maxRangeDays`).
- **"오늘"은 `recordCardClockProvider`에서 받는다.** `DateTime.now()`를 직접 부르면 자정 근처에서 테스트가 흔들린다.

- [ ] **Step 4: 통과를 확인한다**

Run: `fvm flutter test test/record_card_provider_test.dart`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add lib/features/record_card/presentation/record_card_provider.dart test/record_card_provider_test.dart
git commit -m "📍 Feat: 받은 달을 들고 있다가 모자란 달만 받는다"
```

---

### Task 6: 선 아트 위젯과 날짜 칸

**Files:**
- Create: `lib/features/record_card/presentation/route_art_view.dart`
- Create: `lib/features/record_card/presentation/record_card_cell.dart`
- Modify: `lib/core/strings/app_strings.dart` (정렬 위치에)
- Test: `test/record_card_cell_test.dart`

**Interfaces:**
- Consumes: Task 1의 `RouteArt` · `fitRoute`, Task 2의 `RecordCard`.
- Produces:
  - `class RouteArtView extends StatelessWidget` — `{required RouteArt art, required Color color, double strokeWidth = 2}`
  - `class RecordCardCell extends StatelessWidget` — `{required DateTime day, required List<RecordCard> cards, required bool showDayNumber, required VoidCallback? onTap}`
  - `AppStrings.recordCardEmptyTitle` · `recordCardEmptyAction` · `recordCardMonthCount(int)` · `recordCardCellSemantics({required DateTime day, required int count})`
  - ⚠️ 탭 이름은 **이미 있다** — `AppStrings.tabRecordCard`. 새로 만들지 않는다.

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `test/record_card_cell_test.dart`

```dart
testWidgets('사진이 있으면 썸네일을 그린다', (tester) async { /* Image 위젯이 있다 */ });

testWidgets('⚠️ 사진이 없으면 선 아트를 그린다 — 빈 날처럼 보이면 안 된다', (tester) async {
  expect(find.byType(RouteArtView), findsOneWidget);
});

testWidgets('카드가 없는 날은 날짜만 있다', (tester) async {
  expect(find.byType(RouteArtView), findsNothing);
});

testWidgets('하루에 둘이면 개수 배지가 뜬다', (tester) async { /* '2' */ });

testWidgets('하나면 배지가 없다', (tester) async { /* '1'이 없다 */ });

testWidgets('showDayNumber가 false면 날짜를 안 그린다', (tester) async {
  // 분기 보기에서는 칸이 26dp쯤이라 숫자가 안 읽힌다
});

testWidgets('⚠️ 스크린리더가 날짜와 장수를 읽는다', (tester) async {
  // Semantics(label: ..., container: true). container를 빼면 라벨이
  // 조상에 얹히기만 해서 아무것도 안 읽힌다(runner_avatar.dart:41-46).
});
```

- [ ] **Step 2: 실패를 확인한다**

Run: `fvm flutter test test/record_card_cell_test.dart`
Expected: FAIL — `RecordCardCell`이 없다

- [ ] **Step 3: 위젯 둘을 쓴다**

`RouteArtView`는 `CustomPainter` 하나다. `fitRoute`로 받은 픽셀 좌표를 `Path`로 잇고, **조각마다 `moveTo`로 새로 시작한다** — 안 그러면 일시정지로 끊긴 데가 직선으로 이어진다. 점이 하나뿐인 조각은 작은 원을 그린다. `shouldRepaint`는 `art`·`color`·`strokeWidth`를 견준다.

썸네일은 **`ProfilePhotoImage`로 감싸고 `ResizeImage`로 줄인다**(`core/widgets/profile_photo_image.dart`). 서명이 붙은 주소를 매번 다시 받지 않게 하려는 것이다. Fake는 번들 에셋을 주므로 **이번 라운드에는 이 길이 검증되지 않는다** — 주석에 적는다.

- [ ] **Step 4: 통과를 확인한다**

Run: `fvm flutter test test/record_card_cell_test.dart`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add lib/features/record_card/presentation/route_art_view.dart lib/features/record_card/presentation/record_card_cell.dart lib/core/strings/app_strings.dart test/record_card_cell_test.dart
git commit -m "📍 Feat: 날짜 칸에 사진이나 달린 모양을 그린다"
```

---

### Task 7: 캘린더와 그날 시트

**Files:**
- Create: `lib/features/record_card/presentation/record_card_calendar.dart`
- Create: `lib/features/record_card/presentation/day_cards_sheet.dart`
- Test: `test/record_card_calendar_test.dart`

**Interfaces:**
- Consumes: Task 4의 `RecordCardData` · `CalendarZoom` · `zoomFor`, Task 6의 `RecordCardCell`.
- Produces:
  - `class RecordCardCalendar extends StatelessWidget` — `{required RecordCardData data, required ValueChanged<RecordCard> onOpen, required ValueChanged<DateTime> onEmptyDay, required ValueChanged<CalendarZoom> onZoom, required VoidCallback onLoadOlder}`
  - `class DayCardsSheet extends StatelessWidget` — `{required DateTime day, required List<RecordCard> cards, required ValueChanged<RecordCard> onOpen}`
  - `Future<void> showDayCardsSheet(BuildContext, {required DateTime day, required List<RecordCard> cards, required ValueChanged<RecordCard> onOpen})` — `showModalBottomSheet`로 위를 띄운다
  - `AppStrings.recordCardDaySheetTitle(DateTime)` (정렬 위치에)

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `test/record_card_calendar_test.dart`

```dart
testWidgets('달 머리에 카드 수가 선다', (tester) async { /* '카드 18장' */ });

testWidgets('요일 머리가 있다', (tester) async { /* '일' '월' … '토' */ });

testWidgets('1일이 그 달의 요일 자리에서 시작한다', (tester) async {
  // 2026-09-01이 화요일이면 앞 두 칸이 비어 있다
});

testWidgets('⚠️ 분기 보기에서는 날짜 숫자가 없다', (tester) async { /* zoom: quarter */ });

testWidgets('카드가 하나인 날을 누르면 바로 그 카드가 열린다', (tester) async {
  expect(opened?.id, 7);
});

testWidgets('⚠️ 카드가 둘인 날을 누르면 시트가 뜬다 — 두 번째가 갇히면 안 된다', (tester) async {
  expect(find.byType(DayCardsSheet), findsOneWidget);
});

testWidgets('기록이 있는 빈 날을 누르면 onEmptyDay가 불린다', (tester) async { /* 그 날짜로 */ });

testWidgets('⚠️ 필터로 0장이 된 달도 머리와 칸이 남는다', (tester) async {
  // '카드 0장'이 있고, 그 달의 날짜 칸도 그대로 있다
});
```

- [ ] **Step 2: 실패를 확인한다**

Run: `fvm flutter test test/record_card_calendar_test.dart`
Expected: FAIL — `RecordCardCalendar`가 없다

- [ ] **Step 3: 캘린더를 쓴다**

세로로 이어지는 `ListView`에 달마다 **머리 + 7열 그리드**를 얹는다. 그리드는 `GridView.count(crossAxisCount: 7, shrinkWrap: true, physics: NeverScrollableScrollPhysics())`다 — 바깥 `ListView`가 스크롤을 맡는다.

칸 비는 **월 보기 `43:62`**, 분기 보기는 그 **0.6배**다. 세 달이 한 화면에 들어오는 것이 기준이고, 기기에서 보고 다듬는다.

핀치는 `GestureDetector(onScaleUpdate:)`로 받되 **`details.pointerCount < 2`면 무시한다** — 안 그러면 세로 스크롤을 빼앗는다. `zoomFor(현재, details.scale)`의 답이 달라졌을 때만 `onZoom`을 부른다.

시트는 `showModalBottomSheet`다. 줄마다 시작 시각·거리·유형을 보여준다.

- [ ] **Step 4: 통과를 확인한다**

Run: `fvm flutter test test/record_card_calendar_test.dart`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add lib/features/record_card/presentation/record_card_calendar.dart lib/features/record_card/presentation/day_cards_sheet.dart test/record_card_calendar_test.dart
git commit -m "📍 Feat: 기록카드를 월 달력으로 늘어놓고 오므리면 분기로 본다"
```

---

### Task 8: 탭 화면과 라우트, iOS 탭 되살리기

**Files:**
- Create: `lib/features/record_card/presentation/record_card_page.dart`
- Create: `lib/features/record_card/presentation/activity_filter.dart`
- Modify: `lib/app/router/app_router.dart:248-261` — `ComingSoonPage` 교체, `if (showRecordCardTab)` 제거
- Modify: `lib/app/router/app_shell.dart:24-27` — `showRecordCardTab`을 `true`로, `TODO(되살리기)` 제거
- Modify: `lib/app/router/app_routes.dart` — `recordCardDetail` 추가 (정렬 위치에)
- Modify: `test/widget_test.dart` — iOS 탭 검사 제거
- Test: `test/record_card_page_test.dart`

**Interfaces:**
- Consumes: Task 5의 `recordCardControllerProvider`, Task 7의 `RecordCardCalendar`.
- Produces: `AppRoutes.recordCardDetail = '/record-card/:id'` (Task 9가 꽂는다)

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `test/record_card_page_test.dart`

```dart
testWidgets('받는 동안 로딩을 보여준다', (tester) async { /* CircularProgressIndicator */ });

testWidgets('실패하면 오류와 다시 시도가 뜬다', (tester) async { /* failWith: network */ });

testWidgets('⚠️ 카드가 하나도 없어도 달력은 남는다', (tester) async {
  expect(find.byType(RecordCardCalendar), findsOneWidget);
  expect(find.text(AppStrings.recordCardEmptyTitle), findsOneWidget);
});

testWidgets('⚠️ 필터로 0장이 된 것은 빈 상태가 아니다', (tester) async {
  // 카드는 있는데 유형 필터로 0장 → 안내 문구가 뜨면 안 된다
  expect(find.text(AppStrings.recordCardEmptyTitle), findsNothing);
});

testWidgets('유형 칩은 하나만 고를 수 있다', (tester) async { /* 일상 → 대회 → 일상 해제 */ });
```

- [ ] **Step 2: 실패를 확인한다**

Run: `fvm flutter test test/record_card_page_test.dart`
Expected: FAIL — `RecordCardPage`가 없다

- [ ] **Step 3: 탭 화면을 쓰고 라우트를 꽂는다**

`RecordPage`(기록 탭)와 같은 모양이다 — `switch`로 **loading / data / error 세 갈래**를 빠짐없이 처리한다.

**빈 상태와 필터 0장을 가른다.** 안내 문구는 `RecordCardData.months`가 전부 비었을 때만 띄운다. `visible`이 비었는지로 판단하면 필터를 건 사람에게 "아직 없어요"가 뜬다.

⚠️ **`showRecordCardTab`을 지우지 않고 `true`로만 바꾼다.** 심사에서 UGC(신고·차단 없음)로 걸리면 **되돌릴 손잡이**가 필요하다. 그 이유를 주석에 적는다.

- [ ] **Step 4: 통과를 확인한다**

Run: `fvm flutter test test/record_card_page_test.dart test/widget_test.dart`
Expected: PASS — iOS 탭 검사를 지웠으므로 `widget_test`도 함께 돈다

- [ ] **Step 5: 커밋**

```bash
git add lib/features/record_card/presentation/record_card_page.dart lib/features/record_card/presentation/activity_filter.dart lib/app/router test/record_card_page_test.dart test/widget_test.dart
git commit -m "📍 Feat: 기록카드 탭을 준비중 화면에서 꺼낸다"
```

---

### Task 9: 카드 상세 (읽기 전용)

**Files:**
- Create: `lib/features/record_card/presentation/card_detail_page.dart`
- Create: `lib/features/record_card/presentation/card_media_pager.dart`
- Modify: `lib/app/router/app_router.dart` — `AppRoutes.recordCardDetail`을 **탭 셸 밖에** 단다
- Test: `test/record_card_detail_test.dart`

**Interfaces:**
- Consumes: Task 1의 `RecordCard`, Task 6의 `RouteArtView`, Task 8의 `AppRoutes.recordCardDetail`.
- Produces: `class CardMediaPager extends StatefulWidget` — `{required RecordCard card}` (Task 상세 바깥에서도 쓸 수 있게 공개한다)

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `test/record_card_detail_test.dart`

```dart
testWidgets('첫 장은 경로 선 아트다', (tester) async {
  expect(find.byType(RouteArtView), findsOneWidget);
});

testWidgets('⚠️ 사진이 없으면 한 장뿐이고 점도 안 뜬다', (tester) async { /* 점 표시 없음 */ });

testWidgets('사진이 5장이면 점이 6개다', (tester) async { /* 선 아트 1 + 사진 5 */ });

testWidgets('사진 장에서는 캡션이 보인다', (tester) async { /* 밀어서 2번째 장 */ });

testWidgets('지표 셋과 회고가 보인다', (tester) async { /* 거리·페이스·시간·회고 */ });

testWidgets('⚠️ 스크린리더가 몇 번째 장인지 읽는다', (tester) async { /* container: true */ });
```

- [ ] **Step 2: 실패를 확인한다**

Run: `fvm flutter test test/record_card_detail_test.dart`
Expected: FAIL — `CardDetailPage`가 없다

- [ ] **Step 3: 상세와 페이저를 쓴다**

`PageView`에 **선 아트 1장 + 사진 N장**을 9:16으로 싣는다. 점 표시는 장이 둘 이상일 때만 둔다.

⚠️ **지도 위젯을 쓰지 않는다.** `RunMapView`·`flutter_naver_map`을 타면 키 없는 빌드에서 안내가 뜨고, 지도 제스처가 페이저의 좌우 밀기를 빼앗는다.

이번 PR의 상세는 **읽기 전용**이다. `⋮`(수정·삭제)와 음악 줄은 다음 PR이다. 그 자리를 비워 두되 **없는 버튼을 그려 두지 않는다** — 눌러도 아무 데도 안 가는 버튼은 고장으로 읽힌다(`run_summary_page.dart`가 같은 이유를 적어 두었다).

- [ ] **Step 4: 통과를 확인한다**

Run: `fvm flutter test test/record_card_detail_test.dart`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add lib/features/record_card/presentation/card_detail_page.dart lib/features/record_card/presentation/card_media_pager.dart lib/app/router/app_router.dart test/record_card_detail_test.dart
git commit -m "📍 Feat: 기록카드 한 장을 열어 읽는다"
```

---

## 끝낸 뒤

- [ ] `fvm flutter analyze` — 경고 0개
- [ ] `fvm flutter test` — 전부 통과
- [ ] `fvm dart format lib test` — 바뀐 것 없음
- [ ] 에뮬레이터로 **다크·라이트 둘 다** 본다. 캘린더 · 분기 보기 · 그날 시트 · 상세 · 빈 상태 · 오류 화면.
- [ ] `git fetch upstream && git merge upstream/dev` — `app_strings.dart` · `app_routes.dart` · `app_router.dart`가 충돌하기 쉽다. **맨 끝에 붙이지 말고 정렬 위치에 넣는다.**
- [ ] PR을 `dev`로 연다. `.github/pull_request_template.md`의 6개 절을 채우고, **💬 리뷰 포인트**에 적는다.
  - 20파일 / 500줄 초과 사유
  - 분기 보기 칸 크기(0.6배)는 **디자인 확인이 필요한 값**이다
  - `showRecordCardTab`을 지우지 않고 `true`로 둔 이유 (심사 되돌림)
  - 선 아트의 `cos(위도)` 보정을 **앱이 하고 있다** — 서버가 정규화해 주면 어느 쪽이 할지 정해야 한다
  - `ProfilePhotoImage` 재사용은 **이번 라운드에 검증되지 않는다**(Fake가 번들 에셋을 쓴다)
