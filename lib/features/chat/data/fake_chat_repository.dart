import 'dart:async';

import 'package:runiverse/features/chat/domain/chat_message.dart';
import 'package:runiverse/features/chat/domain/chat_repository.dart';

/// 서버가 없는 동안 채팅 화면을 세워 두는 구현.
///
/// ## ⚠️ 살아 있는 것처럼 보이게 만들지 않았다
///
/// **자동 답장이 없다.** 가짜가 말을 받아주면 서버가 없다는 사실을 잊게 되고,
/// 요청하지 않은 연출이기도 하다. 들어오는 메시지는 내가 보낸 것과 테스트가
/// [emit]으로 밀어 넣은 것뿐이다.
///
/// **[fails]로 실패하게 만들 수 있다.** 늘 성공하면 화면의 error 3분기가 한 번도
/// 그려지지 않고, 그것을 덮는 테스트도 쓸 수 없다. 제품 경로에서는 끄고 쓴다.
///
/// [now]를 넣으면 결과가 결정론적이다 — `messageId`를 시각과 순번으로 짓기
/// 때문에 난수가 없고, 같은 `now`면 같은 목록이 나온다. 그리는 순서가 흔들리면
/// 화면을 눈으로 확인할 수 없다.
class FakeChatRepository implements ChatRepository {
  FakeChatRepository({this.fails = false, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final bool fails;
  final DateTime Function() _now;

  final _controller = StreamController<ChatMessage>.broadcast();

  int _historyCalls = 0;
  int _sendCalls = 0;

  /// 테스트가 들여다보는 창. 같은 방에 두 번 붙지 않는지, 공백 전송이 저장소까지
  /// 가지 않는지, 구독이 끊겼는지는 **상태만으로는 확인할 수 없다.**
  int get historyCalls => _historyCalls;
  int get sendCalls => _sendCalls;
  bool get hasListener => _controller.hasListener;

  /// 지난 대화 일곱 건. 입장 알림 하나로 시작하고, 뒤쪽 두 개가 안 읽음이다.
  @override
  Future<List<ChatMessage>> history(ChatRoomSeed seed) async {
    _historyCalls++;
    if (fails) throw const ChatException();

    final at = _now();
    final stamp = at.millisecondsSinceEpoch;
    final party = seed.partyUserIds;
    final total = _texts.length + 1;

    // 시각은 2분 간격으로 과거에 흩어 놓는다. 오름차순이어야 화면이 그대로
    // 위에서 아래로 쌓는다.
    DateTime sentAt(int index) =>
        at.subtract(Duration(minutes: (total - index) * 2));

    // ⚠️ **입장한 사람을 명단 끝에서 집는다.** 첫 사람으로 집으면 나 자신이
    // "들어왔어요"라고 알려지는 경우가 흔해진다.
    final messages = <ChatMessage>[
      ChatMessage(
        messageId: 'fake-$stamp-0',
        senderUserId: party.last,
        kind: ChatMessageKind.joined,
        sentAt: sentAt(0),
      ),
    ];

    for (var i = 0; i < _texts.length; i++) {
      final index = i + 1;
      messages.add(
        ChatMessage(
          messageId: 'fake-$stamp-$index',
          senderUserId: party[i % party.length],
          kind: ChatMessageKind.text,
          sentAt: sentAt(index),
          text: _texts[i],
          // 뒤쪽 두 개만 안 읽음이다 — 배지에 숫자가 처음부터 보여야 한다.
          isRead: index < total - 2,
        ),
      );
    }

    return messages;
  }

  @override
  Stream<ChatMessage> incoming(ChatRoomSeed seed) => _controller.stream;

  @override
  Future<void> send(ChatRoomSeed seed, String text) async {
    _sendCalls++;
    if (fails) throw const ChatException();

    final at = _now();
    emit(
      ChatMessage(
        messageId: 'fake-sent-${at.millisecondsSinceEpoch}-$_sendCalls',
        senderUserId: seed.myUserId,
        kind: ChatMessageKind.text,
        sentAt: at,
        text: text,
      ),
    );
  }

  /// 서버가 보낸 것처럼 밀어 넣는다. **제품 경로에는 없고 테스트만 쓴다.**
  void emit(ChatMessage message) => _controller.add(message);

  /// 인사와 정보 공유뿐이다. 좌표·순위·"친구"·이모지를 넣지 않는다 — 설계 2절의
  /// 반목표다.
  static const _texts = [
    '안녕하세요, 오늘 잘 부탁드려요',
    '반가워요. 저도 이 시간대가 편해요',
    '저는 오늘 가볍게 갈 생각이에요',
    '좋아요. 저도 무리하지 않으려고요',
    '바람이 좀 있어서 겉옷 하나 챙겼어요',
    '곧 준비하고 나갈게요',
  ];
}
