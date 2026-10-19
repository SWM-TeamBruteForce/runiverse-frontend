import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/record/domain/run_detail.dart';
import 'package:runiverse/features/record/domain/split_aggregator.dart';
import 'package:runiverse/features/record/presentation/run_result_view.dart';
import 'package:runiverse/features/record/presentation/split_line_chart.dart';

/// 러닝 결과의 그래프 — **읽을 수 있는 자로 그리는가.**
///
/// 여기서 보는 것은 선의 모양이 아니라 **축에 적힌 말**이다. 50m 표본은 점이
/// 수십 개라 x축을 개수로 솎으면 `0.65km` 같은 어중간한 거리가 나온다.
void main() {
  /// 10m 구간 [count]개. [cadence]를 주면 그 값으로 채운다.
  List<RawSplit> splitsOf(int count, int secondsEach, {int? cadence}) => [
    for (var i = 0; i < count; i++)
      RawSplit(
        startDistanceMeters: i * 10,
        endDistanceMeters: (i + 1) * 10,
        duration: Duration(seconds: secondsEach),
        cadenceSpm: cadence,
        caloriesKcal: 1,
      ),
  ];

  RunDetail detail({required int meters, int? cadence = 170}) => RunDetail(
    runningRoomId: 125,
    distanceMeters: meters,
    duration: Duration(seconds: meters ~/ 10 * 3),
    averagePace: const Duration(minutes: 5),
    rawSplits: splitsOf(meters ~/ 10, 3, cadence: cadence),
  );

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
    await tester.pumpAndSettle();
  }

  /// 제목이 [title]인 그래프 안에서만 찾는다.
  ///
  /// 바깥에도 같은 글자가 있다 — 1km 그래프와 구간 표가 `1km`를 적는다.
  Finder inChart(String title, String text) => find.descendant(
    of: find.ancestor(
      of: find.text(title),
      matching: find.byType(SplitLineChart),
    ),
    matching: find.text(text),
  );

  group('50m 그래프의 x축', () {
    testWidgets('⚠️ 딱 떨어지는 거리에 찍는다', (tester) async {
      // 2km면 50m 표본이 40개다. 개수로 솎으면 여덟씩 세어 첫 점
      // `0.05km`부터 `0.45 · 0.85 · 1.25km`가 나왔다.
      await pump(tester, detail(meters: 2000));

      const title = AppStrings.runResultPaceDetailChart;
      expect(inChart(title, '0.5km'), findsOneWidget);
      expect(inChart(title, '1km'), findsOneWidget);
      expect(inChart(title, '1.5km'), findsOneWidget);
      expect(inChart(title, '2km'), findsOneWidget);

      expect(inChart(title, '0.05km'), findsNothing);
      expect(inChart(title, '0.45km'), findsNothing);
      expect(inChart(title, '1.25km'), findsNothing);
    });

    testWidgets('⚠️ 길어지면 간격을 성기게 잡는다', (tester) async {
      // 0.5km마다 두면 3km에 라벨이 여섯 개가 되어 12px 글자끼리 닿는다.
      await pump(tester, detail(meters: 3000));

      const title = AppStrings.runResultPaceDetailChart;
      expect(inChart(title, '1km'), findsOneWidget);
      expect(inChart(title, '2km'), findsOneWidget);
      expect(inChart(title, '3km'), findsOneWidget);
      expect(inChart(title, '0.5km'), findsNothing);
    });

    testWidgets('마지막 점은 딱 떨어지지 않아도 찍는다', (tester) async {
      // 총 거리를 읽는 자리다.
      await pump(tester, detail(meters: 2150));

      expect(
        inChart(AppStrings.runResultPaceDetailChart, '2.15km'),
        findsOneWidget,
      );
    });

    testWidgets('케이던스 그래프도 같은 자를 쓴다', (tester) async {
      // 위아래로 붙어 있는데 축이 다르면 같은 러닝이 서로 다른 얘기를 한다.
      await pump(tester, detail(meters: 2000));

      const title = AppStrings.runResultCadenceDetailChart;
      expect(inChart(title, '0.5km'), findsOneWidget);
      expect(inChart(title, '0.05km'), findsNothing);
    });
  });
}
