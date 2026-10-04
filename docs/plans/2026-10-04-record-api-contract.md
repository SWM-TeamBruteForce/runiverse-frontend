# 기록 API 계약 맞추기 — 실행 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 바뀐 기록 목록 API에 앱을 맞추고, 지금 쌓이고 있는 잘못된 고도 데이터를 멈춘다.

**Architecture:** UI 교체가 **아니다.** 화면은 건드리지 않고 `data/`·`domain/`만 고친다. 이 둘이 끝나야 기록 탭이 데이터를 읽고, 그래야 다음 묶음(UI 교체)에서 새 디자인을 **눈으로 확인할 수 있다.**

**Tech Stack:** Flutter (fvm) · flutter_test · dio

**근거 문서:**
- 📅 [기록 탭 연동 가이드](https://app.notion.com/p/3ebae181f710813884bde0d76fefcf45) — 요청·응답·값 다루기
- [[기록 목록] 기간 조회 API 연동](https://app.notion.com/p/3ecae181f71081d7a1efe4582e616b8d) — 바뀐 것과 할 것 (2026-10-01, 상태 **검토 전**)

**다음 묶음:** `docs/plans/2026-10-04-ui-redesign-record.md` (기록·설정 UI 교체). **이 계획이 먼저다.**

## Global Constraints

- 모든 flutter/dart 명령은 `.\.fvm\flutter_sdk\bin\flutter.bat` / `dart.bat` 으로 직접 부른다.
- 모든 커밋 시점에 `analyze` 경고 **0개**, `test` **전체 통과**(현재 1,022개).
- 커밋 메시지 `<이모지> <Type>: <설명>`. **AI를 공동 작성자로 넣지 않는다.**
- base는 `dev`. 앞 PR이 머지된 뒤 `upstream/dev`에서 새로 딴다.
- **화면 파일을 건드리지 않는다.** 이 계획은 `data/`·`domain/`과 그 테스트까지다.
- 우리에게 없는 값을 **지어내지 않는다.**
- ⚠️ **확인이 끝나면 임시 경로를 되돌리고 깨끗한 빌드를 다시 설치한다.**

---

## ⚠️ 지금 무슨 일이 일어나고 있나

### 1. 기록 탭이 서버 응답을 못 읽는다

목록 API가 **이미 바뀌어 테스트 서버에 배포됐다**(BE PR #72).

| | 우리 코드 | 지금 서버 |
|---|---|---|
| 응답 키 | `json['items']` · `json['nextCursor']` | **`runningRecords[]`** · 페이지 없음 |
| 조회 | `?cursor=&limit=` + `?from=&to=` | **`?from=&to=` 하나만** |
| 정렬 | 최신순 | **시작 시각 오름차순** |
| 새 필드 | — | `type` · `playerCount` · `totalElevationGainMeters` |
| 기록 상세(옛 20번) | — | **삭제됨** |

`run_record_dto.dart:15`가 `json['items']`를 읽는다. **빈 목록으로 떨어진다.**

### 2. ⚠️ 잘못된 고도가 지금도 쌓이고 있다

> 안드로이드가 고도를 못 구하면 **0.0을 보냅니다.** 앱이 그대로 전송해 서버는 실제 고도로 계산합니다. **기록은 저장 후 고치지 않아 그대로 남습니다.** — 이슈 ⚠️ 주의

`geolocator_location_repository.dart:206`이 `altitude: position.altitude`로 거르지 않고 싣는다.

**UI 교체와 무관하게 급하다** — 고치기 전까지의 기록은 되돌릴 수 없다.

### 3. 주 시작 요일이 한 탭 안에서 둘이다

| | 기준 |
|---|---|
| `record_calendar.dart:148` | **일요일** |
| `record_summary.dart:125` `weekOf` | **월요일** |

→ **이 계획에서는 안 고친다.** 다음 묶음이 월 달력을 **시안의 가로 주간 스트립으로 갈아치우므로**(`158:3793`) 일요일 기준이 그때 사라진다. 시안의 주간 차트도 월요일 시작이라 **`weekOf`는 그대로 두면 맞는다.**

⚠️ 가이드 4장은 **일요일을 권한다.** 근거는 "월 달력과 같은 기준"인데 그 달력이 사라지므로 전제가 바뀐다. **PR에 적어 확인받는다.**

---

## Task 1: 고도 0을 보내지 않는다

⚠️ **먼저 한다.** 이것만 UI·API와 무관하고, 늦을수록 잘못된 기록이 쌓인다.

**Files:**
- Modify: `lib/features/session/data/geolocator_location_repository.dart`
- Test: `test/geolocator_altitude_test.dart` (신설)

- [ ] **Step 1: `upstream/dev`에서 딴다**

```bash
git fetch upstream
git checkout -b fix/altitude-zero upstream/dev
```

- [ ] **Step 2: 거르는 규칙을 순수 함수로 뺀다**

위젯도 플랫폼도 없이 시험할 수 있어야 한다.

```dart
/// 고도를 믿을 수 있는가.
///
/// ⚠️ **안드로이드는 못 구하면 `0.0`을 준다.** 그대로 보내면 서버가 그것을
/// 실제 고도로 보고 누적 상승을 계산하고, **기록은 저장 뒤에 고치지 않는다.**
/// 못 재는 기기는 0 m 가 되고, 간헐적으로 섞이면 오히려 부풀려진다.
static double? altitudeOrNull(double altitude, double accuracy) {
  if (accuracy < 0) return null;
  if (altitude == 0.0 && accuracy == 0.0) return null;
  return altitude;
}
```

- [ ] **Step 3: 테스트를 쓴다**

```dart
test('⚠️ 정확도가 음수면 버린다', ...);
test('⚠️ 고도와 정확도가 둘 다 0이면 버린다', ...);
test('진짜 해수면 높이(0 m)는 정확도가 있으면 살린다', ...);
test('평범한 값은 그대로 통과한다', ...);
```

⚠️ **세 번째가 핵심이다.** `altitude == 0`만 보고 버리면 **실제로 해발 0 m 인 곳**에서 달린 기록을 잃는다. 정확도까지 함께 봐야 하는 이유다.

- [ ] **Step 4: 부른 자리를 바꾼다** (`:206`)

- [ ] **Step 5: 일부러 부순다** — 규칙을 `return altitude;` 한 줄로 되돌려 넷 중 둘이 빨개지는지 본다

- [ ] **Step 6: 검증하고 커밋·PR**

**💬 리뷰 포인트에 적을 것:** 이미 저장된 기록은 **고쳐지지 않는다.** 서버 쪽에서 과거 데이터를 어떻게 할지 백엔드와 정해야 한다.

---

## Task 2: 목록 API 계약을 맞춘다

**Files:**
- Modify: `lib/features/record/data/run_record_dto.dart`
- Modify: `lib/features/record/data/http_run_record_repository.dart`
- Modify: `lib/features/record/domain/run_record.dart`
- Modify: `lib/features/record/domain/run_record_repository.dart`
- Modify: `lib/features/record/data/fake_run_record_repository.dart`
- Test: `test/run_record_dto_test.dart` (신설) · `test/run_record_failure_test.dart`

**Interfaces:**
- Produces: `RunRecord.type` · `RunRecord.playerCount` — 다음 묶음의 목록 카드가 쓴다

- [ ] **Step 1: 앞 PR 머지 후 `upstream/dev`에서 딴다**

- [ ] **Step 2: DTO 를 새 응답에 맞춘다**

```dart
// `items` → `runningRecords`, `nextCursor` 없음
final items = json['runningRecords'];
```

⚠️ **페이지가 사라졌으므로 `RunRecordPage`도 없앤다.** 빈 껍데기를 남겨 두면 다음 사람이 커서가 있는 줄 안다.

- [ ] **Step 3: `type` · `playerCount` 를 엔티티에 더한다**

```dart
/// 러닝 방식. 서버가 `SOLO` 또는 `MATCH` 로 준다.
enum RunKind { solo, match;
  /// ⚠️ **모르는 값이면 `null`이다.** 아무 값으로도 뭉개지 않는다.
  static RunKind? of(Object? wire) => switch (wire) {
    'SOLO' => RunKind.solo, 'MATCH' => RunKind.match, _ => null,
  };
}

/// 이 러닝을 시작한 인원(본인 포함). 시작 전에 나간 사람은 안 센다.
///
/// ⚠️ `MATCH` 인데 `1` 이면 **매칭인데 혼자 달린 것**이다 — 상대가 안 나왔거나
/// 시작 전에 나갔다. 홈의 1인 러닝 카드와 같은 사건이다(가이드 3-3).
final int playerCount;
```

- [ ] **Step 4: 커서 조회를 걷어낸다**

`recent({cursor, limit})` 를 `run_record_repository.dart`(인터페이스)·구현·가짜 구현에서 지운다. **쓰는 곳이 있으면 `byDateRange`로 옮긴다.**

```bash
grep -rn "\.recent(" lib/ test/
```

- [ ] **Step 5: ⚠️ 날짜 묶기를 앞 10자리로 바꿀지 **재어 보고** 정한다**

가이드 3-1 은 `startedAt`의 **앞 10자리를 그대로 쓰라**고 한다. 지금은
`DateTime.parse`로 로컬 시각을 만들고 `RunRecord.day`로 묶는다.

⚠️ **기기가 KST 면 둘이 같은 결과다.** `run_record_dto.dart`에 이미 긴 주석이
있고 "고치려면 파싱만이 아니라 묶는 곳과 그리는 곳까지 옮겨야 한다"고 적혀 있다.

→ **이 PR 범위를 넘는다.** 테스트로 **기기 시간대를 바꿨을 때 날짜가 밀리는지**만
확인해 적어 두고, 고치는 것은 따로 뺀다.

- [ ] **Step 6: 테스트를 쓴다**

```dart
test('새 응답 모양을 읽는다', ...);              // runningRecords[]
test('⚠️ 기록이 없으면 빈 배열이다', ...);        // 오류와 구분
test('⚠️ 모르는 type 은 null 이다', ...);
test('누적 경사가 null 로 올 수 있다', ...);
test('⚠️ MATCH + playerCount 1 을 가려낸다', ...);
```

- [ ] **Step 7: 일부러 부순다** — 응답 키를 `items`로 되돌려 빨개지는지 본다

- [ ] **Step 8: 검증하고 에뮬레이터에서 본다**

⚠️ **로그인해서 기록 탭을 연다.** 이 PR 의 목적이 "데이터가 보이는 것"이라
빈 상태만 보면 확인한 것이 아니다. 기록이 없으면 **솔로 러닝을 한 번 돌려**
기록을 만든다. 어떻게 봤는지 PR 에 적는다.

- [ ] **Step 9: 커밋하고 PR**

**💬 리뷰 포인트에 적을 것:**
- 누적 경사는 **null 이 섞이면 합계가 실제보다 작다**(가이드 3-2). 다음 묶음의 상단 3칸에서 **확정값처럼 보이지 않게** 그려야 한다
- 주 시작 요일은 다음 묶음에서 **월요일로 통일**할 생각이다(위 3절). 가이드는 일요일을 권하지만 그 근거(월 달력)가 사라진다

---

## Task 3: 기록 상세가 삭제된 API 를 안 쓰는지 확인한다

가이드 5장이 **기록 상세(옛 20번)는 삭제**됐고 `runningRoomId`로 러닝 결과·구간 결과를 쓰라고 한다.

- [ ] **Step 1: 지금 무엇을 부르는지 본다**

```bash
grep -rn "running-records/\|/results\|split-results" lib/features/record/data/
```

`http_run_record_repository.byRoom()`이 이미 `results` + `split-results` 둘을
동시에 부르는 것으로 보인다. **맞으면 이 Task 는 확인만 하고 닫는다.**

- [ ] **Step 2: 아니면 고치고, 맞으면 PR 없이 넘어간다**

⚠️ **확인했다는 사실은 남긴다** — 다음 사람이 같은 걱정을 다시 하지 않도록
Task 2 의 PR 본문에 한 줄 적는다.

---

## 이 계획이 다루지 않는 것

- **UI 교체** — `docs/plans/2026-10-04-ui-redesign-record.md`가 맡는다. **이 계획이 끝난 뒤**에 간다
- **날짜 묶기를 앞 10자리로** — Task 2 Step 5. 파싱·묶기·그리기 셋을 함께 옮겨야 해서 따로 뺀다
- **이미 저장된 잘못된 고도** — 서버 쪽 데이터다. 백엔드와 정한다
- **뱃지** — 가이드가 "백엔드에 뱃지 기능이 아직 없다"고 못 박았다. 화면에서 뺀다
- **케이던스** — 목록 응답에 없다. 상세(`averageCadenceSpm`)에만 있다
