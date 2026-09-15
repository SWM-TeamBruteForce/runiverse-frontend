/// 언제 출발하고, 언제 3-2-1을 보여주는가.
///
/// ## ⚠️ 발사 시각은 당기지 않는다
///
/// 서버가 `startsInMs`를 짧게 주더라도 연출만 줄인다. `RUNNING_START`가
/// [at]보다 이르면 서버가 `INVALID_ROOM_STATE`로 거절한다.
///
/// 순수 계산이다. `DateTime.now()`를 안에서 부르지 않는다 — 경계를 시험할 수
/// 없고, 기기 시계를 믿어야 하는 자리가 늘어난다.
class RunLaunch {
  const RunLaunch(this.at);

  /// 출발 시각. 로컬 시계 기준이다.
  ///
  /// `RUNNING_READY`를 받았으면 **받은 순간 + `startsInMs`**로 잡는다.
  /// 그 편이 기기 시계가 어긋나 있어도 맞는다 — 서버가 시각이 아니라 간격을
  /// 주는 이유다.
  ///
  /// 통지를 못 받았으면 방의 `scheduledStartAt`을 쓴다. **SSE가 끊겼거나 앱이
  /// 백그라운드였으면 이벤트가 오지 않는데, 그렇다고 출발을 포기하지는 않는다.**
  final DateTime at;

  /// 3-2-1을 보여주기 시작하는 지점.
  static const countdownFrom = Duration(seconds: 3);

  /// 출발 대기실로 넘어가는 지점.
  ///
  /// 연결이 늦으면 정각에 보낼 수 없다. 카운트다운보다 넉넉히 앞서 들어가
  /// WebSocket을 미리 붙인다.
  static const enterFrom = Duration(seconds: 30);

  /// 남은 시간. **음수를 돌려주지 않는다** — 화면이 "-3초"를 그리게 두면 안 된다.
  Duration remaining(DateTime now) {
    final left = at.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  /// 출발 대기실로 넘어갈 때인가.
  bool shouldEnter(DateTime now) => remaining(now) <= enterFrom;

  /// 지금 쏠 때인가.
  bool shouldLaunch(DateTime now) => !now.isBefore(at);

  /// 크게 띄울 숫자. 3-2-1 구간이 아니면 `null`이다.
  ///
  /// 남은 시간이 2.4초면 `3`이 아니라 **`3`으로 올림**한다 — 0.4초 뒤에 2로
  /// 바뀌는 것이 자연스럽고, 내림하면 마지막 1초가 `0`으로 보인다.
  int? countdownNumber(DateTime now) {
    final left = remaining(now);
    if (left == Duration.zero || left > countdownFrom) return null;
    return (left.inMilliseconds / 1000).ceil();
  }
}
