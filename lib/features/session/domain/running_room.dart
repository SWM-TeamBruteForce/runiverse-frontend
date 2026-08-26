/// 서버가 만들어 준 러닝 방. `POST /api/v1/running-rooms/solo` (명세 16번).
///
/// ## 혼자 달려도 방이 있다
///
/// 서버 모델에서 `running_records.running_room_id`는 `NOT NULL`이고
/// "솔로도 방을 가지므로 항상 값 존재"라고 못박혀 있다. 매칭과 솔로가 **같은
/// WebSocket과 같은 기록 구조**를 쓰기 때문이다.
///
/// 그래서 이 값은 러닝을 시작하기 전에 반드시 있어야 한다 — WS의 모든 메시지가
/// `runningRoomId`를 payload에 싣는다.
class RunningRoom {
  const RunningRoom(this.id);

  /// 서버가 발급한 Long.
  final int id;

  @override
  String toString() => 'RunningRoom($id)';
}

/// 방을 만들지 못한 이유.
enum RunningRoomFailure {
  /// 이미 진행 중인 매칭·러닝이 있다. 서버 409 `RUNNING_ALREADY_IN_PROGRESS`.
  ///
  /// **새 러닝을 시작할 수 없다.** 앱은 진행 중인 것으로 안내해야 한다 —
  /// 여기서 "다시 시도"를 권하면 몇 번을 눌러도 같은 답이 온다.
  alreadyRunning,

  sessionExpired,

  network,

  server,

  unknown,
}

class RunningRoomException implements Exception {
  const RunningRoomException(this.failure);

  final RunningRoomFailure failure;

  @override
  String toString() => 'RunningRoomException($failure)';
}
