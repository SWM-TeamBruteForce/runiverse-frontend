import 'package:runiverse/features/session/domain/geo_point.dart';

/// 경로를 담는 사각형. **위경도만 든다** — 지도 SDK를 모른다.
///
/// 순수 계산이라 테스트가 쉽고, `core/widgets/run_map_view.dart` 가 이것을
/// SDK 타입으로 옮긴다.
class TrackBounds {
  const TrackBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;

  /// 너무 좁은 상자를 넓히는 최소 변. 위도 약 100m.
  ///
  /// 제자리에서 끝난 러닝은 상자가 **한 점**이고, 그대로 넘기면 지도가
  /// 끝까지 확대해 길 이름 하나만 남는다.
  ///
  /// ⚠️ 경도에도 같은 각도를 쓴다. 서울에서 경도 1도는 위도 1도보다
  /// 짧아(약 88km 대 111km) 가로가 조금 좁지만, 이 값은 **바닥**이라
  /// 정확할 필요가 없다.
  static const minSpan = 0.0009;

  /// 달린 경로를 담는 상자. **그릴 것이 없으면 `null`.**
  ///
  /// ⚠️ `null` 을 꼭 다뤄야 한다. 좌표가 하나도 없는 기록이 있다 — GPS를
  /// 못 잡은 러닝이다. 그대로 `NLatLngBounds.from` 에 넘기면 빈 목록이라
  /// **ArgumentError** 가 난다.
  static TrackBounds? of(List<List<GeoPoint>> track) {
    double? south, west, north, east;

    for (final segment in track) {
      for (final point in segment) {
        south = south == null || point.latitude < south
            ? point.latitude
            : south;
        north = north == null || point.latitude > north
            ? point.latitude
            : north;
        west = west == null || point.longitude < west ? point.longitude : west;
        east = east == null || point.longitude > east ? point.longitude : east;
      }
    }

    if (south == null || west == null || north == null || east == null) {
      return null;
    }

    return TrackBounds(
      south: south,
      west: west,
      north: north,
      east: east,
    )._widened();
  }

  /// 변이 [minSpan] 보다 짧으면 **가운데를 두고** 넓힌다.
  TrackBounds _widened() {
    final latitudeGap = minSpan - (north - south);
    final longitudeGap = minSpan - (east - west);
    if (latitudeGap <= 0 && longitudeGap <= 0) return this;

    final latitudePad = latitudeGap > 0 ? latitudeGap / 2 : 0.0;
    final longitudePad = longitudeGap > 0 ? longitudeGap / 2 : 0.0;

    return TrackBounds(
      south: south - latitudePad,
      west: west - longitudePad,
      north: north + latitudePad,
      east: east + longitudePad,
    );
  }
}
