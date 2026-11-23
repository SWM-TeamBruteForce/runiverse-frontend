# 기록카드 읽기 연동 구현 계획 (묶음 7)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 가짜 저장소로 돌던 기록카드의 **읽기 경로**(달력·상세·프로필)를 실제 서버에 붙인다. 쓰기(저장·수정)는 묶음 8이다.

**Architecture:** 카드 ID를 UUID 문자열로 바꾸고, 달력은 러닝 기록 목록(7-1) **한 요청**으로 카드 유무까지 받고, 상세는 8-1을 id로 따로 읽는다. 프로필은 10-3의 커서 페이지를 쓴다. `HttpRecordCardRepository`가 읽기를 구현하고 **쓰기 두 개(`create`·`update`)는 `FakeRecordCardRepository`에 위임**한다 — 묶음 8에서 그 두 줄만 바뀐다.

**Tech Stack:** dio · Riverpod 3 수동 provider · go_router

**Spec:** 노션 「💾 [1.3.2] 기록 카드 프론트엔드 연동 가이드」(`421ae181f71080d2bba5f996c8653c89`) + `docs/specs/2026-11-16-record-card-design.md`

## Global Constraints

가이드에서 그대로 옮긴 값이다. 어기면 서버가 거절한다.

- 모든 경로 앞에 `/api/v1`. 공통 헤더(`Authorization`·`X-App-Version`·`X-App-Platform`)는 `AppVersionHeaders.current`와 기존 인터셉터가 이미 붙인다 — **손대지 않는다.**
- 오류 본문은 `{ "code": "...", "message": "..." }`이고 **분기는 `code` 기준**이다. `403 APP_UPDATE_REQUIRED`는 `dio_client.dart`의 `updateRequiredInterceptor`가 저장소보다 먼저 잡는다 — 카드 실패로 바꾸지 않는다.
- **ID 타입**: `recordCardId`·`recordCardImageId`·`recordCardDraftId`는 **문자열**(UUID v7 꼴). `runningRecordId`·`runningRoomId`는 `int`.
- 시각은 **오프셋 없는 KST**. `DateTime.parse` 그대로 쓰고 `.toUtc()`를 붙이지 않는다.
- 7-1 한 요청은 **양 끝 포함 최대 31일**. 초과하면 `400`.
- `activityType` = `DAILY`·`RACE`·`TRAVEL` / `visibility` = `FRIENDS`·`PUBLIC`·`PRIVATE` / 러닝 `type` = `SOLO`·`MATCH`·`INVITE`.
- `routeArt`는 조각별 `[x, y]` 배열이고 **0~1, y는 아래로 증가**한다. 상세는 합쳐 최대 200점(조각이 아주 많으면 조금 넘을 수 있다), 달력은 최대 50점. **빈 배열은 점 하나**로 그린다.
- 10-3: `limit` 기본 20·최대 50, `cursor`로 이어 받고 `nextCursor == null`에서 멈춘다. 1 미만이나 잘못된 커서는 `400`.
- 음악 상태는 `GENERATING`·`COMPLETED`·`FAILED`. **기본곡 하나 + 사진마다 하나**다.
- 조회용 URL(사진·썸네일·프로필·음악)은 **1시간**. `403`이면 그 URL을 준 API를 다시 부른다.
- CLAUDE.md 전부: Lucide만 · `AppStrings` 정렬 자리 · 테마 토큰 밖 색 하드코딩 금지 · loading/data/error 3분기 + empty + 다크·라이트 · 다른 feature의 화면·위젯 import 금지(provider는 예외).

## 사용자가 정한 것

| 정한 것 | 날짜 | 계획에 미치는 영향 |
|---|---|---|
| 연동까지 끝내고 PR을 올린다 | 2026-11-24 | 묶음 1~6은 PR 전에 이 묶음이 덮는다. ID 타입이 바뀌므로 먼저 올리면 리뷰 중 통째로 바뀐다 |
| 읽기 먼저, 쓰기는 다음 묶음 | 2026-11-24 | 쓰기 두 메서드는 Fake에 위임해 남긴다 (Task 2) |
| 대표 사진은 **고른 것을 맨 앞으로** | 2026-11-23 | 가이드가 그 UI에 `thumbnailIndex: 0`을 적어 뒀다 — `makeCover()`는 그대로 두고 쓰기 묶음에서 필드만 싣는다 |
| 비공개 카드는 프로필에 안 보인다 | 2026-11-19 | **지금 지킬 수 없다** — 아래 미결 참고 |

### ⚠️ 미결 — 내 프로필의 비공개 카드

10-3은 **본인에게 `PRIVATE`까지 보낸다**(가이드 5절 표). 그런데 항목에 들어오는 값은 `recordCardId`·`thumbnailUrl`·`imageCount`·`startedAt`·`totalDistanceMeters`뿐이고 **`visibility`가 없다** — 앱이 가려낼 근거가 없다. 세 길뿐이다.

1. 백엔드에 항목에 `visibility`를 넣어 달라고 하거나 `visibility` 필터 파라미터를 요청한다.
2. 결정을 뒤집어 내 프로필에도 비공개를 보여준다.
3. 그리드 항목마다 8-1을 불러 `visibility`를 본다 — **여섯 번 왕복이라 하지 않는다.**

**Task 6은 서버가 주는 대로 보여주는 것으로 적었다**(가이드대로). 사용자 결정이 오면 그 자리에 한 줄이 붙거나, 백엔드 답이 오면 필터가 붙는다.

## Review Focus

테스트가 다루지 않지만 사람에게 먼저 닿는 다섯 가지다. 각 줄의 테스트를 그 코드를 가진 작업에 붙였다.

1. **사진을 다 지운 카드** — 7-1의 `recordCard`가 있는데 `thumbnailUrl`이 `null`이고 `routeArt`도 빈 배열일 때 달력 칸이 **점 하나**를 그리는지. 가이드 1절 표의 마지막 갈래다. → Task 3
2. **같은 날 카드가 둘이고 마지막 카드가 유형 필터에 걸러질 때** 칸에 어느 카드를 그리는지. 가이드: "같은 날에 조건과 일치하는 다른 카드가 있으면 그 카드를 목록과 개수 배지에 포함." 지금 `cards.last`를 쓰므로 **걸러진 뒤의** 마지막이어야 한다. → Task 3
3. **상세의 `routeArt`가 200점을 넘겨 올 때** 그리는 쪽이 점 수에 상한을 두거나 느려지지 않는지. 가이드가 "조금 넘을 수 있다"고 적었다. → Task 4
4. **음악 폴링이 화면을 떠난 뒤에도 도는지**, 그리고 **재진입 때 기본곡 교체를 잡는지**. 가이드: 교체 중에도 `COMPLETED`로 보여 `GENERATING`만 보는 폴링은 시점을 놓친다. → Task 5
5. **만료된 URL의 403 재조회가 루프를 만들지 않는지** — 재조회 → 또 403 → 또 재조회. 한 번만 시도해야 한다. → Task 7

---

### Task 1: 카드 ID를 문자열로

순수 리팩터다. **동작이 하나도 바뀌지 않는다** — 테스트 수가 앞뒤로 같아야 한다.

**Files:**
- Modify: `lib/features/record_card/domain/record_card.dart` (`RecordCard.id`, `RecordCardPhoto.id`)
- Modify: `lib/features/record_card/domain/edit_record_card.dart` (`EditCardPhoto.savedId`, `EditRecordCard.cardId`)
- Modify: `lib/features/record_card/domain/record_card_repository.dart` (`delete`·`musicOf`·`requestMusic`의 매개변수)
- Modify: `lib/features/record_card/domain/music_generation.dart` (`MusicGeneration.cardId`)
- Modify: `lib/app/router/app_routes.dart` (`recordCardDetailOf`·`recordCardEditOf`·`recordCardEditPhotosOf`·`recordCardEditPublishOf`)
- Modify: `lib/app/router/app_router.dart` (`:cardId`의 `int.tryParse` 제거, `_toDetail`)
- Modify: `lib/features/record_card/presentation/card_delete_provider.dart`, `card_music_provider.dart`, `card_draft_provider.dart`, `card_detail_page.dart`
- Modify: `lib/features/profile/presentation/profile_card_tile.dart`
- Modify: `lib/features/record_card/data/fake_record_card_repository.dart` (mock id를 `'card-1000'` 꼴로)
- Test: 카드 id를 쓰는 테스트 전부

**Interfaces:**
- Produces: `RecordCard.id: String` · `RecordCardPhoto.id: String` · `EditCardPhoto.savedId: String?` · `EditRecordCard.cardId: String` · `RecordCardRepository.delete(String cardId)` · `musicOf(String)` · `requestMusic(String)` · `AppRoutes.recordCardDetailOf(String cardId, {required bool mine})`

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `test/record_card_router_test.dart`에 `'⚠️ UUID 카드 번호로 상세를 연다'`: `AppRoutes.recordCardDetailOf('019aa100-0000-7000-8000-000000000001', mine: true)`로 `go`한 뒤 `find.byType(CardDetailPage)`가 하나 잡히는지.
- [ ] **Step 2: 지금 실패하는 것을 본다** — `.fvm\flutter_sdk\bin\flutter.bat test test/record_card_router_test.dart`. 기대: 컴파일 실패(`String`을 `int` 자리에 넣었다).
- [ ] **Step 3: 위 Files 목록을 `int` → `String`으로 옮긴다.** 라우트의 `int.tryParse` 분기는 **지운다** — 문자열은 파싱할 것이 없고, 빈 문자열만 막는다.
- [ ] **Step 4: 통과를 본다** — 같은 명령. 기대: PASS.
- [ ] **Step 5: 전체 테스트를 돌린다** — `.fvm\flutter_sdk\bin\flutter.bat test`. 기대: **묶음 6 끝과 같은 수**(3,249)가 통과. 수가 줄면 테스트를 지운 것이다.
- [ ] **Step 6: analyze 0을 확인하고 커밋** — `🤖 Refactor: 카드 번호를 서버가 주는 문자열로 바꾼다`

---

### Task 2: 오류를 `code`로 읽고, Http 저장소 골격을 세운다

읽기는 아직 **던진다.** provider에 꽂지 않는다 — 꽂는 것은 Task 10이다.

**Files:**
- Create: `lib/features/record_card/data/record_card_error.dart`
- Create: `lib/features/record_card/data/http_record_card_repository.dart`
- Test: `test/http_record_card_repository_test.dart`

**Interfaces:**
- Consumes: Task 1의 문자열 ID 시그니처
- Produces: `RecordCardFailure failureOf(DioException error)` · `class HttpRecordCardRepository implements RecordCardRepository`

본보기는 `lib/features/record/data/http_run_record_repository.dart`다 — **401이면 `TokenRefresher`로 한 번만 갱신하고 다시 부른다**, `_failureOf`로 상태를 옮긴다, 구간 상한은 서버에 묻기 전에 선검사한다. 그 셋을 그대로 따른다.

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `failureOf`가 `400`→`invalidRequest`, `401`→`sessionExpired`, `403`→`forbidden`, `404`→`notFound`, `5xx`→`server`, `DioExceptionType.connectionTimeout`→`network`로 옮기는지. 그리고 `'⚠️ 401이면 한 번만 갱신하고 다시 부른다'` — 두 번 갱신하지 않는다.
- [ ] **Step 2: 실패를 본다** — `.fvm\flutter_sdk\bin\flutter.bat test test/http_record_card_repository_test.dart`. 기대: FAIL(파일이 없다).
- [ ] **Step 3: 두 파일을 만든다.** 쓰기 두 개(`create`·`update`)는 생성자가 받은 `FakeRecordCardRepository`에 **그대로 넘긴다** — 주석에 "묶음 8에서 이 두 줄이 실제 구현으로 바뀐다"를 박는다. 읽기는 `UnimplementedError`로 둔다(Task 3~6이 채운다).
- [ ] **Step 4: 통과를 본다** — 같은 명령. 기대: PASS.
- [ ] **Step 5: 커밋** — `📍 Feat: 카드 API 오류를 code로 읽는다`

---

### Task 3: 달력이 러닝 기록 목록 하나만 읽는다

지금 달마다 **요청이 둘**이다(카드 + 러닝 기록). 7-1이 둘을 함께 주므로 **하나로 줄어든다.**

**Files:**
- Create: `lib/features/record_card/domain/record_card_summary.dart`
- Create: `lib/features/record_card/data/recorded_run_dto.dart`
- Modify: `lib/features/record_card/domain/composable_record.dart` (`joinCards` **삭제**, `existingCard` 타입 교체)
- Modify: `lib/features/record_card/domain/record_card_repository.dart` (`byDateRange` → `runsInRange`)
- Modify: `lib/features/record_card/data/http_record_card_repository.dart`, `fake_record_card_repository.dart`
- Modify: `lib/features/record_card/presentation/record_card_state.dart` (`MonthCards`), `record_card_provider.dart` (`_fetch`에서 `Future.wait`·`_recordDaysOf` 제거), `record_card_cell.dart`, `day_cards_sheet.dart`, `compose_records_provider.dart`
- Test: `test/recorded_run_dto_test.dart`(새 파일), `test/record_card_calendar_test.dart`, `test/record_card_provider_test.dart`

**Interfaces:**
- Produces:
  - `class RecordCardSummary { final String id; final String? thumbnailUrl; final RouteArt route; final RecordCardActivity? activity; }`
  - `ComposableRecord { final RunRecord record; final RecordCardSummary? existingCard; }` — **이름과 모양은 그대로다.** 타입만 바뀐다
  - `Future<List<ComposableRecord>> RecordCardRepository.runsInRange({required DateTime from, required DateTime to})` — 7-1 순서(`startedAt` 오름차순) 그대로
  - `RecordedRunDto.listFrom(Map<String, dynamic> json) -> List<ComposableRecord>`

**Ruling — `record_card/data`가 7-1 응답을 자기 식으로 읽는다.** `RunRecordDto`를 재사용하면 `record_card/data → record/data`가 되고, 기록 탭 DTO에 카드 필드를 더하면 **기록 탭이 카드를 알게 된다**(방향이 거꾸로다). 필드 이름이 같은 파서가 두 벌이 되는 값을 치르고 의존을 끊는다. 비용: 7-1 응답이 바뀌면 두 곳을 고친다.

- [ ] **Step 1: DTO 테스트를 쓴다** — `test/recorded_run_dto_test.dart`:
  - `'⚠️ recordCard가 null인 행은 카드가 없다'`
  - `'⚠️ 사진을 다 지운 카드는 thumbnailUrl이 null이고 경로만 남는다'` (Review Focus 1)
  - `'⚠️ routeArt가 빈 배열이면 RouteArt.empty다'`
  - `'⚠️ 모르는 activityType은 null이다'`
  - `'⚠️ y를 뒤집지 않는다'` — 서버가 이미 화면 방향(아래로 증가)으로 준다
- [ ] **Step 2: 실패를 본다** — `.fvm\flutter_sdk\bin\flutter.bat test test/recorded_run_dto_test.dart`. 기대: FAIL(파일이 없다).
- [ ] **Step 3: `RecordCardSummary`와 `RecordedRunDto`를 만든다.** `RouteArt`는 **`aspect: 1.0`으로 짓는다** — 서버가 비를 주지 않는다. 이유와 백엔드 질문 번호를 주석에 박는다.
- [ ] **Step 4: 통과를 본다.** 기대: PASS.
- [ ] **Step 5: 달력 테스트를 쓴다** — `'⚠️ 필터를 걸면 걸러진 뒤의 마지막 카드를 칸에 그린다'`(Review Focus 2): 같은 날 `DAILY`·`RACE` 두 장을 두고 `RACE` 필터에서 칸이 `RACE` 카드의 썸네일을 그리는지, 배지가 보이지 않는지(한 장이다).
- [ ] **Step 6: 실패를 본다.** 기대: FAIL.
- [ ] **Step 7: `runsInRange`로 갈아타고 `joinCards`를 지운다.** `MonthCards`는 `List<ComposableRecord>`를 받아 생성자에서 `byDay`(카드 있는 것만)와 `recordDays`(전부)를 만든다. `_fetch`의 `Future.wait`와 `_recordDaysOf`는 **삭제한다** — 요청이 하나다.
- [ ] **Step 8: 통과를 본다.** 기대: PASS.
- [ ] **Step 9: 전체 테스트 + analyze 0을 확인하고 커밋** — `📍 Feat: 달력이 러닝 기록 목록 하나로 카드까지 받는다`

---

### Task 4: 상세를 카드 번호로 읽는다

**Files:**
- Modify: `lib/features/record_card/domain/record_card.dart` (`isMine`·`author` 추가, `RecordCardPhoto.isThumbnail`)
- Modify: `lib/features/record_card/domain/record_card_repository.dart` (`detailOf` 추가)
- Create: `lib/features/record_card/data/record_card_detail_dto.dart`
- Create: `lib/features/record_card/presentation/card_detail_provider.dart`
- Modify: `lib/app/router/app_routes.dart`·`app_router.dart` (**`extra`와 `mine` 쿼리 제거**)
- Modify: `card_detail_page.dart`, `day_cards_sheet.dart`, `card_compose_page.dart`, `profile_cards_page.dart`, `profile_card_grid.dart`
- Modify: `fake_record_card_repository.dart`, `http_record_card_repository.dart`
- Test: `test/record_card_detail_dto_test.dart`, `test/record_card_detail_page_test.dart`

**Interfaces:**
- Produces:
  - `Future<RecordCard> RecordCardRepository.detailOf(String cardId)`
  - `RecordCard.isMine: bool` · `RecordCard.author: CardRunner` · `RecordCardPhoto.isThumbnail: bool`
  - `final cardDetailProvider = FutureProvider.autoDispose.family<RecordCard, String>(retry: (_, _) => null, ...)` — 본보기는 `profileCardsProvider`
  - `AppRoutes.recordCardDetailOf(String cardId)` — **`mine`이 사라진다**

**Ruling — 묶음 6의 `mine` 쿼리를 지운다.** 소유자를 알 길이 없어 라우트에 실어 보냈던 것인데, 8-1이 `isMine`을 준다. 쿼리를 남기면 **두 출처가 어긋날 수 있다**(남의 카드 링크에 `mine=true`를 붙이면 수정 메뉴가 뜬다) — 서버 값이 정본이다. 비용: 상세를 받기 전에는 `⋮`를 그릴 수 없다. 로딩 중에는 안 그린다.

- [ ] **Step 1: DTO 테스트를 쓴다** — `'⚠️ companions가 비면 솔로다'`, `'⚠️ 경로 조각 사이를 잇지 않는다'`, `'⚠️ 점이 200개를 넘겨 와도 전부 든다'`(Review Focus 3), `'⚠️ isThumbnail이 참인 사진이 대표다'`, `'⚠️ 404는 찾을 수 없거나 볼 수 없다는 한 가지 실패다'`.
- [ ] **Step 2: 실패를 본다.** 기대: FAIL.
- [ ] **Step 3: DTO와 도메인 필드를 만든다.**
- [ ] **Step 4: 통과를 본다.** 기대: PASS.
- [ ] **Step 5: 화면 테스트를 쓴다** — `'⚠️ 남의 카드에는 ⋮가 없다'`(`isMine: false`), `'⚠️ 받아 오는 중에는 ⋮를 그리지 않는다'`, `'⚠️ 404면 카드를 찾을 수 없다고 알린다'`.
- [ ] **Step 6: 실패를 본다.** 기대: FAIL.
- [ ] **Step 7: `cardDetailProvider`로 갈아탄다.** 상세로 보내는 자리 넷(그날 시트·작성 목록·프로필 그리드·전체 보기)이 **번호만 push**한다. `app_router`의 `extra` 분기와 "없으면 탭으로 돌려보낸다"는 **삭제한다**.
- [ ] **Step 8: 통과를 본다.** 기대: PASS.
- [ ] **Step 9: 전체 테스트 + analyze 0을 확인하고 커밋** — `📍 Feat: 상세를 카드 번호로 읽는다`

---

### Task 5: 음악을 곡별로 본다

**Files:**
- Delete: `lib/features/record_card/domain/music_generation.dart`
- Create: `lib/features/record_card/domain/card_music.dart`
- Modify: `lib/features/record_card/domain/record_card.dart` (`baseMusic`, `RecordCardPhoto.music`)
- Modify: `lib/features/record_card/domain/record_card_repository.dart` (`musicOf` **삭제**, `requestMusic` → `retryMusic`)
- Modify: `card_music_provider.dart`, `music_strip.dart`, `card_detail_page.dart`, `card_media_pager.dart`, `record_card_detail_dto.dart`, 두 저장소
- Test: `test/record_card_music_test.dart`

**Interfaces:**
- Produces:
  - `enum MusicStatus { generating, completed, failed }` — **`none`·`queued`·`processing`·`succeeded`는 사라진다**
  - `class CardMusic { final MusicStatus status; final String? url; }` — `isPlayable => status == completed && url != null`
  - `RecordCard.baseMusic: CardMusic?` · `RecordCardPhoto.music: CardMusic?` (`null` = 서버가 안 줬다)
  - `RecordCard.hasFailedMusic: bool` · `RecordCard.isMusicWorking: bool`
  - `Future<void> RecordCardRepository.retryMusic(String cardId)` — `204`면 끝. 실패한 곡이 없어도 `204`다
  - `CardMusicController.pollInterval` → **10초에서 1분까지 늘리는 백오프**

`MusicGeneration.baseDuration`(30초)·`photoDuration`(10초)·`durationOfPage`는 **앱의 재생 시간 설정이라 남긴다** — `card_media_pager.dart`가 쓴다. `card_music.dart`로 옮긴다.

**Ruling — 재생은 여전히 범위 밖이다.** `musicUrl`이 실제로 오지만 오디오 패키지를 넣지 않는다(설계 9절). 새 패키지는 승인 사항이고(CLAUDE.md), 재생은 연동이 아니라 기능이다. 비용: URL을 받아 두고 쓰지 않는다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**
  - `'⚠️ 사진 곡 하나가 실패하면 그 장만 음악 없이 선다'` — 카드 전체가 죽지 않는다
  - `'⚠️ 재요청은 실패한 곡이 있을 때만 보인다'`
  - `'⚠️ 남의 카드에는 재요청이 없다'`
  - `'⚠️ 화면을 떠나면 폴링이 멈춘다'` (Review Focus 4) — `dispose` 뒤 타이머가 없는지
  - `'⚠️ 다시 들어오면 GENERATING이 없어도 한 번 읽는다'` (Review Focus 4) — 기본곡 교체를 놓치지 않는다
  - `'⚠️ 폴링 간격이 10초에서 1분까지 늘어난다'`
- [ ] **Step 2: 실패를 본다** — `.fvm\flutter_sdk\bin\flutter.bat test test/record_card_music_test.dart`. 기대: FAIL.
- [ ] **Step 3: 곡별 모델로 갈아탄다.** 폴링은 `cardDetailProvider`를 `invalidate`하는 것으로 바꾼다 — 상태가 상세 응답에 실려 온다.
- [ ] **Step 4: 통과를 본다.** 기대: PASS.
- [ ] **Step 5: 전체 테스트 + analyze 0을 확인하고 커밋** — `📍 Feat: 음악을 기본곡과 사진별 곡으로 나눠 본다`

---

### Task 6: 프로필이 커서로 이어 받는다

**Files:**
- Create: `lib/features/record_card/domain/record_card_list_item.dart`
- Modify: `record_card_repository.dart` (`byUser` → `cardsOf`), 두 저장소
- Create: `lib/features/record_card/data/record_card_list_dto.dart`
- Modify: `lib/features/profile/presentation/profile_cards_provider.dart`, `profile_card_grid.dart`, `profile_cards_page.dart`, `profile_card_tile.dart`
- Test: `test/record_card_list_dto_test.dart`, `test/profile_cards_page_test.dart`

**Interfaces:**
- Produces:
  - `class RecordCardListItem { final String id; final String? thumbnailUrl; final int imageCount; final DateTime startedAt; final int distanceMeters; }`
  - `class RecordCardPage { final List<RecordCardListItem> items; final String? nextCursor; }`
  - `Future<RecordCardPage> cardsOf({required String userId, int? limit, String? cursor})`

**Ruling — 전체 보기는 커서 없이 처음부터 받는다.** 그리드의 `nextCursor`를 넘기면 전체 보기가 **그리드가 떠 있었는지에 따라 달라진다**(새로 고침 뒤에는 커서가 없다). 가이드가 둘 다 허용한다("전체 보기를 빈 목록으로 시작한다면 첫 요청은 커서 없이"). 비용: 첫 여섯 장을 한 번 더 받는다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**
  - `'⚠️ nextCursor가 있으면 더 보기가 보인다'` — 지금은 7장 받아 `length > 6`으로 때웠다
  - `'⚠️ nextCursor가 null이면 더 보기가 없다'`
  - `'⚠️ 전체 보기가 바닥에 닿으면 커서로 이어 받는다'`
  - `'⚠️ 같은 커서로 두 번 요청하지 않는다'` — 스크롤 매 프레임에 요청이 나가면 안 된다(묶음 1의 `_loadingOlder`와 같은 함정)
  - `'⚠️ 썸네일이 없으면 기본 이미지다'`
  - `'⚠️ 볼 수 있는 카드가 없으면 빈 상태다'` — `items: []`는 오류가 아니다
- [ ] **Step 2: 실패를 본다.** 기대: FAIL.
- [ ] **Step 3: 커서 페이지로 갈아탄다.** 그리드는 `limit: 6`을 묻는다(7장 받던 것을 **되돌린다**).
- [ ] **Step 4: 통과를 본다.** 기대: PASS.
- [ ] **Step 5: 전체 테스트 + analyze 0을 확인하고 커밋** — `📍 Feat: 프로필 카드 목록을 커서로 이어 받는다`

---

### Task 7: 만료된 조회 URL을 다시 받는다

**Files:**
- Modify: `lib/core/widgets/card_face.dart` (`cardThumbnail`), `card_media_pager.dart`, `profile_card_tile.dart`
- Test: `test/record_card_expired_url_test.dart`

**Interfaces:**
- Consumes: Task 4의 `cardDetailProvider`, Task 6의 `profileCardsProvider`

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `'⚠️ 403을 받으면 한 번만 다시 받는다'`(Review Focus 5): 이미지가 두 번 연달아 403일 때 무효화가 **한 번**만 일어나는지.
- [ ] **Step 2: 실패를 본다.** 기대: FAIL.
- [ ] **Step 3: `errorBuilder`에서 한 번만 무효화한다.** 재시도 깃발은 **위젯 상태**에 둔다 — provider에 두면 다음 카드가 그 깃발을 물려받는다.
- [ ] **Step 4: 통과를 본다.** 기대: PASS.
- [ ] **Step 5: 커밋** — `🔨 Fix: 만료된 사진 주소를 한 번 다시 받는다`

---

### Task 8: 러닝 요약이 **뛴 날짜**로 작성 화면을 연다

지금 `run_summary_page.dart:257`이 `DateTime.now()`를 쓴다. **자정을 넘긴 러닝에서 방금 뛴 기록을 못 찾는다** — 가이드 6절이 바로 그 예(11월 22일 밤 출발 → 23일 종료)를 든다.

**Files:**
- Modify: `lib/features/record/domain/run_detail.dart` (`startedAt` 추가), `lib/features/record/data/room_result_dto.dart`
- Modify: `lib/features/session/presentation/run_summary_page.dart`
- Test: `test/room_result_dto_test.dart`, `test/run_flow_test.dart`

**Interfaces:**
- Produces: `RunDetail.startedAt: DateTime?` — 6-1이 주지 않으면 `null`

- [ ] **Step 1: 실패하는 테스트를 쓴다**
  - `'⚠️ 자정을 넘긴 러닝은 시작한 날짜로 작성 화면을 연다'` — 23일 00:20에 끝난 22일 23:50 러닝에서 작성 화면의 날짜가 **22일**인지
  - `'⚠️ startedAt이 없으면 기록카드 버튼을 숨긴다'`
- [ ] **Step 2: 실패를 본다** — `.fvm\flutter_sdk\bin\flutter.bat test test/run_flow_test.dart`. 기대: FAIL(지금은 오늘 날짜로 연다).
- [ ] **Step 3: `RunDetail.startedAt`을 읽고 그 날짜를 쓴다.**
- [ ] **Step 4: 통과를 본다.** 기대: PASS.
- [ ] **Step 5: 커밋** — `🔨 Fix: 자정을 넘긴 러닝도 시작한 날짜로 기록카드를 쓴다`

---

### Task 9: 삭제 404를 성공으로 다루고, `INVITE`를 읽는다

**Files:**
- Modify: `lib/features/record_card/presentation/card_delete_provider.dart`
- Modify: `lib/features/record/domain/run_record.dart` (`RunKind.invite`), `lib/features/record/data/run_record_dto.dart`
- Test: `test/record_card_delete_test.dart`, `test/run_record_test.dart`

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `'⚠️ 이미 지워진 카드를 또 지우면 삭제 흐름을 마친다'`(404에 `true`를 돌려주고 달력·프로필을 무효화한다), `'⚠️ type이 INVITE면 초대 러닝이다'`.
- [ ] **Step 2: 실패를 본다.** 기대: FAIL.
- [ ] **Step 3: 두 곳을 고친다.**
- [ ] **Step 4: 통과를 본다.** 기대: PASS.
- [ ] **Step 5: 커밋** — `🔨 Fix: 이미 지워진 카드도 삭제 흐름을 마친다`

---

### Task 10: 실제 서버에 꽂고 기기에서 본다

**Files:**
- Modify: `lib/features/record_card/presentation/record_card_provider.dart` (`recordCardRepositoryProvider`)

- [ ] **Step 1: provider를 `HttpRecordCardRepository`로 바꾼다.** 쓰기 두 개가 아직 Fake로 간다는 것을 주석에 박는다 — **저장은 서버에 가지 않는다.**
- [ ] **Step 2: 전체 테스트** — `.fvm\flutter_sdk\bin\flutter.bat test`. 기대: 전부 PASS.
- [ ] **Step 3: analyze** — `.fvm\flutter_sdk\bin\flutter.bat analyze`. 기대: 경고 0.
- [ ] **Step 4: 에뮬레이터에서 확인한다.** SSH 터널을 띄우고 `svc wifi disable`로 eth0을 강제한 뒤:
  1. 기록카드 탭 — 뛴 날에 👟, 카드 있는 날에 썸네일, 두 장 이상인 날에 배지
  2. 유형 필터 세 개 · 분기 보기
  3. 카드를 눌러 상세 — 경로·지표·파티원·음악 상태
  4. 남의 공개 카드에 `⋮`가 없는 것
  5. 프로필 그리드 여섯 장 + 더 보기 + 전체 보기 이어 받기
  6. 러닝을 끝내고 `기록카드 남기기` → 그 러닝이 미리 골라진 작성 화면
- [ ] **Step 5: 커밋** — `📍 Feat: 기록카드 읽기를 실제 서버에 붙인다`

---

## PR 경계

한 PR에 파일 20개·500줄을 넘기지 않는다는 규칙을 지키려면 **셋으로 나눈다.**

| PR | 작업 | 내용 |
|---|---|---|
| 1 | Task 1~2 | 카드 번호 문자열화 + 오류 매퍼 + Http 골격 |
| 2 | Task 3~5 | 달력 7-1 · 상세 8-1 · 음악 곡별 |
| 3 | Task 6~10 | 프로필 커서 · 만료 URL · 요약 날짜 · 삭제 404 · 실제 연결 |

묶음 1~6의 PR은 이 셋보다 **앞에 선다** — base `dev`에서 차례로 쌓는다.

## Self-review

**가이드 절별 덮임**: 1절 달력 → Task 3 · 2절 상세·포토북 → Task 4 · 3절 작성 → **묶음 8** · 4절 수정 → **묶음 8** · 4절 삭제 → Task 9 · 4절 음악 재요청 → Task 5 · 5절 프로필 → Task 6 · 6절 러닝 요약 → Task 8 · 7절 오류 복구 → Task 2(읽기 코드만), 쓰기 코드 5개는 묶음 8 · 7절 URL 만료 → Task 7 · 7절 음악 완료 확인 → Task 5.

**빠뜨린 것 하나**: 회고 길이를 입력 포매터가 grapheme으로 세는데 서버는 UTF-16(`String.length`)이다. 이모지가 많으면 **포매터는 통과하고 서버가 400**이다. 저장할 때 걸리는 값이라 **묶음 8로 미룬다** — 읽기에서는 드러나지 않는다.

**타입 일관성**: `RecordCardSummary`(달력)·`RecordCard`(상세)·`RecordCardListItem`(프로필) 셋이 서로 다른 타입인 것은 **서버가 세 자리에 다른 필드를 주기 때문**이다. 하나로 합치면 달력이 모르는 값을 지어 넣어야 한다. `RecordCardPage`는 Task 6에서만 쓰인다.

**비례**: 작업 10개, 각 단계는 테스트 이름과 명령까지만 적었다. 본문 코드를 넣은 자리는 없다 — 시그니처와 테스트 이름이 정한다.
