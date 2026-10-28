/// 고를 수 있는 매칭 시간대 하나.
///
/// ## ⚠️ 앱이 만들지 않는다
///
/// 2026-10-22까지는 앱이 18:00~22:00 아홉 칸을 직접 만들었다(`todayRange`).
/// 지금은 **서버가 준다**(`GET /running-matches/slots`, 명세 No 16) — 시각
/// 범위·간격이 서버 설정값이라, 앱이 적어 두면 설정이 바뀌는 날 어긋난다.
/// 읽는 자리는 `slot_board_dto.dart` 하나다.
///
/// ## [raw]를 손대지 않는다
///
/// 신청할 때 이 문자열을 **그대로 되돌려 보낸다.** 다시 조립하지 않는다 —
/// 화면에 그린 시각과 서버로 가는 시각이 두 벌이 되면 언젠가 어긋난다.
///
/// [startAt]은 **화면에 그리기 위해서만** 있다.
class MatchSlot {
  const MatchSlot({
    required this.raw,
    required this.startAt,
    required this.waitingCount,
    required this.selectable,
  });

  /// 서버가 준 문자열. 신청 요청에 그대로 실린다.
  final String raw;

  /// [raw]를 읽은 값. 표시 전용이다.
  final DateTime startAt;

  /// 아직 확정되지 않은 대기자 수. **서버가 0도 보내므로 비널이다.**
  ///
  /// 사회적 증거다 — 대기 인원이 많은 슬롯으로 유도해 매칭 성사율을 올린다.
  /// 0명인 슬롯도 고를 수 있다(`docs/implementation-notes.md` 2-1).
  ///
  /// ⚠️ **0은 "안 그린다"는 뜻으로 쓰인다.** `0명 대기`는 비어 있다고 알리는
  /// 꼴이라 오히려 사람을 민다. 읽을 수 없는 값을 0으로 뭉개는 판단은
  /// `slot_board_dto.dart`가 하고, 여기서는 받은 값을 그대로 들고 있다.
  final int waitingCount;

  /// 모집 마감이 지나지 않았는가.
  ///
  /// 마감된 슬롯은 목록에서 빼지 않고 잠근다. 빼면 "18:00이 왜 없지"가 되고,
  /// 시간이 흐르며 목록이 줄어드는 것도 이상하게 읽힌다.
  final bool selectable;

  // ⚠️ **`closed()`가 죽었다**(2026-10-26). 409를 받으면 이 한 줄을 잠근
  // 사본으로 갈아 끼웠는데, 이제 **판을 다시 받는다** — 한 번에 다 오므로
  // 그쪽이 싸고, 그사이 마감된 다른 시각까지 함께 잠긴 채로 온다.

  @override
  bool operator ==(Object other) =>
      other is MatchSlot &&
      other.raw == raw &&
      other.startAt == startAt &&
      other.waitingCount == waitingCount &&
      other.selectable == selectable;

  @override
  int get hashCode => Object.hash(raw, startAt, waitingCount, selectable);

  @override
  String toString() =>
      'MatchSlot($raw, waiting: $waitingCount, selectable: $selectable)';
}
