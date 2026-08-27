import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/kalman_filter.dart';
import 'package:runiverse/features/session/domain/location_smoother.dart';

/// 좌표 보정 — **제자리 표류를 얼마나 줄이는가.**
///
/// 순수 계산이라 실기기가 필요 없다. 흔들리는 좌표를 손으로 만들어 먹인다.
void main() {
  /// 한 자리에서 흔들리는 좌표들.
  ///
  /// 실제 GPS 잡음처럼 **재현 가능한 난수**로 만든다 — 씨앗을 고정해야 테스트가
  /// 돌 때마다 다른 답이 나오지 않는다.
  List<GeoPoint> jitterAt(
    double lat,
    double lon, {
    required int count,
    required double metres,
    double accuracy = 8,
    double speed = 0,
    int seed = 42,
  }) {
    final random = math.Random(seed);
    // 위도 1도 ≈ 111km. 미터를 도로 옮긴다.
    final delta = metres / 111000;
    final start = DateTime(2026, 8, 25, 19);

    return [
      for (var i = 0; i < count; i++)
        GeoPoint(
          latitude: lat + (random.nextDouble() - 0.5) * 2 * delta,
          longitude: lon + (random.nextDouble() - 0.5) * 2 * delta,
          recordedAt: start.add(Duration(seconds: i)),
          accuracy: accuracy,
          speed: speed,
        ),
    ];
  }

  double totalDistance(List<GeoPoint> points) {
    var sum = 0.0;
    for (var i = 1; i < points.length; i++) {
      sum += points[i - 1].distanceTo(points[i]);
    }
    return sum;
  }

  group('칼만 필터', () {
    test('첫 값은 그대로 통과한다', () {
      // 임의의 초기값에서 출발하면 처음 몇 초 동안 좌표가 그 값에서 끌려온다.
      final filter = KalmanFilter1D();

      expect(filter.filter(37.5665, q: 0.01, r: 0.05), 37.5665);
    });

    test('같은 입력에는 같은 답을 준다', () {
      double run() {
        final filter = KalmanFilter1D();
        var last = 0.0;
        for (final v in [1.0, 1.5, 0.8, 1.2, 1.1]) {
          last = filter.filter(v, q: 0.01, r: 0.05);
        }
        return last;
      }

      expect(run(), run());
    });

    test('⚠️ reset하지 않으면 지난 위치에서 끌려온다', () {
      final filter = KalmanFilter1D();
      filter.filter(37.5, q: 0.01, r: 0.05);

      // 멀리 떨어진 곳에서 다시 시작한다.
      final dragged = filter.filter(35.1, q: 0.01, r: 0.05);
      expect(dragged, greaterThan(35.1));

      filter.reset();
      expect(filter.filter(35.1, q: 0.01, r: 0.05), 35.1);
    });

    test('측정을 믿을수록(R이 작을수록) 측정값에 가깝다', () {
      double after(double r) {
        final filter = KalmanFilter1D()..filter(0, q: 0.01, r: r);
        return filter.filter(10, q: 0.01, r: r);
      }

      // R이 작으면 새 측정을 크게 반영한다.
      expect(after(0.01), greaterThan(after(0.1)));
    });
  });

  group('좌표 보정', () {
    test('⚠️ 제자리에서 쌓이는 거리를 줄인다', () {
      // 이 테스트가 이 기능의 존재 이유다. 서 있는데 거리가 늘면 기록을 믿을 수 없다.
      final raw = jitterAt(37.5665, 126.9780, count: 60, metres: 5);
      final smoother = LocationSmoother();
      final smoothed = [for (final p in raw) smoother.smooth(p)];

      final before = totalDistance(raw);
      final after = totalDistance(smoothed);

      expect(before, greaterThan(0));
      expect(after, lessThan(before / 2));
    });

    test('시각·정확도·속도는 원본 그대로 둔다', () {
      // 보정 대상은 위치뿐이다. 나머지를 만들어내면 뒤에서 그것을 믿게 된다.
      final point = GeoPoint(
        latitude: 37.5,
        longitude: 127.0,
        recordedAt: DateTime(2026, 8, 25, 19, 30),
        accuracy: 7.5,
        speed: 3.2,
      );

      final smoothed = LocationSmoother().smooth(point);

      expect(smoothed.recordedAt, point.recordedAt);
      expect(smoothed.accuracy, 7.5);
      expect(smoothed.speed, 3.2);
    });

    test('첫 좌표는 그대로 통과한다', () {
      final point = GeoPoint(
        latitude: 37.5665,
        longitude: 126.9780,
        recordedAt: DateTime(2026, 8, 25, 19),
        accuracy: 8,
      );

      final smoothed = LocationSmoother().smooth(point);

      expect(smoothed.latitude, point.latitude);
      expect(smoothed.longitude, point.longitude);
    });

    test('⚠️ 달릴 때는 실제 이동을 따라간다', () {
      // 제자리 떨림만 잡고 진짜 이동까지 눌러버리면 경로가 실제보다 짧아진다.
      final start = DateTime(2026, 8, 25, 19);
      final moving = [
        for (var i = 0; i < 40; i++)
          GeoPoint(
            // 1초에 약 3m씩 곧게 나아간다.
            latitude: 37.5665 + i * 3 / 111000,
            longitude: 126.9780,
            recordedAt: start.add(Duration(seconds: i)),
            accuracy: 4,
            speed: 3,
          ),
      ];

      final smoother = LocationSmoother();
      final smoothed = [for (final p in moving) smoother.smooth(p)];

      final actual = totalDistance(moving);
      final measured = totalDistance(smoothed);

      // 조금 뒤처지는 것은 필터의 성질이다. 절반 아래로 떨어지면 못 쓴다.
      expect(measured, greaterThan(actual * 0.7));
    });

    test('reset하면 새 러닝이 지난 위치에 끌리지 않는다', () {
      final smoother = LocationSmoother()
        ..smooth(
          GeoPoint(
            latitude: 37.5,
            longitude: 127.0,
            recordedAt: DateTime(2026, 8, 25, 19),
          ),
        );

      smoother.reset();
      final fresh = smoother.smooth(
        GeoPoint(
          latitude: 35.1,
          longitude: 129.0,
          recordedAt: DateTime(2026, 8, 25, 20),
        ),
      );

      expect(fresh.latitude, 35.1);
      expect(fresh.longitude, 129.0);
    });

    test('⚠️ 위경도 말고는 원본 그대로 나온다', () {
      // 보정은 새 `GeoPoint`를 만들어 돌려준다. 옮겨 담는 것을 빠뜨리면
      // 그 값은 **조용히 `null`이 된다** — 실제로 고도와 방향이 그렇게
      // 사라져 DB에 한 번도 저장되지 않았다.
      final smoothed = LocationSmoother().smooth(
        GeoPoint(
          latitude: 37.5665,
          longitude: 126.978,
          recordedAt: DateTime(2026, 8, 27, 5, 40, 48),
          accuracy: 7.5,
          speed: 2.8,
          altitude: 38.2,
          heading: 45.7,
        ),
      );

      expect(smoothed.altitude, 38.2, reason: '고도는 거르지 않고 그대로 간다');
      expect(smoothed.heading, 45.7, reason: '방향은 각도라 선형 필터를 걸면 안 된다');
      expect(smoothed.accuracy, 7.5);
      expect(smoothed.speed, 2.8);
      expect(smoothed.recordedAt, DateTime(2026, 8, 27, 5, 40, 48));
    });
  });
}
