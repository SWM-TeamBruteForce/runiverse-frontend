import 'package:runiverse/core/utils/kst_time.dart';
import 'package:runiverse/features/matching/domain/match_slot.dart';

/// 슬롯 조회 응답(`GET /api/v1/running-matches/slots`, 명세 No 16)을 읽는다.
///
/// ## ⚠️ 한 줄이 깨져도 목록을 버리지 않는다
///
/// 서버가 예상 밖의 값을 한 줄 섞어 보냈다고 매칭 등록 화면이 통째로 멈추면
/// 안 된다. **시각을 못 읽는 줄만 건너뛰고** 나머지를 준다 — 시각이 없으면
/// 화면에 그릴 수도, 신청에 실어 보낼 수도 없어서 그 줄만은 버릴 수밖에 없다.
///
/// ## ⚠️ `0`과 `모름`을 가르는 일이 여기서 끝난다
///
/// 서버는 대기자가 없는 시각도 `waitingCount: 0`으로 **반드시** 보낸다. 그래서
/// [MatchSlot.waitingCount]는 비널이고, 모름을 만들 수 있는 자리는 이 함수뿐이다.
/// 빠졌거나 타입이 틀리면 **0으로 읽는다** — 화면은 0을 "안 그린다"로 다루므로,
/// 모르는 것을 숫자로 지어내는 것보다 조용히 빠지는 편이 낫다.
List<MatchSlot> matchSlotsFromJson(Object? body) {
  final rows = body is Map ? body['slots'] : null;
  if (rows is! List) return const [];

  final slots = <MatchSlot>[];
  // ⚠️ **같은 시각이 두 번 오면 한 번만 남긴다.** 그대로 두면 합계가 두 배가
  // 되고 시트에 같은 시각이 두 줄 선다.
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
