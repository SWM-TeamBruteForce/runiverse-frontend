import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:integration_test/integration_test.dart';

/// **진단용.** geolocator가 실제로 무엇을 주는지 그대로 찍는다.
///
/// 저장된 방향이 계속 0에 가까웠다. 원인이 셋 중 어느 것인지 코드만 봐서는
/// 모른다.
///
/// 1. 기기·에뮬레이터가 방위를 아예 안 준다 (`hasBearing()`이 false)
/// 2. 방위는 주는데 값이 틀렸다
/// 3. 우리가 옮겨 담는 중에 잃어버린다
///
/// 그래서 `Position`을 가공 없이 찍고, **연속한 두 점으로 직접 계산한 방위**를
/// 나란히 둔다. 셋을 비교하면 어디서 어긋나는지 한 번에 보인다.
///
/// 에뮬레이터에서는 `adb emu geo fix`로, 실기기에서는 실제로 걸으면서 돌린다.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('원본 Position을 그대로 찍는다', (tester) async {
    await tester.runAsync(() async {
      if (!await Geolocator.isLocationServiceEnabled()) {
        fail('기기의 위치 기능이 꺼져 있다');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      expect(
        permission,
        anyOf(LocationPermission.always, LocationPermission.whileInUse),
        reason: '위치 권한이 필요하다',
      );

      // 앱이 쓰는 것과 같은 설정이어야 의미가 있다.
      final stream = Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
          forceLocationManager: false,
          intervalDuration: const Duration(seconds: 1),
        ),
      );

      final seen = <Position>[];
      final done = Completer<void>();
      final subscription = stream.listen((position) {
        seen.add(position);
        _print(position, seen.length > 1 ? seen[seen.length - 2] : null);
        if (seen.length >= 15 && !done.isCompleted) done.complete();
      });

      await done.future.timeout(
        const Duration(seconds: 90),
        onTimeout: () => debugPrint('[RAW] 90초 안에 15개를 못 받았다'),
      );
      await subscription.cancel();

      expect(seen, isNotEmpty, reason: '좌표가 하나도 안 왔다');

      final withBearing = seen.where((p) => p.heading > 0.5).length;
      debugPrint(
        '[RAW] ── 정리 ── 받은 ${seen.length}개 중 '
        '방위가 0.5도 넘는 것 $withBearing개',
      );
    });
  }, timeout: const Timeout(Duration(minutes: 3)));
}

void _print(Position p, Position? previous) {
  final computed = previous == null
      ? null
      : _bearing(
          previous.latitude,
          previous.longitude,
          p.latitude,
          p.longitude,
        );

  debugPrint(
    '[RAW] heading=${p.heading.toStringAsFixed(4)} '
    'headingAcc=${p.headingAccuracy.toStringAsFixed(4)} '
    '| 직접계산=${computed?.toStringAsFixed(1) ?? '--'} '
    '| speed=${p.speed.toStringAsFixed(3)} '
    'speedAcc=${p.speedAccuracy.toStringAsFixed(3)} '
    '| alt=${p.altitude.toStringAsFixed(1)} '
    'acc=${p.accuracy.toStringAsFixed(1)} '
    'mocked=${p.isMocked}',
  );
}

/// 두 좌표 사이의 방위각. 0~360도, 정북이 0이고 시계방향이다.
double _bearing(double lat1, double lon1, double lat2, double lon2) {
  const toRad = math.pi / 180;
  final phi1 = lat1 * toRad;
  final phi2 = lat2 * toRad;
  final deltaLambda = (lon2 - lon1) * toRad;

  final y = math.sin(deltaLambda) * math.cos(phi2);
  final x =
      math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(deltaLambda);

  return (math.atan2(y, x) / toRad + 360) % 360;
}
