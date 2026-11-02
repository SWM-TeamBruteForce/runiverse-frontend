# 초대 러닝과 인앱 알림 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 러너를 직접 초대해 함께 뛰는 초대 방과, 그 초대를 받을 유일한 통로인 앱 전역 인앱 알림을 만든다.

**Architecture:** 초대 방은 매칭 방과 같은 `RoomInfo`를 받으므로 기존 매칭 화면 안에서 `RoomInfo.type`으로 분기한다. 등록 화면만 입력(자유 시각·거리)이 달라 별도 페이지다. 알림은 `notification` 새 feature로, 기존 손수 짠 SSE(`SseMatchStream`)와 같은 방식으로 앱 스트림을 열고 목록 API와 버퍼·병합 규칙으로 배지를 맞춘다.

**Tech Stack:** Flutter (fvm) · Riverpod 3 `Notifier`/`NotifierProvider` · dio · go_router · `dart:io` `HttpClient` SSE · Lucide 아이콘(`AppIcons`)

**Spec:** `docs/specs/2026-10-29-invite-run-design.md`

## Global Constraints

- 모든 flutter/dart 명령 앞에 `fvm`. 테스트는 `fvm flutter test --dart-define-from-file=config/dev.json`
- Riverpod 3 — `StateProvider` / `StateNotifierProvider` 금지. `Notifier` / `NotifierProvider`만
- 아이콘은 `AppIcons` 상수만. `Icons.*`(Material) 혼용 금지
- 색·치수·타이포·문자열은 전부 토큰 — `context.appColorsV2` `AppSpacing` `AppRadius` `AppTypography` `AppStrings`
- `core/theme/tokens/` 밖에서 `Color(0x...)` 하드코딩 금지
- UI 텍스트는 한국어. **화면에서 "친구"라고 쓴다**(설계 §2-1 — `CLAUDE.md`의 금지 줄은 개발자가 걷어낸다)
- 의존 방향 `presentation → domain ← data`. presentation은 data를 import하지 않는다. domain은 순수 Dart만
- 서버 시각은 오프셋이 없다 — `DateTime.parse` 금지, `KstTime.parse` / `KstTime.wallOf`만
- 시작 시각 범위 `지금 +10분 ~ 오늘 23:59` KST 분 단위, 피커 바닥은 **`지금 +11분`**(1분 여유)
- 목표 거리 `1,000 ~ 42,195m` · 정원 `4명` · 모집 마감 `시작 1분 전` · 초대 횟수 `5회`
- 초대 방은 **나가기 제재가 없다** — `cooldownUntil`이 생기지 않는다
- `notificationId`와 `runningRoomId`는 `Long`이다 — **숫자로 비교한다**
- 커밋은 `<이모지> <Type>: <한국어 설명>`. AI 공동 작성자·푸터 금지
- 한 PR에 파일 20개 / 500줄 상한 — 묶음 경계는 §작업 묶음을 따른다
- 코드 작성 후 `fvm flutter analyze` 경고 0개
- `dev`에 34개의 선행 테스트 실패가 있다. 묶음을 시작할 때 기준선을 먼저 잡고, 새 실패와 섞지 않는다

## Review Focus

1. **앱 스트림이 `403 APP_UPDATE_REQUIRED`를 주는데 버전은 읽혀 있을 때** — 진짜 구버전이다. 업데이트 화면으로 가야 한다. Task 5의 우회가 넓으면 구버전 앱이 알림만 못 받고 계속 돌아간다
2. **`RUNNING_INVITED`에 `invitation`이 없을 때** — 명세는 "없다"고 하지만 오면 줄을 그릴 수 없다. 그 알림만 버리고 나머지 목록은 살아야 한다
3. **모집 마감으로 `invitations: []`가 온 뒤** — "초대 중" 슬롯을 지우지 않으면 유령 참가자가 남는다
4. **같은 `runningRoomId` 알림이 여러 페이지에 흩어져 있을 때** — 받아 둔 모든 페이지를 갱신해야 한다. 첫 페이지만 고치면 스크롤하면 낡은 버튼이 나온다
5. **초대 방에서 `MATCH_STARTED`가 올 때** — 서버가 보내지 않기로 했지만 오면 무시해야 한다. 초대 방에 매칭 확정 연출이 터지면 안 된다

---

## 파일 구조

### 새로 만드는 것

| 파일 | 책임 |
|---|---|
| `lib/features/notification/domain/app_notification.dart` | 알림 한 건 · `NotificationType` · `NotificationActor` · `NotificationInvitation` · `InvitationStatus` |
| `lib/features/notification/domain/notification_page_result.dart` | 목록 한 페이지 — `items` · `nextCursor` · `unreadCount` |
| `lib/features/notification/domain/notification_repository.dart` | 목록 조회 · 모두 읽음 인터페이스 |
| `lib/features/notification/domain/app_stream.dart` | 앱 스트림 인터페이스 · `AppStreamFailure` |
| `lib/features/notification/data/notification_dto.dart` | 응답·이벤트 `data`를 읽는 유일한 곳 |
| `lib/features/notification/data/http_notification_repository.dart` | 목록·모두 읽음 REST |
| `lib/features/notification/data/sse_app_stream.dart` | `GET /app/stream` |
| `lib/features/notification/data/fake_app_stream.dart` | 테스트·개발용 |
| `lib/features/notification/presentation/notification_provider.dart` | 버퍼·병합·배지 |
| `lib/features/notification/presentation/notification_page.dart` | 알림함 |
| `lib/features/notification/presentation/notification_row.dart` | 알림 한 줄 |
| `lib/features/matching/domain/room_invitation.dart` | 방 안의 `PENDING` 초대 하나 |
| `lib/features/matching/domain/invite_limits.dart` | 운영값 다섯 개 · 시작 시각 범위 계산 |
| `lib/features/matching/domain/invite_failure.dart` | `InviteFailure` · `InviteException(message)` |
| `lib/features/matching/presentation/invite_register_page.dart` | 초대 등록 |
| `lib/features/matching/presentation/invite_register_provider.dart` | 등록 상태 |
| `lib/features/matching/presentation/invite_friend_sheet.dart` | 친구 초대 모달 |

### 손보는 것

| 파일 | 무엇 |
|---|---|
| `session/domain/user_status.dart` | `isSolo` → `RoomType`, `canStartSolo` |
| `session/data/http_user_status_repository.dart:56` | 낡은 주석과 3-way 읽기 |
| `matching/domain/room_info.dart` | `type` · `invitations` · `fromStatus` · `closeAt` 주석 |
| `matching/domain/match_event.dart` | `InviteRoomEntrance` · `InviteRoomUpdated` |
| `matching/data/sse_match_stream.dart` | 두 이벤트 파싱, `roomOf`에 `type`·`invitations` |
| `matching/domain/match_repository.dart` · `data/http_match_repository.dart` · `data/fake_match_repository.dart` | 초대 REST 4개 |
| `matching/presentation/match_room_page.dart` · `match_room_provider.dart` | `type` 분기 |
| `profile/data/http_profile_repository.dart:334` | `friendStatus` → `relationshipType` |
| `profile/presentation/profile_page.dart` | 벨 |
| `core/widgets/v2/app_tab_bar.dart` | `badges` · Semantics 라벨 |
| `app/router/app_shell.dart` | 앱 스트림 구독 · 탭 점 |
| `app/router/app_routes.dart` · `app_router.dart` | 알림함 · 초대 등록 |
| `home/presentation/home_hero.dart` · `home_waiting.dart` · `home_confirmed.dart` · `home_page.dart` | 초대 문구 · 초대 칸 연결 |
| `core/strings/app_strings.dart` | 문구 |

---

## Task 1: `RoomType` — 유저 상태가 초대를 읽는다

지금 초대 방이 매칭 방으로 읽혀 **매칭 방 화면이 뜬다.** 가장 먼저 고친다.

**Files:**
- Modify: `lib/features/session/domain/user_status.dart`
- Modify: `lib/features/session/data/http_user_status_repository.dart:50-70`
- Modify: `lib/features/matching/domain/room_info.dart:111-127` (`fromStatus`)
- Test: `test/user_status_test.dart` (있으면 추가, 없으면 생성) · `test/http_user_status_repository_test.dart`

**Interfaces:**
- Produces:
  ```dart
  enum RoomType { match, invite, solo;
    static RoomType? of(Object? wire);   // 'MATCH'|'INVITE'|'SOLO', 그 밖엔 null
  }
  // UserStatusWaiting/Ready/Running의 `bool isSolo`가 `RoomType type`으로 바뀐다
  // UserStatus.canStartSolo: RoomType.solo 일 때만 true
  ```

- [ ] **Step 1: `RoomType`의 실패 테스트를 쓴다**

```dart
test('모르는 방 유형은 null이다', () {
  expect(RoomType.of('MATCH'), RoomType.match);
  expect(RoomType.of('INVITE'), RoomType.invite);
  expect(RoomType.of('SOLO'), RoomType.solo);
  expect(RoomType.of('PARTY'), isNull);
  expect(RoomType.of(null), isNull);
});
```

- [ ] **Step 2: 돌려서 실패를 본다**

Run: `fvm flutter test test/user_status_test.dart --dart-define-from-file=config/dev.json`
Expected: FAIL — `RoomType` 미정의

- [ ] **Step 3: `user_status.dart`에 `enum RoomType { match, invite, solo }`와 `static RoomType? of(Object? wire)`를 만든다**

`RoomStatus.of`와 같은 판단이다 — 모르는 값을 아무 값으로도 뭉개지 않는다. 그 이유를 주석으로 남긴다: 뭉개면 초대 방을 매칭 방으로 그린다.

- [ ] **Step 4: 통과를 본다**

Run: 위와 같음
Expected: PASS

- [ ] **Step 5: 3-way 전이 테스트를 쓴다**

```dart
test('확정된 초대 방은 솔로 시작을 허락하지 않는다', () {
  final status = UserStatusReady(
    runningRoomId: 7,
    type: RoomType.invite,
    scheduledStartAt: DateTime(2026, 10, 29, 19, 30),
    targetDistanceMeters: 5000,
  );
  expect(status.canStartSolo, isFalse);
});

test('확정된 솔로 방만 솔로 시작을 허락한다', () {
  // 위와 같은 생성, type: RoomType.solo
  expect(status.canStartSolo, isTrue);
});
```

- [ ] **Step 6: 돌려서 실패를 본다**

Expected: FAIL — `type` 이름 인자 없음(아직 `isSolo`다)

- [ ] **Step 7: `UserStatusWaiting`·`UserStatusReady`·`UserStatusRunning`의 `bool isSolo`를 `RoomType type`으로 바꾸고 `canStartSolo`를 `RoomType.solo`만 `true`로 만든다**

`canStartSolo`는 `user_status.dart:45-50`의 `switch`다. `UserStatusReady(:final type) => type == RoomType.solo`로 바꾼다.

- [ ] **Step 8: 통과를 본다. 깨진 호출부를 `analyze`로 찾는다**

Run: `fvm flutter analyze`
Expected: `isSolo`를 쓰던 자리가 오류로 나열된다 — 전부 `type`으로 옮긴다

- [ ] **Step 9: 응답 읽기 테스트를 쓴다**

```dart
test('type INVITE를 초대 방으로 읽는다', () {
  final status = userStatusFromJson({
    'status': 'WAITING', 'type': 'INVITE', 'runningRoomId': 31,
    'scheduledStartAt': '2026-10-29T19:30:00', 'targetDistanceMeters': 7000,
  });
  expect(status, isA<UserStatusWaiting>());
  expect((status as UserStatusWaiting).type, RoomType.invite);
});
```

- [ ] **Step 10: 돌려서 실패를 본다**

Expected: FAIL — `type`이 `RoomType.match`로 읽힌다

- [ ] **Step 11: `http_user_status_repository.dart:56`의 `final isSolo = body?['type'] == 'SOLO';`를 `RoomType.of(body?['type'])`로 바꾼다**

같은 자리의 주석 `⚠️ INVITE는 미래 예약값이라 계약에 없다. 그래서 SOLO만 보고 가른다.`를 지우고, `INVITE`가 계약에 들어왔다는 사실과 모르는 값이 `null`일 때의 대타(`RoomType.match`로 접지 않고 상태 자체를 버린다)를 적는다.

- [ ] **Step 12: 통과를 본다**

Expected: PASS

- [ ] **Step 13: `fromStatus` 테스트를 쓴다**

```dart
test('초대 방도 스냅샷 없이 세운다', () {
  final room = RoomInfo.fromStatus(UserStatusReady(
    runningRoomId: 31, type: RoomType.invite,
    scheduledStartAt: DateTime(2026, 10, 29, 19, 30),
    targetDistanceMeters: 7000,
  ));
  expect(room, isNotNull);
  expect(room!.type, RoomType.invite);
  expect(room.status, RoomStatus.matched);
});
```

- [ ] **Step 14: 돌려서 실패를 본다**

Expected: FAIL — `fromStatus`가 `null`을 준다

- [ ] **Step 15: `RoomInfo.fromStatus`가 `match`와 `invite` 둘 다 세우게 한다**

`RoomType.solo`만 `null`이다. **빠뜨리면 홈이 `HomeIdle`을 그려 초대 방에 있는 사람에게 "매칭 시작" 버튼을 보여준다** — 그 이유를 주석에 남긴다.

- [ ] **Step 16: 통과를 본다. 전체 스위트를 돌려 기준선과 비교한다**

Run: `fvm flutter test --dart-define-from-file=config/dev.json`
Expected: 선행 34개 외에 새 실패 0개

- [ ] **Step 17: 커밋**

```bash
git add lib/features/session lib/features/matching/domain/room_info.dart test/
git commit -m "🔨 Fix: 유저 상태가 초대 방을 매칭 방으로 읽던 것을 고친다"
```

---

## Task 2: 초대 방 계약과 이벤트

**Files:**
- Create: `lib/features/matching/domain/room_invitation.dart`
- Modify: `lib/features/matching/domain/room_info.dart`
- Modify: `lib/features/matching/domain/match_event.dart`
- Modify: `lib/features/matching/data/sse_match_stream.dart` (`roomOf`, `eventOf`)
- Test: `test/sse_match_stream_test.dart` · `test/room_info_test.dart`

**Interfaces:**
- Consumes: Task 1의 `RoomType`
- Produces:
  ```dart
  class RoomInvitation {            // 방 안의 PENDING 초대 하나
    const RoomInvitation({required this.userId, required this.nickname,
      required this.isDeleted, this.profileImageUrl});
  }
  // RoomInfo에 추가: final RoomType? type; final List<RoomInvitation> invitations;
  class InviteRoomEntrance extends MatchEvent { final RoomInfo room; final int? startsInMs; }
  class InviteRoomUpdated  extends MatchEvent { final RoomInfo room; }
  ```

`invitations`의 `status`와 `isDeleted`는 서버가 항상 `PENDING`·`false`로 보내므로 들고 있지 않는다.

- [ ] **Step 1: `roomOf`가 `type`·`invitations`를 읽는 테스트를 쓴다**

```dart
test('초대 방 스냅샷에서 초대 현황을 읽는다', () {
  final room = SseMatchStream.roomOf({
    'runningRoomId': 130, 'type': 'INVITE', 'status': 'MATCHING',
    'scheduledStartAt': '2026-10-28T19:30:00',
    'closeAt': '2026-10-28T19:29:00', 'targetDistanceMeters': 7000,
    'players': [], 'invitations': [
      {'userId': 'u1', 'nickname': '철수', 'profileImageUrl': null,
       'status': 'PENDING', 'isDeleted': false},
    ],
  });
  expect(room!.type, RoomType.invite);
  expect(room.invitations.single.nickname, '철수');
});

test('invitations가 없으면 빈 목록이다', () {
  // 'type': 'MATCH', invitations 키 없음
  expect(room!.invitations, isEmpty);
});
```

- [ ] **Step 2: 돌려서 실패를 본다**

Run: `fvm flutter test test/sse_match_stream_test.dart --dart-define-from-file=config/dev.json`
Expected: FAIL — `RoomInfo.invitations` 미정의

- [ ] **Step 3: `RoomInvitation`을 만들고 `RoomInfo`에 `type`·`invitations`를 더한 뒤 `roomOf`가 읽게 한다**

`invitations`는 비널 `List`로, 키가 없거나 `List`가 아니면 `const []`다. 못 읽는 원소만 건너뛴다 — `slot_board_dto.dart`와 같은 판단이다.

- [ ] **Step 4: 통과를 본다**

Expected: PASS

- [ ] **Step 5: `closeAt` 주석을 고친다**

`room_info.dart:86`의 `운영 오프셋(현재 10분)`이 초대 방(1분)과 어긋난다. 방 종류마다 다르다고 적는다.

- [ ] **Step 6: 두 이벤트 파싱 테스트를 쓴다**

```dart
test('INVITE_ROOM_ENTRANCE는 startsInMs를 방과 같은 깊이에서 읽는다', () {
  final event = SseMatchStream.eventOf('INVITE_ROOM_ENTRANCE',
    '{"runningRoomId":130,"type":"INVITE","status":"MATCHING",'
    '"scheduledStartAt":"2026-10-28T19:30:00","targetDistanceMeters":7000,'
    '"players":[],"invitations":[],"startsInMs":600000}');
  expect(event, isA<InviteRoomEntrance>());
  expect((event as InviteRoomEntrance).startsInMs, 600000);
  expect(event.room.type, RoomType.invite);
});

test('INVITE_ROOM_UPDATED는 startsInMs가 없다', () {
  expect(event, isA<InviteRoomUpdated>());
});

test('모집 마감은 status MATCHED와 빈 invitations로 온다', () {
  // status: 'MATCHED', invitations: []
  expect((event as InviteRoomUpdated).room.status, RoomStatus.matched);
  expect(event.room.invitations, isEmpty);
});
```

- [ ] **Step 7: 돌려서 실패를 본다**

Expected: FAIL — `eventOf`가 `null`을 준다(모르는 이벤트)

- [ ] **Step 8: `MatchEvent`에 `InviteRoomEntrance`·`InviteRoomUpdated`를 더하고 `eventOf`에 두 `case`를 더한다**

`eventOf`의 `switch`(`sse_match_stream.dart:317-330`)에 `roomOf`를 쓰는 두 분기를 더한다. `startsInMs`는 `int`가 아니면 `null`이다 — 남은 시간 표시용이고, 없으면 `scheduledStartAt`으로 그린다.

- [ ] **Step 9: 통과를 본다**

Expected: PASS

- [ ] **Step 10: Review Focus 5 — 초대 방에서 `MATCH_STARTED`를 무시하는 테스트를 쓴다**

```dart
test('초대 방의 MATCH_STARTED는 확정 연출을 터뜨리지 않는다', () {
  // MatchRoomController에 type: INVITE 방을 세운 뒤 MatchStarted를 넣는다
  // 기대: 상태의 '확정됨' 플래그가 켜지지 않는다
});
```

`match_room_provider.dart`가 `MatchStarted`로 무엇을 켜는지 보고, 초대 방에서는 그것이 꺼진 채 남는지 확인한다.

- [ ] **Step 11: 실패를 보고, `match_room_provider`가 `room.type == RoomType.invite`면 `MatchStarted`를 버리게 한다**

- [ ] **Step 12: 통과를 보고 커밋**

```bash
git add lib/features/matching test/
git commit -m "📍 Feat: 초대 방 계약과 SSE 이벤트 2종을 읽는다"
```

---

## Task 3: 프로필 관계 필드 개명

**Files:**
- Modify: `lib/features/profile/data/http_profile_repository.dart:330-335`
- Modify: `lib/features/profile/domain/profile_summary.dart:49` (주석)
- Test: `test/http_profile_repository_test.dart`

**Interfaces:**
- Produces: 없다. 읽는 키만 바뀐다

- [ ] **Step 1: 실패 테스트를 쓴다**

```dart
test('프로필 요약은 relationshipType으로 관계를 읽는다', () {
  final summary = profileSummaryFromJson({
    'userId': 'u1', 'nickname': '철수', 'friendCount': 3,
    'relationshipType': 'FRIEND_REQUEST_RECEIVED',
  });
  expect(summary.relation, FriendRelation.requestReceived);
});
```

- [ ] **Step 2: 돌려서 실패를 본다**

Expected: FAIL — `relation`이 `null`(아직 `friendStatus`를 읽는다)

- [ ] **Step 3: `body?['friendStatus']`를 `body?['relationshipType']`로 바꾼다**

`friend_relation.dart:46`이 `'FRIEND' || 'ACCEPTED'`를 둘 다 받으므로 **값 매핑은 손대지 않는다.** 이중 어휘는 그대로 둔다 — 구버전 서버와 섞이는 기간을 버틴다.

- [ ] **Step 4: 통과를 보고, `profile_summary.dart:49`의 "서버가 이 값을 `friendStatus`로 부르고 값도 다르다" 주석을 고친다**

1.2.0에서 어휘가 하나로 합쳐졌다고 적는다.

- [ ] **Step 5: 커밋**

```bash
git add lib/features/profile test/
git commit -m "🔨 Fix: 프로필 요약의 관계 필드를 relationshipType으로 읽는다"
```

---

## Task 4: 알림 도메인과 파싱

**Files:**
- Create: `lib/features/notification/domain/app_notification.dart`
- Create: `lib/features/notification/domain/notification_page_result.dart`
- Create: `lib/features/notification/data/notification_dto.dart`
- Test: `test/notification_dto_test.dart`

**Interfaces:**
- Produces:
  ```dart
  enum NotificationType { friendRequested, friendAccepted, runningInvited;
    static NotificationType? of(Object? wire); }
  enum InvitationStatus { pending, accepted, declined, left, expired;
    static InvitationStatus? of(Object? wire); }

  class NotificationActor {
    const NotificationActor({required this.userId, required this.nickname,
      required this.isDeleted, this.profileImageUrl, this.relation});
    final FriendRelation? relation;   // 탈퇴면 null — 친구 버튼을 전부 숨긴다
  }

  class NotificationInvitation {
    const NotificationInvitation({required this.runningRoomId,
      required this.status, required this.scheduledStartAt,
      required this.targetDistanceMeters});
    final int runningRoomId;          // Long — 숫자다
    final InvitationStatus status;
  }

  class AppNotification {
    const AppNotification({required this.notificationId, required this.type,
      required this.isRead, required this.createdAt, required this.actor,
      this.invitation});
    final int notificationId;         // Long — 숫자다
    final NotificationInvitation? invitation;  // runningInvited에만 있다
  }

  class NotificationPageResult {
    const NotificationPageResult({required this.items, required this.unreadCount,
      this.nextCursor});
    final String? nextCursor;         // null이면 마지막 페이지다
  }

  // 목록 응답 한 페이지
  NotificationPageResult notificationPageFromJson(Object? body);
  // 이벤트 data — type을 이름에서 받는다
  AppNotification? notificationFromEvent(String eventName, Object? data);
  ```

- [ ] **Step 1: 실패 테스트를 쓴다 — 이벤트 `data`가 목록 항목과 같은 모양이다**

```dart
test('RUNNING_INVITED data에 이벤트 이름을 붙이면 알림이 된다', () {
  final notification = notificationFromEvent('RUNNING_INVITED', {
    'notificationId': 913, 'isRead': false,
    'createdAt': '2026-10-28T12:10:00',
    'actor': {'userId': 'u1', 'nickname': '철수',
      'profileImageUrl': 'https://x', 'isDeleted': false,
      'relationshipType': 'FRIEND'},
    'invitation': {'runningRoomId': 130, 'status': 'PENDING',
      'scheduledStartAt': '2026-10-28T19:30:00',
      'targetDistanceMeters': 7000},
  });
  expect(notification!.notificationId, 913);
  expect(notification.type, NotificationType.runningInvited);
  expect(notification.invitation!.runningRoomId, 130);
  expect(notification.invitation!.status, InvitationStatus.pending);
});

test('친구 알림은 invitation이 null이다', () {
  final notification = notificationFromEvent('FRIEND_REQUESTED', {
    'notificationId': 912, 'isRead': false,
    'createdAt': '2026-10-28T12:10:00',
    'actor': {'userId': 'u1', 'nickname': '영희', 'isDeleted': false,
      'relationshipType': 'FRIEND_REQUEST_RECEIVED'},
    'invitation': null,
  });
  expect(notification!.invitation, isNull);
  expect(notification.actor.relation, FriendRelation.requestReceived);
});

test('탈퇴한 actor의 관계는 null이다', () {
  // nickname: '탈퇴한 사용자', isDeleted: true, relationshipType: null
  expect(notification!.actor.relation, isNull);
});

test('모르는 이벤트 이름은 null이다', () {
  expect(notificationFromEvent('SOMETHING_NEW', {...}), isNull);
});
```

- [ ] **Step 2: Review Focus 2 — `invitation` 없는 `RUNNING_INVITED` 테스트를 쓴다**

```dart
test('invitation 없는 RUNNING_INVITED는 버린다', () {
  final notification = notificationFromEvent('RUNNING_INVITED', {
    'notificationId': 914, 'isRead': false,
    'createdAt': '2026-10-28T12:10:00',
    'actor': {'userId': 'u1', 'nickname': '철수', 'isDeleted': false,
      'relationshipType': 'FRIEND'},
  });
  expect(notification, isNull);   // 줄을 그릴 수 없다
});
```

- [ ] **Step 3: 목록 페이지 테스트를 쓴다**

```dart
test('items가 비어도 nextCursor가 있으면 마지막 페이지가 아니다', () {
  final page = notificationPageFromJson(
    {'items': [], 'nextCursor': 'c2', 'unreadCount': 7});
  expect(page.items, isEmpty);
  expect(page.nextCursor, 'c2');
  expect(page.unreadCount, 7);
});

test('깨진 항목만 건너뛰고 나머지를 준다', () {
  // items: [정상, {notificationId: 'not-a-number', ...}, 정상]
  expect(page.items, hasLength(2));
});

test('notificationId는 숫자다', () {
  // items: [{'notificationId': '913', ...}]  — 문자열
  expect(page.items, isEmpty);   // 숫자가 아니면 버린다
});
```

- [ ] **Step 4: 돌려서 실패를 본다**

Run: `fvm flutter test test/notification_dto_test.dart --dart-define-from-file=config/dev.json`
Expected: FAIL — 파일 없음

- [ ] **Step 5: 도메인 네 클래스와 두 enum을 만든다**

`NotificationType.of`·`InvitationStatus.of`는 `RoomStatus.of`와 같은 판단이다 — 모르는 값은 `null`이고 아무 값으로도 뭉개지 않는다.

- [ ] **Step 6: `notification_dto.dart`에 `notificationPageFromJson`과 `notificationFromEvent`를 만든다**

`createdAt`·`scheduledStartAt`은 `KstTime.parse`다. 깨진 항목은 그 원소만 건너뛴다 — 알림 하나가 깨져서 알림함 전체가 비면 안 된다.

- [ ] **Step 7: 통과를 보고 커밋**

```bash
git add lib/features/notification test/notification_dto_test.dart
git commit -m "📍 Feat: 인앱 알림 도메인과 응답 파싱을 만든다"
```

---

## Task 5: 앱 스트림

**Files:**
- Create: `lib/features/notification/domain/app_stream.dart`
- Create: `lib/features/notification/data/sse_app_stream.dart`
- Create: `lib/features/notification/data/fake_app_stream.dart`
- Test: `test/sse_app_stream_test.dart`

**Interfaces:**
- Consumes: Task 4의 `AppNotification` · `notificationFromEvent`
- Produces:
  ```dart
  enum AppStreamFailure { network, sessionExpired, appUpdateRequired, unknown }
  class AppStreamException implements Exception {
    const AppStreamException(this.failure, {this.code});
    final String? code;    // 403일 때 서버 code
  }
  abstract interface class AppStream {
    Stream<AppNotification> connect();   // 연결마다 새 Stream
  }
  class SseAppStream implements AppStream {
    static AppNotification? eventOf(String? name, String raw);   // 테스트가 직접 부른다
    static AppStreamFailure failureOf(int? status, Object? body, {required bool versionKnown});
  }
  ```

`SseMatchStream`을 복제하지 않고 **그 파일의 구조를 따른다** — `HttpClient`, `event:`/`data:`/빈 줄, 바이트 침묵 감시, `_closeIfCurrent`. 경로는 `/api/v1/app/stream`이고 **404가 없다.**

- [ ] **Step 1: 주석 두 줄을 무시하는 테스트를 쓴다**

```dart
test('connected와 ping은 알림이 아니다', () {
  expect(SseAppStream.eventOf(null, ''), isNull);
});

test('모르는 event는 버리고 스트림은 살아 있다', () {
  expect(SseAppStream.eventOf('SOMETHING_NEW', '{"notificationId":1}'), isNull);
});

test('RUNNING_INVITED를 알림으로 읽는다', () {
  final notification = SseAppStream.eventOf('RUNNING_INVITED',
    '{"notificationId":913,"isRead":false,"createdAt":"2026-10-28T12:10:00",'
    '"actor":{"userId":"u1","nickname":"철수","isDeleted":false,'
    '"relationshipType":"FRIEND"},"invitation":{"runningRoomId":130,'
    '"status":"PENDING","scheduledStartAt":"2026-10-28T19:30:00",'
    '"targetDistanceMeters":7000}}');
  expect(notification!.notificationId, 913);
});
```

- [ ] **Step 2: Review Focus 1 — 403 분기 테스트를 쓴다**

```dart
test('버전을 읽은 상태의 403 APP_UPDATE_REQUIRED는 진짜 구버전이다', () {
  expect(
    SseAppStream.failureOf(403, {'code': 'APP_UPDATE_REQUIRED'}, versionKnown: true),
    AppStreamFailure.appUpdateRequired,
  );
});

test('버전을 못 읽었으면 업데이트 화면으로 보내지 않는다', () {
  expect(
    SseAppStream.failureOf(403, {'code': 'APP_UPDATE_REQUIRED'}, versionKnown: false),
    AppStreamFailure.unknown,   // 알림만 포기한다
  );
});

test('APP_UPDATE_REQUIRED가 아닌 403은 업데이트가 아니다', () {
  expect(
    SseAppStream.failureOf(403, {'code': 'EMAIL_NOT_AGREED'}, versionKnown: true),
    AppStreamFailure.unknown,
  );
});

test('401은 토큰 문제다', () {
  expect(SseAppStream.failureOf(401, null, versionKnown: true),
    AppStreamFailure.sessionExpired);
});
```

- [ ] **Step 3: 돌려서 실패를 본다**

Expected: FAIL — 파일 없음

- [ ] **Step 4: `app_stream.dart`와 `sse_app_stream.dart`를 만든다**

헤더 세 개를 싣는다 — `Authorization: Bearer …` · `AppVersionHeaders.current`. **버전을 못 읽으면 `current`가 빈 맵이라 두 헤더가 빠지고, 서버는 그것을 `403`으로 거절한다**(설계 §6-4). `versionKnown`은 `InstalledAppVersion.current != null`이다.

- [ ] **Step 5: 통과를 본다**

Expected: PASS

- [ ] **Step 6: 백오프 테스트를 쓴다**

```dart
test('재연결 간격이 반복마다 늘어난다', () {
  final backoff = AppStreamBackoff();
  final first = backoff.next();
  final second = backoff.next();
  expect(second, greaterThan(first));
  backoff.reset();
  expect(backoff.next(), first);
});
```

- [ ] **Step 7: 실패를 보고, 백오프를 만든다**

같은 서버에 붙은 두 기기가 서로의 연결을 끊을 수 있어서, 즉시 재연결을 무한 반복하면 두 기기가 서로를 밀어내며 돈다 — 그 이유를 주석에 남긴다. 상한을 둔다.

- [ ] **Step 8: 통과를 보고 `fake_app_stream.dart`를 만든다**

테스트가 이벤트를 밀어 넣을 수 있는 구현이다. Task 6이 쓴다.

- [ ] **Step 9: 커밋**

```bash
git add lib/features/notification test/sse_app_stream_test.dart
git commit -m "📍 Feat: 앱 전역 알림 스트림을 연다"
```

---

## Task 6: 알림 저장소 — 버퍼와 병합

이 작업의 핵심이다. 배지가 목록과 어긋나면 사용자는 앱을 믿지 않는다.

**Files:**
- Create: `lib/features/notification/domain/notification_repository.dart`
- Create: `lib/features/notification/data/http_notification_repository.dart`
- Create: `lib/features/notification/presentation/notification_provider.dart`
- Test: `test/notification_provider_test.dart` · `test/http_notification_repository_test.dart`

**Interfaces:**
- Consumes: Task 4의 `AppNotification`·`NotificationPageResult`, Task 5의 `AppStream`·`FakeAppStream`
- Produces:
  ```dart
  abstract interface class NotificationRepository {
    Future<NotificationPageResult> list({String? cursor, int limit = 20});
    Future<void> readAll();
  }

  class NotificationState {
    final List<AppNotification> items;
    final int unreadCount;        // 배지
    final String? nextCursor;
    final bool buffering;         // 목록 응답을 기다리는 중
    final bool loading;
    final NotificationFailure? failure;
  }

  class NotificationController extends Notifier<NotificationState> {
    Future<void> start();                 // 앱 스트림 연결 뒤 목록 조회
    Future<void> refresh();               // 포그라운드 복귀 — 첫 페이지부터
    Future<void> loadMore();
    Future<void> markAllRead();           // 목록 조회 뒤에만 부른다
    void onEvent(AppNotification notification);
    void updateRoom(int runningRoomId, InvitationStatus status);
  }
  final notificationProvider =
      NotifierProvider<NotificationController, NotificationState>(...);
  final unreadProvider = Provider<bool>(...);   // 배지 점 — 숫자가 아니다
  ```

- [ ] **Step 1: 버퍼 병합 테스트를 쓴다**

```dart
test('목록 응답 전에 온 이벤트는 버퍼에 담겼다가 합쳐진다', () async {
  // 이벤트 913을 먼저 밀어 넣고, 목록이 [912] unreadCount 1로 온다
  expect(state.items.map((n) => n.notificationId), [913, 912]);
  expect(state.unreadCount, 2);   // 1 + 버퍼 신규 1
});

test('목록에 이미 있는 알림은 배지에 다시 더하지 않는다', () async {
  // 이벤트 912를 먼저, 목록이 [912] unreadCount 1로 온다
  expect(state.items, hasLength(1));
  expect(state.unreadCount, 1);   // 버퍼 신규 0
});

test('같은 notificationId 이벤트가 두 번 와도 한 번만 반영된다', () async {
  // 실시간 모드에서 913을 두 번
  expect(state.items, hasLength(1));
  expect(state.unreadCount, 1);
});

test('목록 조회가 실패하면 버퍼를 지우지 않는다', () async {
  // 이벤트 913 뒤 목록이 실패, 재시도에서 성공
  expect(state.items.map((n) => n.notificationId), contains(913));
});
```

- [ ] **Step 2: 돌려서 실패를 본다**

Run: `fvm flutter test test/notification_provider_test.dart --dart-define-from-file=config/dev.json`
Expected: FAIL — 파일 없음

- [ ] **Step 3: `NotificationRepository`·`NotificationState`·`NotificationController`를 만들고 `start()`가 §5-2 네 단계를 따르게 한다**

순서는 **앱 스트림 연결 → 200 → 목록 조회**다. 목록을 먼저 받으면 그사이 생긴 알림을 실시간으로도 못 받고 목록에도 없다 — 그 이유를 주석에 남긴다. `notificationId`는 숫자로 비교한다.

- [ ] **Step 4: 통과를 본다**

Expected: PASS

- [ ] **Step 5: 재조회 테스트를 쓴다**

```dart
test('재조회는 첫 페이지부터 하고 뒤쪽 페이지와 커서를 버린다', () async {
  // 2페이지까지 받아 둔 뒤 refresh()
  expect(state.items, hasLength(firstPageLength));
  expect(state.nextCursor, newFirstPageCursor);
});

test('nextCursor가 null일 때만 더 불러오지 않는다', () async {
  // items 비어 있고 nextCursor 'c2' → loadMore가 한 번 더 부른다
  expect(repository.listCalls, 2);
});
```

- [ ] **Step 6: 실패를 보고 `refresh()`·`loadMore()`를 만든다**

- [ ] **Step 7: 통과를 보고, Review Focus 4 — 방 단위 갱신 테스트를 쓴다**

```dart
test('같은 방의 알림은 여러 페이지에 흩어져 있어도 함께 갱신된다', () {
  // 1페이지에 runningRoomId 130 알림, 2페이지에도 130 알림(actor 다름)
  controller.updateRoom(130, InvitationStatus.accepted);
  expect(state.items.where((n) => n.invitation?.runningRoomId == 130)
      .every((n) => n.invitation!.status == InvitationStatus.accepted), isTrue);
});

test('다른 방의 알림은 건드리지 않는다', () { ... });
```

- [ ] **Step 8: 실패를 보고 `updateRoom`을 만든다**

받아 둔 **모든** 페이지를 훑는다. 첫 페이지만 고치면 스크롤하면 낡은 버튼이 나온다.

- [ ] **Step 9: 모두 읽음 테스트를 쓴다**

```dart
test('모두 읽음이 성공하면 배지는 0이고 isRead 강조는 남는다', () async {
  // items에 isRead false가 둘
  await controller.markAllRead();
  expect(state.unreadCount, 0);
  expect(state.items.where((n) => !n.isRead), hasLength(2));  // 의도된 동작
});
```

- [ ] **Step 10: 실패를 보고 `markAllRead()`를 만든다**

- [ ] **Step 11: REST 테스트를 쓰고 `http_notification_repository.dart`를 만든다**

`_authorized` 401 한 번 갱신은 `HttpMatchRepository`와 같은 규칙이다. `limit`은 기본 20, 최대 50. 모두 읽음은 여러 번 불러도 `204`다.

- [ ] **Step 12: 전체 스위트를 돌려 기준선과 비교하고 커밋**

```bash
git add lib/features/notification test/
git commit -m "📍 Feat: 알림 목록을 버퍼·병합 규칙으로 맞춘다"
```

---

## Task 7: 초대 REST 네 개

**Files:**
- Create: `lib/features/matching/domain/invite_failure.dart`
- Create: `lib/features/matching/domain/invite_limits.dart`
- Modify: `lib/features/matching/domain/match_repository.dart`
- Modify: `lib/features/matching/data/http_match_repository.dart`
- Modify: `lib/features/matching/data/fake_match_repository.dart`
- Test: `test/invite_limits_test.dart` · `test/http_match_repository_invite_test.dart`

**Interfaces:**
- Produces:
  ```dart
  enum InviteFailure { closed, notFriend, alreadyInRoom, inMatching, running,
    countExceeded, notPending, roomFull, startAtOutOfRange, alreadyInProgress,
    onboardingNotCompleted, invalidRequest, notFound, network,
    sessionExpired, unknown }
  class InviteException implements Exception {
    const InviteException(this.failure, {this.message});
    final String? message;    // 서버 문구 — 초대 실패는 그대로 보여준다
  }

  abstract final class InviteLimits {
    static const minLeadMinutes = 10;      // 서버 규칙
    static const pickerLeadMinutes = 11;   // 피커 바닥 — 1분 여유
    static const minMeters = 1000;
    static const maxMeters = 42195;
    static const capacity = 4;
    static const maxInvitesPerFriend = 5;
    static const closeBeforeMinutes = 1;
    /// 바로가기 세 칸. 3/5/10은 매칭 버킷용이라 초대에 쓰지 않는다.
    static const halfMeters = 21098;   // 21,097.5를 올린다 — 내리면 공인 거리보다 짧다
    static const fullMeters = maxMeters;
    static const shortcuts = <({String label, int meters})>[
      (label: '5km', meters: 5000),
      (label: '하프', meters: halfMeters),
      (label: '풀', meters: fullMeters),
    ];
    /// 고를 수 있는 범위. 바닥이 천장을 넘으면 null — 23:49 이후다.
    static ({DateTime from, DateTime to})? window({required DateTime nowKst});
  }

  // MatchRepository에 추가
  Future<int> createInviteRoom({required String scheduledStartAt, required int meters});
  Future<void> invite({required int roomId, required String inviteeId});
  Future<int> acceptInvitation(int roomId);
  Future<void> declineInvitation(int roomId);
  ```

`MatchFailure`를 쓰지 않는다 — 저쪽은 서버 코드를 앱이 대응할 갈래로 **줄이고** 문구를 버리는데, 초대는 명세가 `message`를 그대로 보여 주라고 한다.

- [ ] **Step 1: 시작 시각 범위 테스트를 쓴다**

```dart
test('바닥은 지금 +11분, 천장은 오늘 23:59다', () {
  final w = InviteLimits.window(nowKst: DateTime(2026, 10, 29, 19, 0));
  expect(w!.from, DateTime(2026, 10, 29, 19, 11));
  expect(w.to, DateTime(2026, 10, 29, 23, 59));
});

test('23:48에는 아직 고를 수 있다', () {
  expect(InviteLimits.window(nowKst: DateTime(2026, 10, 29, 23, 48)), isNotNull);
});

test('23:49 이후에는 고를 수 있는 시각이 없다', () {
  expect(InviteLimits.window(nowKst: DateTime(2026, 10, 29, 23, 49)), isNull);
  expect(InviteLimits.window(nowKst: DateTime(2026, 10, 29, 23, 59)), isNull);
});

test('초는 버린다', () {
  final w = InviteLimits.window(nowKst: DateTime(2026, 10, 29, 19, 0, 37));
  expect(w!.from.second, 0);
});
```

- [ ] **Step 2: 돌려서 실패를 본다**

Expected: FAIL — 파일 없음

- [ ] **Step 3: `InviteLimits`를 만든다**

다섯 운영값을 한 곳에 모은다. **내려주는 API가 없어서 앱이 적어 둔다**는 사실과, 서버가 바꾸면 `INVITE_START_AT_OUT_OF_RANGE`로 알게 된다는 것을 주석에 남긴다. 익일 예약은 안 된다.

- [ ] **Step 4: 통과를 본다**

- [ ] **Step 5: 409 우선순위 테스트를 쓴다**

```dart
test('초대 실패는 명세 순서로 하나만 말한다', () {
  for (final (code, expected) in [
    ('RUNNING_INVITATION_CLOSED', InviteFailure.closed),
    ('NOT_FRIEND', InviteFailure.notFriend),
    ('INVITEE_ALREADY_IN_ROOM', InviteFailure.alreadyInRoom),
    ('INVITEE_IN_MATCHING', InviteFailure.inMatching),
    ('INVITEE_RUNNING', InviteFailure.running),
    ('INVITE_COUNT_EXCEEDED', InviteFailure.countExceeded),
  ]) {
    expect(HttpMatchRepository.inviteExceptionOf(_badResponse(409, code))
        .failure, expected);
  }
});

test('서버 문구를 그대로 들고 온다', () {
  final e = HttpMatchRepository.inviteExceptionOf(
    _badResponse(409, 'NOT_FRIEND', message: '친구에게만 초대할 수 있습니다.'));
  expect(e.message, '친구에게만 초대할 수 있습니다.');
});

test('404는 방 없음·초대 방 아님·내가 참가자 아님을 구분하지 않는다', () {
  expect(HttpMatchRepository.inviteExceptionOf(_badResponse(404, null))
      .failure, InviteFailure.notFound);
});

test('수락의 ROOM_FULL은 초대를 PENDING으로 남긴다', () {
  expect(HttpMatchRepository.inviteExceptionOf(
    _badResponse(409, 'RUNNING_ROOM_FULL')).failure, InviteFailure.roomFull);
});
```

- [ ] **Step 6: 실패를 보고 `invite_failure.dart`와 `HttpMatchRepository.inviteExceptionOf`를 만든다**

`exceptionOf`(매칭용)를 쓰지 않는다 — 저쪽은 404를 `nothingToCancel`로 묶어서, 그대로 쓰면 초대 실패에 "취소할 활성 신청이 없어요"가 뜬다. `_loadExceptionOf`가 같은 이유로 따로 있는 것과 같은 판단이다.

- [ ] **Step 7: 통과를 본다**

- [ ] **Step 8: 네 호출 테스트를 쓴다**

```dart
test('방 개설은 scheduledStartAt과 targetDistanceMeters만 보낸다', () async { ... });
test('초대는 inviteeId 한 명만 보낸다', () async { ... });
test('수락은 본문이 없고 runningRoomId를 받는다', () async { ... });
test('거절은 본문이 없다', () async { ... });
test('방 번호가 없는 201은 unknown이다', () async { ... });
```

마지막은 `apply`와 같은 판단이다 — 개설은 됐는데 스트림에 붙을 수 없으면 조용히 넘기면 안 된다.

- [ ] **Step 9: 실패를 보고 네 메서드를 `MatchRepository`·`HttpMatchRepository`·`FakeMatchRepository`에 더한다**

`_authorized`를 쓰되 `InviteException`으로 던진다. 경로는 `$_path/invite` · `$_path/{roomId}/invitations` · `.../accept` · `.../decline`.

- [ ] **Step 10: 통과를 보고 커밋**

```bash
git add lib/features/matching test/
git commit -m "📍 Feat: 초대 방 개설·초대·수락·거절 API를 붙인다"
```

---

## Task 8: 알림함 화면

**Files:**
- Create: `lib/features/notification/presentation/notification_page.dart`
- Create: `lib/features/notification/presentation/notification_row.dart`
- Modify: `lib/app/router/app_routes.dart` · `lib/app/router/app_router.dart`
- Modify: `lib/core/strings/app_strings.dart`
- Test: `test/notification_row_test.dart` · `test/notification_page_test.dart`

**Interfaces:**
- Consumes: Task 6의 `notificationProvider`·`NotificationController`, Task 7의 `acceptInvitation`·`declineInvitation`, `FriendRepository.accept`·`request` 취소
- Produces: `AppRoutes.notifications = '/profile/notifications'`

⚠️ **초대 방 화면의 `type` 분기는 Task 10이다.** 여기서 수락 뒤 방으로 보내면
그 화면은 아직 매칭 문구로 그려진다 — 동작은 맞고 문구만 낡았다. 의도한
중간 상태다.

문구는 **앱이 만든다** — 서버가 내려주지 않는다.

| 상수 | 값 |
|---|---|
| `notificationTitle` | `알림` |
| `notificationFriendRequested(nickname)` | `{nickname} 님이 친구 요청을 보냈어요` |
| `notificationFriendAccepted(nickname)` | `{nickname} 님과 친구가 되었어요` |
| `notificationRunningInvited(nickname)` | `{nickname} 님이 러닝에 초대했어요` |
| `notificationInviteExpired` | `모집이 마감됐어요` |
| `notificationInviteDeclined` | `초대를 거절했어요` |
| `notificationInviteLeft` | `방에서 나갔어요` |
| `notificationAccept` / `notificationDecline` | `수락` / `거절` |
| `notificationEmpty` | `아직 알림이 없어요` |

- [ ] **Step 1: 줄 버튼 테스트를 쓴다**

```dart
testWidgets('PENDING 초대에만 수락·거절이 선다', (tester) async { ... });
testWidgets('EXPIRED 초대는 버튼 없이 마감만 알린다', (tester) async { ... });
testWidgets('탈퇴한 actor는 친구 버튼을 모두 숨긴다', (tester) async {
  // relation: null
  expect(find.text(AppStrings.notificationAccept), findsNothing);
});
testWidgets('FRIEND_REQUEST_RECEIVED가 아닌 친구 알림에는 버튼이 없다',
  (tester) async { ... });
```

- [ ] **Step 2: 돌려서 실패를 본다**

Expected: FAIL — 파일 없음

- [ ] **Step 3: `NotificationRow`를 만든다**

`RunnerAvatarV2` · 문구 한 줄 · 초대면 `시각 · 거리` 한 줄 · 버튼. 안 읽은 줄에 점을 둔다. empty 상태와 다크·라이트 두 테마를 함께 정의한다.

- [ ] **Step 4: 통과를 본다**

- [ ] **Step 5: 열 때 순서 테스트를 쓴다**

```dart
testWidgets('알림함을 열면 목록 조회 뒤에 모두 읽음을 부른다', (tester) async {
  expect(repository.callOrder, ['list', 'readAll']);
});
```

- [ ] **Step 6: 실패를 보고 `NotificationPage`를 만든다**

loading / data / error 3분기를 반드시 처리한다. 순서를 바꾸면 목록 응답에서 안 읽은 상태가 사라져 점을 그릴 수 없다 — 그 이유를 주석에 남긴다.

- [ ] **Step 7: 통과를 보고 라우트를 등록한다**

`AppRoutes.notifications = '/profile/notifications'`.

- [ ] **Step 8: 수락·거절 테스트를 쓴다**

```dart
testWidgets('러닝 수락은 상태를 다시 읽은 뒤 방으로 보낸다', (tester) async {
  expect(repository.callOrder, ['acceptInvitation', 'userStatus']);
  expect(router.lastLocation, AppRoutes.matchRoom);
});

testWidgets('수락이 ROOM_FULL로 실패하면 버튼이 남는다', (tester) async {
  // 초대는 PENDING으로 남아 자리가 생기면 다시 누를 수 있다
  expect(find.text(AppStrings.notificationAccept), findsOneWidget);
});

testWidgets('수락이 NOT_PENDING으로 실패하면 버튼이 사라진다', (tester) async {
  expect(find.text(AppStrings.notificationAccept), findsNothing);
});

testWidgets('실패하면 목록을 첫 페이지부터 다시 읽는다', (tester) async {
  expect(controller.refreshCalls, 1);
});

testWidgets('거절은 줄을 남기고 버튼만 지운다', (tester) async { ... });
```

- [ ] **Step 9: 실패를 보고 두 버튼을 연결한다**

수락 순서는 **`acceptInvitation` → `GET /users/me/status` 재조회 → 방으로 이동**
이다. **2번을 건너뛸 수 없다** — `match_room_provider`는 `userStatusProvider`가
`WAITING`·`READY`를 말할 때만 스트림을 연다. 그 이유를 주석에 남긴다.

실패는 스낵바로 말하고 `refresh()`를 부른다. 줄만 고치면 그 방의 다른 알림이
낡은 상태로 남는다 — 상태가 방 단위라서 한 줄만 맞추는 것은 맞춘 것이 아니다.
성공하면 `updateRoom(roomId, …)`로 같은 방 알림을 함께 갱신한다(Task 6).

`RUNNING_ROOM_FULL`만 버튼을 지우지 않는다.

- [ ] **Step 10: 통과를 보고 커밋**

```bash
git add lib/features/notification lib/app/router lib/core/strings test/
git commit -m "📍 Feat: 알림함 화면을 만든다"
```

---

## Task 9: 벨과 탭 점

**Files:**
- Modify: `lib/features/profile/presentation/profile_page.dart:118-134`
- Modify: `lib/core/widgets/v2/app_tab_bar.dart`
- Modify: `lib/app/router/app_shell.dart:140-144` · `build`
- Test: `test/app_tab_bar_test.dart` · `test/profile_page_test.dart`

**Interfaces:**
- Consumes: Task 6의 `unreadProvider`
- Produces: `AppTabBarV2({..., Set<int> badges = const {}})`

- [ ] **Step 1: 탭 점 테스트를 쓴다**

```dart
testWidgets('badges에 든 인덱스에만 점이 선다', (tester) async { ... });

testWidgets('점이 있으면 스크린리더가 읽는 이름이 바뀐다', (tester) async {
  // badges: {3}
  expect(tester.getSemantics(find.bySemanticsLabel('프로필, 읽지 않은 알림 있음')),
    isNotNull);
});

testWidgets('점이 없으면 이름은 그대로다', (tester) async {
  expect(tester.getSemantics(find.bySemanticsLabel(AppStrings.tabProfile)),
    isNotNull);
});
```

두 번째가 이 작업의 요점이다. **탭 바에 글자 라벨이 없어서 점을 그림으로만 두면 읽히지 않는다.**

- [ ] **Step 2: 돌려서 실패를 본다**

Expected: FAIL — `badges` 이름 인자 없음

- [ ] **Step 3: `AppTabBarV2`에 `badges: Set<int>`를 더하고 `_Slot`이 점과 라벨을 바꾸게 한다**

`AppTabSpec`은 `static const` 목록이라 거기 담지 않는다 — 그 이유를 주석에 남긴다. 점 색은 토큰에서 가져온다(`Color(0x...)` 금지). `_Slot`의 아이콘을 `Stack`으로 감싼다.

- [ ] **Step 4: 통과를 본다**

- [ ] **Step 5: `app_shell.dart`가 `unreadProvider`를 watch해 `badges`를 넘기게 한다**

앱 스트림 구독도 여기다. `app_shell.dart` 주석이 적어 둔 규칙 그대로 — **안 보이는 탭의 provider는 dispose되므로 전역 연결을 화면 provider에 두면 탭을 옮기는 순간 끊긴다.** 포그라운드 복귀 리스너가 이미 있으니 거기서 `refresh()`를 부른다.

- [ ] **Step 6: 벨 테스트를 쓴다**

```dart
testWidgets('프로필 상단 설정 왼쪽에 벨이 선다', (tester) async { ... });
testWidgets('안 읽은 알림이 있으면 벨에 점이 선다', (tester) async { ... });
testWidgets('벨을 누르면 알림함으로 간다', (tester) async { ... });
```

- [ ] **Step 7: 실패를 보고 `profile_page.dart`의 `Positioned`를 `Row`로 바꿔 벨을 더한다**

`ProfileCoverAction`을 그대로 쓴다 — 어두운 원 + 아이콘이 똑같이 나온다. 아이콘은 `AppIcons.bell`. **숫자가 아니라 점이다**(배지 숫자가 서버와 어긋날 수 있다).

- [ ] **Step 8: 통과를 보고 전체 스위트를 돌린다. 커밋**

```bash
git add lib/features/profile lib/core/widgets/v2/app_tab_bar.dart lib/app/router test/
git commit -m "📍 Feat: 프로필 벨과 탭 바 알림 점을 세운다"
```

---

## Task 10: 초대 방 화면

**Files:**
- Modify: `lib/features/matching/presentation/match_room_page.dart`
- Modify: `lib/features/matching/presentation/match_room_provider.dart`
- Modify: `lib/core/strings/app_strings.dart`
- Test: `test/match_room_page_test.dart` · `test/match_room_provider_test.dart`

**Interfaces:**
- Consumes: Task 2의 `RoomInfo.type`·`invitations`·두 이벤트, Task 7의 초대 REST

문구:

| 상수 | 값 |
|---|---|
| `inviteRoomTitle` | `초대 러닝` |
| `inviteRoomPendingLabel(nickname)` | `초대 중 · {nickname}` |
| `inviteRoomLeaveNotice` | `언제든 나갈 수 있어요` |
| `inviteRoomLastLeaveNotice` | `나가면 방이 사라져요` |
| `inviteRoomAloneWarning` | `1분 뒤 모집이 닫혀요 · 혼자 달리게 됩니다` |
| `inviteRoomInviteCta` | `러너 초대` |
| `inviteRoomSeatsLeft(count)` | `남은 자리 {count}` |

- [ ] **Step 1: 분기 테스트를 쓴다**

```dart
testWidgets('초대 방은 매칭 제재 문구를 말하지 않는다', (tester) async {
  // type: RoomType.invite, status: matched
  expect(find.textContaining('20분'), findsNothing);
  expect(find.text(AppStrings.inviteRoomLeaveNotice), findsOneWidget);
});

testWidgets('매칭 방은 제재 문구를 그대로 말한다', (tester) async { ... });

testWidgets('PENDING 초대가 빈 자리에 선다', (tester) async {
  // players 1명, invitations 1명
  expect(find.text(AppStrings.inviteRoomPendingLabel('철수')), findsOneWidget);
});
```

- [ ] **Step 2: Review Focus 3 — 마감 뒤 초대 현황이 사라지는 테스트를 쓴다**

```dart
testWidgets('모집 마감으로 invitations가 비면 초대 중 자리가 사라진다',
  (tester) async {
  // invitations 1명으로 그린 뒤 status: matched, invitations: [] 로 갱신
  expect(find.textContaining('초대 중'), findsNothing);
});
```

- [ ] **Step 3: 1인 경고 테스트를 쓴다**

```dart
testWidgets('혼자인 방은 마감 전에 혼자 달리게 된다고 알린다', (tester) async {
  // players 1명, closeAt 이 1분 안
  expect(find.text(AppStrings.inviteRoomAloneWarning), findsOneWidget);
});

testWidgets('둘 이상이면 경고하지 않는다', (tester) async { ... });
```

**취소도 `CANCELLED`도 없어서 마감 전 나가기가 유일한 출구다.**

- [ ] **Step 4: 돌려서 실패를 본다**

Expected: FAIL — 문구 상수 미정의

- [ ] **Step 5: `match_room_page.dart`가 `room.type`으로 가르게 한다**

같은 파일 안에서 분기한다. `_PartyCard` 같은 조각이 파일 내부 private이라 **별도 페이지로 떼면 전부 복사해야 한다** — 그 이유를 주석에 남긴다. `_leaveNotice`(`:210`)가 초대 방에서 다른 문구를 준다.

- [ ] **Step 6: 통과를 본다**

- [ ] **Step 7: provider 이벤트 테스트를 쓰고 두 이벤트를 반영한다**

```dart
test('INVITE_ROOM_ENTRANCE가 방을 세운다', () { ... });
test('INVITE_ROOM_UPDATED가 참가자와 초대 현황을 갈아끼운다', () { ... });
test('startsInMs는 남은 시간에 쓰고 출발 타이머는 RUNNING_READY가 정한다', () { ... });
```

- [ ] **Step 8: 통과를 보고 커밋**

```bash
git add lib/features/matching lib/core/strings test/
git commit -m "📍 Feat: 초대 방 대기 화면을 매칭 방에서 가른다"
```

---

## Task 11: 친구 초대 모달

**Files:**
- Create: `lib/features/matching/presentation/invite_friend_sheet.dart`
- Modify: `lib/features/matching/presentation/match_room_page.dart` (버튼 연결)
- Modify: `lib/core/strings/app_strings.dart`
- Test: `test/invite_friend_sheet_test.dart`

**Interfaces:**
- Consumes: Task 7의 `invite`, Task 10의 방 화면, `FriendRepository.friends()`·`search(query:)`

| 상수 | 값 |
|---|---|
| `inviteSheetTitle` | `러너 초대` |
| `inviteSheetSearchHint` | `닉네임 검색` |
| `inviteSheetInvite` | `초대` |
| `inviteSheetInvited` | `초대 중` |
| `inviteSheetJoined` | `참여 중` |
| `inviteSheetRetry` | `다시 초대` |
| `inviteSheetEmpty` | `초대할 러너가 없어요` |

- [ ] **Step 1: 줄 상태 테스트를 쓴다**

```dart
testWidgets('invitations에 있는 사람은 초대 중으로 잠긴다', (tester) async {
  expect(tester.widget<AppButtonV2>(find.ancestor(
    of: find.text(AppStrings.inviteSheetInvited),
    matching: find.byType(AppButtonV2))).onPressed, isNull);
});

testWidgets('players에 있는 사람은 참여 중으로 잠긴다', (tester) async { ... });

testWidgets('남은 자리가 0이면 모든 초대 버튼이 잠긴다', (tester) async {
  // players 4명
});

testWidgets('실패하면 그 줄에 서버 문구가 붙는다', (tester) async {
  // invite가 InviteException(notFriend, message: '친구에게만 초대할 수 있습니다.')
  expect(find.text('친구에게만 초대할 수 있습니다.'), findsOneWidget);
  expect(find.text(AppStrings.inviteSheetRetry), findsOneWidget);
});

testWidgets('한 번에 한 명씩 보낸다', (tester) async {
  // 두 줄을 연달아 누르면 inviteeId가 다른 호출이 둘
  expect(repository.inviteCalls, hasLength(2));
});
```

- [ ] **Step 2: 돌려서 실패를 본다**

Expected: FAIL — 파일 없음

- [ ] **Step 3: `invite_friend_sheet.dart`를 만든다**

`FriendRow`를 재사용하지 않는다 — 저쪽은 **관계**(`FriendRelation`)로 버튼을 가르고 초대의 네 상태는 **방 안의 자리**다. 그 이유를 주석에 남긴다. 아바타는 `RunnerAvatarV2`.

**독촉을 내보내지 않는다.** `PENDING`인 줄은 잠긴다 — 남은 횟수를 알 수 없어서(`invitations[]`에 횟수 필드가 없고 보낸 사람별로 세니 앱이 셀 수도 없다) 몇 번 남았는지 못 말하면서 누르라고 권하는 버튼이 된다. 그 판단과, 횟수 필드가 생기면 `다시 알림`을 붙인다는 것을 주석에 남긴다.

**친구별 "지금 초대 가능" 상태를 서버가 주지 않아서** 전원 멀쩡한 것처럼 그리고 눌러서 실패를 알게 된다 — 이것도 주석에 남긴다.

empty 상태와 다크·라이트 두 테마를 함께 정의한다.

- [ ] **Step 4: 통과를 보고 방 화면의 초대 버튼에 연결한다**

정원이 남아 있고 `status == MATCHING`일 때만 버튼이 선다.

- [ ] **Step 5: 커밋**

```bash
git add lib/features/matching lib/core/strings test/
git commit -m "📍 Feat: 방에서 러너를 골라 초대하는 모달을 만든다"
```

---

## Task 12: 초대 등록 화면

**Files:**
- Create: `lib/features/matching/presentation/invite_register_page.dart`
- Create: `lib/features/matching/presentation/invite_register_provider.dart`
- Modify: `lib/app/router/app_routes.dart` · `app_router.dart`
- Modify: `lib/core/strings/app_strings.dart`
- Test: `test/invite_register_provider_test.dart` · `test/invite_register_page_test.dart`

**Interfaces:**
- Consumes: Task 7의 `InviteLimits`·`createInviteRoom`
- Produces: `AppRoutes.inviteRegister = '/match/invite'`

| 상수 | 값 |
|---|---|
| `inviteRegisterTitle` | `초대 러닝` |
| `inviteRegisterWhen` | `언제 뛸까요` |
| `inviteRegisterHowFar` | `얼마나 뛸까요` |
| `inviteRegisterSubmit` | `방 만들기` |
| `inviteRegisterWindowHint(from, to)` | `{from} ~ {to} 사이로 정할 수 있어요` |
| `inviteRegisterDistanceHint` | `1km ~ 42.195km` |
| `inviteRegisterClosedToday` | `오늘은 초대 러닝을 만들 수 없어요` |
| `inviteRegisterClosedTodayBody` | `자정이 지나면 다시 열려요` |

- [ ] **Step 1: 상태 전이 테스트를 쓴다**

```dart
test('범위 밖 시각은 보낼 수 없다', () { ... });
test('999m는 보낼 수 없고 1000m는 보낼 수 있다', () { ... });
test('42195m는 보낼 수 있고 42196m는 안 된다', () { ... });
test('바로가기 칩이 보내는 값은 5000 · 21098 · 42195다', () {
  expect(InviteLimits.shortcuts.map((s) => s.meters), [5000, 21098, 42195]);
});
test('하프는 21097.5를 올린 값이다', () {
  expect(InviteLimits.halfMeters, 21098);   // 내리면 공인 거리보다 짧다
});
test('풀은 상한과 같다', () {
  expect(InviteLimits.fullMeters, InviteLimits.maxMeters);
});
test('칩을 누르면 입력란이 그 값으로 채워진다', () { ... });
test('셋 밖의 값을 넣으면 아무 칩도 선택되지 않는다', () { ... });
test('개설이 성공하면 방 번호를 들고 나간다', () async { ... });
```

- [ ] **Step 2: 빈 범위 테스트를 쓴다**

```dart
testWidgets('23:49 이후에는 피커 대신 오늘은 못 만든다고 말한다', (tester) async {
  // now 23:50
  expect(find.text(AppStrings.inviteRegisterClosedToday), findsOneWidget);
  expect(find.byType(AppButtonV2), findsNothing);   // 또는 잠긴 CTA
});
```

**빈 피커만 두면 고장으로 읽힌다.**

- [ ] **Step 3: 돌려서 실패를 본다**

Expected: FAIL — 파일 없음

- [ ] **Step 4: `invite_register_provider.dart`를 만든다**

`InviteLimits.window(nowKst:)`가 `null`이면 빈 범위 상태다. `scheduledStartAt`은 `KstTime`으로 만든다 — **앱이 처음으로 이 값을 직접 만드는 자리**이고 `match_slot.dart`가 "다시 조립하지 않는다"고 못 박은 규칙의 예외라는 것을 주석에 남긴다. 피커 바닥에 둔 1분 여유의 이유(기기 시계가 느리면 화면에서 합법이던 값이 서버에서 거절된다)도 적는다.

- [ ] **Step 5: 통과를 본다**

- [ ] **Step 6: 화면을 만든다**

껍데기는 `match_register_page.dart`를 베껴 쓴다 — `SurfaceCard` · `PresetChip` · `AppButtonV2`, 실패를 스낵바로 알리고 곧바로 지우는 패턴. **쿨다운을 막지 않는다**(초대는 쿨다운 중에도 개설할 수 있다). loading / data / error 3분기와 다크·라이트 두 테마.

바로가기 칩은 `InviteLimits.shortcuts` 셋을 **`Row` + `Expanded`로 균등하게** 깐다. 왼쪽으로 쏠리면 오른쪽 빈자리가 "칩이 더 있는데 잘렸나"로 읽힌다 — 그 이유를 주석에 남긴다. 사이 간격은 `AppSpacing`이다.

| 상수 | 값 |
|---|---|
| `inviteRegisterShortcut5` | `5km` |
| `inviteRegisterShortcutHalf` | `하프` |
| `inviteRegisterShortcutFull` | `풀` |

- [ ] **Step 7: 409를 명세 순서로 하나만 말하는 테스트를 쓰고 통과시킨다**

`INVITE_START_AT_OUT_OF_RANGE` → `RUNNING_ALREADY_IN_PROGRESS` → `ONBOARDING_NOT_COMPLETED`.

- [ ] **Step 8: 라우트를 등록하고 커밋**

```bash
git add lib/features/matching lib/app/router lib/core/strings test/
git commit -m "📍 Feat: 시각과 거리를 자유롭게 정하는 초대 등록 화면을 만든다"
```

---

## Task 13: 홈 — 초대 칸과 히어로 문구

**Files:**
- Modify: `lib/features/home/presentation/home_page.dart:190`
- Modify: `lib/features/home/presentation/home_hero.dart:110-160`
- Modify: `lib/features/home/presentation/home_waiting.dart`
- Modify: `lib/features/home/presentation/home_confirmed.dart`
- Modify: `lib/core/strings/app_strings.dart`
- Modify: `test/home_page_test.dart:72-79`
- Test: `test/home_hero_test.dart`

**Interfaces:**
- Consumes: Task 1의 `RoomType`, Task 12의 `AppRoutes.inviteRegister`

| 상수 | 값 |
|---|---|
| `homeInviteWaitingTitle` | `초대 러닝 대기 중` |
| `homeInviteWaitingAlone` | `초대한 러너의 답을 기다리고 있어요` |
| `homeInviteJoined(nickname)` | `{nickname} 님이 함께 뛰어요` |
| `homeInviteConfirmedTitle` | `출발 준비 완료` |

- [ ] **Step 1: 히어로 문구 테스트를 쓴다**

```dart
testWidgets('초대 방 대기는 매칭 대기 중이라고 말하지 않는다', (tester) async {
  // type: invite, status: matching, players 1명
  expect(find.text(AppStrings.homeMatchWaitingTitle), findsNothing);
  expect(find.text(AppStrings.homeInviteWaitingTitle), findsOneWidget);
  expect(find.text(AppStrings.homeInviteWaitingAlone), findsOneWidget);
});

testWidgets('매칭 방 대기는 기존 문구를 그대로 쓴다', (tester) async { ... });

testWidgets('초대 방 확정은 매칭 완료라고 말하지 않는다', (tester) async {
  expect(find.text(AppStrings.homeInviteConfirmedTitle), findsOneWidget);
});

testWidgets('혼자 달리게 된 초대 방은 기존 솔로 문구를 쓴다', (tester) async {
  expect(find.text(AppStrings.homeMatchSoloTitle), findsOneWidget);
});
```

마지막은 그대로 맞는 문구다 — 바꾸지 않는다.

- [ ] **Step 2: 돌려서 실패를 본다**

Expected: FAIL — 문구 상수 미정의

- [ ] **Step 3: 세 파일이 `room.type`을 보고 문구를 고르게 한다**

**새 히어로 파일을 만들지 않는다** — 레이아웃이 같고 문구만 다르다. 네 파일을 복제하면 매칭을 고칠 때마다 두 벌을 고친다. 그 이유를 주석에 남긴다.

- [ ] **Step 4: 통과를 본다**

- [ ] **Step 5: 홈 초대 칸 테스트를 고친다**

`test/home_page_test.dart:72-79`가 "⚠️ 둘째 칸은 초대 러닝이다 … 아직 갈 곳이 없어 준비 중이라고 말한다"를 못 박고 있다. 갈 곳이 생겼으므로 `AppRoutes.inviteRegister`로 간다는 테스트로 바꾼다.

- [ ] **Step 6: 돌려서 실패를 보고, `home_page.dart:190`을 초대 등록으로 연결한다**

- [ ] **Step 7: 전체 스위트를 돌려 기준선과 비교하고 커밋**

```bash
git add lib/features/home lib/core/strings test/
git commit -m "📍 Feat: 홈에서 초대 러닝을 열고 초대 방 문구를 가른다"
```

---

## 작업 묶음 — PR 다섯 개

| PR | 작업 | 사유 |
|---|---|---|
| 1 | Task 1 · 2 · 3 | 계약. 없으면 나머지가 다 어긋난다 |
| 2 | Task 4 · 5 · 6 · 7 | 앱 스트림 · 알림 저장소 · 초대 REST. 화면 없이 테스트할 수 있는 부분이 전부 여기 있다. **초대 REST가 여기 있는 이유는 알림함의 수락 버튼이 그것을 부르기 때문**이다 |
| 3 | Task 8 · 9 | 알림함 · 벨 · 탭 점 |
| 4 | Task 10 · 11 | 초대 방 분기와 초대 모달 |
| 5 | Task 12 · 13 | 초대 등록과 홈 |

**PR 1·2·3은 지금 실제 서버로 확인할 수 있다** — 앱 스트림·알림 목록·친구 이벤트 2종이 모두 BE 개발완료다.

**PR 4·5는 `INVITE_ROOM_ENTRANCE`·`INVITE_ROOM_UPDATED`가 BE 개발중**이라, 그 둘이 끝나기 전에는 `FakeMatchStream`으로만 확인한다. 초대 REST 네 개는 개발완료라 호출 자체는 실제 서버로 확인된다.

PR 본문의 **💬 리뷰 포인트**에 적을 것 — 설계 §9의 "내가 정한 것" 중 그 PR에 든 것(독촉 미노출, 홈 히어로 문구 분기, 수락 뒤 자동 이동, 피커 1분 여유, 1인 방 경고)과 §8의 열린 질문 아홉 개 중 해당하는 것.

**`main`에 머지하지 않는다** — 1.1.1이 스토어 심사를 통과할 때까지. base는 `dev`다.
