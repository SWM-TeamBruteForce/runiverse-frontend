# 기록카드 음악 재생 구현 계획 (묶음 9)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 기록카드 상세에서 **보고 있는 장의 곡이 실제로 들리고, 끝나면 반복**한다. 포토북의 자동 넘김은 없앤다.

**Architecture:** 소리를 내는 것은 `CardAudioPlayer`(domain 인터페이스) 뒤에 가리고 `JustAudioPlayer`(data)가 구현한다. `cardAudioProvider`(family, autoDispose)가 플레이어와 "지금 나고 있나"를 쥐고, **상세 화면만** 그것을 몬다 — 페이저와 음악 줄은 오디오를 모른다. 같은 곡인지는 주소가 아니라 `장|상태|주소의 ? 앞`으로 가른다.

**Tech Stack:** Flutter 3.44.8 / Dart 3.12.2 · `just_audio` 0.10.6 (+ `audio_session` 0.2.4 · `just_audio_platform_interface` · `just_audio_web` · `rxdart`) · Riverpod 3 수동 provider

**Spec:** `docs/specs/2026-11-25-record-card-audio-design.md`

## Global Constraints

- 아이콘은 **Lucide만**. `Icons.*` 금지. 색·치수·타이포·문자열은 전부 토큰.
- `StateProvider` / `StateNotifierProvider` 금지. **Riverpod 3 수동 provider**, family는 `isAutoDispose: true`.
- `domain/`은 **순수 Dart만** — `just_audio`·`audio_session`을 import하지 않는다.
- 의존 방향 `presentation → domain ← data`. presentation은 data를 import하지 않는다.
- UI 텍스트는 한국어.
- **한 PR 파일 20개 / 500줄 초과 금지** → Task 1 / Task 2~3 / Task 4~5 세 PR로 나눈다.
- **서명된 조회 주소를 로그에 남기지 않는다.** 오류를 적을 때도 주소를 흘리지 않는다.
- 모든 flutter/dart 명령: `C:\dev\runiverse\frontend\.fvm\flutter_sdk\bin\flutter.bat` (이 워크트리에 `.fvm`이 없다).
- 커밋 메시지는 이모지 접두 (`📍 Feat` `🔨 Fix` `✂️ Remove` `✅ Test` `📝 Docs`), **AI 공동 작성자 트레일러 금지.**

## Review Focus

테스트가 짚지 않는데 사람을 가장 먼저 물 자리 다섯. 각 줄의 테스트는 괄호 안 Task가 갖는다.

1. **폴링이 돌아도 곡이 안 끊긴다.** 만드는 중인 카드는 상세를 1분마다 다시 읽고 **서명 주소가 그때마다 달라진다.** 같은 곡이면 다시 물지 않아야 한다. (Task 4)
2. **그 장에 서 있는 동안 곡이 완성되면 바로 난다.** `GENERATING → COMPLETED`로 바뀌면 장을 다시 밀지 않아도 들려야 한다. (Task 4)
3. **다른 앱이 소리를 내고 있으면 자동 재생을 접는다.** 듣던 음악이 카드를 연다고 멈추면 안 된다. 버튼은 선다. (Task 4)
4. **로드가 두 번 실패해도 고리가 안 생긴다.** 한 장에서 상세를 **한 번만** 다시 읽고, 두 번째는 조용히 접는다. (Task 5)
5. **곡이 없는 장(만드는 중·실패)에서도 카드를 쓸 수 있다.** 소리는 없고 손으로 넘기는 것은 된다. (Task 1)

---

## 파일 구조

| 파일 | 책임 |
|---|---|
| `lib/features/record_card/domain/card_music.dart` (수정) | `CardMusicTiming` 삭제. `trackIdOf` 추가 — 곡의 신원 |
| `lib/features/record_card/domain/card_audio_player.dart` (신규) | `CardAudioPlayer` 인터페이스. **순수 Dart** |
| `lib/features/record_card/data/just_audio_player.dart` (신규) | `just_audio`로 구현. 반복 모드, 남의 소리 확인 |
| `lib/features/record_card/presentation/card_audio_provider.dart` (신규) | 플레이어를 쥐고 상태를 낸다 |
| `lib/features/record_card/presentation/card_detail_page.dart` (수정) | **플레이어를 모는 유일한 곳.** 생명주기도 여기 |
| `lib/features/record_card/presentation/card_media_pager.dart` (수정) | `Timer` 제거. `playing` 대신 `onTap` |
| `lib/features/record_card/presentation/music_strip.dart` (수정) | `canAdvance` 제거 |
| `lib/core/strings/app_strings.dart` (수정) | `recordCardMusicReady` 삭제 |

---

### Task 1: 자동 넘김을 걷어낸다

소리를 붙이기 전에 **뒤집은 결정을 먼저 반영한다**(설계 2절). 이 Task만으로 앱은 그대로 돈다 — 포토북이 저절로 안 넘어갈 뿐이다.

**Files:**
- Modify: `lib/features/record_card/domain/card_music.dart` (`CardMusicTiming` 삭제, `url` 주석)
- Modify: `lib/features/record_card/presentation/card_media_pager.dart` (`Timer`·`_schedule`·`_advance`·`playing`·`onPlayingChanged` 삭제, `onTap` 추가)
- Modify: `lib/features/record_card/presentation/music_strip.dart` (`canAdvance` 삭제)
- Modify: `lib/features/record_card/presentation/card_detail_page.dart:167,238` (`_canAdvance` 삭제, `onTap` 배선)
- Modify: `lib/core/strings/app_strings.dart` (`recordCardMusicReady` 삭제)
- Test: `test/record_card_media_pager_test.dart` · `test/record_card_music_strip_test.dart` · `test/record_card_music_test.dart` · `test/record_card_detail_test.dart` · `test/record_card_edit_flow_test.dart`

**Interfaces:**
- Produces: `CardMediaPager({required RecordCard card, required VoidCallback onTap, required ValueChanged<int> onPageChanged})` — `playing`·`onPlayingChanged`가 **없다**
- Produces: `MusicStrip({required String cardId, required CardMusic? music, required bool hasFailed, required bool playing, required bool canRequest, required VoidCallback onTogglePlay})` — `canAdvance`가 **없다**

- [ ] **Step 1: 새 테스트를 쓴다** — `test/record_card_media_pager_test.dart`에 추가

```dart
testWidgets('⚠️ 가만히 두어도 장이 넘어가지 않는다', (tester) async {
  // 곡이 끝나면 반복한다 — 넘길 신호가 없다(설계 2절).
  await pump(tester, card(photos: 2));
  expect(find.text('사진 0'), findsOneWidget);

  await tester.pump(const Duration(minutes: 2));
  await tester.pumpAndSettle();

  // 첫 장(경로)에 그대로 서 있다.
  expect(find.text('사진 0'), findsOneWidget);

  // ⚠️ Review Focus 5 — 곡이 없어도 손으로는 넘어간다.
  await tester.drag(find.byType(PageView), const Offset(-600, 0));
  await tester.pumpAndSettle();
  expect(find.text('사진 1'), findsOneWidget);
});
```

- [ ] **Step 2: 마지막 장 테스트를 쓴다** — `test/record_card_music_strip_test.dart`에 추가

```dart
testWidgets('⚠️ 마지막 장에도 버튼이 선다', (tester) async {
  // 넘어갈 장이 없어도 틀 것은 있다 — canAdvance 가 없어졌다.
  await pump(tester, music: const CardMusic(
    status: MusicStatus.completed,
    url: 'https://example.invalid/a.m4a',
  ));
  expect(find.text(AppStrings.recordCardMusicPlay), findsOneWidget);
});
```

- [ ] **Step 3: 둘을 돌려 실패를 본다**

Run: `flutter.bat test test/record_card_media_pager_test.dart test/record_card_music_strip_test.dart`
Expected: FAIL — 첫째는 장이 넘어가 `사진 0`을 못 찾고, 둘째는 `canAdvance` 인자가 없어 컴파일되지 않는다

- [ ] **Step 4: `CardMusicTiming`을 지운다** (`card_music.dart`)

`CardMusic.url`의 "⚠️ 아직 쓰지 않는다" 주석도 **쓴다**로 고친다. 지우는 이유를 주석으로 남기지 않는다 — 없어진 것을 설명하는 주석은 다음 사람을 헷갈리게 한다.

- [ ] **Step 5: 페이저에서 타이머를 걷는다** (`card_media_pager.dart`)

`Timer`·`_advance`·`_schedule`·`didUpdateWidget`의 `_schedule` 호출·`playing`·`onPlayingChanged`를 지우고 `final VoidCallback onTap`을 받는다. `_clampPage()`는 **남긴다**(2026-11-24 RangeError 수정). 클래스 doc의 "음악이 끝나면 다음 장이다" 절을 **"장은 손으로만 넘어간다"**로 고쳐 쓴다.

- [ ] **Step 6: `canAdvance`를 걷는다** (`music_strip.dart`, `card_detail_page.dart`)

`MusicStatus.completed` 갈래는 **늘** `_Line(icon: playing ? pause : play, …, onTap: onTogglePlay)`다. `card_detail_page.dart`의 `_canAdvance` getter를 지우고, 페이저에 `onTap: () => setState(() => _playing = !_playing)`을 넘긴다.

- [ ] **Step 7: `recordCardMusicReady`를 지운다** (`app_strings.dart:1716~1721`)

문서 주석 세 줄까지 함께 지운다.

- [ ] **Step 8: 기존 테스트를 고친다**

- `record_card_music_test.dart:119~121` — `CardMusicTiming` 값을 재는 세 줄을 **지운다**
- `record_card_detail_test.dart` — `CardMusicTiming`으로 `pump`하는 14군데. 자동 넘김을 재던 것은 **지우고**, 장을 바꿔야 하는 것은 `tester.drag(find.byType(PageView), const Offset(-600, 0))`로 바꾼다
- `record_card_music_strip_test.dart` · `record_card_edit_flow_test.dart` — `canAdvance` 인자와 `recordCardMusicReady` 기대를 걷는다

- [ ] **Step 9: 전체 테스트를 돌린다**

Run: `flutter.bat test`
Expected: PASS, 실패 0

- [ ] **Step 10: analyze**

Run: `flutter.bat analyze`
Expected: `No issues found!`

- [ ] **Step 11: 커밋**

```bash
git add -A lib test docs
git commit -m "✂️ Remove: 포토북 자동 넘김을 걷어낸다"
```

---

### Task 2: 곡의 신원과 플레이어 인터페이스

**Files:**
- Modify: `lib/features/record_card/domain/card_music.dart`
- Create: `lib/features/record_card/domain/card_audio_player.dart`
- Test: `test/record_card_music_test.dart`

**Interfaces:**
- Produces: `String trackIdOf({required int page, required CardMusic music})`
- Produces: `abstract interface class CardAudioPlayer` — `Future<void> load(String url)` · `Future<void> play()` · `Future<void> pause()` · `Future<bool> otherAudioPlaying()` · `Future<void> dispose()`

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `test/record_card_music_test.dart`

```dart
group('곡의 신원', () {
  const playable = CardMusic(
    status: MusicStatus.completed,
    url: 'https://cdn.invalid/music/abc.m4a?sig=AAA&exp=1',
  );

  test('⚠️ 서명이 달라져도 같은 곡이다', () {
    // 폴링이 1분마다 새 주소를 준다. 주소를 그대로 비교하면 소리가 끊긴다.
    const again = CardMusic(
      status: MusicStatus.completed,
      url: 'https://cdn.invalid/music/abc.m4a?sig=BBB&exp=2',
    );
    expect(trackIdOf(page: 1, music: again), trackIdOf(page: 1, music: playable));
  });

  test('장이 다르면 다른 곡이다', () {
    expect(trackIdOf(page: 2, music: playable),
        isNot(trackIdOf(page: 1, music: playable)));
  });

  test('⚠️ 다시 만들면 상태가 바뀌어 다른 곡이 된다', () {
    // 서버가 같은 키를 덮어써도 GENERATING 을 지나가므로 다시 문다.
    const making = CardMusic(status: MusicStatus.generating);
    expect(trackIdOf(page: 1, music: making),
        isNot(trackIdOf(page: 1, music: playable)));
  });

  test('쿼리가 없는 주소도 된다', () {
    const bare = CardMusic(
      status: MusicStatus.completed,
      url: 'https://cdn.invalid/music/abc.m4a',
    );
    expect(trackIdOf(page: 1, music: bare), trackIdOf(page: 1, music: playable));
  });
});
```

- [ ] **Step 2: 돌려서 실패를 본다**

Run: `flutter.bat test test/record_card_music_test.dart`
Expected: FAIL — `trackIdOf` 가 없다

- [ ] **Step 3: `trackIdOf`를 쓴다** (`card_music.dart`)

`'$page|${music.status.name}|$path'` 꼴. `path`는 주소의 `?` 앞이고 주소가 없으면 빈 문자열이다. **`ProfilePhotoImage.cacheKeyOf`와 같은 방법**이라는 것을 주석에 적는다(`lib/core/widgets/profile_photo_image.dart:59`).

- [ ] **Step 4: 돌려서 통과를 본다**

Run: `flutter.bat test test/record_card_music_test.dart`
Expected: PASS

- [ ] **Step 5: `CardAudioPlayer`를 쓴다** (`card_audio_player.dart`)

위 Interfaces의 다섯 메서드만. `load`는 **물리기만 하고 틀지 않는다**(처음부터 다시 나게 하는 길), `play`는 **지금 자리에서** 튼다(이어 듣기). 못 물리면 던진다 — 가르지 않는다(설계 7-3). `otherAudioPlaying`은 **자동 재생을 접을지 가르는 값**이고, 안드로이드가 아니면 `false`다.

- [ ] **Step 6: analyze**

Run: `flutter.bat analyze`
Expected: `No issues found!`

- [ ] **Step 7: 커밋**

```bash
git add lib/features/record_card/domain test/record_card_music_test.dart
git commit -m "📍 Feat: 곡의 신원과 플레이어 인터페이스를 둔다"
```

---

### Task 3: `just_audio` 구현

**Files:**
- Modify: `pubspec.yaml` (`just_audio: ^0.10.6` — 이미 추가돼 있으면 그대로)
- Create: `lib/features/record_card/data/just_audio_player.dart`

**Interfaces:**
- Consumes: Task 2의 `CardAudioPlayer`
- Produces: `class JustAudioPlayer implements CardAudioPlayer` — 인자 없는 생성자

- [ ] **Step 1: `JustAudioPlayer`를 쓴다**

`AudioPlayer`를 하나 들고 생성 때 `setLoopMode(LoopMode.one)`을 건다 — **반복은 플레이어에 맡긴다**(설계 11절이 빌더에게 남긴 선택). 각 메서드는 그대로 넘긴다:

| 인터페이스 | `just_audio` |
|---|---|
| `load(url)` | `setUrl(url)` (`Future<Duration?>`, 실패하면 `PlayerException`을 던진다) |
| `play()` | `play()` |
| `pause()` | `pause()` |
| `dispose()` | `dispose()` |

`otherAudioPlaying()`은 **`AndroidAudioManager().isMusicActive()`** (`audio_session`). ⚠️ **안드로이드 전용 채널**이라 `defaultTargetPlatform != TargetPlatform.android`이면 부르지 않고 `false`를 낸다.

⚠️ **`play()`가 오디오 포커스를 가져간다** (`just_audio.dart:1098` — `audioSession.setActive(true)`). 남의 소리를 끊을지 말지는 **부르는 쪽이 `otherAudioPlaying()`으로 먼저 가린다.** 여기서 막지 않는다.

⚠️ **주소를 로그에 남기지 않는다.** 예외를 그대로 다시 던지되 주소를 메시지에 붙이지 않는다.

- [ ] **Step 2: analyze**

Run: `flutter.bat analyze`
Expected: `No issues found!`

- [ ] **Step 3: 안드로이드에서 뜨는지 본다**

Run: `flutter.bat build apk --flavor dev --debug`
Expected: 빌드 성공. 실패하면 `android/app/build.gradle.kts`의 `minSdk`가 `just_audio`가 요구하는 값(21) 이상인지 본다

- [ ] **Step 4: 커밋**

```bash
git add pubspec.yaml pubspec.lock lib/features/record_card/data/just_audio_player.dart
git commit -m "📍 Feat: just_audio 로 기록카드 곡을 튼다"
```

---

### Task 4: 상세 화면이 소리를 몬다

이 Task가 **Review Focus 1·2·3**을 전부 갖는다.

**Files:**
- Create: `lib/features/record_card/presentation/card_audio_provider.dart`
- Modify: `lib/features/record_card/presentation/card_detail_page.dart`
- Test: `test/record_card_audio_test.dart` (신규)

**Interfaces:**
- Consumes: Task 2의 `trackIdOf` · `CardAudioPlayer`, Task 3의 `JustAudioPlayer`
- Produces:
  - `final cardAudioPlayerProvider = Provider<CardAudioPlayer>(..., isAutoDispose: true)` — `JustAudioPlayer`를 만들고 `ref.onDispose`로 버린다. ⚠️ **`isAutoDispose`를 빼면 상세를 떠나도 플레이어가 앱이 끝날 때까지 산다.** **테스트가 override하는 자리**
  - `class CardAudioState { final String? trackId; final bool playing; }`
  - `final cardAudioProvider = NotifierProvider.family<CardAudio, CardAudioState, String>(CardAudio.new, isAutoDispose: true)`
  - `class CardAudio extends Notifier<CardAudioState>` — `Future<void> show({required int page, required CardMusic? music})` · `Future<void> toggle()` · `Future<void> suspend()`

- [ ] **Step 1: 가짜 플레이어와 실패하는 테스트를 쓴다** — `test/record_card_audio_test.dart`

```dart
/// 무엇을 시켰는지만 적는다. 소리는 내지 않는다.
class FakePlayer implements CardAudioPlayer {
  final calls = <String>[];
  bool othersPlaying = false;
  Object? loadThrows;

  @override
  Future<void> load(String url) async {
    calls.add('load');
    if (loadThrows != null) throw loadThrows!;
  }

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<bool> otherAudioPlaying() async => othersPlaying;

  @override
  Future<void> dispose() async => calls.add('dispose');
}
```

네 개를 쓴다. 카드와 pump 헬퍼는 `test/record_card_detail_test.dart`의 것을 본뜬다.

```dart
testWidgets('⚠️ 폴링이 새 주소를 줘도 다시 물지 않는다', (tester) async {
  // Review Focus 1. 서명 주소가 1분마다 달라진다.
  await open(tester, cardWith(url: '…/a.m4a?sig=AAA'));
  expect(fake.calls, ['load', 'play']);

  await refreshDetail(tester, cardWith(url: '…/a.m4a?sig=BBB'));

  expect(fake.calls, ['load', 'play']); // 늘지 않았다
});

testWidgets('⚠️ 서 있는 동안 곡이 완성되면 바로 난다', (tester) async {
  // Review Focus 2.
  await open(tester, cardWith(status: MusicStatus.generating, url: null));
  expect(fake.calls, isEmpty);

  await refreshDetail(tester, cardWith(status: MusicStatus.completed, url: '…/a.m4a'));

  expect(fake.calls, ['load', 'play']);
});

testWidgets('⚠️ 다른 앱이 소리를 내고 있으면 자동 재생을 접는다', (tester) async {
  // Review Focus 3. 물려는 두되 틀지 않는다. 버튼은 선다.
  fake.othersPlaying = true;
  await open(tester, cardWith(url: '…/a.m4a'));

  expect(fake.calls, ['load']);
  expect(find.text(AppStrings.recordCardMusicPlay), findsOneWidget);
});

testWidgets('장을 넘기면 그 장의 곡이 처음부터 난다', (tester) async {
  await open(tester, cardWith(url: '…/base.m4a', photoUrl: '…/photo.m4a'));
  fake.calls.clear();

  await tester.drag(find.byType(PageView), const Offset(-600, 0));
  await tester.pumpAndSettle();

  expect(fake.calls, ['load', 'play']);
});
```

- [ ] **Step 2: 돌려서 실패를 본다**

Run: `flutter.bat test test/record_card_audio_test.dart`
Expected: FAIL — `cardAudioProvider` 가 없다

- [ ] **Step 3: `card_audio_provider.dart`를 쓴다**

`show`가 이 Task의 전부다:

```
show(page, music)
  id = music == null ? null : trackIdOf(page: page, music: music)
  id == state.trackId  →  아무것도 하지 않는다   ← Review Focus 1·2가 여기서 갈린다
  music 이 틀 수 없다  →  pause 하고 trackId = id, playing = false
  틀 수 있다           →  load
                          틀 뜻이 있나?
                            처음 열었다 → otherAudioPlaying() 이 false 일 때만
                            이미 나고 있었다 → 그렇다
                            멈춰 두었다 → 아니다
                          그러면 play
```

⚠️ **멈춰 둔 채로 장을 넘기면 멈춘 채로 둔다.** 설계가 "장을 넘기면 자동 재생"이라 적었지만 **직전에 사람이 멈춘 것을 뒤집지 않는다.** 물려는 두어 `재생`을 누르면 바로 난다.

- [ ] **Step 4: 상세 화면을 배선한다** (`card_detail_page.dart`)

`_playing`을 지우고 `ref.watch(cardAudioProvider(card.id)).playing`을 쓴다. `_page`가 바뀌거나 `card`가 바뀌면 `show(page: _page, music: card.musicOfPage(_page))`를 부른다 — **그리는 중에 부르지 않는다**(`addPostFrameCallback`). 페이저의 `onTap`과 줄의 `onTogglePlay`는 둘 다 `toggle()`이다.

- [ ] **Step 5: 돌려서 통과를 본다**

Run: `flutter.bat test test/record_card_audio_test.dart`
Expected: PASS, 4개

- [ ] **Step 6: 전체 테스트와 analyze**

Run: `flutter.bat test` 그리고 `flutter.bat analyze`
Expected: 실패 0, `No issues found!`

- [ ] **Step 7: 커밋**

```bash
git add lib/features/record_card/presentation test/record_card_audio_test.dart
git commit -m "📍 Feat: 보고 있는 장의 곡을 튼다"
```

---

### Task 5: 멈추는 자리와 못 물렸을 때

**Files:**
- Modify: `lib/features/record_card/presentation/card_audio_provider.dart`
- Modify: `lib/features/record_card/presentation/card_detail_page.dart`
- Test: `test/record_card_audio_test.dart`

**Interfaces:**
- Consumes: Task 4의 `CardAudio.show` · `toggle` · `suspend`
- Produces: 없다 (Task 4의 것을 채운다)

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
testWidgets('⚠️ 두 번 실패해도 상세를 한 번만 다시 읽는다', (tester) async {
  // Review Focus 4. 만료된 주소를 다시 받았는데 또 만료였을 때.
  fake.loadThrows = Exception('load failed');
  await open(tester, cardWith(url: '…/a.m4a?sig=AAA'));
  expect(detailReads, 2); // 처음 + 다시

  await refreshDetail(tester, cardWith(url: '…/a.m4a?sig=BBB'));

  expect(detailReads, 2); // 늘지 않았다 — 조용히 접었다
});

testWidgets('앱이 배경으로 가면 멈추고 돌아와도 안 튼다', (tester) async {
  await open(tester, cardWith(url: '…/a.m4a'));
  fake.calls.clear();

  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump();
  expect(fake.calls, ['pause']);

  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump();
  expect(fake.calls, ['pause']); // 늘지 않았다
  expect(find.text(AppStrings.recordCardMusicPlay), findsOneWidget);
});

testWidgets('⚠️ 시트를 열어도 계속 난다', (tester) async {
  // ⋮ 메뉴는 잠깐 열었다 닫는 것이다 — 전체 화면이 아니다.
  await open(tester, cardWith(url: '…/a.m4a'));
  fake.calls.clear();

  await tester.tap(find.byTooltip(AppStrings.recordCardMore));
  await tester.pumpAndSettle();

  expect(fake.calls, isEmpty);
});
```

- [ ] **Step 2: 돌려서 실패를 본다**

Run: `flutter.bat test test/record_card_audio_test.dart`
Expected: FAIL — 세 개

- [ ] **Step 3: 못 물렸을 때를 채운다** (`card_audio_provider.dart`)

`load`가 던지면 **가르지 않고** `ref.invalidate(cardDetailProvider(cardId))`를 한 번 한다. 깃발은 **`trackId`별로** 든다 (`_retriedFor`) — 장이 바뀌면 신원이 달라져 저절로 내려간다. 두 번째 실패는 **조용히 접는다**: `playing = false`로 두고 카드는 그대로 선다.

⚠️ 설계 7-3은 깃발을 "위젯 상태"에 두라고 적었다. **provider가 `family` + `autoDispose`**라 다음 카드가 물려받지 않고, 장별로 내려야 하므로 `trackId`에 매다는 것이 더 정확하다. 행동은 설계와 같다.

- [ ] **Step 4: 생명주기를 단다** (`card_detail_page.dart`)

`AppLifecycleListener`로 `paused`·`inactive`에 `suspend()`. `suspend()`는 `pause()`하고 `playing = false`로 둔다 — **돌아와도 저절로 안 튼다.**

전체 화면이 덮였는지는 **`ModalRoute.of(context)?.isCurrent`**로 본다. 바텀시트는 `isCurrent`를 `false`로 만들므로 그것만으로는 모자라다 — `didPushNext`를 받는 `RouteObserver<PageRoute>`를 쓰면 **`PageRoute`만** 걸러진다(`showModalBottomSheet`는 `ModalBottomSheetRoute`이지 `PageRoute`가 아니다). `RouteObserver<PageRoute<dynamic>>`를 `MaterialApp.navigatorObservers`에 등록하고 상세가 `RouteAware`로 듣는다.

- [ ] **Step 5: 돌려서 통과를 본다**

Run: `flutter.bat test test/record_card_audio_test.dart`
Expected: PASS, 7개

- [ ] **Step 6: 전체 테스트와 analyze**

Run: `flutter.bat test` 그리고 `flutter.bat analyze`
Expected: 실패 0, `No issues found!`

- [ ] **Step 7: 커밋**

```bash
git add lib test
git commit -m "📍 Feat: 화면을 떠나면 음악을 멈춘다"
```

---

## 기기 확인 (전부 끝낸 뒤)

가짜 저장소는 `example.invalid` 주소를 주므로 **소리가 안 난다**(설계 9절). 터널을 열고 **실제 개발 서버**로 본다.

1. 카드를 연다 → 기본곡이 **바로 난다**
2. 30초 넘게 둔다 → **같은 곡이 다시 난다**(반복), 장은 **안 넘어간다**
3. 사진 장으로 민다 → **사진 곡이 처음부터** 난다
4. 다른 앱으로 음악을 틀어 두고 카드를 연다 → **남의 음악이 안 끊긴다**, `재생`이 서 있다
5. 수정 화면으로 간다 → **멈춘다.** `⋮`만 열면 → **계속 난다**
6. 홈 버튼 → **멈춘다.** 돌아와도 **안 난다**
7. 만드는 중인 카드를 열고 둔다 → 완성되면 **그 자리에서 난다**
