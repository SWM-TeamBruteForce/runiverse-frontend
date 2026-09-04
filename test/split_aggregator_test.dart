import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record/domain/split_aggregator.dart';

/// 서버의 10m 구간을 화면 단위(1km 테이블 · 50m 그래프)로 묶는다.
void main() {
  /// 10m 구간 [count]개. [start]m부터 시작한다.
  List<RawSplit> tenMeters({
    required int count,
    int start = 0,
    int seconds = 3,
    int? cadence = 170,
    int calories = 1,
  }) => [
    for (var i = 0; i < count; i++)
      RawSplit(
        startDistanceMeters: start + i * 10,
        endDistanceMeters: start + (i + 1) * 10,
        duration: Duration(seconds: seconds),
        cadenceSpm: cadence,
        caloriesKcal: calories,
      ),
  ];

  test('빈 입력은 빈 결과다', () {
    expect(SplitAggregator.bucket([], 1000), isEmpty);
  });

  test('100개를 묶어 1km 하나가 된다', () {
    final buckets = SplitAggregator.bucket(tenMeters(count: 100), 1000);

    expect(buckets, hasLength(1));
    expect(buckets.single.distanceMeters, 1000);
    expect(buckets.single.duration, const Duration(seconds: 300));
    expect(buckets.single.caloriesKcal, 100);
    expect(buckets.single.pace, const Duration(seconds: 300));
  });

  test('⚠️ 마지막 묶음은 짧을 수 있다', () {
    // 1.23km를 뛰면 1km 하나와 230m 하나다. 화면이 `1.23km`라고 적어야 한다.
    final buckets = SplitAggregator.bucket(tenMeters(count: 123), 1000);

    expect(buckets, hasLength(2));
    expect(buckets[0].distanceMeters, 1000);
    expect(buckets[1].distanceMeters, 230);
    expect(buckets[0].isPartialOf(1000), isFalse);
    expect(buckets[1].isPartialOf(1000), isTrue);
  });

  test('50m 단위로도 묶인다', () {
    // 그래프가 쓰는 단위다. 1.23km면 25개다(50m×24 + 30m).
    final buckets = SplitAggregator.bucket(tenMeters(count: 123), 50);

    expect(buckets, hasLength(25));
    expect(buckets.first.distanceMeters, 50);
    expect(buckets.last.distanceMeters, 30);
    expect(buckets.map((b) => b.index).take(3), [1, 2, 3]);
  });

  test('번호는 1부터 이어진다', () {
    final buckets = SplitAggregator.bucket(tenMeters(count: 250), 1000);

    expect(buckets.map((b) => b.index), [1, 2, 3]);
  });

  group('케이던스', () {
    test('⚠️ 거리로 가중평균한다', () {
      // 그냥 평균하면 짧은 구간이 긴 구간과 같은 무게를 갖는다.
      // 90구간(900m)이 160spm, 10구간(100m)이 200spm이면
      // 산술평균은 180이지만 가중평균은 164다.
      final raw = [
        ...tenMeters(count: 90, cadence: 160),
        ...tenMeters(count: 10, start: 900, cadence: 200),
      ];

      final bucket = SplitAggregator.bucket(raw, 1000).single;

      expect(bucket.cadenceSpm, 164);
    });

    test('모르는 구간은 평균에서 빠진다', () {
      final raw = [
        ...tenMeters(count: 50, cadence: 180),
        ...tenMeters(count: 50, start: 500, cadence: null),
      ];

      final bucket = SplitAggregator.bucket(raw, 1000).single;

      expect(bucket.cadenceSpm, 180, reason: '아는 것만으로 평균한다');
    });

    test('⚠️ 하나도 모르면 null이다', () {
      // 0으로 때우면 "0spm으로 뛰었다"가 된다. 10m 구간에서는 흔한 일이다.
      final raw = tenMeters(count: 100, cadence: null);

      expect(SplitAggregator.bucket(raw, 1000).single.cadenceSpm, isNull);
    });
  });

  test('순서가 뒤섞여 와도 거리 순으로 묶는다', () {
    final raw = tenMeters(count: 100).reversed.toList();

    final buckets = SplitAggregator.bucket(raw, 1000);

    expect(buckets, hasLength(1));
    expect(buckets.single.startDistanceMeters, 0);
    expect(buckets.single.endDistanceMeters, 1000);
  });
}
