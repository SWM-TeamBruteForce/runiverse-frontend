import 'package:runiverse/features/chat/domain/chat.dart';
import 'package:runiverse/features/chat/domain/chat_failure.dart';
import 'package:runiverse/features/chat/domain/chat_repository.dart';

/// 서버 없이 채팅 화면을 세워 두는 구현.
///
/// ## ⚠️ 살아 있는 것처럼 보이게 만들지 않았다
///
/// **자동 답장이 없다.** 가짜가 말을 받아주면 서버가 없다는 사실을 잊게 된다.
/// 실시간 수신은 이제 저장소의 일이 아니다 — 대기방 스트림이 나르고
/// `ChatEventBus`가 흘려 준다.
///
/// **[fails]로 실패하게 만들 수 있다.** 늘 성공하면 화면의 error 3분기가 한 번도
/// 그려지지 않는다. [failure]로 어느 갈래인지도 고른다 — 409(채팅 닫힘)와
/// 404(방 밖)는 화면이 할 일이 전혀 다르다.
///
/// [now]를 넣으면 결과가 결정론적이다. 그리는 순서가 흔들리면 화면을 눈으로
/// 확인할 수 없다.
class FakeChatRepository implements ChatRepository {
  FakeChatRepository({
    this.myUserId = 'me',
    this.fails = false,
    this.failure = ChatFailure.network,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// 내 것으로 그려질 메시지의 주인. **수정·삭제 버튼이 보이려면 내 말이
  /// 적어도 하나 있어야 한다.**
  final String myUserId;

  /// ⚠️ **가변이다.** "실패한 뒤 다시 붙으면 산다"를 한 컨테이너 안에서
  /// 확인하려면 도중에 바꿀 수 있어야 한다. 제품 경로는 끄고 쓴다.
  bool fails;
  ChatFailure failure;

  final DateTime Function() _now;

  /// 방 번호별로 들고 있는다. 수정·삭제가 다음 조회에 보여야 한다.
  final _rooms = <int, Map<int, Chat>>{};

  int _historyCalls = 0;
  int _sendCalls = 0;

  /// 테스트가 들여다보는 창. 같은 방에 두 번 붙지 않는지, 공백 전송이
  /// 저장소까지 가지 않는지는 **상태만으로는 확인할 수 없다.**
  int get historyCalls => _historyCalls;
  int get sendCalls => _sendCalls;

  @override
  Future<ChatHistory> history(
    int runningRoomId, {
    String? cursor,
    int limit = 50,
  }) async {
    _historyCalls++;
    if (fails) throw ChatException(failure);

    final room = _seeded(runningRoomId);
    // 최신순으로 늘어놓는다 — 서버가 그렇게 준다.
    final newestFirst = room.values.toList()
      ..sort((a, b) => b.chatId.compareTo(a.chatId));

    // 커서는 "이 번호보다 작은 것부터"다. 서버의 불투명 커서를 흉내 내지 않고
    // 읽을 수 있게 둔다 — 가짜를 디버깅하느라 시간을 쓰지 않는다.
    final before = cursor == null ? null : int.tryParse(cursor);
    final page = [
      for (final one in newestFirst)
        if (before == null || one.chatId < before) one,
    ].take(limit).toList();

    final last = page.isEmpty ? null : page.last.chatId;
    final hasMore =
        last != null && newestFirst.any((one) => one.chatId < last);

    return ChatHistory(
      items: page,
      nextCursor: hasMore ? '$last' : null,
    );
  }

  @override
  Future<Chat> send(int runningRoomId, String content) async {
    _sendCalls++;
    if (fails) throw ChatException(failure);

    final room = _seeded(runningRoomId);
    final chat = Chat(
      chatId: _nextId(room),
      runningRoomId: runningRoomId,
      sender: ChatSender(userId: myUserId, nickname: '나'),
      content: content,
      createdAt: _now(),
    );
    room[chat.chatId] = chat;
    return chat;
  }

  @override
  Future<Chat> edit(
    int runningRoomId, {
    required int chatId,
    required String content,
  }) async {
    if (fails) throw ChatException(failure);

    final room = _seeded(runningRoomId);
    final kept = room[chatId];
    // 없거나 이미 지운 것은 서버가 404로 답한다. 남의 것인지도 여기서는
    // 가르지 않는다 — 서버가 셋을 구분하지 않는다.
    if (kept == null || kept.isDeleted) {
      throw const ChatException(ChatFailure.notFound);
    }

    final edited = Chat(
      chatId: kept.chatId,
      runningRoomId: kept.runningRoomId,
      sender: kept.sender,
      content: content,
      editedAt: _now(),
      createdAt: kept.createdAt,
    );
    room[chatId] = edited;
    return edited;
  }

  @override
  Future<void> delete(int runningRoomId, int chatId) async {
    if (fails) throw ChatException(failure);

    final room = _seeded(runningRoomId);
    final kept = room[chatId];
    if (kept == null || kept.isDeleted) {
      throw const ChatException(ChatFailure.notFound);
    }

    room[chatId] = Chat(
      chatId: kept.chatId,
      runningRoomId: kept.runningRoomId,
      sender: kept.sender,
      // 지운 메시지는 내용이 비어서 온다.
      isDeleted: true,
      createdAt: kept.createdAt,
      editedAt: kept.editedAt,
    );
  }

  int _nextId(Map<int, Chat> room) =>
      room.keys.fold(1000, (a, b) => a > b ? a : b) + 1;

  /// 처음 부를 때 지난 대화를 깐다. **방 번호가 `chatId`에 섞이지 않는다** —
  /// 방마다 따로 들고 있어서 섞일 자리가 없다.
  Map<int, Chat> _seeded(int runningRoomId) {
    final existing = _rooms[runningRoomId];
    if (existing != null) return existing;

    final at = _now();
    final room = <int, Chat>{};
    // 시각은 2분 간격으로 과거에 흩어 놓는다.
    for (var i = 0; i < _script.length; i++) {
      final (userId, nickname, text) = _script[i];
      final chatId = 1001 + i;
      room[chatId] = Chat(
        chatId: chatId,
        runningRoomId: runningRoomId,
        sender: ChatSender(
          userId: userId == 'me' ? myUserId : userId,
          nickname: nickname,
        ),
        content: text,
        createdAt: at.subtract(Duration(minutes: (_script.length - i) * 2)),
      );
    }
    _rooms[runningRoomId] = room;
    return room;
  }

  /// 인사와 정보 공유뿐이다. 좌표·순위·"친구"·이모지를 넣지 않는다 — 설계 2절의
  /// 반목표다.
  ///
  /// ⚠️ **내 말을 섞어 둔다.** 전부 남의 말이면 수정·삭제 버튼이 한 번도
  /// 보이지 않아, 그 자리를 눈으로 확인할 수 없다.
  static const _script = <(String, String, String)>[
    ('u1', '영희', '안녕하세요, 오늘 잘 부탁드려요'),
    ('u2', '철수', '반가워요. 저도 이 시간대가 편해요'),
    ('me', '나', '저는 오늘 가볍게 갈 생각이에요'),
    ('u1', '영희', '좋아요. 저도 무리하지 않으려고요'),
    ('u2', '철수', '바람이 좀 있어서 겉옷 하나 챙겼어요'),
    ('me', '나', '곧 준비하고 나갈게요'),
  ];
}
