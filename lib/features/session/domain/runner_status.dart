/// 참가자가 지금 어떤 상태인가. **서버가 정한다.**
///
/// ## ⚠️ 예전에는 `paused` 하나였다
///
/// `bool` 로는 **멈춘 것·끊긴 것·끝난 것**을 가릴 수 없었다. 셋 다 "통지가
/// 멈춘 사람"으로 보여서, 화면은 마지막 통지가 오래됐는지(`stale`)로 **추측**
/// 하는 수밖에 없었다. 1.1.0 서버가 네 상태를 직접 알려준다.
///
/// (`RUNNING_PROGRESS_UPDATED` · `RUNNING_STARTED.players[]` 명세)
enum RunnerStatus {
  /// 뛰는 중. `RUNNING_START` · `RUNNING_RESUME` · 처음 보는 좌표.
  running,

  /// 버튼으로 일시정지. `RUNNING_PAUSE`.
  paused,

  /// 연결이 끊겼거나 **아직 시작을 보내지 않았다.**
  ///
  /// 앱 종료는 즉시, 응답 없이 끊긴 연결은 유휴 타임아웃 뒤에 온다. 스냅샷에서
  /// 상태가 없는 참가자(아직 `RUNNING_START` 전)도 여기로 실린다.
  disconnected,

  /// 종료 확정. **이후 바뀌지 않는다** — 연결을 닫아도 끊김이 되지 않는다.
  finished;

  /// 전선에서 읽는다.
  ///
  /// ⚠️ **모르는 값은 [running] 이다.** 명세상 필수지만 서버가 못 보낼 수도
  /// 있는데, 그때 [disconnected] 로 떨어뜨리면 **멀쩡히 뛰는 사람이 끊긴
  /// 것처럼** 보인다. 반대 방향의 틀림이 덜 나쁘고, 화면은 통지가 끊긴 것을
  /// `stale` 로 따로 보조한다.
  static RunnerStatus of(Object? wire) => switch (wire) {
    'PAUSED' => paused,
    'DISCONNECTED' => disconnected,
    'FINISHED' => finished,
    _ => running,
  };

  /// 뛰고 있지 않은가. 화면이 이 줄을 달리 그릴지 정할 때 쓴다.
  bool get isHalted => this != running;
}
