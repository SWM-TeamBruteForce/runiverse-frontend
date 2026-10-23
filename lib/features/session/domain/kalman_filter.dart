/// 1차원 칼만 필터 하나.
///
/// 값 **한 줄기**를 매끄럽게 만든다. 위도와 경도는 서로 독립이라 각각 하나씩 둔다
/// — 둘을 한 필터에 묶으면 남북으로 흔들린 것이 동서 추정까지 흐린다.
///
/// ```
/// 예측   p = p + Q
/// 이득   K = p / (p + R)
/// 갱신   x = x + K·(z − x)
///        p = (1 − K)·p
/// ```
///
/// [Q]와 [R]을 밖에서 매번 받는 이유는 **좌표마다 달라지기 때문**이다.
/// 정확도가 나쁜 좌표는 `R`이 크고, 빠르게 달릴 때는 `Q`가 크다
/// (`docs/specs/2026-08-05-solo-run-design.md` 3-1).
///
/// 순수 Dart다. import가 하나도 없어 실기기 없이 테스트한다.
class KalmanFilter1D {
  /// 지금까지의 추정값. 첫 측정이 오기 전에는 `null`이다.
  double? _estimate;

  /// 그 추정을 얼마나 못 믿는가. 작을수록 믿는다.
  double _variance = 1;

  /// 아직 아무 값도 받지 않았는가.
  bool get isEmpty => _estimate == null;

  /// [measurement]를 받아 보정한 값을 돌려준다.
  ///
  /// **첫 값은 그대로 통과시킨다.** 비교할 추정이 없어 보정할 것이 없고,
  /// 임의의 초기값에서 출발하면 처음 몇 초 동안 좌표가 그 값에서 끌려온다.
  double filter(double measurement, {required double q, required double r}) {
    final previous = _estimate;
    if (previous == null) {
      _estimate = measurement;
      _variance = r;
      return measurement;
    }

    // 예측 — 시간이 흐른 만큼 추정이 낡았다.
    final predicted = _variance + q;

    // 이득 — 측정을 얼마나 반영할지. `r`이 크면 작아진다(측정을 덜 믿는다).
    final gain = predicted / (predicted + r);

    _estimate = previous + gain * (measurement - previous);
    _variance = (1 - gain) * predicted;
    return _estimate!;
  }

  /// 러닝을 새로 시작할 때 부른다. **안 부르면 지난 러닝의 마지막 위치에서
  /// 끌려온다** — 어제 뛴 곳과 오늘 뛰는 곳이 멀수록 초반이 크게 어긋난다.
  void reset() {
    _estimate = null;
    _variance = 1;
  }
}
