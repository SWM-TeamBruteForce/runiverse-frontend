import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/features/session/domain/party_board.dart';
import 'package:runiverse/features/session/domain/run_progress.dart';
import 'package:runiverse/features/session/presentation/run_party_view.dart';

/// 파티원 상태 화면 — **보드가 정한 것을 그대로 그리는가.**
///
/// 순서·격차·색 자리는 보드 테스트가 지킨다. 여기서는 그 결과가 카드에 빠짐없이
/// 나오는지, 그리고 목표를 모를 때 막대를 채우지 않는지만 본다.
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
    DateTime? now,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: RunPartyView(
          board: board,
          myPace: const Duration(minutes: 5, seconds: 38),
          targetDistanceMeters: target,
          now: now,
        ),
      ),
    ),
  );

  testWidgets('넷이 카드 하나씩으로 나온다', (tester) async {
    final board = const PartyBoard()
        .withRoster(everyone, myUserId: 'me-1')
        .withMyDistance(3200)
        .withProgress(progress('u-1', 3360, pace: 321))
        .withProgress(progress('u-2', 3240, pace: 333))
        .withProgress(progress('u-3', 3080, pace: 352))
        .withCombos(
          const RunCombo([
            ComboPeer(
              userId: 'u-1',
              gapMeters: 160,
              comboCount: 12,
              maxComboCount: 12,
            ),
            ComboPeer(
              userId: 'u-3',
              gapMeters: -120,
              comboCount: 0,
              maxComboCount: 3,
            ),
          ]),
        );
    await pump(tester, board);
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('김도윤'), findsOneWidget);
    expect(find.text('러너42'), findsOneWidget);
    expect(find.text(AppStrings.runPartyMe), findsOneWidget);
    expect(find.text('3.4'), findsOneWidget);
    expect(find.text('/ 5 km'), findsNWidgets(3));
    expect(find.text("5'21\""), findsOneWidget);
    expect(find.text("5'38\""), findsOneWidget);
    // 격차는 말로. 내 카드는 누구 곁인지와 콤보 수.
    expect(find.text(AppStrings.runPartyGapLine(160)), findsOneWidget);
    expect(find.text(AppStrings.runPartyBeside('김도윤')), findsOneWidget);
    expect(find.text(AppStrings.runPartyCombo(12)), findsNWidgets(2));
    // 넷째 카드는 테스트 화면 아래라 내려가서 본다.
    await tester.scrollUntilVisible(
      find.text(AppStrings.runPartyGapLine(-120)),
      AppSpacing.space10,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text(AppStrings.runPartyGapLine(-120)), findsOneWidget);
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

    expect(find.text(AppStrings.runPartyUnknown), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('⚠️ 목표를 모르면 막대를 채우지 않는다', (tester) async {
    final board = const PartyBoard()
        .withRoster(everyone.take(2).toList(), myUserId: 'me-1')
        .withProgress(progress('u-1', 1200));
    await pump(tester, board, target: null);

    // 거리 숫자는 그대로다. `/ 목표`만 없다.
    expect(find.text('1.2'), findsOneWidget);
    expect(find.text(AppStrings.runPartyUnitKm), findsNWidgets(2));
    expect(find.textContaining('/ '), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('⚠️ 통지가 끊긴 사람의 카드는 흐려진다', (tester) async {
    // 서버는 끊김을 알리지 않는다. 서버가 콤보 판정에서 빼는 것과 같은
    // 시간(19초)이 지나면 흐리게만 그린다 — 문구로 단정하지 않는다.
    final now = DateTime(2026, 9, 17, 19, 10);
    final board = const PartyBoard()
        .withRoster(everyone.take(3).toList(), myUserId: 'me-1')
        .withProgress(
          progress(
            'u-1',
            1200,
          ).stamped(now.subtract(const Duration(seconds: 30))),
        )
        .withProgress(
          progress(
            'u-2',
            1100,
          ).stamped(now.subtract(const Duration(seconds: 5))),
        );
    await pump(tester, board, now: now);

    final faded = find.byWidgetPredicate((w) => w is Opacity && w.opacity < 1);
    expect(faded, findsOneWidget);
    expect(
      find.descendant(of: faded, matching: find.text('김도윤')),
      findsOneWidget,
    );
  });

  testWidgets('콤보가 오르면 두 카드에 임팩트가 떴다가 배지로 앉는다', (tester) async {
    ComboPeer peer(int count) => ComboPeer(
      userId: 'u-1',
      gapMeters: 12,
      comboCount: count,
      maxComboCount: count,
    );
    final base = const PartyBoard()
        .withRoster(everyone.take(2).toList(), myUserId: 'me-1')
        .withProgress(progress('u-1', 1200));
    await pump(tester, base.withCombos(RunCombo([peer(11)])));
    expect(find.text(AppStrings.runPartyImpactCombo), findsNothing);

    // 12로 오른다 → 내 카드와 상대 카드 모두 `12 COMBO`.
    await pump(tester, base.withCombos(RunCombo([peer(12)])));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(AppStrings.runPartyImpactCombo), findsNWidgets(2));
    expect(find.text('12'), findsNWidgets(2));

    // 끝나면 덮개는 사라지고 배지에 12콤보가 남는다.
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.runPartyImpactCombo), findsNothing);
    expect(find.text(AppStrings.runPartyCombo(12)), findsNWidgets(2));

    // 같은 값이 다시 와도 튀지 않는다.
    await pump(tester, base.withCombos(RunCombo([peer(12)])));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(AppStrings.runPartyImpactCombo), findsNothing);
  });

  testWidgets('콤보가 끊기면 배지에 최고 기록만 남는다', (tester) async {
    final board = const PartyBoard()
        .withRoster(everyone.take(2).toList(), myUserId: 'me-1')
        .withProgress(progress('u-1', 1200))
        .withCombos(
          const RunCombo([
            ComboPeer(
              userId: 'u-1',
              gapMeters: 12,
              comboCount: 5,
              maxComboCount: 7,
            ),
          ]),
        )
        .withCombos(const RunCombo([]));
    await pump(tester, board);
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.runPartyBestCombo(7)), findsNWidgets(2));
    expect(find.text(AppStrings.runPartyComboHint), findsOneWidget);
  });

  testWidgets('⚠️ 아무도 없어도 내 카드는 남고 빈 문구가 붙는다', (tester) async {
    // 상대가 취소했거나 재시작 뒤 첫 통지가 오기 전. 내 기록은 계속 보인다.
    await pump(
      tester,
      const PartyBoard()
          .withRoster(const [], myUserId: 'me-1')
          .withMyDistance(1500),
    );

    // 이름을 모르니 제목도 아바타 이니셜도 `나`다.
    expect(find.text(AppStrings.runPartyMe), findsNWidgets(2));
    expect(find.text('1.5'), findsOneWidget);
    expect(find.text(AppStrings.runPartyEmpty), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
