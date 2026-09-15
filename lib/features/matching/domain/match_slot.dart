/// 고를 수 있는 매칭 시간대 하나.
///
/// ## ⚠️ 앱이 날짜를 조립하지 않는다
///
/// [raw]는 서버가 준 시각 문자열 그대로이고, **신청할 때 이 값을 손대지 않고
/// 되돌려 보낸다.** 앱이 "오늘 + 19:00"을 조립하면 자정 근처나 기기 시계가
/// 어긋났을 때 엉뚱한 날짜가 나간다. 무엇이 유효한 슬롯인지 판단하는 주체도
/// 서버 하나로 남는다.
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

  /// 아직 확정되지 않은 대기자 수.
  ///
  /// 사회적 증거다 — 대기 인원이 많은 슬롯으로 유도해 매칭 성사율을 올린다.
  /// 0명인 슬롯도 고를 수 있다(`docs/implementation-notes.md` 2-1).
  final int waitingCount;

  /// 모집 마감이 지나지 않았는가.
  ///
  /// 마감된 슬롯은 목록에서 빼지 않고 잠근다. 빼면 "18:00이 왜 없지"가 되고,
  /// 시간이 흐르며 목록이 줄어드는 것도 이상하게 읽힌다.
  final bool selectable;

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
