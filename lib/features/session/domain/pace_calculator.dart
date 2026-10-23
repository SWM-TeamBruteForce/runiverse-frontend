import 'package:runiverse/features/session/domain/geo_point.dart';

/// 페이스 계산 — 순수 함수만 있다.
///
/// **페이스는 속도와 반대다.** 1km를 뛰는 데 걸리는 시간이라 값이 작을수록 빠르다.
/// `5'32"/km`는 5분 32초.
///
/// 계산을 화면에 두지 않는 이유는 `docs/implementation-notes.md` §5-3에 있다 —
/// UI는 상태를 계산하지 않는다.
abstract final class PaceCalculator {
  /// 최소 거리(미터). 이보다 짧으면 페이스를 내지 않는다.
  ///
  /// 출발 직후 2미터에서 나온 페이스는 의미가 없다. 좌표 하나만 튀어도
  /// `0'30"/km` 같은 값이 나와서 화면이 요동친다.
  static const _minMeters = 20.0;

  /// 거리와 시간으로 1km당 페이스를 낸다.
  ///
  /// 아직 낼 수 없으면 `null`이다 — 거리가 0이거나 너무 짧을 때.
  /// `Duration.zero`를 대신 돌려주면 "0분 페이스"라는 없는 값이 화면에 뜬다.
  static Duration? perKilometer({
    required double meters,
    required Duration elapsed,
  }) {
    if (meters < _minMeters || elapsed <= Duration.zero) return null;

    final secondsPerMeter = elapsed.inMilliseconds / 1000 / meters;
    return Duration(milliseconds: (secondsPerMeter * 1000 * 1000).round());
  }

  /// 최근 [window] 안의 좌표만 보고 낸 페이스.
  ///
  /// 평균 페이스는 러닝이 길어질수록 둔해져서 "지금 빠른가"를 알려주지 못한다.
  /// 마지막 좌표를 기준으로 시간 창을 잘라 그 구간만 본다.
  static Duration? recent(
    List<GeoPoint> points, {
    Duration window = const Duration(seconds: 30),
  }) {
    if (points.length < 2) return null;

    final last = points.last;
    final from = last.recordedAt.subtract(window);

    // 창 안에 들어오는 첫 좌표를 찾는다. 하나도 없으면 마지막 두 점만 본다.
    var startIndex = points.length - 2;
    for (var i = points.length - 2; i >= 0; i--) {
      if (points[i].recordedAt.isBefore(from)) break;
      startIndex = i;
    }

    final meters = totalMeters(points.sublist(startIndex));
    final elapsed = last.recordedAt.difference(points[startIndex].recordedAt);
    return perKilometer(meters: meters, elapsed: elapsed);
  }

  /// 좌표를 순서대로 이어 붙인 총 거리(미터).
  ///
  /// ⚠️ **받은 좌표를 그대로 더한다.** 보정을 하지 않으므로 제자리에 서 있어도
  /// 신호가 흔들린 만큼 거리가 늘어난다. 알고 남겨둔 한계다(설계 문서 3절).
  static double totalMeters(List<GeoPoint> points) {
    var meters = 0.0;
    for (var i = 1; i < points.length; i++) {
      meters += points[i - 1].distanceTo(points[i]);
    }
    return meters;
  }

  /// 페이스를 `5'32"` 형태로 적는다. 낼 수 없으면 `--'--"`.
  ///
  /// 단위(`/km`)는 붙이지 않는다. 붙일지는 부르는 쪽이 정한다.
  static String format(Duration? pace) {
    if (pace == null) return "--'--\"";

    final minutes = pace.inMinutes;
    final seconds = pace.inSeconds % 60;
    return "$minutes'${seconds.toString().padLeft(2, '0')}\"";
  }
}
