import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/features/session/domain/party_board.dart';
import 'package:runiverse/features/session/domain/run_progress.dart';
import 'package:runiverse/features/session/presentation/run_party_view.dart';

/// 파티원 비교 화면 — **보드가 정한 것을 그대로 그리는가.**
///
/// 순서·격차·색 자리는 보드 테스트가 지킨다. 여기서는 그 결과가 화면에 빠짐없이
/// 나오는지, 그리고 목표를 모를 때 막대를 그리지 않는지만 본다.
void main() {
  const everyone = [
    PartyMember(userId: 'me-1', nickname: '러너42'),
    PartyMember(userId: 'u-1', nickname: '김도윤'),
    PartyMember(userId: 'u-2', nickname: '이서연'),
    PartyMember(userId: 'u-3', nickname: '박지훈'),
  ];

  RunProgress progress(String userId, int meters, {int? pace}) => RunProgress(
    userId: userId,
    distanceMeters: meters,
    targetDistanceMeters: 5000,
    currentPaceSecondsPerKm: pace,
  );

  Future<void> pump(
    WidgetTester tester,
    PartyBoard board, {
    int? target = 5000,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: RunPartyView(
          board: board,
          myPace: const Duration(minutes: 5, seconds: 38),
          targetDistanceMeters: target,
        ),
      ),
    ),
  );

  testWidgets('넷이 레인과 표에 한 번씩 나온다', (tester) async {
    final board = const PartyBoard()
        .withRoster(everyone, myUserId: 'me-1')
        .withMyDistance(3200)
        .withProgress(progress('u-1', 3360, pace: 321))
        .withProgress(progress('u-2', 3240, pace: 333))
        .withProgress(progress('u-3', 3080, pace: 352));
    await pump(tester, board);
    await tester.pump(const Duration(seconds: 1));

    // 레인의 이름 + 표의 이름 = 둘씩. 내 이름도 닉네임이고, `나`는 머리와
    // 표의 아바타 안에만 들어간다(정본).
    expect(find.text('김도윤'), findsNWidgets(2));
    expect(find.text('러너42'), findsNWidgets(2));
    expect(find.text(AppStrings.runPartyMe), findsNWidgets(2));
    expect(find.text('3.36'), findsOneWidget);
    expect(find.text("5'21\""), findsOneWidget);
    expect(find.text("5'38\""), findsOneWidget);
    // 격차: 앞선 사람은 +, 뒤진 사람은 -.
    expect(find.text('+160m'), findsOneWidget);
    expect(find.text('-120m'), findsOneWidget);
    // 눈금 0~5.
    expect(find.text('5'), findsOneWidget);
    // 꼬리말은 목록 아래라 테스트 화면 밖이다. 내려가서 본다.
    await tester.scrollUntilVisible(
      find.text(AppStrings.runPartyFooter),
      AppSpacing.space10,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text(AppStrings.runPartyFooter), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('페이스를 모르면 자리만 비운다', (tester) async {
    final board = const PartyBoard()
        .withRoster(everyone.take(2).toList(), myUserId: 'me-1')
        .withProgress(progress('u-1', 1200));
    await pump(tester, board);

    expect(find.text("--'--\""), findsOneWidget);
  });

  testWidgets('이름을 모르는 사람도 그린다', (tester) async {
    // 러닝 중 재시작하면 명단이 비어 있다.
    final board = const PartyBoard().withProgress(progress('u-9', 800));
    await pump(tester, board);

    expect(find.text(AppStrings.runPartyUnknown), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('⚠️ 목표를 모르면 막대와 눈금을 그리지 않는다', (tester) async {
    final board = const PartyBoard()
        .withRoster(everyone.take(2).toList(), myUserId: 'me-1')
        .withProgress(progress('u-1', 1200));
    await pump(tester, board, target: null);

    // 표는 그대로다. 눈금 숫자만 없다.
    expect(find.text('1.20'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('아무도 없으면 빈 문구다', (tester) async {
    await pump(tester, const PartyBoard());

    expect(find.text(AppStrings.runPartyEmpty), findsOneWidget);
    expect(find.text(AppStrings.runPartyFooter), findsNothing);
  });
}
