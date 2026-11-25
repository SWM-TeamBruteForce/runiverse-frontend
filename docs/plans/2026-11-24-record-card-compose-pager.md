# 기록카드 작성 슬라이드 · 달력 방향 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 기록카드 작성을 **좌우로 미는 한 화면**으로 바꾸고, 기록카드 탭 달력을 **현재 달이 맨 아래**가 되도록 뒤집는다.

**Architecture:** 작성 1(기록·유형·회고)과 작성 2(사진)를 **하나의 `PageView`**로 합친다. 사진 장은 `card_photo_slide.dart`로 떼어 내 작성 화면이 직접 세운다 — 별도 라우트(`/photos`)와 `CardPhotoPage`는 사라진다. 저장하기(공개 범위)는 **지금처럼 별도 화면**이고 `다음`이 그리로 간다. 달력은 `ListView(reverse: true)` 한 줄로 방향만 뒤집는다 — 상태·조회는 그대로다.

**Tech Stack:** Flutter · Riverpod 3(수동 provider) · go_router · Lucide

**Spec:** `docs/specs/2026-11-16-record-card-design.md` 6-2·6-3절 + 아래 「사용자가 정한 것」

## Global Constraints

- **flutter 실행 경로는 `C:\dev\runiverse\frontend\.fvm\flutter_sdk\bin\flutter.bat`다.** 이 워크트리에는 `.fvm`이 없다.
- 아이콘은 Lucide만. `Icons.*` 금지.
- 색·치수·타이포·문자열은 토큰으로만 — `context.appColorsV2` `AppSpacing` `AppTypographyV2` `AppStrings`.
- `AppStrings`에 새 문자열을 **정렬된 자리**에 넣는다.
- 화면은 loading·data·error 세 갈래와 empty, 다크·라이트를 모두 다룬다.
- 한 PR에 파일 20개·500줄을 넘기지 않는다.
- 커밋은 `<이모지> <type>: <설명>`. **AI를 공동 작성자로 넣지 않는다.**
- 다른 feature의 화면·위젯을 import하지 않는다(provider는 예외).

## 사용자가 정한 것 (2026-11-24)

| 항목 | 정해진 값 |
|---|---|
| 작성 1 → 사진 | `다음` 버튼이 아니라 **옆으로 민다** |
| 공개 범위·저장 | **지금처럼 별도 화면.** 오른쪽 위 `다음`이 거기로 간다 |
| 슬라이드 첫 장 | **지금 작성 1 내용 그대로**(러닝 선택·경로·지표·유형·회고), 그 장만 세로 스크롤 |
| 달력 방향 | **현재 달이 스크롤 맨 아래**, 과거는 위로 올려 본다 |

## Review Focus

1. **사진 장에서 뒤로가기** — 초안을 버릴지 묻는 문은 작성 1에만 있었다. 한 화면이 되면 사진 장에서 뒤로 눌러도 **그 문을 지나야 한다**(Task 3).
2. **마지막 사진을 지웠을 때 보고 있던 장** — 장 수가 줄어 현재 장이 범위를 벗어나면 빈 화면이 선다(Task 3).
3. **회고를 쓰다 옆으로 밀기** — 키보드가 뜬 채 넘어가면 포커스가 캡션 입력으로 끌려간다(Task 3).
4. **첫 장의 세로 스크롤과 가로 스와이프** — 첫 장이 세로로 길다. 세로로 끌었는데 장이 넘어가면 안 된다(Task 3).
5. **달을 하나만 들고 있을 때 더 받기** — 뒤집으면 더 받기 줄이 **맨 위**로 간다. 스크롤할 것이 없으면 보이지도 않는다(Task 1).

---

### Task 1: 달력을 아래에서 위로 쌓는다

**Files:**
- Modify: `lib/features/record_card/presentation/record_card_calendar.dart:57-88`
- Test: `test/record_card_calendar_test.dart`

**Interfaces:**
- Consumes: `RecordCardData.visible`(오름차순), `onLoadOlder`
- Produces: 없음 — 위젯 동작만 바뀐다

- [ ] **Step 1: 실패하는 테스트 둘을 쓴다**

```dart
testWidgets('이번 달이 지난달보다 아래에 있다', (tester) async {
  await pumpCalendar(tester, months: [DateTime(2026, 10), DateTime(2026, 11)]);

  final october = tester.getTopLeft(find.text('2026년 10월')).dy;
  final november = tester.getTopLeft(find.text('2026년 11월')).dy;

  expect(november, greaterThan(october));
});

testWidgets('더 받기 줄은 맨 위다', (tester) async {
  await pumpCalendar(tester, months: [DateTime(2026, 11)]);

  final footer = tester.getTopLeft(find.text(AppStrings.recordCardLoadOlder)).dy;
  final november = tester.getTopLeft(find.text('2026년 11월')).dy;

  expect(footer, lessThan(november));
});
```

- [ ] **Step 2: 실패를 본다.** Run: `C:\dev\runiverse\frontend\.fvm\flutter_sdk\bin\flutter.bat test test/record_card_calendar_test.dart`. 기대: 두 테스트 FAIL(지금은 최신 달이 위, 더 받기가 아래).

- [ ] **Step 3: `ListView.builder`에 `reverse: true`를 준다.** `months`는 지금처럼 `data.visible.reversed`다 — `reverse`가 index 0을 **맨 아래**에 놓으므로 최신 달이 아래로 간다. `onLoadOlder` 조건(`pixels >= maxScrollExtent - 200`)은 **그대로 둔다**: 뒤집힌 목록에서 `maxScrollExtent`는 위쪽 끝이다. 클래스 주석의 "⚠️ 최신 달이 위다"를 **아래다**로 고치고, 열었을 때 이번 달이 보이는 이유(스크롤 0이 곧 바닥)를 적는다.

- [ ] **Step 4: 통과를 본다.** Run: 같은 명령. 기대: PASS.

- [ ] **Step 5: 달력을 쓰는 화면 테스트가 그대로인지 본다.** Run: `... test test/record_card_page_test.dart test/record_card_cell_test.dart`. 기대: PASS.

- [ ] **Step 6: 커밋** — `🎨 Style: 달력을 현재 달부터 위로 거슬러 보게 한다`

---

### Task 2: 사진 한 장을 위젯으로 떼어낸다

**Files:**
- Create: `lib/features/record_card/presentation/card_photo_slide.dart`
- Modify: `lib/features/record_card/presentation/card_photo_page.dart`
- Test: `test/record_card_photo_slide_test.dart`

**Interfaces:**
- Consumes: `CardPhotoDraft`(`SavedPhoto`·`PickedPhoto`), `CardPhotoPan`
- Produces:
  - `class CardPhotoSlide extends StatelessWidget` — `({required CardPhotoDraft photo, required bool isCover, required ValueChanged<({double x, double y})> onPan, required VoidCallback onMakeCover, required VoidCallback onRemove})`
  - `class CardAddPhotoSlide extends StatelessWidget` — `({required bool first, required VoidCallback onPick})`. `first`가 참이면 `AppStrings.recordCardPhotoEmpty`를 함께 보인다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
testWidgets('첫 장이면 넣지 않아도 된다고 말한다', (tester) async {
  await pumpSlide(tester, CardAddPhotoSlide(first: true, onPick: () {}));
  expect(find.text(AppStrings.recordCardPhotoEmpty), findsOneWidget);
});

testWidgets('둘째 장부터는 그 말을 하지 않는다', (tester) async {
  await pumpSlide(tester, CardAddPhotoSlide(first: false, onPick: () {}));
  expect(find.text(AppStrings.recordCardPhotoEmpty), findsNothing);
});

testWidgets('지우기를 누르면 알린다', (tester) async {
  var removed = 0;
  await pumpSlide(tester, CardPhotoSlide(
    photo: const SavedPhoto(id: 'photo-1', url: 'https://example.invalid/a.jpg'),
    isCover: true,
    onPan: (_) {},
    onMakeCover: () {},
    onRemove: () => removed++,
  ));

  await tester.tap(find.text(AppStrings.recordCardPhotoRemove));
  expect(removed, 1);
});

testWidgets('⚠️ 대표인 장에는 대표로 지정하라는 버튼이 없다', (tester) async {
  await pumpSlide(tester, CardPhotoSlide(
    photo: const SavedPhoto(id: 'photo-1', url: 'https://example.invalid/a.jpg'),
    isCover: true,
    onPan: (_) {},
    onMakeCover: () {},
    onRemove: () {},
  ));

  expect(find.text(AppStrings.recordCardPhotoMakeCover), findsNothing);
});
```

- [ ] **Step 2: 실패를 본다.** Run: `... test test/record_card_photo_slide_test.dart`. 기대: FAIL — `card_photo_slide.dart`가 없다.

- [ ] **Step 3: 두 위젯을 만든다.** 지금 `card_photo_page.dart`가 한 장을 그리는 코드를 **그대로 옮긴다**. 상태(`PageController`·캡션 컨트롤러·고르는 중 깃발)는 옮기지 않는다 — 부르는 쪽이 든다. `SavedPhoto`는 끌 수 없다는 규칙(`card_photo_draft.dart`)을 여기서 지킨다.

- [ ] **Step 4: `CardPhotoPage`가 두 위젯을 쓰게 한다.** 화면 동작은 바뀌지 않는다.

- [ ] **Step 5: 통과를 본다.** Run: `... test test/record_card_photo_slide_test.dart test/record_card_photo_page_test.dart test/record_card_photo_pan_test.dart`. 기대: 전부 PASS.

- [ ] **Step 6: 커밋** — `🤖 Refactor: 사진 한 장을 작성 화면이 세울 수 있게 뗀다`

---

### Task 3: 작성 1에 사진 장을 붙인다

**Files:**
- Modify: `lib/features/record_card/presentation/card_compose_page.dart`
- Modify: `lib/core/strings/app_strings.dart`
- Test: `test/record_card_compose_page_test.dart`

**Interfaces:**
- Consumes: Task 2의 `CardPhotoSlide` · `CardAddPhotoSlide`
- Produces: `CardComposePage`가 `PageView`를 든다. 장 수 = `1 + photos.length + (photos.length < CardDraft.maxPhotos ? 1 : 0)`

- [ ] **Step 1: 실패하는 테스트 다섯을 쓴다**

```dart
testWidgets('옆으로 밀면 사진 장이 나온다', (tester) async {
  await pumpCompose(tester, withRecord: true);
  await tester.drag(find.byType(PageView), const Offset(-400, 0));
  await tester.pumpAndSettle();

  expect(find.byType(CardAddPhotoSlide), findsOneWidget);
});

testWidgets('다음은 사진이 아니라 저장하기로 간다', (tester) async {
  await pumpCompose(tester, withRecord: true, withReview: true, withActivity: true);
  await tester.tap(find.text(AppStrings.recordCardComposeNext));
  await tester.pumpAndSettle();

  expect(find.byType(CardPublishPage), findsOneWidget);
});

testWidgets('⚠️ 사진 장에서 뒤로 눌러도 버릴지 묻는다', (tester) async {
  await pumpCompose(tester, withRecord: true, withReview: true);
  await tester.drag(find.byType(PageView), const Offset(-400, 0));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(LucideIcons.chevronLeft));
  await tester.pumpAndSettle();

  expect(find.text(AppStrings.recordCardComposeDiscardTitle), findsOneWidget);
});

testWidgets('⚠️ 마지막 사진을 지우면 그 앞 장으로 당겨진다', (tester) async {
  await pumpCompose(tester, withRecord: true, photos: 1);
  await tester.drag(find.byType(PageView), const Offset(-400, 0));
  await tester.pumpAndSettle();
  await tester.tap(find.text(AppStrings.recordCardPhotoRemove));
  await tester.pumpAndSettle();

  expect(tester.takeException(), isNull);
  expect(find.byType(CardAddPhotoSlide), findsOneWidget);
});

testWidgets('⚠️ 첫 장을 세로로 끌어도 장이 넘어가지 않는다', (tester) async {
  await pumpCompose(tester, withRecord: true);
  await tester.drag(find.byType(PageView), const Offset(0, -300));
  await tester.pumpAndSettle();

  expect(find.byType(CardAddPhotoSlide), findsNothing);
});
```

- [ ] **Step 2: 실패를 본다.** Run: `... test test/record_card_compose_page_test.dart`. 기대: 다섯 모두 FAIL.

- [ ] **Step 3: `CardComposePage`를 `PageView`로 감싼다.**
  - 장 0은 지금의 본문 그대로, 세로 스크롤 안에 둔다.
  - 장 1부터는 `CardPhotoSlide`, 마지막은 `CardAddPhotoSlide`(사진이 `maxPhotos`면 없다).
  - `PageController`·캡션 `TextEditingController`·고르는 중 깃발을 `CardPhotoPage`에서 이 State로 옮긴다. **캡션 컨트롤러는 하나**를 두고 `text`를 갈아 끼운다(`card_photo_page.dart`의 ⚠️ 그대로).
  - 장이 바뀌면 `FocusScope.of(context).unfocus()` — 회고를 쓰다 밀었을 때 키보드가 캡션으로 따라붙지 않는다.
  - 사진이 지워져 현재 장이 범위를 벗어나면 `_page`를 **마지막 장으로 당긴다.**
  - AppBar 제목: 장 0이면 `recordCardComposeTitle`, 사진 장이면 `recordCardPhotoTitle(n, max)`.
  - 오른쪽 위 `다음`은 **어느 장에서나** `canProceed`면 저장하기로 간다.
  - 뒤로가기는 **장과 무관하게** 지금의 "버릴지 묻는" 문을 지난다.
  - 장 표시 점을 제목 아래에 둔다 — 새 문자열은 쓰지 않는다(그림만).

- [ ] **Step 4: 통과를 본다.** Run: `... test test/record_card_compose_page_test.dart`. 기대: 전부 PASS.

- [ ] **Step 5: 작성·수정 흐름 테스트를 본다.** Run: `... test test/record_card_compose_flow_test.dart test/record_card_edit_flow_test.dart`. 기대: `/photos`를 거치던 단계가 FAIL한다 — **Task 4에서 고친다.** 실패 목록을 적어 둔다.

- [ ] **Step 6: 커밋** — `📍 Feat: 작성 화면에서 옆으로 밀어 사진을 넣는다`

---

### Task 4: 사진 라우트를 걷어낸다

**Files:**
- Delete: `lib/features/record_card/presentation/card_photo_page.dart`
- Delete: `test/record_card_photo_page_test.dart`
- Modify: `lib/app/router/app_routes.dart:139-145,174-181`
- Modify: `lib/app/router/app_router.dart:146-149,178-183`
- Test: `test/record_card_compose_flow_test.dart` · `test/record_card_edit_flow_test.dart`

**Interfaces:**
- Consumes: Task 3의 `CardComposePage`
- Produces: `AppRoutes.recordCardNewPhotos` · `recordCardEditPhotos` · `recordCardEditPhotosOf`가 **사라진다**

- [ ] **Step 1: 흐름 테스트를 새 길로 고친다.** `/photos`로 밀던 자리를 `PageView` 밀기로 바꾼다. 작성은 `목록에서 고르기 → 유형·회고 → 옆으로 밀어 사진 → 다음 → 저장`, 수정은 `상세의 ⋮ → 수정 → 옆으로 밀어 사진 → 다음 → 저장`이다.

- [ ] **Step 2: 실패를 본다.** Run: `... test test/record_card_compose_flow_test.dart test/record_card_edit_flow_test.dart`. 기대: FAIL — 아직 라우트가 남아 있다.

- [ ] **Step 3: 라우트 둘과 화면 파일을 지운다.** `AppRoutes`의 사진 라우트 상수·헬퍼와 `app_router.dart`의 등록 둘을 걷어낸다. 작성 2를 가리키던 주석(`card_publish_page.dart`·`card_draft_provider.dart`의 "작성 2")을 **"작성 화면의 사진 장"으로 고친다.**

- [ ] **Step 4: 통과를 본다.** Run: `... test test/record_card_compose_flow_test.dart test/record_card_edit_flow_test.dart`. 기대: PASS.

- [ ] **Step 5: 전체 테스트와 analyze.** Run: `... test` 그리고 `... analyze`. 기대: 전부 PASS, 경고 0.

- [ ] **Step 6: 커밋** — `✂️ Remove: 사진 라우트를 걷어낸다`

---

## PR 경계

파일 10개 안쪽이라 **한 PR**이다. 묶음 1~6의 PR과 묶음 7(읽기 연동) PR **뒤에 선다** — 같은 작성 화면을 건드린다.

## Self-review

**덮임**: 사용자 요청 ①(옆 슬라이드) → Task 2·3·4 · ②(달력 방향) → Task 1. 「사용자가 정한 것」 네 줄 모두 작업이 있다.

**빠뜨린 것 하나**: 묶음 8(쓰기 연동)이 `NewCardPhoto`에 `fileName`을 요구한다. 지금 사진 장은 파일 이름을 들지 않는다 — **이 계획에서는 건드리지 않는다.** 화면 구조와 무관하고, 묶음 8이 `PickedImage.path`에서 뽑으면 된다.

**타입 일관성**: `CardPhotoSlide`·`CardAddPhotoSlide`가 Task 2에서 정의되고 Task 3에서만 쓰인다. `CardDraft.maxPhotos`는 기존 상수를 그대로 쓴다.

**비례**: 작업 5개가 아니라 **4개**다. 각 단계는 테스트 이름과 명령까지만 적었다 — 본문 코드를 넣은 자리는 없다.
