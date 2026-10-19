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
  ///
  /// [gap]이면 1000~1050m를 통째로 비운다 — 걸음 센서가 그 구간을 놓친 경우다.
  /// **50m 묶음 하나를 다 비워야** 한다. 10m 하나만 비우면 나머지 넷의
  /// 가중평균이 들어차 그래프에는 구멍이 생기지 않는다.
  List<RawSplit> splitsOf(
    int count,
    int secondsEach, {
    int? cadence,
    bool gap = false,
  }) => [
    for (var i = 0; i < count; i++)
      RawSplit(
        startDistanceMeters: i * 10,
        endDistanceMeters: (i + 1) * 10,
        duration: Duration(seconds: secondsEach),
        cadenceSpm: gap && i >= 100 && i < 105 ? null : cadence,
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

  /// 나와 이서연 둘이 달린 2km. 둘 다 케이던스를 안다.
  RunDetail party({bool gap = false}) => RunDetail(
    runningRoomId: 125,
    distanceMeters: 2000,
    duration: const Duration(minutes: 11),
    averagePace: const Duration(minutes: 5, seconds: 30),
    rawSplits: splitsOf(200, 3, cadence: 170, gap: gap),
    players: const [
      RunPlayerResult(userId: 'me-1', nickname: '러너42', isMe: true),
      RunPlayerResult(
        userId: 'u-1',
        nickname: '이서연',
        isMe: false,
        distanceMeters: 2000,
        duration: Duration(minutes: 12),
        averagePace: Duration(minutes: 6),
      ),
    ],
    splitsByPlayer: {'u-1': splitsOf(200, 4, cadence: 168)},
  );

  Future<void> pump(WidgetTester tester, RunDetail value) async {
    tester.view.physicalSize = const Size(1080, 6000);
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

  /// 케이던스 비교 — **페이스와 같은 사람을 겹치는가.**
  ///
  /// 서버는 구간마다 파티원 케이던스를 주고 앱도 50m로 묶어 두는데,
  /// 케이던스 그래프에만 그 값을 넘기지 않았다.
  group('케이던스 비교', () {
    const title = AppStrings.runResultCadenceDetailChart;

    SplitLineChart cadenceChart(WidgetTester tester) =>
        tester.widget<SplitLineChart>(
          find.ancestor(
            of: find.text(title),
            matching: find.byType(SplitLineChart),
          ),
        );

    /// 칩은 `InkWell`이다. 이름만으로 찾으면 비교 카드의 글자가 먼저 걸린다.
    Future<void> choose(WidgetTester tester, String name) async {
      await tester.tap(find.widgetWithText(InkWell, name));
      await tester.pumpAndSettle();
    }

    testWidgets('⚠️ 칩으로 고른 사람이 케이던스에도 겹친다', (tester) async {
      await pump(tester, party());
      expect(cadenceChart(tester).secondary, isNull);

      await choose(tester, '이서연');

      // 10m당 4초로 달린 이서연의 값이다.
      expect(cadenceChart(tester).secondary, equals(List.filled(40, 168.0)));
    });

    testWidgets('⚠️ 색 칩이 두 선의 주인을 밝힌다', (tester) async {
      await pump(tester, party());
      expect(inChart(title, '이서연'), findsNothing);

      await choose(tester, '이서연');

      expect(inChart(title, AppStrings.runPartyMe), findsOneWidget);
      expect(inChart(title, '이서연'), findsOneWidget);
    });

    testWidgets('⚠️ 모르는 구간은 0이 아니라 비운다', (tester) async {
      // 0으로 바꿔 그리면 선이 바닥까지 떨어져 "그때 멈췄다"로 읽힌다.
      await pump(tester, party(gap: true));

      final values = cadenceChart(tester).values;
      expect(values[20], isNull, reason: '1000~1050m는 센서가 놓쳤다');
      expect(values, isNot(contains(0.0)));
      expect(values.whereType<double>(), everyElement(170.0));
    });
  });
}
