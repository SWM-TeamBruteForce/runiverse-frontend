import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/record_card/domain/record_card_summary.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/presentation/day_cards_sheet.dart';
import 'package:runiverse/features/record_card/presentation/record_card_calendar.dart';
import 'package:runiverse/features/record_card/presentation/record_card_cell.dart';
import 'package:runiverse/features/record_card/presentation/record_card_state.dart';

import 'record_card_fixtures.dart';

RecordCardSummary _card({
  required int id,
  required DateTime startedAt,
  RecordCardActivity activity = RecordCardActivity.daily,
}) => summary(id: id, startedAt: startedAt, activity: activity);

RecordCardData _data({
  List<RecordCardSummary>? cards,
  RecordCardActivity? filter,
  CalendarZoom zoom = CalendarZoom.month,
  bool atOldest = false,
  List<int>? runDays,
}) => RecordCardData(
  atOldest: atOldest,
  months: [
    MonthCards(
      month: DateTime(2026, 9),
      runs: [
        for (final card
            in cards ??
                [
                  _card(id: 7, startedAt: DateTime(2026, 9, 7, 8)),
                  _card(id: 11, startedAt: DateTime(2026, 9, 11, 8)),
                  _card(id: 12, startedAt: DateTime(2026, 9, 11, 20)),
                ])
          runWith(card),
        // 9일은 뛰었는데 카드가 없다 — 운동화가 서고 눌린다.
        for (final day in runDays ?? const [9]) runOnly(DateTime(2026, 9, day, 7)),
      ],
    ),
  ],
  filter: filter,
  zoom: zoom,
);

/// 카드도 러닝도 없는 달들. **쌓이는 방향만** 보려고 쓴다 — 칸이 비어 있어야
/// 달 머리의 위아래 자리가 내용에 흔들리지 않는다.
RecordCardData _emptyMonths(List<DateTime> months) => RecordCardData(
  months: [for (final month in months) MonthCards(month: month, runs: const [])],
  zoom: CalendarZoom.month,
);

/// 시험 화면을 길게 잡는다.
///
/// ⚠️ **달력이 아래에서 위로 쌓이면서 필요해졌다.** 한 달 그리드가 기본 시험
/// 화면(600px)보다 높아, 바닥에 붙은 목록에서는 **그 달의 윗줄 날짜와 그 위
/// `더 받기` 줄이 아예 만들어지지 않는다.** 기기에서는 스크롤해서 닿는 자리지만
/// 시험은 스크롤하지 않으므로 화면을 키워 둔다.
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _pump(
  WidgetTester tester, {
  RecordCardData? data,
  ValueChanged<RecordCardSummary>? onOpen,
  ValueChanged<DateTime>? onEmptyDay,
  bool light = false,
}) {
  _tallScreen(tester);
  return tester.pumpWidget(
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
}

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
    RecordCardSummary? opened;
    await _pump(tester, onOpen: (card) => opened = card);

    await tester.tap(
      find.bySemanticsLabel(
        AppStrings.recordCardCellSemantics(day: DateTime(2026, 9, 7), count: 1),
      ),
    );
    await tester.pumpAndSettle();

    expect(opened?.id, 'card-7');
    expect(find.byType(DayCardsSheet), findsNothing);
  });

  testWidgets('⚠️ 카드가 둘인 날을 누르면 시트가 뜬다 — 두 번째가 갇히면 안 된다', (tester) async {
    RecordCardSummary? opened;
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
    RecordCardSummary? opened;
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

    expect(opened?.id, 'card-12');
  });

  testWidgets('⚠️ 안 뛴 빈 날은 눌리지 않는다', (tester) async {
    // 눌러서 "기록이 없어요"를 보여 주는 것보다 애초에 안 눌리는 편이 낫다
    // (설계 6-1, 2026-11-18). 운동화가 눌릴 수 있는 날을 이미 가리킨다.
    DateTime? empty;
    await _pump(tester, onEmptyDay: (day) => empty = day);

    await tester.tap(
      find.bySemanticsLabel(
        AppStrings.recordCardCellSemantics(day: DateTime(2026, 9, 3), count: 0),
      ),
    );
    await tester.pumpAndSettle();

    expect(empty, isNull);
  });

  testWidgets('⚠️ 뛴 빈 날을 누르면 onEmptyDay가 그 날짜로 불린다', (tester) async {
    DateTime? empty;
    await _pump(tester, onEmptyDay: (day) => empty = day);

    await tester.tap(
      find.bySemanticsLabel(
        AppStrings.recordCardCellUnwrittenSemantics(DateTime(2026, 9, 9)),
      ),
    );
    await tester.pumpAndSettle();

    expect(empty, DateTime(2026, 9, 9));
  });

  testWidgets('⚠️ 뛴 빈 날에만 운동화가 선다', (tester) async {
    await _pump(tester);

    expect(find.byType(RunShoeMark), findsOneWidget);
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
    // 한 달과 더 받기 줄이 **통째로 들어가는** 화면이다. 끌 것이 없는 상태를
    // 만들어 두고, 그래도 버튼이 있고 눌리는지 본다.
    _tallScreen(tester);
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

  testWidgets('⚠️ 필터를 걸면 걸러진 뒤의 마지막 카드를 칸에 그린다', (tester) async {
    // 가이드 1절: "같은 날에 조건과 일치하는 다른 카드가 있으면 그 카드를
    // 목록과 개수 배지에 포함." 칸은 `cards.last`를 깔므로, 거르기 전의
    // 마지막을 깔면 **필터와 다른 유형의 카드**가 칸에 선다.
    //
    // 7일에 대회(아침)와 일상(저녁) 두 장을 두고 대회만 남긴다. 거르지 않으면
    // 저녁의 일상 카드가 칸에 깔리고, 눌렀을 때도 그것이 열린다.
    RecordCardSummary? opened;
    await _pump(
      tester,
      data: _data(
        cards: [
          _card(
            id: 1,
            startedAt: DateTime(2026, 9, 7, 8),
            activity: RecordCardActivity.race,
          ),
          _card(
            id: 2,
            startedAt: DateTime(2026, 9, 7, 20),
            activity: RecordCardActivity.daily,
          ),
        ],
        filter: RecordCardActivity.race,
      ),
      onOpen: (card) => opened = card,
    );

    await tester.tap(
      find.bySemanticsLabel(
        AppStrings.recordCardCellSemantics(day: DateTime(2026, 9, 7), count: 1),
      ),
    );
    await tester.pumpAndSettle();

    expect(opened?.id, 'card-1');
    expect(opened?.activity, RecordCardActivity.race);
  });

  group('쌓이는 방향', () {
    testWidgets('이번 달이 지난달보다 아래에 있다', (tester) async {
      await _pump(tester, data: _emptyMonths([DateTime(2026, 10), DateTime(2026, 11)]));

      final october = tester
          .getTopLeft(find.text(AppStrings.recordMonthLabel(DateTime(2026, 10))))
          .dy;
      final november = tester
          .getTopLeft(find.text(AppStrings.recordMonthLabel(DateTime(2026, 11))))
          .dy;

      expect(november, greaterThan(october));
    });

    testWidgets('⚠️ 더 받기 줄은 맨 위다', (tester) async {
      // 달이 하나뿐이면 스크롤할 것이 없다. 그때도 과거로 가는 길이 있어야 한다.
      await _pump(tester, data: _emptyMonths([DateTime(2026, 11)]));

      final footer = tester
          .getTopLeft(find.text(AppStrings.recordCardLoadOlder))
          .dy;
      final november = tester
          .getTopLeft(find.text(AppStrings.recordMonthLabel(DateTime(2026, 11))))
          .dy;

      expect(footer, lessThan(november));
    });
  });
}
