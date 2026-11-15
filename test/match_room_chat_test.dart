import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/widgets/v2/surface_card.dart';
import 'package:runiverse/features/app_update/data/fake_app_version_repository.dart';
import 'package:runiverse/features/app_update/presentation/app_version_provider.dart';
import 'package:runiverse/features/chat/data/fake_chat_repository.dart';
import 'package:runiverse/features/chat/domain/chat.dart';
import 'package:runiverse/features/chat/presentation/chat_page.dart';
import 'package:runiverse/features/chat/presentation/chat_provider.dart';
import 'package:runiverse/features/matching/data/fake_match_repository.dart';
import 'package:runiverse/features/matching/data/fake_match_stream.dart';
import 'package:runiverse/features/matching/domain/match_event.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';
import 'package:runiverse/features/matching/presentation/match_register_provider.dart';
import 'package:runiverse/features/matching/presentation/match_room_page.dart';
import 'package:runiverse/features/matching/presentation/match_room_provider.dart';
import 'package:runiverse/features/notification/data/fake_app_stream.dart';
import 'package:runiverse/features/notification/data/fake_notification_repository.dart';
import 'package:runiverse/features/notification/presentation/notification_provider.dart';
import 'package:runiverse/features/session/data/fake_location_repository.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/session/domain/location_repository.dart';
import 'package:runiverse/features/session/domain/user_status.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// 대기방의 채팅 버튼 — **그리고 채팅을 열어 둔 사이의 자동 이동.**
///
/// ## ⚠️ 여기가 이번 작업의 진짜 함정이다
///
/// go_router는 자식을 띄워도 부모를 내리지 않는다. 채팅을 올려 둔 동안
/// `MatchRoomPage`는 **그대로 살아 있고**, 그 안의 자동 이동 두 개가 계속 돈다.
/// 둘 다 **맨 위 라우트**를 건드리므로 채팅을 집는다.
///
/// - 방이 죽을 때 `_leaveScreen()`의 `pop()`이 **채팅만 닫고** 죽은 방 화면에
///   사람을 남긴다
/// - 출발 30초 전의 `pushReplacement`가 **방이 아니라 채팅을 갈아치워** 방 화면이
///   스택에 남는다. 그 화면의 타이머와 `ref.listen`은 러닝 내내 살아 있다
void main() {
  final soon = DateTime.now().add(const Duration(seconds: 20));
  final later = DateTime.now().add(const Duration(minutes: 30));

  RoomInfo room({
    RoomStatus status = RoomStatus.matched,
    int players = 3,
    DateTime? startAt,
  }) => RoomInfo(
    runningRoomId: 125,
    status: status,
    scheduledStartAt: startAt ?? later,
    targetDistanceMeters: 5000,
    players: [
      for (var i = 0; i < players; i++)
        RoomPlayer(userId: 'u-$i', nickname: '러너$i', isDeleted: false),
    ],
  );

  ChatState unreadState(int unread) => ChatState(
    runningRoomId: 125,
    messages: [
      for (var i = 0; i < unread; i++)
        Chat(
          chatId: 1000 + i,
          runningRoomId: 125,
          sender: const ChatSender(userId: 'u-1', nickname: '러너1'),
          content: '안녕하세요',
          createdAt: DateTime.now(),
          isRead: false,
        ),
    ],
  );

  /// 대기방을 띄우고 첫 스냅샷을 밀어 넣는다.
  ///
  /// ⚠️ `pumpAndSettle`을 쓰지 못한다. 카운트다운이 1초 타이머를 계속 돌려
  /// 화면이 영영 잠잠해지지 않는다.
  Future<({FakeMatchStream stream, _StubChat chat})> pumpRoom(
    WidgetTester tester, {
    required RoomInfo snapshot,
    ChatState chatState = const ChatState(),
  }) async {
    final stream = FakeMatchStream();
    final chat = _StubChat(chatState);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appVersionRepositoryProvider.overrideWithValue(
            FakeAppVersionRepository(),
          ),
          matchStreamProvider.overrideWithValue(stream),
          // 채팅 버튼이 보이는 순간 chatProvider가 서고, 그것이 진짜 저장소를
          // 세운다 — 서버 주소가 없는 테스트에서는 거기서 죽는다.
          chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
          matchRepositoryProvider.overrideWithValue(FakeMatchRepository()),
          userStatusRepositoryProvider.overrideWithValue(
            FakeUserStatusRepository(
              status: UserStatusWaiting(
                runningRoomId: 125,
                type: RoomType.match,
                scheduledStartAt: snapshot.scheduledStartAt,
              ),
            ),
          ),
          appStreamProvider.overrideWithValue(FakeAppStream()),
          notificationRepositoryProvider.overrideWithValue(
            FakeNotificationRepository(),
          ),
          // 출발 대기실이 들어올 때 위치 권한을 읽는다.
          locationRepositoryProvider.overrideWithValue(
            FakeLocationRepository(access: LocationAccess.granted),
          ),
          chatProvider.overrideWith(() => chat),
        ],
        child: const RuniverseApp(initialLocation: AppRoutes.matchRoom),
      ),
    );
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MatchRoomPage)),
    );
    container.read(matchRoomProvider.notifier).connect();
    await tester.pump();
    stream.emit(MatchRoomUpdated(snapshot));
    await tester.pump();
    await tester.pump();

    return (stream: stream, chat: chat);
  }

  Future<void> tick(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('언제 보이는가', () {
    testWidgets('파티원이 둘 이상이면 채팅 버튼이 보인다', (tester) async {
      await pumpRoom(tester, snapshot: room());

      expect(find.byKey(MatchRoomPage.chatKey), findsOne);
    });

    testWidgets('⚠️ 나 혼자여도 보인다', (tester) async {
      // ⚠️ **2026-11-13에 뒤집었다.** 전에는 혼자면 숨겼는데, 둘이 대화하다
      // 한 명이 나가면 남은 사람이 **방금 나눈 대화에 들어갈 문을 잃었다.**
      // 대화는 살아 있는데 버튼만 사라지는 상태였다. 출발 전이면 늘 연다.
      await pumpRoom(tester, snapshot: room(players: 1));

      expect(find.byKey(MatchRoomPage.chatKey), findsOne);
    });

    testWidgets('출발한 방(started)에서는 숨는다', (tester) async {
      await pumpRoom(tester, snapshot: room(status: RoomStatus.started));

      expect(find.byKey(MatchRoomPage.chatKey), findsNothing);
    });

    testWidgets('⚠️ 떠 있는 버튼이 목록 맨 끝 줄을 가리지 않는다', (tester) async {
      // ⚠️ **겨냥하는 것이 2026-11-11에 바뀌었다.** 전에는 목록 맨 끝에 나가기
      // 안내가 있어 그것을 봤는데, 팀이 그 안내를 목록 밖(나가기 버튼 위)으로
      // 옮겼다. 안내는 이제 `Stack` 밖이라 버튼에 가려질 수가 없고, 그대로 두면
      // **늘 통과하는 테스트**가 된다.
      //
      // 지금 목록 맨 끝은 파티 카드다. 버튼이 그 위에 떠 있으므로 목록이
      // 버튼만큼 아래 여백을 둬야 카드의 끝 줄이 가려지지 않는다.
      await pumpRoom(tester, snapshot: room());
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tick(tester);

      final party = tester.getRect(find.byType(SurfaceCard).last);
      final button = tester.getRect(find.byKey(MatchRoomPage.chatKey));

      expect(party.overlaps(button), isFalse);
    });

    testWidgets('나가기 버튼이 가려지지 않는다', (tester) async {
      // A안(Scaffold FAB)이 깨진 이유다 — `나가기`가 body 안에 있다.
      await pumpRoom(tester, snapshot: room());
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tick(tester);

      await tester.tap(find.text(AppStrings.matchRoomLeave));
      await tick(tester);

      expect(find.text(AppStrings.matchRoomLeaveTitle), findsOne);
    });
  });

  group('배지', () {
    testWidgets('안 읽은 수가 배지에 뜬다', (tester) async {
      final app = await pumpRoom(
        tester,
        snapshot: room(),
        chatState: unreadState(2),
      );

      expect(find.byKey(MatchRoomPage.chatBadgeKey), findsOne);
      expect(find.text('2'), findsOne);
      // ⚠️ **붙이는 일은 이 화면이 하지 않는다.** 방 번호를 넣어 주던 때는
      // 아무도 보지 않는 사이에 채팅이 버려지면 다시 붙지 않았다 — 혼자
      // 있다가 사람이 들어온 방의 채팅이 빈 목록으로 남았다. 지금은
      // `chatProvider`가 방을 직접 듣는다(`chat_provider_test`가 덮는다).
      expect(app.chat.connects, 0);
    });

    testWidgets('⚠️ 0이면 배지가 없다', (tester) async {
      await pumpRoom(tester, snapshot: room(), chatState: unreadState(0));

      expect(find.byKey(MatchRoomPage.chatBadgeKey), findsNothing);
    });

    testWidgets('Semantics가 안 읽은 수까지 읽는다', (tester) async {
      // 글자 라벨이 없는 버튼이다 — 안 붙이면 스크린리더가 읽을 것이 없다.
      final semantics = tester.ensureSemantics();
      await pumpRoom(tester, snapshot: room(), chatState: unreadState(2));

      expect(
        find.bySemanticsLabel(AppStrings.chatButtonSemantics(2)),
        findsOne,
      );

      // ⚠️ `addTearDown`으로는 늦다 — 핸들 검사가 tearDown보다 먼저 돈다.
      semantics.dispose();
    });
  });

  group('⚠️ 채팅을 열어 둔 사이의 자동 이동', () {
    testWidgets('⚠️ 채팅을 연 채 방이 죽으면 채팅부터 닫힌다', (tester) async {
      final app = await pumpRoom(tester, snapshot: room());
      await tester.tap(find.byKey(MatchRoomPage.chatKey));
      await tick(tester);
      expect(find.byType(ChatPage), findsOne);

      // 서버가 방을 닫았다(나가기·취소 뒤의 모습이다).
      app.stream.emit(MatchRoomUpdated(room(status: RoomStatus.cancelled)));
      await tick(tester);

      // 채팅만 닫히고 죽은 방 화면에 사람이 남으면 실패다.
      expect(find.byType(ChatPage, skipOffstage: false), findsNothing);
      expect(find.byType(MatchRoomPage, skipOffstage: false), findsNothing);
    });

    testWidgets('⚠️ 채팅을 연 채 출발 시각이 닥치면 카운트다운으로 간다', (tester) async {
      final app = await pumpRoom(tester, snapshot: room(startAt: soon));
      await tester.tap(find.byKey(MatchRoomPage.chatKey));
      await tick(tester);
      expect(find.byType(ChatPage), findsOne);

      // 1초 타이머가 돌면 출발 30초 전을 지난 것을 알아챈다.
      await tester.pump(const Duration(seconds: 1));
      await tick(tester);

      // `pushReplacement`가 채팅을 갈아치우면 방 화면이 스택에 남는다 —
      // 그 화면의 타이머와 listen이 러닝 내내 살아 있게 된다.
      expect(find.byType(ChatPage, skipOffstage: false), findsNothing);
      expect(find.byType(MatchRoomPage, skipOffstage: false), findsNothing);

      app.stream.close();
    });
  });
}

/// 상태를 그대로 물려주는 대역. 방 화면이 부르는 `connect`를 세기만 한다.
class _StubChat extends ChatController {
  _StubChat(this.initial);

  final ChatState initial;

  var connects = 0;
  var reloads = 0;

  @override
  ChatState build() => initial;

  @override
  Future<void> connect(int runningRoomId, {int limit = 50}) async => connects++;

  @override
  Future<void> reload() async => reloads++;

  @override
  void open() {}

  @override
  void close() {}
}
