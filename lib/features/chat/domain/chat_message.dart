/// 메시지의 종류. **글과 입장 알림은 생긴 것이 다르다** — 글은 버블이고 알림은
/// 가운데 알약이다.
enum ChatMessageKind { text, joined }

/// 대기방에서 주고받은 한 건.
///
/// ## ⚠️ 발신자의 이름과 사진을 들고 있지 않다
///
/// [senderUserId]만 들고, 이름·사진은 **화면이 방 명단에서 찾는다.** 그래서
/// 서버 계약을 덜 가정하고, 명단에서 사라진 사람은 탈퇴 표기와 한 벌로 처리된다.
/// 입장 알림 문구도 화면이 만든다 — 가짜 저장소가 닉네임을 알 필요가 없다.
///
/// [isRead]는 **내가 읽었는가**다. 남이 내 메시지를 읽었는지(읽음 확인)와는
/// 다른 것이고, 그쪽은 이번 범위에 없다.
class ChatMessage {
  const ChatMessage({
    required this.messageId,
    required this.senderUserId,
    required this.kind,
    required this.sentAt,
    this.text,
    this.isRead = true,
  });

  final String messageId;
  final String senderUserId;
  final ChatMessageKind kind;

  /// [ChatMessageKind.text]일 때만 채운다.
  final String? text;

  final DateTime sentAt;
  final bool isRead;

  ChatMessage copyWith({bool? isRead}) => ChatMessage(
    messageId: messageId,
    senderUserId: senderUserId,
    kind: kind,
    sentAt: sentAt,
    text: text,
    isRead: isRead ?? this.isRead,
  );
}
