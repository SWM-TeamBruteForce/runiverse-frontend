import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/split_calculator.dart';

/// 좌표를 1km 구간으로 끊는 순수 계산. 화면 없이 여기서 다 확인한다.
///
/// ## 좌표를 왜 이렇게 만드나
///
/// 위도 0.001°는 약 111m다. 정확히 100m가 되지는 않지만 **모든 다리가 똑같이**
/// 어긋나므로, 거리와 시간을 같은 간격으로 두면 페이스는 정확히 떨어진다.
/// 그래서 "1km가 몇 도인가"를 몰라도 페이스를 단언할 수 있다.
void main() {
  final start = DateTime(2026, 9, 1, 7);

  /// 북쪽으로 일정하게 달리는 좌표 [count]개. 한 다리에 [step]씩 걸린다.
  List<GeoPoint> line({
    required int count,
    Duration step = const Duration(seconds: 30),
    DateTime? from,
  }) {
    final begin = from ?? start;
    // 111.32m/0.001° · 다리 하나가 대략 100m가 되도록.
    const delta = 0.0008983;
    return [
      for (var i = 0; i < count; i++)
        GeoPoint(
          latitude: 37.5 + delta * i,
          longitude: 127,
          recordedAt: begin.add(step * i),
        ),
    ];
  }

  group('구간 나누기', () {
    test('좌표가 모자라면 구간이 없다', () {
      expect(SplitCalculator.from([]), isEmpty);
      expect(SplitCalculator.from([line(count: 1)]), isEmpty);
    });

    test('1km를 못 채우면 부분 구간 하나만 나온다', () {
      // 다리 4개 ≈ 400m.
      final splits = SplitCalculator.from([line(count: 5)]);

      expect(splits, hasLength(1));
      expect(splits.single.isPartial, isTrue);
      expect(splits.single.distanceMeters, lessThan(1000));
    });

    test('완전한 구간은 정확히 1km로 끊긴다', () {
      // 다리 24개 ≈ 2400m → 1km 둘 + 자투리.
      final splits = SplitCalculator.from([line(count: 25)]);

      expect(splits, hasLength(3));
      expect(splits[0].distanceMeters, 1000);
      expect(splits[1].distanceMeters, 1000);
      expect(splits[2].isPartial, isTrue);
      expect(splits[2].distanceMeters, lessThan(1000));

      // 번호는 1부터 이어진다.
      expect(splits.map((s) => s.index), [1, 2, 3]);
    });

    test('구간 합계는 전체 거리와 같다', () {
      final points = line(count: 25);
      final splits = SplitCalculator.from([points]);

      var total = 0.0;
      for (var i = 1; i < points.length; i++) {
        total += points[i - 1].distanceTo(points[i]);
      }

      expect(
        splits.fold<double>(0, (sum, s) => sum + s.distanceMeters),
        closeTo(total, 0.001),
      );
    });
  });

  group('페이스', () {
    test('100m마다 30초면 5분/km가 된다', () {
      final splits = SplitCalculator.from([line(count: 25)]);

      // 여기서 보는 것은 "300초인가"가 아니라 **경계를 비율로 잘랐는가**다.
      // 넘어간 좌표에서 끊었다면 구간이 1km보다 길어져 310초대로 밀린다.
      // 위도→미터 환산이 딱 떨어지지 않아 소수점 아래는 남는다.
      expect(splits[0].pace.inMilliseconds / 1000, closeTo(300, 1));
      expect(splits[1].pace.inMilliseconds / 1000, closeTo(300, 1));
    });

    test('부분 구간도 1km로 환산한다', () {
      // 400m를 120초에 달렸으면 환산 페이스는 여전히 5분/km다.
      final splits = SplitCalculator.from([line(count: 5)]);

      expect(splits.single.pace.inMilliseconds / 1000, closeTo(300, 1));
    });

    test('평균과의 격차는 빠르면 음수다', () {
      final splits = SplitCalculator.from([line(count: 25)]);

      // 평균이 5분 10초라면 5분에 달린 구간은 10초 빠른 것이다.
      expect(
        splits[0].gapTo(const Duration(seconds: 310)).inMilliseconds / 1000,
        closeTo(-10, 1),
      );
    });
  });

  test('⚠️ 일시정지한 시간은 구간에 들어가지 않는다', () {
    // 세그먼트 둘. 두 번째는 10분 뒤에 다시 시작한다.
    final first = line(count: 11);
    final second = line(
      count: 11,
      from: first.last.recordedAt.add(const Duration(minutes: 10)),
    );

    final splits = SplitCalculator.from([first, second]);

    // 멈춘 10분이 섞였다면 두 번째 구간 페이스가 300초 근처일 수 없다.
    expect(splits[0].pace.inMilliseconds / 1000, closeTo(300, 1));
    expect(splits[1].pace.inMilliseconds / 1000, closeTo(300, 1));
  });
}
