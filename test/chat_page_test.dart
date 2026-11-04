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
import 'package:runiverse/features/chat/domain/chat_message.dart';
import 'package:runiverse/features/chat/domain/chat_repository.dart';
import 'package:runiverse/features/chat/presentation/chat_page.dart';
import 'package:runiverse/features/chat/presentation/chat_provider.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';
import 'package:runiverse/features/matching/presentation/match_room_provider.dart';

/// 채팅 페이지 (대기방 자식 라우트).
///
/// ## ⚠️ 발신자의 이름과 사진은 메시지에 없다
///
/// 화면이 `senderUserId`를 **방 명단에서 찾아** 그린다. 그래서 명단에 없는
/// 사람의 메시지는 탈퇴 표기로 떨어지고, 입장 알림 문구도 화면이 만든다.
void main() {
  final startAt = KstTime.toLocal(DateTime(2026, 11, 4, 19, 30));
  final sentAt = KstTime.toLocal(DateTime(2026, 11, 4, 19, 28));

  const seed = ChatRoomSeed(
    runningRoomId: 130,
    partyUserIds: ['me', 'u1', 'u2', 'u3'],
    myUserId: 'me',
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

  ChatMessage message(
    String id,
    String sender, {
    String? text,
    ChatMessageKind kind = ChatMessageKind.text,
  }) => ChatMessage(
    messageId: id,
    senderUserId: sender,
    kind: kind,
    sentAt: sentAt,
    text: text,
  );

  final conversation = [
    message('m0', 'u1', kind: ChatMessageKind.joined),
    message('m1', 'u1', text: '안녕하세요, 오늘 잘 부탁드려요'),
    message('m2', 'me', text: '저도 반가워요'),
  ];

  Future<_StubChat> pumpChat(
    WidgetTester tester, {
    ChatState state = const ChatState(seed: seed),
    Completer<void>? gate,
    bool light = false,
  }) async {
    final chat = _StubChat(state, gate: gate);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatProvider.overrideWith(() => chat),
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
    return chat;
  }

  group('세 분기와 empty', () {
    testWidgets('싣는 동안 인디케이터가 뜬다', (tester) async {
      await pumpChat(tester, state: const ChatState(seed: seed, loading: true));

      expect(find.byType(CircularProgressIndicator), findsOne);
    });

    testWidgets('실패하면 다시 시도가 뜬다', (tester) async {
      await pumpChat(tester, state: const ChatState(seed: seed, failed: true));

      expect(find.text(AppStrings.chatRetry), findsOne);
    });

    testWidgets('메시지가 없으면 안내와 칩이 함께 보인다', (tester) async {
      // ⚠️ empty에서도 칩과 입력창은 보인다 — 먼저 말을 걸 수 있어야 한다.
      await pumpChat(tester);

      expect(find.text(AppStrings.chatEmpty), findsOne);
      expect(find.text(AppStrings.chatQuickReplies.first), findsOne);
    });
  });

  group('무엇을 그리는가', () {
    testWidgets('제목이 두 줄이다', (tester) async {
      await pumpChat(
        tester,
        state: ChatState(seed: seed, messages: conversation),
      );

      expect(find.text('19:30 - 5 km 러닝'), findsOne);
      expect(find.text('영희님 외 2명'), findsOne);
    });

    testWidgets('내 메시지에는 닉네임이 없다', (tester) async {
      await pumpChat(
        tester,
        state: ChatState(seed: seed, messages: conversation),
      );

      expect(find.text('저도 반가워요'), findsOne);
      expect(find.text('나'), findsNothing);
    });

    testWidgets('남의 메시지에 닉네임과 사진이 붙는다', (tester) async {
      await pumpChat(
        tester,
        state: ChatState(seed: seed, messages: conversation),
      );

      expect(find.text('안녕하세요, 오늘 잘 부탁드려요'), findsOne);
      expect(find.text('영희'), findsOne);
      expect(find.byType(PartyChip), findsOne);
    });

    testWidgets('입장 알림이 버블이 아니다', (tester) async {
      await pumpChat(
        tester,
        state: ChatState(seed: seed, messages: conversation),
      );

      expect(find.text(AppStrings.chatJoined('영희')), findsOne);
    });

    testWidgets('⚠️ 명단에 없는 사람은 탈퇴한 사용자다', (tester) async {
      // 나갔거나 탈퇴한 사람의 메시지. 명단과 한 벌로 처리한다.
      await pumpChat(
        tester,
        state: ChatState(
          seed: seed,
          messages: [message('m9', 'ghost', text: '다녀왔습니다')],
        ),
      );

      expect(find.text(AppStrings.matchRoomDeletedPlayer), findsOne);
    });

    testWidgets('⚠️ 아주 긴 한 줄도 넘치지 않는다', (tester) async {
      // 제목을 두 줄로 나눈 이유가 이것이고, 버블은 줄바꿈으로 받아야 한다.
      final long = '가나다라마바사' * 43;

      for (final light in [false, true]) {
        await pumpChat(
          tester,
          light: light,
          state: ChatState(
            seed: seed,
            messages: [message('m8', 'u1', text: long)],
          ),
        );

        expect(tester.takeException(), isNull);
      }
    });
  });

  group('열고 닫기', () {
    testWidgets('⚠️ 뜨면 열고, 내려가면 닫는다', (tester) async {
      // 이 호출이 사라지면 **보고 있는 말이 안 읽음으로 쌓인다.** 대역이
      // 빈 몸으로 덮고 있어 상태로는 확인할 수 없어서 횟수를 센다.
      final chat = await pumpChat(tester);

      expect(chat.opens, 1);
      expect(chat.closes, 0);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      expect(chat.closes, 1);
    });
  });

  group('보내기', () {
    testWidgets('칩을 누르면 바로 보내진다', (tester) async {
      final chat = await pumpChat(tester);

      await tester.tap(find.text(AppStrings.chatQuickReplies.first));
      await tester.pump();

      expect(chat.sent, [AppStrings.chatQuickReplies.first]);
    });

    testWidgets('⚠️ 칩을 눌러도 쓰던 글은 남는다', (tester) async {
      // 칩 문구는 입력칸에서 온 것이 아니다. 비우면 **사람이 쓰던 글을 지운다.**
      final chat = await pumpChat(tester);

      await tester.enterText(find.byType(TextField), '쓰던 글');
      await tester.pump();
      await tester.tap(find.text(AppStrings.chatQuickReplies.first));
      await tester.pumpAndSettle();

      expect(chat.sent, [AppStrings.chatQuickReplies.first]);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '쓰던 글',
      );
    });

    testWidgets('⚠️ 보내는 동안 칩이 잠긴다', (tester) async {
      // 안 잠그면 같은 말이 다섯 번 도배된다.
      final gate = Completer<void>();
      final chat = await pumpChat(tester, gate: gate);

      await tester.tap(find.text(AppStrings.chatQuickReplies.first));
      await tester.pump();
      await tester.tap(find.text(AppStrings.chatQuickReplies[1]));
      await tester.pump();

      expect(chat.sent, [AppStrings.chatQuickReplies.first]);

      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('공백만 있으면 전송이 비활성이다', (tester) async {
      final chat = await pumpChat(tester);

      await tester.enterText(find.byType(TextField), '   \n ');
      await tester.pump();
      await tester.tap(find.byKey(ChatPage.sendKey), warnIfMissed: false);
      await tester.pump();

      expect(chat.sent, isEmpty);
    });

    testWidgets('보낸 뒤 입력칸이 비워진다', (tester) async {
      final chat = await pumpChat(tester);

      await tester.enterText(find.byType(TextField), '곧 나갈게요');
      await tester.pump();
      await tester.tap(find.byKey(ChatPage.sendKey));
      await tester.pumpAndSettle();

      expect(chat.sent, ['곧 나갈게요']);
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
