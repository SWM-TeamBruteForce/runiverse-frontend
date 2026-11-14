/// 채팅이 실패한 이유. **화면이 할 일이 갈래마다 다르다.**
///
/// 서버가 내리는 것은 400·404·409 셋이고(+공통 401·5xx), 그중 **셋을 반드시
/// 갈라야 한다.**
enum ChatFailure {
  /// 400 `INVALID_REQUEST` — 내용이 비었거나 공백뿐이거나 200자를 넘었다.
  /// 커서가 깨진 경우도 이것이다.
  ///
  /// 입력 단계에서 미리 막는다. 그래도 오면 입력 내용을 확인하도록 안내한다.
  invalidRequest,

  /// 400 `INVALID_REQUEST` 중 **커서가 깨진 경우.**
  ///
  /// ⚠️ [invalidRequest]와 나눠야 한다 — 할 일이 "입력을 확인하라"가 아니라
  /// **커서를 버리고 첫 페이지부터 다시 받는 것**이다.
  ///
  /// 서버 응답만으로는 둘을 가를 수 없어서, **커서를 실어 보낸 요청의 400**을
  /// 이것으로 읽는다.
  invalidCursor,

  /// 404 — 방이 없거나, 솔로 방이거나, 이 방 참가자가 아니다. 수정·삭제에서는
  /// 메시지가 없거나 이미 지웠거나 **남의 메시지**인 경우도 같은 404다.
  ///
  /// ⚠️ **서버가 이 경우들을 가르지 않는다.** 그래서 수정·삭제의 404만으로
  /// 방에서 나가지 않는다 — 먼저 목록을 다시 받아 맞춘다. 목록 조회가 404면
  /// `GET /users/me/status`로 참여 여부를 확인한다.
  notFound,

  /// 409 `ROOM_CHAT_CLOSED` — 러닝이 시작됐거나 방이 닫혔다.
  ///
  /// **목록 조회를 포함한 모든 채팅 API**에 적용된다. 받으면 재시도를 멈추고
  /// 입력·수정·삭제를 닫는다.
  closed,

  /// 401 — 다시 로그인해야 한다. 기다린다고 풀리지 않는다.
  sessionExpired,

  /// 못 닿았거나 5xx다. **전송은 저장됐을 수도 있다** — 자동 재전송하지 않는다.
  network,

  unknown,
}

/// 채팅이 실패했다.
class ChatException implements Exception {
  const ChatException(this.failure);

  final ChatFailure failure;

  @override
  String toString() => 'ChatException(${failure.name})';
}
