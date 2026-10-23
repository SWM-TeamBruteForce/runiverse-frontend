import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/kalman_filter.dart';

/// GPS 좌표의 흔들림을 걷어낸다.
///
/// **제자리에 서 있어도 거리가 늘어난다.** 좌표는 가만히 있어도 몇 미터씩 흔들리고,
/// 받은 대로 이어 붙이면 그 흔들림이 전부 거리가 된다. 위도·경도에 칼만 필터를
/// 하나씩 걸어 그 떨림을 눌러 준다.
///
/// ## 임계값으로 점을 버리지 않는다
///
/// "정확도가 나쁘면 버린다" 같은 규칙을 두지 않는다. 버릴지 말지의 판단을 [_r]이
/// **연속적으로** 대신한다 — 나쁜 좌표는 사라지는 대신 약하게 반영된다.
/// 임계값을 세우면 경계 근처에서 점이 통째로 빠져 경로가 끊긴다
/// (`docs/specs/2026-08-05-solo-run-design.md` 3-2).
///
/// 순수 Dart다. 좌표 목록을 손으로 먹여 테스트한다.
class LocationSmoother {
  final _latitude = KalmanFilter1D();
  final _longitude = KalmanFilter1D();

  /// 보정한 좌표를 돌려준다. **위경도 말고는 원본 그대로 실어 보낸다** —
  /// 보정 대상은 위치뿐이고, 나머지를 만들어내면 뒤에서 그것을 믿게 된다.
  ///
  /// ⚠️ **[GeoPoint]에 필드를 더하면 여기에도 더해야 한다.** 새 `GeoPoint`를
  /// 만들어 돌려주므로 빠뜨린 필드는 조용히 `null`이 된다. 컴파일도 통과하고
  /// 테스트도 통과했다 — 기기에서 저장된 값을 눈으로 보고서야 고도와 방향이
  /// 통째로 비어 있는 것을 찾았다.
  GeoPoint smooth(GeoPoint point) {
    final q = _q(point.speed);
    final r = _r(point.accuracy);

    return GeoPoint(
      latitude: _latitude.filter(point.latitude, q: q, r: r),
      longitude: _longitude.filter(point.longitude, q: q, r: r),
      recordedAt: point.recordedAt,
      accuracy: point.accuracy,
      speed: point.speed,
      // 고도는 거리 계산에 쓰지 않으므로 거르지 않는다. 방향은 각도라
      // 359°와 1°의 평균이 180°가 되어 **선형 필터를 걸면 안 된다.**
      altitude: point.altitude,
      heading: point.heading,
    );
  }

  /// 러닝을 새로 시작할 때 부른다. 지난 러닝의 마지막 위치가 남아 있으면
  /// 초반 좌표가 그쪽으로 끌려온다.
  void reset() {
    _latitude.reset();
    _longitude.reset();
  }

  /// 측정 노이즈 — **이 좌표를 얼마나 못 믿는가.**
  ///
  /// 오차 반경이 클수록 크다. 크면 칼만 이득이 작아져 측정값이 덜 반영된다.
  static double _r(double accuracy) {
    if (accuracy < 5) return 0.01;
    if (accuracy <= 10) return 0.05;
    return 0.1;
  }

  /// 프로세스 노이즈 — **위치가 실제로 얼마나 변했을 만한가.**
  ///
  /// 빠를수록 크다. 크면 이득이 커져 새 측정을 더 받아들인다 — 달리는 중에
  /// 작게 두면 필터가 뒤처져 경로가 실제보다 짧아진다.
  ///
  /// ⚠️ 센서가 속도를 못 구하면 음수가 온다. 그때는 멈춰 있다고 본다 —
  /// 첫 좌표는 어차피 그대로 통과하고, 그다음부터는 대개 값이 들어온다.
  static double _q(double speed) {
    if (speed < 1) return 0.005;
    if (speed < 3) return 0.01;
    if (speed <= 6) return 0.02;
    return 0.05;
  }
}
