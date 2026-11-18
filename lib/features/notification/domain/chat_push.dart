/// 대기방 채팅 푸시 `ROOM_CHAT_SENT` 한 건.
///
/// 서버가 **알림 블록 없이 data만** 보낸다(api-spec 5-E · feature-spec 알림 절).
/// 안드로이드는 OS가 아무것도 띄우지 않으므로 앱이 이것을 읽어 그린다.
///
/// | data | 뜻 |
/// |---|---|
/// | `runningRoomId` | 방 — 방마다 알림 하나에 쌓는다 |
/// | `chatId` | 줄 번호 — 같은 누름을 두 번 받았는지 가린다 |
/// | `chatType` | `MESSAGE`(말) / `JOINED`(들어옴). 나간 줄은 푸시가 없다 |
/// | `title` | 방 제목(`19:30 - 5 km 러닝`) |
/// | `body` | 말이면 내용만, 들어옴이면 서버가 만든 문장(`영희님이 들어왔어요`) |
/// | `actorId` · `actorNickname` · `actorProfileImageUrl` | 보낸 사람 또는 들어온 사람. 사진은 있을 때만 온다 |
class ChatPush {
  const ChatPush({
    required this.runningRoomId,
    required this.chatId,
    required this.kind,
    required this.title,
    required this.body,
    required this.actorId,
    required this.actorNickname,
    this.actorProfileImageUrl,
  });

  static const type = 'ROOM_CHAT_SENT';

  /// 채팅 푸시가 아니거나 그릴 값이 빠졌으면 `null`이다 — 그리지 않는다.
  ///
  /// 모르는 `chatType`도 `null`이다. `PushLanding`처럼 서버가 종류를 늘려도
  /// 앱이 엉뚱한 줄을 그리지 않는다.
  static ChatPush? of(Map<String, Object?> data) {
    if (data['type'] != type) return null;
    final kind = switch (data['chatType']) {
      'MESSAGE' => ChatPushKind.message,
      'JOINED' => ChatPushKind.joined,
      _ => null,
    };
    final runningRoomId = _text(data['runningRoomId']);
    final chatId = _text(data['chatId']);
    final title = _text(data['title']);
    final body = _text(data['body']);
    final actorId = _text(data['actorId']);
    final actorNickname = _text(data['actorNickname']);
    if (kind == null ||
        runningRoomId == null ||
        chatId == null ||
        title == null ||
        body == null ||
        actorId == null ||
        actorNickname == null) {
      return null;
    }
    return ChatPush(
      runningRoomId: runningRoomId,
      chatId: chatId,
      kind: kind,
      title: title,
      body: body,
      actorId: actorId,
      actorNickname: actorNickname,
      actorProfileImageUrl: _text(data['actorProfileImageUrl']),
    );
  }

  final String runningRoomId;
  final String chatId;
  final ChatPushKind kind;
  final String title;
  final String body;
  final String actorId;
  final String actorNickname;

  /// 1시간 뒤 만료되는 주소다. 못 받으면 사진 없이 그린다.
  final String? actorProfileImageUrl;

  /// 알림을 눌렀을 때 `PushLanding.of`에 넘길 data. 방으로 가는 데 필요한
  /// 것만 남긴다.
  Map<String, Object?> get landingData => {
    'type': type,
    'runningRoomId': runningRoomId,
    'chatId': chatId,
  };

  static String? _text(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}

enum ChatPushKind {
  /// 사람이 쓴 말. 이름 칸에 보낸 사람이 선다.
  message,

  /// 들어온 사람의 안내 줄. 내용에 이미 이름이 있어 이름 칸에는 `안내`가 선다.
  joined,
}
