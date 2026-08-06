import 'dart:math' as math;

/// 러닝 중에 받은 위치 한 점.
///
/// geolocator가 주는 `Position`을 화면까지 들고 가지 않는다. 받는 즉시 이 타입으로 옮긴다.
/// 그래야 거리·페이스 계산을 **실기기 없이** 테스트할 수 있고, 위치 패키지를 바꿔도
/// `data/` 파일 하나만 다시 쓰면 된다.
///
/// `dart:math`만 쓴다. 패키지를 import하지 않는다.
class GeoPoint {
  const GeoPoint({
    required this.latitude,
    required this.longitude,
    required this.recordedAt,
    this.accuracy = 0,
  });

  final double latitude;
  final double longitude;

  /// 이 좌표를 받은 시각. 페이스는 좌표 사이의 **시간차**로 계산한다.
  final DateTime recordedAt;

  /// 오차 반경(미터). "이 좌표는 반경 N미터 안 어딘가"라는 뜻이다.
  ///
  /// 지금은 저장만 하고 쓰지 않는다. 좌표 보정을 넣을 때 첫 번째로 보게 될 값이다
  /// (`docs/specs/2026-08-05-solo-run-design.md` 3절).
  final double accuracy;

  /// 지구 반지름(미터). 평균값을 쓴다.
  static const _earthRadius = 6371000.0;

  /// [other]까지의 거리(미터).
  ///
  /// 지구가 둥글어서 위경도 차를 그냥 빼면 안 된다. **하버사인 공식**으로 구면 위의
  /// 거리를 구한다. 수백 미터 단위에서는 오차가 무시할 만하다.
  double distanceTo(GeoPoint other) {
    final dLat = _toRadians(other.latitude - latitude);
    final dLon = _toRadians(other.longitude - longitude);

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(latitude)) *
            math.cos(_toRadians(other.latitude)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    return _earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;

  @override
  String toString() =>
      'GeoPoint($latitude, $longitude, ±${accuracy}m, $recordedAt)';
}
