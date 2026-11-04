import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/chat/data/fake_chat_repository.dart';
import 'package:runiverse/features/chat/domain/chat_message.dart';
import 'package:runiverse/features/chat/domain/chat_repository.dart';

/// 가짜 채팅 저장소. 서버가 없는 동안 화면이 기대는 **유일한 구현**이다.
///
/// ## ⚠️ 여기서 보는 것은 "그럴듯한 대화"가 아니다
///
/// 화면이 그릴 수 있는 **모양**을 본다. 발신자가 명단 안에 있어야 이름이 붙고,
/// 뒤쪽 두 개가 안 읽음이어야 배지에 숫자가 보이고, 실패할 수 있어야 error
/// 3분기를 한 번이라도 그려볼 수 있다.
void main() {
  DateTime fixedNow() => DateTime(2026, 11, 4, 19, 18);

  const seed = ChatRoomSeed(
    runningRoomId: 130,
    partyUserIds: ['me', 'u1', 'u2'],
    myUserId: 'me',
  );

  FakeChatRepository repo({bool fails = false}) =>
      FakeChatRepository(fails: fails, now: fixedNow);

  group('과거 메시지', () {
    test('열 개 안쪽을 시간 순으로 준다', () async {
      final messages = await repo().history(seed);

      expect(messages, isNotEmpty);
      expect(messages.length, lessThanOrEqualTo(10));
      for (var i = 1; i < messages.length; i++) {
        expect(
          messages[i].sentAt.isBefore(messages[i - 1].sentAt),
          isFalse,
          reason: '$i번째가 앞의 것보다 이르다',
        );
      }
    });

    test('⚠️ 뒤쪽 두 개만 안 읽음이다', () async {
      // 배지에 숫자가 처음부터 보이게 하는 자리다.
      final messages = await repo().history(seed);
      final unread = messages.where((m) => !m.isRead).toList();

      expect(unread.length, 2);
      expect(unread, [messages[messages.length - 2], messages.last]);
    });

    test('⚠️ 발신자가 전부 파티원이다', () async {
      // 명단 밖 id가 섞이면 화면이 전부 '탈퇴한 사용자'로 그린다.
      final messages = await repo().history(seed);

      expect(
        messages.every((m) => seed.partyUserIds.contains(m.senderUserId)),
        isTrue,
      );
    });

    test('입장 알림이 하나 있고 글이 없다', () async {
      final messages = await repo().history(seed);
      final joined = messages
          .where((m) => m.kind == ChatMessageKind.joined)
          .toList();

      expect(joined.length, 1);
      expect(joined.single.text, isNull);
    });

    test('글 메시지는 text가 비어 있지 않다', () async {
      final messages = await repo().history(seed);
      final texts = messages.where((m) => m.kind == ChatMessageKind.text);

      expect(texts, isNotEmpty);
      for (final message in texts) {
        expect(message.text, isNotNull);
        expect(message.text!.trim(), isNotEmpty);
      }
    });

    test('⚠️ 같은 seed와 같은 now면 결과가 같다', () async {
      // 그리는 순서가 흔들리면 안 된다 — 난수를 쓰면 여기서 깨진다.
      final once = await repo().history(seed);
      final twice = await repo().history(seed);

      expect(
        twice.map((m) => m.messageId).toList(),
        once.map((m) => m.messageId).toList(),
      );
    });

    test('⚠️ fails면 history가 ChatException을 던진다', () async {
      await expectLater(
        repo(fails: true).history(seed),
        throwsA(isA<ChatException>()),
      );
    });

    test('⚠️ 파티원이 나 하나뿐이어도 터지지 않는다', () async {
      const alone = ChatRoomSeed(
        runningRoomId: 130,
        partyUserIds: ['me'],
        myUserId: 'me',
      );

      expect(await repo().history(alone), isNotEmpty);
    });
  });

  group('전송', () {
    test('send가 보낸 것을 즉시 incoming으로 흘린다', () async {
      final fake = repo();
      final received = <ChatMessage>[];
      final subscription = fake.incoming(seed).listen(received.add);
      addTearDown(subscription.cancel);

      await fake.send(seed, '안녕');
      await Future<void>.delayed(Duration.zero);

      expect(received.single.text, '안녕');
    });

    test('send한 것은 읽은 것이다', () async {
      final fake = repo();
      final received = <ChatMessage>[];
      final subscription = fake.incoming(seed).listen(received.add);
      addTearDown(subscription.cancel);

      await fake.send(seed, '안녕');
      await Future<void>.delayed(Duration.zero);

      expect(received.single.isRead, isTrue);
      expect(received.single.senderUserId, 'me');
    });
  });

  test('부른 횟수와 구독 여부를 들여다볼 수 있다', () async {
    // Task 3의 테스트가 이것에 기댄다 — 같은 방에 두 번 붙지 않는지,
    // 공백 전송이 저장소까지 가지 않는지는 상태만으로 확인할 수 없다.
    final fake = repo();
    expect(fake.historyCalls, 0);
    expect(fake.sendCalls, 0);
    expect(fake.hasListener, isFalse);

    await fake.history(seed);
    expect(fake.historyCalls, 1);
    await fake.history(seed);
    expect(fake.historyCalls, 2);

    final subscription = fake.incoming(seed).listen((_) {});
    expect(fake.hasListener, isTrue);

    await fake.send(seed, '하나');
    expect(fake.sendCalls, 1);

    await subscription.cancel();
    expect(fake.hasListener, isFalse);
  });
}
