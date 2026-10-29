# 초대 러닝과 인앱 알림 (설계)

> 작성 2026-10-29 · 백엔드 REST 전부 개발완료, SSE 초대 이벤트 2종 개발중, 프론트 전부 개발전
> 근거 — `[1.2.0] 인앱 알림·초대 러닝 프론트엔드 연동 가이드`, `[1.2.0] 기존 API 변경 및 프론트엔드 연동 가이드`
> 이벤트 명세 — `INVITE_ROOM_ENTRANCE` · `INVITE_ROOM_UPDATED` · `RUNNING_INVITED`
> 웹뷰 시안 — https://claude.ai/artifact/LkiaxwigT34kP8XWH366ob (등록 · 대기방 · 초대 모달)

같이 뛸 러너를 **직접 골라 초대**한다. 매칭과 달리 시각과 거리를 자유롭게
정하고, 상대가 수락하면 같은 방에 들어온다.

초대받는 쪽의 유일한 통로가 인앱 알림이어서, 이 작업은 **앱 전역 알림
시스템을 함께 세우는 일**이다. 같은 통로로 친구 요청·수락 알림도 와서
지난주에 만든 친구 기능의 알림이 함께 붙는다.

---

## 1. 목표

- 초대 방을 열고, 친구를 골라 초대하고, 수락한 사람과 함께 출발한다
- 초대받은 사람이 **앱 안에서** 초대를 보고 수락·거절한다
- 알림함에서 지난 알림을 보고, 안 읽은 것이 있으면 눈에 띈다

### 비목표

- **푸시 알림.** 서버가 보내지 않고, 앱에도 FCM이 없다. 앱이 꺼져 있으면
  초대는 다음 진입 때 알림 목록으로 본다
- **초대 취소.** 엔드포인트가 없다(§8-2)
- 초대 방 전용 러닝 화면. 출발 이후는 매칭 방과 **완전히 같다**

### 안티목표 — 되면 실패다

- **매칭 등록·매칭 방이 초대 때문에 위험해지는 것.** 두 흐름이 한 화면에서
  엉키면 이미 배포된 매칭이 같이 흔들린다
- **알림을 중복으로 세는 것.** 배지 숫자가 목록과 어긋나면 사용자는 앱을
  믿지 않는다. 가이드 1-1의 병합 규칙을 그대로 따르는 이유다
- **버전 못 읽은 사용자를 업데이트 화면에 가두는 것**(§6-4)

---

## 2. ⚠️ 먼저 — 화면 정본에 초대 러닝이 없다

| 출처 | 초대 러닝을 어떻게 다루나 |
|---|---|
| `와이어프레임_최종.md` (화면 정본) | **947줄에 "초대"가 0건** |
| `와이어프레임_FE노트.md` | `## 로드맵 (MVP 제외)` — "팔로우 세션 초대(구 친구 초대)" |
| `기능명세서(최종).md` 160줄 | "친구 초대 기반 프라이빗 매칭은 **포함하지 않는다**" |

세 문서가 모두 MVP 밖으로 뺀 기능을 백엔드가 먼저 만들었다. **초대 등록·초대
모달·알림함에는 시안이 없다.** 이 설계가 그 세 화면을 정한다 — 전부 내가 정한
것이고, 디자이너 시안이 오면 갈아끼운다.

다만 정본에서 **쓸 수 있는 인접 규칙 두 개**가 있다.

- **C7 알림 탭 랜딩 규칙** — "새 팔로워 → 상대 프로필(S20)"이 가이드의
  `FRIEND_REQUESTED` 랜딩과 정확히 같다. 알림 줄을 눌렀을 때의 이동은 C7을
  따른다
- **C8 인앱 포그라운드 알림** — 상단 슬라이드다운, 4.2초 후 소멸, `보기` 탭 시
  모달을 닫고 이동. `RUNNING_INVITED`를 실시간으로 알릴 자리다. **미구현이다**
  (§7-3)

### 2-1. `CLAUDE.md`의 "친구" 금지 줄이 아직 살아 있다

`CLAUDE.md` Conventions에 `"친구"라는 말은 쓰지 않는다 (요청→수락 모델)`이
그대로 있다. 2026-10-28 친구 설계에서 **백엔드 어휘("친구")로 가기로 정했고**
그 줄을 걷어내자고 제안했는데 아직 적용되지 않았다.

이 설계도 화면에서 **"친구"라고 쓴다** — 초대 모달이 친구 목록을 쓰고, 서버
에러도 "친구에게만 초대할 수 있습니다"라고 말한다. 줄을 걷어내는 것은
개발자가 한다.

---

## 3. 쓰는 엔드포인트와 이벤트

### 3-1. REST — 전부 `BE 개발완료`

| 메서드 | 경로 | 쓰는 곳 |
|---|---|---|
| POST | `/match-rooms/invite` | 초대 방 개설 |
| POST | `/match-rooms/{roomId}/invitations` | 초대 보내기 (독촉도 같은 호출 — §4-4에서 안 내보낸다) |
| POST | `/match-rooms/{roomId}/invitations/accept` | 수락 |
| POST | `/match-rooms/{roomId}/invitations/decline` | 거절 |
| POST | `/match-rooms/leave` | 나가기 — **이미 쓰고 있다** |
| GET | `/match-rooms/stream` | 방 상태 — **이미 쓰고 있다** |
| GET | `/app/stream` | 앱 전역 알림 |
| GET | `/users/me/notifications` | 알림 목록 · 배지 |
| POST | `/users/me/notifications/read` | 모두 읽음 |
| GET | `/users/me/status` | **`type: INVITE`가 처음 내려온다** |
| GET | `/users/{userId}` | `friendStatus` → `relationshipType` 개명 |

초대 방 개설은 `{ scheduledStartAt, targetDistanceMeters }`를 받아
`201 { runningRoomId }`를 준다. 초대는 `{ inviteeId }` **한 명만** 받고 `204`다.
수락은 `201 { runningRoomId }`, 거절은 `204`이고 둘 다 **본문이 없다** — 받는
사람은 토큰 주체이고, 보낸 사람을 고르지 않는다.

**방장이 없다.** 참가자 누구나 초대할 수 있다.

### 3-2. SSE 이벤트

| 스트림 | 이벤트 | BE 현황 |
|---|---|---|
| 매칭 | `INVITE_ROOM_ENTRANCE` — 초대 방 연결 직후 스냅샷 | **개발중** |
| 매칭 | `INVITE_ROOM_UPDATED` — 초대 방 갱신 | **개발중** |
| 앱 | `RUNNING_INVITED` — 초대받음 | 개발완료 |
| 앱 | `FRIEND_REQUESTED` · `FRIEND_ACCEPTED` | 개발완료 |

초대 방은 **`MATCH_STARTED`를 받지 않는다.** 모집 마감은 `INVITE_ROOM_UPDATED`가
`status: MATCHED` · `invitations: []`로 알리고, 확정 연출은 없다.
`RUNNING_READY`까지 대기 화면을 유지한다.

`INVITE_ROOM_UPDATED`가 나가는 때 — 초대 전송·재초대, 수락, 거절, 나가기,
회원 탈퇴 정리, 모집 마감. **나가지 않는 때** — 409로 막힌 초대, 참가자가
0명이 되어 방이 사라질 때(받을 사람이 없다), `STARTED` 전환.

### 3-3. 초대 방의 운영값

| 항목 | 값 |
|---|---|
| 시작 시각 | 현재 +10분 ~ 오늘 23:59 (KST, 분 단위) |
| 목표 거리 | 1,000 ~ 42,195m |
| 정원 | 4명 |
| 한 친구에게 보낼 수 있는 횟수 | 최초 포함 5회, **보낸 사람별로 따로** |
| 모집 마감 | 시작 1분 전 |
| 나가기 제재 | **없다** — `cooldownUntil`이 생기지 않는다 |

**다섯 개 다 운영값인데 내려주는 API가 없다**(§8-5). 앱이 적어 둔다 —
`InviteLimits` 한 곳에 모으고, 서버가 바꾸면 `INVITE_START_AT_OUT_OF_RANGE`로
알게 된다.

초대 방은 **쿨다운 중에도 개설할 수 있다.** 매칭 등록과 다른 점이다.

### 3-4. 알림 모델 — 실제 모양

근거 문서가 저장소 **밖**(팀 노션)에 있어서, DTO를 쓸 때 필요한 것을 여기
옮겨 적는다.

- 연동 가이드 — `https://app.notion.com/p/408ae181f710805c91b8e6ae3d86c271`
- 기존 API 변경 — `https://app.notion.com/p/408ae181f71080afb4bef3cc1ea8e8a4`
- `RUNNING_INVITED` — `https://app.notion.com/p/408ae181f71080639521ed51ff1fb916`

**이벤트 `data`는 알림 목록 항목에서 `type`만 뺀 모양이다.** 종류는 이벤트
이름이 말한다. 즉 `data`에 `type`을 붙이면 그대로 목록 항목이 된다 — 버퍼에
담은 이벤트를 목록과 `notificationId`로 대조할 수 있는 근거가 이것이다.

```json
{
  "event": "RUNNING_INVITED",
  "data": {
    "notificationId": 913,
    "isRead": false,
    "createdAt": "2026-10-28T12:10:00",
    "actor": {
      "userId": "01a0f2d4-6180-7000-8000-446655440013",
      "nickname": "철수",
      "profileImageUrl": "https://...",
      "isDeleted": false,
      "relationshipType": "FRIEND"
    },
    "invitation": {
      "runningRoomId": 130,
      "status": "PENDING",
      "scheduledStartAt": "2026-10-28T19:30:00",
      "targetDistanceMeters": 7000
    }
  }
}
```

| 필드 | 타입 | 비고 |
|---|---|---|
| `notificationId` | Long | **숫자다.** 목록의 같은 이름과 같은 값 |
| `isRead` | bool | 새 알림이라 항상 `false` |
| `createdAt` | String | KST, 오프셋 없음 → `KstTime.parse` |
| `actor.userId` | UUID | |
| `actor.nickname` | String | 탈퇴했으면 `"탈퇴한 사용자"` |
| `actor.profileImageUrl` | String·null | 없거나 탈퇴면 `null` |
| `actor.isDeleted` | bool | |
| `actor.relationshipType` | Enum·null | 탈퇴면 `null` |
| `invitation` | Object·null | **`RUNNING_INVITED`에만 있다.** 나머지 둘은 `null` |
| `invitation.runningRoomId` | Long | 수락·거절 경로에 쓴다 |
| `invitation.status` | Enum | `PENDING`·`ACCEPTED`·`DECLINED`·`LEFT`·`EXPIRED` |
| `invitation.scheduledStartAt` | String | KST |
| `invitation.targetDistanceMeters` | Integer | |

`relationshipType` = `NONE` · `FRIEND` · `FRIEND_REQUEST_SENT` ·
`FRIEND_REQUEST_RECEIVED` (탈퇴 `null`).

목록 조회 `GET /users/me/notifications?cursor=&limit=`(기본 20, 최대 50)는
`{ items[], nextCursor, unreadCount }`를 준다. `items[]` 원소는 위 `data`에
`type`(`FRIEND_REQUESTED`·`FRIEND_ACCEPTED`·`RUNNING_INVITED`)이 붙은 모양이다.

**`invitation`이 `null`인 `RUNNING_INVITED`는 없다.** 초대 행이 없는 알림은
서버가 목록과 이벤트에서 모두 빼므로 그 경우를 따로 다루지 않는다.

---

## 4. 화면

새로 만드는 것 셋, 손보는 것 셋이다.

| | 화면 | |
|---|---|---|
| 새로 | 초대 등록 | §4-2 |
| 새로 | 친구 초대 모달 | §4-4 |
| 새로 | 알림함 | §4-6 |
| 손봄 | 홈 `초대 러닝` 칸 | §4-1 |
| 손봄 | 매칭 방 → 초대 방 분기 | §4-3 |
| 손봄 | 프로필 상단 · 탭 바 | §4-5 · §4-7 |

### 4-1. 홈 `초대 러닝` 칸

`home_page.dart:190`의 둘째 칸이 지금 `ComingSoonPage`로 간다. 초대 등록으로
연결한다. 라벨(`AppStrings.homeInviteRunCta = '초대 러닝'`)은 그대로다.

`test/home_page_test.dart:72-79`가 "준비 중"을 못 박고 있어 **같은 커밋에서
고친다.**

### 4-2. 초대 등록 — 별도 페이지

`match_register_page.dart`(707줄)에 분기를 넣지 않는다. 입력이 겹치지 않는다.

| | 매칭 등록 | 초대 등록 |
|---|---|---|
| 시각 | 서버가 준 슬롯 중 택1 | 자유 입력, 분 단위 |
| 거리 | `TargetDistance` 3/5/10km | 자유 입력 1,000~42,195m |

두 도메인 모델이 자유 입력을 **막는 쪽으로** 적혀 있다. `target_distance.dart`
주석은 "셋 중 하나만 고를 수 있다. 자유 입력이 아니다", `match_slot.dart`는
서버 문자열을 손대지 않고 되돌려 보내는 구조다. 둘 다 초대에 못 쓴다.

껍데기는 베껴 쓴다 — `SurfaceCard` · `PresetChip` · `AppButtonV2`, 실패를
스낵바로 알리고 곧바로 지우는 패턴.

```
┌─────────────────────────┐
│ ←  초대 러닝             │
│                          │
│  언제 뛸까요              │
│ ┌──────────────────────┐ │
│ │  오늘  19:30      ▾  │ │  ← 분 단위 피커
│ └──────────────────────┘ │
│  지금부터 10분 뒤 ~ 23:59 │
│                          │
│  얼마나 뛸까요            │
│ ┌──────────────────────┐ │
│ │        5.0 km        │ │  ← 자유 입력
│ └──────────────────────┘ │
│ ┌───────┬───────┬──────┐ │
│ │  5km  │ 하프  │  풀  │ │  ← 세 칸 균등
│ └───────┴───────┴──────┘ │
│  1km ~ 42.195km          │
│                          │
│  ┌────────────────────┐  │
│  │     방 만들기       │  │
│  └────────────────────┘  │
└─────────────────────────┘
```

#### 바로가기는 `5km · 하프 · 풀` 셋이다

처음에는 매칭 등록의 `3km·5km·10km`를 그대로 가져왔는데, **그 셋이 존재하는
이유가 초대에는 없다.** `target_distance.dart`가 적어 둔 그대로다 — *"서버가 같은
조건끼리 묶어 방을 만들기 때문에, 값이 흩어지면 매칭될 상대가 없어진다."*
버킷 때문이고, 초대 방에는 버킷이 없다(상대를 직접 고른다).

게다가 같은 모양의 칩이 매칭에서는 **"선택지 전부"**, 초대에서는 **"바로가기"**
를 뜻하게 되어 사용자가 자유 입력인 줄 모를 수 있다.

그래서 **타자로 치기 고약하고 이름이 있는 거리**만 남긴다.

| 칩 | 보내는 값 |
|---|---|
| `5km` | `5000` |
| `하프` | `21098` |
| `풀` | `42195` |

⚠️ **하프는 21,097.5m라 정수가 아니다.** 서버가 정수 미터를 받으므로
**21,098m로 올린다.** 내리면 공인 거리보다 짧다. 화면에는 `21.1km`로 보인다.

칩은 자유 입력을 **대신하지 않는다** — 눌러서 입력란을 채운다. 셋 밖의 값을
넣으면 아무 칩도 선택되지 않는다.

**세 칸을 균등하게 깐다.** 왼쪽으로 쏠리면 오른쪽 빈자리가 "칩이 더 있는데
잘렸나"로 읽힌다. `Row` + `Expanded` 셋이고, 사이 간격은 `AppSpacing`이다.

`201`을 받으면 스트림을 연결하고 초대 방으로 간다. 실패는 409 우선순위대로
**한 가지만** 말한다 — `INVITE_START_AT_OUT_OF_RANGE` →
`RUNNING_ALREADY_IN_PROGRESS` → `ONBOARDING_NOT_COMPLETED`. 400
`INVALID_REQUEST`는 네 종류이고, 두 가지를 함께 위반하면 서버가 두 문장을
공백으로 이어 보낸다.

#### ⚠️ 23:49 이후에는 고를 수 있는 시각이 없다

아래가 **오늘 23:49 이후**에 교차한다 — 바닥(`지금 +10분`)이 천장(`오늘 23:59`)을
넘는다. 익일 예약은 안 된다.

빈 범위는 **실제로 생기는 상태**다. 피커를 비워 두지 않고 화면을 바꾼다 —
`오늘은 초대 러닝을 만들 수 없어요 · 자정이 지나면 다시 열려요`와 잠긴 CTA.
비어 있는 피커만 두면 고장으로 읽힌다.

#### 기기 시계를 믿지 않는다

이 화면은 앱이 **처음으로 `scheduledStartAt`을 직접 만드는 자리**다. 지금까지는
서버가 준 문자열을 되돌려 보냈을 뿐이다(`match_slot.dart`가 "다시 조립하지
않는다"고 못 박았다).

기기 시계가 몇 분 느리면 **화면에서 합법이었던 값이 서버에서
`INVITE_START_AT_OUT_OF_RANGE`로 튄다.** 그래서 바닥에 **1분 여유**를 둔다 —
피커의 최소값은 `지금 +11분`이다. 이 저장소는 다른 곳에서도 기기 시계를
의심한다(`RunningReady.startsInMs`, `MatchRoomState.launchAt`).

여유가 1분으로 충분한지는 **서버가 무엇을 기준으로 재는지에 달렸다**(§8-8).

### 4-3. 초대 방 — 매칭 방 안에서 분기한다

`match_room_page.dart`(454줄)의 조각들이 그대로 맞는다. `_Headline`(카운트다운·
인원) · `_SessionCards`(시각·거리·팀 페이스) · `_PartyCard`(참가자) · 나가기
버튼이 전부 `RoomInfo` 하나로 그려지고, 초대 방도 같은 `RoomInfo`를 받는다.
`_PartyCard` 같은 조각이 파일 안의 private 클래스라 **별도 페이지로 떼면 전부
복사**해야 한다. `room.type`으로 가른다.

바뀌는 것 넷.

1. **초대 버튼** — 정원이 남아 있고 모집 전(`status == MATCHING`)이면 그린다.
   누르면 §4-4 모달
2. **`invitations[]` 자리** — 빈 슬롯에 "초대 중 · 닉네임". 모집 마감 뒤에는
   `invitations`가 빈 배열로 와서 **초대 현황 자체를 안 그린다**
3. **나가기 안내 교체** — 초대 방은 제재가 없다. 지금 문구는 "확정 뒤에 나가면
   20분 동안 다시 신청할 수 없다"다. 초대 방에서는 그 줄을 빼고, 마지막
   사람이면 "방이 사라진다"를 대신 말한다
4. **확정 연출 제거** — `MATCH_STARTED`를 기다리지 않는다

수락·거절은 `invitations`와 `players`의 차이로 읽는다 — `invitations`에서
빠지고 `players`에 나타나면 수락, 둘 다 없으면 거절이다. **거절한 사람은 따로
표시하지 않는다.**

#### 아무도 수락하지 않으면 혼자 뛰게 된다

초대 취소가 없고(§7-2) `CANCELLED`도 안 오므로(§8-7), 아무도 수락하지 않은 방은
**마감되고 혼자 출발한다**(§8-9에서 확인 중). 매칭도 같다 — `isAlone`과
`home_solo_room.dart`가 이미 1인 확정을 다룬다.

문제는 **나갈 기회가 마감 전까지뿐**이라는 것이다. 마감되면 `status`가
`MATCHED`로 바뀌고 `RUNNING_READY`까지 간다.

그래서 혼자인 방에서 마감이 가까우면 대기 화면이 미리 말한다 —
`1분 뒤 모집이 닫혀요 · 혼자 달리게 됩니다`. 나가기 버튼은 이미 있다.
**이것이 창이 닫히기 전의 유일한 출구다.**

### 4-4. 친구 초대 모달

바텀시트다. 검색창 + 친구 목록 + 줄마다 `초대` 버튼.

```
┌─────────────────────────┐
│        ━━━               │
│  러너 초대               │
│ ┌──────────────────────┐ │
│ │ 🔍 닉네임 검색        │ │
│ └──────────────────────┘ │
│                          │
│ ◯ 철수            [초대] │
│ ◯ 영희            [초대] │
│ ◯ 민수          [초대 중]│  ← PENDING
│ ◯ 지훈          [참여 중]│  ← players
│                          │
│  남은 자리 2             │
└─────────────────────────┘
```

**한 번에 한 명씩 보낸다.** 서버가 `{ inviteeId }` 하나만 받는다. 그래서
다중 선택 + "초대하기" 한 방이 아니라 줄마다 버튼이다 — 결과도 한 줄씩
돌아온다.

목록은 `FriendRepository.friends()`, 검색은 `search(query:)`를 쓴다.
**친구별 "지금 초대 가능" 상태를 서버가 주지 않아서**(§8-4) 전원 멀쩡한 것처럼
그리고, 눌러서 실패를 알게 된다. 실패는 그 줄에 붙여 말한다 — 서버 `message`를
그대로 쓴다(명세가 그러라고 한다).

줄 상태 넷:

| 상태 | 버튼 | 근거 |
|---|---|---|
| 초대할 수 있다 | `초대` | |
| 이미 초대했다 | `초대 중`(잠김) | `RoomInfo.invitations`에 있다 |
| 이미 들어왔다 | `참여 중`(잠김) | `RoomInfo.players`에 있다 |
| 보냈다가 실패했다 | `다시 초대` + 실패 이유 | 409 `message` |

409 우선순위 — `RUNNING_INVITATION_CLOSED` → `NOT_FRIEND`(자신을 포함) →
`INVITEE_ALREADY_IN_ROOM` → `INVITEE_IN_MATCHING` → `INVITEE_RUNNING` →
`INVITE_COUNT_EXCEEDED`. `404`는 방 없음 · 초대 방 아님 · 내가 참가자 아님을
구분하지 않으니 한 문장으로 말한다.

**꽉 찬 방에도 초대는 보낼 수 있다** — 막히는 것은 수락이다. 그래도 "남은 자리
0"일 때는 버튼을 잠근다. 보내 봐야 상대가 `RUNNING_ROOM_FULL`을 맞는다.

**거절·이탈한 친구를 다시 초대할 수 있다.** 횟수는 이어서 센다 — 그 줄은
`초대`로 돌아온다.

#### ⚠️ 독촉은 이번에 내보내지 않는다

서버는 **`PENDING`인 사람에게 다시 보내는 것**(독촉)을 허용한다. 하지만 위 표가
그 사람의 버튼을 `초대 중`으로 잠그므로, **화면에서 독촉에 닿을 길이 없다.**
의도한 것이다.

남은 횟수를 알 수 없기 때문이다(§8-3). 독촉 버튼을 열면 사용자는 5회 상한이
보이지 않는 채로 누르다가 `INVITE_COUNT_EXCEEDED`를 맞는다 — 몇 번 남았는지
말해 줄 수 없으면서 누르라고 권하는 버튼이다. `invitations[]`에 남은 횟수가
생기면(§8-3) 잠긴 줄에 `다시 알림`을 붙인다.

그래서 5회 상한은 **거절·이탈한 사람을 다시 초대할 때만** 소진된다.

`friend_row.dart`의 `FriendRow`는 관계(`FriendRelation`)로 버튼을 가르는
위젯이다. 초대의 네 상태는 관계가 아니라 **방 안의 자리**라서, 재사용하지 않고
모달 안에 전용 줄을 만든다. 아바타는 `RunnerAvatarV2`를 쓴다.

### 4-5. 알림함 입구 — 프로필 상단, 설정 왼쪽

`profile_page.dart:120-134`의 `Positioned`가 커버 위에 설정 버튼 하나를 세운다.
그 자리를 `Row`로 바꿔 왼쪽에 벨을 더한다. `ProfileCoverAction`을 그대로 쓰면
어두운 원 + 아이콘이 똑같이 나온다. 아이콘은 `AppIcons.bell`(이미 있다).

안 읽은 알림이 있으면 벨 오른쪽 위에 빨간 점을 얹는다 — **숫자는 쓰지 않는다**.
배지 숫자는 서버와 어긋날 수 있다고 가이드가 직접 말하고(2-3), 어긋난 숫자는
틀린 숫자지만 점은 "있다/없다"만 말해서 틀릴 자리가 없다.

### 4-6. 알림함

```
┌─────────────────────────┐
│ ←  알림                  │
│                          │
│ ● ◯ 철수 님이 러닝에     │  ← ● = 안 읽음
│     초대했어요            │
│     오늘 19:30 · 5km     │
│     [거절]  [수락]        │
│ ─────────────────────── │
│   ◯ 영희 님이 친구 요청을 │
│     보냈어요              │
│     [거절]  [수락]        │
│ ─────────────────────── │
│   ◯ 민수 님과 친구가      │
│     되었어요              │
└─────────────────────────┘
```

**문구는 앱이 만든다** — 서버가 내려주지 않는다. `type`별로 한 줄씩 정한다.

| `type` | 문구 | 줄을 누르면 |
|---|---|---|
| `FRIEND_REQUESTED` | `{닉네임} 님이 친구 요청을 보냈어요` | 상대 프로필 |
| `FRIEND_ACCEPTED` | `{닉네임} 님과 친구가 되었어요` | 상대 프로필 |
| `RUNNING_INVITED` | `{닉네임} 님이 러닝에 초대했어요` | `invitation.status`별 |

버튼은 **지금 상태로 그린다.** 알림은 사건의 기록이고, `relationshipType`과
`invitation.status`는 조회 시점 값이다.

| 기준 | 버튼 |
|---|---|
| `actor.relationshipType == FRIEND_REQUEST_RECEIVED` | 친구 수락 · 거절 |
| `actor.relationshipType == null` (탈퇴) | **친구 버튼 전부 숨긴다** |
| `invitation.status == PENDING` | 러닝 수락 · 거절 |
| `ACCEPTED` | 버튼 없음, 누르면 초대 방 |
| `DECLINED` · `LEFT` | 버튼 없음, 상태만 |
| `EXPIRED` | 버튼 없음, "모집이 마감됐어요" |

탈퇴한 사람의 닉네임은 서버가 `"탈퇴한 사용자"`로, 사진은 `null`로 준다.
**목록에서 빼지 않는다.**

#### 수락을 누르면

수락은 `201 { runningRoomId }`이고 본문이 없다. **보낸 사람을 고르지 않는다** —
받는 사람은 토큰 주체다.

1. `POST .../invitations/accept`
2. `GET /users/me/status` 재조회 — `WAITING`·`INVITE`가 된다
3. 초대 방으로 이동. 매칭 스트림은 그 화면이 연결한다

**2번을 건너뛸 수 없다.** `match_room_provider.dart`는 `userStatusProvider`가
`WAITING`·`READY`를 말할 때만 스트림을 연다 — 상태를 새로 받지 않으면 방
화면이 빈 채로 선다.

이동은 **자동**이다. 수락하고 아무 일도 안 일어나면 눌렸는지 알 수 없다.
그래서 알림 쪽이 라우트를 밀게 되고, 그것이 §12의 `notification → matching`
의존이다.

거절은 `204`뿐이고 화면에 남는다 — 줄의 버튼만 사라진다. **마감과 상관없이
거절할 수 있고**, 보낸 사람이 여럿이어도 한 번에 모두 거절된다.

#### 실패하면

| 호출 | 409 우선순위 |
|---|---|
| 수락 | `RUNNING_INVITATION_CLOSED` → `RUNNING_INVITATION_NOT_PENDING` → `RUNNING_ROOM_FULL` → `RUNNING_ALREADY_IN_PROGRESS` → `ONBOARDING_NOT_COMPLETED` |
| 거절 | `RUNNING_INVITATION_NOT_PENDING` |

`RUNNING_ROOM_FULL`이면 **초대는 `PENDING`으로 남는다** — 자리가 생기면 다시
누를 수 있다. 그래서 이 하나만 버튼을 지우지 않는다.

실패는 **스낵바로 말하고 목록을 첫 페이지부터 재조회한다**(§5-2). 줄만 고치면
그 방의 다른 알림이 낡은 상태로 남는다 — 상태가 방 단위라서 한 줄만 맞추는
것은 맞춘 것이 아니다.

열면 **목록 조회 → 모두 읽음** 순서로 부른다. 바꾸면 응답에서 안 읽은 표시가
사라져 `●`를 그릴 수 없다. 모두 읽음이 성공하면 배지는 0으로 두고, 화면의 `●`는
그대로 남긴다 — 가이드가 의도된 동작이라고 못 박았다. 모두 읽음은 여러 번
불러도 `204`다.

페이지네이션은 **`nextCursor`가 `null`일 때만 끝난다.** 서버가 깨진 행을 건너뛰어
`items`가 20보다 적거나 비어 있어도 다음 페이지가 있을 수 있다. 개수로 판단하면
목록이 중간에 끊긴다.

**같은 `runningRoomId`의 알림은 함께 갱신한다.** A와 C가 각각 나를 같은 방에
초대하면 알림은 둘이고 `actor`도 다르지만 초대는 하나다. 하나를 수락하면 다른
줄의 버튼도 같이 사라져야 한다. 반대로 **알림 자체를 하나로 합치지는 않는다** —
재초대도 다른 참가자의 초대도 각각 목록에 남는다.

재초대하면 `DECLINED`·`LEFT`였던 초대가 **`PENDING`으로 돌아온다.** 그래서 같은
방의 **예전 알림에도 버튼이 다시 생긴다.**

보관은 30일이다(운영값). 지난 알림은 목록과 배지에서 사라진다.

### 4-7. 탭 바 — 프로필 탭에 빨간 점

안 읽은 알림이 있으면 하단 탭 바의 프로필 아이콘에 빨간 점을 얹는다.
알림함이 프로필 안에 있어서, 다른 탭에 있을 때 알려 줄 자리가 여기다.

`AppTabSpec`은 `static const` 목록이라 점 여부를 거기 담지 않는다.
`AppTabBarV2`가 `badges: Set<int>`를 따로 받아 그 인덱스에 점을 그린다.

⚠️ **탭 바에는 글자 라벨이 없다.** 스크린리더가 읽을 것이 `Semantics(label:)`
하나뿐이라, 점을 그림으로만 두면 **읽히지 않는다.** 점이 있으면 라벨을
`프로필, 읽지 않은 알림 있음`으로 바꾼다.

### 4-8. ⚠️ 홈 히어로가 초대 방을 "매칭 대기 중"이라고 말한다

놓치기 쉬운 자리다. 초대 방은 `push`로 열리므로 **뒤로 가면 홈 히어로가 선다**.
그리고 방을 만든 사람은 **최소 10분**을 기다린다 — 그 시간을 보내는 곳이 홈이다.

`home_hero.dart:118-127`이 `RoomStatus`만 보고 가른다.

```dart
if (current.status == RoomStatus.matched)  → HomeSoloRoom / HomeConfirmed
if (current.status == RoomStatus.matching) → HomeWaiting
```

초대 방도 같은 `status`로 오니 이 분기에 그대로 들어오는데, **문구가 매칭
전용이다.**

| 상수 | 지금 | 초대 방에서 틀린 이유 |
|---|---|---|
| `homeMatchWaitingTitle` | `매칭 대기 중` | 매칭하고 있지 않다 |
| `homeMatchWaitingAlone` | `아직 함께 달릴 러너를 찾고 있어요` | 찾는 게 아니라 **답을 기다린다** |
| `homeMatchSuccessSuffix` | `님과 매칭성공!` | 매칭이 아니라 수락이다 |
| `homeMatchConfirmedTitle` | `매칭 완료` | 모집 마감이다 |
| `homeMatchSoloTitle` | `혼자 달리게 됐어요` | 그대로 맞는다 |

**새 히어로 파일을 만들지 않는다.** 레이아웃은 같고 문구만 다르다 — 네 파일을
복제하면 매칭을 고칠 때마다 두 벌을 고쳐야 한다. 세 파일(`home_hero` ·
`home_waiting` · `home_confirmed`)이 `room.type`을 보고 문구를 고른다.

초대 쪽 문구는 이렇게 둔다.

| 자리 | 초대 방 |
|---|---|
| 대기 제목 | `초대 러닝 대기 중` |
| 혼자일 때 | `초대한 러너의 답을 기다리고 있어요` |
| 사람이 들어왔을 때 | `{닉네임} 님이 함께 뛰어요` |
| 마감 뒤 | `출발 준비 완료` |

### 4-9. `canStartSolo`가 초대 방을 솔로로 읽는다

`user_status.dart:48`이 `UserStatusReady(:final isSolo) => isSolo`다. 3-way로
바꿀 때 **`RoomType.solo`만 `true`**가 되어야 한다. `invite`를 `true`로 접으면
확정된 초대 방에서 홈이 "혼자 달리기" 버튼을 세운다.

---

## 5. 앱 스트림

### 5-1. 앱 시작 순서가 못 박혀 있다

| 순서 | 호출 |
|---|---|
| 1 | `GET /users/me` |
| 2 | `GET /users/me/status` |
| 3 | `GET /app/stream` |
| 4 | **스트림 200을 받은 뒤** `GET /users/me/notifications` |

**SSE → 목록 순서를 지킨다.** 목록을 먼저 받으면 그 사이에 생긴 알림을 실시간
으로도 못 받고 목록에도 없다. 스트림이 끝나기를 기다리는 것이 아니라 **200
응답**을 기다린다.

### 5-2. 버퍼·병합 규칙

목록 응답을 기다리는 동안 온 이벤트는 **화면에 바로 넣지 않는다.**

1. 임시 버퍼에 담는다. 버퍼 안에서도 같은 `notificationId`는 하나만
2. 목록이 오면 그것으로 목록을 세우고, 버퍼에서 **목록에 없는 것만** 맨 위에 더한다
3. 배지 = 목록의 `unreadCount` + 버퍼에서 새로 더한 수
4. 버퍼를 비우고 실시간 모드로. 이후 이벤트는 맨 위에 더하고 배지 +1,
   **이미 있는 `notificationId`면 무시**

`notificationId`는 `Long`이다 — 숫자로 비교한다. 문자열로 다루면
`"912"`와 `912`가 다른 알림이 된다.

목록 조회가 실패하면 **버퍼를 지우지 않고** 재시도한다. 지우면 그동안의 알림이
사라진다.

재조회는 **첫 페이지부터**다. 스크롤로 받아 둔 뒤쪽 페이지와 커서는 버리고,
새 응답의 `nextCursor`로 다시 시작한다. 연결이 살아 있으면 새 200을 기다리지
않고 버퍼 모드로 바꾼 뒤 바로 재조회한다.

### 5-3. 언제 열고, 언제 다시 여나

| 상황 | 처리 |
|---|---|
| 로그인 상태로 앱 진입 | 연결 |
| 포그라운드 복귀 | 끊겼으면 재연결. **연결 여부와 무관하게** 목록 재조회 |
| 30분 경과 | 서버가 끊는다 → 재연결 |
| 같은 계정으로 새 연결 | 끊길 수 있다. 다른 끊김과 구분하지 않는다 |
| 네트워크 단절 | 연결 상태를 확인하고 재연결 |
| 로그아웃 | 끊고 재연결 중단 |

**백오프를 넣는다.** 같은 서버에 붙은 두 기기가 서로의 연결을 끊을 수 있어서,
즉시 재연결을 무한 반복하면 두 기기가 서로를 밀어내며 돌게 된다.

계정 전체에 연결이 하나뿐이라고 **가정하지 않는다** — ALB 뒤에 여러 서버가
있어 두 기기가 모두 알림을 받을 수 있다.

스트림이 유지된 상태에서도 이벤트를 **놓칠 수 있다**(모바일 백그라운드, Redis
문제). 재연결만으로 놓친 이벤트가 다시 오지 않는다 — 복구는 목록 조회뿐이다.

### 5-4. `SseMatchStream`을 쓴다

`sse_match_stream.dart`가 `dart:io` `HttpClient`로 직접 짠 SSE다. `event:` ·
`data:` · 빈 줄만 읽고, 바이트 침묵을 감시해 조용히 죽는 연결을 잡는다.
**`EventSource`로는 못 싣는 헤더 세 개를 이 방식이 싣는다** — 가이드가 요구하는
그대로다(`Authorization` · `X-App-Version` · `X-App-Platform`).

매칭 스트림과 앱 스트림은 **별개 연결이고 동시에 유지한다.** 한쪽을 열었다고
다른 쪽을 닫으면 방에 있는 동안 알림을 못 받는다.

앱 스트림은 **404가 없다.** 매칭 스트림의 404(수락 전 연결)와 구분한다.

연결 직후 오는 `:connected`와 15초마다 오는 `:ping`은 SSE 주석이다. 알림으로
세지 않는다. 연결 직후 **스냅샷이 없다** — 매칭 스트림과 다른 점이다.
**모르는 `event`는 무시한다** — 스트림을 끊거나 알림 처리 전체를 실패시키지
않는다.

---

## 6. 우리 코드가 어긋난 곳

### 6-1. `RoomInfo`에 `type`과 `invitations`가 없다

`room_info.dart`의 `RoomInfo`가 일곱 필드를 든다. `type`(`MATCH`|`INVITE`)과
`invitations[]`를 더한다. `invitations` 원소는 `userId` · `nickname` ·
`profileImageUrl` · `isDeleted`로, `RoomPlayer`와 모양이 같지만 **페이스가 없다** —
아직 방에 없는 사람이다. `status`는 항상 `PENDING`이고 `isDeleted`는 항상
`false`라 들고 있을 이유가 없다.

`RoomStatus.of`처럼 **모르는 `type`은 `null`로 둔다.** 아무 값으로 뭉개면 초대
방을 매칭 방으로 그린다.

`closeAt` 주석의 "운영 오프셋(현재 10분)"도 고친다 — 초대 방은 1분이다.

### 6-2. `MatchEvent`에 초대 이벤트가 없다

`match_event.dart`의 `sealed class MatchEvent`에 `MatchStarted` ·
`MatchRoomUpdated` · `RunningReady` 셋뿐이다. **지금 앱은 초대 이벤트 둘을
조용히 버린다.**

`InviteRoomEntrance(room, startsInMs)`와 `InviteRoomUpdated(room)`을 더한다.
`INVITE_ROOM_ENTRANCE`는 `data`에 `RoomInfo`와 `startsInMs`를 **같은 깊이로**
싣는다 — 감싸지 않아서 기존 파서가 그대로 읽고 한 필드만 더 꺼낸다.

`startsInMs`는 **남은 시간 표시용**이다. 출발 타이머는 `RUNNING_READY.startsInMs`
그대로다.

**화면은 이벤트 이름이 아니라 `status`로 정한다.** 재연결하면 이미 시작한 방도
`INVITE_ROOM_ENTRANCE`로 온다.

### 6-3. `UserStatus`의 `isSolo`가 불린이다

`user_status.dart`의 하위 타입들이 `isSolo`를 불린으로 든다. 그래서
`http_user_status_repository.dart:56`이 이렇게 읽는다.

```dart
// ⚠️ `INVITE`는 미래 예약값이라 계약에 없다. 그래서 `SOLO`만 보고 가른다.
final isSolo = body?['type'] == 'SOLO';
```

**이 주석이 낡았다.** `INVITE`가 계약에 들어왔고 실제로 내려온다. 지금은 초대
방이 `isSolo: false`로 읽혀 **매칭 방 화면이 뜬다.**

불린을 3-way `RoomType { match, invite, solo }`로 바꾼다.

**`RoomInfo.fromStatus`를 같은 커밋에서 고친다.** 지금은
`UserStatusReady(isSolo: false)`와 `UserStatusRunning(isSolo: false)` 두 분기만
방을 세우고 나머지는 `null`이다. 3-way로 바꾸면서 `invite`를 빠뜨리면
`fromStatus`가 `null`을 주고, 홈은 `HomeIdle`을 그려 **초대 방에 들어가 있는
사람에게 "매칭 시작" 버튼**을 보여준다. 눌러도 409다. 지금 버그를 다른 막다른
길로 바꾸는 셈이라, 둘은 쪼갤 수 없다.

`canStartSolo`도 함께다(§4-9).

상태별 처리는 **매칭과 같다.** `type`만 보고 화면을 가른다.

| `status` | `type` | 처리 |
|---|---|---|
| `WAITING` | `INVITE` | 스트림 연결 → `INVITE_ROOM_ENTRANCE`로 대기 화면 |
| `READY` | `INVITE` | 연결 유지. 마감 뒤라 `invitations`는 빈 배열 |
| `RUNNING` | `INVITE` | 매칭과 동일 — WS → `RUNNING_START` |
| `IDLE` | — | **초대받기만 한 사람은 `IDLE`이다** |

`WAITING`이 유지되는 경계도 다르다 — 매칭 방은 시작 10분 전, 초대 방은 1분 전.
초대 방은 제재가 없어 **`cooldownUntil`이 생기지 않는다.**

### 6-4. ⚠️ 버전 헤더 정책이 앱 스트림에서만 다르다

`app_version_headers.dart`가 **"서버는 헤더가 없거나 형식이 틀리면 거절하지
않고 그대로 처리한다(공통 규칙)"** 를 전제로 서 있다. 그래서 버전을 못 읽으면
두 헤더를 **아예 안 싣는다**(빈 맵). `installed_app_version.dart`에 이유도 적혀
있다 — *"`null`을 `0.0.0`으로 눌러선 안 된다. 못 읽었을 뿐인 사용자를 영영
업데이트 화면에 가둔다."*

앱 스트림은 반대다. **헤더가 하나라도 없거나 형식이 틀리면 `403
APP_UPDATE_REQUIRED`**, 그것도 토큰 검사보다 먼저. 즉 `PackageInfo` 읽기가 실패한
기기는 **멀쩡한 최신 앱인데도 알림 스트림에서 영구히 업데이트 화면을 본다.**

막는 방법: 앱 스트림에서 `403 APP_UPDATE_REQUIRED`를 받았을 때
`InstalledAppVersion.current == null`이면 **업데이트 화면으로 보내지 않고**
알림만 포기한다. 버전을 못 읽은 것은 앱을 못 쓸 이유가 아니라는 기존 판단을
유지한다.

다만 **정책이 갈린 것 자체를 BE에 확인한다**(§8-1). 경로마다 규칙이 다르면
앞으로도 같은 함정을 반복한다.

`403`은 상태 코드만으로 판단하지 않는다 — 이메일 미동의 같은 다른 403이 있어서
응답 `code`가 `APP_UPDATE_REQUIRED`일 때만 업데이트 화면이다. `401`은 토큰을
갱신하고 재연결한다.

### 6-5. 프로필 요약의 `friendStatus`가 `relationshipType`으로 바뀐다

`http_profile_repository.dart:334`가 `body?['friendStatus']`를 읽는다. 필드명을
바꾼다. **값은 이미 호환된다** — `friend_relation.dart:46`이
`'FRIEND' || 'ACCEPTED'`를 둘 다 받는다.

이것으로 친구 설계 §2-1("관계를 부르는 말이 서버에 둘 있다")이 **해소된다.**
서버 어휘가 하나로 합쳐졌다. 읽는 쪽의 이중 어휘는 그대로 둔다 — 해롭지 않고,
구버전 서버와 섞이는 기간을 버틴다.

`friendCount`는 손댈 것이 없다(`:320`이 이미 응답값을 읽는다). 1.1.x에서
목값 42가 고정으로 오던 것이 실제 값으로 바뀔 뿐이다.

모르는 관계 값을 받아도 **화면이 죽지 않고, 버튼을 임의로 그리지도 않는다.**

### 6-6. 손댈 것이 없는 것

확인했고 **이미 반영돼 있다.**

- 슬롯 응답 `slots` → `distances[]`, `targetDistanceMeters` 쿼리 제거 —
  `slot_board_dto.dart`가 `distances`를 읽는다
- 경로 `/running-matches` → `/match-rooms`, `DELETE` → `POST /leave` — PR #224
- `unread-count` API 삭제 — 부르는 코드가 없다

---

## 7. 범위 밖

### 7-1. 푸시 알림

서버가 보내지 않고 앱에 FCM이 없다. **초대는 최소 10분 뒤 시작이라, 상대가 앱을
켜고 있지 않으면 거의 닿지 않는다.** 가이드도 "보낼 연결이 없다"고 인정하고,
놓친 것은 다음 진입 때 목록으로 받는다.

이 한계를 사용자에게 어떻게 말할지는 정하지 않았다 — 초대 모달에 "상대가 앱을
보고 있을 때 알림이 가요" 같은 줄을 둘지는 디자인 판단이다.

### 7-2. 초대 취소

엔드포인트가 없다(§8-2). 잘못 보낸 초대를 되돌릴 길이 **거절·만료뿐**이다.

### 7-3. C8 인앱 배너

정본에 규칙이 있지만(상단 슬라이드다운, 4.2초) **구현이 없다.**
`core/widgets/v2/`에 배너·토스트가 없다.

이번에는 만들지 않는다. 알림함과 빨간 점이 있으면 초대를 **볼 수는** 있다.
배너를 넣으면 "그때 보던 화면 위에 띄우고, 모달을 닫고 이동한다"는 규칙 때문에
러닝 중·카운트다운 중에 무엇을 하는지까지 정해야 하고, 그건 별도 작업이다.

### 7-4. 알림 항목별 읽음

서버가 지원하지 않는다. 모두 읽음만 있다.

---

## 8. 열려 있는 것 — BE·기획에 물을 것

### 8-1. 앱 스트림만 버전 헤더 누락을 거절하는 것이 의도인가

§6-4. 다른 경로의 공통 규칙("없으면 통과")과 어긋난다. 의도라면 앱이 우회를
넣고, 아니라면 서버가 공통 규칙으로 돌아오는 쪽이 낫다.

### 8-2. 초대 취소 API

기능정의서에 `INVITE-CANCEL-001 친구 초대 취소`가 있는데 **"엔드포인트: 🚧
확정 필요"** 로 남아 있고, 2차 API 명세에 없다.

### 8-3. 남은 독촉 횟수를 알 수 없다

한 친구에게 5회인데 `invitations[]`에 횟수가 없다. "보낸 사람별로 센다"라서
앱이 직접 셀 수도 없다 — 재시작하면 잃어버린다. 결국 **눌러 보고
`INVITE_COUNT_EXCEEDED`로 알아낸다.** `invitations[]`에 `sentCount`나
`remainingCount`가 있으면 버튼을 미리 잠글 수 있다.

### 8-4. 친구 목록에 그 친구의 지금 상태가 없다

초대 실패 사유가 5종인데 `FriendRepository.friends()`가 그 정보를 주지 않는다.
전원 멀쩡한 것처럼 그려 놓고 눌러서 실패를 보여주는 방식만 가능하다.

### 8-5. 운영값을 내려주는 API가 없다

§3-3의 다섯 개를 앱이 하드코딩한다. 서버에서 바뀌면 앱이 고를 수 없는 범위를
그린다. 매칭에는 `slots`가 선택지를 내려줬지만 초대에는 없다.

### 8-6. 초대받은 사람이 수락 전에 방 안을 못 본다

알림에 든 것은 초대한 사람 · 시각 · 거리뿐이고 수락 전에는 스트림이 404다.
**누가 있는 방인지 모르고 수락한다.** 의도인지 확인한다.

### 8-7. 서버가 `CANCELLED`를 보내지 않는다

명세에 `CANCELLED`가 있지만 "현재 서버는 보내지 않는다"고 적혀 있다. 마지막
사람이 나가 방이 사라져도 초대받은 쪽은 **수락을 눌러 409로 안다.**

### 8-8. `지금 +10분`을 무엇을 기준으로 재나

서버 수신 시각인지, 아니면 다른 기준인지. 수신 시각이면 기기 시계가 느릴 때
화면에서 합법이던 값이 거절된다 — 피커에 둔 1분 여유(§4-2)가 충분한지가
여기에 달렸다. 허용 오차가 있는지도 함께 묻는다.

### 8-9. 아무도 수락하지 않은 방이 혼자 시작하나

마감 시점에 1명이면 그대로 출발하는지, 아니면 방이 사라지는지. 매칭은 1인도
확정이라 같다고 보고 설계했지만(§4-3) 명세에 적혀 있지 않다. 사라진다면
`CANCELLED`가 필요하고(§8-7), 출발한다면 §4-3의 사전 경고가 유일한 출구다.

---

## 9. 내가 정한 것

디자이너 시안이 오면 갈아끼운다.

| 정한 것 | 왜 |
|---|---|
| 초대 등록을 별도 페이지로 | 입력이 겹치지 않는다. 707줄 안에서 두 모드가 엉키면 배포된 매칭이 위험하다(§4-2) |
| 초대 방은 매칭 방 안에서 분기 | `_PartyCard` 같은 조각이 파일 내부 private이라 떼면 전부 복사한다(§4-3) |
| 초대 모달은 줄마다 버튼 | 서버가 한 명씩만 받는다. 다중 선택은 결과를 한 줄씩 보여줄 수 없다(§4-4) |
| ~~거리 프리셋 3/5/10km~~ → `5km · 하프 · 풀` | 3/5/10은 매칭 **버킷** 때문에 있는 값이고 초대에는 버킷이 없다. 타자로 치기 고약하고 이름이 있는 거리만 남긴다(§4-2) — 개발자 확인 2026-10-29 |
| 하프를 21,098m로 올린다 | 21,097.5m는 정수가 아니다. 내리면 공인 거리보다 짧다(§4-2) |
| 배지에 숫자 대신 점 | 가이드가 숫자와 목록이 어긋날 수 있다고 직접 말한다. 점은 틀릴 자리가 없다(§4-5) |
| 점이 있으면 Semantics 라벨을 바꾼다 | 탭 바에 글자가 없어서 그림만으로는 안 읽힌다(§4-7) |
| `type`을 모르면 `null` | `RoomStatus.of`와 같은 판단. 뭉개면 초대 방을 매칭 방으로 그린다 |
| `notification`을 새 feature로 | 친구 알림도 같은 통로로 온다. `friend` 아래 두면 초대가 친구를 import한다 |
| C8 배너를 이번에 안 만든다 | 러닝 중·카운트다운 중 동작까지 정해야 해서 별도 작업이다(§7-3) |
| 403 우회로 알림만 포기 | 버전을 못 읽은 것은 앱을 못 쓸 이유가 아니다. 기존 판단을 유지한다(§6-4) |
| **독촉을 화면에 안 내보낸다** | 남은 횟수를 알 수 없어서, 몇 번 남았는지 못 말하면서 누르라고 권하는 버튼이 된다(§4-4) |
| **홈 히어로는 새 파일 없이 문구만 분기** | 레이아웃이 같다. 네 파일을 복제하면 매칭을 고칠 때마다 두 벌을 고친다(§4-8) |
| **수락하면 자동으로 방으로 이동** | 아무 일도 안 일어나면 눌렸는지 알 수 없다. 대신 상태 재조회가 먼저다(§4-6) |
| **23:49 이후는 전용 화면 + 피커 바닥에 1분 여유** | 빈 피커는 고장으로 읽힌다. 기기 시계를 믿지 않는 이 저장소의 관행을 따른다(§4-2) |
| **혼자인 방은 마감 전에 미리 경고** | 취소도 `CANCELLED`도 없어서, 마감 전 나가기가 유일한 출구다(§4-3) |
| 초대 REST를 `matching`에 남긴다 | `/match-rooms/…` 경로의 주인이 이미 `http_match_repository`다(§12) |

---

## 10. 개발자가 정한 것 (2026-10-29)

- 화면은 **매칭 러닝과 같다.** 다른 것은 초대 등록과 대기방뿐
- 매칭 등록·매칭 방 화면을 **그대로 쓰고** 친구 초대 모달을 더한다
- 알림함 입구는 **프로필 탭 상단, 설정 버튼 왼쪽에 벨**
- 안 읽은 알림이 있으면 **하단 탭 바 프로필 버튼에 빨간 점**

---

## 11. 테스트

CLAUDE.md가 셋만 쓴다고 했다 — 순수 계산 · 색 생성의 결정론성 · 상태 전이.
여기서는 첫째와 셋째다.

| 무엇 | 왜 |
|---|---|
| `RoomType.of` — 모르는 값이 `null` | 뭉개면 초대 방이 매칭 방으로 뜬다 |
| 초대 이벤트 파싱 — `startsInMs`가 같은 깊이 | 감싼 줄 알고 읽으면 남은 시간이 안 뜬다 |
| 알림 병합 — 같은 `notificationId`가 두 번 와도 한 번 | 배지가 목록과 어긋난다 |
| 알림 병합 — 배지 = `unreadCount` + 버퍼 신규분 | 가이드 1-1의 핵심 |
| `notificationId`를 숫자로 비교 | 문자열로 다루면 중복 제거가 깨진다 |
| 같은 `runningRoomId` 알림을 함께 갱신 | 한쪽만 바뀌면 죽은 버튼이 남는다 |
| 시작 시각 범위 — 경계 네 개 | 하드코딩한 운영값이라 경계가 틀리기 쉽다 |
| `UserStatus` 3-way 전이 | 지금 초대가 매칭으로 읽히는 버그의 회귀 테스트 |
| `nextCursor`가 `null`일 때만 종료 | `items` 개수로 끝내면 목록이 중간에 끊긴다 |
| `RoomInfo.fromStatus`가 초대도 세운다 | `null`이면 홈이 "매칭 시작"을 그린다(§6-3) |
| `canStartSolo` — `invite`는 `false` | `true`로 접으면 확정된 방에서 솔로 버튼이 뜬다(§4-9) |
| 23:49 이후 시작 시각 범위가 빈다 | 경계가 틀리면 고를 수 없는 시각을 권한다(§4-2) |
| `invitation == null`인 `FRIEND_*` 파싱 | 두 이벤트는 `null`로 온다. 필수로 읽으면 친구 알림이 통째로 깨진다 |

`test/home_page_test.dart:72-79`가 "준비 중"을 못 박고 있어 §4-1과 **같은
커밋에서** 고친다.

`dev`에 34개의 선행 실패가 있다(내가 만든 것이 아니다). 새 실패와 섞이지
않도록 묶음마다 기준선을 먼저 잡는다.

---

## 12. 파일

### 새로 만드는 것

```
lib/features/notification/
  domain/   app_notification.dart  notification_repository.dart
            app_stream_event.dart  app_stream.dart
  data/     http_notification_repository.dart  notification_dto.dart
            sse_app_stream.dart
  presentation/
            notification_page.dart  notification_provider.dart
            notification_row.dart

lib/features/matching/
  domain/   invite_limits.dart  room_invitation.dart
  presentation/
            invite_register_page.dart  invite_register_provider.dart
            invite_friend_sheet.dart
```

`notification`이 새 feature다. 친구 알림도 같은 통로로 와서 `friend` 아래
두면 초대가 친구를 import하게 된다.

#### feature 사이 의존

CLAUDE.md가 provider만 예외로 두고 **"한 방향으로만"**을 요구한다. 지금은
`onboarding · matching → session` 하나뿐인데, 이 작업이 네 개를 더한다.

| 방향 | 왜 |
|---|---|
| `notification → matching` | 알림 줄의 수락·거절이 초대 REST를 부르고, 수락 뒤 방으로 밀어 준다(§4-6) |
| `notification → friend` | 알림 줄의 친구 수락·거절 |
| `matching → friend` | 초대 모달이 친구 목록·검색을 쓴다 |
| `profile → notification` | 벨의 빨간 점 |

**순환이 없다** — `notification` → (`matching` → `friend`, `friend`),
`profile` → `notification`. Riverpod이 막지 않는다.

초대 REST를 `notification` 쪽으로 옮기지 않는다. `/match-rooms/…` 경로이고
`http_match_repository.dart`가 이미 그 경로의 주인이다. 옮기면 같은 서버 자원을
두 repository가 부르게 된다.

### 손보는 것

| 파일 | 무엇 |
|---|---|
| `matching/domain/room_info.dart` | `type` · `invitations` 추가, `closeAt` 주석 |
| `matching/domain/match_event.dart` | 초대 이벤트 2종 |
| `matching/data/sse_match_stream.dart` | 초대 이벤트 파싱 |
| `matching/presentation/match_room_page.dart` | `type` 분기, 초대 버튼, 안내 문구 |
| `matching/presentation/match_room_provider.dart` | 초대 이벤트 반영 |
| `matching/data/http_match_repository.dart` | 초대 REST 4개 |
| `session/domain/user_status.dart` | `isSolo` → `RoomType`, `canStartSolo` |
| `home/presentation/home_hero.dart` | `type`별 문구 분기 |
| `home/presentation/home_waiting.dart` | 초대 문구 |
| `home/presentation/home_confirmed.dart` | 초대 문구 |
| `session/data/http_user_status_repository.dart` | 낡은 주석과 함께 3-way |
| `profile/data/http_profile_repository.dart` | `friendStatus` → `relationshipType` |
| `profile/presentation/profile_page.dart` | 벨 추가 |
| `core/widgets/v2/app_tab_bar.dart` | `badges` 받기, Semantics 라벨 |
| `app/router/app_shell.dart` | 앱 스트림 구독, 탭 점 |
| `app/router/app_routes.dart` | 알림함 · 초대 등록 |
| `core/strings/app_strings.dart` | 문구 |
| `home/presentation/home_page.dart` | 초대 칸 연결 |

앱 스트림은 **셸 레이어에서 구독한다.** `app_shell.dart` 주석이 적어 둔 규칙
그대로다 — 안 보이는 탭의 provider는 dispose되므로, 전역 연결을 화면 provider에
두면 탭을 옮기는 순간 끊긴다.

---

## 13. 작업 순서

PR 하나에 파일 20개 / 500줄이 상한이라 다섯으로 가른다.

| | 묶음 | 왜 이 순서 |
|---|---|---|
| 1 | **계약 맞추기** — `RoomInfo` · `MatchEvent` · `UserStatus`(+`fromStatus`·`canStartSolo`) · `relationshipType` | 없으면 나머지가 다 어긋난다 |
| 2 | **앱 스트림 + 알림 저장소** — 연결 · 버퍼 · 목록 · 모두 읽음 | 화면 없이 테스트할 수 있는 부분이 여기 다 있다 |
| 3 | **알림함 + 배지** — 화면 · 벨 · 탭 점 | 2 없이는 그릴 것이 없다 |
| 4 | **초대 방** — 분기 · 초대 모달 · 홈 히어로 문구 | 1이 필요하다. 히어로는 방 화면과 같은 문구 묶음이다 |
| 5 | **초대 등록** — 자유 시각 · 거리 | 4가 있어야 개설 뒤에 갈 곳이 있다 |

⚠️ **1번만으로 초대 방이 제대로 뜨지는 않는다.** 1번은 `type`을 **읽을 수 있게**
만들 뿐이고, 그것으로 고쳐지는 것은 "초대 방이 매칭 방으로 복구되던" 것까지다.
문구는 매칭 것이 그대로 나온다(§4-8) — 그 교정은 4번이다. 1번에서
`fromStatus`를 빠뜨리면 버그가 고쳐지는 게 아니라 **"매칭 시작" 버튼이 뜨는
다른 막다른 길로 바뀐다**(§6-3).

4·5는 **`INVITE_ROOM_ENTRANCE`·`INVITE_ROOM_UPDATED`가 BE 개발중**이라, 그
둘이 끝나기 전에는 가짜 스트림으로만 확인한다. 1~3은 지금 바로 실제 서버로
확인할 수 있다.

확인 시나리오는 가이드 4절을 쓴다 — 계정 둘(일부는 셋)로 친구 요청 → 알림함 →
수락 → 초대 → 재초대 → 수락·입장 → 앱 미접속 중 알림 순이다.
