import 'package:runiverse/core/network/ws_client.dart';
import 'package:runiverse/core/network/ws_message.dart';

/// 러닝 중 서버와 주고받는 것.
///
/// 화면은 이 타입에만 기대고 WebSocket을 모른다.
///
/// ## ⚠️ 지금은 앞의 둘만 서버가 받는다
///
/// 좌표 전송·일시정지·종료는 명세상 `개발전`이라 **계약만 정의하고 구현은
/// 나중에 붙인다**(설계 문서 3절). 지금 만들어도 받는 쪽이 없어 검증할 수 없다.
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

  /// 스스로 끊는다. 재연결하지 않는다.
  Future<void> close();
}
