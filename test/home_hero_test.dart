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
    DateTime? cooldownUntil,
    String? name,
    // ⚠️ 돌려주는 기록은 **pump 시점에 굳는다**(레코드라 값이 복사된다).
    // 누른 뒤의 횟수를 보려면 부르는 쪽이 살아 있는 카운터를 넘겨야 한다.
    VoidCallback? onMatch,
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
              name: name,
              room: withRoom,
              pending: pending,
              cooldownUntil: cooldownUntil,
              now: now ?? DateTime(2026, 9, 16, 18, 30),
              onMatch: onMatch ?? () => match++,
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
    testWidgets('매칭 버튼을 보여준다', (tester) async {
      await pumpHero(tester);

      expect(find.text(AppStrings.homeMatchCta), findsOneWidget);
    });

    testWidgets('⚠️ 솔로 버튼은 여기 없다', (tester) async {
      // 시안 `158:2848`이 카드 밖 하단 칸으로 옮겼다. 둘 다 있으면 같은 일을
      // 하는 버튼이 한 화면에 둘이 된다.
      await pumpHero(tester);

      expect(find.text(AppStrings.homeSoloCta), findsNothing);
    });

    testWidgets('이름이 있으면 부른다', (tester) async {
      await pumpHero(tester, name: '러너42');

      expect(find.textContaining('러너42님'), findsOneWidget);
    });

    testWidgets('⚠️ 이름이 없으면 그 줄을 통째로 뺀다', (tester) async {
      // `/me`가 오기 전이거나 온보딩 전이면 비어 있다. `님`만 남으면
      // 이름을 잃어버린 것처럼 보인다.
      await pumpHero(tester);

      expect(find.text(AppStrings.homeHeroPrompt), findsOneWidget);
      expect(find.textContaining('님'), findsNothing);
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

  group('⚠️ 이탈 제재 중', () {
    // 예전에는 눌러서 409를 받아야만 이유를 알 수 있었다. 서버는 이미
    // 언제까지인지 말해 줬는데 앱이 그것을 숨기고 있었다.
    final until = DateTime(2026, 9, 16, 18, 40);

    testWidgets('⚠️ 매칭 신청을 미리 막는다', (tester) async {
      // ⚠️ **눌러서 본다.** 위젯의 `onPressed`가 null 인지만 재면, 그 위에
      // 다른 것이 얹혀 눌리는 경우를 못 잡는다(스펙 9절).
      var matched = 0;
      await pumpHero(tester, cooldownUntil: until, onMatch: () => matched++);

      await tester.tap(find.text(AppStrings.homeMatchCta));
      await tester.pumpAndSettle();

      expect(matched, 0, reason: '잠겼는데 눌렸다');
    });

    testWidgets('언제까지인지 글로 말한다', (tester) async {
      await pumpHero(tester, cooldownUntil: until);

      expect(find.text(AppStrings.matchFailedCooldown(until)), findsOneWidget);
    });

    // ⚠️ **`솔로는 막지 않는다`가 여기서 빠졌다.** 솔로 버튼이 카드 밖
    // `ActionTileV2`로 나가서, 이 화면에는 막을 것도 열 것도 없다.
    // 그 단정은 `home_page_test`가 이어받는다.

    testWidgets('제한이 지났으면 그대로 연다', (tester) async {
      var matched = 0;
      await pumpHero(
        tester,
        cooldownUntil: DateTime(2026, 9, 16, 18, 20),
        now: DateTime(2026, 9, 16, 18, 30),
        onMatch: () => matched++,
      );
      await tester.tap(find.text(AppStrings.homeMatchCta));
      await tester.pumpAndSettle();

      expect(matched, 1);
      expect(find.textContaining('신청할 수 없어요'), findsNothing);
    });
  });

  group('⚠️ 러닝이 이미 시작됐을 때', () {
    // 예약한 시각이 지나 서버가 러닝을 시작했는데 사용자가 홈 탭에 있는
    // 자리다. 예전에는 기본 히어로로 떨어져 **달리는 중에 "지금 매칭하기"가
    // 보였고**, 들어갈 문이 없어 그사이가 통째로 거리에서 빠졌다.
    testWidgets('기본 히어로로 떨어지지 않는다', (tester) async {
      await pumpHero(tester, withRoom: room(RoomStatus.started));

      expect(find.text(AppStrings.homeRunStarted), findsOneWidget);
      expect(find.text(AppStrings.homeMatchCta), findsNothing);
    });

    testWidgets('⚠️ 들어갈 문이 있다', (tester) async {
      // `pumpHero`가 돌려주는 횟수는 pump 시점에 굳으므로 여기서는 직접 센다.
      var entered = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: HomeHero(
              room: room(RoomStatus.started),
              now: DateTime(2026, 9, 16, 19, 5),
              onMatch: () {},
              onCancel: () {},
              onLobby: () => entered++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.homeRunToSession));
      await tester.pump();

      expect(entered, 1);
    });

    testWidgets('기다릴 것이 없으니 카운트다운을 그리지 않는다', (tester) async {
      await pumpHero(tester, withRoom: room(RoomStatus.started));

      expect(find.text(AppStrings.homeMatchStartLabel), findsNothing);
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
