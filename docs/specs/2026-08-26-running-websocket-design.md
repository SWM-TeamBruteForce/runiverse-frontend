# 러닝 실시간 통신 (WebSocket) 설계

1인 러닝을 서버에 연결한다. 좌표를 보내고, 서버가 기록을 만든다.

---

## 1. ⚠️ 전제가 바뀌었다 — 기록의 원본은 서버다

**이 절이 이 문서에서 가장 중요하다.** 앞선 설계 논의에서 "로컬 DB에 기록을 저장한다"고
잡았는데, **틀린 전제였다.** 명세를 다시 읽고 바로잡는다.

> **3차 변경사항** — 러닝 기록 저장 주체를 명확히 했다: 거리·페이스·구간 분할을
> **서버가 받은 좌표로 계산**한다. 클라 계산값은 러닝 중 화면 표시용이다.

> **RUNNING_FINISH** — 마지막 수신 트랙으로 거리·페이스·구간·칼로리·고도 지표를
> 계산한다. 기록·splits·S3 GPS 트랙·`route_polyline`을 만들고…

> **`running_records.running_room_id`** — `NOT NULL`. 솔로도 방을 가지므로 항상 값 존재

그래서 **클라이언트가 하지 않는 일**이 분명해졌다.

| 하지 않는다 | 이유 |
|---|---|
| 구간(splits) 분할 | 서버가 트랙으로 계산한다 |
| `route_polyline` 인코딩 | 서버가 만든다 |
| 칼로리 계산 | 서버가 종료 시 계산한다 |
| 기록을 로컬에 영구 보관 | 서버가 원본이다. 두 벌이면 반드시 어긋난다 |

클라이언트가 계산하는 거리·페이스·케이던스는 **러닝 중 화면에 띄우기 위한 것**이고,
기록으로 남는 값이 아니다. 화면 숫자와 나중에 보는 기록이 미세하게 다를 수 있다 —
이는 결함이 아니라 설계다.

### 로컬 저장은 남는다. 다만 성격이 다르다

저장하는 것은 "기록"이 아니라 **아직 서버가 받았는지 모르는 좌표 트랙**이다.
그리고 이것은 WS 프로토콜이 직접 요구한다.

> 재연결 시 로컬 트랙 전체를 첫 `sequence`부터 다시 보내며, 서버는
> `(runningRoomId, userId, sequence)`가 같은 좌표를 무시한다.
> 로컬 트랙은 `RUNNING_FINISHED` ack 뒤 삭제한다.

**즉 로컬 DB는 WebSocket의 상위 작업이 아니라 하위 작업이다.** 순서가 뒤집혀 있었다.

---

## 2. 서버 배포 현황 — 지금 붙일 수 있는 것

| 항목 | 채널 | BE 현황 |
|---|---|---|
| `POST /api/v1/running-rooms/solo` | REST | ✅ **개발완료** |
| `HEALTH_CHECK` / `HEALTH_CHECKED` | WS | ✅ **개발완료** |
| `RUNNING_START` / `RUNNING_STARTED` | WS | 🟡 개발중 |
| `RUNNING_LOCATION_UPDATE` | WS | ✅ **개발완료** (2026-08-27 백엔드 확인. Notion은 아직 `개발전`) |
| `RUNNING_PAUSE` / `RUNNING_RESUME` | WS | ❌ 개발전 |
| `RUNNING_FINISH` / `RUNNING_FINISHED` | WS | ❌ 개발전 |
| 기록 목록·상세 (#19·#20) | REST | ❌ 개발전 |

**연결·인증·헬스체크까지는 오늘 실제로 검증할 수 있다.** 나머지는 계약대로 만들어
두고 서버를 기다린다.

---

## 3. 단계

```
1. WS 연결 · 인증 · 헬스체크        ✅ 완료 · dev 서버로 검증
2. 솔로 방 생성 (POST .../solo)     ✅ 완료 · dev 서버로 검증
3. 로컬 트랙 저장 (sqflite)         ✅ 완료 · 기기에서 검증
4. 좌표 배치 전송 (10초)            ✅ 완료 · ⚠️ 서버로 검증 못 함
─────────────────────────────────  여기까지 만들었다
5. 케이던스 (pedometer)             ← 실기기 필요
6. 종료 · ack 후 트랙 삭제          ← 서버 개발전
```

⚠️ **4단계는 아직 서버로 검증하지 못했다.** 이 계정에 끝나지 않은 방이 남아
`POST /running-rooms/solo`가 409를 준다(4절). 방을 만들 수 없으니 좌표를 실제로
보내볼 수도 없다. **방이 풀리는 대로 확인한다.**

⚠️ **6단계가 없어 방을 끝낼 방법이 앱에 없다.** `RUNNING_FINISH`와
`DELETE /users/me/running-match`가 둘 다 `개발전`이라, 한 번 방을 만든 계정은
다음 러닝을 시작하지 못한다. **이것이 지금 가장 급한 백엔드 의존이다.**

---

## 4. 이번 범위 (1~2)

### 흐름

```
홈 · 혼자 달리기
      ↓
POST /api/v1/running-rooms/solo   → runningRoomId
      ↓
wss://.../api/v1/ws/running       + Authorization: Bearer
      ↓
연결 유지 (HEALTH_CHECK 주기 전송)
      ↓
출발 준비 화면 (GPS 신호 대기 — 이미 있다)
```

**방을 먼저 만들고 WS를 연결한다.** `runningRoomId`가 이후 모든 메시지의 payload에
들어가므로 순서가 뒤바뀔 수 없다.

### 연결 규칙 (명세에서 그대로 온 것)

- **인증**: 핸드셰이크에서 `Authorization: Bearer {accessToken}` 한 번만 검증한다.
  연결 중 만료만으로 끊기지 않는다.
- **401이면** `POST /auth/refresh` 후 재연결. 다시 실패하면 재로그인.
- **중복 연결**: 같은 사용자의 마지막 연결만 유지된다. 새 연결이 오면 서버가 기존
  연결을 close code **`4001`**로 닫는다.
  ⚠️ **`4001`을 받으면 재연결하지 않는다.** 다른 기기에서 접속했다는 뜻이고,
  재연결하면 두 기기가 서로를 끊는 무한 루프가 된다.
- **헬스체크**: 클라이언트가 `HEALTH_CHECK`(`data={}`), 서버가 `HEALTH_CHECKED`.
  유휴가 운영 설정을 넘으면 서버가 닫는다. 주기는 운영값이라 **상수로 두되
  서버와 맞춰야 한다.**

### 메시지 봉투

```json
{ "event": "...", "data": { ... } }
```

키는 `event`다. `type`이 아니다 — 2차 명세와 다르니 옛 문서를 보지 않는다.

### 오류

`ERROR` 7종: `MALFORMED_MESSAGE` · `MISSING_MESSAGE_TYPE` ·
`UNSUPPORTED_MESSAGE_TYPE` · `INVALID_REQUEST` · `ROOM_NOT_FOUND` ·
`NOT_ROOM_PLAYER` · `INVALID_ROOM_STATE`

**오류를 받아도 연결은 유지된다.** 끊고 재연결하면 안 된다.

### 솔로 방 생성 실패

`409 RUNNING_ALREADY_IN_PROGRESS` — 이미 진행 중인 매칭이 있다. 앱은 새 러닝을
시작할 수 없고, 진행 중인 것으로 안내해야 한다.

### 방 생성이 실패하면 — 재시도하며 달린다

실패 원인은 넷이고, 셋은 재시도로 풀린다.

| 원인 | 재시도로 풀리나 |
|---|---|
| 네트워크 일시 불안정 (지하철·엘리베이터·터널) | ✅ 몇 초면 대개 성공 |
| 401 토큰 만료 | ✅ 갱신 후 재시도 — 저장소가 이미 한다 |
| 5xx | 🟡 서버가 살아나면 |
| **409 이미 진행 중** | ❌ 몇 번을 눌러도 같은 답 |

**409만 멈추고 나머지는 달리면서 재시도한다.** 한 번 실패했다고 러닝을 막으면
신호가 잠깐 없는 곳에서 아예 못 뛰게 된다. 방이 늦게라도 생기면 그때부터
좌표가 올라간다.

⚠️ **409는 실제로 자주 날 것이다.** 러닝 중 앱이 죽으면 서버에 `STARTED` 방이
남고, 다음 러닝에서 409를 맞는다. 그래서 "다시 시도" 버튼을 주지 않는다 —
사용자가 이전 러닝을 정리해야 풀린다. `GET /users/me/running-match`로 진행 중인
것을 조회할 수 있으니, 이어서·종료하기를 제안하는 화면이 나중에 여기 붙는다.

### ⚠️ 러닝 내내 오프라인은 MVP 밖이다

방만 만들어지면 그 뒤로는 완전히 오프라인을 견딘다 — WS가 끊겨도 좌표는 로컬에
쌓이고 재연결하면 `sequence`로 중복을 걸러가며 올라간다.

**막히는 것은 `runningRoomId` 하나다.** 서버 DB의 PK(Long)라 클라가 만들 수 없고,
WS의 모든 메시지 payload에 들어간다. 방 번호 없이는 보낼 수 있는 메시지가 없다.

산속·지하처럼 **러닝 내내 오프라인**이면 방을 못 만든다. "번호 없이 쌓아뒀다가
나중에 몰아서 보내기"는 기술적으로 가능하지만 **서버 계약이 그 흐름을 상정하지
않았다**:

- `RUNNING_START`가 방을 `STARTED`로 바꾸는데, 그 시점엔 러닝이 이미 끝나 있다
- 종료 타임아웃이 "마지막 좌표 수신 시각 기준"이라 몰아서 보내면 이상하게 돈다
- `recordedAt`이 과거 시각인 것을 서버가 받아주는지 명세에 없다

**MVP 밖으로 둔다.** 필요해지면 8절 ⑥으로 백엔드에 묻고, 답이 온 뒤에 만든다.
추측으로 만들면 서버가 거절할 때 통째로 다시 짜게 된다.

### 계층

```
lib/core/network/
  ws_client.dart            연결·재연결·헬스체크. 메시지 내용을 모른다
  ws_message.dart           봉투(event + data) 직렬화

lib/features/session/
  domain/
    running_room.dart       runningRoomId를 담는 값
    running_room_repository.dart
    running_channel.dart    러닝 메시지 인터페이스 (연결·시작·좌표·종료)
  data/
    http_running_room_repository.dart
    ws_running_channel.dart  ws_client 위에 러닝 계약을 얹는다
```

**`ws_client`는 러닝을 모른다.** 매칭 SSE·알림 등 다른 채널이 생겨도 재사용한다.
러닝 계약은 `ws_running_channel`에만 있다.

### 새 패키지

**`web_socket_channel`** — Dart 팀이 관리한다. `IOWebSocketChannel.connect`가
헤더를 받아 핸드셰이크에 `Authorization`을 실을 수 있다.

대안인 `stomp_dart_client`는 쓰지 않는다. 서버가 STOMP가 아니라 **평문 JSON 봉투**를
쓴다(`{event, data}`). STOMP 프레이밍이 필요 없다.

---

## 5. 안드로이드에서 수집할 수 있는 값

`RUNNING_LOCATION_UPDATE`의 필드 9개 중 **8개는 이미 가진 것에서 나온다.**

| 페이로드 필드 | 출처 | 상태 |
|---|---|---|
| `sequence` | 클라 카운터 | ✅ |
| `latitude` · `longitude` | `Position` | ✅ |
| `altitudeMeters` | `Position.altitude` | ✅ nullable 표기와 맞음 |
| `accuracyMeters` | `Position.accuracy` | ✅ |
| `speedMetersPerSecond` | `Position.speed` | ✅ |
| `headingDegrees` | `Position.heading` | ⚠️ 8절 ① |
| `cadenceSpm` | 걸음 센서 (`pedometer`) | ⚠️ 아래 |
| `currentPaceSecondsPerKm` | `PaceCalculator` (이미 있다) | ✅ |
| `recordedAt` | `Position.timestamp` | ⚠️ 형식 변환 |

`Position`은 이 밖에 `speedAccuracy` · `altitudeAccuracy` · `floor` · **`isMocked`**도
준다. `isMocked`는 모의 위치 앱으로 달린 척하는 것을 잡을 수 있어, 부정 방지가
필요해지면 쓸 자리가 있다.

**수집 주기는 이미 맞는다.** `AndroidSettings(intervalDuration: 1초, distanceFilter: 0)`
으로 설정돼 있어 명세의 "1~2초 간격"에 부합한다.

### 케이던스만 새 센서가 필요하다

안드로이드 걸음 센서는 둘이다.

- **`TYPE_STEP_DETECTOR`** — 걸음마다 이벤트. 케이던스 계산에 맞다
- **`TYPE_STEP_COUNTER`** — 부팅 이후 누적. 배터리는 좋지만 최대 수 초 지연

`cadence = 최근 N초 걸음 수 × 60/N`으로 낸다. Flutter에서는 `pedometer` 패키지가
둘 다 노출한다. **`ACTIVITY_RECOGNITION` 권한이 필요하다**(API 29+) — 위치와 별개로
하나 더 물어야 한다.

⚠️ **에뮬레이터에는 걸음 센서가 없다.** 케이던스는 실기기로만 검증된다.

### `recordedAt` 형식 함정

서버는 오프셋 없는 KST(`yyyy-MM-ddTHH:mm:ss`)를 받는다.
`DateTime.toIso8601String()`은 마이크로초를 붙이고 UTC면 `Z`가 붙어 **형식이 다르다.**
변환 함수를 하나 두고 거기서만 만든다.

---

## 6. 로컬 트랙 (3단계, 이번 범위 밖)

성격이 "기록"이 아니라 **재전송 버퍼**다.

### 무엇을 계산해서 보내는가

**클라이언트는 좌표만 보낸다.** 명세의 페이로드 필드가 10개뿐이고, 그 안에
누적거리·경사·칼로리 자리가 없다.

| 값 | 페이로드 | 누가 만드나 |
|---|---|---|
| 페이스 | ✅ `currentPaceSecondsPerKm` (좌표마다) | **클라 계산** |
| 케이던스 | ✅ `cadenceSpm` (좌표마다) | **클라 계산** (걸음 센서) |
| 고도 | ✅ `altitudeMeters` (그 지점의 원본) | 기기 GPS |
| 방향 | ✅ `headingDegrees` | 기기 센서 |
| 속도 | ✅ `speedMetersPerSecond` | 기기 GPS |
| **누적거리** | ❌ 없음 | 서버가 좌표로 계산 |
| **경사·누적상승** | ❌ 없음 | 서버가 고도로 계산 |
| **칼로리** | ❌ 없음 | 서버가 종료 시 계산 |
| **경과시간** | ❌ 없음 | 서버가 `recordedAt` 차이로 계산 |

⚠️ **클라도 거리·시간을 계산하지만 그것은 화면 표시용이다.** 명세가
*"클라 계산값은 러닝 중 화면 표시용이다"*라고 못박았다. 그래서 **러닝 중 화면
숫자와 나중에 보는 기록이 미세하게 다를 수 있다** — 결함이 아니라 설계다.

지표를 클라가 보내는 안(필드 추가 요청)도 검토했으나 택하지 않았다.
**클라가 보낸 값은 조작할 수 있고**, 기기마다 계산이 다르면 기록 일관성이
깨진다. 서버가 원본 트랙을 가지므로 언제든 재계산할 수 있다.

경사와 칼로리는 어느 쪽을 택하든 **지금 클라가 제대로 낼 수 없다**:
- 경사 — `Position.altitude`는 오차가 흔히 ±10~20m다. 평지에서도 오르내리는
  것처럼 찍혀 경사가 튄다. 제대로 하려면 기압계(`TYPE_PRESSURE`)가 필요한데
  모든 기기에 있지 않다. 서버가 `totalElevationGainMeters`를 nullable로 둔
  이유로 보인다
- 칼로리 — 체중이 필요한데 `GET /users/me/profile`이 `개발전`이라 앱을 껐다
  켜면 모른다. `ProfileBody`가 메모리에만 들고 있다

### 스키마

```sql
CREATE TABLE run_track_points (
  running_room_id  INTEGER NOT NULL,
  sequence         INTEGER NOT NULL,
  latitude         REAL    NOT NULL,
  longitude        REAL    NOT NULL,
  altitude_meters  REAL,              -- nullable (명세 표기)
  accuracy_meters  REAL    NOT NULL,
  speed_mps        REAL    NOT NULL,
  heading_degrees  REAL,              -- nullable ← 8절 ①
  cadence_spm      INTEGER,           -- nullable ← 8절 ②
  pace_sec_per_km  INTEGER,           -- 러닝 초반에는 낼 수 없다
  recorded_at      TEXT    NOT NULL,  -- 'yyyy-MM-ddTHH:mm:ss'
  PRIMARY KEY (running_room_id, sequence)
);
```

**컬럼이 페이로드와 1:1이다.** 재전송할 때 변환 없이 그대로 실어 보낸다.
중간 형식을 두면 저장할 때와 보낼 때 값이 갈릴 자리가 생긴다.

**복합 PK `(running_room_id, sequence)`** — 서버의 중복 제거 키와 같다.
같은 좌표를 두 번 넣으려 하면 DB가 막고, 순서대로 읽는 인덱스도 함께 얻는다.

**"보냈음" 플래그가 없다.** 어디까지 보냈는지는 **메모리에만** 든다(아래).
컬럼을 두면 "보냈다고 표시됐는데 서버는 못 받은" 상태가 남는다.

**테이블은 하나뿐이다.** "러닝 세션" 테이블을 따로 둘까 고민했으나 뺐다 —
앱이 죽어도 `running_room_id`는 트랙 행에서 복구되고, 트랙이 비어 있는 경우
(방만 만들고 바로 죽음)는 `GET /users/me/running-match`로 알 수 있다.

### 페이로드 — `runningRoomId`는 여기 없다

```json
{ "locations": [ { "sequence": 15, "latitude": ..., "longitude": ...,
    "altitudeMeters": 18.4, "accuracyMeters": 6.2,
    "speedMetersPerSecond": 2.8, "headingDegrees": 85.3,
    "cadenceSpm": 165, "currentPaceSecondsPerKm": 345,
    "recordedAt": "2026-07-25T19:10:30" } ] }
```

**방 번호는 `RUNNING_START`에서 한 번만 보낸다.** 서버가 WS 세션(사용자 →
활성 방)에서 알아낸다. 로컬 DB에는 그래도 `running_room_id`를 남긴다 —
ack 후 어느 행을 지울지, 이전 러닝 트랙이 섞이지 않게 하는 데 필요하다.

⚠️ **`recordedAt` 변환이 함정이다.** `Position.timestamp`는 **UTC로 온다.**
`.toLocal()`을 거치지 않으면 9시간 어긋난 기록이 쌓이는데, **에러가 나지 않아
한참 뒤에 발견된다.** `toIso8601String()`도 쓸 수 없다 — 마이크로초와 `Z`가
붙어 서버 형식과 다르다. 변환 함수를 하나 두고 거기서만 만든다.

### `headingDegrees` — 음수나 0이면 0으로 보낸다

`Position.heading`은 방향을 못 잴 때(정지·저속) 음수나 0을 준다. 명세는
`0~360`이고 nullable 표기가 없어 **`0`으로 눌러 보낸다.**

⚠️ **0은 "정북"이라는 뜻이라 엄밀히는 거짓이다.** 서버가 방향을 어디에 쓰는지
확정되면(8절 ①) 바뀔 수 있어, 판단을 **함수 하나에 모아 둔다.**

### 쓰고 읽는 주기

```
1초마다   좌표 수신 → 페이스·방향을 함께 계산 → 한 행 저장
10초마다  _lastSent 이후 최대 200행을 읽어 전송 → _lastSent 갱신
재연결    _lastSent - 겹침(30점 ≈ 30초) 부터 다시 보낸다
ack 받으면 DELETE WHERE running_room_id = ?
```

### ⚠️ 재전송은 전체가 아니라 겹쳐서 이어붙인다

명세는 *"첫 `sequence`부터 다시 보낸다"*지만 **전체를 보내지 않는다.**

명세가 전체를 택한 이유는 `RUNNING_LOCATION_UPDATE`에 **ack가 없어서**
클라가 서버 수신 지점을 모르기 때문이다. 그런데 클라가 아는 것이 하나 있다 —
**소켓에 넘긴 시점**이다. WebSocket은 TCP 위에 있어 **연결이 살아 있는 동안
넘긴 데이터는 사실상 도착한다.** 유실 위험은 끊기던 순간 날아가던 것뿐이고,
그 크기는 마지막 한두 배치다.

그래서 `_lastSent`에서 **30초(30점)를 물러서서** 다시 보낸다. 서버가
`sequence`로 중복을 거르므로 겹치는 것은 공짜고, 전송량은 1,800점이 아니라 30점이다.

⚠️ **겹침을 줄이면 안 된다.** 좌표가 비면 서버가 그 구간을 직선으로 잇고
**거리가 실제보다 짧게 계산된다.** 사용자가 뛴 만큼 기록이 안 나오는 것은
되돌릴 수 없다.

**8절 ③이 해결되면 정확해진다.** `RUNNING_STARTED` ack에 서버가 마지막 수신
`sequence`를 실어 주면 추측 없이 그 지점부터 보낸다. **그 값이 오면 쓰고
없으면 겹침으로 가는 구조**로 만든다.

`_lastSent`는 **메모리에만** 둔다. 재연결은 `WsClient`가 처리하므로 컨트롤러가
살아 있다. 앱이 통째로 죽는 경우는 러닝 자체가 사라지는 별개 문제(4절 409)다.

**페이스·케이던스를 저장 시점에 계산해 박아 둔다.** 전송 시점에 계산하면
재전송할 때마다 다시 계산해야 하고, 그때는 이미 지나간 시점의 페이스를
재현해야 한다. 저장할 때 박아두면 재전송이 **읽어서 보내기**로 끝난다.

수집 주기는 **1초**다(명세 `1~2초` 중 빠른 쪽). 30분에 1,800행 ≈ 300KB.

2초로 늘렸다가 되돌렸다. 이유가 둘이고 **둘 다 거리를 짧게 만드는 방향**이다.

- **곡선에서 거리가 깎인다.** 점 사이를 직선으로 이으므로 간격이 길수록 굽은
  길에서 짧게 나온다. GPS 잡음은 반대로 거리를 부풀리지만 **그쪽은 칼만 필터가
  잡고, 곡선 손실은 보정할 방법이 없다**
- **칼만 `Q`가 간격을 모른다.** 간격이 두 배면 그사이 실제 이동도 두 배인데
  `Q`는 그대로라, 필터가 자기 예측을 과신해 경로가 안쪽으로 깎인다

⚠️ **주기를 다시 바꾸면 `Q`를 함께 봐야 한다.** `LocationSmoother`의 `Q`는
여전히 간격을 모른다.

---

## 7. 이번 범위의 테스트

서버가 준비된 구간이라 실제로 검증할 수 있다.

- **연결 상태 전이** — 끊김 → 재연결, `4001`을 받으면 재연결하지 않는가
- **헬스체크** — 주기마다 보내는가, 응답이 없으면 어떻게 되는가
- **방 생성 실패** — `409`일 때 러닝을 시작하지 않는가

⚠️ `ws_client` 테스트에는 가짜 채널이 필요하다. `web_socket_channel`의
`StreamChannel`을 인터페이스로 두고 테스트에서 갈아 끼운다.

---

## 8. 백엔드에 물어볼 것

**① `headingDegrees`가 0~360을 보장할 수 없다**

geolocator는 방향을 못 잴 때(정지 상태가 대표적) `0` 또는 **음수**를 준다.
명세는 `0~360`이고 nullable 표기가 없다. 음수일 때 `null`을 허용할지, `0`으로
눌러 보낼지 정해야 한다.

**② `cadenceSpm`의 nullable 여부가 명시되지 않았다**

페이로드에 `165`로 있고 nullable 표기는 `altitudeMeters`에만 붙어 있다. 그런데
권한 거부·센서 없음·러닝 초반(표본 부족)에는 낼 수 없다. **기록 상세(#20)의
`averageCadenceSpm`은 nullable**이라 앞뒤가 맞지 않는다.

**③ 재연결 시 "전체 재전송"이 무겁다**

30분 러닝이면 좌표 ~1800개다. **ack가 없어 서버가 어디까지 받았는지 알 방법이 없고**,
지하철·터널로 재연결이 반복되면 매번 전체를 다시 보낸다.
서버가 마지막 `sequence`를 `RUNNING_STARTED` ack에 실어 주면 그 뒤부터만 보낼 수 있다.

**④ 일시정지 중 `sequence`가 어떻게 되는지 불명확하다**

`RUNNING_PAUSE`는 좌표 전송을 멈추라고 한다. 그동안 번호를 건너뛰는지, 재개 시
이어붙이는지 — 서버가 `(roomId, userId, sequence)`로 중복을 거르므로 빈 구간이
있어도 되는지 확인이 필요하다.

**⑥ 사후 업로드를 받아줄 수 있는가** `[MVP 제외]`

러닝 내내 오프라인이었던 경우(산속·지하), 끝난 뒤 방을 만들고 쌓아둔 좌표를
몰아서 보내는 흐름이다. 위 4절에 적은 세 가지 이유로 현재 계약과 맞지 않는다.
**지금 필요한 것은 아니고, 오프라인 러닝을 지원하기로 정할 때 묻는다.**

### 명세 자체에 이미 적혀 있는 미확정 사항

3차 WEBSOCKET 명세서가 스스로 "정합성 확인 필요"로 남긴 것들이다. 그중 솔로에
영향을 주는 것:

- **솔로 목표 거리** — 솔로 개시 API는 목표 거리를 받지 않고 방의
  `target_distance=null`이라는데, `running_players.target_distance`는 `NOT NULL`이고
  종료 계약(`totalDistanceMeters / targetDistanceMeters` 비율로 페널티 판정)은
  목표 거리를 전제한다. **솔로는 목표가 없는데 무엇과 비교하는가.**
- **재연결 참가자 판정** — `RUNNING_START`는 이미 `RUNNING`인 참가자의 재연결을
  허용하지만, '활성 신청' 정의는 `status='JOINED'`라 용어가 충돌한다.

---

## 9. 참고

- 3차 WEBSOCKET 명세서 (정본)
- `RUNNING_START` · `RUNNING_LOCATION_UPDATE` · `RUNNING_FINISH` 메시지 상세
- 4차 API 명세서 #16 `POST /running-rooms/solo`, #19·#20 기록 조회
- `docs/specs/2026-08-05-solo-run-design.md` — 화면과 GPS 보정
