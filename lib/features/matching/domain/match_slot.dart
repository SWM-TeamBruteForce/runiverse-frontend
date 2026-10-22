import 'package:runiverse/core/utils/kst_time.dart';

/// 고를 수 있는 매칭 시간대 하나.
///
/// ## ⚠️ 앱이 만들지 않는다
///
/// 2026-10-22까지는 앱이 18:00~22:00 아홉 칸을 직접 만들었다(`todayRange`).
/// 지금은 **서버가 준다**(`GET /running-matches/slots`, 명세 No 16) — 시각
/// 범위·간격이 서버 설정값이라, 앱이 적어 두면 설정이 바뀌는 날 어긋난다.
/// 읽는 자리는 `slot_dto.dart` 하나다.
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
  /// `slot_dto.dart`가 하고, 여기서는 받은 값을 그대로 들고 있다.
  final int waitingCount;

  /// 모집 마감이 지나지 않았는가.
  ///
  /// 마감된 슬롯은 목록에서 빼지 않고 잠근다. 빼면 "18:00이 왜 없지"가 되고,
  /// 시간이 흐르며 목록이 줄어드는 것도 이상하게 읽힌다.
  final bool selectable;

  /// 오늘 고를 수 있는 시간대를 앱이 만든다.
  ///
  /// ## ⚠️ 곧 지운다
  ///
  /// 목록의 주인이 서버로 넘어가는 중이다(`slot_dto.dart`). 이 함수를 부르는
  /// `loadSlots`가 사라지는 커밋에서 함께 간다 — 지금 지우면 그 커밋이
  /// 빌드되지 않아 한 커밋에 변경이 둘 섞인다.
  ///
  /// 범위와 간격은 명세가 고정했다 — **18:00~22:00, 30분 간격.** 서버가 그
  /// 밖의 값을 400으로 거절하므로 앱이 만들어도 판단 주체는 여전히 서버다.
  ///
  /// [selectable]은 **시작 시각만 보고** 정한다. 진짜 마감은 그보다 앞서지만
  /// (`start_at - 오프셋`) 그 오프셋은 운영값이라 앱이 알면 언젠가 어긋난다.
  /// 마감이 지난 슬롯을 누르면 서버가 `MATCH_SLOT_CLOSED`로 거절하고, 화면이
  /// 그때 그 슬롯을 잠근다.
  ///
  /// ⚠️ [nowWall]은 **한국 벽시계**다. 기기 시계로 만들면 해외에 있는 사용자가
  /// 자기 지역의 18:00을 신청하게 되고, 서버는 그것을 KST로 읽는다.
  /// ⚠️ **벽시계끼리는 `isBefore` 로 비교하지 않는다.**
  ///
  /// `DateTime` 의 비교는 필드가 아니라 **그 값이 가리키는 순간**을 본다.
  /// 그래서 `isUtc` 플래그가 한쪽만 붙어 있으면 시차만큼 어긋난다.
  ///
  /// 운영에서 이걸로 터졌다. [KstTime.nowWall] 은 `.toUtc().add(9h)` 라
  /// **UTC 플래그**가 붙어 오는데, 슬롯은 `DateTime(...)`(로컬 플래그)로 만들어
  /// 비교했다. 한국 기기에서는 두 값이 **시차의 두 배인 18시간** 벌어져,
  /// 18:00~22:00 아홉 칸이 하루 종일 전부 마감으로 떴다.
  ///
  /// 테스트가 못 잡은 이유는 `nowWall` 을 로컬로 넘겨 **양쪽 플래그가 같았기**
  /// 때문이고, 에뮬레이터가 멀쩡해 보인 이유는 시간대가 UTC 라 로컬 == UTC
  /// 였기 때문이다. 둘 다 "맞아서 통과한 것"이 아니다.
  ///
  /// 그래서 플래그를 타지 않는 **하루 중 분**으로 센다. 슬롯의 날짜는 언제나
  /// [nowWall] 의 날짜라, 시각만 견주면 충분하고 결과가 기기 시간대와 무관해진다.
  static List<MatchSlot> todayRange({required DateTime nowWall}) {
    const firstHour = 18;
    const lastHour = 22;
    const halves = (lastHour - firstHour) * 2;

    final minutesNow = nowWall.hour * 60 + nowWall.minute;

    return [
      for (var i = 0; i <= halves; i++)
        () {
          final hour = firstHour + i ~/ 2;
          final minute = (i % 2) * 30;
          // UTC 플래그로 만든다. [KstTime.format]·[KstTime.toLocal] 은 필드만
          // 읽으므로 결과가 같고, 이 값이 다시 순간 비교에 섞여도 어긋나지 않는다.
          final wall = DateTime.utc(
            nowWall.year,
            nowWall.month,
            nowWall.day,
            hour,
            minute,
          );
          return MatchSlot(
            raw: KstTime.format(wall),
            // 화면에 그리고 남은 시간을 재는 값이라 **기기 시각**이어야 한다.
            startAt: KstTime.toLocal(wall),
            waitingCount: 0,
            selectable: minutesNow < hour * 60 + minute,
          );
        }(),
    ];
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
