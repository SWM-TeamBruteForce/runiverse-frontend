import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/chat/domain/chat.dart';
import 'package:runiverse/features/chat/domain/chat_merge.dart';

/// 같은 `chatId`를 두 번 받았을 때 **어느 쪽을 남기는가.**
///
/// ## ⚠️ 받은 순서로 덮으면 안 된다
///
/// 목록 응답과 실시간 이벤트가 겹쳐 온다. 늦게 도착한 목록 응답으로 덮으면
/// **수정 전 내용이 되살아나고**, 먼저 도착한 전송 이벤트로 덮으면 **이미 지운
/// 메시지가 되살아난다.** 그래서 도착 순서가 아니라 규칙으로 고른다.
///
/// 규칙은 셋이고 순서가 있다(연동 가이드 2-2).
/// 1. 삭제 상태가 이긴다 — 한 번 지워진 것은 되살아나지 않는다
/// 2. 둘 다 안 지워졌으면 `editedAt`이 늦은 쪽. `null`은 가장 이른 것
/// 3. `editedAt`이 같으면 나중에 받은 쪽 — 초 단위라 같은 값이 온다
void main() {
  final createdAt = DateTime(2026, 11, 12, 19, 28);

  const sender = ChatSender(userId: 'u1', nickname: '영희');

  Chat chat({
    int chatId = 10,
    String? content = '곧 출발해요',
    bool isDeleted = false,
    DateTime? editedAt,
    bool isRead = true,
  }) => Chat(
    chatId: chatId,
    runningRoomId: 125,
    sender: sender,
    content: isDeleted ? null : content,
    isDeleted: isDeleted,
    editedAt: editedAt,
    createdAt: createdAt,
    isRead: isRead,
  );

  group('둘 중 하나를 고른다', () {
    test('⚠️ 1. 삭제가 이긴다 — 어느 쪽으로 왔든', () {
      // 늦게 도착한 전송 이벤트나 오래된 목록 응답이 지운 메시지를 되살리면
      // 지운 사람은 지웠다고 믿는 말이 남의 화면에 계속 보인다.
      final deleted = chat(isDeleted: true);
      final alive = chat(content: '곧 출발해요');

      expect(mergeChat(deleted, alive).isDeleted, isTrue);
      expect(mergeChat(alive, deleted).isDeleted, isTrue);
      // 내용은 비워서 그린다.
      expect(mergeChat(alive, deleted).content, isNull);
    });

    test('⚠️ 1. 삭제는 더 늦은 수정도 이긴다 — 규칙에 순서가 있다', () {
      // `editedAt`을 먼저 보면 "지운 뒤에 온 수정"이 삭제를 덮는다.
      final deleted = chat(isDeleted: true);
      final editedLater = chat(editedAt: DateTime(2026, 11, 12, 19, 40));

      expect(mergeChat(deleted, editedLater).isDeleted, isTrue);
      expect(mergeChat(editedLater, deleted).isDeleted, isTrue);
    });

    test('2. 둘 다 살아 있으면 editedAt이 늦은 쪽', () {
      final early = chat(
        content: '곧 출발',
        editedAt: DateTime(2026, 11, 12, 19, 30),
      );
      final late = chat(
        content: '조금 늦어요',
        editedAt: DateTime(2026, 11, 12, 19, 40),
      );

      expect(mergeChat(early, late).content, '조금 늦어요');
      expect(mergeChat(late, early).content, '조금 늦어요');
    });

    test('⚠️ 2. editedAt이 null이면 가장 이른 것으로 본다', () {
      // 목록 응답이 늦게 도착해도 수정 전 내용으로 돌아가지 않는다.
      final never = chat(content: '곧 출발');
      final edited = chat(
        content: '조금 늦어요',
        editedAt: DateTime(2026, 11, 12, 19, 40),
      );

      expect(mergeChat(never, edited).content, '조금 늦어요');
      expect(mergeChat(edited, never).content, '조금 늦어요');
    });

    test('3. editedAt이 같으면 나중에 받은 쪽', () {
      // `editedAt`은 초 단위다. 같은 초에 두 번 고치면 같은 값이 온다 —
      // 그때는 수신 순서에 의존한다(가이드가 그렇게 정했다).
      final at = DateTime(2026, 11, 12, 19, 40);
      final first = chat(content: '첫 수정', editedAt: at);
      final second = chat(content: '두 번째 수정', editedAt: at);

      expect(mergeChat(first, second).content, '두 번째 수정');
    });

    test('3. 둘 다 고친 적 없으면 나중에 받은 쪽', () {
      final kept = chat(content: '예전에 받은 것');
      final arrived = chat(content: '방금 받은 것');

      expect(mergeChat(kept, arrived).content, '방금 받은 것');
    });

    test('⚠️ 읽음은 서버가 모르는 값이다 — 한 번 읽으면 되돌아가지 않는다', () {
      // 수정 이벤트가 **안 읽음으로** 들어온다고 이미 읽은 말이 다시 배지에
      // 세어지면, 보고 있는 화면에서 숫자가 늘어난다.
      final read = chat(isRead: true);
      final unread = chat(
        content: '고친 내용',
        isRead: false,
        editedAt: DateTime(2026, 11, 12, 19, 40),
      );

      expect(mergeChat(read, unread).isRead, isTrue);
      expect(mergeChat(read, unread).content, '고친 내용');
    });

    test('아직 안 읽은 것에 수정이 오면 여전히 안 읽음이다', () {
      final unread = chat(isRead: false);
      final edited = chat(
        content: '고친 내용',
        isRead: false,
        editedAt: DateTime(2026, 11, 12, 19, 40),
      );

      expect(mergeChat(unread, edited).isRead, isFalse);
    });
  });

  group('목록에 합친다', () {
    test('없는 chatId는 새로 넣는다', () {
      final merged = mergeChats([chat(chatId: 10)], [chat(chatId: 11)]);

      expect(merged.map((one) => one.chatId), [10, 11]);
    });

    test('⚠️ chatId 오름차순을 지킨다 — 받은 순서가 아니다', () {
      // 생성 순서대로 커지는 값이라 이것이 곧 시간 순이다. 이벤트가 목록보다
      // 먼저 와도 자리가 흔들리지 않는다.
      final merged = mergeChats(
        [chat(chatId: 20)],
        [chat(chatId: 11), chat(chatId: 30), chat(chatId: 15)],
      );

      expect(merged.map((one) => one.chatId), [11, 15, 20, 30]);
    });

    test('같은 chatId는 규칙으로 합친다', () {
      final merged = mergeChats(
        [chat(chatId: 10, content: '곧 출발'), chat(chatId: 11)],
        [chat(chatId: 10, isDeleted: true)],
      );

      expect(merged, hasLength(2));
      expect(merged.first.isDeleted, isTrue);
    });

    test('⚠️ 수정해도 자리가 바뀌지 않는다', () {
      // 고친 메시지가 맨 아래로 내려가면 대화의 맥락이 끊긴다.
      final merged = mergeChats(
        [chat(chatId: 10), chat(chatId: 11), chat(chatId: 12)],
        [
          chat(
            chatId: 10,
            content: '고쳤다',
            editedAt: DateTime(2026, 11, 12, 20),
          ),
        ],
      );

      expect(merged.map((one) => one.chatId), [10, 11, 12]);
      expect(merged.first.content, '고쳤다');
    });

    test('한 번에 들어온 같은 chatId도 규칙으로 합친다', () {
      // 목록과 이벤트를 한 묶음으로 넘길 때가 있다.
      final merged = mergeChats(const [], [
        chat(chatId: 10),
        chat(chatId: 10, isDeleted: true),
      ]);

      expect(merged, hasLength(1));
      expect(merged.single.isDeleted, isTrue);
    });

    test('빈 입력은 원본을 그대로 둔다', () {
      final current = [chat(chatId: 10)];

      expect(mergeChats(current, const []).map((one) => one.chatId), [10]);
    });
  });

  group('무엇을 표시할지 Chat이 안다', () {
    test('수정됨은 살아 있고 editedAt이 있을 때만', () {
      expect(chat().isEdited, isFalse);
      expect(chat(editedAt: DateTime(2026, 11, 12, 20)).isEdited, isTrue);
    });

    test('⚠️ 지운 메시지에는 수정됨을 붙이지 않는다', () {
      // 삭제 상태가 우선이다. 둘을 함께 그리면 "삭제된 메시지 (수정됨)"이 된다.
      final deleted = Chat(
        chatId: 10,
        runningRoomId: 125,
        sender: sender,
        isDeleted: true,
        editedAt: DateTime(2026, 11, 12, 20),
        createdAt: createdAt,
      );

      expect(deleted.isEdited, isFalse);
    });
  });
}
