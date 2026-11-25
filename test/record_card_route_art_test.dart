import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';

/// 좌표 하나. 선 아트는 위경도만 보므로 나머지는 아무 값이어도 된다.
GeoPoint _p(double lat, double lon) =>
    GeoPoint(latitude: lat, longitude: lon, recordedAt: DateTime(2026, 9, 2));

void main() {
  group('normalizeRoute', () {
    test('⚠️ 경도에 cos(위도)를 곱한다 — 안 하면 동서로 늘어난다', () {
      // 서울 언저리에서 남북 0.01도, 동서 0.01도인 ㄱ자.
      // 도 수는 같지만 실제 거리는 동서가 cos(37.5°) ≈ 0.7934 배다.
      final art = normalizeRoute([
        [_p(37.50, 127.00), _p(37.51, 127.00), _p(37.51, 127.01)],
      ]);

      expect(art.aspect, closeTo(math.cos(37.505 * math.pi / 180), 0.002));
    });

    test('조각 수를 지킨다 — 일시정지로 끊긴 선을 잇지 않는다', () {
      final art = normalizeRoute([
        [_p(37.50, 127.00), _p(37.51, 127.01)],
        [_p(37.52, 127.02), _p(37.53, 127.03)],
      ]);

      expect(art.strokes, hasLength(2));
      expect(art.strokes.first, hasLength(2));
    });

    test('정규화하면 모든 좌표가 0과 1 사이다', () {
      final art = normalizeRoute([
        [_p(37.50, 127.00), _p(37.55, 127.02), _p(37.52, 127.08)],
      ]);

      for (final stroke in art.strokes) {
        for (final point in stroke) {
          expect(point.x, inInclusiveRange(0, 1));
          expect(point.y, inInclusiveRange(0, 1));
        }
      }
    });

    test('⚠️ 위도는 위로, 화면 y는 아래로 커진다 — 북쪽이 작은 y다', () {
      final art = normalizeRoute([
        [_p(37.50, 127.00), _p(37.60, 127.00)],
      ]);

      final south = art.strokes.single.first;
      final north = art.strokes.single.last;
      expect(north.y, lessThan(south.y));
    });

    test('⚠️ 점이 하나뿐이면 가운데 한 점이다 — 0으로 나누지 않는다', () {
      final art = normalizeRoute([
        [_p(37.50, 127.00)],
      ]);

      expect(art.strokes.single.single.x, 0.5);
      expect(art.strokes.single.single.y, 0.5);
      expect(art.aspect, 1.0);
    });

    test('⚠️ 모든 점이 같은 좌표여도 터지지 않는다 — 트레드밀', () {
      final art = normalizeRoute([
        [for (var i = 0; i < 50; i++) _p(37.50, 127.00)],
      ]);

      expect(art.strokes.single, hasLength(50));
      for (final point in art.strokes.single) {
        expect(point.x, 0.5);
        expect(point.y, 0.5);
      }
    });

    test('⚠️ 남북으로만 움직이면 세로선이 된다 — 가로 폭이 0이다', () {
      final art = normalizeRoute([
        [_p(37.50, 127.00), _p(37.60, 127.00)],
      ]);

      for (final point in art.strokes.single) {
        expect(point.x, 0.5);
      }
      expect(art.aspect, lessThan(0.1));
    });

    test('빈 트랙은 RouteArt.empty다', () {
      expect(normalizeRoute(const []).isEmpty, isTrue);
      expect(
        normalizeRoute(const <List<GeoPoint>>[<GeoPoint>[]]).isEmpty,
        isTrue,
      );
    });
  });

  group('fitRoute', () {
    /// 네 귀퉁이를 다 쓰는 0~1 경로. [aspect]만 바꿔 가며 쓴다.
    RouteArt square(double aspect) => RouteArt(
      strokes: const [
        [RoutePoint(0, 0), RoutePoint(1, 1)],
      ],
      aspect: aspect,
    );

    test('가로세로 비를 지키며 가운데에 앉힌다', () {
      // 가로:세로 = 1:2 인 경로를 100x100 상자에 넣으면 세로로 꽉 차고
      // 가로는 가운데 50폭(25~75)만 쓴다.
      final fitted = fitRoute(square(0.5), width: 100, height: 100, padding: 0);

      expect(fitted.single.first.x, closeTo(25, 0.001));
      expect(fitted.single.first.y, closeTo(0, 0.001));
      expect(fitted.single.last.x, closeTo(75, 0.001));
      expect(fitted.single.last.y, closeTo(100, 0.001));
    });

    test('가로로 긴 경로는 가로에 맞추고 세로를 가운데 둔다', () {
      final fitted = fitRoute(square(2), width: 100, height: 100, padding: 0);

      expect(fitted.single.first.x, closeTo(0, 0.001));
      expect(fitted.single.first.y, closeTo(25, 0.001));
      expect(fitted.single.last.x, closeTo(100, 0.001));
      expect(fitted.single.last.y, closeTo(75, 0.001));
    });

    test('padding만큼 안쪽으로 들인다', () {
      final fitted = fitRoute(
        square(0.5),
        width: 100,
        height: 100,
        padding: 10,
      );

      expect(fitted.single.first.x, closeTo(30, 0.001));
      expect(fitted.single.first.y, closeTo(10, 0.001));
      expect(fitted.single.last.x, closeTo(70, 0.001));
      expect(fitted.single.last.y, closeTo(90, 0.001));
    });

    test('빈 경로는 빈 결과다', () {
      expect(
        fitRoute(RouteArt.empty, width: 100, height: 100, padding: 0),
        isEmpty,
      );
    });

    test('⚠️ padding이 상자보다 크면 터지지 않는다', () {
      final fitted = fitRoute(square(1), width: 10, height: 10, padding: 20);

      for (final point in fitted.single) {
        expect(point.x.isFinite, isTrue);
        expect(point.y.isFinite, isTrue);
      }
    });
  });
}
