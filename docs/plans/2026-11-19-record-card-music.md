# 기록카드 음악 상태 줄 · 재생 흉내 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** 카드 상세에 **음악 상태 한 줄**을 세우고, 그 줄이 포토북의 재생을
쥐게 한다. 설계 6-6이 미뤄 둔 **음악 알림 둘**(생성 중 수정·삭제, 입력 변경 시
전곡 재생성)도 함께 붙인다.

**Architecture:** 음악은 **카드 하나에 상태 하나**다(설계 3절 —
`music_generations.status`, 곡별 상태가 없다). 그래서 `RecordCard`에 필드를
더하지 않고 **따로 조회한다** — 서버에 음악 엔드포인트가 아예 없어
(설계 10절 4번) 어디에 실릴지 모르는 값을 카드 응답에 지어 넣지 않는다.
가짜가 타이머 대신 **요청 시각과 흐른 시간**으로 상태를 계산하고, provider가
**폴링**한다(완료 통지 방법이 미정이다 — 10절 10번).

**Tech Stack:** Flutter · Riverpod 3 수동 provider(`NotifierProvider.family`) ·
Lucide 아이콘 · 오디오 패키지 없음(소리 없이 길이만 쓴다).

**Spec:** `docs/specs/2026-11-16-record-card-design.md` — 3절(백엔드가 못 박은
것) · 6-5(음악 줄 5상태) · 6-6(알림 둘) · 8절(가짜 음악 흉내) · 9절(재생
패키지 안 넣는다).

앞선 묶음: `2026-11-16-record-card-calendar.md`(1) ·
`2026-11-18-record-card-compose.md`(2) ·
`2026-11-18-record-card-photo-publish.md`(3) ·
`2026-11-19-record-card-edit-delete.md`(4).

## Global Constraints

- 브랜치 `feat/record-card`에서 이어 간다. 커밋은 `<이모지> <type>: <한국어>`,
  **AI 공동 작성자 트레일러 금지**.
- 아이콘은 **Lucide만**. `AppIcons`(SVG 33개)에 음악·재생 글리프가 없다.
- 한국어 UI 문자열은 전부 `AppStrings`에, **정렬 위치에** 넣는다.
- `core/theme/tokens`·`theme/v2` 밖에서 색 하드코딩 금지. 다크·라이트 둘 다.
- 화면은 **loading / data / error 3분기**를 빠짐없이 처리한다.
- `domain/`은 **순수 Dart만** — `package:flutter`도 안 된다(`listEquals` 금지).
- `StateProvider`/`StateNotifierProvider` 금지. 수동 `NotifierProvider`는
  **기본이 `isAutoDispose: false`**다(`chat_provider.dart:143` 전례).
- 새 패키지 금지. **오디오는 넣지 않는다**(설계 9절) — 소리 없이 길이만 쓴다.
- `fvm` 대신 `C:\dev\runiverse\frontend\.fvm\flutter_sdk\bin\flutter.bat`을
  부른다. 이 워크트리에 `.fvm`이 없다(git-ignore).
- 테스트 함정 둘(묶음 4에서 두 번 걸렸다): **진행 표시 앞에서 `pumpAndSettle`은
  영영 안 끝난다**(명시적 `pump(Duration)`을 쓴다) · `Fake...(delay:)`는 **모든
  메서드**에 걸린다(하나만 느리게 하려면 그것만 감싸는 래퍼).

## Review Focus

설계가 넌지시 요구하지만 아래 작업들의 테스트가 **짚지 않는** 입력들.
각 줄의 테스트를 그 코드를 가진 작업에 넣어 두었다.

1. **상세를 열어 둔 채 음악이 끝나면** 줄이 스스로 바뀌어야 한다 — 폴링이
   멈추면 영원히 `만드는 중…`이다 (Task 4).
2. **상세를 닫았는데 폴링이 계속 돈다** — `autoDispose`를 안 켜면 카드를 열어 본
   만큼 타이머가 쌓인다 (Task 4).
3. **`다시 만들기`를 두 번 연타** — 재진입 가드가 없으면 요청이 둘 나가고
   서버가 활성 요청을 둘 들게 된다 (Task 4).
4. **사진이 없는 카드**(곡 1개) — 곡 수가 `사진 수 + 1`이라 0장이 1곡이다.
   `trackCount`를 `photos.length`로 적으면 사진 없는 카드가 0곡이 된다 (Task 1).
5. **수정에서 공개범위만 바꿨을 때** 재생성 경고가 뜨면 안 된다 — 뜨면 사용자가
   공개범위를 바꿀 때마다 음악을 잃는다고 믿는다 (Task 2·7).

---

### Task 1: 음악 상태와 곡 길이 — `music_generation.dart`

**Files:**
- Create: `lib/features/record_card/domain/music_generation.dart`
- Modify: `lib/features/record_card/presentation/card_media_pager.dart`
  (`baseDuration`·`photoDuration`을 걷고 도메인에서 읽는다)
- Modify: `test/record_card_detail_test.dart` (상수 출처 6곳)
- Test: `test/record_card_music_test.dart`

**Interfaces:**
- Consumes: 없다.
- Produces: `enum MusicStatus { none, queued, processing, succeeded, failed }` ·
  `class MusicGeneration({required int cardId, required MusicStatus status,
  required int trackCount})` · `MusicGeneration.baseDuration` ·
  `MusicGeneration.photoDuration` ·
  `static int MusicGeneration.trackCountFor(int photoCount)` ·
  `static Duration MusicGeneration.durationOfPage(int page)` ·
  `bool get isWorking` · `bool get isPlayable`.

**왜 곡을 목록으로 안 담나:** 설계의 파일 목록이 "`MusicStatus`(카드 단위) +
곡 목록"이라 적었지만, 3절이 **곡별 상태가 없다**고 못 박았고 재생 주소도
없다(9절 — 오디오 패키지를 안 넣는다). 지금 곡 하나가 가진 것은 **길이**뿐이고
길이는 자리(경로 장 30초 · 사진 장 10초)로 정해진다. 그래서 `trackCount`와
길이 상수 둘로 줄인다. **곡마다 주소나 상태가 생기는 날 목록으로 늘린다.**

- [ ] **Step 1: 실패하는 테스트**

```dart
test('곡 수는 사진 수 + 1이다 — 사진이 없어도 기본 음악 한 곡이 있다', () {
  expect(MusicGeneration.trackCountFor(0), 1);
  expect(MusicGeneration.trackCountFor(5), 6);
});

test('경로 장은 30초, 사진 장은 10초다', () {
  expect(MusicGeneration.durationOfPage(0), const Duration(seconds: 30));
  expect(MusicGeneration.durationOfPage(1), const Duration(seconds: 10));
  expect(MusicGeneration.durationOfPage(5), const Duration(seconds: 10));
});

test('만드는 중인 것은 QUEUED와 PROCESSING 둘이다', () {
  for (final status in MusicStatus.values) {
    expect(
      _generation(status).isWorking,
      status == MusicStatus.queued || status == MusicStatus.processing,
      reason: '$status',
    );
  }
});

test('틀 수 있는 것은 SUCCEEDED뿐이다', () {
  for (final status in MusicStatus.values) {
    expect(_generation(status).isPlayable, status == MusicStatus.succeeded);
  }
});
```

- [ ] **Step 2: 돌려서 떨어지는 것을 본다**

Run: `C:\dev\runiverse\frontend\.fvm\flutter_sdk\bin\flutter.bat test test/record_card_music_test.dart`
Expected: FAIL — `music_generation.dart`가 없다.

- [ ] **Step 3: `music_generation.dart`를 쓴다**

`MusicStatus`에 각 값이 **서버의 어느 값인지** 주석으로 적는다
(`none`은 서버 값이 아니라 **행이 없는 것**이다 — 생성을 한 번도 요청하지
않았다는 뜻이고, 줄이 `♪ AI 음악 만들기`로 선다).

- [ ] **Step 4: 통과를 본다**

Run: 같은 명령
Expected: PASS

- [ ] **Step 5: 길이 상수를 페이저에서 걷는다**

`CardMediaPager.baseDuration`·`photoDuration`을 지우고
`MusicGeneration.durationOfPage(_page)`를 쓴다. 상수의 출처가 둘이면 음악 계약이
바뀔 때 한쪽만 고쳐진다. `test/record_card_detail_test.dart`의 참조 6곳을
`MusicGeneration.*`로 바꾼다.

- [ ] **Step 6: 상세 테스트가 그대로 통과하는 것을 본다**

Run: `...flutter.bat test test/record_card_detail_test.dart test/record_card_music_test.dart`
Expected: PASS — 자동 넘김 동작은 **바뀌지 않았다.**

- [ ] **Step 7: 커밋**

```bash
git add lib/features/record_card/domain/music_generation.dart \
        lib/features/record_card/presentation/card_media_pager.dart \
        test/record_card_music_test.dart test/record_card_detail_test.dart
git commit -m "📍 Feat: 음악 상태와 곡 길이가 도메인으로 간다"
```

---

### Task 2: 전곡 재생성을 부르는 입력 — `music_inputs.dart`

**Files:**
- Create: `lib/features/record_card/domain/music_inputs.dart`
- Test: `test/record_card_music_inputs_test.dart`

**Interfaces:**
- Consumes: `CardDraft` · `RecordCard` · `EditRecordCard`.
- Produces: `class MusicInputs` + 세 factory
  (`MusicInputs.ofCard(RecordCard)` · `MusicInputs.ofDraft(CardDraft)` ·
  `MusicInputs.ofEdit(EditRecordCard)`) + `==`/`hashCode`.

**왜 값 객체 하나인가:** "바뀌면 전곡 재생성"의 기준이 **두 곳**에서 필요하다 —
화면이 경고를 띄울 때(초안 ↔ 카드)와 가짜가 생성을 되돌릴 때(수정 요청 ↔ 카드).
두 번 적으면 한쪽만 고쳐져 **경고는 뜨는데 음악은 그대로**거나 그 반대가 된다.

**세는 것(설계 3절):** 유형 · 회고 · 사진 · 캡션.
**안 세는 것:** 공개범위(AI 입력이 아니다) · 러닝 기록(수정에서 못 바꾼다).

사진은 **"무엇인가 + 한마디"**를 이은 문자열 목록으로 줄이고 **순서도 센다** —
순서를 바꾸면 사진 1번의 곡과 2번의 곡이 바뀌어야 하므로 재생성이 맞다.
이미 올린 것은 `s<id>|<캡션>`, 새로 고른 것은 `n<경로>|<캡션>`이다. 접두사가
갈라서 **번호 12와 경로 `12`가 섞이지 않는다.**

- [ ] **Step 1: 실패하는 테스트**

```dart
test('카드에서 뜬 초안은 입력이 같다 — 아무것도 안 건드렸다', () {
  final card = _card(photos: 2);
  expect(MusicInputs.ofDraft(CardDraft.fromCard(card)), MusicInputs.ofCard(card));
});

test('⚠️ 공개범위만 바꾸면 입력이 같다 — AI가 읽는 값이 아니다', () {
  final card = _card();
  final draft = CardDraft.fromCard(card)
      .copyWith(visibility: RecordCardVisibility.public);
  expect(MusicInputs.ofDraft(draft), MusicInputs.ofCard(card));
});

test('회고를 고치면 입력이 달라진다', () { ... reviewText: '다른 글' ... isNot ... });
test('유형을 바꾸면 입력이 달라진다', () { ... });
test('캡션만 고쳐도 입력이 달라진다 — 사진 음악이 캡션을 읽는다', () { ... });
test('사진을 한 장 빼면 입력이 달라진다', () { ... });
test('⚠️ 순서만 바꿔도 입력이 달라진다 — 장마다 곡이 따로다', () { ... });
test('수정 요청과 카드를 맞대 볼 수 있다', () {
  final card = _card(photos: 1);
  final same = EditRecordCard(
    cardId: card.id,
    activity: card.activity,
    visibility: RecordCardVisibility.public, // 공개범위는 안 센다
    reviewText: card.reviewText,
    photos: [
      EditCardPhoto.saved(savedId: card.photos.first.id,
          caption: card.photos.first.caption),
    ],
  );
  expect(MusicInputs.ofEdit(same), MusicInputs.ofCard(card));
});
```

- [ ] **Step 2: 떨어지는 것을 본다** — Run: `...flutter.bat test test/record_card_music_inputs_test.dart` / Expected: FAIL
- [ ] **Step 3: `music_inputs.dart`를 쓴다**

`==`는 손으로 적는다 — `domain/`은 순수 Dart라 `listEquals`를 못 쓴다
(`package:flutter/foundation.dart`가 필요하다). 목록은 길이부터 보고 한 칸씩
비교하는 `static bool _sameOrder(List<String>, List<String>)`로 가른다.
캡션이 `null`인 사진과 빈 문자열은 **같은 것으로** 센다(초안은 `''`, 카드는
`null`이다 — 안 맞추면 캡션을 안 쓴 카드가 열자마자 "바뀌었다"가 된다).

- [ ] **Step 4: 통과를 본다** — Expected: PASS
- [ ] **Step 5: 커밋**

```bash
git commit -m "📍 Feat: 전곡을 다시 만들게 하는 입력이 무엇인지 정한다"
```

---

### Task 3: 저장소에 음악을 묻는다 + 가짜가 흉내낸다

**Files:**
- Modify: `lib/features/record_card/domain/record_card_repository.dart`
- Modify: `lib/features/record_card/data/fake_record_card_repository.dart`
- Test: `test/record_card_fake_repository_test.dart` (음악 묶음을 더한다)

**Interfaces:**
- Consumes: Task 1의 `MusicGeneration`·`MusicStatus`, Task 2의 `MusicInputs`.
- Produces: `Future<MusicGeneration> musicOf(int cardId)` ·
  `Future<MusicGeneration> requestMusic(int cardId)` ·
  `FakeRecordCardRepository({DateTime Function() clock = DateTime.now})` ·
  `musicRequests` 카운터.

**가짜의 규칙(설계 8절):**

| 무엇 | 어떻게 |
|---|---|
| 요청하면 | `QUEUED` → **3초 뒤** `PROCESSING` → **13초 뒤**(요청 기준) `SUCCEEDED` |
| 스무 번에 한 번 | 그 요청은 끝에서 `FAILED`로 떨군다 — **`QUEUED`→`PROCESSING`을 거친 뒤**다. 요청 즉시 실패하면 진짜와 다르다 |
| 목 카드 20장 | 번호 `1000`=`PROCESSING` · `1001`=`FAILED` · `1002`=`none` · 나머지 `SUCCEEDED`. **다섯 상태를 기다리지 않고 다 본다**(`QUEUED`는 눌러서 본다) |
| 앱이 만든 카드 | `musicEnabled`가 참이면 **만든 시각으로 요청이 걸린다**. 거짓이면 `none` |
| 고치면 | [MusicInputs]가 달라졌고 음악이 `none`이 아니면 **요청 시각을 지금으로 되돌린다** — 활성 요청 무효화 + 전곡 재생성(3절) |
| 지우면 | 음악 기록도 함께 지운다 |
| 없는 카드 | `RecordCardFailure.notFound`로 던진다 |

**시각을 주입하는 이유:** 타이머로 흉내내면 테스트가 **13초를 실제로 기다린다.**
요청 시각만 적어 두고 `clock()`과의 차로 상태를 **계산**하면, 테스트가 시계를
밀어 세 상태를 즉시 확인한다. 기기에서는 기본값 `DateTime.now`로 진짜 시간이
흐른다.

**20분의 1을 난수로 하지 않는 이유:** 재현되지 않는 가짜 실패는 눈검증을
망친다. `musicRequests` 카운터의 20번째를 떨군다 — 눈으로도 보이고 테스트에서도
짚을 수 있다. 강제 실패는 `failWith`가 이미 한다.

- [ ] **Step 1: 실패하는 테스트**

```dart
test('⚠️ 사진 없는 카드도 한 곡이다', () async {
  // 목 번호 1001은 사진 0장이고 FAILED다 → 사진 0장 + SUCCEEDED 카드를 고른다.
  final music = await repo.musicOf(1003);
  expect(music.trackCount, 1);
});

test('요청하면 준비 중이고, 3초 뒤 만드는 중, 13초 뒤 끝난다', () async {
  var now = DateTime(2026, 11, 19, 10);
  final repo = FakeRecordCardRepository(today: now, clock: () => now);

  expect((await repo.requestMusic(1002)).status, MusicStatus.queued);

  now = now.add(const Duration(seconds: 3));
  expect((await repo.musicOf(1002)).status, MusicStatus.processing);

  now = now.add(const Duration(seconds: 10));
  expect((await repo.musicOf(1002)).status, MusicStatus.succeeded);
});

test('⚠️ 스무 번째 요청은 거치고 나서 실패한다 — 즉시가 아니다', () async {
  // 1~19번은 성공, 20번째가 실패다.
  for (var i = 0; i < 19; i++) { await repo.requestMusic(1002); }
  expect((await repo.requestMusic(1002)).status, MusicStatus.queued);
  now = now.add(const Duration(seconds: 3));
  expect((await repo.musicOf(1002)).status, MusicStatus.processing);
  now = now.add(const Duration(seconds: 10));
  expect((await repo.musicOf(1002)).status, MusicStatus.failed);
});

test('목 카드가 네 상태를 한 번씩 보여 준다', () async {
  expect((await repo.musicOf(1000)).status, MusicStatus.processing);
  expect((await repo.musicOf(1001)).status, MusicStatus.failed);
  expect((await repo.musicOf(1002)).status, MusicStatus.none);
  expect((await repo.musicOf(1003)).status, MusicStatus.succeeded);
});

test('음악을 켜고 만든 카드는 준비 중으로 선다', () async { ... musicEnabled: true ... queued });
test('음악을 끄고 만든 카드는 만들지 않는다', () async { ... musicEnabled: false ... none });

test('⚠️ 회고를 고치면 다 된 음악이 처음으로 돌아간다', () async {
  // 1003은 SUCCEEDED다.
  await repo.update(EditRecordCard(cardId: 1003, ..., reviewText: '다른 글', ...));
  expect((await repo.musicOf(1003)).status, MusicStatus.queued);
});

test('⚠️ 공개범위만 바꾸면 음악은 그대로다', () async {
  await repo.update(/* 다른 값은 1003 그대로, visibility만 public */);
  expect((await repo.musicOf(1003)).status, MusicStatus.succeeded);
});

test('지운 카드의 음악은 없는 카드로 답한다', () async {
  await repo.delete(1003);
  expect(() => repo.musicOf(1003), throwsA(isA<RecordCardException>()));
});
```

- [ ] **Step 2: 떨어지는 것을 본다** — Run: `...flutter.bat test test/record_card_fake_repository_test.dart` / Expected: FAIL (`musicOf`가 없다)
- [ ] **Step 3: 인터페이스에 두 메서드를 더한다**

`musicOf`에 **지금은 붙일 엔드포인트가 없다**는 것과 10절 4번·10번을 적는다.
`requestMusic`에 **전곡이라는 것**(곡별 재요청이 없다)을 적는다.

- [ ] **Step 4: 가짜를 고친다**

`_musicRequestedAt` · `_musicWillFail` · `musicRequests` · `clock`을 더하고,
`create`·`update`·`delete`가 음악 기록을 함께 건드리게 한다.

- [ ] **Step 5: 통과를 본다** — Expected: PASS
- [ ] **Step 6: 커밋**

```bash
git commit -m "📍 Feat: 가짜가 음악 상태를 흉내낸다 — 시간만 흐르게 한다"
```

---

### Task 4: 음악 상태를 들고 있는다 — `card_music_provider.dart`

**Files:**
- Create: `lib/features/record_card/presentation/card_music_provider.dart`
- Test: `test/record_card_music_provider_test.dart`

**Interfaces:**
- Consumes: `recordCardRepositoryProvider`(`record_card_provider.dart`) ·
  Task 3의 두 메서드.
- Produces: `cardMusicProvider`
  (`NotifierProvider.family<CardMusicController, CardMusicState, int>`,
  **`isAutoDispose: true`**) · sealed `CardMusicState`
  = `CardMusicLoading` | `CardMusicError(RecordCardFailure)` |
  `CardMusicData({required MusicGeneration generation, bool requesting})` ·
  `Future<void> load()` · `Future<void> request()` ·
  `static const pollInterval = Duration(seconds: 3)`.

**폴링인 이유:** 완료를 앱에 알리는 방법이 **아직 안 정해졌다**(설계 10절 10번 —
FCM / 조회 / 폴링). 셋 중 앱만으로 되는 것은 폴링이다. **만드는 중일 때만**
돌고(`isWorking`) 끝나면 멈춘다 — 서버가 큐에서 6시간을 기다릴 수 있어
(3절) 통지 방식이 정해지면 **이 provider 한 곳만** 바꾼다.

**`autoDispose`인 이유:** 상세는 열고 닫는 화면이고 카드마다 family 인자가
다르다. 안 켜면 카드를 열어 본 만큼 상태와 **타이머가 쌓인다**. 수동 provider는
기본이 `false`다 — 명시해야 켜진다.

- [ ] **Step 1: 실패하는 테스트**

```dart
test('열면 받아 온다', () async { ... CardMusicLoading → CardMusicData ... });

test('⚠️ 만드는 중이면 스스로 다시 묻는다 — 상세를 열어 둔 사람이 끝을 본다',
    () => fakeAsync((async) { /* clock을 밀고 pollInterval만큼 흘린다 */ }));

test('⚠️ 다 되면 더 묻지 않는다', ...);          // calls가 늘지 않는다

test('⚠️ 닫으면 폴링이 멈춘다', ...);            // container.dispose() 뒤 calls 고정

test('⚠️ 두 번 연타해도 요청은 한 번이다', () async {
  final one = controller.request();
  final two = controller.request();
  await Future.wait([one, two]);
  expect(repo.musicRequests, 1);
});

test('실패하면 오류로 세우고 폴링하지 않는다', ...);   // failWith = network
test('다시 만들기가 실패 상태에서 준비 중으로 되돌린다', ...);
```

**폴링 테스트는 `testWidgets` + `tester.pump(간격)`으로 쓴다.** `pubspec`에
`fake_async`가 없고(전이 의존을 직접 import하면
`depend_on_referenced_packages`가 뜬다 — 묶음 3에서 `characters`로 걸렸다),
`flutter_test`의 테스트 바인딩이 `Timer`를 이미 가짜 시계에 매달아 둔다.
위젯을 안 세우고 `ProviderContainer`만 만들어도 `tester.pump(d)`가 그 타이머를
민다. `addTearDown(container.dispose)`로 닫는다.

- [ ] **Step 2: 떨어지는 것을 본다** — Expected: FAIL
- [ ] **Step 3: provider를 쓴다**

`await` 뒤에 상태를 쓰기 전에 **살아 있는지 본다** — `autoDispose`라 실제로
죽는다(`chat_provider.dart`의 `_alive` 전례). `ref.onDispose`로 타이머를 끈다.

- [ ] **Step 4: 통과를 본다** — Expected: PASS
- [ ] **Step 5: 커밋**

```bash
git commit -m "📍 Feat: 음악 상태를 묻고, 만드는 중에만 다시 묻는다"
```

---

### Task 5: 음악 상태 한 줄 — `music_strip.dart`

**Files:**
- Create: `lib/features/record_card/presentation/music_strip.dart`
- Modify: `lib/core/strings/app_strings.dart` (상세 묶음 **정렬 위치에**)
- Test: `test/record_card_music_strip_test.dart`

**Interfaces:**
- Consumes: Task 4의 `cardMusicProvider`, Task 1의 `MusicStatus`.
- Produces: `class MusicStrip extends ConsumerWidget`
  (`{required int cardId, required bool playing, required VoidCallback onTogglePlay}`).

**설계 6-5의 다섯 상태 + 3분기:**

| 상태 | 줄 | 누르면 |
|---|---|---|
| loading | `♪` 아이콘만 흐리게 (**높이를 지킨다**) | — |
| error | `♪ 음악 상태를 보지 못했어요` + `다시` | `load()` |
| `none` | `♪ AI 음악 만들기` — **줄 전체가 버튼** | `request()` |
| `queued` | `♪ 음악 생성 준비 중…` | — |
| `processing` | `♪ 음악 만드는 중…` | — |
| `succeeded` | 멈춰 있으면 `▶ 재생`, 도는 중이면 `⏸ 멈춤` | `onTogglePlay` |
| `failed` | `♪ 음악을 만들지 못했어요` + `다시 만들기` | `request()` |

**⚠️ `▶ 재생`을 늘 `재생`으로 두지 않는다.** 포토북은 상세를 열면 **이미
돌고 있다**(묶음 1에서 그렇게 정하고 기기에서 확인했다). 그 위에 `▶ 재생`을
세우면 **이미 하고 있는 것을 하라는 버튼**이 되고, 눌러서 멈추면 라벨이
거짓이 된다. 설계 6-5의 표는 "음악이 준비됐다"는 상태를 적은 것이고, 그
자리에 선 컨트롤은 **지금 상태의 반대**를 가리켜야 한다.

**⚠️ 진행바를 두지 않는다.** 설계 8절이 "▶를 누르면 진행바가 찬다"고 적었지만,
**2026-11-17에 사용자가 기기에서 보고 차는 막대를 작은 흰 점으로 바꿨다**
(6-5의 변경 기록). 11절도 "남은 시간을 못 알리는 것은 그대로"라고 적어 두었다.
여기서 막대를 되살리면 **사용자가 내린 결정을 조용히 뒤집는다.** 점이 몇 번째
장인지 말하고, 줄은 음악 상태를 말한다. **막대를 다시 원하면 되돌릴 자리다.**

- [ ] **Step 1: 실패하는 테스트**

```dart
testWidgets('만들지 않은 카드는 만들라고 권한다', ...);     // recordCardMusicCreate
testWidgets('누르면 요청이 나간다', ...);                   // repo.musicRequests == 1
testWidgets('준비 중·만드는 중은 말만 한다 — 누를 것이 없다', ...);
testWidgets('⚠️ 도는 중이면 멈춤이고, 멈춰 있으면 재생이다', ...);
testWidgets('재생을 누르면 바깥이 듣는다', ...);            // onTogglePlay 호출
testWidgets('실패하면 다시 만들기가 선다', ...);
testWidgets('다시 만들기를 누르면 요청이 나간다', ...);
testWidgets('못 읽었으면 오류를 말하고 다시 묻게 한다', ...);
testWidgets('⚠️ 받는 동안에도 줄 높이가 같다 — 아래가 튀지 않는다', ...);
testWidgets('라이트 테마에서도 그려진다', ...);
testWidgets('스크린리더가 무슨 버튼인지 읽는다', ...);
```

- [ ] **Step 2: 떨어지는 것을 본다** — Expected: FAIL
- [ ] **Step 3: 문자열을 `AppStrings`에 넣는다**

`recordCardMusic*` 묶음을 **상세 문구 옆**(`recordCardReview` 뒤)에 둔다 —
`recordCardMore`·`recordCardDelete*`가 작성 묶음 사이에 끼어 있는 것은 묶음 4의
미뤄 둔 것 7번이다. **같은 실수를 반복하지 않는다.**

- [ ] **Step 4: 위젯을 쓴다** — Expected: PASS (Step 5에서 확인)
- [ ] **Step 5: 통과를 본다**

Run: `...flutter.bat test test/record_card_music_strip_test.dart`
Expected: PASS

- [ ] **Step 6: 커밋**

```bash
git commit -m "📍 Feat: 음악 상태가 한 줄로 선다"
```

---

### Task 6: 상세가 줄을 세우고, 줄이 재생을 쥔다

**Files:**
- Modify: `lib/features/record_card/presentation/card_detail_page.dart`
  (`ConsumerWidget` → `ConsumerStatefulWidget`, `playing`을 든다)
- Modify: `lib/features/record_card/presentation/card_media_pager.dart`
  (`_playing`을 바깥에서 받는다)
- Test: `test/record_card_detail_test.dart`

**Interfaces:**
- Consumes: Task 5의 `MusicStrip`.
- Produces: `CardMediaPager({required RecordCard card, required bool playing,
  required ValueChanged<bool> onPlayingChanged})`.

**왜 `playing`을 올리나:** 줄과 페이저가 **같은 하나**를 가리켜야 한다. 각자
들면 줄은 `▶ 재생`인데 책은 넘어가거나, 책을 탭해서 멈췄는데 줄은 여전히
`⏸ 멈춤`이다. provider로 올리지 않는 이유는 **화면 하나를 넘지 않는 상태**라서다 —
카드를 닫으면 사라져야 하고, family provider를 두면 그 수명을 또 관리해야 한다.

**⚠️ 음악 상태가 자동 넘김을 막지 않는다.** `SUCCEEDED`가 아닐 때 책을
세워 두면, 음악을 끈 카드(`none`)와 실패한 카드의 포토북이 **영영 첫 장에서
멈춘다.** 음악이 붙으면 바뀌는 것은 설계가 적은 대로 **길이의 출처뿐**이다
(6-5) — 넘어가는 일 자체는 묶음 1에서 이미 서 있다.

- [ ] **Step 1: 실패하는 테스트**

```dart
testWidgets('상세에 음악 줄이 선다', ...);
testWidgets('⚠️ 줄의 멈춤을 누르면 책이 안 넘어간다', (tester) async {
  // SUCCEEDED 카드를 열고 ⏸을 누른 뒤 baseDuration을 흘린다 → 첫 장 그대로
});
testWidgets('⚠️ 다시 누르면 이어간다', ...);
testWidgets('⚠️ 사진을 탭해 멈추면 줄도 재생으로 바뀐다 — 둘이 한 상태다', ...);
testWidgets('음악이 없는 카드도 책은 넘어간다', ...);   // none인 1002
```

- [ ] **Step 2: 떨어지는 것을 본다** — Expected: FAIL
- [ ] **Step 3: 페이저가 `playing`을 받게 한다**

`_playing` 필드를 걷고 `widget.playing`을 본다. 탭은 `onPlayingChanged(!playing)`
를 부른다. `didUpdateWidget`에서 `playing`이 바뀌면 타이머를 다시 건다 —
**안 걸면 줄로 멈춘 것이 반영되지 않는다.**

- [ ] **Step 4: 상세가 둘을 잇는다**

`ConsumerStatefulWidget`으로 바꾸고 `_playing`을 든다. `ListView`의 순서는
머리 → 페이저(점·글 포함) → **음악 줄**이다(시안 6-5).

- [ ] **Step 5: 통과를 본다**

Run: `...flutter.bat test test/record_card_detail_test.dart`
Expected: PASS — 묶음 1의 자동 넘김·탭 멈춤 테스트가 **그대로** 통과한다.

- [ ] **Step 6: 커밋**

```bash
git commit -m "📍 Feat: 음악 줄이 포토북의 재생을 쥔다"
```

---

### Task 7: 설계 6-6이 미뤄 둔 알림 둘

**Files:**
- Modify: `lib/features/record_card/presentation/card_publish_page.dart`
- Modify: `lib/features/record_card/presentation/card_detail_page.dart`
  (삭제 확인 시트)
- Modify: `lib/core/strings/app_strings.dart`
- Test: `test/record_card_publish_page_test.dart` ·
  `test/record_card_delete_test.dart`

**Interfaces:**
- Consumes: Task 2의 `MusicInputs`, Task 4의 `cardMusicProvider`.
- Produces: 없다(화면 안에서 끝난다).

**어떤 줄이 언제 뜨나.** 수정 화면(`draft.editing != null`)에서만이고,
**`none`과 `failed`에서는 아무 줄도 없다** — 잃을 음악이 없다.

| 음악 | 입력이 바뀜 | 줄 |
|---|---|---|
| `queued`·`processing` | 상관없다 | `음악을 만드는 중이에요. 저장하면 만들던 것은 버려지고 처음부터 다시 만듭니다` |
| `succeeded` | 바뀜 | `저장하면 음악을 처음부터 다시 만듭니다` |
| `succeeded` | 공개범위만 | **없다** |

**⚠️ 생성 중에는 "공개범위만 바꾸면 그대로"가 거짓이다.** 설계 6-6은 "공개범위만
바꾸면 음악은 그대로"라고 적었지만, 3절의 백엔드 사실은 **"생성 중 수정·삭제는
활성 요청을 무효화한다"**다. 완성된 음악에 대한 말과 **만드는 중**인 요청에
대한 말이 다르다 — 만드는 중이면 무엇을 바꾸든 버려진다. 3절을 따른다.

삭제 확인 시트에는 만드는 중일 때만 `음악을 만드는 중이에요. 카드와 함께
사라집니다`를 **되돌릴 수 없다는 말 아래**에 한 줄 더한다. **막지 않는다**(6-6).

**⚠️ 시트에서 provider를 읽지 않는다.** `showModalBottomSheet`의 builder는
`Navigator` 밑에 따로 서서, 거기서 `ref.watch`를 하면 시트가 떠 있는 동안
상태가 바뀔 때 다시 그려지지 않는다. **열기 전에 값을 읽어 넘긴다.**

- [ ] **Step 1: 실패하는 테스트**

```dart
// publish
testWidgets('⚠️ 새 카드에는 아무 음악 경고도 없다', ...);
testWidgets('만드는 중인 카드를 고치면 버려진다고 알린다', ...);
testWidgets('다 된 음악인데 회고를 고치면 다시 만든다고 알린다', ...);
testWidgets('⚠️ 다 된 음악인데 공개범위만 바꾸면 아무 말도 하지 않는다', ...);
testWidgets('음악이 없는 카드를 고치면 아무 말도 하지 않는다', ...);
testWidgets('실패한 음악을 고치면 아무 말도 하지 않는다 — 잃을 것이 없다', ...);

// delete
testWidgets('만드는 중이면 함께 사라진다고 알린다', ...);
testWidgets('⚠️ 알리기만 하고 막지 않는다', ...);   // 지우기 버튼이 그대로 눌린다
testWidgets('다 된 음악은 삭제 시트에서 말하지 않는다', ...);
```

- [ ] **Step 2: 떨어지는 것을 본다** — Expected: FAIL
- [ ] **Step 3: 문자열 셋을 넣는다** (`recordCardMusic*`, 정렬 위치에)
- [ ] **Step 4: 두 화면에 줄을 붙인다**

작성 3의 경고는 `_RouteWarning`과 같은 꼴(`LucideIcons.triangleAlert` +
`colors.warning`)로 둔다 — 같은 성격의 말이 두 모양이면 하나가 덜 중요해 보인다.

- [ ] **Step 5: 통과를 본다**

Run: `...flutter.bat test test/record_card_publish_page_test.dart test/record_card_delete_test.dart`
Expected: PASS

- [ ] **Step 6: 전체를 돌린다**

Run: `...flutter.bat test` · `...flutter.bat analyze`
Expected: 전부 통과 · 경고 0

- [ ] **Step 7: 커밋**

```bash
git commit -m "📍 Feat: 음악을 잃는 수정과 삭제를 미리 알린다"
```

---

## 자기 검토

**설계 범위:** 6-5의 음악 줄 5상태(Task 5) · 곡 길이와 자동 넘김(Task 1·6) ·
8절의 가짜 흉내(Task 3) · 6-6의 알림 둘(Task 7) · 9절의 "오디오 패키지 안
넣는다"(지킨다 — 소리가 없다).

**설계에서 **일부러 뺀** 것:**

1. **`🔒 나만 보기` 칩을 눌러 공개범위만 바꾸는 시트**(6-5) — 상세에 **칩 자체가
   없다.** 묶음 1이 유형·공개범위 칩을 두지 않기로 하고 테스트로 못 박았다
   ("유형은 두지 않는다 — 달력의 필터가 이미 말했다"). 칩을 되살리는 것은 음악이
   아니라 **상세 레이아웃의 결정**이라 묶음 5의 범위가 아니다. 미뤄 둔 것에 적는다.
2. **수정 화면의 음악 토글** — 되살리지 않는다. 상태가 `none`인 카드에 음악을
   켜는 길은 **상세의 `♪ AI 음악 만들기`**로 이미 있다. 수정에도 두면 같은 일을
   하는 컨트롤이 둘이고, `EditRecordCard`에 음악을 다시 실어야 하는데 "안 바꿈"을
   표현할 값이 없다(묶음 4가 그래서 걷었다).
3. **진행바** — Task 5의 ⚠️에 적은 이유로 두지 않는다.
4. **멈춤 표시를 따로 둘지**(11절 미정) — 줄의 `▶ 재생`/`⏸ 멈춤`이 그 일을
   한다. 사진 위에 겹치는 표시는 두지 않는다.

**타입 일관성:** `MusicGeneration`(Task 1) → 저장소 반환형(Task 3) →
`CardMusicData.generation`(Task 4) → `MusicStrip`이 읽는 값(Task 5).
`MusicInputs`(Task 2) → 가짜의 재생성 판정(Task 3) + 작성 3의 경고(Task 7).
`playing`은 상세가 들고(Task 6) 줄과 페이저가 받는다.

**분량:** 새 파일 4개(도메인 2 · provider 1 · 위젯 1) + 고치는 파일 5개 +
테스트 5개. **20파일·500줄을 넘는다** — 묶음 1~4와 같은 PR 사유를 적는다.
