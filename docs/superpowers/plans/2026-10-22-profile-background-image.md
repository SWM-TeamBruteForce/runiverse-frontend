# 프로필 배경 이미지 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 프로필 화면 맨 위에 커버 사진을 깔고, 프로필 편집 화면에서 바꾸고 지울 수 있게 한다.

**Architecture:** 프로필 사진의 3단계 업로드(발급 → S3 PUT → 등록)를 `ProfileImageKind`로 갈라 저장소 하나를 두 종류로 쓴다. 고르는 경로(갤러리·EXIF 제거·압축)와 시트는 그대로 함께 쓰고, 컨트롤러만 배경용을 하나 더 둔다. 화면은 커버를 상태바 뒤까지 올리고 그늘막으로 시계를 지킨다.

**Tech Stack:** Flutter + fvm · Riverpod 3(`Notifier`/`Provider`) · dio · `flutter_image_compress`

**Spec:** `docs/specs/2026-10-22-profile-background-image-design.md`

## Global Constraints

- 모든 flutter/dart 명령 앞에 `fvm` — 이 저장소는 `./.fvm/flutter_sdk/bin/flutter.bat`
- `fvm flutter analyze` 경고 **0개**, `fvm dart format lib test`
- 색·치수·문자열은 토큰으로만: `context.appColorsV2` · `AppSpacing` · `AppRadius` · `AppTypographyV2` · `AppStrings`
- 아이콘은 **Lucide만**. `Icons.*` 금지
- `presentation → domain ← data`. presentation은 data를 import하지 않는다
- 허용 MIME은 `image/jpeg` · `image/png` · `image/webp`, 크기는 **1바이트~10,485,760바이트**
- 조회(`GET /users/{userId}/background-image`)에는 **`Authorization`을 붙이지 않는다**
- 압축·변환은 **발급 요청 전에** 끝난다. 발급 뒤 파일이 바뀌면 403
- 커밋은 `<이모지> <type>: <설명>`, AI 공동 작성자 트레일러 금지

## Review Focus

사양이 요구하지만 어느 작업의 테스트도 건드리지 않는 입력들이다. 각 줄의 테스트를 그것을 가진 작업에 넣어 두었다.

1. **종류를 섞은 Key** — 프로필 Key로 배경을 등록하면 서버가 `INVALID_BACKGROUND_IMAGE`를 준다. 저장소가 **자기 종류의 경로·필드만** 쓰는지 (Task 1)
2. **조회에 토큰이 붙는 경우** — 만료된 토큰이 붙으면 공개 API가 401을 준다. 배경 조회에 헤더가 **없는지** (Task 1)
3. **깨진 커버의 되풀이 조회** — 만료 주소가 계속 실패하면 재조회가 무한히 돈다. **한 번만** 다시 받는지 (Task 5)
4. **저장 중 배경만 실패** — 프로필 값이 함께 나가면 반만 저장된다. 배경이 실패하면 **거기서 멈추는지** (Task 6)
5. **기본 배경일 때의 그늘막** — 상태에 따라 켜고 끄면 틀렸을 때 **시계가 사라지는 쪽으로** 틀린다. 사진이 없어도 깔리는지 (Task 4)

---

### Task 1: 저장소를 종류로 가른다

**Files:**
- Create: `lib/features/profile/domain/profile_image_kind.dart`
- Modify: `lib/features/profile/data/http_profile_image_repository.dart`
- Modify: `lib/features/profile/data/fake_profile_image_repository.dart` (필요하면 종류를 들고 있게)
- Test: `test/http_profile_image_repository_test.dart` (없으면 생성)

**Interfaces:**
- Consumes: 없음
- Produces:
  - `enum ProfileImageKind { profile, background }` — `String get mePath` · `String userPath(String userId)` · `String get keyField` · `String get urlField`
  - `HttpProfileImageRepository(Dio dio, TokenStore store, AuthRepository auth, {Dio? uploadDio, ProfileImageKind kind = ProfileImageKind.profile})`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
test('⚠️ 배경은 배경 경로로만 간다', () async {
  // 프로필 Key로 배경을 등록하면 서버가 INVALID_BACKGROUND_IMAGE를 준다.
  final repository = _repositoryOf(ProfileImageKind.background);
  await repository.upload(_image());

  expect(dio.paths, [
    '/api/v1/users/me/background-image/presigned-url',
    '/api/v1/users/me/background-image',
  ]);
  expect(dio.bodies.last.keys, ['backgroundImageKey']);
});

test('프로필은 프로필 경로로 간다', () async {
  final repository = _repositoryOf(ProfileImageKind.profile);
  await repository.upload(_image());

  expect(dio.paths.first, '/api/v1/users/me/profile-image/presigned-url');
  expect(dio.bodies.last.keys, ['profileImageKey']);
});

test('⚠️ 조회에는 토큰을 붙이지 않는다', () async {
  // 공개 API라도 헤더가 있으면 토큰을 검사한다 — 만료된 것이 붙으면 401이다.
  await _repositoryOf(ProfileImageKind.background).fetchUrl();

  expect(dio.lastHeaders, isNot(contains('Authorization')));
});

test('조회 응답의 필드 이름도 종류를 따른다', () async {
  dio.getResponse = {'backgroundImageUrl': 'https://x'};

  expect(await _repositoryOf(ProfileImageKind.background).fetchUrl(), 'https://x');
});

test('⚠️ 발급 요청의 크기·형식이 고른 파일과 같다', () async {
  // 서명이 이 값으로 만들어진다. 하나라도 다르면 S3가 403을 준다.
  final image = _image(mimeType: 'image/jpeg', sizeBytes: 248392);
  await _repositoryOf(ProfileImageKind.background).upload(image);

  expect(dio.bodies.first, {'mimeType': 'image/jpeg', 'fileSizeBytes': 248392});
  expect(upload.lastHeaders['Content-Type'], 'image/jpeg');
  expect(upload.lastHeaders['Content-Length'], '248392');
});
```

- [ ] **Step 2: 실패를 확인한다**

Run: `./.fvm/flutter_sdk/bin/flutter.bat test test/http_profile_image_repository_test.dart`
Expected: FAIL — `ProfileImageKind`가 없다

- [ ] **Step 3: `ProfileImageKind`를 만들고 저장소가 그것을 쓰게 한다**

`enum`이 경로·필드 이름을 전부 들고 있게 한다(사양 1절 표). 저장소의 `_mePath`·`_userPath`·요청 본문 키·응답 키를 `kind`에서 읽는다. **`kind`는 `final`이고 생성자에서만 정한다** — 메서드 인자로 받으면 한 객체가 두 종류를 오가며 Key를 섞을 수 있다.

기본값은 `ProfileImageKind.profile`로 두어 기존 호출부가 그대로 돈다.

- [ ] **Step 4: 통과를 확인한다**

Run: `./.fvm/flutter_sdk/bin/flutter.bat test test/http_profile_image_repository_test.dart`
Expected: PASS

- [ ] **Step 5: 변이 하나를 심어 그물을 확인한다**

`kind`를 무시하고 프로필 경로를 하드코딩해 본다. **배경 테스트가 떨어져야 한다.** 확인 후 되돌린다.

- [ ] **Step 6: 커밋**

```bash
git add lib/features/profile/domain/profile_image_kind.dart lib/features/profile/data/ test/http_profile_image_repository_test.dart
git commit -m "📍 Feat: 이미지 저장소를 종류로 가른다"
```

---

### Task 2: 배경용 provider와 컨트롤러

**Files:**
- Create: `lib/features/profile/presentation/background_image_provider.dart`
- Test: `test/background_image_controller_test.dart`

**Interfaces:**
- Consumes: Task 1의 `ProfileImageKind` · `HttpProfileImageRepository(..., kind:)`
- Produces:
  - `backgroundImageRepositoryProvider` — `Provider<ProfileImageRepository>`
  - `backgroundImageControllerProvider` — `NotifierProvider<BackgroundImageController, ProfileImageState>`
  - `BackgroundImageController` — `load()` · `pick()` · `apply(PendingPhoto)` · `retryOnce()`

`load`·`pick`·`apply`의 시그니처와 동작은 `ProfileImageController`와 같다. `retryOnce()`는 이 컨트롤러에만 있다 — Task 5가 쓴다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
test('조회하면 주소를 세운다', () async {
  repository.url = 'https://cover';
  await container.read(backgroundImageControllerProvider.notifier).load();

  expect(container.read(backgroundImageControllerProvider), isA<ProfileImageReady>()
      .having((s) => s.url, 'url', 'https://cover'));
});

test('⚠️ 올린 적이 없으면 실패가 아니다', () async {
  repository.url = null;
  await container.read(backgroundImageControllerProvider.notifier).load();

  expect(container.read(backgroundImageControllerProvider), isA<ProfileImageReady>()
      .having((s) => s.url, 'url', isNull));
});

test('올리는 동안 busy가 켜지고 끝나면 새 주소가 선다', () async { /* apply(PhotoPicked) */ });

test('⚠️ 올리기가 실패하면 원래 주소가 남는다', () async { /* 사진이 사라진 것처럼 보이면 안 된다 */ });

test('⚠️ 다시 받기는 한 번뿐이다', () async {
  // 만료가 되풀이되면 끝없이 두드린다.
  await controller.load();
  await controller.retryOnce();
  await controller.retryOnce();

  expect(repository.fetchCount, 2);
});

test('새로 올리면 다시 받기가 풀린다', () async {
  // 사진을 바꾸면 그 주소는 새것이다. 다음 만료에도 한 번은 다시 받아야 한다.
  await controller.load();
  await controller.retryOnce();
  await controller.apply(PhotoPicked(_image()));
  await controller.retryOnce();

  expect(repository.fetchCount, greaterThan(2));
});
```

- [ ] **Step 2: 실패를 확인한다**

Run: `./.fvm/flutter_sdk/bin/flutter.bat test test/background_image_controller_test.dart`
Expected: FAIL — `backgroundImageControllerProvider`가 없다

- [ ] **Step 3: provider와 컨트롤러를 만든다**

`ProfileImageController`를 그대로 따르되 저장소만 `backgroundImageRepositoryProvider`에서 읽는다. **피커는 `photoPickerProvider`를 그대로 쓴다**(압축 기본값이 배경에도 맞는다 — 사양 6절).

`retryOnce()`는 **이미 한 번 다시 받았으면 아무것도 하지 않는다.** 플래그는 `load()`와 `apply()` 성공에서 풀린다.

- [ ] **Step 4: 통과를 확인한다**

Run: `./.fvm/flutter_sdk/bin/flutter.bat test test/background_image_controller_test.dart`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add lib/features/profile/presentation/background_image_provider.dart test/background_image_controller_test.dart
git commit -m "📍 Feat: 배경 이미지 상태를 따로 둔다"
```

---

### Task 3: 문구

**Files:**
- Modify: `lib/core/strings/app_strings.dart`

**Interfaces:**
- Produces: `profileBackgroundSheetTitle` = `'배경 이미지'` · `profileEditBackground` = `'배경 바꾸기'` · `profileBackgroundLabel` = `'배경 이미지'`

시트의 두 항목(`앨범에서 선택` · `기본 이미지로`)은 **기존 문구를 그대로 쓴다.**

- [ ] **Step 1: 문구를 더한다** — 프로필 사진 문구 바로 아래, 왜 제목만 다른지 한 줄 주석
- [ ] **Step 2: 커밋**

```bash
git commit -am "🚚 Chore: 배경 이미지 문구를 더한다"
```

---

### Task 4: 커버 위젯

**Files:**
- Create: `lib/features/profile/presentation/profile_cover.dart`
- Test: `test/profile_cover_test.dart`

**Interfaces:**
- Consumes: Task 2의 `backgroundImageControllerProvider`
- Produces: `ProfileCover({Key? key})` — 폭 전체, 비율 `412:200`, 상태바 뒤까지 올라간다

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
testWidgets('주소가 있으면 사진을 그린다', (tester) async { /* Image 위젯이 있다 */ });

testWidgets('⚠️ 세 상태가 모두 기본 단색이다', (tester) async {
  // Loading · Ready{url: null} · Failed — 회전 표시를 넣지 않는다.
  for (final state in [const ProfileImageLoading(), const ProfileImageReady(), ...]) {
    await pumpCover(tester, state);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(Image), findsNothing);
  }
});

testWidgets('⚠️ 기본 배경일 때도 그늘막이 깔린다', (tester) async {
  // 상태에 따라 켜고 끄면 틀렸을 때 시계가 사라지는 쪽으로 틀린다.
  await pumpCover(tester, const ProfileImageReady());

  expect(find.byKey(ProfileCover.scrimKey), findsOneWidget);
});

testWidgets('⚠️ 위 여백을 받지 않는다', (tester) async {
  // 커버는 상태바 뒤까지 올라간다 — SafeArea 안에 있으면 띠가 생긴다.
  await pumpCover(tester, const ProfileImageReady(), topInset: 40);

  expect(tester.getTopLeft(find.byType(ProfileCover)).dy, 0);
});

testWidgets('비율이 412:200이다', (tester) async { /* 폭 412 → 높이 200 */ });
```

- [ ] **Step 2: 실패를 확인한다**

Run: `./.fvm/flutter_sdk/bin/flutter.bat test test/profile_cover_test.dart`
Expected: FAIL — `ProfileCover`가 없다

- [ ] **Step 3: `ProfileCover`를 만든다**

`AspectRatio(412/200)` 안에 `Stack`: 바탕(토큰 단색) → 주소가 있으면 `Image.network(fit: BoxFit.cover)` → **그늘막**(위에서 아래로 검정 40% → 투명, 상태바 높이 + `AppSpacing.space4`). 그늘막에 `scrimKey`를 단다.

`Image.network`의 `errorBuilder`에서 `retryOnce()`를 부른다(Task 5에서 배선 확인). `loadingBuilder`는 두지 않는다 — 바탕이 이미 기본 배경이다.

- [ ] **Step 4: 통과를 확인한다**

Run: `./.fvm/flutter_sdk/bin/flutter.bat test test/profile_cover_test.dart`
Expected: PASS

- [ ] **Step 5: 변이로 그물을 확인한다**

그늘막을 `url != null`일 때만 깔도록 바꿔 본다. **`기본 배경일 때도` 테스트가 떨어져야 한다.**

- [ ] **Step 6: 커밋**

```bash
git add lib/features/profile/presentation/profile_cover.dart test/profile_cover_test.dart
git commit -m "📍 Feat: 프로필 커버를 그린다"
```

---

### Task 5: 프로필 화면에 얹는다

**Files:**
- Modify: `lib/features/profile/presentation/profile_page.dart`
- Modify: `lib/features/profile/presentation/profile_header.dart`
- Test: `test/profile_page_test.dart` (없으면 생성) · `test/profile_header_test.dart`

**Interfaces:**
- Consumes: Task 4의 `ProfileCover` · Task 2의 `backgroundImageControllerProvider.load()`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
testWidgets('화면에 들어오면 배경을 한 번 받는다', (tester) async {
  expect(repository.fetchCount, 1);
});

testWidgets('⚠️ 커버가 깨지면 한 번 더 받는다', (tester) async {
  // 조회 주소는 1시간이면 만료된다. 커버가 비면 "안 올린 사람"과 구분되지 않는다.
  await pumpProfile(tester);
  _failCoverImage(tester);

  expect(repository.fetchCount, 2);
});

testWidgets('⚠️ 다시 받고도 깨지면 또 받지 않는다', (tester) async {
  await pumpProfile(tester);
  _failCoverImage(tester);
  _failCoverImage(tester);

  expect(repository.fetchCount, 2);
});

testWidgets('⚠️ 설정 버튼이 커버 위에 있지 않다', (tester) async {
  // 사진 위 흰 아이콘은 밝은 사진에서 안 보인다.
  await pumpProfile(tester);

  final cover = tester.getRect(find.byType(ProfileCover));
  final settings = tester.getRect(find.bySemanticsLabel(AppStrings.settingsTitle));
  expect(settings.top, greaterThanOrEqualTo(cover.bottom));
});

testWidgets('⚠️ 아바타가 커버에 걸친다', (tester) async {
  await pumpProfile(tester);

  final cover = tester.getRect(find.byType(ProfileCover));
  final avatar = tester.getRect(find.byType(ProfileAvatar));
  expect(avatar.top, lessThan(cover.bottom));
  expect(avatar.bottom, greaterThan(cover.bottom));
});

testWidgets('프로필을 떠나면 상태바 스타일이 돌아온다', (tester) async { /* AnnotatedRegion */ });
```

- [ ] **Step 2: 실패를 확인한다**

Run: `./.fvm/flutter_sdk/bin/flutter.bat test test/profile_page_test.dart test/profile_header_test.dart`
Expected: FAIL

- [ ] **Step 3: 화면을 배치한다**

`ProfilePage`: `SafeArea` **밖**에 `ProfileCover`를 두고 그 아래부터 지금 내용을 둔다. `initState`의 postFrame에서 `backgroundImageControllerProvider.notifier.load()`를 함께 부른다. 화면 전체를 `AnnotatedRegion<SystemUiOverlayStyle>`로 감싸 **이 화면에서만** 밝은 아이콘을 지정한다.

`ProfileHeader`: 설정 버튼을 **아바타 오른쪽, 편집 버튼 위**로 내린다. 아바타는 `Transform.translate`로 43 끌어올려 커버에 걸친다(사양 4절 그림).

⚠️ **알림 벨은 만들지 않는다.**

- [ ] **Step 4: 통과를 확인한다**

Run: `./.fvm/flutter_sdk/bin/flutter.bat test test/profile_page_test.dart test/profile_header_test.dart`
Expected: PASS

- [ ] **Step 5: 기존 그물이 성한지 본다**

Run: `./.fvm/flutter_sdk/bin/flutter.bat test`
Expected: 전부 통과. 헤더를 건드렸으므로 프로필 관련 위젯 테스트가 함께 돈다

- [ ] **Step 6: 커밋**

```bash
git add lib/features/profile/presentation/profile_page.dart lib/features/profile/presentation/profile_header.dart test/
git commit -m "📍 Feat: 프로필 화면에 커버를 얹는다"
```

---

### Task 6: 편집 화면에서 바꾼다

**Files:**
- Modify: `lib/features/profile/presentation/profile_edit_page.dart`
- Create: `lib/features/profile/presentation/background_picker.dart`
- Test: `test/profile_edit_background_test.dart`

**Interfaces:**
- Consumes: Task 2의 컨트롤러 · Task 3의 문구 · 기존 `showProfilePhotoSheet` · 기존 `PendingPhoto`
- Produces: `BackgroundPicker({PendingPhoto? pending, required ValueChanged<PendingPhoto> onPending})` — 2:1 미리보기, 누르면 시트

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
testWidgets('⚠️ 고른 것은 저장 전까지 올라가지 않는다', (tester) async {
  // 사진과 같은 규칙이다. 섞으면 한 화면에 규칙이 둘이 된다.
  await pickBackground(tester);

  expect(repository.uploads, isEmpty);
});

testWidgets('저장을 누르면 올라간다', (tester) async {
  await pickBackground(tester);
  await tapSave(tester);

  expect(repository.uploads, hasLength(1));
});

testWidgets('⚠️ 배경이 실패하면 프로필 값이 안 나간다', (tester) async {
  // 반만 저장되면 화면이 무엇을 들고 있는지 알 수 없다.
  repository.failUpload = true;
  await pickBackground(tester);
  await typeIntroduction(tester, '바뀐 소개');
  await tapSave(tester);

  expect(profileRepository.saved, isEmpty);
  expect(find.byType(ProfileEditPage), findsOneWidget, reason: '화면에 남는다');
});

testWidgets('기본 이미지로를 고르면 지운다', (tester) async { /* PhotoRemoved → remove() */ });

testWidgets('사진 → 배경 → 프로필 값 순서로 나간다', (tester) async { /* 순서 기록 */ });
```

- [ ] **Step 2: 실패를 확인한다**

Run: `./.fvm/flutter_sdk/bin/flutter.bat test test/profile_edit_background_test.dart`
Expected: FAIL — `BackgroundPicker`가 없다

- [ ] **Step 3: 미리보기와 저장 단계를 더한다**

`BackgroundPicker`는 아바타 블록 **아래**에 라벨과 함께 선다. 누르면 `showProfilePhotoSheet`를 제목만 바꿔 띄우고, 고른 것은 `pending`으로 화면이 들고 있는다.

`_save()`에 단계를 하나 더 끼운다 — **사진 → 배경 → 프로필 값**, 각 단계가 실패하면 거기서 멈춘다. 지금 `_savePhoto()`가 하는 모양 그대로다.

- [ ] **Step 4: 통과를 확인한다**

Run: `./.fvm/flutter_sdk/bin/flutter.bat test test/profile_edit_background_test.dart`
Expected: PASS

- [ ] **Step 5: 변이로 그물을 확인한다**

배경 실패에서 멈추지 않고 이어 가게 바꿔 본다. **`프로필 값이 안 나간다` 테스트가 떨어져야 한다.**

- [ ] **Step 6: 커밋**

```bash
git add lib/features/profile/presentation/ test/profile_edit_background_test.dart
git commit -m "📍 Feat: 편집 화면에서 배경을 바꾼다"
```

---

### Task 7: 전체 확인과 PR

- [ ] **Step 1: 형식·정적 분석·전체 테스트**

```bash
./.fvm/flutter_sdk/bin/dart.bat format lib test
./.fvm/flutter_sdk/bin/flutter.bat analyze     # 0개
./.fvm/flutter_sdk/bin/flutter.bat test        # 전부 통과
```

- [ ] **Step 2: 기기 확인**

에뮬레이터와 **호스트 8080 터널**이 모두 필요하다(터널은 사용자가 띄운다). 볼 것 넷:

1. 배경을 올리면 커버에 뜨고, 앱을 다시 켜도 남는다
2. **밝은 사진**에서 시계·배터리가 읽히는가 — 그늘막 진하기를 정하는 자리다(사양 10절)
3. 기본 이미지로 되돌리면 단색으로 돌아온다
4. 세로 사진을 골라도 흐리지 않다(사양 6절)

- [ ] **Step 3: PR**

`.github/pull_request_template.md`의 6개 절을 채운다. **💬 리뷰 포인트**에 적을 것: 그늘막 진하기(기기에서 정함) · 기본 배경 모습(디자인 확인 필요) · 컨트롤러를 가른 이유 · 상태바 스타일을 이 화면에서만 지정한 이유.
