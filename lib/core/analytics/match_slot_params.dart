import 'package:runiverse/core/utils/kst_time.dart';

/// 매칭 이벤트에 싣는 **예약한 출발 시각과 거리**.
///
/// ## 왜 따로 싣나
///
/// GA 는 이벤트가 **남은 시각**으로 나눈다. 오후 2시에 19:00 칸을 신청하면
/// 14시로 잡힌다 — 시간대별 성사율을 보려면 신청한 시각이 아니라 **예약한
/// 시각**이 필요하다.
///
/// ⚠️ **분류용이다.** 건별 정확한 성사율은 서버 신청 이력으로 본다.
abstract final class MatchSlotParams {
  const MatchSlotParams._();

  /// [startAt] 은 예약한 출발 순간, [meters] 는 목표 거리다. 모르는 값은
  /// **빼고 낸다** — 빈 문자열이나 0 을 실으면 그런 분류가 차트에 생긴다.
  ///
  /// - `slot_time` — KST `"19:00"`
  /// - `slot_weekday` — KST 요일 `"mon"` … `"sun"`
  /// - `distance_group` — `"5km"`. 1km 단위가 아니면 `"7.5km"`
  static Map<String, Object> of({DateTime? startAt, int? meters}) {
    // ⚠️ **기기 시간대가 아니라 KST 로 적는다.** 슬롯은 KST 18:00~22:00
    // 고정이라, 런던 기기에서 `10:00` 이 찍히면 없는 슬롯이 생긴다.
    final wall = startAt == null ? null : KstTime.wallOf(startAt);
    return {
      if (wall != null) 'slot_time': '${_two(wall.hour)}:${_two(wall.minute)}',
      if (wall != null) 'slot_weekday': _weekdays[wall.weekday - 1],
      if (meters != null && meters > 0) 'distance_group': distanceGroup(meters),
    };
  }

  /// 거리 분류. 서버가 거리를 늘려도 따라가도록 **표를 두지 않는다.**
  static String distanceGroup(int meters) {
    final km = meters / 1000;
    final text = km == km.truncateToDouble()
        ? km.toInt().toString()
        : km.toString();
    return '${text}km';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  /// `DateTime.weekday` 는 월요일이 1이다.
  static const _weekdays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
}
