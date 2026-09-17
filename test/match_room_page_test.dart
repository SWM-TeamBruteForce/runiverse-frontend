import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/features/matching/data/fake_match_repository.dart';
import 'package:runiverse/features/matching/data/fake_match_stream.dart';
import 'package:runiverse/features/matching/domain/match_event.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';
import 'package:runiverse/features/matching/presentation/match_register_provider.dart';
import 'package:runiverse/features/matching/presentation/match_room_page.dart';
import 'package:runiverse/features/matching/presentation/match_room_provider.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/session/domain/user_status.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// 대기방 (S10) — **무엇을 보여주고, 나갈 때 무엇을 알리는가.**
///
/// 확정 뒤에 나가면 20분 동안 다시 신청할 수 없다. 그 사실을 나간 뒤에 알리면
/// 속았다고 느낀다 — 언제 겁을 주고 언제 주지 않는가가 여기의 핵심이다.
void main() {
  final startAt = DateTime.now().add(const Duration(minutes: 30));
  final closeAtSoon = DateTime.now().add(const Duration(minutes: 20));
  final closedAlready = DateTime.now().subtract(const Duration(minutes: 5));

  RoomInfo room({
    required RoomStatus status,
    DateTime? closeAt,
    int players = 3,
    bool deletedLast = false,
  }) => RoomInfo(
    runningRoomId: 125,
    status: status,
    scheduledStartAt: startAt,
    closeAt: closeAt,
    targetDistanceMeters: 5000,
    players: [
      for (var i = 0; i < players; i++)
        RoomPlayer(
          userId: 'u-$i',
          nickname: '러너$i',
          isDeleted: deletedLast && i == players - 1,
        ),
    ],
  );

  /// 대기방을 띄우고 첫 스냅샷을 밀어 넣는다.
  ///
  /// ⚠️ `pumpAndSettle`을 쓰지 못한다. 카운트다운이 1초 타이머를 계속 돌려
  /// 화면이 영영 잠잠해지지 않는다.
  Future<({FakeMatchStream stream, FakeMatchRepository matches})> pumpRoom(
    WidgetTester tester, {
    required RoomInfo snapshot,
  }) async {
    final stream = FakeMatchStream();
    final matches = FakeMatchRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matchStreamProvider.overrideWithValue(stream),
          matchRepositoryProvider.overrideWithValue(matches),
          userStatusRepositoryProvider.overrideWithValue(
            // ⚠️ 대기로 답하게 둔다. 끊긴 뒤 재연결이 이 값을 실제로 읽는데,
            // `IDLE`이면 "신청한 적 없다"로 읽혀 방을 비우는 것이 맞는 동작이
            // 된다 — 대기방을 띄워놓고 상태만 idle인 상황은 서버에 없다.
            FakeUserStatusRepository(
              status: UserStatusWaiting(
                runningRoomId: 1,
                scheduledStartAt: startAt,
              ),
            ),
          ),
        ],
        child: const RuniverseApp(initialLocation: AppRoutes.matchRoom),
      ),
    );
    await tester.pump();

    // 화면이 소유하지 않으므로 provider를 직접 붙인다 — 실제로는 유저 상태가
    // 대기·확정일 때 앱이 붙여 둔 상태로 들어온다.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MatchRoomPage)),
    );
    container.read(matchRoomProvider.notifier).connect();
    await tester.pump();
    stream.emit(MatchRoomUpdated(snapshot));
    await tester.pump();
    await tester.pump();

    return (stream: stream, matches: matches);
  }

  Future<void> tick(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// 목록 아래쪽을 끌어온다.
  ///
  /// 테스트 화면이 800×600이라 나가기 안내가 화면 밖으로 밀린다. 실제 기기에서
  /// 보이지 않는다는 뜻은 아니다 — 스크롤하면 나온다.
  Future<void> revealBottom(WidgetTester tester) async {
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tick(tester);
  }

  group('무엇을 보여주는가', () {
    testWidgets('첫 스냅샷이 오기 전에는 기다리는 중임을 보여준다', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            matchStreamProvider.overrideWithValue(FakeMatchStream()),
            matchRepositoryProvider.overrideWithValue(FakeMatchRepository()),
            userStatusRepositoryProvider.overrideWithValue(
              FakeUserStatusRepository(),
            ),
          ],
          child: const RuniverseApp(initialLocation: AppRoutes.matchRoom),
        ),
      );
      await tester.pump();

      // 빈 화면은 고장으로 읽힌다.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('⚠️ 단계에 따라 화면 이름이 갈린다', (tester) async {
      // 같은 화면이다. 모집 중에는 누구와 뛸지 아직 모르니 로비이고,
      // 확정 뒤에는 출발을 기다리는 대기실이다.
      await pumpRoom(
        tester,
        snapshot: room(status: RoomStatus.matching, closeAt: closeAtSoon),
      );

      expect(find.text(AppStrings.matchRoomTitleLobby), findsOneWidget);
      expect(find.text(AppStrings.matchRoomTitleWaiting), findsNothing);
    });

    testWidgets('확정되면 대기실이다', (tester) async {
      await pumpRoom(
        tester,
        snapshot: room(status: RoomStatus.matched, closeAt: closedAlready),
      );

      expect(find.text(AppStrings.matchRoomTitleWaiting), findsOneWidget);
    });

    testWidgets('모집 중에는 마감까지 세고 인원을 알린다', (tester) async {
      await pumpRoom(
        tester,
        snapshot: room(status: RoomStatus.matching, closeAt: closeAtSoon),
      );

      expect(find.text(AppStrings.matchRoomWaiting), findsOneWidget);
      expect(find.text(AppStrings.matchRoomCloseLabel), findsOneWidget);
      expect(find.text(AppStrings.matchRoomJoined(3)), findsOneWidget);
    });

    testWidgets('확정 뒤에는 출발까지 센다', (tester) async {
      // 모집 중과 확정 뒤에 사람이 기다리는 것이 다르다.
      await pumpRoom(
        tester,
        snapshot: room(status: RoomStatus.matched, closeAt: closedAlready),
      );

      expect(find.text(AppStrings.matchRoomMatched), findsOneWidget);
      expect(find.text(AppStrings.matchRoomStartLabel), findsOneWidget);
    });

    testWidgets('세션 정보와 파티원을 보여준다', (tester) async {
      await pumpRoom(
        tester,
        snapshot: room(status: RoomStatus.matched, closeAt: closedAlready),
      );

      expect(find.text(AppStrings.matchRoomStartAt(startAt)), findsOneWidget);
      expect(find.text(AppStrings.matchRoomTarget(5)), findsOneWidget);
      expect(find.text(AppStrings.matchRoomPlayers(3)), findsOneWidget);
      expect(find.text('러너0'), findsOneWidget);
    });

    testWidgets('⚠️ 탈퇴한 참가자도 자리를 지킨다', (tester) async {
      // 빼면 인원 수가 방과 어긋난다.
      await pumpRoom(
        tester,
        snapshot: room(
          status: RoomStatus.matched,
          closeAt: closedAlready,
          deletedLast: true,
        ),
      );

      expect(find.text(AppStrings.matchRoomPlayers(3)), findsOneWidget);
      expect(find.text(AppStrings.matchRoomDeletedPlayer), findsOneWidget);
    });

    testWidgets('⚠️ 끊기면 무엇이 멈췄는지 알린다', (tester) async {
      // 방은 그대로 두되, 인원이 바뀌어도 안 보인다는 사실은 말해야 한다.
      final app = await pumpRoom(
        tester,
        snapshot: room(status: RoomStatus.matching, closeAt: closeAtSoon),
      );

      app.stream.breakDown();
      // ⚠️ 두 번 민다. 첫 프레임에 오류가 전달되고, 그것이 바꾼 상태는 다음
      // 프레임에야 화면에 닿는다. 1초짜리 재연결 예약보다는 이르다.
      await tester.pump();
      await tester.pump();

      expect(find.text(AppStrings.matchRoomDisconnected), findsOneWidget);
      // 방은 남아 있다 — 잠깐 끊겼다고 사람을 홈으로 튕기지 않는다.
      expect(find.text(AppStrings.matchRoomPlayers(3)), findsOneWidget);
    });

    testWidgets('⚠️ 다시 붙으면 경고를 내린다', (tester) async {
      // 서버는 30분마다 스트림을 정상으로 닫는다. 끊긴 채로 두면 확정 통지를
      // 놓치므로 스스로 다시 붙고, 붙었으면 겁주던 문구를 거둬야 한다.
      final app = await pumpRoom(
        tester,
        snapshot: room(status: RoomStatus.matching, closeAt: closeAtSoon),
      );

      app.stream.breakDown();
      await tester.pump();
      await tester.pump();
      expect(find.text(AppStrings.matchRoomDisconnected), findsOneWidget);

      // 재연결 예약이 깨어날 만큼 흘린다.
      await tester.pump(const Duration(seconds: 2));
      await tick(tester);

      expect(find.text(AppStrings.matchRoomDisconnected), findsNothing);
      expect(find.text(AppStrings.matchRoomPlayers(3)), findsOneWidget);
      // 새로 붙었다 — 닫고 다시 여는 것이 한 번씩 일어났다.
      expect(app.stream.connects, 2);
    });
  });

  group('나가기', () {
    testWidgets('모집 중에는 겁주지 않는다', (tester) async {
      // 마감 전에 나가는 것은 제재 대상이 아니다.
      await pumpRoom(
        tester,
        snapshot: room(status: RoomStatus.matching, closeAt: closeAtSoon),
      );
      await revealBottom(tester);

      expect(find.text(AppStrings.matchRoomLeaveFree), findsOneWidget);
      expect(find.text(AppStrings.matchRoomLeavePenalty), findsNothing);
    });

    testWidgets('⚠️ 마감이 지났으면 20분 제한을 미리 알린다', (tester) async {
      // 나간 뒤에 알리면 속았다고 느낀다.
      await pumpRoom(
        tester,
        snapshot: room(status: RoomStatus.matched, closeAt: closedAlready),
      );
      await revealBottom(tester);

      expect(find.text(AppStrings.matchRoomLeavePenalty), findsOneWidget);
    });

    testWidgets('⚠️ 혼자 남은 방은 마감이 지나도 면제다', (tester) async {
      // 있지도 않은 제재로 겁주지 않는다.
      await pumpRoom(
        tester,
        snapshot: room(
          status: RoomStatus.matched,
          closeAt: closedAlready,
          players: 1,
        ),
      );
      await revealBottom(tester);

      expect(find.text(AppStrings.matchRoomLeaveFree), findsOneWidget);
    });

    testWidgets('묻지 않고 나가지 않는다', (tester) async {
      final app = await pumpRoom(
        tester,
        snapshot: room(status: RoomStatus.matched, closeAt: closedAlready),
      );

      await tester.tap(
        find.widgetWithText(AppButton, AppStrings.matchRoomLeave),
      );
      await tick(tester);

      expect(find.text(AppStrings.matchRoomLeaveTitle), findsOneWidget);
      expect(app.matches.cancelCalls, 0);
    });

    testWidgets('남아 있겠다고 하면 아무 일도 없다', (tester) async {
      final app = await pumpRoom(
        tester,
        snapshot: room(status: RoomStatus.matched, closeAt: closedAlready),
      );

      await tester.tap(
        find.widgetWithText(AppButton, AppStrings.matchRoomLeave),
      );
      await tick(tester);
      await tester.tap(find.text(AppStrings.matchRoomStay));
      await tick(tester);

      expect(app.matches.cancelCalls, 0);
      expect(find.byType(MatchRoomPage), findsOneWidget);
    });

    testWidgets('나가겠다고 하면 취소를 보내고 스트림을 닫는다', (tester) async {
      final app = await pumpRoom(
        tester,
        snapshot: room(status: RoomStatus.matched, closeAt: closedAlready),
      );

      await tester.tap(
        find.widgetWithText(AppButton, AppStrings.matchRoomLeave),
      );
      await tick(tester);
      await tester.tap(find.text(AppStrings.matchRoomLeaveConfirm));
      await tick(tester);

      expect(app.matches.cancelCalls, 1);
      // 남겨두면 지난 방의 이벤트가 계속 올라온다.
      expect(app.stream.isConnected, isFalse);
    });

    testWidgets('모집 중에는 버튼 문구가 취소다', (tester) async {
      await pumpRoom(
        tester,
        snapshot: room(status: RoomStatus.matching, closeAt: closeAtSoon),
      );

      expect(
        find.widgetWithText(AppButton, AppStrings.matchRoomCancel),
        findsOneWidget,
      );
    });
  });
}
