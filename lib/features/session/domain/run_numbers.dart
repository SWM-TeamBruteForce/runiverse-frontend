/// 그 러닝이 **다음에 쓸 번호 두 개.**
///
/// ## 왜 둘을 묶는가
///
/// 둘 다 "앱이 들고 있다가 재시작하면 되살려야 하는 값"이고, 같은 순간에
/// 저장된다. 따로 두면 **한쪽만 저장된 상태**가 생기는데, 그때 좌표는 이미
/// 두 번호를 함께 달고 나간다.
///
/// ## ⚠️ [pauseSegment]는 "몇 번째 멈춤 이후인가"다
///
/// 경로 조각 번호가 아니다. 서버는 **번호가 다른 연속 좌표 사이**를 멈춘
/// 구간으로 보고 거리·시간·고도에서 뺀다. 경로 조각은 그 결과로 나뉘는
/// 그림의 단위이고, GPS 튐이나 관측 공백에서도 나뉜다 — 두 값을 같은 번호
/// 체계로 취급하면 안 된다(1.1.1 4절).
class RunNumbers {
  const RunNumbers({required this.nextSequence, required this.pauseSegment});

  /// 새 러닝. **순번은 1부터, 구간 번호는 0부터다.**
  ///
  /// 서버는 받은 좌표가 없을 때 `nextSequence`를 0으로 주지만, 앱은 첫 좌표에
  /// 1을 매긴다([TrackPoint.sequence]). 둘 중 큰 값을 쓰므로 어긋나지 않는다.
  static const start = RunNumbers(nextSequence: 1, pauseSegment: 0);

  /// 서버가 받아 주는 구간 번호의 상한. 넘으면 `INVALID_REQUEST`다(1.1.1 2절).
  static const maxPauseSegment = 100000;

  /// **서버가 이 러닝의 좌표를 하나도 못 받았다.**
  ///
  /// [start]와 다르다 — 서버의 `nextSequence`는 받은 좌표가 없으면 0이고, 앱은
  /// 첫 좌표에 1을 매긴다. [mergedWith]에서 어느 값과 합쳐도 상대가 그대로
  /// 남으므로, **못 읽은 몸통의 자리를 메우는 데도 쓴다.**
  static const serverZero = RunNumbers(nextSequence: 0, pauseSegment: 0);

  /// `RUNNING_STARTED`가 싣고 온 **본인 기준** 번호를 읽는다 — 1.1.1 2절.
  ///
  /// `nextSequence`는 서버가 받은 마지막 좌표의 순번 + 1, `pauseSegment`는 그
  /// 좌표의 구간 번호다. 둘 다 받은 좌표가 없으면 0이다.
  ///
  /// ## ⚠️ 못 읽어도 던지지 않는다
  ///
  /// 이 값을 못 읽었다고 러닝을 끊을 수는 없다. [serverZero]를 주면
  /// [mergedWith]가 로컬 번호를 그대로 남긴다 — 재설치가 아니라면 원래 그래야
  /// 하는 결과다.
  ///
  /// ## ⚠️ 상한을 넘는 값은 깎는다
  ///
  /// 그대로 실어 보내면 서버가 **자기가 준 번호를 `INVALID_REQUEST`로
  /// 되받는다.** 음수도 0으로 본다 — 번호가 줄어드는 쪽으로는 한 칸도
  /// 움직이지 않는 편이 안전하다.
  static RunNumbers of(Map<String, dynamic> data) {
    final next = data['nextSequence'];
    final segment = data['pauseSegment'];

    return RunNumbers(
      nextSequence: next is int && next > 0 ? next : 0,
      pauseSegment: segment is! int || segment < 0
          ? 0
          : segment > maxPauseSegment
          ? maxPauseSegment
          : segment,
    );
  }

  /// 다음 **새** 좌표에 매길 순번.
  ///
  /// ⚠️ 이미 저장된 좌표의 순번은 이 값으로 바꾸지 않는다. 번호를 바꾸면
  /// 서버가 복원하는 일시정지 경계가 어긋난다.
  final int nextSequence;

  /// 지금 수집하는 좌표에 달 구간 번호.
  final int pauseSegment;

  /// 일시정지 버튼을 눌렀다. **구간 번호만 1 올린다.**
  ///
  /// ⚠️ **재개할 때는 올리지 않는다.** 가이드가 "일시정지할 때 한 번만"이라고
  /// 못 박았다. 양쪽에서 올리면 멈춤 한 번이 구간 두 개가 되고, 서버는 있지도
  /// 않은 멈춤 구간을 거리에서 뺀다.
  ///
  /// ⚠️ **순번은 그대로다.** `sequence`는 일시정지와 무관하게 이어 증가한다.
  ///
  /// [maxPauseSegment]에서 멈춘다. 사람이 10만 번 멈출 일은 없으니 여기 닿는
  /// 것은 버그인데, 그때 번호를 넘겨 보내면 **배치 전체가 거부되어 러닝이
  /// 통째로 안 남는다.** 멈춤 몇 번이 한 구간으로 뭉개지는 편이 낫다.
  RunNumbers afterPause() => RunNumbers(
    nextSequence: nextSequence,
    pauseSegment: pauseSegment >= maxPauseSegment
        ? maxPauseSegment
        : pauseSegment + 1,
  );

  /// 좌표 하나를 매겼다. **다음 순번으로 밀어 둔다.**
  RunNumbers afterPoint() =>
      RunNumbers(nextSequence: nextSequence + 1, pauseSegment: pauseSegment);

  /// 저장된 값과 들고 있던 값 중 **큰 쪽으로** 맞춘다.
  ///
  /// 작은 쪽을 쓰면 이미 쓴 순번을 다시 쓰거나(서버가 중복으로 버린다), 번호가
  /// 줄어들어 `PAUSE_SEGMENT_DECREASED`로 배치가 거부된다. 둘 다 그 구간이
  /// 기록에서 빠진다.
  RunNumbers mergedWith(RunNumbers other) => RunNumbers(
    nextSequence: nextSequence > other.nextSequence
        ? nextSequence
        : other.nextSequence,
    pauseSegment: pauseSegment > other.pauseSegment
        ? pauseSegment
        : other.pauseSegment,
  );

  @override
  bool operator ==(Object other) =>
      other is RunNumbers &&
      other.nextSequence == nextSequence &&
      other.pauseSegment == pauseSegment;

  @override
  int get hashCode => Object.hash(nextSequence, pauseSegment);

  @override
  String toString() => 'RunNumbers(next: $nextSequence, pause: $pauseSegment)';
}
