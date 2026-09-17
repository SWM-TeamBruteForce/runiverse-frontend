import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/record/domain/run_detail.dart';
import 'package:runiverse/features/record/domain/split_aggregator.dart';
import 'package:runiverse/features/record/presentation/run_result_view.dart';

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

  RunDetail detail({bool solo = false}) => RunDetail(
    runningRoomId: 125,
    distanceMeters: 2000,
    duration: const Duration(minutes: 11),
    averagePace: const Duration(minutes: 5, seconds: 30),
    rawSplits: splitsOf(200, 3), // 2km, 10m당 3초 = 5'00"
    players: [
      const RunPlayerResult(userId: 'me-1', nickname: '러너42', isMe: true),
      if (!solo) ...[
        const RunPlayerResult(
          userId: 'u-1',
          nickname: '이서연',
          isMe: false,
          distanceMeters: 2000,
          duration: Duration(minutes: 12),
          averagePace: Duration(minutes: 6),
        ),
        const RunPlayerResult(userId: 'u-2', nickname: '박지훈', isMe: false),
      ],
    ],
    splitsByPlayer: solo ? const {} : {'u-1': splitsOf(200, 4)},
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

  testWidgets('칩을 누르면 격차의 기준이 그 사람으로 바뀐다', (tester) async {
    await pump(tester, detail());

    // 기준이 내 평균(5'30")일 때: 5'00"은 30초 빠르다.
    expect(find.text('-30s'), findsWidgets);

    await tester.tap(find.text('이서연').last);
    await tester.pump();

    // 기준이 이서연(10m당 4초 = 6'40")일 때: 100초 빠르다.
    expect(find.text('-100s'), findsWidgets);
    expect(find.text('-30s'), findsNothing);

    // 다시 누르면 내 평균으로 돌아온다.
    await tester.tap(find.text('이서연').last);
    await tester.pump();
    expect(find.text('-30s'), findsWidgets);
  });

  testWidgets('기록 없는 사람의 칩은 눌리지 않는다', (tester) async {
    await pump(tester, detail());

    await tester.tap(find.text('박지훈').last);
    await tester.pump();

    expect(find.text('-30s'), findsWidgets);
  });
}
