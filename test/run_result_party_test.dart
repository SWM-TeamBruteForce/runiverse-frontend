import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/run_palette.dart';
import 'package:runiverse/features/record/domain/run_detail.dart';
import 'package:runiverse/features/record/domain/split_aggregator.dart';
import 'package:runiverse/features/record/presentation/run_result_view.dart';
import 'package:runiverse/features/record/presentation/split_line_chart.dart';

/// 러닝 결과의 파티원 비교 — **카드가 뜨고, 칩으로 한 명을 겹쳐 보는가.**
///
/// 지도는 SDK 키가 없어 안내로 대신 그려지므로 위젯 테스트가 가능하다.
void main() {
  List<RawSplit> splitsOf(int count, int secondsEach) => [
    for (var i = 0; i < count; i++)
      RawSplit(
        startDistanceMeters: i * 10,
        endDistanceMeters: (i + 1) * 10,
        duration: Duration(seconds: secondsEach),
        caloriesKcal: 1,
      ),
  ];

  const me = RunPlayerResult(userId: 'me-1', nickname: '러너42', isMe: true);
  const seoyeon = RunPlayerResult(
    userId: 'u-1',
    nickname: '이서연',
    isMe: false,
    distanceMeters: 2000,
    duration: Duration(minutes: 12),
    averagePace: Duration(minutes: 6),
  );
  const jihun = RunPlayerResult(userId: 'u-2', nickname: '박지훈', isMe: false);

  /// [meLast]면 명단의 **끝**에 내가 선다 — 레인 색이 첫 자리가 아니게 된다.
  /// [noMe]면 명단에 내가 아예 없다(서버가 빠뜨린 경우).
  /// [noPartySplits]면 명단에는 기록이 있는데 구간만 안 왔다.
  RunDetail detail({
    bool solo = false,
    bool meLast = false,
    bool noMe = false,
    bool noPartySplits = false,
  }) {
    final others = solo ? const <RunPlayerResult>[] : [seoyeon, jihun];
    return RunDetail(
      runningRoomId: 125,
      distanceMeters: 2000,
      duration: const Duration(minutes: 11),
      averagePace: const Duration(minutes: 5, seconds: 30),
      rawSplits: splitsOf(200, 3), // 2km, 10m당 3초 = 5'00"
      players: [if (!noMe && !meLast) me, ...others, if (!noMe && meLast) me],
      splitsByPlayer: solo || noPartySplits
          ? const {}
          : {'u-1': splitsOf(200, 4)},
    );
  }

  Future<void> pump(WidgetTester tester, RunDetail value) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: RunResultView(detail: value),
      ),
    );
  }

  testWidgets('파티원이 있으면 비교 카드가 뜬다', (tester) async {
    await pump(tester, detail());

    expect(find.text(AppStrings.runResultPartyTitle), findsOneWidget);
    // 카드와 칩에 한 번씩.
    expect(find.text('이서연'), findsNWidgets(2));
    expect(find.text("6'00\""), findsOneWidget);
    // 기록 없는 사람은 0이 아니라 없다.
    expect(find.text(AppStrings.runResultNoRecord), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('솔로는 카드도 칩도 없다', (tester) async {
    await pump(tester, detail(solo: true));

    expect(find.text(AppStrings.runResultPartyTitle), findsNothing);
    expect(find.text(AppStrings.runResultCompareHint), findsNothing);
  });

  testWidgets('칩을 누르면 그 사람 대비 격차가 뜬다', (tester) async {
    await pump(tester, detail());

    await tester.tap(find.text('이서연').last);
    await tester.pump();

    // 기준이 이서연(10m당 4초 = 6'40")일 때: 100초 빠르다.
    expect(find.text('-100s'), findsWidgets);

    // 다시 누르면 기준이 사라져 차이도 걷힌다.
    await tester.tap(find.text('이서연').last);
    await tester.pump();
    expect(find.text('-100s'), findsNothing);
  });

  testWidgets('기록 없는 사람의 칩은 눌리지 않는다', (tester) async {
    await pump(tester, detail());

    await tester.tap(find.text('박지훈').last);
    await tester.pump();

    expect(find.text(AppStrings.runResultGapBaseParty), findsNothing);
  });

  /// 차이 값 — **파티원을 골랐을 때만, 무엇 대비인지 적고 뜨는가.**
  ///
  /// 전에는 혼자 볼 때도 내 평균 대비로 떴다. 첫 구간부터 숫자가 붙어 있어
  /// **직전 구간과의 차이로 읽혔다** — 읽히는 뜻이 틀리면 없느니만 못하다.
  group('차이의 기준', () {
    /// 표에 그려진 차이 값. 하나도 없으면 비어 있다.
    Finder gaps() => find.textContaining(RegExp(r'^[+-]?\d+s$'));

    testWidgets('⚠️ 아무도 안 고르면 차이를 그리지 않는다', (tester) async {
      await pump(tester, detail());

      expect(gaps(), findsNothing);
      expect(find.text(AppStrings.runResultGapBaseParty), findsNothing);
    });

    testWidgets('⚠️ 칩을 고르면 차이와 기준이 함께 뜬다', (tester) async {
      await pump(tester, detail());

      await tester.tap(find.text('이서연').last);
      await tester.pump();

      expect(gaps(), findsWidgets);
      expect(find.text(AppStrings.runResultGapBaseParty), findsOneWidget);
    });

    testWidgets('⚠️ 골라도 상대 구간이 없으면 아무것도 뜨지 않는다', (tester) async {
      // 잴 것이 하나도 없는 상태다. 고른 것만 보고 적으면 **머리줄이
      // 거짓말을 한다.**
      await pump(tester, detail(noPartySplits: true));

      await tester.tap(find.text('이서연').last);
      await tester.pump();

      expect(gaps(), findsNothing);
      expect(find.text(AppStrings.runResultGapBaseParty), findsNothing);
    });

    testWidgets('닉네임은 머리줄에 넣지 않는다', (tester) async {
      // 긴 닉네임이 들어오면 머리줄이 밀린다. 누구를 골랐는지는 칩이 말한다.
      await pump(tester, detail());

      await tester.tap(find.text('이서연').last);
      await tester.pump();

      // 카드와 칩에 한 번씩 — 머리줄에는 늘지 않았다.
      expect(find.text('이서연'), findsNWidgets(2));
    });
  });

  /// 참가자 색 — **나는 파랑 고정인가.**
  ///
  /// `lane(0)`(브랜드 파랑)은 내 자리다. 전에는 명단 자리 번호를 그대로 써서
  /// **내가 명단 둘째면 첫 자리 상대가 내 파랑을 가져갔다.**
  group('참가자 색', () {
    /// 화면이 그리는 모든 꺾은선의 내 선 색.
    List<Color> lineColors(WidgetTester tester) => [
      for (final chart in tester.widgetList<SplitLineChart>(
        find.byType(SplitLineChart),
      ))
        chart.color,
    ];

    final blue = RunPaletteV2.lane(0);

    testWidgets('⚠️ 명단 어디에 서도 내 선은 파랑이다', (tester) async {
      // 명단 끝에 세운다. 자리 번호를 쓰면 `lane(2)`(분홍)가 나온다.
      await pump(tester, detail(meLast: true));

      expect(lineColors(tester), isNotEmpty);
      expect(lineColors(tester), everyElement(blue));
    });

    testWidgets('⚠️ 파티원이 내 파랑을 가져가지 않는다', (tester) async {
      // 명단 첫 자리가 이서연이다. 자리 번호를 쓰면 그 사람이 `lane(0)`이다.
      await pump(tester, detail(meLast: true));

      await tester.tap(find.text('이서연').last);
      await tester.pump();

      final chart = tester.widget<SplitLineChart>(
        find.byType(SplitLineChart).first,
      );
      expect(chart.color, blue);
      expect(chart.secondaryColor, isNotNull);
      expect(chart.secondaryColor, isNot(blue));
    });

    testWidgets('⚠️ 명단에 내가 없어도 파랑이다', (tester) async {
      // 서버가 나를 빠뜨린 경우다. 이때도 파티원은 파랑을 못 가져간다.
      await pump(tester, detail(noMe: true));

      expect(lineColors(tester), everyElement(blue));

      await tester.tap(find.text('이서연').last);
      await tester.pump();

      final chart = tester.widget<SplitLineChart>(
        find.byType(SplitLineChart).first,
      );
      expect(chart.secondaryColor, isNot(blue));
    });

    testWidgets('내 색은 테마의 primary와 같은 값이다', (tester) async {
      // 두 값이 갈리면 화면마다 내 색이 달라진다.
      await pump(tester, detail());

      final primary = tester
          .element(find.byType(RunResultView))
          .appColorsV2
          .primary;
      expect(blue, primary);
    });
  });
}
