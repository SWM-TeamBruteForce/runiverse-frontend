/// 시간대 인사 — 홈 히어로(S05)가 쓴다.
///
/// 화면이 `DateTime.now().hour`를 직접 보고 `if`를 늘어놓지 않게 분리했다.
/// 시각만 넣으면 결과가 정해지는 순수 함수라 시계를 돌리지 않고 테스트할 수 있다
/// (`docs/implementation-notes.md` §5-3 — UI는 상태를 계산하지 않는다).
enum Greeting {
  /// 05:00 ~ 11:59
  morning,

  /// 12:00 ~ 17:59
  afternoon,

  /// 18:00 ~ 22:59
  evening,

  /// 23:00 ~ 04:59
  night,
}

abstract final class GreetingRule {
  /// [now]의 **시(hour)** 만 본다. 분·초는 경계를 바꾸지 않는다.
  ///
  /// 밤이 자정을 넘어 이어지므로 나머지 셋을 먼저 걸러내고 남는 시간을 밤으로 본다.
  /// 그래야 `23 <= h || h < 5`처럼 조건이 끊긴 구간을 쓰지 않아도 된다.
  static Greeting of(DateTime now) {
    final hour = now.hour;
    if (hour >= 5 && hour < 12) return Greeting.morning;
    if (hour >= 12 && hour < 18) return Greeting.afternoon;
    if (hour >= 18 && hour < 23) return Greeting.evening;
    return Greeting.night;
  }
}
