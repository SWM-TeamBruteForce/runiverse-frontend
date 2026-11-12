import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record/presentation/record_calendar.dart';
import 'package:runiverse/features/record/presentation/record_state.dart';

/// 기록 캘린더의 월 달력 — **좁은 폰에서도 뛴 날 점이 제 칸에 있는가.**
///
/// 칸은 폭의 1/7 정사각인데 원 40·간격 2·점 5는 47로 고정이다. 360dp 폰은
/// 칸이 41.1이라 점이 아랫줄로 5.9 넘쳐 아랫날 원에 가렸다(S23+ 384dp도 2.4).
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

  // 2026-11-01은 일요일이다. 5일(목)에 뛰었고, 바로 아래 칸인 12일을 골랐다.
  RecordData data() => RecordData(
    month: DateTime(2026, 11),
    selectedDay: DateTime(2026, 11, 12),
    monthRecords: [record(5)],
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

  Rect dot(WidgetTester tester, String day) => tester.getRect(sized(day, 5));

  testWidgets('넓은 폰에서는 칸이 정사각 그대로다', (tester) async {
    await pump(tester, screen: 412);

    expect(tester.takeException(), isNull);
    // (412 − 화면 여백 32 − 카드 여백 40) ÷ 7.
    final size = tester.getSize(cell('5'));
    expect(size.width, moreOrLessEquals(340 / 7));
    expect(size.height, moreOrLessEquals(340 / 7));
  });

  testWidgets('⚠️ 360dp 폰에서 날짜 칸이 넘치지 않는다', (tester) async {
    await pump(tester, screen: 360);

    expect(tester.takeException(), isNull);
    // 칸 폭 41.1은 그대로 두고 높이만 원·점을 쌓은 47로 늘린다.
    final size = tester.getSize(cell('5'));
    expect(size.width, moreOrLessEquals(288 / 7));
    expect(size.height, moreOrLessEquals(47));
    expect(
      dot(tester, '5').bottom,
      lessThanOrEqualTo(tester.getRect(cell('5')).bottom),
    );
  });

  testWidgets('⚠️ 뛴 날 점이 아랫날 원에 붙지 않는다', (tester) async {
    await pump(tester, screen: 360);

    // 줄 사이 8. 없으면 점과 아랫날 원이 맞닿는다.
    expect(
      tester.getRect(sized('12', 40)).top - dot(tester, '5').bottom,
      moreOrLessEquals(8),
    );
  });
}
