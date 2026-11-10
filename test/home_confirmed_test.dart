import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/widgets/v2/runner_avatar.dart';
import 'package:runiverse/features/home/presentation/home_confirmed.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';

/// 매칭 확정 카드의 참여자 줄 — **4명이 좁은 폰에서도 다 보이는가.**
///
/// 시안(`158:3102`)은 아바타 60·간격 20으로 3명을 그렸다. 4명이면 300이라
/// 360dp 폰의 카드 안쪽(296)에 안 들어간다. 이름 칸을 72로 두던 때는
/// 348이 돼 4번째 사람이 잘렸다(에뮬레이터 360dp에서 52px 넘침).
void main() {
  RoomInfo room(int players) => RoomInfo(
    runningRoomId: 125,
    status: RoomStatus.matched,
    scheduledStartAt: DateTime(2026, 9, 16, 19),
    players: [
      for (var i = 0; i < players; i++)
        RoomPlayer(userId: 'u-$i', nickname: '러너$i', isDeleted: false),
    ],
  );

  /// 폰 폭 [screen]에서 홈이 카드에 주는 폭(좌우 여백 16씩을 뺀 값)으로 띄운다.
  Future<void> pump(
    WidgetTester tester, {
    required double screen,
    int players = 4,
  }) async {
    tester.view.physicalSize = Size(screen * 2, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: screen - 32,
              child: HomeConfirmed(
                room: room(players),
                now: DateTime(2026, 9, 16, 18, 30),
                onLobby: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  Finder avatar(int index) => find.byType(RunnerAvatarV2).at(index);

  double centerGap(WidgetTester tester) =>
      tester.getCenter(avatar(1)).dx - tester.getCenter(avatar(0)).dx;

  testWidgets('넓은 폰에서는 시안 그대로다', (tester) async {
    await pump(tester, screen: 412);

    expect(tester.takeException(), isNull);
    expect(tester.getSize(avatar(0)), const Size(60, 60));
    // 아바타 60 + 간격 20.
    expect(centerGap(tester), moreOrLessEquals(80));
  });

  testWidgets('⚠️ 360dp 폰에서 4명이 넘치지 않는다', (tester) async {
    await pump(tester, screen: 360);

    expect(tester.takeException(), isNull);
    // (296 − 20×3) ÷ 4 = 59. 간격은 두고 아바타가 줄어든다.
    expect(tester.getSize(avatar(0)), const Size(59, 59));
    expect(centerGap(tester), moreOrLessEquals(79));
    expect(
      tester.getRect(avatar(3)).right,
      lessThanOrEqualTo(tester.getRect(find.byType(HomeConfirmed)).right),
    );
  });

  testWidgets('⚠️ 그보다 좁아도 넘치지 않는다', (tester) async {
    await pump(tester, screen: 320);

    expect(tester.takeException(), isNull);
    // (256 − 20×3) ÷ 4 = 49.
    expect(tester.getSize(avatar(0)), const Size(49, 49));
  });

  testWidgets('3명은 360dp에서도 줄지 않는다', (tester) async {
    await pump(tester, screen: 360, players: 3);

    expect(tester.getSize(avatar(0)), const Size(60, 60));
    expect(centerGap(tester), moreOrLessEquals(80));
  });
}
