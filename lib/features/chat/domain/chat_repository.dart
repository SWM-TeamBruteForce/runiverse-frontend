import 'package:runiverse/features/chat/domain/chat.dart';

/// 한 페이지. **최신순으로 온 것을 그대로 담는다.**
///
/// 화면이 뒤집어 그린다 — 오래된 것이 위, 최신이 아래다.
class ChatHistory {
  const ChatHistory({required this.items, this.nextCursor});

  /// 서버가 준 순서 그대로(최신순, `chatId` 내림차순).
  final List<Chat> items;

  /// 다음(더 **이전**) 페이지 커서.
  ///
  /// `null`이면 방의 첫 메시지까지 다 받았다 — 위로 더 긁어도 나올 것이 없다.
  final String? nextCursor;
}

/// 대기방 채팅의 경계. **화면은 이것만 안다.**
///
/// ## ⚠️ 실시간 수신이 여기 없다
///
/// 채팅 이벤트(`ROOM_CHAT_SENT`·`EDITED`·`DELETED`)는 **대기방 SSE가 나른다**
/// (`GET /api/v1/match-rooms/stream`). 그 연결은 매칭 방 화면이 이미 열어 두고
/// 있고, **사용자당 하나만** 유지되므로 채팅이 따로 열 수 없다 — 열면 서버가
/// 기존 연결을 닫는다.
///
/// 그래서 저장소는 **부르는 것만** 맡는다. 받는 것은
/// `ChatEventBus`(`chat_event_bus.dart`)가 매칭 방에서 흘려 준다.
///
/// ## ⚠️ 매칭 방과 초대 방이 같은 경로를 쓴다
///
/// 주소가 `/match-rooms/...`지만 초대 방도 이것을 부른다. 방 종류로 갈리지
/// 않는다.
abstract interface class ChatRepository {
  /// 메시지 한 페이지. 첫 페이지는 [cursor] 없이 부른다.
  ///
  /// [limit]은 서버 기본값이 20이고 최대 50이다. **첫 페이지는 50으로 부른다** —
  /// 대기방 대화는 길지 않아 한 번에 거의 다 받는다.
  ///
  /// ⚠️ **스트림이 연결된 뒤에 부른다.** 먼저 부르면 응답과 연결 사이에 생긴
  /// 메시지를 잃는다.
  Future<ChatHistory> history(int runningRoomId, {String? cursor, int limit});

  /// 한 건 보낸다. **돌아온 [Chat]으로 내 화면을 그린다.**
  ///
  /// 내가 보낸 것의 `ROOM_CHAT_SENT`는 나에게 오지 않는다.
  ///
  /// ⚠️ **실패해도 저장됐을 수 있다.** 자동으로 다시 보내지 않는다.
  Future<Chat> send(int runningRoomId, String content);

  /// 내 메시지를 고친다. **돌아온 [Chat]에 `editedAt`이 채워져 있다.**
  ///
  /// 보낸 본인만, 횟수 제한 없이 고칠 수 있다. 이미 지운 메시지는 404다.
  ///
  /// ⚠️ **같은 내용이면 부르지 않는다.** 서버는 그래도 수정으로 쳐서
  /// "수정됨"이 붙는다.
  Future<Chat> edit(
    int runningRoomId, {
    required int chatId,
    required String content,
  });

  /// 내 메시지를 지운다. **되돌릴 수 없다.**
  ///
  /// 응답은 `204`로 본문이 없다 — 부른 쪽이 그 메시지를 `content: null`,
  /// `isDeleted: true`로 바꾼다.
  Future<void> delete(int runningRoomId, int chatId);
}
