import 'package:runiverse/features/chat/domain/chat_message.dart';

/// 어느 방의 채팅인지. **저장소가 방을 알아야 하는 전부다.**
///
/// 파티원 명단을 함께 들고 다니는 이유는 가짜 저장소가 **명단 안의 사람으로만**
/// 메시지를 만들어야 하기 때문이다 — 명단 밖 id가 섞이면 화면이 전부
/// '탈퇴한 사용자'로 그린다.
class ChatRoomSeed {
  const ChatRoomSeed({
    required this.runningRoomId,
    required this.partyUserIds,
    required this.myUserId,
  });

  final int runningRoomId;
  final List<String> partyUserIds;

  /// 내 것으로 그려야 하는 메시지를 가르는 기준. [partyUserIds] 안에 있다.
  final String myUserId;
}

/// 채팅이 실패했다. **왜 실패했는지는 아직 가르지 않는다** — 서버가 없어서
/// 실패 조건을 정할 수 없고, 화면은 "다시 시도" 하나로 받는다.
class ChatException implements Exception {
  const ChatException();
}

/// 대기방 채팅의 경계. **화면은 이것만 안다.**
///
/// 지금 끼우는 구현은 가짜 하나뿐이고, 서버가 정해지면 같은 자리에 진짜가 들어온다.
abstract interface class ChatRepository {
  /// 지난 메시지. 실패하면 [ChatException]을 던진다.
  Future<List<ChatMessage>> history(ChatRoomSeed seed);

  /// 새로 들어오는 메시지. **구독하는 쪽이 끊는다.**
  Stream<ChatMessage> incoming(ChatRoomSeed seed);

  /// 한 건 보낸다. 보낸 것은 [incoming]으로 되돌아온다.
  Future<void> send(ChatRoomSeed seed, String text);
}
