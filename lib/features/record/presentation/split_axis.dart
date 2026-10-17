/// 구간 그래프의 **세로 자.**
///
/// ## ⚠️ 두 선을 합쳐 잡는다
///
/// 파티원과 비교할 때 내 값만으로 범위를 잡으면 **두 선이 다른 자로 그려진다.**
/// 상대가 나보다 느렸던 구간은 그림 밖으로 밀려나고, 같은 높이가 서로 다른
/// 페이스를 뜻하게 된다. 비교가 성립하려면 자가 하나여야 한다.
///
/// ## 눈금은 셋이다 — 가운데는 평균이 아니다
///
/// 최고 · 중간 · 최저. 가운데는 **축의 중간값**이지 평균이 아니다. 평균을
/// 그리면 그게 누구의 평균인지가 문제가 되고, 비교 중에는 둘 중 하나를 고를
/// 수 없다. 축은 사람의 값이 아니라 눈금이라 이름이 붙지 않는다.
///
/// ## 왜 위젯과 그림이 이걸 나눠 쓰나
///
/// 격자선은 캔버스가, 눈금 값은 위젯이 그린다. 두 곳이 각자 높이를 계산하면
/// **선과 숫자가 어긋나는 날이 온다.** 말풍선 좌표를 그림 쪽에 몰아둔 것과
/// 같은 판단이다(`SplitLineChart` 참조).
class SplitAxis {
  const SplitAxis._({
    required this.lo,
    required this.hi,
    required this.inverted,
  });

  /// 그릴 값들로 자를 잡는다. [secondary]가 있으면 **합쳐서** 잡는다.
  factory SplitAxis.of(
    List<double> values, {
    List<double>? secondary,
    bool inverted = false,
  }) {
    final all = [...values, ...?secondary];
    // 그릴 것이 없다. 부르는 쪽이 먼저 걸러내지만 여기서 죽지는 않는다.
    if (all.isEmpty) {
      return const SplitAxis._(lo: 0, hi: 0, inverted: false);
    }

    var lo = all.first;
    var hi = all.first;
    for (final value in all) {
      if (value < lo) lo = value;
      if (value > hi) hi = value;
    }
    return SplitAxis._(lo: lo, hi: hi, inverted: inverted);
  }

  /// 가장 작은 값. 페이스면 **가장 빨랐던 구간**이다.
  final double lo;

  /// 가장 큰 값. 페이스면 **가장 느렸던 구간**이다.
  final double hi;

  /// 작은 값을 위로 올리는가. **페이스만 `true`다** — 작을수록 빠른 값이라
  /// 그대로 올리면 솟은 봉우리가 "느렸던 구간"이 되어 거꾸로 읽힌다.
  final bool inverted;

  /// 위아래 여백 비율. 선이 천장과 바닥에 닿으면 값의 크기를 못 읽는다.
  static const padRatio = 0.15;

  /// 값이 전부 같은가. 나눌 폭이 없어 눈금도 하나뿐이다.
  bool get isFlat => hi - lo < 0.000001;

  /// 높이 [height]인 그림 영역 안의 세로 좌표.
  double dy(double value, double height) {
    if (isFlat) return height / 2;

    final pad = height * padRatio;
    final ratio = (value - lo) / (hi - lo);
    // 화면 좌표는 아래로 갈수록 크다. 보통은 큰 값이 위로 가야 하므로
    // 뒤집고, 페이스는 작을수록 빠르므로 그대로 쓴다.
    return pad + (inverted ? ratio : 1 - ratio) * (height - pad * 2);
  }

  /// 눈금 값 — **위에서 아래 순서다.**
  ///
  /// 순서를 정해 두는 것은 읽는 사람을 위해서다. 그리는 쪽은 [dy]로 자리를
  /// 잡으므로 순서가 필요 없지만, 목록을 눈으로 확인할 때 위아래가 뒤집혀
  /// 있으면 `inverted`를 잘못 넣은 것을 알아채기 어렵다.
  List<double> get ticks {
    if (isFlat) return [lo];
    final mid = (lo + hi) / 2;
    return inverted ? [lo, mid, hi] : [hi, mid, lo];
  }

  @override
  bool operator ==(Object other) =>
      other is SplitAxis &&
      other.lo == lo &&
      other.hi == hi &&
      other.inverted == inverted;

  @override
  int get hashCode => Object.hash(lo, hi, inverted);
}
