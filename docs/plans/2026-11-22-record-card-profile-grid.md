# 기록카드 프로필 그리드 · 전체 보기 · 러닝 요약 진입점 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** 공개한 카드가 **프로필에 선다** — 3열 9:16 그리드에 처음 6장, `더 보기`로
전체 보기 화면. 러닝 요약(S15)에 `기록카드 남기기`를 붙인다. 묶음 4·5가 넘긴
**남의 카드 소유 게이트**를 닫고, 사용자가 **대표 사진을 지정**할 수 있게 한다.

**Architecture:** 그리드 위젯은 `profile/`에 둔다(설계 7절 — 반대로 두면 `profile`이
`record_card`의 **화면**을 import하게 되고 CLAUDE.md가 그것을 막는다). 그래서 달력
칸과 그리드가 **함께 쓰는 그리는 조각**을 `core/widgets/`로 올린다 —
`core/widgets/run_map_view.dart`가 `session/domain`을 import하는 전례와 같은 모양이다.

소유 여부는 **들어온 길이 말한다.** `RecordCard`에 소유자 필드가 없고(카드 응답
스키마가 비어 있다 — 설계 10절 1번) 지어 넣으면 응답이 오는 날 도메인을 다시 짓는다.
라우트 쿼리 `mine`으로 받고, **모르면 `⋮`를 세우지 않는다**(설계 9절 "모르면 안
보여주는 쪽이 안전하다").

대표 사진은 **고른 것을 목록 맨 앞으로 올리는 것**이다(사용자 결정 2026-11-22).
썸네일 규칙은 `RecordCard.thumbnailUrl` = `photos.first` **그대로** — 서버에 새 컬럼이
필요 없고, 백엔드 답을 기다리지 않는다.

**Tech Stack:** Flutter · Riverpod 3 수동 provider + `FutureProvider.family`
(`composeRecordsProvider` 전례) · go_router(셸 밖 라우트) · Lucide 아이콘.

**Spec:** `docs/specs/2026-11-16-record-card-design.md` — 6-7(프로필 그리드) ·
6-8(러닝 요약 진입점) · 6-2(이미 카드가 있는 기록은 수정으로) · 7절(구조·라우트) ·
9절(그리드 6장 + `더 보기`) · 10절 5번(사용자별 조회 상한 미정).

앞선 묶음: `2026-11-16-record-card-calendar.md`(1) ·
`2026-11-18-record-card-compose.md`(2) ·
`2026-11-18-record-card-photo-publish.md`(3) ·
`2026-11-19-record-card-edit-delete.md`(4) · `2026-11-19-record-card-music.md`(5).

### 사용자가 정한 것 (2026-11-22)

| 물은 것 | 정한 것 |
|---|---|
| 대표 사진 지정 방식 | **고른 사진을 맨 앞으로 올린다.** 썸네일은 첫 장 그대로 |
| 대표를 고르는 자리 | **작성 2(사진) 화면.** 수정도 같은 화면이라 함께 된다 |

## Global Constraints

- 브랜치 `feat/record-card`에서 이어 간다. 커밋은 `<이모지> <type>: <한국어>`,
  **AI 공동 작성자 트레일러 금지**.
- `presentation → domain ← data`. **다른 feature의 화면·위젯은 import하지 않는다** —
  provider와 domain은 예외다(CLAUDE.md). 이 묶음이 `core/widgets/`로 올리는 이유다.
- 한국어 UI 문자열은 전부 `AppStrings`에, **정렬 위치에** 넣는다 — 프로필 묶음은
  `── 프로필 탭 (S22, 본인) ──` 바로 뒤, 요약 버튼은 `── 1인 러닝 ──` 안.
- 아이콘은 **Lucide만**. 색·치수는 `appColorsV2`·`AppSpacing`·`AppRadius` 토큰.
  **다크·라이트 둘 다** 그려 본다.
- 화면은 **loading / data / error 3분기**를 빠짐없이, **빈 상태**도 정의한다.
- `StateProvider`/`StateNotifierProvider` 금지. 수동 `NotifierProvider`는 기본이
  `isAutoDispose: false`다.
- 새 패키지 금지.
- `fvm` 대신 `C:\dev\runiverse\frontend\.fvm\flutter_sdk\bin\flutter.bat`을 부른다.
  이 워크트리에 `.fvm`이 없다(git-ignore). 포맷은 `dart format`(`flutter format`은
  없는 명령이다).
- 테스트 함정(묶음 4·5에서 걸렸다): **진행 표시 앞에서 `pumpAndSettle`은 영영 안
  끝난다** · `Fake...(delay:)`는 **모든 메서드**에 걸린다 · `autoDispose` provider는
  **듣는 사람 없이 `read`하면 매번 다시 만들어진다**(`container.listen`을 걸어 둔다) ·
  **타이머가 남은 채 끝나면 `!timersPending`으로 죽는다**.

## Review Focus

설계가 넌지시 요구하지만 아래 작업들의 테스트가 **짚지 않는** 입력들. 각 줄의
테스트를 그 코드를 가진 작업에 넣어 두었다.

1. **남의 프로필에서 카드를 열고 뒤로 왔을 때 탭이 바뀌면 안 된다** — 상세가 셸
   밖인 이유가 이것인데(설계 7절) 지금까지 그 길로 들어가 본 적이 없다 (Task 7).
2. **카드가 0장인 프로필** — 그리드는 **아무 말도 하지 않고**(설계 6-7) 자리를 비우되,
   전체 보기 **화면**은 빈 화면을 내보내지 않는다 (Task 6·8).
3. **받는 동안 프로필이 들썩이면 안 된다** — 그리드가 로딩에서 높이 0이면 아래
   여백이 튀어오르고, 받아 오면 다시 내려간다 (Task 6).
4. **러닝 요약에서 들어와 카드를 저장한 뒤** 러닝 세션이 남아 있으면 **다음 러닝이
   이 러닝의 거리에서 이어진다**(`run_summary_page.dart`의 `_leave` 주석) (Task 9).
5. **지우거나 고친 뒤 그리드가 옛 카드를 그대로 들고 있으면 안 된다** — 저장·삭제가
   달력(`recordCardControllerProvider`)만 버리고 그리드를 버리지 않으면, 프로필에
   지운 카드가 남는다 (Task 8).

---

### Task 1: 카드의 얼굴을 `core/widgets/`로 올린다

그리드가 달력 칸과 **같은 그림**을 그려야 한다(설계 6-7 "사진 없는 카드는 캘린더와
같은 경로 선 아트"). 지금 그 그림은 `record_card/presentation`에 있어 `profile`이
가져다 쓸 수 없다.

**동작이 바뀌지 않는 이사다.** 새 테스트를 쓰지 않는다 — 기존 테스트가 그대로
통과하는 것이 이 작업의 증거다.

**Files:**
- Create: `lib/core/widgets/route_art_view.dart` (옮김)
- Create: `lib/core/widgets/card_face.dart` — `CardFace`(지금의 `_Face`) ·
  `CardMarkDot` · `cardThumbnail()`
- Delete: `lib/features/record_card/presentation/route_art_view.dart`
- Modify: `record_card_cell.dart`(세 조각을 떼고 `CardFace`를 쓴다) ·
  `card_media_pager.dart` · `card_photo_page.dart` · `card_compose_page.dart`
- Modify (import만): `test/record_card_cell_test.dart` ·
  `test/record_card_compose_page_test.dart` · `test/record_card_detail_test.dart`

**Interfaces:**
- Consumes: `RecordCard.thumbnailUrl` · `RouteArt`
- Produces: `CardFace({required RecordCard card})` — 썸네일이 있으면 사진, 없으면 선
  아트, 둘 다 없으면 `CardMarkDot`. `cardThumbnail(BuildContext, String) ->
  ImageProvider<Object>`. `RouteArtView`가 `package:runiverse/core/widgets/`로 온다.

- [ ] **Step 1: 옮기기 전 전체 테스트를 돌려 기준을 잡는다**

Run: `C:\dev\runiverse\frontend\.fvm\flutter_sdk\bin\flutter.bat test`
Expected: 전부 통과. **이 수를 적어 둔다** — Step 4가 같은 수여야 한다.

- [ ] **Step 2: `route_art_view.dart`를 `core/widgets/`로 옮기고 import 네 곳을 고친다**

내용은 한 글자도 바꾸지 않는다. 클래스 주석의 "지도 위젯을 쓰지 않는다"는 그대로
맞는 말이다.

- [ ] **Step 3: `_Face`·`CardMarkDot`·`cardThumbnail`을 `core/widgets/card_face.dart`로 옮긴다**

`_Face` → `CardFace`로 이름만 공개한다. 주석(⚠️ 셋 — 경로도 사진도 없는 카드,
`assets/` 분기, 서명 URL 캐시)을 **함께 옮긴다.** `record_card_cell.dart`는
`CardFace`를 쓰고, `card_media_pager.dart`·`card_photo_page.dart`는 `cardThumbnail`을
새 경로에서 가져온다.

- [ ] **Step 4: 전체 테스트와 analyze**

Run: `...flutter.bat test` 그리고 `...flutter.bat analyze`
Expected: Step 1과 **같은 수**가 통과, analyze 경고 0.

- [ ] **Step 5: 커밋**

```
🤖 Refactor: 카드의 얼굴과 선 아트를 core로 올린다
```

---

### Task 2: 대표 사진을 지정한다 — 고른 것이 맨 앞으로 온다

설계에 없던 요구다(사용자, 2026-11-22). 지금은 **먼저 고른 사진**이 달력 칸과
그리드의 얼굴이 되고, 바꿀 길이 없다.

⚠️ **순서를 바꾸는 것으로 구현한다.** 썸네일 규칙(`photos.first`)을 건드리지 않아
서버에 새 컬럼이 필요 없다. 대신 **포토북 넘기는 순서도 함께 바뀐다** — 대표가 첫
사진이 된다. 사용자가 그 비용을 알고 골랐다.

⚠️ **서버가 사진 순서를 보존하는지 모른다.** 수정에서 `EditRecordCard.photos`는
"남길 사진 전체"를 순서대로 싣지만, 응답이 `id` 순으로 돌아오면 **올린 대표가
되돌아간다.** 이 묶음의 가짜는 목록 순서를 지킨다 — 질문을 적어 둔다.

**Files:**
- Modify: `lib/features/record_card/presentation/card_draft_provider.dart`
  (`makeCover(int index)`)
- Modify: `lib/features/record_card/presentation/card_photo_page.dart`
  (`대표로 지정` / 첫 장에서는 `대표 사진` 라벨)
- Modify: `lib/core/strings/app_strings.dart` (작성 2 묶음 안, 정렬 위치)
- Modify: `docs/notes/2026-11-16-record-card-backend-questions.md` (질문 한 줄)
- Test: `test/record_card_draft_provider_test.dart`(+3) ·
  `test/record_card_photo_page_test.dart`(+3) · `test/record_card_save_test.dart`(+1)

**Interfaces:**
- Consumes: `CardDraft.photos`(`List<CardPhotoDraft>`) · `_withPhoto` 전례
- Produces: `CardDraftController.makeCover(int index)` — `photos[index]`를 0번으로
  옮기고 **나머지 순서는 그대로** 둔다. 범위 밖이거나 이미 0번이면 **아무 일도
  하지 않는다**(상태를 새로 쓰지도 않는다).

- [ ] **Step 1: 실패하는 초안 테스트 셋을 쓴다**

```dart
test('대표로 고른 사진이 맨 앞으로 오고 나머지 순서는 그대로다', () {
  // a b c d → c a b d
});
test('이미 맨 앞이면 아무 일도 없다', () {
  // 상태 인스턴스가 그대로인지까지 본다 — 다시 쓰면 화면이 헛 그려진다.
});
test('범위 밖은 무시한다', () { /* -1, length */ });
```

- [ ] **Step 2: 실패를 본다**

Run: `...flutter.bat test test/record_card_draft_provider_test.dart`
Expected: FAIL — `makeCover`가 없다(컴파일 오류).

- [ ] **Step 3: `makeCover(int index)`를 `_withPhoto` 옆에 더한다**

- [ ] **Step 4: 통과를 본다** → Expected: PASS

- [ ] **Step 5: 실패하는 작성 2 테스트 셋을 쓴다**

```dart
testWidgets('⚠️ 대표로 지정하면 그 사진이 1번이 되고 화면이 1번으로 따라간다', ...);
testWidgets('⚠️ 첫 장에는 버튼이 아니라 대표 사진이라고만 적는다', ...);
// 음악 줄에서 배운 것과 같은 규칙이다 — 눌러도 아무 일도 없는 버튼을 두지 않는다.
testWidgets('⚠️ 대표를 바꾸면 캡션 칸이 그 장의 글로 바뀐다', ...);
// `_caption` 컨트롤러가 장과 따로 움직이면 캡션이 엉뚱한 사진에 붙는다.
```

Expected: FAIL — `대표로 지정`을 못 찾는다.

- [ ] **Step 6: 작성 2에 줄을 하나 더한다**

`사진 지우기` 위에 둔다. 보고 있는 장이 0번이면 **버튼 없이**
`AppStrings.recordCardPhotoCover`(`대표 사진`)만, 아니면
`AppStrings.recordCardPhotoMakeCover`(`대표로 지정`) `TextButton`이고 누르면
`_draft.makeCover(page)` 뒤 `_jump(0)`이다 — `_jump`가 캡션 칸까지 당겨 준다.

- [ ] **Step 7: 통과와 analyze** → Expected: PASS, 경고 0

- [ ] **Step 8: 저장이 그 순서로 간다는 테스트 한 줄**

```dart
test('대표로 올린 사진이 카드의 첫 사진으로 저장된다', ...);
// NewRecordCard.photos[0] 이 그 경로인지 본다.
```

- [ ] **Step 9: 백엔드 질문에 한 줄 더한다**

`docs/notes/2026-11-16-record-card-backend-questions.md`에 **사진 순서 보존**을
적는다 — "남길 사진 전체를 순서대로 싣는다. 응답도 그 순서로 오나, 정렬 키가
따로 있나. **대표 사진이 그 순서에 걸린다.**"

- [ ] **Step 10: 커밋**

```
📍 Feat: 대표 사진을 지정한다 — 고른 것이 맨 앞으로 온다
```

---

### Task 3: 저장소가 "이 사람의 공개된 카드"를 답한다

**Files:**
- Modify: `lib/features/record_card/domain/record_card_repository.dart`
- Modify: `lib/features/record_card/data/fake_record_card_repository.dart`
- Modify: 테스트 가짜 **9개**(`implements RecordCardRepository`) — 던지는 구현만 더한다
- Test: `test/record_card_user_cards_test.dart` (새 파일)

**Interfaces:**
- Produces: `Future<List<RecordCard>> byUser({required String userId, int? limit})` —
  **최신순**(시작 시각 내림차순, 달력의 오름차순과 반대다), 없으면 빈 목록.
  `limit`이 `null`이면 서버 기본값에 맡긴다.

⚠️ **거르는 것은 서버다**(설계 6-7). 앱이 `PRIVATE`를 거르면 **안 보여야 할 카드가
이미 기기에 와 있다**는 뜻이 된다. 가짜는 서버 역할이라 자기가 거른다.

⚠️ **가짜는 사용자별 카드를 모른다.** 카드에 소유자 필드가 없어 누가 묻든 **같은
목록**을 준다 — 남의 프로필에서도 그리드가 서는 것이 눈검증에는 오히려 필요하다.
소유자가 응답에 생기는 날 여기서 가른다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
test('비공개는 빠진다 — 내 카드여도', ...);        // 20장 중 PRIVATE 전부
test('최신순이다', ...);                          // startedAt 내림차순
test('limit만큼만 준다', ...);                     // limit: 7 → 7장
test('limit이 없으면 전부 준다', ...);
test('지운 카드는 빠진다', ...);                   // delete 뒤
test('방금 만든 공개 카드가 맨 앞에 선다', ...);    // create 뒤
test('고쳐서 비공개가 된 카드는 빠진다', ...);      // update 뒤
test('실패를 흉내낸다', ...);                      // failWith → RecordCardException
```

- [ ] **Step 2: 실패를 본다** → Expected: FAIL (`byUser`가 없다)

- [ ] **Step 3: 인터페이스에 메서드를 더한다**

왜 공개범위를 서버가 거르는지, 상한이 미정이라 `limit`이 `int?`인지(설계 10절 5번)
주석으로 남긴다.

- [ ] **Step 4: 가짜에 구현을 더한다**

살아 있는 카드를 모으는 기존 경로(`byDateRange`가 쓰는 것)를 **그대로 재사용**한다 —
따로 모으면 지운 카드가 한쪽에만 남는다.

- [ ] **Step 5: 테스트 가짜 9개를 컴파일되게 한다**

Run: `...flutter.bat test`
Expected: 전부 통과. (가짜들은 `UnimplementedError`를 던진다 — 이 메서드를 안 쓰는
테스트들이다.)

- [ ] **Step 6: 커밋** — `📍 Feat: 저장소가 이 사람의 공개된 카드를 답한다`

---

### Task 4: 그 사람의 카드를 읽는 provider

**Files:**
- Create: `lib/features/profile/presentation/profile_cards_provider.dart`
- Test: `test/profile_cards_provider_test.dart`

**Interfaces:**
- Consumes: `recordCardRepositoryProvider`(provider는 feature를 넘어도 된다 —
  CLAUDE.md 예외) · `RecordCardRepository.byUser`
- Produces: `typedef ProfileCardsQuery = ({String userId, int? limit});`
  `final profileCardsProvider = FutureProvider.autoDispose.family<List<RecordCard>,
  ProfileCardsQuery>(retry: (_, _) => null, ...)`

⚠️ **자동 재시도를 끈다** — Riverpod 3은 실패한 provider를 10번(약 38초) 다시 부르고
그동안 화면은 **오류 분기에 닿지 못한다**(`composeRecordsProvider`에 같은 주석).

⚠️ **키에 `limit`이 들어간다.** 그리드(7)와 전체 보기(전부)가 **다른 조회**다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
test('공개된 카드를 돌려준다', ...);
test('실패하면 바로 오류다 — 다시 부르지 않는다', ...);   // 호출 수 1
test('limit이 다르면 따로 받는다', ...);                 // 호출 수 2
```
- [ ] **Step 2: 실패를 본다** → FAIL
- [ ] **Step 3: provider를 쓴다**
- [ ] **Step 4: 통과를 본다** → PASS
- [ ] **Step 5: 커밋** — `📍 Feat: 프로필이 그 사람의 카드를 묻는다`

---

### Task 5: 상세가 남의 카드에서 손을 뗀다

묶음 4가 미뤄 둔 것이다(`2026-11-19-record-card-edit-delete-deferred.md` 1번 —
"**묶음 6에서 반드시 본다**"). 그리드가 붙는 순간 남의 카드에 **수정·삭제와
`AI 음악 만들기`**가 선다.

**Files:**
- Modify: `lib/app/router/app_routes.dart` (`recordCardDetailOf(id, {required mine})`)
- Modify: `lib/app/router/app_router.dart` (상세 builder가 쿼리를 읽는다)
- Modify: `lib/features/record_card/presentation/card_detail_page.dart` (`mine`)
- Modify: `lib/features/record_card/presentation/music_strip.dart` (`canRequest`)
- Modify: `record_card_page.dart`·`card_compose_page.dart` (부르는 쪽 둘)
- Test: `test/record_card_detail_test.dart`(+3) ·
  `test/record_card_music_strip_test.dart`(+2) ·
  `test/record_card_edit_flow_test.dart`(호출 고치기)

**Interfaces:**
- Produces: `CardDetailPage({required RecordCard card, required bool mine})` ·
  `AppRoutes.recordCardDetailOf(int cardId, {required bool mine})` →
  `/record-card/card/42?mine=true` · `MusicStrip({... required bool canRequest})`

⚠️ **`mine`을 선택 인자로 두지 않는다.** 기본값을 주면 새 진입점이 조용히 "내 것"으로
들어오고, 그 결과는 남의 카드에 뜬 수정 버튼이다. **컴파일러가 묻게 한다.**

⚠️ **쿼리가 없으면 "내 것이 아니다"로 읽는다**(`== 'true'`). 딥링크·복원으로 들어온
경우가 그렇다 — 모르면 손을 떼는 쪽이 안전하다(설계 9절).

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
testWidgets('⚠️ 남의 카드에는 ⋮가 없다', ...);
testWidgets('⚠️ 남의 카드에서는 음악을 만들라고 하지 않는다', ...);
// canRequest: false + none/failed → 줄이 아예 서지 않는다(높이 0).
testWidgets('⚠️ 남의 카드에서도 다 된 음악은 재생을 쥔다', ...);
// 듣는 것은 읽기다. succeeded면 토글이 그대로 선다.
test('모르는 길로 들어오면 내 것이 아니다', ...);  // 쿼리 없는 location
```

- [ ] **Step 2: 실패를 본다** → FAIL

- [ ] **Step 3: `mine`을 라우트와 화면에 꿴다**

- [ ] **Step 4: `MusicStrip`에 `canRequest`를 더한다**

`!canRequest`면 `succeeded`만 그리고 나머지(none·failed·queued·processing·loading·
error)는 `SizedBox.shrink()`다. **빈 40px를 남기지 않는다** — 남의 카드에서는 그
자리가 고장으로 읽힌다.

- [ ] **Step 5: 통과·전체 테스트·analyze** → PASS, 경고 0

- [ ] **Step 6: 커밋** — `🔨 Fix: 남의 카드에서는 고치지도 지우지도 못한다`

---

### Task 6: 프로필 그리드 위젯

**Files:**
- Create: `lib/features/profile/presentation/profile_card_grid.dart`
- Modify: `lib/core/strings/app_strings.dart` (`── 프로필 기록카드 그리드 (설계
  6-7) ──` 묶음을 `── 프로필 탭 (S22, 본인) ──` **바로 뒤**에)
- Test: `test/profile_card_grid_test.dart` (새 파일)

**Interfaces:**
- Consumes: `profileCardsProvider` · `CardFace` · `AppRoutes.recordCardDetailOf`
- Produces: `ProfileCardGrid({required String userId, required bool mine})` ·
  `ProfileCardTile({required RecordCard card, required VoidCallback onTap})` ·
  `ProfileCardGrid.previewCount = 6`

**문자열:** `profileCardsMore`(`더 보기`) · `profileCardsError`(`기록카드를 읽지
못했어요`) · `profileCardsOn(DateTime)`(스크린리더 — `9월 2일 기록카드`).
`다시 시도`는 `AppStrings.recordRetry`를 쓴다.

⚠️ **7장을 묻고 6장을 깐다.** 6장만 물으면 "더 있는지"를 알 수 없어 `더 보기`를
항상 세우게 되고, 딱 6장인 사람이 빈 화면으로 간다.

⚠️ **카드가 없으면 아무것도 그리지 않는다**(설계 6-7). 남의 프로필에 "아직
없어요"를 띄울 이유가 없다.

⚠️ **받는 동안에도 자리를 지킨다** — 로딩이 높이 0이면 프로필 아래가 튀어오른다.
두 줄 높이만큼 잡고 가운데에 진행 표시를 둔다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
testWidgets('처음 여섯 장만 깐다', ...);                       // 7장 응답 → 타일 6
testWidgets('일곱 번째가 있으면 더 보기가 선다', ...);
testWidgets('여섯 장 이하면 더 보기가 없다', ...);              // 6장 응답
testWidgets('⚠️ 카드가 없으면 아무것도 그리지 않는다', ...);     // 높이 0
testWidgets('사진 없는 카드는 선 아트로 선다', ...);            // RouteArtView
testWidgets('눌러서 상세로 간다 — 남의 것이면 mine=false', ...);
testWidgets('못 읽으면 한 줄로 말하고 다시 시도가 선다', ...);
testWidgets('⚠️ 받는 동안에도 높이가 같다', ...);
testWidgets('라이트 테마에서도 그려진다', ...);
testWidgets('스크린리더가 무슨 칸인지 읽는다', ...);
```

- [ ] **Step 2: 실패를 본다** → FAIL
- [ ] **Step 3: 문자열 셋을 정렬 위치에 넣는다**
- [ ] **Step 4: 위젯을 쓴다**

`GridView.count(crossAxisCount: 3, childAspectRatio: 9/16, shrinkWrap: true,
physics: NeverScrollableScrollPhysics())` — 프로필이 이미 스크롤한다.

- [ ] **Step 5: 통과와 analyze** → PASS, 경고 0
- [ ] **Step 6: 커밋** — `📍 Feat: 공개한 카드가 프로필에 3열로 선다`

---

### Task 7: 두 프로필 화면에 꽂는다

**Files:**
- Modify: `lib/features/profile/presentation/profile_page.dart` — `ProfileStatRow`
  아래, "**아래 본문이 비어 있다. 빠뜨린 것이 아니다**"라고 적힌 그 자리
- Modify: `lib/features/profile/presentation/user_profile_page.dart` —
  `ProfileStatRow` 아래
- Test: `test/profile_card_grid_test.dart`(+2)

⚠️ **내 프로필은 `mine: true`가 구조적으로 참이다.** 남의 프로필은
`summary.isMe`를 그대로 넘긴다 — 서버가 답한 값이고, 소유 판단을 두 군데서 따로
계산하지 않는다.

⚠️ 내 프로필의 `userId`는 `AuthSignedIn.userId`다. 없으면(`/me` 전) 그리드를 세우지
않는다 — 누구의 카드를 물을지 모른다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
testWidgets('내 프로필의 친구 줄 아래에 그리드가 선다', ...);
testWidgets('⚠️ 남의 프로필에서 카드를 열고 뒤로 와도 탭이 바뀌지 않는다', ...);
// Review Focus 1. 상세가 셸 밖인 이유가 이것이다(설계 7절).
```
- [ ] **Step 2: 실패를 본다** → FAIL
- [ ] **Step 3: 두 화면에 꽂는다** (바닥 여백 계산을 건드리지 않는다)
- [ ] **Step 4: 통과·전체 테스트** → PASS
- [ ] **Step 5: 커밋** — `📍 Feat: 내 프로필과 남의 프로필이 같은 그리드를 쓴다`

---

### Task 8: 전체 보기 화면 · 지우거나 고치면 그리드도 다시 받는다

**Files:**
- Create: `lib/features/profile/presentation/profile_cards_page.dart`
- Modify: `lib/app/router/app_routes.dart` (`/record-card/user/:userId`, **정렬
  위치에**) · `lib/app/router/app_router.dart` (셸 **밖**)
- Modify: `lib/features/profile/presentation/profile_card_grid.dart` (`더 보기`가
  거기로 간다)
- Modify: `lib/features/record_card/presentation/card_save_provider.dart` ·
  `card_delete_provider.dart` (`ref.invalidate(profileCardsProvider)`)
- Modify: `lib/core/strings/app_strings.dart` (`profileCardsTitle` ·
  `profileCardsEmpty`)
- Test: `test/profile_cards_page_test.dart`(새) ·
  `test/record_card_save_test.dart`(+1) · `test/record_card_delete_test.dart`(+1)

**Interfaces:**
- Produces: `AppRoutes.recordCardsOfUser = '/record-card/user/:userId'` ·
  `AppRoutes.recordCardsOf(String userId, {required bool mine})` (userId를
  `Uri.encodeComponent`한다 — `userFriendsOf` 전례) ·
  `ProfileCardsPage({required String userId, required bool mine})`

⚠️ **경로를 `/record-card/` 아래 둔다.** Task 9의 되돌아가기 규칙이 경로 앞머리로
"작성/수정 흐름"을 가리기 때문이고, 셸 밖이라 **탭이 바뀌지 않는다**.

⚠️ **화면의 빈 상태는 한 줄을 둔다.** 그리드는 침묵하지만(설계 6-7), 눌러서 들어온
화면이 텅 비면 고장으로 읽힌다.

⚠️ **`profileCardsProvider`를 묶음째 버린다** — 키에 `limit`이 들어 있어 하나만
버리면 그리드와 전체 보기 중 한쪽이 옛 목록을 들고 남는다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
testWidgets('더 보기를 누르면 전체 보기로 간다', ...);
testWidgets('전체 보기는 limit 없이 전부 받는다', ...);
testWidgets('카드가 없으면 한 줄로 알린다', ...);
testWidgets('못 읽으면 오류와 다시 시도가 선다', ...);
testWidgets('카드를 눌러 상세로 간다 — mine이 그대로 간다', ...);
test('카드를 지우면 프로필 그리드도 다시 받는다', ...);   // delete_test
test('카드를 고치면 프로필 그리드도 다시 받는다', ...);   // save_test
```
- [ ] **Step 2: 실패를 본다** → FAIL
- [ ] **Step 3: 라우트·화면·`더 보기` 링크를 쓴다**
- [ ] **Step 4: 저장·삭제가 그리드를 버리게 한다**
- [ ] **Step 5: 통과·전체 테스트·analyze** → PASS, 경고 0
- [ ] **Step 6: 커밋** — `📍 Feat: 더 보기로 그 사람의 카드를 전부 본다`

---

### Task 9: 러닝 요약에 진입점을 붙이고, 돌아올 자리를 지킨다

설계 6-8이 `run_summary_page.dart`에 적어 둔 그대로다 — "`기록카드 남기기` 버튼은
탭이 `ComingSoonPage`라 뺐다. 탭이 살아나면 이 위에 붙는다."

**Files:**
- Modify: `lib/features/session/presentation/run_summary_page.dart`
- Modify: `lib/app/router/app_routes.dart` (`recordCardNewOn`에 `roomId`)
- Modify: `lib/app/router/app_router.dart` (`_toDetail`의 되돌아가기 범위 ·
  작성 1 builder가 `room`을 읽는다)
- Modify: `lib/features/record_card/presentation/card_compose_page.dart`
  (`roomId`로 미리 고른다 · 이미 카드가 있으면 **수정으로**)
- Modify: `lib/core/strings/app_strings.dart` (`runSummaryRecordCard`)
- Test: 러닝 요약 테스트(+2) · `test/record_card_compose_page_test.dart`(+3) ·
  `test/record_card_edit_flow_test.dart`(+1)

**Interfaces:**
- Produces: `AppRoutes.recordCardNewOn(DateTime day, {int? roomId})` →
  `?date=2026-11-22&room=120` · `CardComposePage({... int? roomId})`

**정하고 가는 것 셋:**

1. ⚠️ **요약은 날짜가 아니라 방 번호로 기록을 가리킨다.** `RunDetail`에 기록 번호가
   없고(`runningRoomId`뿐) `RunRecord.runningRoomId`가 있어 **그 번호로 맞춘다.**
   방이 없으면(솔로·방 열기 실패) 날짜만 넘기고 고르는 것은 사용자가 한다.
2. ⚠️ **요약을 닫고 간다.** `닫기`와 같은 길이다 — `reset()` 뒤 홈으로 `go`,
   그 위에 작성 1을 `push`. 요약을 남겨 두고 작성으로 가면, 저장할 때 요약까지
   걷히면서 **`reset()`이 안 불려 다음 러닝이 이 러닝의 거리에서 이어진다**
   (Review Focus 4).
3. ⚠️ **`_toDetail`이 자기 흐름만 걷는다.** 지금은 `while (canPop()) pop()`이라
   **쓰던 새 카드 화면까지 걷힌다**(묶음 4 미뤄 둔 것 4번). 고치는 흐름이면
   `/record-card/card/`로 시작하는 것만, 새 카드면 `/record-card/new`로 시작하는
   것만 걷는다 — `router.state.matchedLocation`을 본다(`app_shell.dart` 전례).

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
testWidgets('요약에서 기록카드 남기기로 작성 1에 간다 — 날짜와 방이 실린다', ...);
testWidgets('⚠️ 요약을 떠날 때 러닝 세션을 비운다', ...);
// 비우지 않으면 다음 러닝이 이 거리에서 이어진다.
testWidgets('방 번호로 그 기록이 미리 골라진다', ...);
testWidgets('⚠️ 그 기록에 이미 카드가 있으면 수정 화면으로 보낸다', ...);
// 설계 6-2. 작성 화면을 띄워 놓고 못 쓰게 하는 것보다 낫다.
testWidgets('방이 없으면 날짜만 정해지고 고르는 것은 사용자가 한다', ...);
testWidgets('⚠️ 고쳐 저장해도 쓰던 새 카드 화면은 걷히지 않는다', ...);
```

- [ ] **Step 2: 실패를 본다** → FAIL

- [ ] **Step 3: 요약에 버튼을 붙인다**

`자세한 기록 보기` **위**에 둔다 — 방금 한 일을 남기는 것이 결과를 들여다보는 것보다
앞이다. 주 버튼(`AppButtonV2` 기본 변형)으로 두고, 아래 `자세한 기록 보기`는 지금의
`tonal` 그대로 둔다.

- [ ] **Step 4: 작성 1이 방 번호로 미리 고른다**

목록이 오면 **한 번만** 고른다(`_preselected` 깃발). 이미 초안에 기록이 있으면
건드리지 않는다 — 쓰던 것을 되돌리면 안 된다. 맞은 기록에 카드가 있으면
`pushReplacement`로 **수정 1**로 보낸다(`extra`에 그 카드).

- [ ] **Step 5: `_toDetail`의 범위를 좁힌다**

낡은 주석("러닝 요약에서 들어온 경우까지 걷는다(묶음 6). 그때 이 줄을 다시 본다")을
**정한 것으로 바꿔 적는다.**

- [ ] **Step 6: 목록의 `카드` 줄도 수정으로 보낸다**

`_pick`이 지금 상세로 보내면서 "수정 화면은 뒤 PR이라"라고 적어 뒀다 — 그 PR이
끝났다(묶음 4). 설계 6-2의 "**누르면 수정으로 보낸다**"로 맞춘다.

- [ ] **Step 7: 통과·전체 테스트·analyze** → PASS, 경고 0

- [ ] **Step 8: 커밋** — `📍 Feat: 러닝 요약에서 바로 기록카드를 쓴다`

---

## 자기 점검 (계획을 쓴 뒤)

**설계 덮기**: 6-7의 모든 줄(공개한 것만 · 같은 위젯 두 곳 · 서버가 거른다 ·
6장+더 보기 · 선 아트 · 빈 자리)이 Task 3·6·7·8에 있다. 6-8은 Task 9.
6-2의 "이미 카드가 있으면 수정으로"는 Task 9 Step 4·6.

**설계에 있는데 이 계획에 없는 것**:
- **PR 1.5(모아보기 — 유형별 앨범 줄 + 탭 머리 보기 전환)는 들어 있지 않다.**
  묶음 1에서 "보기 전환은 다음 묶음이 이 머리에 더한다"로 미뤄 둔 뒤 아무 묶음도
  가져가지 않았다. **이 묶음에서도 하지 않는다** — 프로필과 관계가 없고, 묶음 6을
  두 배로 만든다. 1차 작업이 끝난 뒤 따로 한다.
- 11절 "분기 칸 크기 · 전환 애니메이션 · 핀치 충돌"은 기기에서 정하는 것이라 그대로
  남는다.

**이름 맞춤**: `profileCardsProvider` · `ProfileCardsQuery` · `ProfileCardGrid` ·
`ProfileCardTile` · `ProfileCardsPage` · `CardFace` · `cardThumbnail` ·
`recordCardDetailOf(id, mine:)` · `recordCardsOf(userId, mine:)` ·
`makeCover(index)` — Task 3~9에서 쓰는 이름이 모두 선언하는 Task와 같다.

**PR 크기**: 25파일 / 500줄을 넘는다. **사유를 PR에 적는다** — 그리드 하나를
세우려면 조각 이사(Task 1) · 저장소 · provider · 소유 게이트가 함께 가야 하고,
쪼개면 사용자에게 보이는 것이 없는 PR이 생긴다. CLAUDE.md가 허용하는 예외다.
