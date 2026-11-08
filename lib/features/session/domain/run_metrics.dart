import 'package:runiverse/features/session/domain/pace_calculator.dart';

/// 러닝 중에 화면이 보여주는 수치 한 벌.
///
/// **평균 페이스를 필드로 들지 않는다.** 거리와 시간에서 나오는 값이라
/// 따로 저장하면 셋이 어긋날 수 있다. 필요할 때 계산한다.
class RunMetrics {
  const RunMetrics({
    required this.distanceMeters,
    required this.elapsed,
    Duration? clockElapsed,
    this.currentPace,
    this.calories,
    this.cadenceSpm,
  }) : clockElapsed = clockElapsed ?? elapsed;

  /// 시작 직후. 아무것도 쌓이지 않은 상태다.
  static const zero = RunMetrics(distanceMeters: 0, elapsed: Duration.zero);

  /// 좌표를 이어 붙인 총 거리(미터).
  ///
  /// 미터로 든다. km 소수로 들면 반올림 지점이 화면과 서버에서 갈린다.
  final double distanceMeters;

  /// 움직인 시간 — 일시정지와 **버튼 없이 멈춘 구간**을 뺀다(가이드 2.3).
  ///
  /// 서버 `totalDurationSeconds`와 같은 기준이다. 요약·평균 페이스·칼로리가 이걸 쓴다.
  final Duration elapsed;

  /// 경과 시간 — **버튼 일시정지만** 뺀 시계. 러닝 화면과 워치가 보여 준다.
  ///
  /// ⚠️ 버튼 없이 멈춘 구간을 여기서 빼지 않는다. 멈춤은 10초 넘게 서 있어야
  /// 확정돼서, 빼면 확정 순간에 시간이 거꾸로 간다. 안 주면 [elapsed]와 같다.
  final Duration clockElapsed;

  /// 최근 구간의 페이스. 아직 낼 수 없으면 `null`이다.
  final Duration? currentPace;

  /// 태운 열량(kcal). **몸무게를 모르면 `null`이다.**
  ///
  /// ⚠️ **기록이 아니라 화면 표시용이다.** 서버가 종료 시 확정하는 값과 다를 수
  /// 있다(`CalorieCalculator` 참조). 페이로드에도 이 자리는 없다.
  final int? calories;

  /// 분당 걸음 수(spm). **낼 수 없으면 `null`이다.**
  ///
  /// 권한이 없거나, 걸음 센서가 없거나(에뮬레이터), 표본이 아직 모자랄 때다.
  /// 이 값은 **서버로도 간다** — 칼로리와 달리 페이로드에 자리가 있다.
  final int? cadenceSpm;

  double get distanceKm => distanceMeters / 1000;

  /// 전 구간 평균 페이스. 아직 낼 수 없으면 `null`.
  Duration? get averagePace =>
      PaceCalculator.perKilometer(meters: distanceMeters, elapsed: elapsed);

  RunMetrics copyWith({
    double? distanceMeters,
    Duration? elapsed,
    Duration? clockElapsed,
    Duration? currentPace,
    int? calories,
    int? cadenceSpm,
  }) {
    return RunMetrics(
      distanceMeters: distanceMeters ?? this.distanceMeters,
      elapsed: elapsed ?? this.elapsed,
      clockElapsed: clockElapsed ?? this.clockElapsed,
      // null로 되돌리는 경우가 없어 ?? 로 충분하다.
      currentPace: currentPace ?? this.currentPace,
      calories: calories ?? this.calories,
      cadenceSpm: cadenceSpm ?? this.cadenceSpm,
    );
  }

  @override
  String toString() =>
      'RunMetrics(${distanceMeters.toStringAsFixed(1)}m, $elapsed, '
      '${PaceCalculator.format(currentPace)})';
}
