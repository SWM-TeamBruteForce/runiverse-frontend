# 기록카드 수정 · 삭제 구현 계획 (PR 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 만든 카드를 **고치고 지운다.** 작성 세 화면을 그대로 다시 쓴다.

**Architecture:** 수정은 새 화면을 만들지 않는다 — 작성 1·2·3이 `cardId`를 이미
받고, `cardDraftProvider`가 그 번호로 family를 가른다. 더할 것은 ①카드에서 초안을
**씨 뿌리기** ②기록 선택기를 **읽기 전용**으로 바꾸기 ③`update`·`delete` ④상세의
`⋮`다. 가장 큰 모델 변경은 **초안의 사진이 두 종류**가 되는 것이다 — 이미 올라간
사진(주소)과 새로 고른 사진(파일).

**Tech Stack:** Flutter + fvm · Riverpod 3 수동 provider · go_router · Lucide 아이콘

**Spec:** `docs/specs/2026-11-16-record-card-design.md` 6-6절 · 7절(초안 수명)

## 사용자가 정한 것 (2026-11-19)

- **음악 관련 알림은 전부 묶음 5로 미룬다.** `RecordCard`에 음악 상태 필드가 없고
  (`music_generation.dart`도 없다) 설계 7절이 묶음 5로 잡아 뒀다. **없는 상태를
  추측해 경고하지 않는다** — 6-6의 "음악이 있고 입력이 바뀌면 알린다"와 "생성
  중에도 고치고 지울 수 있다(한 줄로 알린다)"는 그때 붙인다.
- **사진 수정은 "남길 사진 전체"를 보낸다.** 바뀐 것만 보내지 않는다 — 서버가
  차집합으로 지우고, 앱은 변경을 추적하지 않으며, 순서 바꾸기가 공짜다.

## Global Constraints

- UI 텍스트는 **한국어**, 전부 `AppStrings`에. **정렬 위치에 넣는다.**
- 색·치수·타이포는 토큰만. `core/theme/tokens/` 밖에서 `Color(0x...)` 금지.
- 아이콘은 **Lucide만**. `Icons.*` 금지.
- `StateProvider` · `StateNotifierProvider` 금지.
- 화면은 **loading / data / error 3분기**. **empty + 다크·라이트** 둘 다.
- `domain/`은 **순수 Dart만**. `dart:io` · `dart:ui` 금지.
- 의존 방향 `presentation → domain ← data`. 다른 feature의 **화면·위젯** import 금지.
- 이 worktree에서 flutter는 `C:\dev\runiverse\frontend\.fvm\flutter_sdk\bin\flutter.bat`
  (`.fvm`은 git 무시라 원본에만 있다).
- 커밋: `<이모지> <Type>: <한국어 설명>`. **AI 공동 작성자 트레일러·푸터 금지.**
- 사진 **최대 5장** · 캡션 **100자** · 회고 **1000자** — 수정에서도 같다.

## Review Focus

설계가 함축하지만 어느 Task의 테스트도 건드리지 않는다. 사람이 먼저 맞을 순서대로.

1. **수정 중에 새 카드 작성으로 들어갔다 온다.** family가 가르므로 섞이면 안 된다
   (설계 7절). 섞이면 **남의 카드 글이 새 카드에 붙는다.** → Task 2에 테스트.
2. **기존 사진만 남기고 저장한다.** 새로 고른 것이 하나도 없으면 자르기가 한 번도
   안 돌아야 한다 — 이미 잘린 것을 다시 자르면 **9:16을 또 잘라** 그림이 좁아진다.
   → Task 5에 테스트.
3. **수정하다 뒤로 나간다.** 초안이 남으면 다음에 그 카드를 열었을 때 **고치다 만
   것이 되살아난다.** 작성 1의 이어 쓰기 시트가 수정에서도 맞는 말인지. → Task 3.
4. **지운 카드의 상세에 머문다.** 삭제 후 되돌아가지 않으면 **없는 카드를 보고
   있다** — 거기서 수정을 누르면 404다. → Task 6에 테스트.
5. **사진을 전부 지우고 저장한다.** 사진 0장은 작성에서 허용이다. 수정에서도
   저장되어야 하고, **`photos: []`가 "안 바꿈"으로 읽히면 안 된다.** → Task 5.

---

## 파일 구조

| 파일 | 맡는 일 |
|---|---|
| `domain/card_photo_draft.dart` **(수정)** | 사진 한 장이 **이미 올린 것**이거나 **새로 고른 것** |
| `domain/card_draft.dart` **(수정)** | `fromCard` — 카드에서 초안을 뜬다 |
| `domain/edit_record_card.dart` **(신규)** | 수정 요청 값 (남길 사진 전체) |
| `domain/record_card_repository.dart` **(수정)** | `update` · `delete` |
| `data/fake_record_card_repository.dart` **(수정)** | 둘의 가짜 구현 |
| `presentation/card_draft_provider.dart` **(수정)** | `seed(card)` — 한 번만 뿌린다 |
| `presentation/card_save_provider.dart` **(수정)** | `cardId`가 있으면 `update` |
| `presentation/card_delete_provider.dart` **(신규)** | 삭제 + 상태 |
| `presentation/card_compose_page.dart` **(수정)** | 수정이면 기록 선택기를 읽기 전용으로 |
| `presentation/card_photo_page.dart` **(수정)** | 두 종류 사진을 함께 그린다 |
| `presentation/card_detail_page.dart` **(수정)** | `⋮` → 수정 · 삭제 |
| `app/router/app_routes.dart` · `app_router.dart` **(수정)** | `/record-card/card/:id/edit{,/photos,/publish}` |
| `core/strings/app_strings.dart` **(수정)** | 수정·삭제 문구 |

---

### Task 1: 초안의 사진이 두 종류가 된다

수정에서 작성 2를 다시 쓰는데 기존 사진이 안 보이면 **3장짜리 카드가 0장으로
열린다.** 그래서 초안이 **이미 올린 사진(주소)**과 **새로 고른 사진(파일)**을
함께 담아야 한다.

**Files:**
- Modify: `lib/features/record_card/domain/card_photo_draft.dart`
- Test: `test/record_card_draft_test.dart`

**Interfaces:**
- Consumes: `PickedImage` · `RecordCardPhoto`
- Produces:
  ```dart
  /// 초안에 담긴 사진 한 장. 둘 중 하나다.
  sealed class CardPhotoDraft {
    const CardPhotoDraft({required this.caption});
    final String caption;
    static const captionMaxLength = 100;
    static const aspectRatio = 9 / 16;
    CardPhotoDraft withCaption(String caption);
  }

  /// 이미 올라가 있는 사진. **다시 자르지 않는다.**
  class SavedPhoto extends CardPhotoDraft {
    const SavedPhoto({required this.id, required this.url,
                      this.thumbnailUrl, super.caption = ''});
    final int id; final String url; final String? thumbnailUrl;
  }

  /// 방금 고른 사진. 저장할 때 자른다.
  class PickedPhoto extends CardPhotoDraft {
    const PickedPhoto({required this.image, super.caption = '',
                       this.alignX = 0, this.alignY = 0});
    final PickedImage image; final double alignX, alignY;
    PickedPhoto withAlign({double? alignX, double? alignY});
  }
  ```

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
group('초안의 사진', () {
  test('이미 올린 사진은 주소를 든다', () {
    const photo = SavedPhoto(id: 7, url: 'https://x/a.jpg', caption: '바다');
    expect(photo.caption, '바다');
    expect(photo.url, 'https://x/a.jpg');
  });

  test('새로 고른 사진은 파일과 민 위치를 든다', () {
    final photo = PickedPhoto(image: _image(), alignX: -0.5);
    expect(photo.alignX, -0.5);
    expect(photo.alignY, 0);
  });

  test('캡션은 종류와 상관없이 바뀐다', () {
    expect(const SavedPhoto(id: 7, url: 'u').withCaption('가').caption, '가');
    expect(PickedPhoto(image: _image()).withCaption('가').caption, '가');
  });

  // ⚠️ 민 위치는 새로 고른 것에만 있다 — 이미 잘려 올라간 것은 옮길 데가 없다.
  test('⚠️ 민 위치를 바꿔도 종류는 그대로다', () {
    final moved = PickedPhoto(image: _image()).withAlign(alignX: 1);
    expect(moved, isA<PickedPhoto>());
    expect(moved.alignX, 1);
  });

  test('상한은 그대로다', () {
    expect(CardPhotoDraft.captionMaxLength, 100);
    expect(CardPhotoDraft.aspectRatio, closeTo(9 / 16, 1e-9));
  });
});
```

- [ ] **Step 2: 실패를 확인한다**

Run: `<flutter> test test/record_card_draft_test.dart`
Expected: FAIL — `SavedPhoto` · `PickedPhoto`가 없다

- [ ] **Step 3: `CardPhotoDraft`를 sealed로 가른다**

`sealed class` + 두 자식. `copyWith` 대신 `withCaption`·`withAlign`을 둔다 —
종류가 섞이면 안 되므로 **각 자식이 자기 종류를 돌려준다.**

- [ ] **Step 4: 부르는 쪽을 고친다**

`card_draft.dart`·`card_draft_provider.dart`·`card_photo_page.dart`·
`card_save_provider.dart`가 `CardPhotoDraft(image:)`를 쓴다. `PickedPhoto`로
바꾸고, `photo.image`를 쓰는 자리는 `switch`로 가른다.

- [ ] **Step 5: 통과를 확인한다**

Run: `<flutter> test` 그리고 `<flutter> analyze`
Expected: 전체 통과 · `No issues found!` (기존 작성 흐름이 안 깨졌다)

- [ ] **Step 6: 커밋**

```bash
git commit -m "🤖 Refactor: 초안의 사진이 올린 것과 고른 것으로 갈린다"
```

---

### Task 2: 카드에서 초안을 뜬다

**Files:**
- Modify: `lib/features/record_card/domain/card_draft.dart`
- Modify: `lib/features/record_card/presentation/card_draft_provider.dart`
- Test: `test/record_card_draft_test.dart` · `test/record_card_draft_provider_test.dart`

**Interfaces:**
- Consumes: `RecordCard` · Task 1의 `SavedPhoto`
- Produces:
  ```dart
  /// 카드를 고치려고 뜬 초안. 러닝 기록은 **못 바꾼다**(설계 6-6).
  factory CardDraft.fromCard(RecordCard card, {required RunRecord record});

  /// 카드 값을 초안에 **한 번만** 뿌린다. 이미 손댄 초안은 건드리지 않는다.
  void seed(RecordCard card, {required RunRecord record});
  ```

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
test('카드의 값이 그대로 초안에 들어온다', () {
  final draft = CardDraft.fromCard(_card(), record: _record());
  expect(draft.activity, _card().activity);
  expect(draft.visibility, _card().visibility);
  expect(draft.reviewText, _card().reviewText);
  expect(draft.photos, hasLength(_card().photos.length));
  expect(draft.photos.first, isA<SavedPhoto>());
  expect(draft.record?.id, _record().id);
});

test('⚠️ 뜬 초안은 아직 손대지 않은 것이다', () {
  // `isDirty`가 참이면 들어오자마자 "이어 쓸까요?"를 묻는다 — 고치러 들어온
  // 사람에게 아무 말이나 묻는 꼴이다.
  expect(CardDraft.fromCard(_card(), record: _record()).isDirty, isFalse);
});

test('카드의 경로가 초안에 실린다', () {
  expect(CardDraft.fromCard(_card(), record: _record()).route,
         same(_card().route));
});
```

provider:

```dart
test('seed가 카드 값을 뿌린다', () {
  notifier(7).seed(_card(id: 7), record: _record());
  expect(draft(7).reviewText, _card(id: 7).reviewText);
});

// ⚠️ Review Focus 1
test('⚠️ 수정 초안과 새 카드 초안이 섞이지 않는다', () {
  notifier(7).seed(_card(id: 7), record: _record());
  notifier().setReview('새로 쓰는 글');

  expect(draft(7).reviewText, isNot('새로 쓰는 글'));
  expect(draft().photos, isEmpty);
});

test('⚠️ 이미 고친 초안에는 다시 뿌리지 않는다', () {
  // 사진 화면에 갔다 돌아올 때마다 다시 뿌리면 **고친 것이 되돌아간다.**
  notifier(7).seed(_card(id: 7), record: _record());
  notifier(7).setReview('고친 글');

  notifier(7).seed(_card(id: 7), record: _record());

  expect(draft(7).reviewText, '고친 글');
});
```

- [ ] **Step 2: 실패를 확인한다**

Run: `<flutter> test test/record_card_draft_test.dart test/record_card_draft_provider_test.dart`
Expected: FAIL — `fromCard` · `seed`가 없다

- [ ] **Step 3: `CardDraft.fromCard`를 만든다**

사진은 `SavedPhoto`로 옮긴다. ⚠️ **`isDirty`가 거짓이어야 한다** — `fromCard`가
채운 값은 "앱이 꽂아 준 것"이고, 참이면 들어오자마자 이어 쓰기 시트가 뜬다.
`isDirty`를 "뜬 뒤로 바뀌었나"로 바꾸려면 기준값이 필요하므로, **`_seeded`
플래그를 초안에 둔다**(`fromCard`가 세우고 모든 `set*`이 내린다).

- [ ] **Step 4: `seed`를 만든다**

**이미 손댄 초안이면 아무 일도 하지 않는다.** 화면이 매번 부르므로, 안 막으면
사진 화면에서 돌아올 때마다 고친 것이 되돌아간다.

- [ ] **Step 5: 통과를 확인한다**

Run: `<flutter> test test/record_card_draft_test.dart test/record_card_draft_provider_test.dart`
Expected: PASS

- [ ] **Step 6: 커밋**

```bash
git commit -m "📍 Feat: 카드에서 초안을 뜬다"
```

---

### Task 3: 작성 1이 수정 모드를 안다

**Files:**
- Modify: `lib/features/record_card/presentation/card_compose_page.dart`
- Modify: `lib/core/strings/app_strings.dart`
- Test: `test/record_card_compose_page_test.dart`

**새 `AppStrings`:**

```dart
static const recordCardEditTitle = '기록카드 고치기';
/// ⚠️ 왜 못 바꾸는지 말한다. 그냥 잠가 두면 고장으로 읽힌다.
static const recordCardEditRecordLocked = '러닝 기록은 바꿀 수 없어요';
```

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
testWidgets('⚠️ 수정이면 날짜도 기록도 못 고른다', (tester) async {
  // `unique(running_record_id)` 때문에 카드 있는 기록으로 옮기면 서버가
  // 거절하고, 바꾸면 지표·경로가 통째로 달라져 다른 카드가 된다(설계 6-6).
  await _pump(tester, cardId: 7, card: _card(id: 7));

  expect(find.text(AppStrings.recordCardEditRecordLocked), findsOne);
  await tester.tap(find.byType(_DateRowFinder));   // 날짜 줄
  await tester.pumpAndSettle();
  expect(find.text(AppStrings.recordCardComposeDateSheet), findsNothing);
});

testWidgets('수정이면 제목이 다르다', (tester) async {
  await _pump(tester, cardId: 7, card: _card(id: 7));
  expect(find.text(AppStrings.recordCardEditTitle), findsOne);
  expect(find.text(AppStrings.recordCardComposeTitle), findsNothing);
});

testWidgets('고른 기록이 읽기 전용으로 보인다', (tester) async {
  await _pump(tester, cardId: 7, card: _card(id: 7));
  // 목록이 아니라 한 줄이다 — 고를 것이 없다.
  expect(find.byType(RadioListTile<int>), findsNothing);
  expect(find.textContaining('km'), findsWidgets);
});

// ⚠️ Review Focus 3
testWidgets('⚠️ 수정에서는 이어 쓰기를 묻지 않는다', (tester) async {
  // 뜬 초안은 손대지 않은 것이다. 물으면 고치러 들어온 사람에게 아무 말이나
  // 묻는 꼴이다.
  await _pump(tester, cardId: 7, card: _card(id: 7));
  expect(find.text(AppStrings.recordCardComposeResumeTitle), findsNothing);
});

testWidgets('수정에서 뒤로 나가면 고친 것을 버릴지 묻는다', (tester) async {
  await _pump(tester, cardId: 7, card: _card(id: 7));
  await tester.enterText(find.byType(TextField), '고친 글');
  await tester.pump();

  await tester.tap(find.byIcon(LucideIcons.chevronLeft));
  await tester.pumpAndSettle();

  expect(find.text(AppStrings.recordCardComposeDiscardTitle), findsOne);
});
```

- [ ] **Step 2: 실패를 확인한다**

Run: `<flutter> test test/record_card_compose_page_test.dart`
Expected: FAIL — 수정 모드가 없다

- [ ] **Step 3: 문구를 넣고 화면을 가른다**

`cardId != null`이면: 제목이 `recordCardEditTitle`, 날짜 줄은 **안 눌린다**,
기록 목록 대신 **고른 기록 한 줄 + `recordCardEditRecordLocked`**, 이어 쓰기
시트는 **안 띄운다**(뜬 초안은 손대지 않은 것이다).

`initState`에서 `seed`를 부른다 — 화면이 카드를 받아야 하므로 `card` 인자를 더한다.

- [ ] **Step 4: 통과를 확인한다**

Run: `<flutter> test test/record_card_compose_page_test.dart`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git commit -m "📍 Feat: 수정은 러닝 기록을 잠그고 이어 쓰기를 묻지 않는다"
```

---

### Task 4: 작성 2가 두 종류 사진을 그린다

**Files:**
- Modify: `lib/features/record_card/presentation/card_photo_page.dart`
- Modify: `lib/features/record_card/presentation/card_photo_pan.dart`
- Test: `test/record_card_photo_page_test.dart`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
testWidgets('이미 올린 사진이 보인다', (tester) async {
  await _pump(tester, draft: _ready(saved: 2));
  expect(find.text(AppStrings.recordCardPhotoTitle(2, 5)), findsOne);
  expect(tester.takeException(), isNull);
});

testWidgets('⚠️ 이미 올린 사진은 밀 수 없다', (tester) async {
  // 이미 9:16으로 잘려 올라갔다 — 옮길 데가 없다. 끌기를 달면 아무 일도
  // 안 일어나는 제스처가 된다.
  await _pump(tester, draft: _ready(saved: 1));
  expect(find.byType(GestureDetector), findsNothing);
  expect(find.text(AppStrings.recordCardPhotoPanHint), findsNothing);
});

testWidgets('새로 고른 사진은 밀 수 있다', (tester) async {
  await _pump(tester, draft: _ready(picked: 1));
  expect(find.text(AppStrings.recordCardPhotoPanHint), findsOne);
});

testWidgets('올린 것과 고른 것이 섞여도 캡션이 따로 간다', (tester) async {
  final container = await _pump(
    tester,
    draft: _ready(saved: 1, picked: 1, captions: ['옛것', '새것']),
  );
  expect(_fieldText(tester), '옛것');

  await tester.drag(find.byType(PageView), const Offset(-600, 0));
  await tester.pumpAndSettle();

  expect(_fieldText(tester), '새것');
});

testWidgets('올린 사진을 지울 수 있다', (tester) async {
  final container = await _pump(tester, draft: _ready(saved: 2));
  await _tapBelow(tester, find.text(AppStrings.recordCardPhotoRemove));
  expect(container.read(cardDraftProvider(7)).photos, hasLength(1));
});
```

- [ ] **Step 2: 실패를 확인한다**

Run: `<flutter> test test/record_card_photo_page_test.dart`
Expected: FAIL

- [ ] **Step 3: 두 종류를 그린다**

`switch`로 가른다 — `SavedPhoto`는 `cardThumbnail(context, url)`로 그리고
**끌기를 달지 않는다**, `PickedPhoto`는 지금처럼 `CardPhotoPan`이다. 안내
문구(`recordCardPhotoPanHint`)는 **밀 수 있는 장에서만** 둔다.

`CardPhotoPan`은 `PickedPhoto`만 받게 좁힌다.

- [ ] **Step 4: 통과를 확인한다**

Run: `<flutter> test test/record_card_photo_page_test.dart`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git commit -m "📍 Feat: 작성 2가 올린 사진과 고른 사진을 함께 그린다"
```

---

### Task 5: 저장이 수정도 한다

**Files:**
- Create: `lib/features/record_card/domain/edit_record_card.dart`
- Modify: `lib/features/record_card/domain/record_card_repository.dart`
- Modify: `lib/features/record_card/data/fake_record_card_repository.dart`
- Modify: `lib/features/record_card/presentation/card_save_provider.dart`
- Test: `test/record_card_save_test.dart`

**Interfaces:**
```dart
/// 고친 카드. **남길 사진 전체**를 싣는다(사용자 결정 2026-11-19) —
/// 서버가 차집합으로 지우고, 앱은 변경을 추적하지 않는다.
class EditRecordCard {
  const EditRecordCard({required this.cardId, required this.activity,
    required this.visibility, required this.reviewText,
    required this.photos, required this.musicEnabled});
  final int cardId; /* ... */ final List<EditCardPhoto> photos;
}

/// 남길 사진 하나. 이미 올린 것이면 [savedId], 새로 올릴 것이면 [path].
class EditCardPhoto {
  const EditCardPhoto.saved({required this.savedId, this.caption})
      : path = null, thumbnailPath = null;
  const EditCardPhoto.added({required this.path, required this.thumbnailPath,
                             this.caption}) : savedId = null;
}

Future<RecordCard> update(EditRecordCard card);   // repository
```

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
test('수정이면 create가 아니라 update를 부른다', () async {
  final world = _World(cardId: 7);
  await world.saveEdit();
  expect(world.repository.creates, 0);
  expect(world.repository.updates, 1);
});

// ⚠️ Review Focus 2
test('⚠️ 이미 올린 사진은 다시 자르지 않는다', () async {
  // 이미 9:16으로 잘린 것을 또 자르면 그림이 좁아진다.
  final world = _World(cardId: 7);
  await world.saveEdit(saved: 2);
  expect(world.cropper.calls, isEmpty);
});

test('새로 고른 것만 자른다', () async {
  final world = _World(cardId: 7);
  await world.saveEdit(saved: 1, picked: 2);
  expect(world.cropper.calls, hasLength(2));
});

test('남길 사진 전체를 보낸다', () async {
  final world = _World(cardId: 7);
  await world.saveEdit(saved: 1, picked: 1);
  final sent = world.repository.lastEdit!.photos;
  expect(sent, hasLength(2));
  expect(sent.first.savedId, isNotNull);
  expect(sent.last.path, isNotNull);
});

// ⚠️ Review Focus 5
test('⚠️ 사진을 전부 지워도 저장된다', () async {
  final world = _World(cardId: 7);
  final card = await world.saveEdit();   // 사진 0장
  expect(card, isNotNull);
  expect(world.repository.lastEdit!.photos, isEmpty);
});

test('성공하면 초안을 비우고 달력을 무효화한다', () async { /* ... */ });

test('⚠️ 실패하면 고친 글을 지킨다', () async {
  final world = _World(cardId: 7, failWith: RecordCardFailure.network);
  await world.saveEdit(review: '고친 글');
  expect(world.draft(7).reviewText, '고친 글');
});
```

- [ ] **Step 2: 실패를 확인한다** → FAIL (`update`가 없다)

- [ ] **Step 3: `EditRecordCard`와 `update`를 만든다**

- [ ] **Step 4: Fake에 `update`를 만든다**

`_created`에서 그 번호를 찾아 갈아 끼운다. 목 데이터(`1000 +`)를 고치면 **다음
`byDateRange`가 목을 다시 만들어 되돌아간다** — 목도 고칠 수 있게 `_edited`
맵을 두고 `_all()`이 거기 있는 것으로 덮어쓴다.

- [ ] **Step 5: `CardSaveController`를 가른다**

`cardId`가 있으면 `update`, 없으면 `create`. **`SavedPhoto`는 자르기를
건너뛴다.** 치우기·초안 비우기·달력 무효화는 그대로다.

- [ ] **Step 6: 통과를 확인한다** → `<flutter> test` · `analyze`

- [ ] **Step 7: 커밋**

```bash
git commit -m "📍 Feat: 저장이 수정도 한다 — 남길 사진 전체를 보낸다"
```

---

### Task 6: 삭제

**Files:**
- Create: `lib/features/record_card/presentation/card_delete_provider.dart`
- Modify: `lib/features/record_card/domain/record_card_repository.dart`
- Modify: `lib/features/record_card/data/fake_record_card_repository.dart`
- Modify: `lib/core/strings/app_strings.dart`
- Test: `test/record_card_delete_test.dart`

**새 `AppStrings`:**

```dart
static const recordCardDelete = '삭제';
static const recordCardDeleteTitle = '이 기록카드를 지울까요?';
/// ⚠️ **되돌릴 수 없다는 말을 그대로 쓴다.** 서버에 논리 삭제 컬럼이 없다.
static const recordCardDeleteBody = '지우면 되돌릴 수 없어요';
static const recordCardDeleteConfirm = '지우기';
static const recordCardDeleteCancel = '그대로 두기';
static const recordCardDeleteFailed = '지우지 못했어요';
```

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
test('지우면 저장소에서 빠진다', () async { /* ... */ });

test('⚠️ 지우면 달력을 무효화한다', () async {
  // 안 하면 지운 카드가 달력에 남는다 — 저장 때와 같은 결함이다.
});

test('지우는 중에 또 누르면 한 번만 간다', () async { /* ... */ });

test('실패하면 왜인지 들고 있는다', () async { /* ... */ });
```

- [ ] **Step 2: 실패를 확인한다** → FAIL

- [ ] **Step 3: `delete`와 Fake 구현을 만든다**

목 데이터도 지울 수 있어야 한다 — `_deletedIds`를 두고 `_all()`이 거른다.

- [ ] **Step 4: `cardDeleteProvider`를 만든다**

`cardSaveProvider`와 같은 꼴(sealed 상태 · 재진입 가드 · 달력 무효화).

- [ ] **Step 5: 통과를 확인한다** → PASS

- [ ] **Step 6: 커밋**

```bash
git commit -m "📍 Feat: 카드를 지운다 — 되돌릴 수 없다고 말하고 받는다"
```

---

### Task 7: 상세의 `⋮`와 라우트 셋

**Files:**
- Modify: `lib/features/record_card/presentation/card_detail_page.dart`
- Modify: `lib/app/router/app_routes.dart` · `app_router.dart`
- Test: `test/record_card_detail_test.dart` · `test/record_card_edit_flow_test.dart`(신규)

**Interfaces:**
```dart
static String recordCardEditOf(int cardId) => '$recordCard/card/$cardId/edit';
static String recordCardEditPhotosOf(int cardId) => '${recordCardEditOf(cardId)}/photos';
static String recordCardEditPublishOf(int cardId) => '${recordCardEditOf(cardId)}/publish';
```

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
testWidgets('⋮에 수정과 삭제가 있다', (tester) async { /* ... */ });

testWidgets('수정을 누르면 그 카드의 작성 1로 간다', (tester) async { /* ... */ });

// ⚠️ Review Focus 4
testWidgets('⚠️ 지우면 상세에 머물지 않는다', (tester) async {
  // 없는 카드를 보고 있으면 거기서 수정을 눌러 404를 받는다.
  await _pumpDetail(tester, card: _card(id: 7));
  await _tapMenu(tester, AppStrings.recordCardDelete);
  await tester.tap(find.text(AppStrings.recordCardDeleteConfirm));
  await tester.pumpAndSettle();

  expect(find.byType(CardDetailPage), findsNothing);
  expect(find.byType(RecordCardPage), findsOne);
});

testWidgets('지우기를 취소하면 아무 일도 없다', (tester) async { /* ... */ });

testWidgets('수정 저장하면 상세로 돌아오고 고친 값이 보인다', (tester) async {
  // 실제 라우터를 탄다 — 수정 라우트 셋과 `:id` 파싱이 거기서만 틀린다.
});

testWidgets('⚠️ 수정 라우트가 카드 없이 들어오면 탭으로 돌려보낸다', (tester) async {
  // 딥링크나 프로세스 복원이다. 상세가 `extra` 없이 들어온 것과 같은 꼴이다.
});
```

- [ ] **Step 2: 실패를 확인한다** → FAIL

- [ ] **Step 3: 라우트 셋을 더한다**

`/record-card/card/:id/edit{,/photos,/publish}`. **`extra`로 카드를 받는다** —
단건 조회 API가 없어 상세와 같은 방식이다. 없으면 탭으로 돌려보낸다.

⚠️ **`/record-card/card/:id`보다 **뒤에** 선언해도 안전하다** — go_router는 더
긴 경로를 먼저 맞춘다. 그래도 `app_routes.dart`의 **정렬 위치**에 넣는다.

- [ ] **Step 4: `⋮`를 붙인다**

`LucideIcons.ellipsisVertical`. 눌러서 바텀시트 — `수정` · `삭제`.
삭제는 **확인 시트**를 한 번 더 받는다. 상세의 머리 주석("없는 버튼을 그려 두지
않는다")을 **고친다** — 이제 있다.

- [ ] **Step 5: 저장 뒤 돌아갈 곳을 가른다**

수정 저장은 **새 상세를 밀지 않는다** — 작성 셋을 걷고 **원래 상세로 돌아간다**.
새로 밀면 상세가 둘 쌓여 뒤로가 두 번이 된다.

⚠️ 삭제는 **왔던 곳으로** 간다(설계 6-6). 지금 들어오는 길은 달력뿐이라
`pop`이면 충분하다 — 프로필 그리드는 묶음 6이다.

- [ ] **Step 6: 통과를 확인한다** → `<flutter> test` · `analyze` · `format`

- [ ] **Step 7: 커밋**

```bash
git commit -m "📍 Feat: 상세에서 고치고 지운다"
```

---

## 끝낸 뒤

**작성 1(PR 2) · 작성 2·3(PR 3) · 수정·삭제(PR 4)를 함께 올릴지, 작성 둘만 먼저
올릴지는 사용자가 정한다.** 작성 둘은 이미 혼자 설 수 있다(저장하면 카드가 생기고
상세로 간다). 수정·삭제는 그 위에 얹히므로 나중에 따로 올려도 막힌 버튼이 없다.

미뤄 둔 것은 `docs/notes/`에 같은 꼴로 남긴다. **음악 관련 알림 둘**(설계 6-6의
"음악이 있고 입력이 바뀌면", "생성 중에도 고치고 지울 수 있다")은 **묶음 5에서
반드시 붙인다** — 이 계획이 일부러 빼 둔 것이다.
