import 'package:runiverse/features/matching/domain/match_slot.dart';

/// 한 거리의 시간대 묶음.
class DistanceSlots {
  const DistanceSlots({required this.meters, required this.slots});

  /// 목표 거리(m). **화면의 칩이 이 값으로 선다** — 앱이 목록을 갖지 않는다.
  final int meters;

  /// 이 거리의 시간대. `scheduledStartAt` 오름차순으로 온다.
  final List<MatchSlot> slots;
}

/// 거리 × 시간의 판. 조회 응답 하나를 통째로 담는다(명세 No 16).
///
/// ## ⚠️ 한 번 받아 끝이다
///
/// 2026-10-26 전에는 조회가 **거리를 필수로 받아** 그 거리의 시간대만 줬다.
/// 그래서 거리를 고를 때마다 다시 물었고, 왕복 한 번 내내 **새 거리 이름에 옛
/// 거리 숫자**가 붙는 틈이 있었다. 지금은 숫자가 한 판에서 같이 오므로 그 틈이
/// **구조적으로 없다.**
///
/// ## ⚠️ 거리 순서를 앱이 정하지 않는다
///
/// 명세가 `targetDistanceMeters` 오름차순으로 준다고 했고, 칩의 순서는 **서버가
/// 정하는 것**이다. 여기서 다시 정렬하면 서버가 순서를 바꿔도 화면이 안 따라간다.
class SlotBoard {
  const SlotBoard(this.distances);

  /// 거리별 묶음. 받은 순서 그대로다.
  final List<DistanceSlots> distances;

  /// 시간 선택기가 읽는 가로줄. **거리를 접어 시각 하나로 만든 것이다.**
  ///
  /// ⚠️ **거리마다 시각 목록이 같다고 믿지 않는다.** 명세는 같다고 적었지만,
  /// 하나만 빠진 응답이 오면 그 시각이 통째로 사라진다 — 합집합이라 남는다.
  ///
  /// ⚠️ **매번 새로 만든다.** 판은 조회 한 번에 한 벌이고 화면이 자주 읽지
  /// 않는다. 미리 계산해 두면 두 벌이 생겨 어긋날 자리가 는다.
  List<SlotTime> get times {
    final startAt = <String, DateTime>{};
    final waiting = <String, int>{};
    final open = <String, bool>{};

    for (final distance in distances) {
      for (final slot in distance.slots) {
        startAt.putIfAbsent(slot.raw, () => slot.startAt);
        waiting[slot.raw] = (waiting[slot.raw] ?? 0) + slot.waitingCount;
        // ⚠️ **하나라도 고를 수 있으면 연다.** 명세는 시작 시각이 같으면 거리가
        // 달라도 값이 같다고 했지만, 서버가 그 전제를 깨도 고를 수 있는 것을
        // 막지는 않게 된다. 막는 쪽으로 틀리면 사람이 할 수 있는 일이 없다.
        open[slot.raw] = (open[slot.raw] ?? false) || slot.selectable;
      }
    }

    // ⚠️ **문자열이 아니라 읽은 시각으로 세운다.** 거리마다 순서가 어긋난
    // 응답이 와도 시트가 뒤섞이지 않는다. 거리 순서는 서버 것을 그대로 쓰지만
    // (위 주석), 시각은 **합집합이라 순서를 여기서 정해야 한다.**
    final order = startAt.keys.toList()
      ..sort((a, b) => startAt[a]!.compareTo(startAt[b]!));

    return [
      for (final raw in order)
        SlotTime(
          raw: raw,
          startAt: startAt[raw]!,
          waitingTotal: waiting[raw]!,
          selectable: open[raw]!,
        ),
    ];
  }

  /// 시각 × 거리로 한 칸을 집는다. **없으면 `null`이다.**
  ///
  /// ⚠️ **0으로 뭉개지 않는다.** 등록 버튼이 이 값을 읽는데, 없는 조합을
  /// `0명 대기`로 그리면 고를 수 없는 자리를 고를 수 있는 것처럼 말하게 된다.
  MatchSlot? at({required String raw, required int meters}) {
    for (final distance in distances) {
      if (distance.meters != meters) continue;
      for (final slot in distance.slots) {
        if (slot.raw == raw) return slot;
      }
      return null;
    }
    return null;
  }
}

/// 시간 선택기의 한 줄. **거리와 무관하다.**
class SlotTime {
  const SlotTime({
    required this.raw,
    required this.startAt,
    required this.waitingTotal,
    required this.selectable,
  });

  /// 서버가 준 문자열. **신청에 그대로 실린다** — 다시 조립하지 않는다.
  final String raw;

  /// [raw]를 읽은 값. 표시 전용이다.
  final DateTime startAt;

  /// 이 시각에 기다리는 사람. **모든 거리를 더한 수다.**
  ///
  /// ⚠️ **거리가 다르면 같은 방에 매칭되지 않는다**(명세). `5명`이 3km 3명과
  /// 10km 2명일 수 있고, 그 다섯이 서로 만나지는 않는다. 그래서 문구에 "함께"
  /// 같은 말을 붙이지 않는다 — 거리를 고르면 등록 버튼의 숫자가 **진짜 그
  /// 조건의 수**로 바뀌면서 저절로 좁혀진다.
  final int waitingTotal;

  /// 아직 고를 수 있는가. 거리 중 **하나라도** 열려 있으면 참이다.
  final bool selectable;

  @override
  bool operator ==(Object other) =>
      other is SlotTime &&
      other.raw == raw &&
      other.startAt == startAt &&
      other.waitingTotal == waitingTotal &&
      other.selectable == selectable;

  @override
  int get hashCode => Object.hash(raw, startAt, waitingTotal, selectable);

  @override
  String toString() =>
      'SlotTime($raw, waiting: $waitingTotal, selectable: $selectable)';
}
