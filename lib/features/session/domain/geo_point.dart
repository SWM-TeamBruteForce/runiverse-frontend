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
    this.speed = 0,
    this.altitude,
    this.heading,
  });

  final double latitude;
  final double longitude;

  /// 이 좌표를 받은 시각. 페이스는 좌표 사이의 **시간차**로 계산한다.
  final DateTime recordedAt;

  /// 오차 반경(미터). "이 좌표는 반경 N미터 안 어딘가"라는 뜻이다.
  ///
  /// 칼만 필터의 측정 노이즈 `R`을 여기서 정한다 — 반경이 클수록 그 좌표를 덜 믿는다.
  final double accuracy;

  /// 그 순간의 속도(m/s).
  ///
  /// 칼만 필터의 프로세스 노이즈 `Q`를 여기서 정한다 — 빠를수록 위치가 실제로
  /// 변한다고 보고 측정을 더 받아들인다.
  ///
  /// ⚠️ **센서가 못 구하면 음수가 온다.** 직전 점과의 거리로 계산할 수도 있지만
  /// 센서 값(도플러 기반)이 더 정확하다. 읽는 쪽이 음수를 0으로 다룬다.
  final double speed;

  /// 해발 고도(미터). **못 구하면 `null`이다.**
  ///
  /// 서버 페이로드의 `altitudeMeters`가 그대로 nullable이라 여기서도 nullable로 든다.
  ///
  /// ⚠️ **경사를 내는 데 쓰지 않는다.** GPS 고도는 오차가 흔히 ±10~20m라
  /// 평지에서도 오르내리는 것처럼 찍힌다. 서버가 트랙 전체를 보고 계산하고,
  /// 그쪽도 `totalElevationGainMeters`를 nullable로 두었다.
  final double? altitude;

  /// 진행 방향(도, 0~360). **못 구하면 `null`이다.**
  ///
  /// 정지·저속에서 자주 못 구한다. 서버는 `0~360`을 요구하고 nullable 표기가
  /// 없어, **보낼 때 `0`으로 눌러 보낸다**(설계 문서 6절). 그 판단은 전송
  /// 계층이 하고, 도메인은 "모른다"를 `null`로 그대로 든다.
  final double? heading;

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
      'GeoPoint($latitude, $longitude, ±${accuracy}m, ${speed}m/s, $recordedAt)';
}
