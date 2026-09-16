/// 고를 수 있는 매칭 시간대 하나.
///
/// ## [raw]를 손대지 않는다
///
/// 신청할 때 이 문자열을 **그대로 되돌려 보낸다.** 서버가 준 것이면 서버의
/// 판단을 그대로 쓰는 것이고, 앱이 만든 것이면 [todayRange]가 만든 그 값이
/// 그대로 나간다. 어느 쪽이든 화면에 그린 시각과 서버로 가는 시각이 갈리지
/// 않는다 — 두 벌로 관리하면 언젠가 어긋난다.
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

  /// 아직 확정되지 않은 대기자 수. **모르면 `null`이다.**
  ///
  /// 사회적 증거다 — 대기 인원이 많은 슬롯으로 유도해 매칭 성사율을 올린다.
  /// 0명인 슬롯도 고를 수 있다(`docs/implementation-notes.md` 2-1).
  ///
  /// ⚠️ **`0`과 `null`은 다르다.** `0`은 "아무도 없다"이고 `null`은 "모른다"다.
  /// 모르는 것을 0으로 그리면 사람이 없다고 잘못 알린다 — 조회 API가 아직
  /// 없어서 [todayRange]로 만든 목록은 전부 `null`이다.
  final int? waitingCount;

  /// 모집 마감이 지나지 않았는가.
  ///
  /// 마감된 슬롯은 목록에서 빼지 않고 잠근다. 빼면 "18:00이 왜 없지"가 되고,
  /// 시간이 흐르며 목록이 줄어드는 것도 이상하게 읽힌다.
  final bool selectable;

  /// 오늘 고를 수 있는 시간대를 **앱이 만든다.**
  ///
  /// ## ⚠️ 조회 API가 MVP에 없다
  ///
  /// `GET /running-matches/slots`(14번)는 대기 인원을 세는 것이 목적이라
  /// MVP 범위 밖이다. 신청은 `POST /running-matches`만으로 되므로, 목록이
  /// 없다고 화면을 멈출 이유가 없다.
  ///
  /// 범위와 간격은 명세가 고정했다 — **18:00~22:00, 30분 간격.** 서버가 그
  /// 밖의 값을 400으로 거절하므로 앱이 만들어도 판단 주체는 여전히 서버다.
  ///
  /// [selectable]은 **시작 시각만 보고** 정한다. 진짜 마감은 그보다 앞서지만
  /// (`start_at - 오프셋`) 그 오프셋은 운영값이라 앱이 알면 언젠가 어긋난다.
  /// 마감이 지난 슬롯을 누르면 서버가 `MATCH_SLOT_CLOSED`로 거절하고, 화면이
  /// 그때 그 슬롯을 잠근다.
  static List<MatchSlot> todayRange({required DateTime now}) {
    const firstHour = 18;
    const lastHour = 22;
    const halves = (lastHour - firstHour) * 2;

    return [
      for (var i = 0; i <= halves; i++)
        () {
          final startAt = DateTime(
            now.year,
            now.month,
            now.day,
            firstHour + i ~/ 2,
            (i % 2) * 30,
          );
          return MatchSlot(
            raw: isoOf(startAt),
            startAt: startAt,
            waitingCount: null,
            selectable: now.isBefore(startAt),
          );
        }(),
    ];
  }

  /// 서버가 쓰는 표기 — 시간대 없는 한국 시각, 초 단위까지.
  ///
  /// `DateTime.toIso8601String()`을 쓰지 않는다. 밀리초가 붙어 서버 형식과
  /// 어긋난다.
  static String isoOf(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)}'
        'T${two(time.hour)}:${two(time.minute)}:00';
  }

  /// 이 슬롯을 잠근 사본. 서버가 마감됐다고 답했을 때 쓴다.
  MatchSlot closed() => MatchSlot(
    raw: raw,
    startAt: startAt,
    waitingCount: waitingCount,
    selectable: false,
  );

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
