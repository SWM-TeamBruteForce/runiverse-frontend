import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/profile/presentation/profile_stat_row.dart';

/// 프로필에서 친구로 들어가는 자리 — 시안 `85:2882`의 **팔로워 자리**.
///
/// ## ⚠️ 빨간 숫자는 첫 페이지만 센 값이다
///
/// 받은 요청 수를 주는 API가 따로 없다. 프로필을 열 때 친구 목록 첫 장
/// (`limit=20`)을 받아 센다. 서버가 받은 요청을 맨 앞에 두므로 대개 맞지만,
/// 20개가 꽉 차면 그보다 많다는 뜻이라 `20+`로 적는다.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required int friendCount,
    int received = 0,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: ProfileStatRow(
          friendCount: friendCount,
          receivedCount: received,
          onTap: () {},
        ),
      ),
    ),
  );

  testWidgets('친구 수가 프로필에 뜬다', (tester) async {
    await pump(tester, friendCount: 12);

    expect(find.text(AppStrings.friendProfileEntry(12)), findsOneWidget);
  });

  testWidgets('⚠️ 받은 요청이 있으면 빨간 숫자가 붙는다', (tester) async {
    // 요청이 왔다는 것을 알 통로가 지금은 이것뿐이다.
    await pump(tester, friendCount: 12, received: 2);

    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('받은 요청이 없으면 숫자가 없다', (tester) async {
    await pump(tester, friendCount: 12);

    expect(find.text('0'), findsNothing);
  });

  testWidgets('⚠️ 20개를 채우면 20+ 로 적는다', (tester) async {
    // 첫 페이지만 세기 때문이다. 그보다 많으면 정확한 수에 뜻이 없다.
    await pump(tester, friendCount: 30, received: 20);

    expect(find.text(AppStrings.friendBadgeOverflow), findsOneWidget);
    expect(find.text('20'), findsNothing);
  });

  testWidgets('업적 줄은 준비중이고 눌리지 않는다', (tester) async {
    await pump(tester, friendCount: 0);

    expect(find.text(AppStrings.friendAchievement), findsOneWidget);
    expect(find.text(AppStrings.friendAchievementSoon), findsOneWidget);
    expect(find.text(AppStrings.friendAchievementTitle), findsOneWidget);
  });
}
