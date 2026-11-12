import 'package:flutter/foundation.dart';
import 'package:runiverse/core/utils/kst_time.dart';
import 'package:runiverse/features/chat/domain/chat.dart';
import 'package:runiverse/features/chat/domain/chat_repository.dart';

/// 메시지 한 건을 읽는다. **읽을 수 없으면 `null`이다.**
///
/// ⚠️ 던지지 않는다. 한 줄이 깨져서 방 전체의 대화를 못 그리면 안 된다 — 방
/// 스냅샷의 참가자 목록과 같은 판단이다(`sse_match_stream._playerOf`).
Chat? chatFromJson(Object? wire) {
  if (wire is! Map) return null;

  final chatId = wire['chatId'];
  final roomId = wire['runningRoomId'];
  final sender = _senderOf(wire['sender']);
  final createdAt = KstTime.parse(wire['createdAt']);

  // 이 넷 중 하나라도 없으면 그릴 수 없다. 특히 `chatId`는 정렬과 병합의
  // 기준이라, 없는 메시지를 들이면 **자리도 정하지 못하고 중복도 못 거른다.**
  if (chatId is! int || roomId is! int || sender == null || createdAt == null) {
    debugPrint('[chat] 읽을 수 없는 메시지를 버렸다');
    return null;
  }

  final content = wire['content'];
  return Chat(
    chatId: chatId,
    runningRoomId: roomId,
    sender: sender,
    content: content is String ? content : null,
    isDeleted: wire['isDeleted'] == true,
    editedAt: KstTime.parse(wire['editedAt']),
    createdAt: createdAt,
  );
}

ChatSender? _senderOf(Object? wire) {
  if (wire is! Map) return null;
  final userId = wire['userId'];
  final nickname = wire['nickname'];
  // 이름이 없으면 누가 한 말인지 못 그린다. 탈퇴한 사용자도 서버가 이름을
  // 채워서 준다(`탈퇴한 사용자`).
  if (userId is! String || nickname is! String) return null;

  final imageUrl = wire['profileImageUrl'];
  return ChatSender(
    userId: userId,
    nickname: nickname,
    profileImageUrl: imageUrl is String && imageUrl.isNotEmpty
        ? imageUrl
        : null,
    isDeleted: wire['isDeleted'] == true,
  );
}

/// 한 페이지를 읽는다. **본문이 비어 있어도 던지지 않는다.**
///
/// 빈 페이지와 "못 읽었다"를 가르지 않는다 — 어느 쪽이든 화면이 할 일은 같다.
ChatHistory chatHistoryFromJson(Map<String, dynamic>? body) {
  final items = body?['items'];
  final cursor = body?['nextCursor'];

  return ChatHistory(
    items: items is List
        ? [for (final one in items) ?chatFromJson(one)]
        : const [],
    // 빈 문자열을 커서로 쓰면 400이다. 없는 것과 같게 다룬다.
    nextCursor: cursor is String && cursor.isNotEmpty ? cursor : null,
  );
}
