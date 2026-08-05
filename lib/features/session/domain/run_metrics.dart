import 'package:runiverse/features/session/domain/pace_calculator.dart';

/// 러닝 중에 화면이 보여주는 수치 한 벌.
///
/// **평균 페이스를 필드로 들지 않는다.** 거리와 시간에서 나오는 값이라
/// 따로 저장하면 셋이 어긋날 수 있다. 필요할 때 계산한다.
class RunMetrics {
  const RunMetrics({
    required this.distanceMeters,
    required this.elapsed,
    this.currentPace,
  });

  /// 시작 직후. 아무것도 쌓이지 않은 상태다.
  static const zero = RunMetrics(distanceMeters: 0, elapsed: Duration.zero);

  /// 좌표를 이어 붙인 총 거리(미터).
  ///
  /// 미터로 든다. km 소수로 들면 반올림 지점이 화면과 서버에서 갈린다.
  final double distanceMeters;

  /// 일시정지를 **뺀** 러닝 시간.
  final Duration elapsed;

  /// 최근 구간의 페이스. 아직 낼 수 없으면 `null`이다.
  final Duration? currentPace;

  double get distanceKm => distanceMeters / 1000;

  /// 전 구간 평균 페이스. 아직 낼 수 없으면 `null`.
  Duration? get averagePace =>
      PaceCalculator.perKilometer(meters: distanceMeters, elapsed: elapsed);

  RunMetrics copyWith({
    double? distanceMeters,
    Duration? elapsed,
    Duration? currentPace,
  }) {
    return RunMetrics(
      distanceMeters: distanceMeters ?? this.distanceMeters,
      elapsed: elapsed ?? this.elapsed,
      // null로 되돌리는 경우가 없어 ?? 로 충분하다.
      currentPace: currentPace ?? this.currentPace,
    );
  }

  @override
  String toString() =>
      'RunMetrics(${distanceMeters.toStringAsFixed(1)}m, $elapsed, '
      '${PaceCalculator.format(currentPace)})';
}
