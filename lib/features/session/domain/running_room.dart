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
  const RunningRoom(this.id, {this.targetDistanceMeters});

  /// 서버가 발급한 Long.
  final int id;

  /// 목표 거리(m). **솔로는 `null`이다** — 목표가 없어 제한도 없다.
  ///
  /// 매칭 방은 신청할 때 정해져 `RoomInfo`가 실어 온다. 여기 실어 두면
  /// 첫 진행 통지(최대 10초)를 기다리지 않고 막대·눈금·80% 판정이 처음부터 선다.
  final int? targetDistanceMeters;

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

  /// 서버가 이 사용자를 **이 방의 참가자로 보지 않는다**(WS `NOT_ROOM_PLAYER`).
  ///
  /// 명시적으로 나간 사람이 받는 답이다 — 다른 기기에서 취소했거나 서버가
  /// 방에서 뺀 경우. 재시도해도 같으므로 **러닝을 접고 상태를 다시 읽는다.**
  notRoomPlayer,

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
