/// 달리며 태운 열량을 낸다.
///
/// ## ⚠️ 이 값은 기록이 아니다
///
/// **칼로리는 서버가 종료 시 확정한다.** 페이로드에 칼로리 자리가 없고, 명세가
/// *"클라 계산값은 러닝 중 화면 표시용이다"*라고 못박았다
/// (`docs/specs/2026-08-26-running-websocket-design.md` 1절).
/// 여기 값은 달리는 동안 보여주기 위한 것이고, **나중에 보는 기록과 다를 수 있다.**
///
/// ## 무엇으로 내나 — ACSM 달리기 대사식
///
/// 미국스포츠의학회(ACSM)가 정한 식이다. 분당 이동 거리에서 산소 섭취량을 내고,
/// 그것을 대사당량(MET)으로 옮긴 뒤 몸무게와 시간을 곱한다.
///
/// ```
/// VO2(ml/kg/min) = 0.2 × 속도(m/min) + 3.5
/// MET            = VO2 / 3.5
/// kcal           = MET × 3.5 × 몸무게(kg) × 분 / 200
/// ```
///
/// 시속 10km(167m/min)를 넣으면 MET가 10.5쯤 나오는데, 이는 운동 대사량 표
/// (Compendium of Physical Activities)의 달리기 값과 맞는다. 근거가 있는
/// 숫자라 나중에 서버 값과 벌어져도 어디서 갈렸는지 말할 수 있다.
///
/// ## 키는 쓰지 않는다
///
/// 이 식에 들어가는 신체 값은 **몸무게 하나뿐**이다. 키가 필요한 것은
/// 기초대사량(BMR) 기반 식인데, 그쪽은 안정 시 소모까지 더해 러닝만의 소모를
/// 재는 데 맞지 않는다. 키는 프로필에 함께 저장하되 여기서는 안 쓴다.
abstract final class CalorieCalculator {
  const CalorieCalculator._();

  /// 서 있을 때의 산소 섭취량(ml/kg/min). 1 MET가 이 값이다.
  static const _restingVo2 = 3.5;

  /// 달리기의 수평 이동 계수. ACSM이 정한 값이다.
  static const _runningFactor = 0.2;

  /// 이 속도 아래로는 내지 않는다(m/min).
  ///
  /// 분당 30m는 시속 1.8km로 **걷기보다 느리다.** 신호를 기다리며 서 있는
  /// 동안 GPS가 흔들린 것을 달린 것으로 세지 않는다.
  static const _minimumSpeed = 30.0;

  /// 태운 열량(kcal). **낼 수 없으면 `null`이다.**
  ///
  /// 몸무게를 모르면 `null`이다 — **기본값으로 때우지 않는다.** 63kg으로
  /// 채우면 그 사람의 칼로리가 조용히 틀리는데, 틀렸다는 것을 알 방법이 없다.
  /// 화면은 `null`을 `--`로 그린다.
  static int? burned({
    required double meters,
    required Duration elapsed,
    required int? weightKg,
  }) {
    if (weightKg == null || weightKg <= 0) return null;

    final minutes = elapsed.inMilliseconds / Duration.millisecondsPerMinute;
    if (minutes <= 0 || meters <= 0) return 0;

    final speed = meters / minutes;
    if (speed < _minimumSpeed) return 0;

    final vo2 = _runningFactor * speed + _restingVo2;
    final met = vo2 / _restingVo2;

    return (met * _restingVo2 * weightKg * minutes / 200).round();
  }
}
