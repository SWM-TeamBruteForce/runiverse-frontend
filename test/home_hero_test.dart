import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/features/home/presentation/home_hero.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';

/// 홈 히어로가 **매칭 상태를 전담한다** (S05).
///
/// 모집 중에는 갈 화면이 따로 없어서, 여기가 틀리면 사용자는 자기가 신청했는지
/// 조차 알 수 없다. 확정 뒤의 `로비로 이동`은 방으로 가는 유일한 문이다.
void main() {
  final startAt = DateTime(2026, 9, 16, 19);

  RoomInfo room(RoomStatus status, {int players = 2, DateTime? closeAt}) =>
      RoomInfo(
        runningRoomId: 125,
        status: status,
        scheduledStartAt: startAt,
        closeAt: closeAt,
        players: [
          for (var i = 0; i < players; i++)
            RoomPlayer(userId: 'u-$i', nickname: '러너$i', isDeleted: false),
        ],
      );

  Future<({int match, int cancel, int lobby})> pumpHero(
    WidgetTester tester, {
    RoomInfo? withRoom,
    bool pending = false,
    DateTime? now,
  }) async {
    var match = 0;
    var cancel = 0;
    var lobby = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: HomeHero(
              greeting: AppStrings.homeGreetingEvening,
              room: withRoom,
              pending: pending,
              now: now ?? DateTime(2026, 9, 16, 18, 30),
              onMatch: () => match++,
              onSolo: () {},
              onCancel: () => cancel++,
              onLobby: () => lobby++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (match: match, cancel: cancel, lobby: lobby);
  }

  group('기본', () {
    testWidgets('두 버튼을 보여준다', (tester) async {
      await pumpHero(tester);

      expect(find.text(AppStrings.homeMatchCta), findsOneWidget);
      expect(find.text(AppStrings.homeSoloCta), findsOneWidget);
    });
  });

  group('모집 중', () {
    testWidgets('몇 명 모였는지와 마감을 알린다', (tester) async {
      await pumpHero(
        tester,
        withRoom: room(
          RoomStatus.matching,
          players: 2,
          closeAt: DateTime(2026, 9, 16, 18, 50),
        ),
      );

      expect(find.text(AppStrings.homeMatchWaiting), findsOneWidget);
      // 숫자만 강조색이라 `Text.rich`다 — `findRichText`가 없으면 못 읽는다.
      expect(
        find.text(
          '${AppStrings.homeMatchJoinedPrefix} '
          '${AppStrings.homeMatchJoinedCount(2)} '
          '${AppStrings.homeMatchJoinedSuffix}',
          findRichText: true,
        ),
        findsOneWidget,
      );
      // 20분 남았다. 초까지 세지 않는다 — 조급해진다.
      expect(
        find.text(
          AppStrings.homeMatchSlotLine(startAt, const Duration(minutes: 20)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('⚠️ 다시 신청하러 갈 문이 없다', (tester) async {
      // 이미 신청했다. 또 누르면 서버가 409로 막는다.
      await pumpHero(tester, withRoom: room(RoomStatus.matching));

      expect(find.text(AppStrings.homeMatchCta), findsNothing);
      expect(find.text(AppStrings.homeMatchToLobby), findsOneWidget);
    });

    testWidgets('⚠️ 취소는 히어로에 두지 않는다', (tester) async {
      // 제재 여부는 로비가 문구로 알려준다. 두 곳에 두면 한쪽만 고쳐진다.
      await pumpHero(tester, withRoom: room(RoomStatus.matching));

      expect(find.text(AppStrings.homeMatchCancel), findsNothing);
    });

    testWidgets('파티원 이름이 보인다', (tester) async {
      await pumpHero(tester, withRoom: room(RoomStatus.matching));

      expect(find.text('러너0'), findsOneWidget);
      expect(find.text('러너1'), findsOneWidget);
    });
  });

  group('확정', () {
    testWidgets('출발까지 세고 로비로 가는 문을 연다', (tester) async {
      await pumpHero(tester, withRoom: room(RoomStatus.matched, players: 3));

      expect(find.text(AppStrings.homeMatchConfirmed(startAt)), findsOneWidget);
      expect(find.text(AppStrings.homeMatchStartLabel), findsOneWidget);
      expect(find.text(AppStrings.homeMatchParty(3)), findsOneWidget);
      expect(find.text(AppStrings.homeMatchToWaitingRoom), findsOneWidget);
    });

    testWidgets('⚠️ 확정 뒤에도 취소가 히어로에 없다', (tester) async {
      // 확정 이탈은 제재가 붙는다. 대기실에서 문구를 보고 결정하게 한다.
      await pumpHero(tester, withRoom: room(RoomStatus.matched));

      expect(find.text(AppStrings.homeMatchCancel), findsNothing);
    });

    testWidgets('시작 시각이 지나도 음수를 그리지 않는다', (tester) async {
      await pumpHero(
        tester,
        withRoom: room(RoomStatus.matched),
        now: DateTime(2026, 9, 16, 19, 0, 5),
      );

      expect(
        find.text(AppStrings.matchRoomCountdown(Duration.zero)),
        findsOneWidget,
      );
    });
  });

  group('방 정보가 아직 없을 때', () {
    testWidgets('⚠️ 기본 히어로를 보여주지 않는다', (tester) async {
      // 신청한 사람이 이걸 보면 사라진 줄 알고 다시 누른다.
      await pumpHero(tester, pending: true);

      expect(find.text(AppStrings.homeMatchPending), findsOneWidget);
      expect(find.text(AppStrings.homeMatchCta), findsNothing);
    });

    testWidgets('그래도 나갈 수는 있다', (tester) async {
      // 취소는 방 번호를 쓰지 않는다.
      await pumpHero(tester, pending: true);

      expect(find.text(AppStrings.homeMatchCancel), findsOneWidget);
    });
  });
}
