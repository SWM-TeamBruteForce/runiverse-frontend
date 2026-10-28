import 'package:runiverse/core/utils/kst_time.dart';
import 'package:runiverse/features/matching/domain/match_slot.dart';
import 'package:runiverse/features/matching/domain/slot_board.dart';

/// 슬롯 조회 응답(`GET /api/v1/running-matches/slots`, 명세 No 16)을 읽는다.
///
/// ```
/// { distances: [ { targetDistanceMeters, slots: [ { scheduledStartAt,
///   waitingCount, selectable } ] } ] }
/// ```
///
/// ## ⚠️ 한 줄이 깨져도 판을 버리지 않는다
///
/// 서버가 예상 밖의 값을 한 줄 섞어 보냈다고 매칭 등록 화면이 통째로 멈추면
/// 안 된다. **못 읽는 줄만 건너뛰고** 나머지를 준다 — 시각을 못 읽으면 화면에
/// 그릴 수도, 신청에 실어 보낼 수도 없어서 그 줄만은 버릴 수밖에 없다.
///
/// ## ⚠️ 같은 시각이 거리마다 오는 것은 중복이 아니다
///
/// 전에는 응답이 한 거리 분량이어서 `scheduledStartAt`이 겹치면 버렸다. 지금은
/// **18:30이 3km·5km·10km에 한 번씩 정상적으로 온다.** 그 규칙을 그대로 들고
/// 오면 첫 거리만 남고 나머지가 통째로 사라진다. 중복은 **한 거리 안에서만**
/// 본다.
///
/// ## ⚠️ `0`과 `모름`을 가르는 일이 여기서 끝난다
///
/// 서버는 대기자가 없는 시각도 `waitingCount: 0`으로 **반드시** 보낸다. 그래서
/// [MatchSlot.waitingCount]는 비널이고, 모름을 만들 수 있는 자리는 이 함수뿐이다.
/// 빠졌거나 타입이 틀리면 **0으로 읽는다** — 화면은 0을 "안 그린다"로 다루므로,
/// 모르는 것을 숫자로 지어내는 것보다 조용히 빠지는 편이 낫다.
SlotBoard slotBoardFromJson(Object? body) {
  final rows = body is Map ? body['distances'] : null;
  if (rows is! List) return const SlotBoard([]);

  final distances = <DistanceSlots>[];
  // ⚠️ **같은 거리가 두 번 오면 한 번만 남긴다.** 그대로 두면 칩이 두 개 서고,
  // 시간 시트의 합계가 그 거리만 두 배가 된다.
  final seenDistances = <int>{};

  for (final row in rows) {
    if (row is! Map) continue;

    // ⚠️ **미터값이 칩의 이름이자 신청에 실리는 값이다.** 모르는 채로 세우면
    // 누를 수는 있는데 무엇을 신청하는지 알 수 없는 칩이 생긴다. 그래서
    // 시간대가 멀쩡해도 이 줄은 통째로 버린다.
    final meters = row['targetDistanceMeters'];
    if (meters is! int || meters <= 0) continue;
    if (!seenDistances.add(meters)) continue;

    // ⚠️ **시간대가 비어도 거리는 남긴다.** 서버가 내놓은 선택지를 앱이
    // 감추지 않는다. 칩은 서고, 해당하는 칸이 없으니 등록 버튼이 저절로
    // 막는다(`SlotBoard.at`이 `null`).
    distances.add(
      DistanceSlots(meters: meters, slots: _slotsFromJson(row['slots'])),
    );
  }

  return SlotBoard(distances);
}

/// 한 거리의 시간대 목록을 읽는다.
List<MatchSlot> _slotsFromJson(Object? rows) {
  if (rows is! List) return const [];

  final slots = <MatchSlot>[];
  // 한 거리 안에서 같은 시각이 두 번 오면 진짜 중복이다 — 그대로 두면 그
  // 거리의 합계가 두 배가 된다.
  final seen = <String>{};

  for (final row in rows) {
    if (row is! Map) continue;

    final raw = row['scheduledStartAt'];
    if (raw is! String) continue;
    // ⚠️ **`DateTime.parse`를 쓰지 않는다.** 서버는 오프셋 없이 주고, 화면이
    // `KstTime.wallOf`로 +9시간을 한다. 로컬로 읽으면 UTC 기기에서 18:00
    // 슬롯이 03:00으로 뜬다.
    final startAt = KstTime.parse(raw);
    if (startAt == null) continue;
    if (!seen.add(raw)) continue;

    final waiting = row['waitingCount'];
    final selectable = row['selectable'];

    slots.add(
      MatchSlot(
        // ⚠️ **읽기 전 원본 문자열 그대로다.** 신청이 이것을 되돌려 보낸다 —
        // 다시 조립하면 화면에 그린 시각과 서버로 가는 시각이 갈린다.
        raw: raw,
        startAt: startAt,
        // 음수는 0으로 본다. 그대로 두면 합계가 줄어 "사람이 적다"로 읽힌다.
        waitingCount: waiting is int && waiting > 0 ? waiting : 0,
        // 모르면 **막는 쪽**이다. 열어 두면 마감된 시각을 눌러 409를 맞는다.
        selectable: selectable is bool && selectable,
      ),
    );
  }

  return slots;
}
