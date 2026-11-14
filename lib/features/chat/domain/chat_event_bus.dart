import 'dart:async';

import 'package:runiverse/features/chat/domain/chat.dart';

/// 채팅에 생긴 변화 한 건.
enum ChatChangeKind {
  /// 새 메시지가 왔다. **이것만 안 읽음으로 쌓는다.**
  sent,

  /// 누가 자기 메시지를 고쳤다.
  edited,

  /// 누가 자기 메시지를 지웠다.
  deleted,
}

/// ## ⚠️ 종류를 들고 다니는 이유는 배지 하나다
///
/// 합치는 규칙은 셋이 같다([mergeChat]). 다른 것은 **안 읽음으로 셀지**뿐이다.
///
/// 아직 위로 긁어 오지 않은 과거 메시지의 수정·삭제가 올 수 있는데, 그것을
/// 새 메시지와 같게 다루면 **본 적 없는 "삭제된 메시지"가 배지에 세어진다.**
class ChatChange {
  const ChatChange(this.kind, this.chat);

  final ChatChangeKind kind;
  final Chat chat;

  /// 안 읽음으로 쌓을 것인가.
  bool get countsAsUnread => kind == ChatChangeKind.sent;
}

/// 대기방 스트림이 받은 채팅 변화를 채팅 화면으로 흘리는 자리.
///
/// ## ⚠️ 왜 사이에 이것을 두는가
///
/// 채팅 이벤트는 **대기방 SSE가 나른다.** 그 연결은 매칭 방 provider가 이미
/// 열어 두고 있고, 사용자당 하나만 유지되므로 채팅이 따로 열 수 없다 — 열면
/// 서버가 기존 연결을 닫는다.
///
/// 그렇다고 두 provider가 서로를 들을 수는 없다. Riverpod이
/// `CircularDependencyError`로 막는다. 한쪽이 다른 쪽의 notifier를 `read`하는
/// 방법도 있지만, 그러면 **채팅 provider가 매칭 방에 매달려 영영 살아 있게
/// 된다** — 방을 떠난 뒤에도 지난 방의 메시지를 들고 있다.
///
/// 그래서 **값만 지나가는 자리**를 하나 둔다. 매칭 방이 밀어 넣고 채팅이 듣는다.
/// 듣는 쪽이 없으면 그냥 버려진다 — 홈에 있는 동안 오는 채팅이 그렇다.
class ChatEventBus {
  final _controller = StreamController<ChatChange>.broadcast();

  Stream<ChatChange> get stream => _controller.stream;

  void emit(ChatChange change) {
    // ⚠️ 닫힌 뒤에 들어올 수 있다. 앱이 내려가는 중의 마지막 이벤트가 그렇다.
    if (_controller.isClosed) return;
    _controller.add(change);
  }

  Future<void> close() => _controller.close();
}
