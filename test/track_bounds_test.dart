import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/track_bounds.dart';

/// 결과 화면의 지도가 **경로 전체를 담도록** 카메라에 넘길 상자.
///
/// ## ⚠️ 이 계산이 없어서 결과 화면이 엉뚱한 곳을 보여줬다
///
/// 결과 화면이 러닝 중 지도(`RunMapView`)를 그대로 썼고, 그 위젯은 화면과
/// 무관하게 `setLocationTrackingMode(follow)` 를 켰다. 다 달린 기록을 보는데
/// **카메라가 지금 내 위치로 가서 따라 움직였고**, 경로는 화면 밖에 있었다.
///
/// 상자는 SDK에 넘기기 전에 두 가지를 막아야 한다 — 둘 다 실제로 터지는
/// 자리라 여기서 센다.
void main() {
  GeoPoint at(double latitude, double longitude) => GeoPoint(
    latitude: latitude,
    longitude: longitude,
    recordedAt: DateTime(2026, 10, 12),
  );

  test('경로를 전부 담는다', () {
    final bounds = TrackBounds.of([
      [at(37.50, 127.00), at(37.52, 127.04)],
      [at(37.49, 127.06), at(37.51, 127.02)],
    ])!;

    expect(bounds.south, 37.49);
    expect(bounds.north, 37.52);
    expect(bounds.west, 127.00);
    expect(bounds.east, 127.06);
  });

  test('⚠️ 구간이 나뉘어도 끊긴 쪽을 빠뜨리지 않는다', () {
    // 일시정지로 구간이 갈린다. 마지막 구간만 보면 앞쪽이 화면 밖에 남는다.
    final bounds = TrackBounds.of([
      [at(37.40, 127.00), at(37.41, 127.01)],
      [at(37.60, 127.20), at(37.61, 127.21)],
    ])!;

    expect(bounds.south, 37.40);
    expect(bounds.north, 37.61);
  });

  group('⚠️ SDK 에 그대로 넘기면 터지는 것', () {
    test('좌표가 하나도 없으면 null 이다', () {
      // GPS를 못 잡은 러닝이 있다. `NLatLngBounds.from([])` 은
      // **ArgumentError** 를 던진다 — 결과 화면이 통째로 죽는다.
      expect(TrackBounds.of([]), isNull);
      expect(TrackBounds.of([[], []]), isNull);
    });

    test('⚠️ 제자리에서 끝난 러닝도 상자가 생긴다', () {
      // 좌표가 전부 같으면 상자가 **한 점**이고, `fitBounds` 는 거기에
      // 맞추려고 끝까지 확대한다. 길 이름 하나만 남는다.
      final bounds = TrackBounds.of([
        [at(37.5, 127.0), at(37.5, 127.0)],
      ])!;

      expect(bounds.north - bounds.south, closeTo(TrackBounds.minSpan, 1e-12));
      expect(bounds.east - bounds.west, closeTo(TrackBounds.minSpan, 1e-12));
    });

    test('⚠️ 넓힐 때 가운데가 밀리지 않는다', () {
      final bounds = TrackBounds.of([
        [at(37.5, 127.0)],
      ])!;

      expect((bounds.north + bounds.south) / 2, closeTo(37.5, 1e-12));
      expect((bounds.east + bounds.west) / 2, closeTo(127.0, 1e-12));
    });

    test('한쪽만 좁으면 그쪽만 넓힌다', () {
      // 직선으로만 달리면 한 축이 0이다. 멀쩡한 축까지 넓히면 경로가
      // 화면에서 쓸데없이 작아진다.
      final bounds = TrackBounds.of([
        [at(37.50, 127.0), at(37.52, 127.0)],
      ])!;

      expect(bounds.north - bounds.south, closeTo(0.02, 1e-12), reason: '그대로');
      expect(bounds.east - bounds.west, closeTo(TrackBounds.minSpan, 1e-12));
    });
  });
}
