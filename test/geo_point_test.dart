import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';

/// 좌표 하나가 아는 순수 계산 — **거리와 방위.**
///
/// 실기기가 필요 없다. 값을 손으로 넣고 답을 안다.
void main() {
  final at = DateTime(2026, 8, 27, 19);

  GeoPoint point(double lat, double lon) =>
      GeoPoint(latitude: lat, longitude: lon, recordedAt: at);

  group('거리', () {
    test('위도 0.001도는 약 111미터다', () {
      // 위도 1도 = 약 111.19km. 경도와 달리 위치에 상관없이 일정하다.
      final metres = point(37.5, 127).distanceTo(point(37.501, 127));

      expect(metres, closeTo(111.19, 0.5));
    });

    test('같은 점은 0이다', () {
      expect(point(37.5, 127).distanceTo(point(37.5, 127)), 0);
    });

    test('⚠️ 경도 1도는 위도에 따라 짧아진다', () {
      // 위경도 차를 그냥 빼면 안 되는 이유다. 서울(37.5도)에서 경도 1도는
      // 적도의 약 79%다.
      final atSeoul = point(37.5, 127).distanceTo(point(37.5, 128));
      final atEquator = point(0, 127).distanceTo(point(0, 128));

      expect(
        atSeoul / atEquator,
        closeTo(math.cos(37.5 * math.pi / 180), 0.01),
      );
    });
  });

  group('방위', () {
    /// 서울 위도에서 [metres]만큼 북쪽·동쪽으로 간 점.
    ///
    /// 경도는 위도에 따라 좁아지므로 `cos`으로 나눠야 실제 동쪽 거리가 맞는다.
    /// 안 나누면 45도를 기대한 자리에서 34도가 나온다.
    GeoPoint offset(double north, double east) {
      const lat = 37.5;
      const perDegree = 111320.0;
      return point(
        lat + north / perDegree,
        127.0 + east / (perDegree * math.cos(lat * math.pi / 180)),
      );
    }

    final origin = point(37.5, 127.0);

    test('정북은 0도다', () {
      expect(origin.bearingTo(offset(100, 0)), closeTo(0, 0.5));
    });

    test('정동은 90도다', () {
      expect(origin.bearingTo(offset(0, 100)), closeTo(90, 0.5));
    });

    test('정남은 180도다', () {
      expect(origin.bearingTo(offset(-100, 0)), closeTo(180, 0.5));
    });

    test('⚠️ 정서는 270도다. 음수가 아니다', () {
      // atan2는 -90을 준다. 서버가 0~360을 요구하므로 옮겨야 한다.
      expect(origin.bearingTo(offset(0, -100)), closeTo(270, 0.5));
    });

    test('북동은 45도다', () {
      expect(origin.bearingTo(offset(100, 100)), closeTo(45, 0.5));
    });

    test('⚠️ 답은 항상 0 이상 360 미만이다', () {
      // 어느 방향으로 가든 서버가 거절할 값이 나오면 안 된다.
      for (var degrees = 0; degrees < 360; degrees += 15) {
        final radians = degrees * math.pi / 180;
        final bearing = origin.bearingTo(
          offset(100 * math.cos(radians), 100 * math.sin(radians)),
        );

        expect(bearing, inInclusiveRange(0, 359.9999));
        expect(bearing, closeTo(degrees.toDouble(), 0.5));
      }
    });

    test('⚠️ 에뮬레이터에서 센서가 0을 줄 때도 실제 방향이 나온다', () {
      // 이 값들이 실제로 겪은 것이다. heading은 0.007도였고 직접 계산은
      // 45도 근처였다. 회귀하면 여기서 걸린다.
      final from = GeoPoint(
        latitude: 37.567676,
        longitude: 126.979481,
        recordedAt: at,
        heading: 0.0074,
      );
      final to = GeoPoint(
        latitude: 37.567694,
        longitude: 126.979503,
        recordedAt: at,
        heading: 0.0066,
      );

      expect(from.bearingTo(to), closeTo(45, 5));
    });
  });
}
