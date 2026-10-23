/// 서버가 준 구간 하나. **본인 몫만 추린 것**이다.
///
/// `GET /running-rooms/{id}/split-results`(18번)의 `splits[]`에서 `isMe`인
/// 참가자의 수치만 뽑아 담는다. 파티원 비교가 붙으면 그때 사람별로 나눈다.
class RawSplit {
  const RawSplit({
    required this.startDistanceMeters,
    required this.endDistanceMeters,
    required this.duration,
    this.cadenceSpm,
    this.caloriesKcal = 0,
  });

  /// 구간 시작·종료 누적 거리(m). 서버가 **0부터 10m씩 고정 경계**로 자른다.
  final int startDistanceMeters;
  final int endDistanceMeters;

  final Duration duration;

  /// 표본이 부족하면 `null`이다. 10m 구간에서는 흔하다.
  final int? cadenceSpm;

  final int caloriesKcal;

  int get distanceMeters => endDistanceMeters - startDistanceMeters;
}

/// 집계된 구간 하나. 1km 테이블과 50m 차트가 같은 타입을 쓴다.
class SplitBucket {
  const SplitBucket({
    required this.index,
    required this.startDistanceMeters,
    required this.endDistanceMeters,
    required this.duration,
    required this.caloriesKcal,
    this.cadenceSpm,
  });

  /// 1부터 세는 번호.
  final int index;

  final int startDistanceMeters;
  final int endDistanceMeters;
  final Duration duration;
  final int caloriesKcal;

  /// 가중평균 케이던스. 아는 구간이 하나도 없으면 `null`이다.
  final int? cadenceSpm;

  int get distanceMeters => endDistanceMeters - startDistanceMeters;

  /// 1km 환산 페이스. 거리가 0이면 `null`이다.
  Duration? get pace {
    if (distanceMeters <= 0) return null;
    return Duration(
      microseconds: (duration.inMicroseconds * 1000 / distanceMeters).round(),
    );
  }

  /// 이 구간이 온전한 [bucketMeters]를 채웠는가.
  ///
  /// 마지막 구간만 짧을 수 있다. 화면이 `5km`가 아니라 `5.4km`로 적어야 해서
  /// 들고 있는다.
  bool isPartialOf(int bucketMeters) => distanceMeters < bucketMeters;
}

/// 서버의 10m 구간을 화면이 쓰는 단위로 묶는다.
///
/// ## 왜 다시 묶나
///
/// 서버는 **0m부터 10m씩 고정 경계**로 자른다 — `splitNumber` N이 모든
/// 참가자에게 같은 거리 구간이어야 파티원 비교가 되기 때문이다(18번 명세).
/// 화면이 쓰는 단위는 다르다. 구간 테이블은 **1km**, 페이스·케이던스 그래프는
/// **50m**다. 그래서 여기서 다시 묶는다.
///
/// ## ⚠️ 앱이 좌표에서 다시 계산하지 않는다
///
/// 종료 후 기록은 서버가 확정한 값을 쓴다. 앱이 좌표로 구간을 다시 나누면
/// 같은 러닝의 숫자가 화면마다 달라진다.
abstract final class SplitAggregator {
  const SplitAggregator._();

  /// 구간 테이블이 쓰는 단위.
  static const tableMeters = 1000;

  /// 페이스·케이던스 그래프가 쓰는 단위.
  ///
  /// 10m 그대로 그리면 점이 너무 많고(5km면 500개) 잡음이 심하다. 50m면
  /// 5km에 100점이라 화면 폭에 맞고 흔들림도 눈에 읽힌다.
  static const chartMeters = 50;

  /// [raw]를 [bucketMeters]씩 묶는다.
  ///
  /// 마지막 묶음은 짧을 수 있다 — 1.23km를 뛰면 1km 하나와 230m 하나다.
  ///
  /// 케이던스는 **거리로 가중평균**한다. 그냥 평균하면 짧은 구간이 긴 구간과
  /// 같은 무게를 갖는다. 아는 구간이 하나도 없으면 `null`이다.
  static List<SplitBucket> bucket(List<RawSplit> raw, int bucketMeters) {
    if (raw.isEmpty || bucketMeters <= 0) return const [];

    final sorted = [...raw]
      ..sort((a, b) => a.startDistanceMeters.compareTo(b.startDistanceMeters));

    final buckets = <SplitBucket>[];

    var start = sorted.first.startDistanceMeters;
    var end = start;
    var duration = Duration.zero;
    var calories = 0;
    // 케이던스 가중평균의 분자·분모. 아는 구간만 센다.
    var cadenceWeighted = 0;
    var cadenceMeters = 0;

    void close() {
      if (end <= start) return;
      buckets.add(
        SplitBucket(
          index: buckets.length + 1,
          startDistanceMeters: start,
          endDistanceMeters: end,
          duration: duration,
          caloriesKcal: calories,
          cadenceSpm: cadenceMeters == 0
              ? null
              : (cadenceWeighted / cadenceMeters).round(),
        ),
      );
    }

    for (final split in sorted) {
      // 경계를 넘었으면 지금까지를 접는다. 서버 경계(10m)가 묶음 단위의
      // 약수라 구간이 묶음 사이에 걸치지 않는다.
      if (split.endDistanceMeters - start > bucketMeters) {
        close();
        start = split.startDistanceMeters;
        end = start;
        duration = Duration.zero;
        calories = 0;
        cadenceWeighted = 0;
        cadenceMeters = 0;
      }

      end = split.endDistanceMeters;
      duration += split.duration;
      calories += split.caloriesKcal;

      final cadence = split.cadenceSpm;
      if (cadence != null) {
        cadenceWeighted += cadence * split.distanceMeters;
        cadenceMeters += split.distanceMeters;
      }
    }
    close();

    return buckets;
  }
}
