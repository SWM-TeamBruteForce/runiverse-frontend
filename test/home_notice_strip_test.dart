import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/home/domain/home_notice.dart';
import 'package:runiverse/features/home/presentation/home_notice_provider.dart';
import 'package:runiverse/features/home/presentation/home_notice_strip.dart';

void main() {
  const hold = Duration(seconds: 5);
  final notice = find.byType(HomeNoticeStrip);
  final lines = find.descendant(of: notice, matching: find.byType(Text));

  Future<void> pumpNotice(WidgetTester tester, ValueNotifier<bool> active) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [homeNoticeProvider.overrideWith(_SeededNotice.new)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: ValueListenableBuilder(
              valueListenable: active,
              child: const HomeNoticeStrip(),
              builder: (context, enabled, child) => TickerMode(
                enabled: enabled,
                child: Scaffold(
                  body: Align(alignment: Alignment.topLeft, child: child),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('5초 뒤 두 줄이 한 줄 간격을 유지하며 함께 올라간다', (tester) async {
    final active = ValueNotifier(true);
    addTearDown(active.dispose);
    await pumpNotice(tester, active);
    final first = tester.widget<Text>(lines).data!;
    final baseline = tester.getCenter(find.text(first)).dy;
    final lineHeight = tester.getSize(find.text(first)).height;

    const millisecond = Duration(milliseconds: 1);
    await tester.pump(hold - millisecond);
    expect(lines, findsOneWidget);
    expect(find.text(first), findsOneWidget);

    await tester.pump(millisecond);
    expect(lines, findsNWidgets(2));
    final next = tester.widget<Text>(lines.last).data!;
    for (var frame = 0; frame < 3; frame++) {
      await tester.pump(const Duration(milliseconds: 80));
      final outgoing = tester.getCenter(find.text(first)).dy;
      final incoming = tester.getCenter(find.text(next)).dy;
      expect(outgoing, lessThan(baseline));
      expect(incoming, greaterThan(baseline));
      expect(incoming - outgoing, closeTo(lineHeight, 0.1));
    }

    await tester.pump(const Duration(milliseconds: 81));
    expect(find.text(first), findsNothing);
    expect(tester.getCenter(find.text(next)).dy, baseline);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('탭에 돌아오면 이전 줄 없이 첫 공지에서 5초를 다시 센다', (tester) async {
    final active = ValueNotifier(true);
    addTearDown(active.dispose);
    await pumpNotice(tester, active);
    final first = tester.widget<Text>(lines).data!;
    final baseline = tester.getCenter(find.text(first)).dy;

    await tester.pump(hold);
    await tester.pump(const Duration(milliseconds: 100));
    expect(lines, findsNWidgets(2));
    active.value = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 8));

    active.value = true;
    await tester.pump();
    expect(lines, findsOneWidget);
    expect(tester.widget<Text>(lines).data, first);
    expect(tester.getCenter(find.text(first)).dy, baseline);

    const millisecond = Duration(milliseconds: 1);
    await tester.pump(hold - millisecond);
    expect(lines, findsOneWidget);
    expect(find.text(first), findsOneWidget);

    await tester.pump(millisecond);
    expect(lines, findsNWidgets(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _SeededNotice extends HomeNoticeController {
  @override
  HomeNoticeState build() => const HomeNoticeState(
    activity: HomeActivity(
      runningNowCount: 3,
      todayFinishedRuns: [],
      todayFinishedCount: 9,
      yesterdayFinishedCount: 0,
    ),
  );
}
