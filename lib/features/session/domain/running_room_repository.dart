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

  /// 아직 시작하지 않은 방을 **서버에서 없앤다**(`DELETE /running-matches`).
  ///
  /// ## 왜 준비 화면이 이것을 부르는가
  ///
  /// 솔로 방은 `POST /running-rooms/solo` 순간에 `READY`로 태어난다. 그 뒤
  /// 앱을 껐다 켜면 서버는 여전히 `READY`라고 답하고, 앱은 준비 화면을
  /// 복구한다. **거기서 그냥 나가면 방이 서버에 남아** 이후 매칭 신청이 전부
  /// 409(`MATCH_ALREADY_IN_PROGRESS`)로 막힌다.
  ///
  /// ## ⚠️ 매칭 저장소에도 같은 호출이 있다
  ///
  /// 엔드포인트가 하나이고 매칭 취소와 솔로 준비 취소가 같은 것을 지운다.
  /// 여기에 사본을 두는 이유는 **의존 방향** 때문이다 — `matching → session`
  /// 한 방향만 허용이라 session이 matching의 저장소를 부를 수 없다.
  /// 서버 계약이 바뀌면 `HttpMatchRepository.cancel`과 **함께** 고쳐야 한다.
  ///
  /// 이미 없으면(404) 성공으로 본다 — 원하던 상태다.
  ///
  /// 실패: `alreadyRunning`(409, 이미 시작됨) · `sessionExpired` ·
  /// `network` · `server`
  Future<void> cancelPending();
}
