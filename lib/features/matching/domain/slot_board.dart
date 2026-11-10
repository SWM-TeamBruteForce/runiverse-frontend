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

  /// 오늘 아직 열린 시각이 있는지 가리는 가로줄. **거리를 접어 시각 하나로
  /// 만든 것이다.**
  ///
  /// ⚠️ **시간 선택기가 읽지 않는다.** 선택기는 고른 거리의 줄([slotsOf])을
  /// 그린다 — 거리가 다르면 같은 방에 매칭되지 않으므로, 거리를 접은 숫자는
  /// 들어가 보면 아무도 없는 시각을 `1명 대기`로 그린다. 그래서 여기에는
  /// 인원을 두지 않는다. 남은 쓰임은 "오늘이 끝났나" 하나다.
  ///
  /// ⚠️ **거리마다 시각 목록이 같다고 믿지 않는다.** 명세는 같다고 적었지만,
  /// 하나만 빠진 응답이 오면 그 시각이 통째로 사라진다 — 합집합이라 남는다.
  ///
  /// ⚠️ **매번 새로 만든다.** 판은 조회 한 번에 한 벌이고 화면이 자주 읽지
  /// 않는다. 미리 계산해 두면 두 벌이 생겨 어긋날 자리가 는다.
  List<SlotTime> get times {
    final startAt = <String, DateTime>{};
    final open = <String, bool>{};

    for (final distance in distances) {
      for (final slot in distance.slots) {
        startAt.putIfAbsent(slot.raw, () => slot.startAt);
        // ⚠️ **하나라도 고를 수 있으면 연다.** 명세는 시작 시각이 같으면 거리가
        // 달라도 값이 같다고 했지만, 서버가 그 전제를 깨도 고를 수 있는 것을
        // 막지는 않게 된다. 막는 쪽으로 틀리면 사람이 할 수 있는 일이 없다.
        open[slot.raw] = (open[slot.raw] ?? false) || slot.selectable;
      }
    }

    // ⚠️ **문자열이 아니라 읽은 시각으로 세운다.** 거리마다 순서가 어긋난
    // 응답이 와도 합집합의 순서가 정해진다. 거리 순서는 서버 것을 그대로 쓰지만
    // (위 주석), 시각은 **합집합이라 순서를 여기서 정해야 한다.**
    final order = startAt.keys.toList()
      ..sort((a, b) => startAt[a]!.compareTo(startAt[b]!));

    return [
      for (final raw in order)
        SlotTime(raw: raw, startAt: startAt[raw]!, selectable: open[raw]!),
    ];
  }

  /// 한 거리의 시간대. 시간 선택기가 그리는 줄이다. **없는 거리면 비어 있다.**
  ///
  /// ⚠️ **숫자가 그 거리의 수다.** 시트에 적힌 `1명 대기`가 곧 들어갔을 때
  /// 만나는 사람이다 — 등록 버튼의 숫자([at])와 같은 칸을 읽는다.
  ///
  /// ⚠️ **시각 순으로 세운다.** 명세가 오름차순을 약속했지만 [times]처럼 읽은
  /// 시각으로 다시 정렬한다 — 받은 순서를 믿으면 서버가 어긋나는 날 시트가
  /// 뒤섞인다.
  List<MatchSlot> slotsOf(int meters) {
    for (final distance in distances) {
      if (distance.meters == meters) {
        return [...distance.slots]
          ..sort((a, b) => a.startAt.compareTo(b.startAt));
      }
    }
    return const [];
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

/// 거리를 접은 시각 하나. **거리와 무관하다.**
///
/// ⚠️ **인원을 두지 않는다.** 모든 거리를 더한 `waitingTotal`이 있었는데,
/// 서로 만나지 않는 사람을 더한 수라 그 숫자를 보고 들어가면 빈 방이었다.
class SlotTime {
  const SlotTime({
    required this.raw,
    required this.startAt,
    required this.selectable,
  });

  /// 서버가 준 문자열.
  final String raw;

  /// [raw]를 읽은 값. 표시 전용이다.
  final DateTime startAt;

  /// 아직 고를 수 있는가. 거리 중 **하나라도** 열려 있으면 참이다.
  final bool selectable;

  @override
  bool operator ==(Object other) =>
      other is SlotTime &&
      other.raw == raw &&
      other.startAt == startAt &&
      other.selectable == selectable;

  @override
  int get hashCode => Object.hash(raw, startAt, selectable);

  @override
  String toString() => 'SlotTime($raw, selectable: $selectable)';
}
