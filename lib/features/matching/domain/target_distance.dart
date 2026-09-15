/// 매칭이 받는 목표 거리.
///
/// **셋 중 하나만 고를 수 있다.** 자유 입력이 아니다 — 서버가 같은 조건끼리
/// 묶어 방을 만들기 때문에, 값이 흩어지면 매칭될 상대가 없어진다.
enum TargetDistance {
  km3(3),
  km5(5),
  km10(10);

  const TargetDistance(this.km);

  /// 화면이 말하는 단위.
  final int km;

  /// 서버가 말하는 단위. **환산은 여기 한 곳뿐이다** — 화면은 `5km`를,
  /// 요청은 `5000`을 쓰는데 그 곱셈이 여러 곳에 흩어지면 한쪽만 고치는 날이 온다.
  int get meters => km * 1000;

  /// 서버가 준 미터 값을 되읽는다. 매칭 조건을 다시 그릴 때 쓴다.
  ///
  /// ⚠️ 셋 밖의 값이면 `null`이다. 가장 가까운 값으로 뭉개면 화면이 서버와
  /// 다른 거리를 말하게 된다 — 모르면 안 그리는 편이 낫다.
  static TargetDistance? fromMeters(int? meters) {
    for (final distance in TargetDistance.values) {
      if (distance.meters == meters) return distance;
    }
    return null;
  }
}
