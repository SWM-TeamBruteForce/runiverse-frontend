import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/utils/kst_time.dart';
import 'package:runiverse/core/widgets/v2/party_chip.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/chat/domain/chat.dart';
import 'package:runiverse/features/chat/domain/chat_failure.dart';
import 'package:runiverse/features/chat/presentation/chat_page.dart';
import 'package:runiverse/features/chat/presentation/chat_provider.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';
import 'package:runiverse/features/matching/presentation/match_room_provider.dart';

/// 채팅 페이지 (대기방 자식 라우트).
///
/// ## ⚠️ 이름과 사진은 메시지가 들고 온다
///
/// 서버가 메시지마다 보낸 사람을 실어 준다. 방 명단에서 찾지 않는다 — 방을
/// 떠난 사람의 지난 메시지가 전부 '탈퇴한 사용자'로 그려지기 때문이다. 명단이
/// 정하는 것은 **색**뿐이다.
void main() {
  final startAt = KstTime.toLocal(DateTime(2026, 11, 4, 19, 30));
  final createdAt = KstTime.toLocal(DateTime(2026, 11, 4, 19, 28));

  const me = ChatSender(userId: 'me', nickname: '나');
  const younghee = ChatSender(userId: 'u1', nickname: '영희');
  const withdrawn = ChatSender(
    userId: 'u9',
    nickname: '탈퇴한 사용자',
    isDeleted: true,
  );

  final room = RoomInfo(
    runningRoomId: 130,
    status: RoomStatus.matched,
    scheduledStartAt: startAt,
    targetDistanceMeters: 5000,
    players: const [
      RoomPlayer(userId: 'me', nickname: '나', isDeleted: false),
      RoomPlayer(userId: 'u1', nickname: '영희', isDeleted: false),
      RoomPlayer(userId: 'u2', nickname: '철수', isDeleted: false),
      RoomPlayer(userId: 'u3', nickname: '민수', isDeleted: false),
    ],
  );

  Chat chat(
    int chatId,
    ChatSender sender, {
    String? content = '안녕하세요',
    bool isDeleted = false,
    DateTime? editedAt,
  }) => Chat(
    chatId: chatId,
    runningRoomId: 130,
    sender: sender,
    content: isDeleted ? null : content,
    isDeleted: isDeleted,
    editedAt: editedAt,
    createdAt: createdAt,
  );

  final conversation = [
    chat(1001, younghee, content: '안녕하세요, 오늘 잘 부탁드려요'),
    chat(1002, me, content: '저도 반가워요'),
  ];

  Future<_StubChat> pumpChat(
    WidgetTester tester, {
    ChatState state = const ChatState(runningRoomId: 130),
    Completer<void>? gate,
    bool light = false,
  }) async {
    final chatStub = _StubChat(state, gate: gate);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatProvider.overrideWith(() => chatStub),
          matchRoomProvider.overrideWith(
            () => _StubRoom(MatchRoomState(room: room, connected: true)),
          ),
          authControllerProvider.overrideWith(
            () => _StubAuth(const AuthSignedIn('me', isOnboarded: true)),
          ),
        ],
        child: MaterialApp(
          theme: light ? AppTheme.light() : AppTheme.dark(),
          home: const ChatPage(),
        ),
      ),
    );
    await tester.pump();
    return chatStub;
  }

  group('세 분기와 empty', () {
    testWidgets('싣는 동안 인디케이터가 뜬다', (tester) async {
      await pumpChat(
        tester,
        state: const ChatState(runningRoomId: 130, loading: true),
      );

      expect(find.byType(CircularProgressIndicator), findsOne);
    });

    testWidgets('실패하면 다시 시도가 뜬다', (tester) async {
      await pumpChat(
        tester,
        state: const ChatState(
          runningRoomId: 130,
          failure: ChatFailure.network,
        ),
      );

      expect(find.text(AppStrings.chatRetry), findsOne);
    });

    testWidgets('메시지가 없으면 안내와 칩이 함께 보인다', (tester) async {
      // ⚠️ empty에서도 칩과 입력창은 보인다 — 먼저 말을 걸 수 있어야 한다.
      await pumpChat(tester);

      expect(find.text(AppStrings.chatEmpty), findsOne);
      expect(find.text(AppStrings.chatQuickReplies.first), findsOne);
    });

    testWidgets('⚠️ 닫혔으면 입력창이 사라지고 안내가 남는다', (tester) async {
      // 러닝이 시작됐다. 되돌아오지 않는 상태라 "다시 시도"도 띄우지 않는다.
      await pumpChat(
        tester,
        state: ChatState(
          runningRoomId: 130,
          closed: true,
          messages: conversation,
        ),
      );

      expect(find.text(AppStrings.chatClosed), findsOne);
      expect(find.byType(TextField), findsNothing);
      expect(find.text(AppStrings.chatRetry), findsNothing);
    });
  });

  group('무엇을 그리는가', () {
    testWidgets('제목이 두 줄이다', (tester) async {
      await pumpChat(
        tester,
        state: ChatState(runningRoomId: 130, messages: conversation),
      );

      expect(find.text('19:30 - 5 km 러닝'), findsOne);
      expect(find.text('영희님 외 2명'), findsOne);
    });

    testWidgets('내 메시지에는 닉네임이 없다', (tester) async {
      await pumpChat(
        tester,
        state: ChatState(runningRoomId: 130, messages: conversation),
      );

      expect(find.text('저도 반가워요'), findsOne);
      expect(find.text('나'), findsNothing);
    });

    testWidgets('남의 메시지에 닉네임과 사진이 붙는다', (tester) async {
      await pumpChat(
        tester,
        state: ChatState(runningRoomId: 130, messages: conversation),
      );

      expect(find.text('안녕하세요, 오늘 잘 부탁드려요'), findsOne);
      expect(find.text('영희'), findsOne);
      expect(find.byType(PartyChip), findsOne);
    });

    testWidgets('⚠️ 이름은 메시지가 들고 온 것을 쓴다', (tester) async {
      // 방 명단에서 찾으면 방을 떠난 사람의 지난 말이 전부 탈퇴 표기가 된다.
      // 명단에 없는 `u9`인데도 서버가 준 이름이 그려져야 한다.
      await pumpChat(
        tester,
        state: ChatState(
          runningRoomId: 130,
          messages: [chat(1003, withdrawn, content: '다녀왔습니다')],
        ),
      );

      expect(find.text('탈퇴한 사용자'), findsOne);
      expect(find.text('다녀왔습니다'), findsOne);
    });

    testWidgets('⚠️ 지운 메시지는 자리를 지키고 문구만 바뀐다', (tester) async {
      // 빼면 그 자리에서 대화가 끊겨 보인다.
      await pumpChat(
        tester,
        state: ChatState(
          runningRoomId: 130,
          messages: [
            chat(1001, younghee, content: '첫 말'),
            chat(1002, younghee, isDeleted: true),
            chat(1003, younghee, content: '끝 말'),
          ],
        ),
      );

      expect(find.text(AppStrings.chatDeleted), findsOne);
      expect(find.text('첫 말'), findsOne);
      expect(find.text('끝 말'), findsOne);
    });

    testWidgets('고친 메시지에 수정됨이 붙는다', (tester) async {
      await pumpChat(
        tester,
        state: ChatState(
          runningRoomId: 130,
          messages: [
            chat(1001, younghee, content: '조금 늦어요', editedAt: createdAt),
          ],
        ),
      );

      expect(find.text(AppStrings.chatEdited), findsOne);
    });

    testWidgets('⚠️ 지운 메시지에는 수정됨을 붙이지 않는다', (tester) async {
      // 삭제 상태가 우선이다. 둘을 함께 그리면 "삭제된 메시지 (수정됨)"이 된다.
      await pumpChat(
        tester,
        state: ChatState(
          runningRoomId: 130,
          messages: [
            chat(1001, younghee, isDeleted: true, editedAt: createdAt),
          ],
        ),
      );

      expect(find.text(AppStrings.chatDeleted), findsOne);
      expect(find.text(AppStrings.chatEdited), findsNothing);
    });

    testWidgets('⚠️ 아주 긴 한 줄도 넘치지 않는다', (tester) async {
      // 제목을 두 줄로 나눈 이유가 이것이고, 버블은 줄바꿈으로 받아야 한다.
      final long = '가나다라마바사' * 43;

      for (final light in [false, true]) {
        await pumpChat(
          tester,
          light: light,
          state: ChatState(
            runningRoomId: 130,
            messages: [chat(1008, younghee, content: long)],
          ),
        );

        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('⚠️ 비속어는 가려서 그린다', (tester) async {
      // ## 왜 보내는 쪽이 아니라 그리는 쪽인가
      //
      // 보내는 쪽에서 막으면 **클라이언트를 고친 사람에게 효력이 없다.** 그리는
      // 쪽에서 가리면 상대가 무슨 앱을 쓰든 **보는 사람이** 보호된다.
      await pumpChat(
        tester,
        state: ChatState(
          runningRoomId: 130,
          messages: [chat(1009, younghee, content: '시발 늦었네')],
        ),
      );

      expect(find.text('시발 늦었네'), findsNothing);
      expect(find.text('** 늦었네'), findsOne);
    });

    testWidgets('⚠️ 정상인 말은 한 글자도 안 바꾼다', (tester) async {
      // 오탐이 미탐보다 나쁘다. '시간'·'출발'이 가려지면 기능을 못 쓴다.
      await pumpChat(
        tester,
        state: ChatState(
          runningRoomId: 130,
          messages: [chat(1010, younghee, content: '시간 맞춰 출발해요')],
        ),
      );

      expect(find.text('시간 맞춰 출발해요'), findsOne);
    });
  });

  group('보내지 못한 말', () {
    testWidgets('⚠️ 실패하면 다시 보내기와 지우기가 함께 뜬다', (tester) async {
      // 성공한 모양으로 두면 사람은 전해졌다고 믿고 방을 떠난다. 버릴 길이
      // 없으면 실패한 말풍선이 방을 떠날 때까지 남는다.
      await pumpChat(
        tester,
        state: const ChatState(
          runningRoomId: 130,
          pending: [PendingChat(localId: -1, content: '곧 나갈게요', failed: true)],
        ),
      );

      expect(find.text('곧 나갈게요'), findsOne);
      expect(find.text(AppStrings.chatSendFailed), findsOne);
      expect(find.text(AppStrings.chatResend), findsOne);
      expect(find.text(AppStrings.chatDiscard), findsOne);
    });

    testWidgets('보내는 중에는 다시 보내기가 없다', (tester) async {
      await pumpChat(
        tester,
        state: const ChatState(
          runningRoomId: 130,
          pending: [PendingChat(localId: -1, content: '곧 나갈게요')],
        ),
      );

      expect(find.text('곧 나갈게요'), findsOne);
      expect(find.text(AppStrings.chatResend), findsNothing);
    });

    testWidgets('다시 보내기를 누르면 그 한 건이 넘어간다', (tester) async {
      final stub = await pumpChat(
        tester,
        state: const ChatState(
          runningRoomId: 130,
          pending: [PendingChat(localId: -1, content: '곧 나갈게요', failed: true)],
        ),
      );

      await tester.tap(find.text(AppStrings.chatResend));
      await tester.pump();

      expect(stub.resent.single.content, '곧 나갈게요');
    });

    testWidgets('⚠️ 보내지 못한 말도 비속어를 가린다', (tester) async {
      // 내가 쓴 말이라도 화면에 그려지는 것은 같은 규칙을 따른다.
      await pumpChat(
        tester,
        state: const ChatState(
          runningRoomId: 130,
          pending: [PendingChat(localId: -1, content: '시발', failed: true)],
        ),
      );

      expect(find.text('시발'), findsNothing);
    });
  });

  group('내 말 고치고 지우기', () {
    testWidgets('⚠️ 남의 말에는 메뉴가 열리지 않는다', (tester) async {
      // 서버가 404로 막지만, 누를 수 있게 두면 안 되는 것을 눌러 보게 된다.
      await pumpChat(
        tester,
        state: ChatState(
          runningRoomId: 130,
          messages: [chat(1001, younghee, content: '남의 말')],
        ),
      );

      await tester.longPress(find.text('남의 말'));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.chatEditAction), findsNothing);
    });

    testWidgets('⚠️ 지운 내 말에도 메뉴가 열리지 않는다', (tester) async {
      // 이미 지운 것은 다시 고치거나 지울 수 없다 — 서버가 404다.
      await pumpChat(
        tester,
        state: ChatState(
          runningRoomId: 130,
          messages: [chat(1002, me, isDeleted: true)],
        ),
      );

      await tester.longPress(find.text(AppStrings.chatDeleted));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.chatEditAction), findsNothing);
    });

    testWidgets('내 말을 길게 누르면 수정·삭제가 나온다', (tester) async {
      await pumpChat(
        tester,
        state: ChatState(
          runningRoomId: 130,
          messages: [chat(1002, me, content: '내 말')],
        ),
      );

      await tester.longPress(find.text('내 말'));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.chatEditAction), findsOne);
      expect(find.text(AppStrings.chatDeleteAction), findsOne);
    });

    testWidgets('수정을 고르면 입력창에 그 내용이 들어온다', (tester) async {
      await pumpChat(
        tester,
        state: ChatState(
          runningRoomId: 130,
          messages: [chat(1002, me, content: '내 말')],
        ),
      );

      await tester.longPress(find.text('내 말'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.chatEditAction));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.chatEditing), findsOne);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '내 말',
      );
      // ⚠️ 수정 중에는 칩을 감춘다 — 누르면 고치던 내용이 날아간다.
      expect(find.text(AppStrings.chatQuickReplies.first), findsNothing);
    });

    testWidgets('수정하고 보내면 고치기로 넘어간다', (tester) async {
      final stub = await pumpChat(
        tester,
        state: ChatState(
          runningRoomId: 130,
          messages: [chat(1002, me, content: '내 말')],
        ),
      );

      await tester.longPress(find.text('내 말'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.chatEditAction));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '고친 말');
      await tester.tap(find.byKey(ChatPage.sendKey));
      await tester.pumpAndSettle();

      expect(stub.edited, [(1002, '고친 말')]);
      expect(stub.sent, isEmpty, reason: '보내기가 아니라 고치기다');
    });

    testWidgets('수정을 취소하면 입력창이 비워진다', (tester) async {
      await pumpChat(
        tester,
        state: ChatState(
          runningRoomId: 130,
          messages: [chat(1002, me, content: '내 말')],
        ),
      );

      await tester.longPress(find.text('내 말'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.chatEditAction));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.chatEditCancel));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(find.text(AppStrings.chatQuickReplies.first), findsOne);
    });

    testWidgets('⚠️ 삭제는 되돌릴 수 없어서 묻는다', (tester) async {
      final stub = await pumpChat(
        tester,
        state: ChatState(
          runningRoomId: 130,
          messages: [chat(1002, me, content: '내 말')],
        ),
      );

      await tester.longPress(find.text('내 말'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.chatDeleteAction));
      await tester.pumpAndSettle();

      // 아직 지우지 않았다.
      expect(find.text(AppStrings.chatDeleteConfirmTitle), findsOne);
      expect(stub.removed, isEmpty);

      await tester.tap(find.text(AppStrings.chatDeleteAction).last);
      await tester.pumpAndSettle();

      expect(stub.removed, [1002]);
    });

    testWidgets('확인에서 취소하면 지우지 않는다', (tester) async {
      final stub = await pumpChat(
        tester,
        state: ChatState(
          runningRoomId: 130,
          messages: [chat(1002, me, content: '내 말')],
        ),
      );

      await tester.longPress(find.text('내 말'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.chatDeleteAction));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.chatEditCancel));
      await tester.pumpAndSettle();

      expect(stub.removed, isEmpty);
    });
  });

  group('열고 닫기', () {
    testWidgets('⚠️ 뜨면 열고, 내려가면 닫는다', (tester) async {
      // 이 호출이 사라지면 **보고 있는 말이 안 읽음으로 쌓인다.** 대역이
      // 빈 몸으로 덮고 있어 상태로는 확인할 수 없어서 횟수를 센다.
      final stub = await pumpChat(tester);

      expect(stub.opens, 1);
      expect(stub.closes, 0);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      expect(stub.closes, 1);
    });
  });

  group('보내기', () {
    testWidgets('칩을 누르면 바로 보내진다', (tester) async {
      final stub = await pumpChat(tester);

      await tester.tap(find.text(AppStrings.chatQuickReplies.first));
      await tester.pump();

      expect(stub.sent, [AppStrings.chatQuickReplies.first]);
    });

    testWidgets('⚠️ 칩을 눌러도 쓰던 글은 남는다', (tester) async {
      // 칩 문구는 입력칸에서 온 것이 아니다. 비우면 **사람이 쓰던 글을 지운다.**
      final stub = await pumpChat(tester);

      await tester.enterText(find.byType(TextField), '쓰던 글');
      await tester.pump();
      await tester.tap(find.text(AppStrings.chatQuickReplies.first));
      await tester.pumpAndSettle();

      expect(stub.sent, [AppStrings.chatQuickReplies.first]);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '쓰던 글',
      );
    });

    testWidgets('⚠️ 보내는 동안 칩이 잠긴다', (tester) async {
      // 안 잠그면 같은 말이 다섯 번 도배된다.
      final gate = Completer<void>();
      final stub = await pumpChat(tester, gate: gate);

      await tester.tap(find.text(AppStrings.chatQuickReplies.first));
      await tester.pump();
      await tester.tap(find.text(AppStrings.chatQuickReplies[1]));
      await tester.pump();

      expect(stub.sent, [AppStrings.chatQuickReplies.first]);

      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('공백만 있으면 전송이 비활성이다', (tester) async {
      final stub = await pumpChat(tester);

      await tester.enterText(find.byType(TextField), '   \n ');
      await tester.pump();
      await tester.tap(find.byKey(ChatPage.sendKey), warnIfMissed: false);
      await tester.pump();

      expect(stub.sent, isEmpty);
    });

    testWidgets('⚠️ 200자를 넘기면 전송이 잠기고 까닭이 보인다', (tester) async {
      // 서버가 받는 길이다. `maxLength`로 끊으면 붙여넣은 글이 조용히 잘린다 —
      // 넘겨 쓸 수는 있게 두고 보내기만 잠근다.
      final stub = await pumpChat(tester);

      await tester.enterText(find.byType(TextField), '가' * 201);
      await tester.pump();

      expect(find.text(AppStrings.chatTooLong), findsOne);

      await tester.tap(find.byKey(ChatPage.sendKey), warnIfMissed: false);
      await tester.pump();

      expect(stub.sent, isEmpty);
    });

    testWidgets('200자까지는 보내진다', (tester) async {
      final stub = await pumpChat(tester);

      await tester.enterText(find.byType(TextField), '가' * 200);
      await tester.pump();
      await tester.tap(find.byKey(ChatPage.sendKey));
      await tester.pumpAndSettle();

      expect(stub.sent, hasLength(1));
      expect(find.text(AppStrings.chatTooLong), findsNothing);
    });

    testWidgets('보낸 뒤 입력칸이 비워진다', (tester) async {
      final stub = await pumpChat(tester);

      await tester.enterText(find.byType(TextField), '곧 나갈게요');
      await tester.pump();
      await tester.tap(find.byKey(ChatPage.sendKey));
      await tester.pumpAndSettle();

      expect(stub.sent, ['곧 나갈게요']);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    });
  });
}

/// 상태를 그대로 물려주는 대역. `build`를 덮으므로 저장소를 읽지 않는다.
class _StubChat extends ChatController {
  _StubChat(this.initial, {this.gate});

  final ChatState initial;

  /// 전송을 붙잡아 둔다. "보내는 동안"을 눈으로 볼 유일한 방법이다.
  final Completer<void>? gate;

  final sent = <String>[];
  final edited = <(int, String)>[];
  final removed = <int>[];
  final resent = <PendingChat>[];
  final discarded = <PendingChat>[];

  var opens = 0;
  var closes = 0;

  @override
  ChatState build() => initial;

  @override
  void open() => opens++;

  @override
  void close() => closes++;

  @override
  Future<void> send(String text) async {
    sent.add(text);
    final waiting = gate;
    if (waiting != null) await waiting.future;
  }

  @override
  Future<void> edit(int chatId, String text) async =>
      edited.add((chatId, text));

  @override
  Future<void> remove(int chatId) async => removed.add(chatId);

  @override
  Future<void> resend(PendingChat pending) async => resent.add(pending);

  @override
  void discard(PendingChat pending) => discarded.add(pending);

  @override
  Future<void> loadMore() async {}
}

class _StubRoom extends MatchRoomController {
  _StubRoom(this.initial);

  final MatchRoomState initial;

  @override
  MatchRoomState build() => initial;
}

class _StubAuth extends AuthController {
  _StubAuth(this.initial);

  final AuthState initial;

  @override
  AuthState build() => initial;
}
