import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/chat/data/fake_chat_repository.dart';
import 'package:runiverse/features/chat/domain/chat.dart';
import 'package:runiverse/features/chat/domain/chat_event_bus.dart';
import 'package:runiverse/features/chat/domain/chat_failure.dart';
import 'package:runiverse/features/chat/presentation/chat_provider.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/session/domain/user_status.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// 채팅 상태 — **합치는 규칙이 여기서 실제로 쓰인다.**
///
/// 목록 응답·이전 페이지·실시간 이벤트·내 API 응답이 겹쳐서 같은 메시지를 싣고
/// 온다. 받은 순서로 덮으면 지운 말이 되살아나고 고친 말이 되돌아간다.
///
/// 안 읽은 수도 여기서 나온다. 틀리면 사람이 읽은 말을 또 읽으러 들어간다.
void main() {
  DateTime fixedNow() => DateTime(2026, 11, 4, 19, 18);

  const roomId = 130;
  const otherRoomId = 131;

  ({
    ProviderContainer container,
    FakeChatRepository fake,
    FakeUserStatusRepository statuses,
    ChatEventBus bus,
  })
  setUpChat({bool fails = false, ChatFailure failure = ChatFailure.network}) {
    final fake = FakeChatRepository(
      fails: fails,
      failure: failure,
      now: fixedNow,
    );
    final statuses = FakeUserStatusRepository();
    final bus = ChatEventBus();
    final container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(fake),
        chatEventBusProvider.overrideWithValue(bus),
        userStatusRepositoryProvider.overrideWithValue(statuses),
      ],
    );
    addTearDown(container.dispose);
    // ⚠️ **보는 사람을 하나 둔다.** provider가 auto-dispose라 아무도 안 보면
    // 첫 `await` 사이에 버려지고, 그 뒤 `read`는 빈 상태의 새 instance를 준다.
    // 실제 화면은 배지 때문에 늘 watch하고 있다.
    final watching = container.listen(chatProvider, (_, _) {});
    addTearDown(watching.close);
    return (container: container, fake: fake, statuses: statuses, bus: bus);
  }

  ChatController chat(ProviderContainer container) =>
      container.read(chatProvider.notifier);
  ChatState stateOf(ProviderContainer container) =>
      container.read(chatProvider);

  /// 서버가 보낸 것처럼 만드는 한 건.
  Chat incoming({
    int chatId = 9001,
    int room = roomId,
    String sender = 'u1',
    String? content = '거의 다 왔어요',
    bool isDeleted = false,
    DateTime? editedAt,
  }) => Chat(
    chatId: chatId,
    runningRoomId: room,
    sender: ChatSender(userId: sender, nickname: '영희'),
    content: isDeleted ? null : content,
    isDeleted: isDeleted,
    editedAt: editedAt,
    createdAt: fixedNow(),
  );

  group('첫 조회', () {
    test('싣는 동안 loading이고, 끝나면 목록이 선다', () async {
      final app = setUpChat();

      final loading = chat(app.container).connect(roomId);
      expect(stateOf(app.container).loading, isTrue);
      await loading;

      final state = stateOf(app.container);
      expect(state.loading, isFalse);
      expect(state.messages, isNotEmpty);
      expect(state.runningRoomId, roomId);
    });

    test('⚠️ chatId 오름차순으로 들고 있는다 — 서버는 최신순으로 준다', () async {
      // 뒤집지 않으면 화면이 거꾸로 그려진다.
      final app = setUpChat();
      await chat(app.container).connect(roomId);

      final ids = stateOf(app.container).messages.map((one) => one.chatId);
      expect(ids.toList(), [...ids]..sort());
    });

    test('⚠️ 같은 방이면 다시 싣지 않는다', () async {
      // 화면이 다시 그려질 때마다 과거를 또 부르면 목록이 깜빡이고 서버를
      // 두 번 때린다.
      final app = setUpChat();
      await chat(app.container).connect(roomId);
      await chat(app.container).connect(roomId);

      expect(app.fake.historyCalls, 1);
    });

    test('⚠️ 방을 옮기면 전 방의 말이 사라진다', () async {
      final app = setUpChat();
      await chat(app.container).connect(roomId);
      await chat(app.container).connect(otherRoomId);

      final state = stateOf(app.container);
      expect(state.runningRoomId, otherRoomId);
      expect(
        state.messages.every((one) => one.runningRoomId == otherRoomId),
        isTrue,
      );
    });

    test('실패하면 갈래가 남고, 다시 부르면 다시 싣는다', () async {
      final app = setUpChat(fails: true);
      await chat(app.container).connect(roomId);

      expect(stateOf(app.container).failure, ChatFailure.network);
      expect(stateOf(app.container).failed, isTrue);

      app.fake.fails = false;
      await chat(app.container).connect(roomId);

      expect(stateOf(app.container).failed, isFalse);
      expect(stateOf(app.container).messages, isNotEmpty);
    });

    test('⚠️ 409면 채팅이 닫힌 것이다 — 재시도하지 않는다', () async {
      // 러닝이 시작됐다. 그 상태로 되풀이하면 러닝 중에 계속 서버를 때린다.
      final app = setUpChat(fails: true, failure: ChatFailure.closed);
      await chat(app.container).connect(roomId);

      expect(stateOf(app.container).closed, isTrue);

      // 다시 불러도 나가지 않는다.
      await chat(app.container).connect(roomId);
      expect(app.fake.historyCalls, 1);
    });

    test('⚠️ 404면 방 참여 여부를 다시 확인한다', () async {
      // 나갔거나 처음부터 이 방이 아니다. 활성 신청이 없으면 상태 조회가
      // 홈으로 이끈다 — 화면을 여기서 옮기지 않는다.
      final app = setUpChat(fails: true, failure: ChatFailure.notFound);
      app.statuses.status = const UserStatusIdle();

      await chat(app.container).connect(roomId);

      expect(app.statuses.calls, greaterThan(0));
    });
  });

  group('이전 메시지', () {
    test('위로 긁으면 이전 페이지가 앞에 붙는다', () async {
      final app = setUpChat();
      // 한 번에 둘만 받아 커서가 남게 한다.
      await chat(app.container).connect(roomId, limit: 2);
      final first = stateOf(app.container).messages.length;
      expect(stateOf(app.container).hasMore, isTrue);

      await chat(app.container).loadMore();

      expect(stateOf(app.container).messages.length, greaterThan(first));
      // 자리는 여전히 오름차순이다.
      final ids = stateOf(app.container).messages.map((one) => one.chatId);
      expect(ids.toList(), [...ids]..sort());
    });

    test('⚠️ 커서가 없으면 부르지 않는다', () async {
      // 방의 첫 메시지까지 다 받았다. 더 긁어도 나올 것이 없다.
      final app = setUpChat();
      await chat(app.container).connect(roomId);
      expect(stateOf(app.container).hasMore, isFalse);

      final before = app.fake.historyCalls;
      await chat(app.container).loadMore();

      expect(app.fake.historyCalls, before);
    });

    test('⚠️ 긁는 동안 또 부르지 않는다', () async {
      // 스크롤이 한 프레임에 여러 번 닿는다. 그대로 두면 같은 페이지를
      // 여러 번 받는다.
      final app = setUpChat();
      await chat(app.container).connect(roomId, limit: 2);

      final before = app.fake.historyCalls;
      await Future.wait([
        chat(app.container).loadMore(),
        chat(app.container).loadMore(),
      ]);

      expect(app.fake.historyCalls, before + 1);
    });
  });

  group('보내기', () {
    test('보내는 동안 내 말이 먼저 보이고, 응답이 오면 자리를 잡는다', () async {
      final app = setUpChat();
      await chat(app.container).connect(roomId);

      final sending = chat(app.container).send('곧 나갈게요');
      // ⚠️ 눈에 보여야 한다. 응답을 기다려 그리면 느린 망에서 먹통으로 느낀다.
      expect(stateOf(app.container).pending, hasLength(1));
      await sending;

      final state = stateOf(app.container);
      expect(state.pending, isEmpty);
      expect(state.messages.last.content, '곧 나갈게요');
    });

    test('⚠️ 공백만이면 저장소까지 가지 않는다', () async {
      final app = setUpChat();
      await chat(app.container).connect(roomId);

      await chat(app.container).send('   \n ');

      expect(app.fake.sendCalls, 0);
      expect(stateOf(app.container).pending, isEmpty);
    });

    test('⚠️ 200자를 넘으면 보내지 않는다', () async {
      // 서버도 400으로 막지만, 보내 보고 실패를 그리면 쓴 말이 날아간 것처럼
      // 보인다. 입력 단계에서 막는다.
      final app = setUpChat();
      await chat(app.container).connect(roomId);

      await chat(app.container).send('가' * 201);

      expect(app.fake.sendCalls, 0);
    });

    test('⚠️ 실패하면 다시 보내기로 남는다 — 자동으로 또 보내지 않는다', () async {
      // 응답을 못 받았어도 서버에는 저장됐을 수 있다. 자동 재전송은 같은 말을
      // 두 번 남긴다.
      final app = setUpChat();
      await chat(app.container).connect(roomId);
      app.fake.fails = true;

      await chat(app.container).send('곧 나갈게요');

      final pending = stateOf(app.container).pending.single;
      expect(pending.failed, isTrue);
      expect(pending.content, '곧 나갈게요');
      expect(app.fake.sendCalls, 1);
    });

    test('다시 보내기를 누르면 그 한 건만 다시 보낸다', () async {
      final app = setUpChat();
      await chat(app.container).connect(roomId);
      app.fake.fails = true;
      await chat(app.container).send('곧 나갈게요');

      app.fake.fails = false;
      await chat(app.container).resend(stateOf(app.container).pending.single);

      expect(stateOf(app.container).pending, isEmpty);
      expect(stateOf(app.container).messages.last.content, '곧 나갈게요');
    });

    test('실패한 것을 버릴 수 있다', () async {
      // 버릴 길이 없으면 실패한 말풍선이 방을 떠날 때까지 남는다.
      final app = setUpChat();
      await chat(app.container).connect(roomId);
      app.fake.fails = true;
      await chat(app.container).send('곧 나갈게요');

      chat(app.container).discard(stateOf(app.container).pending.single);

      expect(stateOf(app.container).pending, isEmpty);
    });

    test('⚠️ 채팅이 닫혔으면 보내지 않는다', () async {
      final app = setUpChat(fails: true, failure: ChatFailure.closed);
      await chat(app.container).connect(roomId);
      app.fake.fails = false;

      await chat(app.container).send('곧 나갈게요');

      expect(app.fake.sendCalls, 0);
    });
  });

  group('수정', () {
    test('고치면 내용이 바뀌고 수정됨이 붙는다', () async {
      final app = setUpChat();
      await chat(app.container).connect(roomId);
      final mine = stateOf(
        app.container,
      ).messages.firstWhere((one) => one.sender.userId == 'me');

      await chat(app.container).edit(mine.chatId, '조금 늦어요');

      final edited = stateOf(
        app.container,
      ).messages.firstWhere((one) => one.chatId == mine.chatId);
      expect(edited.content, '조금 늦어요');
      expect(edited.isEdited, isTrue);
    });

    test('⚠️ 자리는 바뀌지 않는다', () async {
      final app = setUpChat();
      await chat(app.container).connect(roomId);
      final before = stateOf(
        app.container,
      ).messages.map((one) => one.chatId).toList();
      final mine = stateOf(app.container).messages.first;

      await chat(app.container).edit(mine.chatId, '고쳤어요');

      expect(
        stateOf(app.container).messages.map((one) => one.chatId).toList(),
        before,
      );
    });

    test('⚠️ 같은 내용이면 부르지 않는다', () async {
      // 서버는 같은 내용도 수정으로 쳐서 "수정됨"이 붙는다.
      final app = setUpChat();
      await chat(app.container).connect(roomId);
      final mine = stateOf(app.container).messages.first;

      await chat(app.container).edit(mine.chatId, mine.content!);

      expect(
        stateOf(app.container).messages.first.isEdited,
        isFalse,
        reason: '부르지 않았으니 수정됨이 붙지 않는다',
      );
    });

    test('공백만이거나 200자를 넘으면 부르지 않는다', () async {
      final app = setUpChat();
      await chat(app.container).connect(roomId);
      final mine = stateOf(app.container).messages.first;

      await chat(app.container).edit(mine.chatId, '  ');
      await chat(app.container).edit(mine.chatId, '가' * 201);

      expect(stateOf(app.container).messages.first.isEdited, isFalse);
    });

    test('⚠️ 404면 목록을 다시 받는다 — 방에서 나가지 않는다', () async {
      // 없는 메시지·남의 메시지·이미 지운 것이 모두 404다. 그것만으로 방을
      // 떠나면 멀쩡한 방에서 쫓겨난다. 서버가 이미 지운 것을 고치려는 경우다.
      final app = setUpChat();
      await chat(app.container).connect(roomId);
      final mine = stateOf(app.container).messages.first;
      final before = app.fake.historyCalls;
      app.fake
        ..fails = true
        ..failure = ChatFailure.notFound;

      await chat(app.container).edit(mine.chatId, '고쳤어요');

      expect(app.fake.historyCalls, before + 1);
      expect(stateOf(app.container).runningRoomId, roomId);
    });

    test('⚠️ 재조회까지 404면 그때 참여 여부를 확인한다', () async {
      // 메시지 하나가 없는 것과 **방 밖인 것**을 서버가 가르지 않는다. 그래서
      // 목록을 한 번 더 물어 가른다 — 그쪽도 404면 정말 방 밖이다.
      final app = setUpChat();
      await chat(app.container).connect(roomId);
      final mine = stateOf(app.container).messages.first;
      app.fake
        ..fails = true
        ..failure = ChatFailure.notFound;

      await chat(app.container).edit(mine.chatId, '고쳤어요');

      expect(app.statuses.calls, greaterThan(0));
    });

    test('⚠️ 들고 있지 않은 번호는 부르기 전에 막는다', () async {
      // 화면에 없는 메시지를 고칠 길은 없다. 불러 봐야 404라, 그 왕복으로
      // 목록만 다시 받게 된다.
      final app = setUpChat();
      await chat(app.container).connect(roomId);
      final before = app.fake.historyCalls;

      await chat(app.container).edit(999999, '고쳤어요');
      await chat(app.container).remove(999999);

      expect(app.fake.historyCalls, before);
    });
  });

  group('삭제', () {
    test('⚠️ 204라 응답에 메시지가 없다 — 부른 쪽이 비운다', () async {
      final app = setUpChat();
      await chat(app.container).connect(roomId);
      final mine = stateOf(app.container).messages.first;

      await chat(app.container).remove(mine.chatId);

      final deleted = stateOf(
        app.container,
      ).messages.firstWhere((one) => one.chatId == mine.chatId);
      expect(deleted.isDeleted, isTrue);
      expect(deleted.content, isNull);
    });

    test('⚠️ 목록에서 빠지지 않고 자리를 지킨다', () async {
      final app = setUpChat();
      await chat(app.container).connect(roomId);
      final before = stateOf(app.container).messages.length;

      await chat(
        app.container,
      ).remove(stateOf(app.container).messages.first.chatId);

      expect(stateOf(app.container).messages, hasLength(before));
    });
  });

  group('실시간 수신', () {
    test('새 메시지가 들어온다', () async {
      final app = setUpChat();
      await chat(app.container).connect(roomId);

      chat(app.container).received(ChatChange(ChatChangeKind.sent, incoming()));

      expect(stateOf(app.container).messages.last.chatId, 9001);
    });

    test('⚠️ 보고 있지 않으면 안 읽음으로 쌓인다', () async {
      final app = setUpChat();
      await chat(app.container).connect(roomId);

      chat(app.container).received(ChatChange(ChatChangeKind.sent, incoming()));

      expect(stateOf(app.container).unread, 1);
    });

    test('보고 있는 동안 온 것은 읽은 것이다', () async {
      final app = setUpChat();
      await chat(app.container).connect(roomId);
      chat(app.container).open();

      chat(app.container).received(ChatChange(ChatChangeKind.sent, incoming()));

      expect(stateOf(app.container).unread, 0);
    });

    test('⚠️ 수정·삭제는 배지에 세지 않는다', () async {
      // 아직 위로 긁어 오지 않은 과거 메시지의 수정·삭제가 올 수 있다. 본 적
      // 없는 "삭제된 메시지"가 배지에 세어지면 들어가 봐도 새 말이 없다.
      final app = setUpChat();
      await chat(app.container).connect(roomId);

      chat(app.container).received(
        ChatChange(
          ChatChangeKind.deleted,
          incoming(chatId: 500, isDeleted: true),
        ),
      );
      chat(app.container).received(
        ChatChange(
          ChatChangeKind.edited,
          incoming(chatId: 501, editedAt: fixedNow()),
        ),
      );

      expect(stateOf(app.container).unread, 0);
    });

    test('⚠️ 다른 방 것은 버린다', () async {
      final app = setUpChat();
      await chat(app.container).connect(roomId);
      final before = stateOf(app.container).messages.length;

      chat(
        app.container,
      ).received(ChatChange(ChatChangeKind.sent, incoming(room: otherRoomId)));

      expect(stateOf(app.container).messages, hasLength(before));
    });

    test('버스로 들어온 것도 반영된다', () async {
      // 대기방 provider가 밀어 넣는 길이다. 끊기면 실시간 수신이 통째로 죽는다.
      final app = setUpChat();
      await chat(app.container).connect(roomId);

      app.bus.emit(ChatChange(ChatChangeKind.sent, incoming()));
      await Future<void>.delayed(Duration.zero);

      expect(stateOf(app.container).messages.last.chatId, 9001);
    });

    test('⚠️ 삭제가 늦게 온 전송 이벤트에 되살아나지 않는다', () async {
      final app = setUpChat();
      await chat(app.container).connect(roomId);

      chat(app.container).received(
        ChatChange(
          ChatChangeKind.deleted,
          incoming(chatId: 9001, isDeleted: true),
        ),
      );
      chat(app.container).received(
        ChatChange(
          ChatChangeKind.sent,
          incoming(chatId: 9001, content: '되살아남'),
        ),
      );

      final one = stateOf(
        app.container,
      ).messages.firstWhere((one) => one.chatId == 9001);
      expect(one.isDeleted, isTrue);
      expect(one.content, isNull);
    });
  });

  group('다시 붙었을 때', () {
    test('⚠️ 목록과 커서를 비우고 다시 받는다', () async {
      // 끊긴 동안 놓친 이벤트는 다시 오지 않는다. 목록을 다시 받아 맞춘다.
      final app = setUpChat();
      await chat(app.container).connect(roomId);
      final before = app.fake.historyCalls;

      await chat(app.container).reload();

      expect(app.fake.historyCalls, before + 1);
      expect(stateOf(app.container).messages, isNotEmpty);
    });

    test('⚠️ 새 연결에서 이미 받은 이벤트를 버리지 않는다', () async {
      // 목록 응답이 왔다는 이유로 초기화하면 그 사이에 온 말이 사라진다.
      final app = setUpChat();
      await chat(app.container).connect(roomId);

      // 스트림이 다시 붙고, 목록보다 이벤트가 먼저 닿았다.
      final reloading = chat(app.container).reload();
      chat(
        app.container,
      ).received(ChatChange(ChatChangeKind.sent, incoming(chatId: 9001)));
      await reloading;

      expect(
        stateOf(app.container).messages.any((one) => one.chatId == 9001),
        isTrue,
      );
    });
  });

  group('읽음', () {
    test('화면이 뜨면 들고 있던 것이 전부 읽음이 된다', () async {
      final app = setUpChat();
      await chat(app.container).connect(roomId);
      chat(app.container).received(ChatChange(ChatChangeKind.sent, incoming()));
      expect(stateOf(app.container).unread, 1);

      chat(app.container).open();

      expect(stateOf(app.container).unread, 0);
    });

    test('떠나면 이후에 온 것이 다시 쌓인다', () async {
      final app = setUpChat();
      await chat(app.container).connect(roomId);
      chat(app.container).open();
      chat(app.container).close();

      chat(app.container).received(ChatChange(ChatChangeKind.sent, incoming()));

      expect(stateOf(app.container).unread, 1);
    });
  });
}
