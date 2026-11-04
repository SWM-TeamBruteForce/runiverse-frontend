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
  }) {
    final fake = FakeChatRepository(fails: fails, now: fixedNow);
    final container = ProviderContainer(
      overrides: [chatRepositoryProvider.overrideWithValue(fake)],
    );
    if (dispose) addTearDown(container.dispose);
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

    test('⚠️ 구독은 provider가 버려질 때 끊긴다', () async {
      final chat = setUpChat(dispose: false);

      await chat.container.read(chatProvider.notifier).connect(seed);
      expect(chat.fake.hasListener, isTrue);

      chat.container.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(chat.fake.hasListener, isFalse);
    });
  });

  group('안 읽은 수', () {
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
