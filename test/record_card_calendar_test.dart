import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';
import 'package:runiverse/features/record_card/presentation/day_cards_sheet.dart';
import 'package:runiverse/features/record_card/presentation/record_card_calendar.dart';
import 'package:runiverse/features/record_card/presentation/record_card_cell.dart';
import 'package:runiverse/features/record_card/presentation/record_card_state.dart';

RecordCard _card({
  required int id,
  required DateTime startedAt,
  RecordCardActivity activity = RecordCardActivity.daily,
}) => RecordCard(
  id: id,
  runningRecordId: id + 100,
  startedAt: startedAt,
  activity: activity,
  visibility: RecordCardVisibility.friends,
  reviewText: '회고 $id',
  photos: const [],
  route: RouteArt.empty,
  distanceMeters: 5000,
  duration: const Duration(minutes: 30),
  averagePace: const Duration(minutes: 6),
  runners: const [],
);

RecordCardData _data({
  List<RecordCard>? cards,
  RecordCardActivity? filter,
  CalendarZoom zoom = CalendarZoom.month,
  bool atOldest = false,
}) => RecordCardData(
  atOldest: atOldest,
  months: [
    MonthCards(
      month: DateTime(2026, 9),
      cards:
          cards ??
          [
            _card(id: 7, startedAt: DateTime(2026, 9, 7, 8)),
            _card(id: 11, startedAt: DateTime(2026, 9, 11, 8)),
            _card(id: 12, startedAt: DateTime(2026, 9, 11, 20)),
          ],
    ),
  ],
  filter: filter,
  zoom: zoom,
);

Future<void> _pump(
  WidgetTester tester, {
  RecordCardData? data,
  ValueChanged<RecordCard>? onOpen,
  ValueChanged<DateTime>? onEmptyDay,
  bool light = false,
}) => tester.pumpWidget(
  MaterialApp(
    theme: light ? AppTheme.light() : AppTheme.dark(),
    home: Scaffold(
      body: RecordCardCalendar(
        data: data ?? _data(),
        onOpen: onOpen ?? (_) {},
        onEmptyDay: onEmptyDay ?? (_) {},
        onZoom: (_) {},
        onLoadOlder: () {},
      ),
    ),
  ),
);

void main() {
  group('leadingBlanks', () {
    test('⚠️ 1일이 그 달의 요일 자리에서 시작한다', () {
      // 2026-09-01은 화요일이다. 일요일부터 세면 앞에 두 칸이 빈다.
      expect(leadingBlanks(DateTime(2026, 9)), 2);
      // 2026-11-01은 일요일이다. 앞이 비지 않는다.
      expect(leadingBlanks(DateTime(2026, 11)), 0);
      // 2026-08-01은 토요일이다. 앞에 여섯 칸이 빈다.
      expect(leadingBlanks(DateTime(2026, 8)), 6);
    });
  });

  testWidgets('달 머리에 달 이름과 카드 수가 선다', (tester) async {
    await _pump(tester);

    expect(find.text(AppStrings.recordMonthLabel(DateTime(2026, 9))), findsOne);
    expect(find.text(AppStrings.recordCardMonthCount(3)), findsOne);
  });

  testWidgets('요일 머리가 있다', (tester) async {
    await _pump(tester);

    for (final label in AppStrings.recordWeekdays) {
      expect(find.text(label), findsWidgets);
    }
  });

  testWidgets('그 달의 날 수만큼 칸이 선다', (tester) async {
    await _pump(tester);

    // 2026년 9월은 30일이다.
    expect(find.byType(RecordCardCell), findsNWidgets(30));
  });

  testWidgets('⚠️ 분기 보기에서는 날짜 숫자도 요일 머리도 없다 — 칸이 작다', (tester) async {
    await _pump(tester, data: _data(zoom: CalendarZoom.quarter));

    expect(find.text('7'), findsNothing);
    expect(find.text(AppStrings.recordWeekdays.first), findsNothing);
    expect(find.byType(RecordCardCell), findsNWidgets(30));
  });

  testWidgets('카드가 하나인 날을 누르면 바로 그 카드가 열린다', (tester) async {
    RecordCard? opened;
    await _pump(tester, onOpen: (card) => opened = card);

    await tester.tap(
      find.bySemanticsLabel(
        AppStrings.recordCardCellSemantics(day: DateTime(2026, 9, 7), count: 1),
      ),
    );
    await tester.pumpAndSettle();

    expect(opened?.id, 7);
    expect(find.byType(DayCardsSheet), findsNothing);
  });

  testWidgets('⚠️ 카드가 둘인 날을 누르면 시트가 뜬다 — 두 번째가 갇히면 안 된다', (tester) async {
    RecordCard? opened;
    await _pump(tester, onOpen: (card) => opened = card);

    await tester.tap(
      find.bySemanticsLabel(
        AppStrings.recordCardCellSemantics(
          day: DateTime(2026, 9, 11),
          count: 2,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DayCardsSheet), findsOne);
    expect(opened, isNull);
    expect(
      find.text(AppStrings.recordCardDaySheetTitle(DateTime(2026, 9, 11))),
      findsOne,
    );
  });

  testWidgets('시트에서 한 장을 고르면 그 카드가 열린다', (tester) async {
    RecordCard? opened;
    await _pump(tester, onOpen: (card) => opened = card);

    await tester.tap(
      find.bySemanticsLabel(
        AppStrings.recordCardCellSemantics(
          day: DateTime(2026, 9, 11),
          count: 2,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(AppStrings.recordCardStartedAt(DateTime(2026, 9, 11, 20))),
    );
    await tester.pumpAndSettle();

    expect(opened?.id, 12);
  });

  testWidgets('빈 날을 누르면 onEmptyDay가 그 날짜로 불린다', (tester) async {
    DateTime? empty;
    await _pump(tester, onEmptyDay: (day) => empty = day);

    await tester.tap(
      find.bySemanticsLabel(
        AppStrings.recordCardCellSemantics(day: DateTime(2026, 9, 3), count: 0),
      ),
    );
    await tester.pumpAndSettle();

    expect(empty, DateTime(2026, 9, 3));
  });

  testWidgets('⚠️ 필터로 0장이 된 달도 머리와 칸이 남는다', (tester) async {
    await _pump(tester, data: _data(filter: RecordCardActivity.race));

    expect(find.text(AppStrings.recordCardMonthCount(0)), findsOne);
    expect(find.byType(RecordCardCell), findsNWidgets(30));
  });

  testWidgets('⚠️ 스크롤할 것이 없어도 과거를 더 받을 길이 있다', (tester) async {
    // 안드로이드에서는 스크롤할 것이 없으면 ScrollUpdateNotification 자체가
    // 나오지 않는다. 그것만 방아쇠로 두면 과거 카드에 닿을 길이 앱 안에 없다.
    var asked = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: RecordCardCalendar(
            data: _data(),
            onOpen: (_) {},
            onEmptyDay: (_) {},
            onZoom: (_) {},
            onLoadOlder: () => asked++,
          ),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text(AppStrings.recordCardLoadOlder),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text(AppStrings.recordCardLoadOlder));
    await tester.pump();

    expect(asked, 1);
  });

  testWidgets('⚠️ 더 과거가 없으면 버튼 대신 그 사실을 알린다', (tester) async {
    await _pump(tester, data: _data(atOldest: true));

    await tester.scrollUntilVisible(
      find.text(AppStrings.recordCardNoOlder),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text(AppStrings.recordCardLoadOlder), findsNothing);
    expect(find.text(AppStrings.recordCardNoOlder), findsOneWidget);
  });

  testWidgets('라이트 테마에서도 그려진다', (tester) async {
    await _pump(tester, light: true);

    expect(tester.takeException(), isNull);
  });
}
