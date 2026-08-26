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
| `RUNNING_LOCATION_UPDATE` | WS | ❌ 개발전 |
| `RUNNING_PAUSE` / `RUNNING_RESUME` | WS | ❌ 개발전 |
| `RUNNING_FINISH` / `RUNNING_FINISHED` | WS | ❌ 개발전 |
| 기록 목록·상세 (#19·#20) | REST | ❌ 개발전 |

**연결·인증·헬스체크까지는 오늘 실제로 검증할 수 있다.** 나머지는 계약대로 만들어
두고 서버를 기다린다.

---

## 3. 단계

```
1. WS 연결 · 인증 · 헬스체크        ← 서버 준비됨. 이번 범위
2. 솔로 방 생성 (POST .../solo)     ← 서버 준비됨. 이번 범위
─────────────────────────────────  이번 PR은 여기까지
3. 로컬 트랙 저장 (sqflite)         ← 재전송 요구사항
4. 좌표 배치 전송 (10초)            ← 서버 개발전
5. 케이던스 (pedometer)             ← 실기기 필요
6. 종료 · ack 후 트랙 삭제          ← 서버 개발전
```

**3~6은 지금 만들어도 검증할 수 없다.** 서버가 없으면 "보냈다"까지만 확인되고
받는 쪽이 무엇이라 답하는지 모른다. 명세가 바뀌면 통째로 다시 짜게 된다.

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

성격이 "기록"이 아니라 **재전송 버퍼**이므로 스키마가 단순하다.

```
run_track_points
  running_room_id, sequence   (복합 유니크)
  latitude, longitude, altitude_meters, accuracy_meters
  speed_meters_per_second, heading_degrees, cadence_spm
  current_pace_seconds_per_km, recorded_at
```

`RUNNING_FINISHED` ack를 받으면 **그 방의 행을 전부 지운다.** 남겨두면 기록이
두 벌이 되고, 1절에서 정한 원칙에 어긋난다.

⚠️ 앱이 죽었다 살아나도 트랙이 남아야 재전송이 된다. 메모리로는 안 되고
`sqflite`가 필요하다. 패키지는 그때 승인받는다.

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
