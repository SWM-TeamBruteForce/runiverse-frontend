import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record/domain/route_segments.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';

/// 서버 경로를 **선으로 이을 수 있는 토막**으로 가른다 — 1.1.0 가이드 4.2.
///
/// ## ⚠️ 이 규칙이 없으면 가 보지 않은 길에 선이 생긴다
///
/// 서버는 정지 구간과 오염 좌표를 빼고 경로를 준다. 빠진 자리의 양 끝을
/// 그대로 이으면 **지하철로 지나간 구간이 뛴 경로로 그려진다.**
void main() {
  /// 위도만 북쪽으로 [meters] 옮긴 좌표. `distanceTo`가 쓰는 반지름으로
  /// 되짚어 계산해 **요청한 미터가 그대로 나오게** 한다 — 111320 같은 다른
  /// 값을 쓰면 30m를 넣었는데 29.97m가 되어 경계 판정이 뒤집힌다.
  GeoPoint at(double meters) => GeoPoint(
    latitude: 37.4979 + meters / (6371000.0 * math.pi / 180),
    longitude: 127.0276,
    recordedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  List<List<double>> metersOf(List<List<GeoPoint>> segments) => [
    for (final segment in segments)
      [
        for (final point in segment)
          ((point.latitude - 37.4979) * (6371000.0 * math.pi / 180))
              .roundToDouble(),
      ],
  ];

  test('가까이 이어진 좌표는 한 줄로 남는다', () {
    final segments = RouteSegments.split([at(0), at(6), at(12), at(18)]);

    expect(segments, hasLength(1));
    expect(metersOf(segments), [
      [0, 6, 12, 18],
    ]);
  });

  test('⚠️ 30m를 넘게 벌어지면 거기서 끊는다', () {
    // ⚠️ **이것이 안 되면 빠진 구간이 직선으로 이어진다.**
    final segments = RouteSegments.split([
      at(0),
      at(10),
      at(10 + 31), // 31m 점프
      at(10 + 31 + 10),
    ]);

    expect(segments, hasLength(2));
    expect(metersOf(segments), [
      [0, 10],
      [41, 51],
    ]);
  });

  test('⚠️ 딱 경계만큼 떨어진 점은 잇는다', () {
    // 가이드는 "30m를 **초과**"라고 적었다. 경계를 끊으면 멀쩡한 선이 끊긴다.
    //
    // ⚠️ **한계를 직접 재서 넘긴다.** `at(30)`으로 30m를 만들어 봤자 하버사인이
    // 29.999…를 주므로 `>`와 `>=`가 똑같이 통과한다 — 그물이 비어 있었다.
    // 실제로 나온 거리를 그대로 한계로 쓰면 등호가 걸리는 쪽만 끊긴다.
    final gap = at(0).distanceTo(at(30));

    final segments = RouteSegments.split([at(0), at(30)], maxGapMeters: gap);

    expect(segments, hasLength(1));
  });

  test('⚠️ 간격은 바로 앞 점과만 잰다', () {
    // 한 토막의 **시작점**에서 재면, 10m씩 꾸준히 간 사람이 네 번째 점에서
    // 통째로 끊긴다 — 가이드가 말한 것은 "이웃한 두 점"이다.
    final segments = RouteSegments.split([
      for (var i = 0; i <= 10; i++) at(10.0 * i),
    ]);

    expect(segments, hasLength(1));
    expect(segments.single, hasLength(11));
  });

  test('⚠️ 양쪽이 끊긴 외톨이 점은 버린다', () {
    // 혼자서는 선이 못 된다. 남겨 두면 지도 위젯의 "구간은 좌표 2개 이상"
    // 약속이 깨진다.
    final segments = RouteSegments.split([
      at(0),
      at(10),
      at(200), // 외톨이
      at(400),
      at(410),
    ]);

    expect(metersOf(segments), [
      [0, 10],
      [400, 410],
    ]);
  });

  test('좌표가 하나면 그릴 선이 없다', () {
    expect(RouteSegments.split([at(0)]), isEmpty);
    expect(RouteSegments.split([]), isEmpty);
  });

  test('끊긴 뒤에도 계속 센다', () {
    // 끊김이 둘 이상이어도 토막이 그만큼 나와야 한다.
    final segments = RouteSegments.split([
      at(0),
      at(10),
      at(100),
      at(110),
      at(300),
      at(310),
    ]);

    expect(segments, hasLength(3));
  });
}
