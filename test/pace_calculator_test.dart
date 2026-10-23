import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/pace_calculator.dart';

/// 거리와 페이스 — 순수 계산. 실기기도 시계도 필요 없다.
void main() {
  final origin = DateTime(2026, 8, 5, 19);

  GeoPoint at(double lat, double lon, {int seconds = 0}) => GeoPoint(
    latitude: lat,
    longitude: lon,
    recordedAt: origin.add(Duration(seconds: seconds)),
  );

  group('두 좌표 사이의 거리', () {
    test('같은 자리면 0이다', () {
      expect(at(37.5, 127).distanceTo(at(37.5, 127)), 0);
    });

    test('위도 0.001도는 약 111m다', () {
      // 위도 1도 = 약 111km. 어느 위도에서나 같다.
      final meters = at(37.5, 127).distanceTo(at(37.501, 127));

      expect(meters, closeTo(111, 1));
    });

    test('방향이 바뀌어도 거리는 같다', () {
      final a = at(37.5, 127);
      final b = at(37.51, 127.01);

      expect(a.distanceTo(b), closeTo(b.distanceTo(a), 0.001));
    });
  });

  group('누적 거리', () {
    test('좌표가 하나면 0이다', () {
      expect(PaceCalculator.totalMeters([at(37.5, 127)]), 0);
    });

    test('좌표가 없으면 0이다', () {
      expect(PaceCalculator.totalMeters([]), 0);
    });

    test('구간을 순서대로 더한다', () {
      final points = [at(37.5, 127), at(37.501, 127), at(37.502, 127)];

      // 같은 간격 두 번이므로 한 구간의 두 배다.
      expect(PaceCalculator.totalMeters(points), closeTo(222, 2));
    });
  });

  group('페이스 환산', () {
    test('1km를 5분에 뛰면 5분 페이스다', () {
      final pace = PaceCalculator.perKilometer(
        meters: 1000,
        elapsed: const Duration(minutes: 5),
      );

      expect(pace, const Duration(minutes: 5));
    });

    test('500m를 2분 46초에 뛰면 5분 32초 페이스다', () {
      final pace = PaceCalculator.perKilometer(
        meters: 500,
        elapsed: const Duration(minutes: 2, seconds: 46),
      );

      expect(pace!.inSeconds, 332);
    });

    test('거리가 너무 짧으면 내지 않는다', () {
      // 출발 직후 몇 미터에서 나온 페이스는 의미가 없다.
      final pace = PaceCalculator.perKilometer(
        meters: 5,
        elapsed: const Duration(seconds: 3),
      );

      expect(pace, isNull);
    });

    test('거리가 0이면 내지 않는다 — 0으로 나누지 않는다', () {
      expect(
        PaceCalculator.perKilometer(
          meters: 0,
          elapsed: const Duration(minutes: 1),
        ),
        isNull,
      );
    });

    test('시간이 0이면 내지 않는다', () {
      expect(
        PaceCalculator.perKilometer(meters: 1000, elapsed: Duration.zero),
        isNull,
      );
    });
  });

  group('페이스 표기', () {
    test('분과 초를 따옴표로 적는다', () {
      expect(
        PaceCalculator.format(const Duration(minutes: 5, seconds: 32)),
        "5'32\"",
      );
    });

    test('초가 한 자리면 앞을 0으로 채운다', () {
      expect(
        PaceCalculator.format(const Duration(minutes: 5, seconds: 3)),
        "5'03\"",
      );
    });

    test('낼 수 없으면 빈 자리로 적는다', () {
      // 0'00"으로 적으면 "0분 페이스"라는 없는 값이 화면에 뜬다.
      expect(PaceCalculator.format(null), "--'--\"");
    });
  });

  group('최근 페이스', () {
    test('좌표가 하나면 내지 않는다', () {
      expect(PaceCalculator.recent([at(37.5, 127)]), isNull);
    });

    test('창 밖의 오래된 좌표는 보지 않는다', () {
      // 앞 구간은 느리게(120초에 111m), 뒤 구간은 빠르게(30초에 111m) 뛰었다.
      final points = [
        at(37.5, 127),
        at(37.501, 127, seconds: 120),
        at(37.502, 127, seconds: 150),
      ];

      final recent = PaceCalculator.recent(
        points,
        window: const Duration(seconds: 60),
      );
      final overall = PaceCalculator.perKilometer(
        meters: PaceCalculator.totalMeters(points),
        elapsed: const Duration(seconds: 150),
      );

      // 최근만 보면 전체 평균보다 빠르게 나와야 한다.
      expect(recent!, lessThan(overall!));
    });
  });
}
