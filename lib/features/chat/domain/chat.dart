/// 대기방에서 주고받은 한 건. **서버의 `Chat`과 같은 모양이다.**
///
/// ## ⚠️ [chatId]가 정렬과 병합을 모두 맡는다
///
/// 생성 순서대로 커지는 값이라 **이것이 곧 시간 순이다.** 목록 응답과 실시간
/// 이벤트가 겹쳐 올 수 있으므로 같은 [chatId]는 하나로 합치고([mergeChat]),
/// 화면은 오름차순으로 그린다. 수정돼도 자리는 바뀌지 않는다.
///
/// [createdAt]으로 정렬하지 않는다 — 초 단위라 같은 값이 나오고, 그러면 같은
/// 초에 온 두 메시지의 순서가 흔들린다.
///
/// ## ⚠️ 지운 메시지도 목록에서 빠지지 않는다
///
/// [isDeleted]가 `true`면 [content]가 `null`로 온다. 빼면 그 자리에서 대화가
/// 끊겨 보이므로, 자리를 지키고 "삭제된 메시지"로 그린다.
library;

/// 보낸 사람. **메시지가 직접 들고 온다.**
///
/// ## ⚠️ 방 명단에서 찾지 않는다
///
/// 방을 떠난 사람의 지난 메시지도 목록에 남는데, 명단에서 찾으면 그 사람이
/// 전부 '탈퇴한 사용자'로 그려진다. 서버가 메시지마다 보낸 사람을 실어 주므로
/// **그대로 쓴다.**
///
/// 파티 색만은 방 명단이 정한다 — 러닝 화면에서 본 그 사람 색과 같아야 해서,
/// 명단의 순서가 색을 가른다.
class ChatSender {
  const ChatSender({
    required this.userId,
    required this.nickname,
    this.profileImageUrl,
    this.isDeleted = false,
  });

  final String userId;

  /// 탈퇴한 사용자는 서버가 `탈퇴한 사용자`로 준다.
  final String nickname;

  /// 사진이 없거나 탈퇴한 사용자면 `null`.
  final String? profileImageUrl;

  /// **회원 탈퇴 여부다.** 메시지를 지운 것([Chat.isDeleted])과 다르다.
  final bool isDeleted;
}

class Chat {
  const Chat({
    required this.chatId,
    required this.runningRoomId,
    required this.sender,
    required this.createdAt,
    this.content,
    this.isDeleted = false,
    this.editedAt,
    this.isRead = true,
  });

  final int chatId;
  final int runningRoomId;
  final ChatSender sender;

  /// 내용. **지운 메시지면 `null`이다.**
  final String? content;

  /// 보낸 사람이 지웠는가. [ChatSender.isDeleted](탈퇴)와 다르다.
  final bool isDeleted;

  /// 마지막 수정 시각. 고친 적 없으면 `null`.
  final DateTime? editedAt;

  final DateTime createdAt;

  /// 내가 읽었는가. **서버가 모르는 값이다** — 배지의 숫자를 세기 위해 앱이
  /// 붙인다. 남이 내 메시지를 읽었는지(읽음 확인)와는 다른 것이고, 그쪽은
  /// 이번 범위에 없다.
  ///
  /// ⚠️ 기본값이 `true`다. 목록으로 받은 과거 메시지는 배지에 세지 않는다.
  final bool isRead;

  /// "수정됨"을 붙일지. **지운 메시지에는 붙이지 않는다** — 삭제 상태가
  /// 우선이라, 함께 그리면 "삭제된 메시지 (수정됨)"이 된다.
  bool get isEdited => !isDeleted && editedAt != null;

  /// 지운 뒤의 모습. **삭제 응답은 `204`로 본문이 없어서** 부른 쪽이 만든다.
  ///
  /// `editedAt`은 들고 간다 — 서버도 지우지 않는다. [isEdited]가 삭제를
  /// 우선하므로 "수정됨"은 붙지 않는다.
  Chat get asDeleted => Chat(
    chatId: chatId,
    runningRoomId: runningRoomId,
    sender: sender,
    createdAt: createdAt,
    isDeleted: true,
    editedAt: editedAt,
    isRead: isRead,
  );

  Chat copyWith({bool? isRead}) => Chat(
    chatId: chatId,
    runningRoomId: runningRoomId,
    sender: sender,
    createdAt: createdAt,
    content: content,
    isDeleted: isDeleted,
    editedAt: editedAt,
    isRead: isRead ?? this.isRead,
  );
}
