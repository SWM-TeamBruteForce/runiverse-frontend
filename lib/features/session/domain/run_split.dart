/// 러닝을 1km씩 끊은 구간 하나.
///
/// S16 아래쪽의 구간 차트와 구간 리스트가 이것을 그린다. 순수 Dart다 —
/// 좌표에서 뽑아내는 일은 `SplitCalculator`가 한다.
class RunSplit {
  const RunSplit({
    required this.index,
    required this.distanceMeters,
    required this.duration,
    required this.isPartial,
  });

  /// 1부터 세는 구간 번호. `3`이면 2km 지점부터 3km 지점까지다.
  final int index;

  /// 이 구간에서 실제로 달린 거리(미터).
  ///
  /// 마지막 구간만 1km보다 짧을 수 있다 — 5.4km를 달리면 6번째가 400m다.
  final double distanceMeters;

  /// 이 구간에 걸린 시간.
  ///
  /// **일시정지는 빠져 있다.** 좌표를 세그먼트 안에서만 이어 재기 때문에,
  /// 멈춰 있던 사이의 시간은 애초에 세지 않는다.
  final Duration duration;

  /// 1km를 채우지 못한 마지막 구간인가.
  ///
  /// 화면이 `5km`가 아니라 `5.4km`처럼 따로 적어야 해서 들고 있다. 400m를
  /// 뛰고 만 구간의 페이스를 온전한 1km와 나란히 놓으면 오해를 부른다.
  final bool isPartial;

  /// 1km 환산 페이스.
  ///
  /// 부분 구간도 같은 기준으로 환산한다. 그래야 차트의 마지막 점이 짧은
  /// 거리 때문에 아래로 꺼지지 않는다.
  Duration get pace => Duration(
    microseconds: (duration.inMicroseconds * 1000 / distanceMeters).round(),
  );

  /// [average] 대비 이 구간이 얼마나 빠르거나 느렸나.
  ///
  /// 음수면 평균보다 빨랐다는 뜻이다 — 페이스는 작을수록 빠르다.
  Duration gapTo(Duration average) => pace - average;

  @override
  String toString() =>
      'RunSplit($index, ${distanceMeters.toStringAsFixed(0)}m, $duration'
      '${isPartial ? ', partial' : ''})';
}
