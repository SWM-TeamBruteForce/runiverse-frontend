# 기록카드 작성 2·3 구현 계획 (PR 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 고른 러닝에 사진을 9:16으로 붙이고, 공개범위와 음악 여부를 정해 **카드를 만든다.**

**Architecture:** 작성 1이 세운 `cardDraftProvider` 하나를 세 화면이 이어 쓴다. 사진은
고를 때 **자르지 않고** 원본 + 밀어 둔 위치만 초안에 담았다가, **저장할 때 한 번에**
자르고 썸네일을 만든다 — 프로필 커버와 같은 순서다. 자르는 코드(`CoverCrop` ·
`UiImageCropper`)는 `features/profile`에 있는 것을 제자리에서 쓰고, 9:16에서 필요한
`alignX`만 더한다.

**Tech Stack:** Flutter + fvm · Riverpod 3 수동 provider · go_router ·
`image_picker`(이미 있음) · `flutter_image_compress`(이미 있음) · Lucide 아이콘

**Spec:** `docs/specs/2026-11-16-record-card-design.md` 6-3절 · 6-4절 · 7절(초안 수명)

## Global Constraints

- UI 텍스트는 **한국어**, 전부 `AppStrings`에. **정렬 위치에 넣는다** — 맨 끝에 붙이면 머지 충돌이 난다.
- 색·치수·타이포는 토큰만 (`context.appColorsV2` `AppSpacing` `AppRadius` `AppTypography`). `core/theme/tokens/` 밖에서 `Color(0x...)` 금지.
- 아이콘은 **Lucide만**. `Icons.*` 혼용 금지.
- `StateProvider` · `StateNotifierProvider` 금지. 수동 provider만 (코드 생성 미도입).
- 화면은 **loading / data / error 3분기 필수**. **empty 상태 + 다크·라이트** 둘 다.
- 위젯은 필요한 필드만 `select`해서 watch한다.
- `domain/`은 **순수 Dart만**. `dart:io` · `dart:ui` 금지.
- 의존 방향 `presentation → domain ← data`. **다른 feature의 화면·위젯은 import하지 않는다.** provider와 domain은 예외다 (CLAUDE.md).
- 모든 flutter/dart 명령 앞에 `fvm`. 이 저장소에서는 `.fvm/flutter_sdk/bin/flutter.bat`을 직접 부른다.
- 커밋: `<이모지> <Type>: <한국어 설명>`. **AI 공동 작성자 트레일러·푸터 금지.**
- 사진 한 장 **10MB** 상한은 `PickedImage.maxBytes`가 이미 가진 값이다. 새로 적지 않는다.
- 사진 **최대 5장** · 캡션 **100자** · 회고 **1000자**(이미 있음).
- 공개범위 기본값 **친구 공개**, 음악 토글 기본값 **켜짐**.

## Review Focus

이 다섯은 설계가 함축하지만 어느 Task의 테스트도 건드리지 않는다. 사람이 먼저 맞을 순서대로.

1. **고르는 중 OS가 임시 폴더를 비운다.** 초안은 파일 **경로**만 들고 있어, 백그라운드에 오래 둔 뒤 저장하면 읽을 파일이 없다. 저장이 실패하고 **쓴 글이 남아야** 한다 — 초안을 비우면 회고까지 잃는다. → Task 6에 테스트를 붙인다.
2. **마지막 장을 지우면 페이저 인덱스가 범위를 넘는다.** 3장 중 3번째를 보다가 지우면 가리키는 곳이 없다. → Task 4에 테스트를 붙인다.
3. **저장을 두 번 누른다.** 느린 저장 중에 또 누르면 **카드가 둘** 생긴다. → Task 6에 테스트를 붙인다.
4. **캡션 100자를 이모지로 채운다.** 입력 칸은 grapheme, 자르기는 code unit으로 세면 끝에 반쪽 서로게이트가 남는다. 회고에서 이미 같은 결함을 미뤄 뒀다(`docs/notes/2026-11-18-record-card-compose-deferred.md` 1번) — **여기서는 되풀이하지 않는다.** → Task 2에 테스트를 붙인다.
5. **`alignX`를 더하면서 기존 호출자 둘이 바뀐다.** 프로필 커버와 워치 사진이 `CoverCrop.rect`를 쓴다. 기본값 0이 **오늘의 "가운데"와 같은 값**이어야 한다. → Task 1에 테스트를 붙인다.

---

## 파일 구조

| 파일 | 맡는 일 |
|---|---|
| `profile/domain/cover_crop.dart` **(수정)** | 가로로 넘칠 때 `alignX`로 좌우를 고른다 |
| `profile/domain/image_cropper.dart` **(수정)** | `crop`에 `alignX` 추가 |
| `profile/data/ui_image_cropper.dart` **(수정)** | `alignX`를 넘긴다 |
| `record_card/domain/card_photo_draft.dart` **(신규)** | 고른 사진 한 장 + 캡션 + 밀어 둔 위치 |
| `record_card/domain/card_draft.dart` **(수정)** | 사진 목록 · 공개범위 · 음악 토글 |
| `record_card/domain/new_record_card.dart` **(신규)** | 저장 요청 값 (자른 사진 경로까지 끝난 것) |
| `record_card/domain/card_thumbnail_maker.dart` **(신규)** | 자른 결과에서 썸네일을 만든다 (인터페이스) |
| `record_card/domain/record_card_repository.dart` **(수정)** | `create` 추가 |
| `record_card/data/compressed_card_thumbnail_maker.dart` **(신규)** | 긴 변 320px JPEG |
| `record_card/data/fake_record_card_repository.dart` **(수정)** | 만든 카드를 메모리에 쌓는다 |
| `record_card/presentation/card_draft_provider.dart` **(수정)** | 사진·공개범위·음악 손잡이 |
| `record_card/presentation/card_photo_pan.dart` **(신규)** | 9:16 칸에서 **넘치는 축으로** 미는 미리보기 |
| `record_card/presentation/card_photo_page.dart` **(신규)** | 작성 2 — 사진 |
| `record_card/presentation/card_publish_page.dart` **(신규)** | 작성 3 — 공개범위 · 음악 · 저장 |
| `record_card/presentation/card_save_provider.dart` **(신규)** | 자르기 → 썸네일 → `create` |
| `record_card/presentation/visibility_label.dart` **(신규)** | 공개범위를 화면에 쓸 말로 |
| `record_card/presentation/record_card_cell.dart` **(수정)** | `cardThumbnail`에 로컬 파일 분기 |
| `app/router/app_routes.dart` · `app_router.dart` **(수정)** | `/new/photos` · `/new/publish` |
| `core/strings/app_strings.dart` **(수정)** | 작성 2·3 문구 |

---

### Task 1: 9:16 크롭 — 넘치는 축으로 민다

9:16 틀에서는 **세로로 밀 수가 없다.** 4:3이든 3:4든 실제 사진은 거의 다 9:16보다
납작해서 *가로로* 넘치는데, 지금 `CoverCrop.rect`는 가로로 넘치면 "언제나 가운데"로
못 박아 둔다. 설계 6-3의 "비율만 바꿔 쓴다"가 **그대로는 안 된다.**

**Files:**
- Modify: `lib/features/profile/domain/cover_crop.dart`
- Modify: `lib/features/profile/domain/image_cropper.dart`
- Modify: `lib/features/profile/data/ui_image_cropper.dart`
- Test: `test/cover_crop_test.dart`

**Interfaces:**
- Consumes: 없음
- Produces:
  ```dart
  CoverCrop.rect({
    required int width, required int height,
    required double aspectRatio,
    double alignX = 0,            // 새로 추가. -1 왼쪽 · 0 가운데 · 1 오른쪽
    required double alignY,
  }) → ({int left, int top, int width, int height})

  ImageCropper.crop(PickedImage image, {
    required double aspectRatio, double alignX = 0, required double alignY,
  }) → Future<PickedImage>
  ```

- [ ] **Step 1: 실패하는 테스트를 쓴다** (`test/cover_crop_test.dart`에 추가)

```dart
group('가로로 넘치는 사진', () {
  // 1600×900을 9:16에 앉히면 폭 506만 남고 1094가 넘친다.
  test('alignX -1은 왼쪽 끝을 남긴다', () {
    final rect = CoverCrop.rect(
      width: 1600, height: 900, aspectRatio: 9 / 16, alignX: -1, alignY: 0,
    );
    expect(rect.left, 0);
    expect(rect.width, 506);
    expect(rect.top, 0);
    expect(rect.height, 900);
  });

  test('alignX 1은 오른쪽 끝을 남긴다', () {
    final rect = CoverCrop.rect(
      width: 1600, height: 900, aspectRatio: 9 / 16, alignX: 1, alignY: 0,
    );
    expect(rect.left, 1600 - 506);
  });

  // ⚠️ Review Focus 5 — 기존 호출자 둘이 쓰는 값이다.
  test('alignX 기본값은 오늘의 가운데와 같다', () {
    final now = CoverCrop.rect(
      width: 1600, height: 900, aspectRatio: 9 / 16, alignY: 0,
    );
    expect(now.left, ((1600 - 506) / 2).round());
  });

  test('alignX는 끝에서 멈춘다', () {
    final rect = CoverCrop.rect(
      width: 1600, height: 900, aspectRatio: 9 / 16, alignX: -9, alignY: 0,
    );
    expect(rect.left, 0);
  });
});

test('세로로 넘치는 사진은 alignX를 무시한다', () {
  // 900×1600을 2.06:1에 앉히면 폭을 다 쓴다 — 좌우로 밀 것이 없다.
  final rect = CoverCrop.rect(
    width: 900, height: 1600, aspectRatio: 412 / 200, alignX: 1, alignY: 0,
  );
  expect(rect.left, 0);
  expect(rect.width, 900);
});
```

- [ ] **Step 2: 실패를 확인한다**

Run: `.fvm/flutter_sdk/bin/flutter.bat test test/cover_crop_test.dart`
Expected: FAIL — `alignX` 이름 있는 인자가 없다는 컴파일 오류

- [ ] **Step 3: `CoverCrop.rect`에 `alignX`를 더한다**

가로로 넘치는 쪽(`else` 가지)에서 `left`를 `((width - cropWidth) * (alignX.clamp(-1,1) + 1) / 2).round()`로 낸다. 세로로 넘치는 쪽은 그대로다 — 폭을 다 쓰므로 좌우로 밀 것이 없다. 문서 주석의 "가로로 넘친 사진은 **언제나 가운데다**"를 고친다.

- [ ] **Step 4: 통과를 확인한다**

Run: `.fvm/flutter_sdk/bin/flutter.bat test test/cover_crop_test.dart`
Expected: PASS

- [ ] **Step 5: `ImageCropper.crop`과 `UiImageCropper`에 `alignX`를 흘린다**

`crop`에 `double alignX = 0`을 더하고, `UiImageCropper`의 `_cropped` · `_croppedPng`를 거쳐 `CoverCrop.rect`까지 넘긴다. 임시 파일 이름의 `runiverse_cover_`는 그대로 둔다 — 고치면 이 Task가 커지고, 카드 사진은 Task 6이 자기 이름으로 만든다.

- [ ] **Step 6: 기존 호출자가 안 깨졌는지 전체로 확인한다**

Run: `.fvm/flutter_sdk/bin/flutter.bat analyze` 그리고 `.fvm/flutter_sdk/bin/flutter.bat test`
Expected: analyze `No issues found!` · 전체 통과 (프로필 커버·워치 사진이 기본값으로 돈다)

- [ ] **Step 7: 커밋**

```bash
git add lib/features/profile/domain/cover_crop.dart lib/features/profile/domain/image_cropper.dart lib/features/profile/data/ui_image_cropper.dart test/cover_crop_test.dart
git commit -m "📍 Feat: 9:16에서는 좌우로 밀어야 한다 — 크롭에 alignX를 더한다"
```

---

### Task 2: 초안이 사진·공개범위·음악을 든다

**Files:**
- Create: `lib/features/record_card/domain/card_photo_draft.dart`
- Modify: `lib/features/record_card/domain/card_draft.dart`
- Modify: `lib/features/record_card/presentation/card_draft_provider.dart`
- Test: `test/record_card_draft_test.dart` · `test/record_card_draft_provider_test.dart`

**Interfaces:**
- Consumes: `CardDraft` · `CardDraftController` (작성 1) · `PickedImage`(`profile/domain`) · `RecordCardVisibility`
- Produces:
  ```dart
  class CardPhotoDraft {
    const CardPhotoDraft({required this.image, this.caption = '',
                          this.alignX = 0, this.alignY = 0});
    final PickedImage image;
    final String caption;
    final double alignX;
    final double alignY;
    static const captionMaxLength = 100;
    static const aspectRatio = 9 / 16;
    CardPhotoDraft copyWith({String? caption, double? alignX, double? alignY});
  }

  // CardDraft에 추가
  final List<CardPhotoDraft> photos;          // 기본 const []
  final RecordCardVisibility visibility;      // 기본 RecordCardVisibility.friends
  final bool musicEnabled;                    // 기본 true
  static const maxPhotos = 5;
  bool get canAddPhoto;

  // CardDraftController에 추가
  void addPhoto(PickedImage image);
  void removePhotoAt(int index);
  void setCaption(int index, String text);
  void setPhotoAlign(int index, {double? alignX, double? alignY});
  void setVisibility(RecordCardVisibility visibility);
  void setMusicEnabled(bool enabled);
  ```

- [ ] **Step 1: 실패하는 테스트를 쓴다** (`test/record_card_draft_test.dart`)

```dart
test('사진 다섯 장이 차면 더 넣지 못한다', () {
  final draft = CardDraft(photos: List.filled(5, _photo()));
  expect(draft.canAddPhoto, isFalse);
  expect(CardDraft.maxPhotos, 5);
});

test('공개범위 기본값은 친구 공개, 음악은 켜짐이다', () {
  const draft = CardDraft();
  expect(draft.visibility, RecordCardVisibility.friends);
  expect(draft.musicEnabled, isTrue);
});

// ⚠️ 사진은 사용자가 손으로 넣은 것이다. 세지 않으면 조용히 버린다.
test('사진만 넣어도 버리기 전에 묻는다', () {
  final draft = CardDraft(photos: [_photo()]);
  expect(draft.isDirty, isTrue);
});

test('공개범위를 바꿔도 버리기 전에 묻는다', () {
  const draft = CardDraft(visibility: RecordCardVisibility.private);
  expect(draft.isDirty, isTrue);
});

test('사진은 다음 버튼의 조건이 아니다', () {
  // 설계 6-3: "사진은 선택이다. 한 장도 없이 다음을 누를 수 있다."
  final draft = CardDraft(
    record: _record(), activity: RecordCardActivity.daily, reviewText: '좋았다',
  );
  expect(draft.canProceed, isTrue);
});
```

`test/record_card_draft_provider_test.dart`:

```dart
test('캡션은 100자에서 자른다', () {
  final controller = _controller()..addPhoto(_image());
  controller.setCaption(0, 'ㄱ' * 200);
  expect(controller.state.photos.first.caption.characters.length, 100);
});

// ⚠️ Review Focus 4 — 회고에서 미뤄 둔 결함을 여기서는 되풀이하지 않는다.
test('이모지로 100자를 채워도 반쪽이 남지 않는다', () {
  final controller = _controller()..addPhoto(_image());
  controller.setCaption(0, '🏃' * 200);
  final caption = controller.state.photos.first.caption;
  expect(caption.characters.length, 100);
  expect(caption.runes.every((r) => r != 0xFFFD), isTrue);
  expect(caption.codeUnits.length, 200);   // 서로게이트 쌍 100개
});

test('여섯 번째 사진은 들어가지 않는다', () {
  final controller = _controller();
  for (var i = 0; i < 6; i++) { controller.addPhoto(_image()); }
  expect(controller.state.photos, hasLength(5));
});

test('지운 자리의 캡션은 아무 일도 하지 않는다', () {
  // 화면이 지운 뒤 늦게 온 콜백이다. 던지면 작성 중에 앱이 죽는다.
  final controller = _controller()..addPhoto(_image());
  controller.removePhotoAt(0);
  expect(() => controller.setCaption(0, '가'), returnsNormally);
  expect(controller.state.photos, isEmpty);
});

test('사진을 밀면 그 장만 바뀐다', () {
  final controller = _controller()..addPhoto(_image())..addPhoto(_image());
  controller.setPhotoAlign(1, alignX: -0.5);
  expect(controller.state.photos[0].alignX, 0);
  expect(controller.state.photos[1].alignX, -0.5);
});
```

- [ ] **Step 2: 실패를 확인한다**

Run: `.fvm/flutter_sdk/bin/flutter.bat test test/record_card_draft_test.dart test/record_card_draft_provider_test.dart`
Expected: FAIL — `photos` · `canAddPhoto` · `addPhoto` 등이 없다는 컴파일 오류

- [ ] **Step 3: `CardPhotoDraft`를 만든다**

`domain/card_photo_draft.dart`. 순수 Dart다 — `PickedImage`도 순수 Dart라 들어와도 된다. 자르는 일은 **여기서 하지 않는다**: 저장할 때 한 번에 한다(프로필 커버와 같은 순서). 그래서 이 값은 **원본 경로 + 밀어 둔 위치**다.

- [ ] **Step 4: `CardDraft`를 늘린다**

`photos` · `visibility` · `musicEnabled` · `maxPhotos` · `canAddPhoto`를 더하고 `copyWith`에 넣는다. `isDirty`에 `photos.isNotEmpty`와 **기본값에서 바뀐 공개범위·음악**을 더한다 — 안 세면 사용자가 고친 것을 조용히 버린다. `canProceed`는 **고치지 않는다**(사진은 선택이다).

- [ ] **Step 5: `CardDraftController`에 손잡이 여섯을 더한다**

자르기는 `characters` 패키지의 `String.characters.take(n)`으로 한다 — code unit으로 세면 이모지 경계에서 반쪽이 남는다. 범위를 넘는 `index`는 **아무 일도 하지 않는다.**

- [ ] **Step 6: 통과를 확인한다**

Run: `.fvm/flutter_sdk/bin/flutter.bat test test/record_card_draft_test.dart test/record_card_draft_provider_test.dart`
Expected: PASS

- [ ] **Step 7: 커밋**

```bash
git add lib/features/record_card/domain/card_photo_draft.dart lib/features/record_card/domain/card_draft.dart lib/features/record_card/presentation/card_draft_provider.dart test/record_card_draft_test.dart test/record_card_draft_provider_test.dart
git commit -m "📍 Feat: 초안이 사진·공개범위·음악을 든다"
```

---

### Task 3: 9:16 칸에서 넘치는 축으로 미는 미리보기

**Files:**
- Create: `lib/features/record_card/presentation/card_photo_pan.dart`
- Test: `test/record_card_photo_pan_test.dart`

**Interfaces:**
- Consumes: `CardPhotoDraft`
- Produces:
  ```dart
  /// 9:16 칸에 `BoxFit.cover`로 앉혔을 때 **축마다 넘치는 픽셀.** 모르면 0이다.
  ({double x, double y}) photoOverflow({required Size box, required Size image});

  class CardPhotoPan extends StatefulWidget {
    const CardPhotoPan({required this.photo, required this.onAlign,
                        this.enabled = true, super.key});
    final CardPhotoDraft photo;
    final void Function({double? alignX, double? alignY}) onAlign;
    final bool enabled;
  }
  ```

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
// 넘침 셈은 순수 함수로 꺼낸다 — 위젯 테스트로는 몇 픽셀 넘쳤는지 못 본다.
test('가로로 긴 사진은 좌우로 넘친다', () {
  final over = photoOverflow(
    box: const Size(270, 480), image: const Size(1600, 900),
  );
  // 높이를 480에 맞추면 폭이 853이 된다. 270을 넘는 583이 넘침이다.
  expect(over.x, closeTo(583.3, 0.5));
  expect(over.y, 0);
});

test('세로로 긴 사진은 위아래로 넘친다', () {
  final over = photoOverflow(
    box: const Size(270, 480), image: const Size(900, 1900),
  );
  expect(over.x, 0);
  expect(over.y, greaterThan(0));
});

test('9:16 사진은 어느 쪽으로도 넘치지 않는다', () {
  final over = photoOverflow(
    box: const Size(270, 480), image: const Size(900, 1600),
  );
  expect(over.x, closeTo(0, 0.5));
  expect(over.y, closeTo(0, 0.5));
});

testWidgets('가로로 넘치는 사진은 좌우로 밀린다', (tester) async {
  double? got;
  await _pump(tester, photo: _photo(), onAlign: ({alignX, alignY}) => got = alignX);
  await tester.drag(find.byType(CardPhotoPan), const Offset(-40, 0));
  expect(got, isNotNull);
  expect(got, lessThan(0));   // 왼쪽으로 끌면 오른쪽이 보인다
});

testWidgets('enabled가 false면 밀리지 않는다', (tester) async {
  var called = false;
  await _pump(tester, photo: _photo(), enabled: false,
              onAlign: ({alignX, alignY}) => called = true);
  await tester.drag(find.byType(CardPhotoPan), const Offset(-40, 0));
  expect(called, isFalse);
});
```

- [ ] **Step 2: 실패를 확인한다**

Run: `.fvm/flutter_sdk/bin/flutter.bat test test/record_card_photo_pan_test.dart`
Expected: FAIL — `photoOverflow` · `CardPhotoPan`이 없다

- [ ] **Step 3: `photoOverflow`와 `CardPhotoPan`을 만든다**

`background_picker.dart`의 `_BackgroundPreview`가 전례다 — 거기서 둘이 다르다.

1. **축을 고른다.** `photoOverflow`가 큰 쪽으로 민다. 가로로 넘치면 `onHorizontalDragUpdate`, 세로면 `onVerticalDragUpdate`. 둘 다 0이면 `GestureDetector`를 달지 않는다.
2. ⚠️ **방금 보낸 값에서 이어 간다.** 한 프레임에 끌기가 여러 번 오면 `widget.photo`가 아직 옛 값이다 — `_dragging`에 들고 있다가 `onDragEnd`에서 놓는다. 안 하면 끈 거리가 사라진다(전례의 주석과 같은 함정).
3. 크기는 `ImageStreamListener`로 읽고 **읽은 쪽이 `dispose`한다.**

- [ ] **Step 4: 통과를 확인한다**

Run: `.fvm/flutter_sdk/bin/flutter.bat test test/record_card_photo_pan_test.dart`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add lib/features/record_card/presentation/card_photo_pan.dart test/record_card_photo_pan_test.dart
git commit -m "📍 Feat: 9:16 칸에서 넘치는 축으로 사진을 민다"
```

---

### Task 4: 작성 2 — 사진

**Files:**
- Create: `lib/features/record_card/presentation/card_photo_page.dart`
- Modify: `lib/core/strings/app_strings.dart`
- Test: `test/record_card_photo_page_test.dart`

**Interfaces:**
- Consumes: `cardDraftProvider(int?)` · `CardPhotoPan` · `photoOverflow` · `photoPickerProvider`(`profile/presentation`) · `ProfileImageFailure`
- Produces:
  ```dart
  class CardPhotoPage extends ConsumerStatefulWidget {
    const CardPhotoPage({this.cardId, super.key});
    final int? cardId;      // null = 새 카드. 수정 묶음이 번호를 준다
  }
  ```

**새 `AppStrings`** (정렬 위치에):

```dart
static String recordCardPhotoTitle(int count, int max) => '사진 ($count/$max)';
static const recordCardPhotoAdd = '사진 추가';
static const recordCardPhotoEmpty = '사진은 넣지 않아도 괜찮아요';
static const recordCardPhotoPanHint = '사진을 밀어 보일 곳을 고르세요';
static const recordCardPhotoCaptionHint = '이 사진에 한마디 (선택)';
static const recordCardPhotoCaptionNote = 'AI가 음악을 만들 때 이 글을 읽어요';
static String recordCardPhotoCaptionCounter(int length, int max) => '$length / $max';
static const recordCardPhotoRemove = '이 사진 지우기';
static String recordCardPhotoLimit(int max) => '사진은 $max장까지 넣을 수 있어요';
static String recordCardPhotoSemantics(int index, int count) => '$count장 중 $index번째 사진';
static const recordCardPhotoPickFailed = '사진을 가져오지 못했어요';
static const recordCardPhotoUnsupported = '이 형식의 사진은 넣을 수 없어요';
static const recordCardPhotoTooLarge = '사진이 너무 커요';
```

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
testWidgets('사진이 없으면 괜찮다고 말하고 다음이 열려 있다', (tester) async {
  await _pump(tester, draft: _ready());      // 기록·유형·회고가 찬 초안
  expect(find.text(AppStrings.recordCardPhotoEmpty), findsOne);
  expect(_nextEnabled(tester), isTrue);
});

testWidgets('제목이 몇 장인지 센다', (tester) async {
  await _pump(tester, draft: _ready().copyWith(photos: [_photo(), _photo()]));
  expect(find.text(AppStrings.recordCardPhotoTitle(2, 5)), findsOne);
});

// ⚠️ Review Focus 2
testWidgets('보고 있던 마지막 장을 지워도 깨지지 않는다', (tester) async {
  await _pump(tester, draft: _ready().copyWith(photos: [_photo(), _photo(), _photo()]));
  await tester.drag(find.byType(PageView), const Offset(-800, 0));
  await tester.pumpAndSettle();
  await tester.drag(find.byType(PageView), const Offset(-800, 0));
  await tester.pumpAndSettle();                       // 3번째 장
  await tester.tap(find.text(AppStrings.recordCardPhotoRemove));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  expect(find.text(AppStrings.recordCardPhotoTitle(2, 5)), findsOne);
});

testWidgets('다섯 장이 차면 추가가 거절을 말한다', (tester) async {
  await _pump(tester, draft: _ready().copyWith(photos: List.filled(5, _photo())));
  await tester.tap(find.byTooltip(AppStrings.recordCardPhotoAdd));
  await tester.pumpAndSettle();
  expect(find.text(AppStrings.recordCardPhotoLimit(5)), findsOne);
});

testWidgets('고르기가 실패하면 왜인지 말한다', (tester) async {
  await _pump(tester, draft: _ready(),
              picker: _FailingPicker(ProfileImageFailure.unsupportedFormat));
  await tester.tap(find.byTooltip(AppStrings.recordCardPhotoAdd));
  await tester.pumpAndSettle();
  expect(find.text(AppStrings.recordCardPhotoUnsupported), findsOne);
});

testWidgets('취소는 실패가 아니다', (tester) async {
  await _pump(tester, draft: _ready(), picker: _CancellingPicker());
  await tester.tap(find.byTooltip(AppStrings.recordCardPhotoAdd));
  await tester.pumpAndSettle();
  expect(find.text(AppStrings.recordCardPhotoPickFailed), findsNothing);
  expect(tester.takeException(), isNull);
});

testWidgets('캡션을 쓰면 초안에 남고 글자 수가 보인다', (tester) async {
  await _pump(tester, draft: _ready().copyWith(photos: [_photo()]));
  await tester.enterText(find.byType(TextField), '바람이 좋았다');
  await tester.pump();
  expect(find.text(AppStrings.recordCardPhotoCaptionCounter(7, 100)), findsOne);
});

testWidgets('뒤로는 묻지 않고 초안을 지킨 채 돌아간다', (tester) async {
  // 확인은 작성 1의 뒤로가기에서만 받는다(설계 7절). 여기서 또 물으면
  // 사진을 보러 들어왔다 나가는 사람이 세 번 막힌다.
  final container = await _pump(tester, draft: _ready().copyWith(photos: [_photo()]));
  await tester.pageBack();
  await tester.pumpAndSettle();
  expect(find.text(AppStrings.recordCardComposeDiscardTitle), findsNothing);
  expect(container.read(cardDraftProvider(null)).photos, hasLength(1));
});
```

- [ ] **Step 2: 실패를 확인한다**

Run: `.fvm/flutter_sdk/bin/flutter.bat test test/record_card_photo_page_test.dart`
Expected: FAIL — `CardPhotoPage`가 없다

- [ ] **Step 3: `AppStrings`에 문구를 넣는다** (정렬 위치에)

- [ ] **Step 4: `CardPhotoPage`를 만든다**

위에서 아래로: `AppBar`(뒤로 · `recordCardPhotoTitle` · `다음`) → 9:16 `PageView`(각 장은 `CardPhotoPan`, 마지막 칸은 `+`) → 점 인디케이터 → 캡션 `TextField`(`maxLength`는 쓰지 않는다 — 기본 카운터가 `AppStrings`를 거치지 않는다. `recordCardPhotoCaptionCounter`를 직접 그린다) → `이 사진 지우기`.

- 사진이 0장이면 페이저 대신 `recordCardPhotoEmpty`와 `+` 하나를 둔다.
- `PageController`는 사진 수가 줄 때 **범위를 넘지 않게 맞춘다**(Review Focus 2).
- 캡션 칸은 **장을 넘길 때 그 장의 값으로 바뀐다** — `TextEditingController`를 장마다 새로 만들지 말고 하나를 두고 `text`를 갈아 끼운다.
- 고르기는 `ref.read(photoPickerProvider).pick()`이다. `ProfileImageException`을 받아 `ProfileImageFailure`를 카드 문구로 옮긴다. **취소(`null`)는 아무 일도 하지 않는다.**
- `다음`은 `draft.canProceed`를 따른다. 누르면 `context.push(AppRoutes.recordCardNewPublish)` — **Task 7이 라우트를 만들기 전까지는 갈 데가 없다.** 이 Task에서는 핸들러를 비워 두지 않고 Task 7에서 한 줄을 채운다.
- `select`로 필요한 것만 본다 — 캡션 한 글자에 `CardPhotoPan`까지 다시 그려지면 사진이 끊긴다.
- 다크·라이트 둘 다, 빈 상태 포함.

- [ ] **Step 5: 통과를 확인한다**

Run: `.fvm/flutter_sdk/bin/flutter.bat test test/record_card_photo_page_test.dart`
Expected: PASS

- [ ] **Step 6: 커밋**

```bash
git add lib/features/record_card/presentation/card_photo_page.dart lib/core/strings/app_strings.dart test/record_card_photo_page_test.dart
git commit -m "📍 Feat: 기록카드 작성 2 — 사진 고르기·밀기·캡션"
```

---

### Task 5: 작성 3 — 공개범위 · 음악

**Files:**
- Create: `lib/features/record_card/presentation/card_publish_page.dart`
- Create: `lib/features/record_card/presentation/visibility_label.dart`
- Modify: `lib/core/strings/app_strings.dart`
- Test: `test/record_card_publish_page_test.dart`

**Interfaces:**
- Consumes: `cardDraftProvider(int?)` · `RecordCardVisibility`
- Produces:
  ```dart
  class CardPublishPage extends ConsumerWidget {
    const CardPublishPage({this.cardId, super.key});
    final int? cardId;
  }
  String recordCardVisibilityLabel(RecordCardVisibility visibility);
  String recordCardVisibilityBody(RecordCardVisibility visibility);
  ```

**새 `AppStrings`:**

```dart
static const recordCardPublishTitle = '저장하기';
static const recordCardPublishSave = '저장';
static const recordCardPublishVisibilitySection = '누가 볼 수 있나요';
static const recordCardVisibilityPublic = '전체 공개';
static const recordCardVisibilityPublicBody = '누구나 봅니다';
static const recordCardVisibilityFriends = '친구 공개';
static const recordCardVisibilityFriendsBody = '친구만 봅니다';
static const recordCardVisibilityPrivate = '나만 보기';
static const recordCardVisibilityPrivateBody = '나만 봅니다';
/// ⚠️ 설계 6-4는 "지도로"라고 썼지만 기록카드의 경로는 **배경 없는 선 아트**다
/// (같은 문서 3절). 지도라고 말하면 보고 있지 않은 것을 경고하는 셈이다.
static const recordCardPublishRouteWarning = '공개하면 달린 경로가 선으로 함께 보입니다';
static const recordCardPublishMusicTitle = 'AI 음악 만들기';
static const recordCardPublishMusicBody =
    '회고와 러닝 기록으로 30초, 사진마다 10초짜리 곡을 만듭니다. 몇 분에서 길게는 더 걸립니다.';
static const recordCardPublishSaveFailed = '저장하지 못했어요';
```

"친구"라는 말은 설계 3절이 이미 정리했다 — 사용자가 공개범위를 `Friends`로 확정했고, 코드에 이미 `features/friend/`가 있다. CLAUDE.md 문구가 낡았고 고치는 것은 이 작업의 범위 밖이다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
testWidgets('기본값은 친구 공개와 음악 켜짐이다', (tester) async {
  await _pump(tester, draft: _ready());
  expect(_selected(tester), AppStrings.recordCardVisibilityFriends);
  expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
});

testWidgets('전체 공개와 친구 공개에서만 경로 경고가 뜬다', (tester) async {
  await _pump(tester, draft: _ready());
  expect(find.text(AppStrings.recordCardPublishRouteWarning), findsOne);

  await tester.tap(find.text(AppStrings.recordCardVisibilityPrivate));
  await tester.pumpAndSettle();
  expect(find.text(AppStrings.recordCardPublishRouteWarning), findsNothing);

  await tester.tap(find.text(AppStrings.recordCardVisibilityPublic));
  await tester.pumpAndSettle();
  expect(find.text(AppStrings.recordCardPublishRouteWarning), findsOne);
});

testWidgets('고른 공개범위가 초안에 남는다', (tester) async {
  final container = await _pump(tester, draft: _ready());
  await tester.tap(find.text(AppStrings.recordCardVisibilityPrivate));
  await tester.pumpAndSettle();
  expect(container.read(cardDraftProvider(null)).visibility,
         RecordCardVisibility.private);
});

testWidgets('음악을 끄면 초안에 남는다', (tester) async {
  final container = await _pump(tester, draft: _ready());
  await tester.tap(find.byType(Switch));
  await tester.pumpAndSettle();
  expect(container.read(cardDraftProvider(null)).musicEnabled, isFalse);
});

testWidgets('공개범위 셋이 이름·설명과 고른 상태를 함께 읽힌다', (tester) async {
  await _pump(tester, draft: _ready());
  for (final visibility in RecordCardVisibility.values) {
    expect(find.text(recordCardVisibilityLabel(visibility)), findsOne);
    expect(find.text(recordCardVisibilityBody(visibility)), findsOne);
  }
  // 고른 것은 `selected`로 읽힌다 — 글자만 있으면 무엇이 켜졌는지 모른다.
  final node = tester.getSemantics(
    find.text(AppStrings.recordCardVisibilityFriends),
  );
  expect(node, matchesSemantics(label: contains('친구 공개'), isSelected: true));
});
```

- [ ] **Step 2: 실패를 확인한다**

Run: `.fvm/flutter_sdk/bin/flutter.bat test test/record_card_publish_page_test.dart`
Expected: FAIL — `CardPublishPage`가 없다

- [ ] **Step 3: 문구와 `visibility_label.dart`를 만든다**

`activity_label.dart`와 같은 꼴이다 — `AppStrings`가 feature의 enum을 import하면 의존이 거꾸로 서므로, 문구는 `AppStrings`에 두고 고르는 일만 여기서 한다.

- [ ] **Step 4: `CardPublishPage`를 만든다**

`AppBar`(뒤로 · `recordCardPublishTitle` · `저장`) → 공개범위 셋(`RadioListTile`이 아니라 `activity_filter.dart`의 타일 꼴을 따른다) → 경고 한 줄(`public`·`friends`에서만) → 구분선 → 음악 토글 + 설명.

`저장`은 **이 Task에서 아무 데도 가지 않는다** — Task 6이 붙인다. 테스트도 Task 6에서 쓴다.

- [ ] **Step 5: 통과를 확인한다**

Run: `.fvm/flutter_sdk/bin/flutter.bat test test/record_card_publish_page_test.dart`
Expected: PASS

- [ ] **Step 6: 커밋**

```bash
git add lib/features/record_card/presentation/card_publish_page.dart lib/features/record_card/presentation/visibility_label.dart lib/core/strings/app_strings.dart test/record_card_publish_page_test.dart
git commit -m "📍 Feat: 기록카드 작성 3 — 공개범위와 음악 토글"
```

---

### Task 6: 저장 — 자르고, 썸네일을 만들고, 카드를 만든다

**Files:**
- Create: `lib/features/record_card/domain/new_record_card.dart`
- Create: `lib/features/record_card/domain/card_thumbnail_maker.dart`
- Create: `lib/features/record_card/data/compressed_card_thumbnail_maker.dart`
- Create: `lib/features/record_card/presentation/card_save_provider.dart`
- Modify: `lib/features/record_card/domain/record_card_repository.dart`
- Modify: `lib/features/record_card/data/fake_record_card_repository.dart`
- Modify: `lib/features/record_card/presentation/record_card_cell.dart`
- Modify: `lib/features/record_card/presentation/card_publish_page.dart`
- Test: `test/record_card_save_test.dart` · `test/record_card_cell_test.dart`

**Interfaces:**
- Consumes: `CardDraft` · `ImageCropper`(`imageCropperProvider`) · `RecordCardRepository` · `RouteArt.empty`
- Produces:
  ```dart
  class NewRecordCard {
    const NewRecordCard({required this.record, required this.route,
      required this.activity, required this.visibility,
      required this.reviewText, required this.photos,
      required this.musicEnabled});
    final RunRecord record;  final RouteArt route;
    final RecordCardActivity activity;
    final RecordCardVisibility visibility;
    final String reviewText;
    final List<NewCardPhoto> photos;
    final bool musicEnabled;
  }
  class NewCardPhoto {
    const NewCardPhoto({required this.path, required this.thumbnailPath,
                        this.caption});
    final String path;            // 9:16으로 자른 결과
    final String? thumbnailPath;  // 못 만들었으면 null
    final String? caption;
  }

  // RecordCardRepository에 추가
  Future<RecordCard> create(NewRecordCard card);

  abstract interface class CardThumbnailMaker {
    /// 자른 9:16 한 장에서 **긴 변 320px** JPEG를 만든다.
    /// 못 만들면 `null` — 썸네일이 없어도 카드는 산다.
    Future<String?> make(String croppedPath);
    static const longEdge = 320;
  }

  final cardThumbnailMakerProvider = Provider<CardThumbnailMaker>(
    (ref) => const CompressedCardThumbnailMaker(),
  );

  /// `record_card_state.dart`의 sealed union 꼴을 따른다(freezed 미도입).
  sealed class CardSaveState { const CardSaveState(); }
  class CardSaveIdle extends CardSaveState { const CardSaveIdle(); }
  class CardSaveSaving extends CardSaveState { const CardSaveSaving(); }
  class CardSaveFailed extends CardSaveState {
    const CardSaveFailed(this.failure);
    final RecordCardFailure failure;
  }

  final cardSaveProvider =
      NotifierProvider.family<CardSaveController, CardSaveState, int?>(
        CardSaveController.new,
      );
  // CardSaveController.save(CardDraft draft) → Future<RecordCard?>
  //   만들었으면 카드, 실패했으면 null. 화면은 null에서 머문다.
  ```

- [ ] **Step 1: 실패하는 테스트를 쓴다** (`test/record_card_save_test.dart`)

```dart
test('저장은 사진을 9:16으로 자르고 썸네일을 붙인다', () async {
  final cropper = _RecordingCropper();
  final container = _container(cropper: cropper);
  await container.read(cardSaveProvider(null).notifier).save(_draftWith2Photos());
  expect(cropper.calls.map((c) => c.aspectRatio),
         everyElement(closeTo(9 / 16, 1e-9)));
  expect(cropper.calls, hasLength(2));
});

test('자른 결과를 올린다 — 원본이 아니다', () async {
  // 설계 6-3: "서버에 올리는 원본은 크롭 결과다."
  final card = await _save(_draftWith2Photos());
  expect(card.photos.first.url, _croppedPath);
});

test('밀어 둔 위치가 자르기로 넘어간다', () async {
  final cropper = _RecordingCropper();
  final container = _container(cropper: cropper);
  await container.read(cardSaveProvider(null).notifier)
      .save(_draftWithPhoto(alignX: -0.4));
  expect(cropper.calls.single.alignX, -0.4);
});

test('썸네일을 못 만들어도 카드는 산다', () async {
  final card = await _save(_draftWith2Photos(), thumbnails: _FailingThumbnails());
  expect(card.photos.first.thumbnailUrl, isNull);
  expect(card.photos, hasLength(2));
});

test('경로가 없는 러닝은 빈 선 아트로 저장된다', () async {
  // 트레드밀이다. RecordCard.route는 null을 받지 못한다.
  final card = await _save(_draftWithoutRoute());
  expect(card.route.isEmpty, isTrue);
});

// ⚠️ Review Focus 1
test('고른 파일이 사라졌으면 실패하고 초안을 지키지 않는다', () async {
  final container = _container(cropper: _MissingFileCropper());
  final controller = container.read(cardSaveProvider(null).notifier);
  await controller.save(_draftWith2Photos());
  expect(container.read(cardSaveProvider(null)), isA<CardSaveFailed>());
  // 초안은 그대로다 — 비우면 회고까지 잃는다.
  expect(container.read(cardDraftProvider(null)).reviewText, isNotEmpty);
});

// ⚠️ Review Focus 3
test('저장 중에 또 누르면 카드가 하나만 생긴다', () async {
  final repository = _SlowFakeRepository();
  final container = _container(repository: repository);
  final controller = container.read(cardSaveProvider(null).notifier);
  final first = controller.save(_draftWith2Photos());
  final second = controller.save(_draftWith2Photos());
  await Future.wait([first, second]);
  expect(repository.creates, 1);
});

test('자른 임시 파일은 성공이든 실패든 치운다', () async {
  final cropper = _RecordingCropper();
  await _save(_draftWith2Photos(), cropper: cropper);
  expect(cropper.discarded, hasLength(2));
});

test('만든 카드는 Fake의 그날 목록에 들어간다', () async {
  final repository = FakeRecordCardRepository(today: _today);
  final card = await repository.create(_newCard());
  final sameDay = await repository.byDateRange(from: card.day, to: card.day);
  expect(sameDay.map((c) => c.id), contains(card.id));
});
```

`test/record_card_cell_test.dart`에 추가:

```dart
test('로컬 파일 경로는 파일에서 읽는다', () {
  // 서버가 없어 방금 만든 카드의 사진이 기기 안 파일이다.
  expect(cardThumbnail(_context, '/data/user/0/cache/a.jpg'), isA<FileImage>());
  expect(cardThumbnail(_context, 'assets/images/a.jpg'), isA<AssetImage>());
  expect(cardThumbnail(_context, 'https://x/a.jpg'), isA<ProfilePhotoImage>());
});
```

- [ ] **Step 2: 실패를 확인한다**

Run: `.fvm/flutter_sdk/bin/flutter.bat test test/record_card_save_test.dart test/record_card_cell_test.dart`
Expected: FAIL — `NewRecordCard` · `cardSaveProvider` · `create`가 없다

- [ ] **Step 3: `NewRecordCard`와 `CardThumbnailMaker`를 만든다**

`NewCardPhoto`가 **이미 자른 경로**를 든다 — 자르는 것은 `data`의 일이고 `domain`은 `dart:io`를 못 본다. 자르기를 부르는 것은 `presentation`의 `cardSaveProvider`이고, `imageCropperProvider`로 받는다(CLAUDE.md가 허용한 provider 공유).

- [ ] **Step 4: `RecordCardRepository.create`와 Fake 구현을 만든다**

Fake는 만든 카드를 `_created` 목록에 쌓고 `byDateRange`가 목 데이터와 **함께** 돌려준다. `id`는 목 데이터와 겹치지 않는 자리에서 센다. `failWith`가 있으면 `create`도 던진다 — 저장 실패 화면을 눈으로 보는 길이다.

⚠️ **`runners`는 빈 목록이다.** `RunRecord`는 `playerCount`만 있고 함께 뛴 사람의 닉네임·프로필을 모른다. 서버가 붙으면 응답이 싣는다.

⚠️ **앱을 끄면 만든 카드는 사라진다.** 메모리다. 영속화하지 않는다 — 서버가 올 자리에 로컬 DB를 세우면 서버가 올 때 두 번 걷어낸다.

- [ ] **Step 5: `compressed_card_thumbnail_maker.dart`를 만든다**

`FlutterImageCompress`로 **긴 변 320px**. 9:16이라 긴 변은 세로다 → `minHeight: 320`, `minWidth: 180`. 실패하면 **던지지 않고 `null`** — 썸네일이 없으면 원본을 쓰고, 카드가 안 생기는 것보다 낫다.

- [ ] **Step 6: `cardSaveProvider`를 만든다**

순서: 사진마다 `crop(aspectRatio: 9/16, alignX:, alignY:)` → `make(thumbnail)` → `repository.create` → **성공하면 `draft.clear()`** → 자른 임시 파일 `discard`(성공·실패 모두).

⚠️ **이미 저장 중이면 두 번째 호출은 바로 돌아간다**(Review Focus 3). ⚠️ **실패하면 초안을 비우지 않는다**(Review Focus 1).

- [ ] **Step 7: `cardThumbnail`에 파일 분기를 더한다**

`assets/` → `AssetImage`, `http` → `ProfilePhotoImage`, **나머지 → `FileImage`.** 순서가 중요하다. 주석에 **HTTP 구현체가 붙어도 이 분기는 남는다**고 적는다 — 방금 만든 카드는 올라가기 전까지 기기 안 파일이다.

- [ ] **Step 8: `저장` 버튼을 붙인다**

`CardPublishPage`의 `저장`이 `cardSaveProvider`를 부른다. 도는 동안 버튼이 진행 표시로 바뀌고 **다시 눌리지 않는다.** 실패하면 `recordCardPublishSaveFailed`를 띄우고 **화면에 머문다.**

- [ ] **Step 9: 통과를 확인한다**

Run: `.fvm/flutter_sdk/bin/flutter.bat test` 그리고 `.fvm/flutter_sdk/bin/flutter.bat analyze`
Expected: 전체 통과 · `No issues found!`

- [ ] **Step 10: 커밋**

```bash
git add lib/features/record_card/ test/record_card_save_test.dart test/record_card_cell_test.dart
git commit -m "📍 Feat: 저장 — 사진을 자르고 썸네일을 붙여 카드를 만든다"
```

---

### Task 7: 세 화면을 잇는다 — 라우트와 저장 뒤 상세

**Files:**
- Modify: `lib/app/router/app_routes.dart`
- Modify: `lib/app/router/app_router.dart`
- Modify: `lib/features/record_card/presentation/card_photo_page.dart`
- Modify: `lib/features/record_card/presentation/card_publish_page.dart`
- Test: `test/record_card_compose_flow_test.dart`

**Interfaces:**
- Consumes: `CardPhotoPage` · `CardPublishPage` · `AppRoutes.recordCardDetailOf`
- Produces:
  ```dart
  static const recordCardNewPhotos = '/record-card/new/photos';
  static const recordCardNewPublish = '/record-card/new/publish';
  ```

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
// `_pumpFlow`는 실제 `createAppRouter`를 태운다 — 작성 1의 미뤄 둔 Minor 8번
// ("실제 라우터를 타는 테스트가 없다")이 여기서 함께 덮인다.
testWidgets('작성 1의 다음이 사진으로 간다', (tester) async {
  await _pumpFlow(tester, at: AppRoutes.recordCardNewOn(_today));
  await _fillCompose(tester);                      // 기록·유형·회고
  await tester.tap(find.text(AppStrings.recordCardComposeNext));
  await tester.pumpAndSettle();
  expect(find.byType(CardPhotoPage), findsOne);
});

testWidgets('사진의 다음이 공개범위로 간다', (tester) async {
  await _pumpFlow(tester, at: AppRoutes.recordCardNewPhotos, draft: _ready());
  await tester.tap(find.text(AppStrings.recordCardComposeNext));
  await tester.pumpAndSettle();
  expect(find.byType(CardPublishPage), findsOne);
});

testWidgets('저장하면 상세로 가고 작성 화면들이 걷힌다', (tester) async {
  // 설계 6-4: "카드가 만들어지고 상세로 간다(작성 화면들은 스택에서 걷힌다)."
  await _pumpFlow(tester, at: AppRoutes.recordCardNewPublish, draft: _ready());
  await tester.tap(find.text(AppStrings.recordCardPublishSave));
  await tester.pumpAndSettle();
  expect(find.byType(CardDetailPage), findsOne);

  await tester.pageBack();
  await tester.pumpAndSettle();
  expect(find.byType(RecordCardPage), findsOne);   // 캘린더다. 작성 3이 아니다
  expect(find.byType(CardPublishPage), findsNothing);
});

testWidgets('초안이 비면 사진·공개범위는 탭으로 돌려보낸다', (tester) async {
  // 딥링크나 프로세스 복원으로 중간 화면에 바로 떨어지는 길이다.
  for (final route in [
    AppRoutes.recordCardNewPhotos,
    AppRoutes.recordCardNewPublish,
  ]) {
    await _pumpFlow(tester, at: route);            // 초안을 주지 않는다
    expect(find.byType(RecordCardPage), findsOne, reason: route);
  }
});
```

- [ ] **Step 2: 실패를 확인한다**

Run: `.fvm/flutter_sdk/bin/flutter.bat test test/record_card_compose_flow_test.dart`
Expected: FAIL — 라우트가 없다

- [ ] **Step 3: 라우트 둘을 더한다**

`app_routes.dart`의 **정렬 위치에** 넣는다(맨 끝은 충돌한다). `app_router.dart`에 **셸 밖**으로 선언한다. `/record-card/card/:id`가 이미 `/card/`로 갈라 두어 `:id` 충돌은 없다.

⚠️ **초안이 비어 있으면 탭으로 돌려보낸다.** 카드 상세가 `extra` 없으면 돌려보내는 것과 같은 꼴이다 — 작성 1을 거치지 않고 떨어지면 고를 기록도, 쓴 회고도 없다.

- [ ] **Step 4: 버튼 셋을 잇는다**

작성 1의 `다음` → `recordCardNewPhotos`, 작성 2의 `다음` → `recordCardNewPublish`. 작성 1의 비어 있던 `onPressed: draft.canProceed ? () {} : null`이 여기서 채워진다.

- [ ] **Step 5: 저장 뒤 상세로 보낸다**

```dart
// go로 가면 셸 밖 라우트 아래에 스택이 없어 안드로이드 뒤로가 앱을 닫는다.
// 작성 셋을 걷고 상세를 밀어, 뒤로가 캘린더로 떨어지게 한다.
final router = GoRouter.of(context);
while (router.canPop()) { router.pop(); }
router.push(AppRoutes.recordCardDetailOf(card.id), extra: card);
```

⚠️ **러닝 요약에서 들어온 경우까지 걷는다**(묶음 6). 그때 이 줄을 다시 본다.

- [ ] **Step 6: 통과를 확인한다**

Run: `.fvm/flutter_sdk/bin/flutter.bat test` 그리고 `.fvm/flutter_sdk/bin/flutter.bat analyze` 그리고 `.fvm/flutter_sdk/bin/dart.bat format --set-exit-if-changed lib test`
Expected: 전체 통과 · `No issues found!` · 포맷 변화 없음

- [ ] **Step 7: 커밋**

```bash
git add lib/app/router/ lib/features/record_card/presentation/ test/record_card_compose_flow_test.dart
git commit -m "📍 Feat: 작성 세 화면을 잇고, 저장하면 상세로 보낸다"
```

---

## 끝낸 뒤

**이 묶음까지 끝나면 PR을 올린다 — 작성 1(PR 2)과 함께.** 작성 1은 `다음`이 갈
곳이 없어 혼자 올리면 막힌 버튼을 내보낸다. 두 묶음을 합치면 **20파일 / 500줄을
넘으므로 사유를 PR에 적는다**(CLAUDE.md가 허용하는 예외).

PR 본문의 **💬 리뷰 포인트**는 두 곳에서 나온다:
`docs/notes/2026-11-18-record-card-compose-deferred.md`(작성 1)와 이 묶음이 남길 같은 꼴의 기록.

**기기 확인이 아직 없다.** 작성 1도 위젯 테스트만 통과한 상태다. 사진 고르기는
플랫폼 채널이라 **테스트가 닿지 못하는 자리**이고(`GalleryPhotoPicker`의 주석),
크롭 결과가 눈으로 본 것과 같은지는 기기에서만 보인다. SSH 터널과 실제 러닝 기록이
필요하다.
