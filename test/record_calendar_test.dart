import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record/presentation/record_calendar.dart';
import 'package:runiverse/features/record/presentation/record_state.dart';

/// 기록 캘린더의 월 달력 — **좁은 폰에서도 뛴 날 점이 제 칸에 있는가.**
///
/// 칸은 폭의 1/7 정사각이다. 점을 원(40) 아래에 따로 쌓던 때는 내용이 47이라
/// 360dp 폰(칸 41.1)에서 점이 아랫줄로 5.9 넘쳐 아랫날 원에 가렸다(S23+
/// 384dp도 2.4). 지금은 점이 원 안, 숫자 바로 밑에 있다.
void main() {
  RunRecord record(int day) => RunRecord(
    id: day,
    runningRoomId: day,
    startedAt: DateTime(2026, 11, day, 7),
    distanceMeters: 5000,
    duration: const Duration(minutes: 30),
    averagePace: const Duration(minutes: 6),
    playerCount: 1,
  );

  final week = [for (var day = 9; day <= 15; day++) DateTime(2026, 11, day)];

  // 2026-11-01은 일요일이다. 5일(목)과 바로 아래 칸인 12일에 뛰었고, 12일을
  // 골랐다.
  RecordData data() => RecordData(
    month: DateTime(2026, 11),
    selectedDay: DateTime(2026, 11, 12),
    monthRecords: [record(5), record(12)],
    rangeRecords: const [],
    weekDays: week,
    stripDays: week,
  );

  /// 폰 폭 [screen]에서 기록 화면처럼 좌우 16씩 띄우고 달력을 편다.
  Future<void> pump(WidgetTester tester, {required double screen}) async {
    tester.view.physicalSize = Size(screen * 2, 2000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              RecordCalendar(
                data: data(),
                onSelect: (_) {},
                onMoveMonth: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip(AppStrings.recordCalendarExpand));
    await tester.pump();
  }

  /// [day]일 칸. 칸의 맨 바깥이 누르는 자리다.
  Finder cell(String day) => find
      .ancestor(of: find.text(day), matching: find.byType(GestureDetector))
      .first;

  Finder sized(String day, double size) => find.descendant(
    of: cell(day),
    matching: find.byWidgetPredicate(
      (w) => w is SizedBox && w.width == size && w.height == size,
    ),
  );

  testWidgets('넓은 폰에서는 칸이 정사각 그대로다', (tester) async {
    await pump(tester, screen: 412);

    expect(tester.takeException(), isNull);
    // (412 − 화면 여백 32 − 카드 여백 40) ÷ 7.
    final size = tester.getSize(cell('5'));
    expect(size.width, moreOrLessEquals(340 / 7));
    expect(size.height, moreOrLessEquals(340 / 7));
  });

  testWidgets('⚠️ 360dp 폰에서도 칸이 정사각이고 점이 제 원 안에 있다', (tester) async {
    await pump(tester, screen: 360);

    expect(tester.takeException(), isNull);
    final size = tester.getSize(cell('5'));
    expect(size.width, moreOrLessEquals(288 / 7));
    expect(size.height, moreOrLessEquals(288 / 7));

    final circle = tester.getRect(sized('5', 40));
    final dot = tester.getRect(sized('5', 5));
    expect(dot.top, greaterThanOrEqualTo(circle.top));
    expect(dot.bottom, lessThanOrEqualTo(circle.bottom));
  });

  testWidgets('⚠️ 352dp보다 좁으면 원 높이만큼만 늘린다', (tester) async {
    await pump(tester, screen: 320);

    expect(tester.takeException(), isNull);
    // 칸 폭 (320 − 72) ÷ 7 = 35.4는 원(40)보다 좁다.
    expect(tester.getSize(cell('5')).height, moreOrLessEquals(40));
  });

  testWidgets('⚠️ 고른 날에는 점을 그리지 않는다', (tester) async {
    // 아래 목록이 그날 기록을 보여 주고, 채운 원 위의 같은 색 점은 보이지
    // 않는다.
    await pump(tester, screen: 412);

    expect(sized('12', 5), findsNothing);
    expect(sized('5', 5), findsOneWidget);
  });
}
