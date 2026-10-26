# 매칭 슬롯 — 거리·시간 한 번에 받기 (설계)

> 대상 API: `GET /api/v1/running-matches/slots` (1차 명세 **No 16**, BE 개발완료 · FE 개발전)
> 바뀌는 화면: 매칭 등록(**S08**) · 시간 선택 시트
> 나가는 버전: **1.1.2** — 앞선 1.1.1(버전 메타·SDK)이 **심사 중이라 머지 시점이 묶인다**(2절)
> 앞선 설계: [`2026-10-22-match-slot-waiting-count-design.md`](2026-10-22-match-slot-waiting-count-design.md) — **이 문서가 그것을 대체한다.**

---

## 1. 무엇이 바뀌었나

API가 바뀌었다. 전에는 **거리를 필수로 받아 그 거리의 시간대만** 돌려줬다. 이제는 **날짜만 받고
모든 거리 × 모든 시간대를 한 번에** 돌려준다.

```
전   GET /slots?targetDistanceMeters=5000   →  { slots: [ … ] }
후   GET /slots                             →  { distances: [ { targetDistanceMeters, slots: [ … ] } ] }
```

그래서 **거리를 고를 때마다 다시 묻던 왕복이 통째로 없어진다.** 지금 코드에서 가장 복잡한 부분이
그 왕복을 둘러싼 것들이었다 — 거리를 안 골랐는데 마감 여부를 알아야 해서 아무 거리로 한 번 묻던
`probeToday`, 거리를 바꾸는 동안 옛 숫자가 새 이름에 붙지 않게 목록을 비우던 절차, 같은 거리를
다시 눌러 경합이 나던 자리(`_loadToken`). **그 전제가 사라지면 셋 다 같이 사라진다.**

---

## 2. ⚠️ 이 변경은 이미 배포된 1.1.0을 깨뜨린다

**이것이 이 작업의 일정을 정한다.** 구현보다 먼저 읽어야 한다.

운영에 나가 있는 1.1.0은 `targetDistanceMeters`를 쿼리로 보내고 응답의 **`body['slots']`**를 읽는다
(`http_match_repository.dart`). 새 응답에는 `slots` 키가 없다. 그러면

1. `matchSlotsFromJson`이 **빈 목록**을 돌려준다 — 예외가 아니라 정상 응답으로 읽힌다
2. `slotsReady`가 거짓이라 **시간 선택기가 열리지 않는다**
3. `closedForToday`는 `slots.isNotEmpty`를 보므로 **거짓** — 마감 팝업조차 안 뜬다

결과는 **오류 하나 없이 아무것도 못 하는 화면**이다. 사용자는 거리를 고르고 시간을 누를 수 없는
채로 멈춘다. 무엇이 잘못됐는지 알 길이 없고, 다시 시도 버튼도 안 붙는다.

### 그래서 배포 순서가 정해져 있다

| | 순서 | 비고 |
|---|---|---|
| 가장 안전 | 서버가 **옛 요청에 옛 응답**을 주는 호환 기간을 둔다 → 앱 배포 → 스토어 반영 확인 → 서버 정리 | 백엔드에 요청해야 한다 |
| 차선 | 앱을 먼저 내고 **스토어 반영을 확인한 뒤** 서버를 올린다 | 강제 업데이트가 아니라 **구버전이 남는다** — 아래 참고 |
| 안 됨 | 서버를 먼저 올린다 | 올린 순간부터 1.1.0 사용자는 매칭을 못 한다 |

### ⚠️ 1.1.1 심사가 끝나기 전에는 `main`에 머지할 수 없다

이 작업은 **1.1.2**로 나간다. 그 앞에 **1.1.1**(버전 메타·SDK만 붙인 것)이 출시 검사에 들어가 있다.

`docs/release.md`가 적어 둔 대로, **검토 중인 변경사항이 있을 때 `main`에 머지하면 내부 테스트
업로드만으로 진행 중인 심사가 취소되고 다시 제출된다.** Play API의 기본 동작이고, 업로드 액션은
이를 바꾸는 옵션을 넘기지 않는다.

그래서 순서가 이렇게 묶인다.

```
1.1.1 심사 제출 ──────────────── 승인·출시
                                      │
        1.1.2 작업 → dev → release/1.1.2 ─┴─→ main → Prod Release
                                      ↑
                        여기를 넘기 전에는 머지하지 않는다
```

**코드는 그 전에 다 끝내 둔다.** `dev`까지는 자유롭게 머지하고, `release/1.1.2`를 잘라 두고 기다린다.
기다리는 동안 1.1.1이 승인되면 그때 `main` PR을 연다.

⚠️ **백엔드가 그 사이에 서버를 올리면 운영이 깨진 채로 기다리게 된다.** 2절의 "가장 안전" 경로를
받아내는 것이 그래서 더 중요하다 — 심사 일정은 우리가 정하지 못한다.

⚠️ **스토어 반영 확인이 끝이 아니다.** 앱은 자동 업데이트가 아니므로 구버전을 쓰는 사람이 남는다.
앱에 `X-App-Version` 기반 업데이트 게이트가 이미 있으므로(`lib/features/app_update/`), 서버가
최소 버전을 올려 **구버전을 업데이트 화면으로 보내는 것**이 실질적인 마무리다.

**백엔드에 물어볼 것 — 이 API가 운영에 언제 올라가는가, 호환 기간을 둘 수 있는가.** 답에 따라 이
작업이 평상시 릴리스가 되거나 `hotfix/*`가 된다. 코드는 어느 쪽이든 같다.

---

## 3. 결정한 것

| | 결정 | 정한 사람 |
|---|---|---|
| 화면 순서 | **시간 → 거리.** 2026-10-22에 뒤집었던 것을 되돌린다 | 사용자 |
| 시간 시트의 숫자 | 그 시각의 **모든 거리 합계** | 사용자 |
| 등록 버튼의 숫자 | 둘 다 고른 뒤, **그 시각 × 그 거리**의 수 | 사용자 |
| 거리 선택지의 출처 | **응답.** 앱이 목록을 갖지 않는다 | 사용자 (명세 요구) |
| `TargetDistance` enum | **남긴다 — 표시 이름을 찾는 데만.** 선택지의 출처로 쓰지 않는다 | 설계 (4절) |
| 0명일 때 | **아무것도 안 그린다** — 시트 줄도, 버튼도 | 앞선 설계에서 이어받음 |
| 조회 시점 | **진입에 한 번.** 거리를 바꿔도 다시 묻지 않는다 | 명세 요구 |
| 거리를 먼저 고를 수 있나 | **그렇다. 잠그지 않는다** (5-3) | 설계 |
| 갱신 주기 | **없다.** 폴링도 WebSocket도 아니다 | 앞선 설계에서 이어받음 |
| `date` 파라미터 | **안 보낸다** — 오늘뿐이고, 보내면 형식 오류로 400을 자초한다 | 설계 |
| 운영 안내·마감 팝업 | **그대로 둔다.** 이번 변경과 무관하다 | 설계 |

---

## 4. 거리 선택지는 응답이 정한다

명세가 못 박았다.

> **거리 목록과 시간대의 범위·간격은 서버 설정값입니다.** 앱에서 하드코딩하지 말고, 이 응답을
> 선택지로 사용해 주세요. 매칭 신청에서 허용하는 선택지와 동일합니다.

지금 앱은 `TargetDistance.values`(km3·km5·km10)로 칩을 그린다. **그것이 선택지의 출처다.** 서버가
7km를 추가하면 앱을 다시 내기 전까지 아무도 고를 수 없다.

### 그러나 enum을 지우지는 않는다

`TargetDistance.fromMeters(meters)?.km`가 **네 화면에서 표시용으로** 쓰인다 — 홈의 확정 카드·솔로
방, 카운트다운, 대기방. 전부 서버가 준 미터값을 사람이 읽는 `5km`로 바꾸는 일이다. 그 역할은
그대로 둔다.

없애는 것은 **선택지의 출처로 쓰는 것 하나**다.

| | 전 | 후 |
|---|---|---|
| 칩 목록 | `TargetDistance.values` | 응답의 `distances` 순서 그대로 |
| 고른 값 | `TargetDistance` | `int meters` |
| 신청 요청 | `distance.meters` | 고른 `meters` 그대로 |
| 칩 글자 | `matchDistanceText(distance.km)` | 아는 값이면 같은 문구, 모르면 미터에서 환산 |

그래서 `MatchRepository.apply`의 인자가 `TargetDistance`에서 `int meters`로 바뀐다. 번지는 자리는
저장소 인터페이스·HTTP 구현·가짜 저장소·컨트롤러와 그 테스트까지다. **표시용 네 화면은 손대지
않는다.**

---

## 5. 화면

### 5-1. 순서를 되돌린다

```
오늘 언제 뛸까요?      ← 시간 선택기 (진입 조회가 끝나면 바로 열린다)
  [ 18:30 ]
목표 거리
  [ 3km ] [ 5km ] [ 10km ]      ← 응답이 만든다
  …
[ 매칭 등록하기 · 3명 대기 ]     ← 둘 다 고르면 숫자가 붙는다
```

2026-10-22에 거리를 위로 올린 이유는 **조회가 거리를 필수로 받았기 때문**이다. 거리를 모르면 시간
목록을 받을 수 없어서 순서가 강제됐다. 그 제약이 사라졌으므로 시안의 순서로 돌아간다.

### 5-2. 숫자가 서는 자리 둘

| 자리 | 언제 | 무엇을 |
|---|---|---|
| 시간 시트의 각 줄 | 시트를 열 때 | 그 시각의 **모든 거리 합계** |
| 등록 버튼 | 시간·거리를 **둘 다** 고른 뒤 | 그 **시각 × 거리**의 수 |

전 설계에 있던 **등록 버튼 위의 줄(`matchWaitingTotal`)은 없어진다.** 거리만 골랐을 때 그 거리의
모든 시각 합을 보여주던 자리인데, 이제 거리를 먼저 고르는 흐름이 아니다.

⚠️ **0이면 아무것도 안 그린다.** `0명 대기`는 비어 있다고 알리는 꼴이라 오히려 사람을 민다. 버튼은
`매칭 등록하기`로 남는다.

### 5-3. 거리를 먼저 골라도 된다

한 번에 다 받으므로 **잠글 이유가 없다.** 시간을 고르기 전에 거리를 눌러도 되고, 그 반대도 된다.
등록 버튼만 둘 다 골라야 열린다.

그래서 `matchSlotsLockedByDistance`(`거리를 먼저 골라주세요`)가 **죽는다.**

### 5-4. 시간 시트의 합계가 뜻하는 것

⚠️ **명세는 거리가 다르면 같은 방에 매칭되지 않는다고 못 박았다.** 그래서 `18:30에 5명`이 실제로는
3km 3명 + 10km 2명일 수 있고, **그 다섯이 서로 만나지는 않는다.**

사용자가 정한 것이라 그대로 간다. 다만 문구가 "이 시간에 5명이 함께 뛴다"로 읽히지 않게 둔다 —
기존 `matchWaitingCount`(`N명 대기`)를 그대로 쓰고, 합계라는 말을 덧붙이지 않는다. 거리를 고르면
버튼의 숫자가 **진짜 그 조건의 수**로 바뀌면서 저절로 좁혀진다.

리뷰에서 다시 볼 자리로 남긴다.

### 5-5. 마감된 시각

목록에서 빼지 않고 잠근다(기존과 같다). 명세가 **시작 시각이 같으면 거리가 달라도 `selectable`이
같다**고 했으므로, 시간 시트의 잠금은 그 시각 아무 거리의 `selectable`이면 된다. 그래도 앱은
**합집합으로 읽는다** — 하나라도 고를 수 있으면 열어 둔다. 서버가 전제를 깨도 고를 수 있는 것을
막지는 않게 된다.

등록 버튼은 **고른 시각 × 고른 거리**의 `selectable`로 잠근다.

---

## 6. 상태

### 6-1. 새 모양

```dart
/// 한 거리의 시간대 묶음.
class DistanceSlots {
  final int meters;
  final List<MatchSlot> slots;   // scheduledStartAt 오름차순
}

/// 응답 전체. 거리 × 시간의 판이다.
class SlotBoard {
  final List<DistanceSlots> distances;   // targetDistanceMeters 오름차순

  List<SlotTime> get times;                           // 시각 합집합
  MatchSlot? at({required String raw, required int meters});
}

/// 시간 선택기의 한 줄. **거리와 무관하다.**
class SlotTime {
  final String raw;          // 신청에 그대로 실린다
  final DateTime startAt;    // 표시 전용
  final int waitingTotal;    // 모든 거리 합
  final bool selectable;     // 아무 거리나 하나라도
}
```

`MatchSlot`은 그대로 둔다 — `raw` · `startAt` · `waitingCount` · `selectable`. 한 거리의 한 시각을
뜻하는 것은 변함이 없다. **`closed()`는 죽는다**(7-2).

### 6-2. `MatchRegisterState`

| 필드 | 전 | 후 |
|---|---|---|
| 목록 | `List<MatchSlot> slots` | `SlotBoard? board` |
| 고른 시간 | `MatchSlot? selected` | `SlotTime? time` |
| 고른 거리 | `TargetDistance? distance` | `int? meters` |
| 파생 | `slotsReady` `waitingTotal` `openSlots` `closedForToday` | `slotsReady` `openTimes` `closedForToday` `pickedWaiting` |

`waitingTotal`(한 거리의 전 시각 합)이 죽고, `pickedWaiting`(고른 시각 × 고른 거리)이 생긴다.

---

## 7. 조회

### 7-1. 진입에 한 번

```
화면 진입 → reset() → load()
```

`probeToday`가 죽는다. "거리를 안 골랐는데 어떻게 묻나"라는 질문 자체가 사라졌다.
`selectDistance`는 **서버를 부르지 않는 순수한 선택**이 된다.

`_loadToken`은 **남긴다.** 조회 실패 뒤 `다시 시도`를 연타할 수 있고, 그때 늦게 온 실패가 먼저 온
성공을 덮는 경합은 그대로다.

### 7-2. 거리를 바꿔도 다시 묻지 않는다

받아 둔 판에서 꺼내 쓴다. 그래서 **거리를 바꾸는 동안 옛 숫자가 새 이름에 붙던 문제가 구조적으로
사라진다** — 숫자가 한 판에서 같이 오므로 어긋날 틈이 없다.

`_applySlots`가 고른 시간을 새 목록의 같은 `raw`로 갈아 끼우던 절차도 함께 죽는다. 고른 시간은
`SlotTime`이고 판이 바뀌지 않으니 갈아 끼울 일이 없다.

`MatchSlot.closed()`도 죽는다. 신청이 `MATCH_SLOT_CLOSED`를 받으면 **판을 다시 받는다**(기존
`_reloadAfterClosed`와 같다) — 한 번에 다 받으므로 한 줄만 잠그는 것보다 다시 받는 쪽이 싸고 정확하다.

### 7-3. 실패는 그대로

`SlotLoadFailure` 네 갈래(`network` · `sessionExpired` · `invalidRequest` · `unknown`)와 별도 필드에
담는 규칙을 그대로 쓴다. 400은 이제 **날짜 형식**일 때만 나는데, 앱이 `date`를 안 보내므로 정상
경로에서는 나오지 않는다 — 나오면 앱 규칙이 서버와 어긋났다는 신호라 로그로 남긴다.

---

## 8. 코드가 움직이는 자리

### 새로 생기는 것

| 파일 | 무엇 |
|---|---|
| `domain/slot_board.dart` | `SlotBoard` · `DistanceSlots` · `SlotTime` |
| `data/slot_board_dto.dart` | `slotBoardFromJson` — `distances[].slots[]`를 읽는다 |

### 고치는 것

| 파일 | 무엇 |
|---|---|
| `data/http_match_repository.dart` | `slots()`에서 거리 쿼리를 뺀다 · `apply`가 미터를 받는다 |
| `data/fake_match_repository.dart` | 기본 판을 거리 3 × 시각 9로 |
| `domain/match_repository.dart` | `slots()` 반환형 · `apply` 인자 |
| `presentation/match_register_provider.dart` | `probeToday`·`_applySlots` 삭제, `load()` 하나로 |
| `presentation/match_register_page.dart` | 순서 되돌림 · 칩을 응답에서 · 버튼에 숫자 |
| `core/strings/app_strings.dart` | 버튼 문구 하나 추가, `matchSlotsLockedByDistance`·`matchWaitingTotal` 삭제 |

### 죽는 것

- `slot_dto.dart`의 `matchSlotsFromJson` — `slot_board_dto.dart`가 대신한다
- `MatchSlot.closed()`
- `MatchRegisterState.waitingTotal` · `openSlots`
- `AppStrings.matchSlotsLockedByDistance` · `matchWaitingTotal`

### 손대지 않는 것

- 표시용으로 `TargetDistance.fromMeters`를 쓰는 네 화면
- 운영 안내 팝업 셋(`matchPolicy*` · `matchSlotClosed*` · `matchCooldown*`)
- `KstTime.parse`로 시각을 읽는 규칙 — **`DateTime.parse` 금지**는 그대로다

---

## 9. 테스트

### 새로 쓰는 것

| 무엇 | 왜 |
|---|---|
| `distances[]`를 읽는다 | 응답 모양이 통째로 바뀌었다 |
| 거리 한 줄이 깨져도 나머지를 준다 | 한 줄 때문에 화면이 멈추면 안 된다 |
| 시각 합집합이 오름차순이다 | 시트 순서가 그것으로 정해진다 |
| 시각별 합계가 모든 거리를 더한다 | 사용자가 정한 핵심 동작 |
| `selectable`은 **하나라도 되면** 열린다 | 5-5 |
| 요청에 `targetDistanceMeters`가 없다 | 명세가 받지 않는다 |
| 거리를 바꿔도 **다시 묻지 않는다** | 왕복이 사라진 것이 이번 변경의 핵심 |
| 거리를 먼저 골라도 된다 | 5-3 |
| 모르는 거리도 칩이 선다 | 4절 — 하드코딩하지 않는다는 증거 |
| 둘 다 고르면 버튼에 그 조건의 수가 붙는다 | 사용자가 정한 핵심 동작 |
| 0이면 버튼에 숫자가 없다 | 0은 안 그린다 |

### 깨지는 테스트

`match_slots_repository_test` · `match_slot_dto_test` · `match_slots_state_test` · `match_register_test`.
전부 **거리를 쿼리로 보내는 것**과 **`{slots: []}` 응답**을 전제로 쓰여 있다. 고치는 것이 아니라
새 전제로 다시 쓴다.

---

## 10. 열린 질문

1. **이 API가 운영에 언제 올라가는가.** 백엔드 확인이 필요하다(2절). 답이 배포 경로를 정한다.
2. **호환 기간을 둘 수 있는가.** `targetDistanceMeters`가 오면 옛 응답을 주는 식이면 가장 안전하다.
   **1.1.1 심사 때문에 우리 쪽 머지 시점이 묶여 있어**(2절) 이 답이 특히 중요하다.
3. **시간 시트의 거리 무관 합계를 그대로 둘 것인가**(5-4). 사용자가 정한 것이지만, 만나지 않는
   사람을 한 줄에 더해 보여주는 것이라 리뷰에서 다시 본다.
