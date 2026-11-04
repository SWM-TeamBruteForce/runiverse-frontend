import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/chat/data/fake_chat_repository.dart';
import 'package:runiverse/features/chat/domain/chat_message.dart';
import 'package:runiverse/features/chat/domain/chat_repository.dart';
import 'package:runiverse/features/chat/presentation/chat_provider.dart';

/// 채팅 상태. **안 읽은 수가 이 파일의 주인공이다** — 배지의 숫자가 여기서 나오고,
/// 틀리면 사람이 읽은 말을 또 읽으러 들어간다.
///
/// ## ⚠️ 방에 묶인 상태다
///
/// 방 번호가 바뀌면 전 방의 말이 남아 있어서는 안 된다. 그리고 이 provider는
/// `matchRoomProvider`를 **듣지 않는다** — 서로 들으면 Riverpod이
/// `CircularDependencyError`로 막는다. 방 번호와 명단은 화면이 넣어 준다.
void main() {
  DateTime fixedNow() => DateTime(2026, 11, 4, 19, 18);

  const seed = ChatRoomSeed(
    runningRoomId: 130,
    partyUserIds: ['me', 'u1', 'u2'],
    myUserId: 'me',
  );
  const otherRoom = ChatRoomSeed(
    runningRoomId: 131,
    partyUserIds: ['me', 'u9'],
    myUserId: 'me',
  );

  ({ProviderContainer container, FakeChatRepository fake}) setUpChat({
    bool fails = false,
    bool dispose = true,
    bool watch = true,
  }) {
    final fake = FakeChatRepository(fails: fails, now: fixedNow);
    final container = ProviderContainer(
      overrides: [chatRepositoryProvider.overrideWithValue(fake)],
    );
    if (dispose) addTearDown(container.dispose);
    // ⚠️ **보는 사람을 하나 둔다.** provider가 auto-dispose라 아무도 안 보면
    // 첫 `await` 사이에 버려지고, 그 뒤 `read`는 빈 상태의 새 instance를 준다.
    // 실제 화면은 배지 때문에 늘 watch하고 있다.
    if (watch) {
      final watching = container.listen(chatProvider, (_, _) {});
      addTearDown(watching.close);
    }
    return (container: container, fake: fake);
  }

  ChatMessage arriving({bool isRead = false}) => ChatMessage(
    messageId: 'incoming-1',
    senderUserId: 'u1',
    kind: ChatMessageKind.text,
    sentAt: fixedNow(),
    text: '거의 다 왔어요',
    isRead: isRead,
  );

  group('붙는다', () {
    test('connect가 과거 메시지를 싣는다', () async {
      final chat = setUpChat();

      await chat.container.read(chatProvider.notifier).connect(seed);

      expect(chat.container.read(chatProvider).messages, isNotEmpty);
      expect(chat.container.read(chatProvider).failed, isFalse);
    });

    test('싣는 동안 loading이다', () async {
      final chat = setUpChat();

      final loading = chat.container.read(chatProvider.notifier).connect(seed);
      expect(chat.container.read(chatProvider).loading, isTrue);

      await loading;
      expect(chat.container.read(chatProvider).loading, isFalse);
    });

    test('⚠️ 파티원이 나 하나뿐이어도 붙는다', () async {
      // 버튼은 숨지만 provider는 붙어 있다.
      const alone = ChatRoomSeed(
        runningRoomId: 130,
        partyUserIds: ['me'],
        myUserId: 'me',
      );
      final chat = setUpChat();

      await chat.container.read(chatProvider.notifier).connect(alone);

      expect(chat.container.read(chatProvider).messages, isNotEmpty);
    });

    test('같은 방으로 다시 connect하면 다시 싣지 않는다', () async {
      final chat = setUpChat();
      final controller = chat.container.read(chatProvider.notifier);

      await controller.connect(seed);
      await controller.connect(seed);

      expect(chat.fake.historyCalls, 1);
    });

    test('⚠️ 방 번호가 바뀌면 전 방의 메시지를 버린다', () async {
      final chat = setUpChat();
      final controller = chat.container.read(chatProvider.notifier);

      await controller.connect(seed);
      final before = chat.container
          .read(chatProvider)
          .messages
          .map((m) => m.messageId)
          .toSet();
      await controller.connect(otherRoom);

      final after = chat.container.read(chatProvider).messages;
      expect(after, isNotEmpty);
      expect(after.where((m) => before.contains(m.messageId)), isEmpty);
    });

    test('⚠️ 아무도 보지 않으면 버려지고 구독이 끊긴다', () async {
      // ⚠️ **제품 경로의 유일한 뒷정리다.** 방 화면이 내려가면 이 provider를
      // 보는 사람이 없어지는데, auto-dispose가 아니면 `ref.onDispose`가 영영
      // 돌지 않는다 — 서버가 붙는 날 방이 끝나도 연결이 열려 있게 된다.
      final fake = FakeChatRepository(now: fixedNow);
      final container = ProviderContainer(
        overrides: [chatRepositoryProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      final watching = container.listen(chatProvider, (_, _) {});
      await container.read(chatProvider.notifier).connect(seed);
      expect(fake.hasListener, isTrue);

      watching.close();
      await Future<void>.delayed(Duration.zero);

      expect(fake.hasListener, isFalse);
    });

    test('⚠️ 보는 사람이 없는 동안 붙어도 터지지 않는다', () async {
      // 혼자인 방은 채팅 버튼이 숨어 **아무도 watch하지 않는다.** 그 사이에
      // `connect`가 끝나면 이미 버려진 provider에 상태를 쓰게 된다.
      const alone = ChatRoomSeed(
        runningRoomId: 130,
        partyUserIds: ['me'],
        myUserId: 'me',
      );
      final chat = setUpChat(watch: false);

      await chat.container.read(chatProvider.notifier).connect(alone);
    });

    test('⚠️ 앞 방의 응답이 늦게 와도 새 방에 섞이지 않는다', () async {
      // `history`가 네트워크가 되는 순간 방을 빠르게 옮기면 재현된다 —
      // 앞 방의 응답이 **새 방의 상태에** 써진다.
      final held = _HeldChat();
      final container = ProviderContainer(
        overrides: [chatRepositoryProvider.overrideWithValue(held)],
      );
      addTearDown(container.dispose);
      final watching = container.listen(chatProvider, (_, _) {});
      addTearDown(watching.close);

      final controller = container.read(chatProvider.notifier);
      // ⚠️ 한 틱 쉬어야 첫 요청이 `history`까지 간다 — `connect`는 구독 취소에서
      // 한 번 양보하므로, 연달아 부르면 둘 다 거기서 멎어 있다.
      final first = controller.connect(seed);
      await Future<void>.delayed(Duration.zero);
      final second = controller.connect(otherRoom);
      await Future<void>.delayed(Duration.zero);

      // 새 방이 먼저 답하고, 앞 방이 뒤늦게 답한다.
      held.answer(1, 'room131');
      await second;
      held.answer(0, 'room130');
      await first;

      final state = container.read(chatProvider);
      expect(state.seed!.runningRoomId, otherRoom.runningRoomId);
      expect(state.messages.map((m) => m.messageId), ['room131']);
    });

    test('⚠️ 앞 방의 실패가 새 방을 실패로 만들지 않는다', () async {
      final held = _HeldChat();
      final container = ProviderContainer(
        overrides: [chatRepositoryProvider.overrideWithValue(held)],
      );
      addTearDown(container.dispose);
      final watching = container.listen(chatProvider, (_, _) {});
      addTearDown(watching.close);

      final controller = container.read(chatProvider.notifier);
      // ⚠️ 한 틱 쉬어야 첫 요청이 `history`까지 간다 — `connect`는 구독 취소에서
      // 한 번 양보하므로, 연달아 부르면 둘 다 거기서 멎어 있다.
      final first = controller.connect(seed);
      await Future<void>.delayed(Duration.zero);
      final second = controller.connect(otherRoom);
      await Future<void>.delayed(Duration.zero);

      held.answer(1, 'room131');
      await second;
      held.fail(0);
      await first;

      expect(container.read(chatProvider).failed, isFalse);
    });

    test('⚠️ 구독은 provider를 손으로 버릴 때도 끊긴다', () async {
      final chat = setUpChat(dispose: false);

      await chat.container.read(chatProvider.notifier).connect(seed);
      expect(chat.fake.hasListener, isTrue);

      chat.container.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(chat.fake.hasListener, isFalse);
    });
  });

  group('안 읽은 수', () {
    test('⚠️ 버려진 뒤에 열거나 닫아도 터지지 않는다', () async {
      // 화면이 내려갈 때 `ChatPage.dispose`가 `close()`를 부른다. 그 순간
      // provider가 이미 버려져 있을 수 있다.
      final chat = setUpChat(watch: false);
      final controller = chat.container.read(chatProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      controller.close();
      controller.open();
    });

    test('⚠️ 안 읽은 수는 isRead가 아닌 것의 수다', () async {
      final chat = setUpChat();

      await chat.container.read(chatProvider.notifier).connect(seed);

      expect(chat.container.read(chatProvider).unread, 2);
    });

    test('열면 전부 읽은 것이 된다', () async {
      final chat = setUpChat();
      final controller = chat.container.read(chatProvider.notifier);

      await controller.connect(seed);
      controller.open();

      expect(chat.container.read(chatProvider).unread, 0);
    });

    test('⚠️ 열려 있는 동안 들어온 것은 세지 않는다', () async {
      // 보고 있는 말을 안 읽음으로 쌓으면 배지가 거짓말을 한다.
      final chat = setUpChat();
      final controller = chat.container.read(chatProvider.notifier);

      await controller.connect(seed);
      controller.open();
      chat.fake.emit(arriving());
      await Future<void>.delayed(Duration.zero);

      expect(chat.container.read(chatProvider).unread, 0);
    });

    test('닫은 뒤 들어온 것은 센다', () async {
      final chat = setUpChat();
      final controller = chat.container.read(chatProvider.notifier);

      await controller.connect(seed);
      controller.open();
      controller.close();
      chat.fake.emit(arriving());
      await Future<void>.delayed(Duration.zero);

      expect(chat.container.read(chatProvider).unread, 1);
    });
  });

  group('실패와 전송', () {
    test('history가 실패하면 failed다', () async {
      final chat = setUpChat(fails: true);

      await chat.container.read(chatProvider.notifier).connect(seed);

      final state = chat.container.read(chatProvider);
      expect(state.failed, isTrue);
      expect(state.loading, isFalse);
    });

    test('실패한 뒤 다시 connect하면 산다', () async {
      final chat = setUpChat(fails: true);
      final controller = chat.container.read(chatProvider.notifier);

      await controller.connect(seed);
      chat.fake.fails = false;
      await controller.connect(seed);

      final state = chat.container.read(chatProvider);
      expect(state.failed, isFalse);
      expect(state.messages, isNotEmpty);
    });

    test('⚠️ 공백·개행만 보내면 아무 일도 없다', () async {
      final chat = setUpChat();
      final controller = chat.container.read(chatProvider.notifier);

      await controller.connect(seed);
      final before = chat.container.read(chatProvider).messages.length;
      await controller.send('   \n ');
      await Future<void>.delayed(Duration.zero);

      expect(chat.container.read(chatProvider).messages.length, before);
      expect(chat.fake.sendCalls, 0);
    });
  });
}

/// `history`를 붙잡아 두는 대역. **경쟁 순서를 손으로 정하려면** 응답 시점을
/// 밖에서 쥐고 있어야 한다.
class _HeldChat implements ChatRepository {
  final _controller = StreamController<ChatMessage>.broadcast();
  final _held = <Completer<List<ChatMessage>>>[];

  @override
  Future<List<ChatMessage>> history(ChatRoomSeed seed) {
    final gate = Completer<List<ChatMessage>>();
    _held.add(gate);
    return gate.future;
  }

  @override
  Stream<ChatMessage> incoming(ChatRoomSeed seed) => _controller.stream;

  @override
  Future<void> send(ChatRoomSeed seed, String text) async {}

  void answer(int call, String messageId) => _held[call].complete([
    ChatMessage(
      messageId: messageId,
      senderUserId: 'u1',
      kind: ChatMessageKind.text,
      sentAt: DateTime(2026, 11, 4, 19, 18),
      text: '안녕하세요',
    ),
  ]);

  void fail(int call) => _held[call].completeError(const ChatException());
}
