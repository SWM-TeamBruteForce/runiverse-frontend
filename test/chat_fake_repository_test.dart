import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/chat/data/fake_chat_repository.dart';
import 'package:runiverse/features/chat/domain/chat_failure.dart';

/// 가짜 저장소 — **화면을 서버 없이 세워 두는 것이 일이다.**
///
/// 여기서 거짓말을 하면 화면 테스트가 전부 거짓이 된다. 특히 `chatId`가
/// 생성 순서대로 커지는 것, 지운 메시지가 자리를 지키는 것, 수정이 다음
/// 조회에 보이는 것은 **서버 계약이라 가짜도 지켜야 한다.**
void main() {
  DateTime fixedNow() => DateTime(2026, 11, 12, 19, 18);

  FakeChatRepository fake({bool fails = false}) =>
      FakeChatRepository(fails: fails, now: fixedNow);

  group('지난 대화', () {
    test('한 번에 다 주고 커서를 남기지 않는다', () async {
      final repo = fake();

      final page = await repo.history(130, limit: 50);

      expect(page.items, isNotEmpty);
      expect(page.nextCursor, isNull);
    });

    test('⚠️ chatId가 생성 순서대로 커진다 — 화면이 이것으로 정렬한다', () async {
      final repo = fake();

      final page = await repo.history(130, limit: 50);
      // 서버는 최신순으로 준다.
      final ids = page.items.map((one) => one.chatId).toList();

      expect(ids, [...ids]..sort((a, b) => b.compareTo(a)));
    });

    test('⚠️ 내 말이 섞여 있다 — 수정·삭제 자리를 볼 수 있어야 한다', () async {
      // 전부 남의 말이면 수정·삭제 버튼이 한 번도 안 보여서, 그 자리를 눈으로
      // 확인할 수 없다.
      final repo = FakeChatRepository(myUserId: 'me', now: fixedNow);

      final page = await repo.history(130, limit: 50);

      expect(page.items.any((one) => one.sender.userId == 'me'), isTrue);
      expect(page.items.any((one) => one.sender.userId != 'me'), isTrue);
    });

    test('⚠️ 방마다 따로 들고 있다', () async {
      // 한 통에 담으면 방을 옮겨도 전 방의 말이 남아 있는 것처럼 보인다.
      final repo = fake();
      await repo.send(130, '130번 방의 말');

      final other = await repo.history(131, limit: 50);

      expect(other.items.any((one) => one.content == '130번 방의 말'), isFalse);
      expect(other.items.every((one) => one.runningRoomId == 131), isTrue);
    });

    test('limit만큼만 주고 남으면 커서를 준다', () async {
      final repo = fake();

      final first = await repo.history(130, limit: 2);

      expect(first.items, hasLength(2));
      expect(first.nextCursor, isNotNull);
    });

    test('커서로 이어 받으면 더 이전 것이 온다', () async {
      final repo = fake();
      final first = await repo.history(130, limit: 2);

      final second = await repo.history(
        130,
        cursor: first.nextCursor,
        limit: 2,
      );

      final firstIds = first.items.map((one) => one.chatId).toSet();
      final secondIds = second.items.map((one) => one.chatId).toSet();
      expect(firstIds.intersection(secondIds), isEmpty);
      expect(secondIds.every((id) => id < firstIds.reduce((a, b) => a < b ? a : b)), isTrue);
    });

    test('끝까지 받으면 커서가 사라진다', () async {
      final repo = fake();

      var cursor = (await repo.history(130, limit: 2)).nextCursor;
      var guard = 0;
      while (cursor != null && guard++ < 10) {
        cursor = (await repo.history(130, cursor: cursor, limit: 2)).nextCursor;
      }

      expect(cursor, isNull);
      expect(guard, lessThan(10), reason: '끝이 있어야 한다');
    });

    test('몇 번 불렸는지 센다', () async {
      final repo = fake();

      await repo.history(130, limit: 50);
      await repo.history(130, limit: 50);

      expect(repo.historyCalls, 2);
    });
  });

  group('보내기', () {
    test('보낸 것이 다음 조회에 보인다', () async {
      final repo = fake();
      await repo.history(130, limit: 50);

      final sent = await repo.send(130, '곧 나갈게요');
      final page = await repo.history(130, limit: 50);

      expect(sent.content, '곧 나갈게요');
      expect(page.items.any((one) => one.chatId == sent.chatId), isTrue);
    });

    test('⚠️ 새 chatId가 기존 것보다 크다', () async {
      final repo = fake();
      final before = await repo.history(130, limit: 50);
      final largest = before.items
          .map((one) => one.chatId)
          .reduce((a, b) => a > b ? a : b);

      final sent = await repo.send(130, '곧 나갈게요');

      expect(sent.chatId, greaterThan(largest));
    });

    test('⚠️ 보낸 것은 고친 적이 없다', () async {
      final repo = fake();

      final sent = await repo.send(130, '곧 나갈게요');

      expect(sent.editedAt, isNull);
      expect(sent.isEdited, isFalse);
      expect(sent.isDeleted, isFalse);
    });
  });

  group('수정', () {
    test('내용이 바뀌고 editedAt이 채워진다', () async {
      final repo = fake();
      final sent = await repo.send(130, '곧 나갈게요');

      final edited = await repo.edit(130, chatId: sent.chatId, content: '조금 늦어요');

      expect(edited.content, '조금 늦어요');
      expect(edited.editedAt, isNotNull);
      expect(edited.isEdited, isTrue);
      // 자리를 가르는 값은 그대로다.
      expect(edited.chatId, sent.chatId);
      expect(edited.createdAt, sent.createdAt);
    });

    test('고친 것이 다음 조회에 보인다', () async {
      final repo = fake();
      final sent = await repo.send(130, '곧 나갈게요');
      await repo.edit(130, chatId: sent.chatId, content: '조금 늦어요');

      final page = await repo.history(130, limit: 50);

      expect(
        page.items.firstWhere((one) => one.chatId == sent.chatId).content,
        '조금 늦어요',
      );
    });

    test('없는 메시지는 404다', () async {
      final repo = fake();

      await expectLater(
        repo.edit(130, chatId: 999999, content: '고쳤어요'),
        throwsA(
          isA<ChatException>().having(
            (error) => error.failure,
            'failure',
            ChatFailure.notFound,
          ),
        ),
      );
    });
  });

  group('삭제', () {
    test('⚠️ 자리를 지키고 내용만 비운다', () async {
      final repo = fake();
      final sent = await repo.send(130, '곧 나갈게요');
      final before = (await repo.history(130, limit: 50)).items.length;

      await repo.delete(130, sent.chatId);
      final page = await repo.history(130, limit: 50);

      expect(page.items, hasLength(before));
      final deleted = page.items.firstWhere((one) => one.chatId == sent.chatId);
      expect(deleted.isDeleted, isTrue);
      expect(deleted.content, isNull);
    });

    test('⚠️ 이미 지운 것은 다시 지우거나 고칠 수 없다 — 404다', () async {
      final repo = fake();
      final sent = await repo.send(130, '곧 나갈게요');
      await repo.delete(130, sent.chatId);

      await expectLater(
        repo.delete(130, sent.chatId),
        throwsA(isA<ChatException>()),
      );
      await expectLater(
        repo.edit(130, chatId: sent.chatId, content: '고쳤어요'),
        throwsA(isA<ChatException>()),
      );
    });
  });

  group('실패를 만들 수 있다', () {
    test('fails면 모든 길이 던진다', () async {
      final repo = fake(fails: true);

      await expectLater(repo.history(130, limit: 50), throwsA(isA<ChatException>()));
      await expectLater(repo.send(130, '어'), throwsA(isA<ChatException>()));
    });

    test('⚠️ 어느 갈래인지 고를 수 있다 — 409와 404는 할 일이 다르다', () async {
      final repo = FakeChatRepository(
        fails: true,
        failure: ChatFailure.closed,
        now: fixedNow,
      );

      await expectLater(
        repo.history(130, limit: 50),
        throwsA(
          isA<ChatException>().having(
            (error) => error.failure,
            'failure',
            ChatFailure.closed,
          ),
        ),
      );
    });

    test('실패를 끄면 다시 산다', () async {
      final repo = fake(fails: true);
      await expectLater(repo.history(130, limit: 50), throwsA(isA<ChatException>()));

      repo.fails = false;

      expect((await repo.history(130, limit: 50)).items, isNotEmpty);
    });
  });
}
