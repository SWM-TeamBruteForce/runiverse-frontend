# 기록카드 쓰기 연동(묶음 8) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 가짜가 받던 카드 **저장과 수정**을 실제 서버에 붙인다 — 초안 발급(9-1) → S3 업로드 → 확정(9-2), 수정은 PATCH(9-3).

**Architecture:** `HttpRecordCardRepository`의 `create`·`update` 두 줄이 실제 구현으로 바뀌고 `fallback`이 사라진다. S3 업로드는 **인증 헤더가 붙지 않은 별도 `Dio`**로 보낸다(`HttpProfileImageRepository`와 같은 함정). 확정 뒤에는 **8-1을 다시 읽어** 카드를 돌려준다 — 파서를 한 벌만 둔다.

**Tech Stack:** Flutter · dio · Riverpod 3(수동 provider)

**Spec:** 「💾 [1.3.2] 기록 카드 프론트엔드 연동 가이드」 3·4·7절이 정본이다(노션). `docs/specs/2026-11-16-record-card-design.md` 6-3·6-6절은 그 앞의 추측이라, 어긋나면 가이드가 이긴다.

## Global Constraints

- **flutter 실행 경로는 `C:\dev\runiverse\frontend\.fvm\flutter_sdk\bin\flutter.bat`다.** 이 워크트리에는 `.fvm`이 없다.
- 모든 API 경로에 `/api/v1`을 붙인다. 오류 본문은 `{ "code": "...", "message": "..." }`이고 **분기는 `code` 기준**이다.
- `activityType`: `DAILY`·`RACE`·`TRAVEL` / `visibility`: `FRIENDS`·`PUBLIC`·`PRIVATE`. **대문자**로 보낸다.
- `memo`는 **필수**이고 공백만 보낼 수 없다. 길이는 **`String.length`(UTF-16) 기준 1~1,000**.
- 사진은 최대 5장. 크롭본 ≤100MB·썸네일 ≤1MB, 둘 다 `image/jpeg`·`image/png`·`image/webp` 중 하나.
- `fileName`은 새 사진마다 **필수**, 최대 100자, **슬래시·역슬래시·제어 문자 금지**.
- `caption`은 선택, 최대 100자. 공백만 보내면 서버가 `null`로 저장한다.
- 업로드 URL과 초안은 **30분**, 조회용 URL은 **1시간**.
- 색·치수·문자열은 토큰으로만. `AppStrings`에 새 문자열은 정렬된 자리에.
- 커밋은 `<이모지> <type>: <설명>`. **AI를 공동 작성자로 넣지 않는다.**
- **보안**: 서버 주소·토큰·서명 URL을 로그나 주석에 적지 않는다.

## 내가 정하고 가는 것 (가이드가 답하지 않은 자리)

| 자리 | 정한 값 | 틀렸을 때 |
|---|---|---|
| 썸네일을 못 만들었다 | **크롭본을 썸네일로 올린다**(1MB 이하일 때). 넘으면 저장 실패 | 달력이 큰 그림을 받는다. 지금은 아예 못 올린다 |
| `MULTIPART`가 왔다 | 구현하지 않고 **분명한 실패**로 돌려준다 | 10MB 넘는 크롭본이 생기면 저장이 막힌다. 조용히 멈추는 것보다 낫다 |
| PATCH가 `draft: null`을 줬다 | 응답의 `recordCard`를 쓰지 않고 **8-1을 다시 읽는다** | 왕복이 한 번 는다. 대신 파서가 한 벌이다 |
| 회고 길이 | 입력 칸을 **UTF-16**으로 막는다(세는 칸도 이미 UTF-16) | 이모지를 많이 쓰면 글자 수보다 일찍 막힌다 |

## Review Focus

1. **확정(9-2) 직전에 끊겼다** — 같은 `recordCardDraftId`로 다시 불러야 하고, 이미 확정된 초안이면 같은 `recordCardId`가 온다(Task 5).
2. **올린 파일이 하나 빠졌다**(`400 RECORD_CARD_IMAGE_NOT_UPLOADED`) — 빠진 것만 다시 올리고 같은 초안으로 재확정(Task 5).
3. **그 기록에 이미 카드가 있다**(`409 RECORD_CARD_ALREADY_EXISTS`) — 작성이 아니라 **수정으로 보내야** 한다(Task 7).
4. **사진이 0장이다** — S3 단계를 통째로 건너뛰고 9-1 → 9-2만 간다(Task 5).
5. **수정에서 남긴 사진 번호가 그 카드 것이 아니다**(`400 INVALID_RECORD_CARD_IMAGE`) — 8-1을 다시 읽어 편집 화면을 갱신해야 한다(Task 6).

---

### Task 1: 올릴 파일의 이름·형식·바이트를 싣는다

**Files:**
- Modify: `lib/features/record_card/domain/new_record_card.dart`
- Modify: `lib/features/record_card/domain/edit_record_card.dart`
- Modify: `lib/features/record_card/presentation/card_save_provider.dart`
- Test: `test/record_card_save_test.dart`

**Interfaces:**
- Produces: `class UploadFile { final String path; final String fileName; final String mimeType; final int sizeBytes; }` (`new_record_card.dart`에 둔다)
  - `NewCardPhoto({required UploadFile file, required UploadFile thumbnail, String? caption})`
  - `EditCardPhoto.added({required UploadFile file, required UploadFile thumbnail, String? caption})`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
test('⚠️ 썸네일을 못 만들면 크롭본을 썸네일로 쓴다', () async {
  final saved = await _save(thumbnailMaker: _NoThumbnail());
  expect(saved.photos.single.thumbnail.path, saved.photos.single.file.path);
});

test('⚠️ 크롭본이 1MB를 넘는데 썸네일이 없으면 저장하지 않는다', () async {
  final state = await _saveExpectingFailure(
    thumbnailMaker: _NoThumbnail(),
    croppedBytes: 1024 * 1024 + 1,
  );
  expect(state, isA<CardSaveFailed>());
});

test('파일 이름에 경로 구분자가 들어가지 않는다', () async {
  final saved = await _save();
  expect(saved.photos.single.file.fileName, isNot(contains('/')));
  expect(saved.photos.single.file.fileName.length, lessThanOrEqualTo(100));
});
```

- [ ] **Step 2: 실패를 본다.** Run: `... test test/record_card_save_test.dart`. 기대: FAIL — `UploadFile`이 없다.

- [ ] **Step 3: `UploadFile`을 만들고 두 사진 타입이 그것을 들게 한다.** 저장 provider가 자른 파일과 썸네일의 **실제 바이트 수**를 재어 채운다(가이드 3절: 요청에 넣는 것은 크롭·압축이 끝난 파일의 실제 크기다). 이름은 경로의 마지막 조각을 쓰고 100자로 자른다. 썸네일이 `null`이면 크롭본을 쓰되 1MB를 넘으면 `RecordCardFailure.invalidRequest`로 실패한다. `card_thumbnail_maker.dart`의 "없으면 달력이 원본을 쓴다"는 주석을 **서버가 썸네일을 요구한다**로 고친다.

- [ ] **Step 4: 통과를 본다.** Run: 같은 명령. 기대: PASS.

- [ ] **Step 5: 커밋** — `📍 Feat: 올릴 사진에 이름·형식·바이트를 싣는다`

---

### Task 2: 회고를 UTF-16으로 막는다

**Files:**
- Modify: `lib/features/record_card/presentation/card_compose_page.dart` (회고 `inputFormatters`)
- Modify: `lib/features/record_card/domain/card_draft.dart` (`reviewMaxLength` 주석)
- Test: `test/record_card_compose_page_test.dart`

**Interfaces:**
- Consumes: 없음 / Produces: 없음

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
testWidgets('⚠️ 이모지가 많아도 서버가 세는 길이에서 멈춘다', (tester) async {
  // 서버는 String.length(UTF-16)로 센다. grapheme 으로 막으면 포매터는
  // 통과시키고 서버가 400을 준다.
  await _pump(tester);
  await _reach(tester, find.byType(AppInputV2));
  await tester.enterText(find.byType(AppInputV2), '🏃' * 600);
  await tester.pumpAndSettle();

  final text = tester.widget<TextField>(find.byType(TextField)).controller!.text;
  expect(text.length, lessThanOrEqualTo(CardDraft.reviewMaxLength));
});
```

- [ ] **Step 2: 실패를 본다.** Run: `... test test/record_card_compose_page_test.dart --plain-name "이모지가 많아도"`. 기대: FAIL — 1200이 들어간다.

- [ ] **Step 3: `LengthLimitingTextInputFormatter`를 UTF-16으로 세는 포매터로 바꾼다.** `maxLength`를 code unit으로 보는 `TextInputFormatter`를 `card_draft.dart` 옆에 두거나 그 자리에서 자른다 — **세는 칸이 이미 `reviewText.length`(UTF-16)라 둘이 같아진다.**

- [ ] **Step 4: 통과를 본다.** Run: 같은 명령. 기대: PASS.

- [ ] **Step 5: 커밋** — `🔨 Fix: 회고를 서버가 세는 길이로 막는다`

---

### Task 3: 쓰기 오류를 `code`로 가른다

**Files:**
- Modify: `lib/features/record_card/domain/record_card_repository.dart` (`RecordCardFailure`)
- Modify: `lib/features/record_card/data/http_record_card_repository.dart` (`failureOf`)
- Test: `test/http_record_card_repository_test.dart`

**Interfaces:**
- Produces: `RecordCardFailure.alreadyExists` · `RecordCardFailure.changed` 두 값이 는다. `static RecordCardFailure failureOf(DioException)`가 **본문의 `code`를 먼저 본다.**

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
test('⚠️ 409 RECORD_CARD_ALREADY_EXISTS 는 수정으로 보내야 하는 실패다', () {
  expect(
    HttpRecordCardRepository.failureOf(_conflict('RECORD_CARD_ALREADY_EXISTS')),
    RecordCardFailure.alreadyExists,
  );
});

test('⚠️ 409 RECORD_CARD_CHANGED 는 다시 읽어야 하는 실패다', () {
  expect(
    HttpRecordCardRepository.failureOf(_conflict('RECORD_CARD_CHANGED')),
    RecordCardFailure.changed,
  );
});

test('⚠️ code 를 모르면 상태 코드로 떨어진다', () {
  expect(
    HttpRecordCardRepository.failureOf(_conflict('WHAT_IS_THIS')),
    RecordCardFailure.server,
  );
});
```

- [ ] **Step 2: 실패를 본다.** Run: `... test test/http_record_card_repository_test.dart`. 기대: FAIL.

- [ ] **Step 3: `failureOf`가 본문의 `code`를 먼저 보게 한다.** 모르는 `code`는 **지어내지 않고** 지금의 상태 코드 규칙으로 떨어진다. `409`에 `code`가 없으면 `server`다.

- [ ] **Step 4: 통과를 본다.** Run: 같은 명령. 기대: PASS.

- [ ] **Step 5: 커밋** — `📍 Feat: 쓰기 오류를 code로 가른다`

---

### Task 4: S3에 올린다

**Files:**
- Create: `lib/features/record_card/data/card_photo_uploader.dart`
- Test: `test/record_card_photo_uploader_test.dart`

**Interfaces:**
- Produces:
  - `class CardPhotoUploader { CardPhotoUploader({Dio? uploadDio}); Future<void> put({required String url, required String path, required String mimeType, required int sizeBytes}); @visibleForTesting Dio get uploadDio; }`
  - `static BaseOptions get uploadOptions` — `connectTimeout` 10초 · `sendTimeout` 60초 · `receiveTimeout` 10초.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
test('⚠️ 보내는 시간 제한이 따로 길다', () {
  final uploader = CardPhotoUploader();
  expect(uploader.uploadDio.options.sendTimeout, const Duration(seconds: 60));
  expect(uploader.uploadDio.options.baseUrl, isEmpty);
});

test('⚠️ 잰 크기와 실제 바이트가 다르면 올리지 않는다', () async {
  // 서명은 fileSizeBytes 로 받았다. 그대로 올리면 403 인데 원인이 안 보인다.
  await expectLater(
    uploader.put(url: 'https://s3.invalid/x', path: file.path,
        mimeType: 'image/jpeg', sizeBytes: file.lengthSync() + 1),
    throwsA(isA<RecordCardException>()),
  );
});
```

- [ ] **Step 2: 실패를 본다.** Run: `... test test/record_card_photo_uploader_test.dart`. 기대: FAIL — 파일이 없다.

- [ ] **Step 3: `CardPhotoUploader`를 만든다.** `HttpProfileImageRepository._putToS3`와 같은 규칙이다 — **`Uint8List`로 보내고**(`List<int>`면 글자로 올라간다), `Options(contentType: mimeType, responseType: ResponseType.plain)`를 주고, `Content-Length`는 dio가 붙이게 둔다. 인증 헤더를 **붙이지 않는다**(S3가 서명 검증에 넣어 403을 준다). 실패는 `RecordCardException(RecordCardFailure.network)`다.

- [ ] **Step 4: 통과를 본다.** Run: 같은 명령. 기대: PASS.

- [ ] **Step 5: 커밋** — `📍 Feat: 카드 사진을 S3에 올린다`

---

### Task 5: 카드를 만든다 (9-1 → S3 → 9-2)

**Files:**
- Create: `lib/features/record_card/data/record_card_draft_dto.dart`
- Modify: `lib/features/record_card/data/http_record_card_repository.dart` (`create`)
- Test: `test/record_card_create_test.dart`

**Interfaces:**
- Consumes: Task 1의 `UploadFile`, Task 3의 `failureOf`, Task 4의 `CardPhotoUploader`
- Produces:
  - `abstract final class RecordCardDraftDto` — `static CardDraftIssued from(Map<String, dynamic>)`
  - `class CardDraftIssued { final String draftId; final DateTime expiresAt; final List<CardUploadSlot> uploads; }`
  - `class CardUploadSlot { final String imageId; final String uploadType; final String uploadUrl; final String? thumbnailUploadUrl; }`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
test('사진이 없으면 S3 단계를 건너뛴다', () async {
  await repository.create(_card(photos: 0));
  expect(uploader.calls, isEmpty);
  expect(dio.paths, ['/api/v1/record-cards',
      '/api/v1/record-cards/drafts/$_draftId/complete', '/api/v1/record-cards/$_cardId']);
});

test('사진 한 장이면 크롭본과 썸네일을 둘 다 올린다', () async {
  await repository.create(_card(photos: 1));
  expect(uploader.calls, hasLength(2));
});

test('⚠️ 확정이 409 RECORD_CARD_DRAFT_IN_PROGRESS 면 같은 초안으로 다시 부른다', () async {
  dio.failCompleteOnce(409, 'RECORD_CARD_DRAFT_IN_PROGRESS');
  final card = await repository.create(_card(photos: 0));
  expect(card.id, _cardId);
  expect(dio.completeCalls, 2);
});

test('⚠️ 확정이 400 RECORD_CARD_IMAGE_NOT_UPLOADED 면 다시 올리고 재확정한다', () async {
  dio.failCompleteOnce(400, 'RECORD_CARD_IMAGE_NOT_UPLOADED');
  await repository.create(_card(photos: 1));
  expect(uploader.calls, hasLength(4));
  expect(dio.completeCalls, 2);
});

test('⚠️ MULTIPART 는 분명히 실패한다', () async {
  dio.uploadType = 'MULTIPART';
  await expectLater(repository.create(_card(photos: 1)),
      throwsA(isA<RecordCardException>()));
});

test('⚠️ 확정하면 그 번호로 상세를 다시 읽는다', () async {
  final card = await repository.create(_card(photos: 0));
  expect(card.id, _cardId);
});
```

- [ ] **Step 2: 실패를 본다.** Run: `... test test/record_card_create_test.dart`. 기대: 전부 FAIL.

- [ ] **Step 3: `create`를 구현한다.** 9-1 요청 본문은 가이드 3절 그대로다(`runningRecordId`·`activityType`·`memo`·`visibility`·`images[]`·`thumbnailIndex`). `uploads[i]`를 요청의 **새 사진 순서**로 이어 붙인다. 재시도는 **각각 한 번만**이다 — 두 번째도 실패하면 그대로 던진다.

- [ ] **Step 4: 통과를 본다.** Run: 같은 명령. 기대: PASS.

- [ ] **Step 5: 커밋** — `📍 Feat: 기록카드를 서버에 만든다`

---

### Task 6: 카드를 고친다 (9-3)

**Files:**
- Modify: `lib/features/record_card/data/http_record_card_repository.dart` (`update`)
- Modify: `lib/features/record_card/data/record_card_draft_dto.dart` (PATCH 응답의 `draft`)
- Test: `test/record_card_update_test.dart`

**Interfaces:**
- Consumes: Task 5의 `CardDraftIssued`
- Produces: `static CardDraftIssued? draftOf(Map<String, dynamic>)` — PATCH 응답의 `draft`가 `null`이면 `null`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
test('새 사진이 없으면 PATCH 한 번으로 끝난다', () async {
  await repository.update(_edit(added: 0));
  expect(dio.completeCalls, 0);
});

test('⚠️ draft 가 오면 새 사진만 올리고 확정한다', () async {
  dio.patchReturnsDraft = true;
  await repository.update(_edit(kept: 1, added: 1));
  // 남긴 사진은 번호만 돌려보낸다 — 다시 올리지 않는다.
  expect(uploader.calls, hasLength(2));
  expect(dio.completeCalls, 1);
});

test('⚠️ 남긴 캡션을 그대로 다시 보낸다', () async {
  await repository.update(_edit(kept: 1, keptCaption: '노을'));
  expect(dio.lastPatchImages.single['caption'], '노을');
});

test('⚠️ 사진을 전부 지우면 빈 배열을 보낸다', () async {
  await repository.update(_edit(kept: 0, added: 0));
  expect(dio.lastPatchBody['images'], isEmpty);
});

test('⚠️ 400 INVALID_RECORD_CARD_IMAGE 는 다시 읽으라는 실패다', () async {
  dio.failPatch(400, 'INVALID_RECORD_CARD_IMAGE');
  await expectLater(repository.update(_edit()), throwsA(
      isA<RecordCardException>().having((e) => e.failure, 'failure',
          RecordCardFailure.changed)));
});
```

- [ ] **Step 2: 실패를 본다.** Run: `... test test/record_card_update_test.dart`. 기대: 전부 FAIL.

- [ ] **Step 3: `update`를 구현한다.** 보내는 것은 `memo`·`activityType`·`visibility`·`images`·`thumbnailIndex`뿐이다 — **러닝 기록은 보내지 않는다**(수정에서 바꿀 수 없다). `images`는 **남길 전체**이고, 기존 사진은 `{recordCardImageId, caption}`, 새 사진은 파일 메타다. 한 항목에 두 형식을 섞으면 `400`이다. 끝나면 **8-1을 다시 읽는다.**

- [ ] **Step 4: 통과를 본다.** Run: 같은 명령. 기대: PASS.

- [ ] **Step 5: 커밋** — `📍 Feat: 기록카드 수정을 서버에 붙인다`

---

### Task 7: 가짜를 떼고 화면이 두 실패를 다르게 안내한다

**Files:**
- Modify: `lib/features/record_card/presentation/record_card_provider.dart` (`fallback` 제거)
- Modify: `lib/features/record_card/data/http_record_card_repository.dart` (`fallback` 필드 제거)
- Modify: `lib/features/record_card/presentation/card_publish_page.dart`
- Modify: `lib/core/strings/app_strings.dart`
- Test: `test/record_card_publish_page_test.dart`

**Interfaces:**
- Consumes: Task 3의 `RecordCardFailure.alreadyExists`·`changed`
- Produces: `AppStrings.recordCardSaveAlreadyExists = '이 러닝에는 이미 기록카드가 있어요'` · `AppStrings.recordCardSaveChanged = '다른 곳에서 먼저 고쳤어요. 다시 읽어 주세요'`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
testWidgets('⚠️ 이미 카드가 있으면 그렇게 말한다', (tester) async {
  await _pump(tester, failure: RecordCardFailure.alreadyExists);
  await tester.tap(find.text(AppStrings.recordCardPublishSave));
  await tester.pumpAndSettle();

  expect(find.text(AppStrings.recordCardSaveAlreadyExists), findsOne);
});

testWidgets('⚠️ 먼저 고쳐졌으면 다시 읽으라고 한다', (tester) async {
  await _pump(tester, failure: RecordCardFailure.changed);
  await tester.tap(find.text(AppStrings.recordCardPublishSave));
  await tester.pumpAndSettle();

  expect(find.text(AppStrings.recordCardSaveChanged), findsOne);
});
```

- [ ] **Step 2: 실패를 본다.** Run: `... test test/record_card_publish_page_test.dart`. 기대: FAIL.

- [ ] **Step 3: 셋을 고친다.** provider가 `fallback` 없이 `HttpRecordCardRepository`를 만들고, 저장소에서 그 필드를 지운다. 발행 화면이 `CardSaveFailed.failure`로 문구를 가른다 — 나머지는 지금의 `recordCardPublishSaveFailed`다. provider 주석의 "**저장만 아직 가짜다**" 경고를 걷어낸다.

- [ ] **Step 4: 통과를 본다.** Run: 같은 명령. 기대: PASS.

- [ ] **Step 5: 전체 테스트와 analyze.** Run: `... test` 그리고 `... analyze`. 기대: 전부 PASS, 경고 0. 가짜를 꽂아 두던 테스트(`widget_test.dart`·`profile_page_test.dart`)가 깨지면 그 자리를 고친다.

- [ ] **Step 6: 커밋** — `📍 Feat: 기록카드 저장을 실제 서버에 붙인다`

---

### Task 8: 기기에서 끝까지 본다

**Files:** 없음 (확인만)

- [ ] **Step 1: 앱을 올린다.** `... run -d emulator-5554 --dart-define-from-file=config/dev.json`
- [ ] **Step 2: 사진 두 장짜리 카드를 저장한다.** 상세가 뜨고 경로·지표·사진·캡션이 보인다.
- [ ] **Step 3: 달력에 그 날이 썸네일로 바뀐다.** 운동화가 아니라 사진이다.
- [ ] **Step 4: 프로필 그리드에 그 카드가 선다.**
- [ ] **Step 5: 음악이 만들어진다.** 상세를 열어 두면 `생성 중`에서 바뀐다(10초 → 최대 1분 간격).
- [ ] **Step 6: 수정한다.** 회고를 고치고 사진 하나를 지운 뒤 저장 → 상세가 바뀐다.
- [ ] **Step 7: 같은 러닝으로 또 쓰려 한다.** `이 러닝에는 이미 기록카드가 있어요`가 뜬다.
- [ ] **Step 8: `routeArt` 정규화를 눈으로 본다.** 가로로 긴 코스 카드에서 짧은 축이 `0~1`을 다 쓰는지 — 묶음 7에서 카드가 없어 못 본 확인이다. 임시 `debugPrint`로 **폭만** 찍는다(좌표 아님).
- [ ] **Step 9: 삭제한다.** 달력과 프로필에서 빠진다.

---

## PR 경계

| PR | 작업 | 내용 |
|---|---|---|
| 1 | Task 1~4 | 올릴 파일 메타 · 회고 길이 · 오류 코드 · S3 업로더 |
| 2 | Task 5~7 | 작성 · 수정 · 실제 연결 |

묶음 1~7의 PR **뒤에 선다.**

## Self-review

**가이드 절별 덮임**: 3절 작성 → Task 1·4·5 · 3절 `memo` 길이 → Task 2 · 4절 수정 → Task 6 · 4절 `images` 세 가지 보내는 법 → Task 6 · 7절 오류 복구 7줄 → Task 3(분류)·5(재시도 둘)·6(다시 읽기)·7(안내) · 7절 URL 만료 → 묶음 7에서 끝났다.

**빠뜨린 것 둘**: ① `thumbnailIndex`를 **대표 지정 UI와 잇는 것** — 화면은 이미 `makeCover`로 순서를 바꾸므로 항상 `0`을 보내면 맞는다. 바꿀 일이 생기면 그때 싣는다. ② `409 RECORD_CARD_ALREADY_EXISTS`에서 **수정 화면으로 자동 이동**하는 것 — 문구로 알리는 데까지만 한다. 자동으로 옮기면 쓰던 회고가 어디로 갔는지 알 수 없다.

**타입 일관성**: `UploadFile`(Task 1) → `CardUploadSlot`(Task 5) → `CardPhotoUploader.put`(Task 4)이 `path`·`mimeType`·`sizeBytes`로 이어진다. `CardDraftIssued`는 Task 5가 정의하고 Task 6이 그대로 쓴다.

**비례**: 작업 8개, 각 단계는 테스트 이름과 명령까지만 적었다. 본문 코드를 넣은 자리는 없다.
