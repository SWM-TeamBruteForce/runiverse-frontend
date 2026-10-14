import 'package:runiverse/features/session/domain/geo_point.dart';

/// 서버가 준 경로 한 줄을 **선으로 이을 수 있는 토막들**로 가른다 —
/// 1.1.0 가이드 4.2.
///
/// ## ⚠️ 멀리 떨어진 두 점은 잇지 않는다
///
/// 서버는 정지 구간과 오염 좌표를 빼고 경로를 준다. 빠진 자리의 양 끝을
/// 그대로 이으면 **가 본 적 없는 길에 선이 그려진다** — 좌표가 튀어 제외된
/// 구간이나, 신호를 못 받아 관측하지 못한 이동이 거기 숨어 있다. 지하철로
/// 몇 정거장을 이동한 뒤 다시 잡힌 좌표가 직선으로 이어지는 식이다.
///
/// 그래서 **이웃한 두 점이 [maxGapMeters]를 넘게 떨어져 있으면 선을 끊고**
/// 다음 점부터 새 토막을 시작한다. 가이드가 전체 지도와 구간별 지도에 같이
/// 적용하라고 적은 규칙이다.
///
/// ## 혼자 남은 점은 버린다
///
/// 양쪽이 모두 끊긴 점은 선이 될 수 없다. 지도 위젯도 좌표가 2개 미만인
/// 토막은 그리지 않으므로, 여기서 미리 걸러 **"각 구간은 좌표 2개 이상"**
/// 이라는 그쪽 약속을 지킨다.
///
/// 순수 Dart다. 좌표 목록을 손으로 먹여 테스트한다.
abstract final class RouteSegments {
  const RouteSegments._();

  /// 이보다 멀면 잇지 않는다. 가이드가 못 박은 값이다.
  static const maxGapMeters = 30.0;

  /// [points]를 순서대로 훑어 토막 목록으로 만든다.
  ///
  /// 좌표가 2개 미만이면 빈 목록이다 — 그릴 선이 없다.
  static List<List<GeoPoint>> split(
    List<GeoPoint> points, {
    double maxGapMeters = RouteSegments.maxGapMeters,
  }) {
    if (points.length < 2) return const [];

    final segments = <List<GeoPoint>>[];
    var current = <GeoPoint>[points.first];

    for (var i = 1; i < points.length; i++) {
      final point = points[i];
      if (current.last.distanceTo(point) > maxGapMeters) {
        // 선을 끊는다. 지금까지 모은 것이 선이 될 만하면 남긴다.
        if (current.length > 1) segments.add(current);
        current = <GeoPoint>[point];
        continue;
      }
      current.add(point);
    }
    if (current.length > 1) segments.add(current);

    return segments;
  }
}
