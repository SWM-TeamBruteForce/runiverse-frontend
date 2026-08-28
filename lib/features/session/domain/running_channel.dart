import 'package:runiverse/core/network/ws_client.dart';
import 'package:runiverse/core/network/ws_message.dart';
import 'package:runiverse/features/session/domain/track_point.dart';

/// 러닝 중 서버와 주고받는 것.
///
/// 화면은 이 타입에만 기대고 WebSocket을 모른다.
///
/// ## ⚠️ 일시정지·종료는 아직 계약뿐이다
///
/// `RUNNING_PAUSE` · `RUNNING_RESUME` · `RUNNING_FINISH`는 명세상 `개발전`이라
/// 받는 쪽이 없다. 지금 만들어도 검증할 수 없어 미뤄 둔다(설계 문서 3절).
abstract interface class RunningChannel {
  /// 지금 연결 상태.
  Stream<WsConnectionState> get states;

  WsConnectionState get state;

  /// 서버가 거절했을 때. **연결은 유지된다.**
  Stream<WsErrorCode> get errors;

  /// 붙고 `RUNNING_START`를 보낸다.
  ///
  /// **최초 진입과 재연결을 구분하지 않는다** — 서버가 같은 메시지로 둘 다
  /// 받고 멱등하게 처리한다. 그래서 재연결 후에도 이걸 다시 보내면 된다.
  ///
  /// 솔로 방은 이 첫 요청이 방을 `MATCHED → STARTED`로 바꾼다.
  Future<void> start(int runningRoomId);

  /// 좌표 묶음을 보낸다. **소켓에 넘겼으면 `true`.**
  ///
  /// ## ⚠️ ack가 없다
  ///
  /// `true`는 "서버가 받았다"가 아니라 **"소켓에 넘겼다"**는 뜻이다. 명세가
  /// 이 메시지에 ack를 두지 않았다. 그래서 재연결하면 겹쳐서 다시 보낸다.
  ///
  /// `false`를 무시하고 커서를 앞으로 옮기면 그 구간이 영영 안 간다.
  bool sendLocations(List<TrackPoint> points);

  /// 스스로 끊는다. 재연결하지 않는다.
  Future<void> close();
}
