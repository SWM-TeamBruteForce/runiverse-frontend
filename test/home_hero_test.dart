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
    String? myUserId,
    VoidCallback? onLobby,
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
              myUserId: myUserId,
              room: withRoom,
              pending: pending,
              cooldownUntil: cooldownUntil,
              now: now ?? DateTime(2026, 9, 16, 18, 30),
              onMatch: onMatch ?? () => match++,
              onCancel: () => cancel++,
              onLobby: onLobby ?? () => lobby++,
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
    testWidgets('기다리는 중이라고 말한다', (tester) async {
      await pumpHero(
        tester,
        withRoom: room(
          RoomStatus.matching,
          players: 2,
          closeAt: DateTime(2026, 9, 16, 18, 50),
        ),
      );

      expect(find.text(AppStrings.homeMatchWaitingTitle), findsOneWidget);
      expect(
        find.textContaining(AppStrings.homeMatchWaitingOthers(2)),
        findsOneWidget,
      );
    });

    testWidgets('⚠️ 나는 둘레에서 빠진다', (tester) async {
      // 가운데가 나다. 서버 명단에 내가 들어 있으면 둘이 되는데, 명단에
      // 나를 넣는지 아닌지는 서버 사정이라 **아이디로 거른다.**
      await pumpHero(
        tester,
        withRoom: room(RoomStatus.matching, players: 2),
        myUserId: 'u-0',
      );

      expect(
        find.textContaining(AppStrings.homeMatchWaitingOthers(1)),
        findsOneWidget,
      );
    });

    testWidgets('⚠️ 인원이 셋이 아니어도 고르게 흩어진다', (tester) async {
      // 시안은 세 사람을 손으로 배치했다. 우리 방은 2~4명이라 둘레에 설
      // 사람이 1~3명으로 변한다 — **각도를 박아 두면 그때 겹친다.**
      final handle = tester.ensureSemantics();

      for (final count in [1, 2, 3, 4]) {
        await pumpHero(
          tester,
          withRoom: room(RoomStatus.matching, players: count),
        );

        final spots = <Offset>[];
        for (var i = 0; i < count; i++) {
          spots.add(tester.getCenter(find.bySemanticsLabel('러너$i')));
        }
        for (var a = 0; a < spots.length; a++) {
          for (var b = a + 1; b < spots.length; b++) {
            expect(
              (spots[a] - spots[b]).distance,
              greaterThan(40),
              reason: '$count명일 때 $a번과 $b번이 겹친다',
            );
          }
        }
      }
      handle.dispose();
    });

    testWidgets('⚠️ 아직 나뿐이면 0명이라 적지 않는다', (tester) async {
      // 신청 직후에는 둘레가 빈다. **시안에 없는 구간이다.**
      await pumpHero(tester, withRoom: room(RoomStatus.matching, players: 0));

      expect(
        find.textContaining(AppStrings.homeMatchWaitingAlone),
        findsOneWidget,
      );
      expect(find.textContaining('0명'), findsNothing);
    });

    testWidgets('⚠️ 다시 신청하러 갈 문이 없다', (tester) async {
      // 이미 신청했다. 또 누르면 서버가 409로 막는다.
      await pumpHero(tester, withRoom: room(RoomStatus.matching));

      expect(find.text(AppStrings.homeMatchCta), findsNothing);
      expect(find.text(AppStrings.homeMatchWaitingCta), findsOneWidget);
    });

    testWidgets('⚠️ 취소는 히어로에 두지 않는다', (tester) async {
      // 제재 여부는 로비가 문구로 알려준다. 두 곳에 두면 한쪽만 고쳐진다.
      await pumpHero(tester, withRoom: room(RoomStatus.matching));

      expect(find.text(AppStrings.homeMatchCancel), findsNothing);
    });

    testWidgets('⚠️ 파티원 이름을 읽어 준다', (tester) async {
      // 시안이 둘레에 **사진만** 둔다. 글자가 없어 `Semantics`가 유일한 길이다.
      final handle = tester.ensureSemantics();
      await pumpHero(tester, withRoom: room(RoomStatus.matching));

      expect(find.bySemanticsLabel('러너0'), findsOneWidget);
      expect(find.bySemanticsLabel('러너1'), findsOneWidget);
      handle.dispose();
    });
  });

  group('확정', () {
    testWidgets('출발까지 세고 로비로 가는 문을 연다', (tester) async {
      await pumpHero(tester, withRoom: room(RoomStatus.matched, players: 3));

      expect(find.text(AppStrings.homeMatchConfirmedTitle), findsOneWidget);
      expect(find.text(AppStrings.homeMatchStartLabel), findsOneWidget);
      expect(find.text(AppStrings.homeMatchToWaitingRoom), findsOneWidget);
    });

    testWidgets('⚠️ 그 문이 실제로 열린다', (tester) async {
      // 글자가 있는지만 보면 **문을 통째로 막아도 초록이다**(직접 부숴
      // 확인했다). 확정된 방으로 들어가는 유일한 문이라 눌러서 본다.
      var entered = 0;
      await pumpHero(
        tester,
        withRoom: room(RoomStatus.matched, players: 3),
        onLobby: () => entered++,
      );

      await tester.tap(find.text(AppStrings.homeMatchToWaitingRoom));
      await tester.pumpAndSettle();

      expect(entered, 1, reason: '로비로 가는 문이 안 열린다');
    });

    testWidgets('⚠️ 함께 달릴 사람을 이름으로 보여준다', (tester) async {
      // 시안이 겹친 동그라미 대신 이름을 붙인 얼굴 셋을 둔다. 누가 함께
      // 달리는지가 이 카드의 요점이다.
      await pumpHero(tester, withRoom: room(RoomStatus.matched, players: 3));

      expect(find.text(AppStrings.homeMatchPartyLabel), findsOneWidget);
      expect(find.text('러너0'), findsOneWidget);
      expect(find.text('러너2'), findsOneWidget);
    });

    testWidgets('⚠️ 세 칸을 라벨과 함께 보여준다', (tester) async {
      await pumpHero(tester, withRoom: room(RoomStatus.matched, players: 3));

      expect(find.text(AppStrings.homeMatchStartAtLabel), findsOneWidget);
      expect(find.text(AppStrings.homeMatchDistanceLabel), findsOneWidget);
      expect(find.text(AppStrings.matchSlotTime(startAt)), findsOneWidget);
    });

    testWidgets('⚠️ 목표 거리를 모르면 지어내지 않는다', (tester) async {
      // 서버가 안 줄 수 있다. 0km 라고 적으면 목표가 달라 보인다.
      await pumpHero(tester, withRoom: room(RoomStatus.matched, players: 3));

      expect(find.text(AppStrings.homeMatchUnknownValue), findsOneWidget);
    });

    testWidgets('⚠️ 나 혼자인 방은 혼자 달린다고 알린다', (tester) async {
      // 서버는 마감 10분 전까지 상대를 못 찾으면 **그 방을 1인 러닝으로
      // 돌린다.** 확정 카드를 그리면 참여자 줄에 나 혼자 서 있고, 왜 그런지는
      // 아무 데도 안 적힌다.
      await pumpHero(
        tester,
        withRoom: room(RoomStatus.matched, players: 1),
        myUserId: 'u-0',
      );

      expect(find.text(AppStrings.homeMatchSoloTitle), findsOneWidget);
      expect(find.text(AppStrings.homeMatchConfirmedTitle), findsNothing);
    });

    testWidgets('⚠️ 명단을 모르는 것은 혼자가 아니다', (tester) async {
      // 스냅샷이 늦으면 `RoomInfo.fromStatus()`가 **빈 명단**으로 대타 방을
      // 세운다. 그걸 혼자로 읽으면 멀쩡한 4인 방에 이 화면이 뜬다.
      // (`RoomInfo.isAlone`이 `players.length <= 1`이라 그대로 쓰면 틀린다.)
      await pumpHero(
        tester,
        withRoom: room(RoomStatus.matched, players: 0),
        myUserId: 'u-0',
      );

      expect(find.text(AppStrings.homeMatchSoloTitle), findsNothing);
      expect(find.text(AppStrings.homeMatchConfirmedTitle), findsOneWidget);
    });

    testWidgets('⚠️ 남이 있으면 혼자가 아니다', (tester) async {
      await pumpHero(
        tester,
        withRoom: room(RoomStatus.matched, players: 2),
        myUserId: 'u-0',
      );

      expect(find.text(AppStrings.homeMatchSoloTitle), findsNothing);
    });

    testWidgets('⚠️ 혼자여도 들어갈 문은 열린다', (tester) async {
      // 예약한 시각에 달릴 방이다. 여기서 못 들어가면 러닝을 통째로 놓친다.
      var entered = 0;
      await pumpHero(
        tester,
        withRoom: room(RoomStatus.matched, players: 1),
        myUserId: 'u-0',
        onLobby: () => entered++,
      );

      await tester.tap(find.text(AppStrings.homeMatchToWaitingRoom));
      await tester.pumpAndSettle();

      expect(entered, 1);
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
