import 'package:runiverse/features/session/domain/running_room.dart';

/// 러닝 방을 연다.
///
/// 지금은 솔로 하나뿐이다. 매칭 방은 SSE·매칭 흐름이 붙을 때 여기 더한다 —
/// 그때도 **받는 것은 `runningRoomId` 하나**라 이 인터페이스가 그대로 늘어난다.
abstract interface class RunningRoomRepository {
  /// 1인 방을 만들고 `runningRoomId`를 받는다.
  ///
  /// **요청 본문이 없다.** 목표 거리도 보내지 않는다 — 서버가 받지 않는다.
  ///
  /// ⚠️ 이 호출이 성공해야 WS에 연결할 수 있다. 방 ID 없이 연결하면
  /// 첫 메시지(`RUNNING_START`)를 만들지 못한다.
  ///
  /// 실패: `alreadyRunning`(409) · `sessionExpired` · `network` · `server`
  Future<RunningRoom> openSolo();
}
