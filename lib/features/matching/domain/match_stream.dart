import 'package:runiverse/features/matching/domain/match_event.dart';

/// 매칭 스트림이 끊긴 이유.
enum MatchStreamFailure {
  /// ⚠️ **활성 신청이 없다.** 서버가 404로 거절한다.
  ///
  /// 붙을 방이 없는데 열어주면 아무 채널도 구독하지 못하고, 그 뒤에 신청해도
  /// 이벤트가 영영 오지 않는 연결이 된다. 그래서 서버가 연결 자체를 막는다.
  ///
  /// **이 응답에만 본문이 없다** — 요청 `Accept`가 `text/event-stream`이라
  /// 다른 에러처럼 JSON을 실을 수 없다. 상태 코드로 판단한다.
  noActiveMatch,

  sessionExpired,

  /// 닿지 못했거나 도중에 끊겼다.
  network,

  unknown,
}

class MatchStreamException implements Exception {
  const MatchStreamException(this.failure);

  final MatchStreamFailure failure;

  @override
  String toString() => 'MatchStreamException($failure)';
}

/// 매칭 이벤트를 받는 곳. **수신 전용이다.**
///
/// ## ⚠️ 신청 응답을 받기 전에 열지 않는다
///
/// 활성 신청이 없으면 서버가 404로 거절한다. 신청 → `runningRoomId` 저장 →
/// 연결 순서를 지킨다.
///
/// ## 화면 생명주기에 묶지 않는다
///
/// 홈을 벗어나도 스트림은 살아 있어야 한다. 대기방을 보다가 기록 탭에 다녀와도
/// 그사이의 확정 통지를 놓치면 안 된다.
///
/// ## 요청 실패라는 개념이 없다
///
/// 보내는 것이 없으므로, 신청·취소의 오류는 REST 응답이 나른다.
abstract interface class MatchStream {
  /// 붙어서 이벤트를 흘린다. **연결 직후 서버가 현재 상태를 한 번 보낸다.**
  ///
  /// 각 이벤트는 변경분이 아니라 전체 상태라 `Last-Event-ID` 재개를 쓰지 않는다.
  ///
  /// 끊기면 [MatchStreamException]으로 끝난다. **스스로 다시 붙지 않는다** —
  /// 다시 붙을지는 유저 상태를 다시 읽어 정할 일이다.
  Stream<MatchEvent> connect();

  /// 스스로 끊는다. `RUNNING_STARTED` ack를 받은 뒤에 부른다.
  Future<void> close();
}
