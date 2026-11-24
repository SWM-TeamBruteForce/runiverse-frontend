import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record_card/domain/composable_record.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/presentation/record_card_state.dart';

import 'record_card_fixtures.dart';

ComposableRecord _run({
  required int id,
  required DateTime startedAt,
  RecordCardActivity? activity = RecordCardActivity.daily,
}) => runWith(summary(id: id, startedAt: startedAt, activity: activity));

void main() {
  group('MonthCards', () {
    test('카드를 날짜별로 묶는다', () {
      final month = MonthCards(
        month: DateTime(2026, 9),
        runs: [
          _run(id: 1, startedAt: DateTime(2026, 9, 2, 18, 54)),
          _run(id: 2, startedAt: DateTime(2026, 9, 7, 7, 10)),
        ],
      );

      expect(
        month.byDay.keys,
        containsAll([DateTime(2026, 9, 2), DateTime(2026, 9, 7)]),
      );
      expect(month.byDay[DateTime(2026, 9, 2)], hasLength(1));
      expect(month.cardCount, 2);
    });

    test('⚠️ 자정 직전에 시작한 러닝도 그날 칸에 붙는다', () {
      final month = MonthCards(
        month: DateTime(2026, 9),
        runs: [_run(id: 1, startedAt: DateTime(2026, 9, 2, 23, 50))],
      );

      expect(month.byDay[DateTime(2026, 9, 2)], hasLength(1));
      expect(month.byDay[DateTime(2026, 9, 3)], isNull);
    });

    test('⚠️ 하루에 둘이면 한 키에 둘이 담긴다', () {
      final month = MonthCards(
        month: DateTime(2026, 9),
        runs: [
          _run(id: 1, startedAt: DateTime(2026, 9, 2, 8)),
          _run(id: 2, startedAt: DateTime(2026, 9, 2, 21)),
        ],
      );

      expect(month.byDay[DateTime(2026, 9, 2)], hasLength(2));
    });

    test('필터를 걸면 그 유형만 남고 카드 수도 따라 준다', () {
      final month = MonthCards(
        month: DateTime(2026, 9),
        runs: [
          _run(id: 1, startedAt: DateTime(2026, 9, 2)),
          _run(id: 2, startedAt: DateTime(2026, 9, 3)),
          _run(
            id: 3,
            startedAt: DateTime(2026, 9, 4),
            activity: RecordCardActivity.race,
          ),
        ],
      );

      expect(month.filtered(RecordCardActivity.race).cardCount, 1);
      expect(month.filtered(null).cardCount, 3);
    });
  });

  group('RecordCardData', () {
    MonthCards september({
      RecordCardActivity activity = RecordCardActivity.daily,
    }) => MonthCards(
      month: DateTime(2026, 9),
      runs: [_run(id: 1, startedAt: DateTime(2026, 9, 2), activity: activity)],
    );

    MonthCards october() => MonthCards(
      month: DateTime(2026, 10),
      runs: [_run(id: 2, startedAt: DateTime(2026, 10, 5))],
    );

    test('달은 오름차순이다', () {
      final data = RecordCardData(months: [october(), september()]);

      expect(data.visible.first.month, DateTime(2026, 9));
      expect(data.visible.last.month, DateTime(2026, 10));
    });

    test('⚠️ 필터로 0장이 된 달도 목록에 남는다 — 달이 사라지면 달력이 아니다', () {
      final data = RecordCardData(
        months: [september(), october()],
        filter: RecordCardActivity.race,
      );

      expect(data.visible, hasLength(2));
      expect(data.visible.first.cardCount, 0);
    });

    test('⚠️ 가장 오래된 빈 달들은 보이지 않는다 — 첫 카드가 있는 달까지다', () {
      // 더 받기가 빈 달을 붙여 놓으면 바닥에 아무것도 없는 달력이 늘어선다.
      final data = RecordCardData(
        months: [
          MonthCards(month: DateTime(2026, 7), runs: const []),
          MonthCards(month: DateTime(2026, 8), runs: const []),
          september(),
          october(),
        ],
      );

      expect(data.visible.map((m) => m.month), [
        DateTime(2026, 9),
        DateTime(2026, 10),
      ]);
      // 원본은 그대로다 — 이미 받은 달을 다시 받지 않으려면 들고 있어야 한다.
      expect(data.months, hasLength(4));
    });

    test('⚠️ 사이에 낀 빈 달은 남는다 — 달력에서 달이 건너뛰면 안 된다', () {
      final data = RecordCardData(
        months: [
          september(),
          MonthCards(month: DateTime(2026, 10), runs: const []),
          MonthCards(
            month: DateTime(2026, 11),
            runs: [_run(id: 3, startedAt: DateTime(2026, 11, 2))],
          ),
        ],
      );

      expect(data.visible, hasLength(3));
    });

    test('⚠️ 카드가 하나도 없으면 받은 달을 그대로 보여준다 — 달력이 통째로 비면 안 된다', () {
      final data = RecordCardData(
        months: [
          MonthCards(month: DateTime(2026, 9), runs: const []),
          MonthCards(month: DateTime(2026, 10), runs: const []),
        ],
      );

      expect(data.visible, hasLength(2));
      expect(data.hasAnyCard, isFalse);
    });

    test('⚠️ 필터로 0장이 된 달은 잘리지 않는다 — 자르는 기준은 필터 전이다', () {
      final data = RecordCardData(
        months: [september(), october()],
        filter: RecordCardActivity.race,
      );

      expect(data.visible, hasLength(2));
    });

    test('⚠️ 필터는 visible만 바꾼다 — 원본은 그대로다', () {
      final data = RecordCardData(
        months: [september()],
        filter: RecordCardActivity.race,
      );

      expect(data.visible.single.cardCount, 0);
      expect(data.months.single.cardCount, 1);
    });

    test('⚠️ 카드가 하나도 없는 것과 필터로 0장인 것을 가른다', () {
      final empty = RecordCardData(
        months: [MonthCards(month: DateTime(2026, 9), runs: const [])],
      );
      final filteredOut = RecordCardData(
        months: [september()],
        filter: RecordCardActivity.race,
      );

      expect(empty.hasAnyCard, isFalse);
      expect(filteredOut.hasAnyCard, isTrue);
    });

    test('copyWith는 받은 것만 바꾼다', () {
      final data = RecordCardData(months: [september()]);
      final zoomed = data.copyWith(zoom: CalendarZoom.quarter);

      expect(zoomed.zoom, CalendarZoom.quarter);
      expect(zoomed.filter, isNull);
      expect(zoomed.months, data.months);
    });

    test('copyWith로 필터를 지울 수 있다', () {
      final data = RecordCardData(
        months: [september()],
        filter: RecordCardActivity.daily,
      );

      expect(data.copyWith(clearFilter: true).filter, isNull);
    });
  });

  group('shoeDays', () {
    test('⚠️ 뛰었는데 카드가 없는 날만 운동화다', () {
      final data = RecordCardData(
        months: [
          MonthCards(
            month: DateTime(2026, 9),
            runs: [
              _run(id: 7, startedAt: DateTime(2026, 9, 7, 8)),
              // 9일은 뛰었는데 카드가 없다 — 운동화가 선다.
              runOnly(DateTime(2026, 9, 9, 7)),
            ],
          ),
        ],
      );

      // 7일은 카드가 있어 썸네일·선 아트가 칸을 채운다. 9일만 운동화다.
      expect(data.shoeDays, {DateTime(2026, 9, 9)});
    });

    test('⚠️ 운동화는 유형 필터와 무관하다', () {
      // 일상 카드가 있는 날에 `대회` 필터를 걸면 칸은 비지만, 거기에 운동화를
      // 띄우면 달력이 운동화로 뒤덮인다. 필터 걸기 전 카드로 가린다.
      final data = RecordCardData(
        months: [
          MonthCards(
            month: DateTime(2026, 9),
            runs: [
              _run(id: 7, startedAt: DateTime(2026, 9, 7, 8)),
              // 9일은 뛰었는데 카드가 없다 — 운동화가 선다.
              runOnly(DateTime(2026, 9, 9, 7)),
            ],
          ),
        ],
        filter: RecordCardActivity.race,
      );

      expect(data.visible.single.cardCount, 0);
      expect(data.shoeDays, isNot(contains(DateTime(2026, 9, 7))));
      expect(data.shoeDays, contains(DateTime(2026, 9, 9)));
    });

    test('러닝 기록을 못 받은 달은 운동화가 없다', () {
      final data = RecordCardData(
        months: [MonthCards(month: DateTime(2026, 9), runs: const [])],
      );

      expect(data.shoeDays, isEmpty);
    });

    test('⚠️ 필터를 걸어도 visible이 recordDays를 잃지 않는다', () {
      // 떨어뜨리면 visible을 읽는 다음 사람이 빈 집합을 받고 조용히 틀린다.
      final data = RecordCardData(
        months: [
          MonthCards(
            month: DateTime(2026, 9),
            runs: [
              _run(id: 7, startedAt: DateTime(2026, 9, 7, 8)),
              runOnly(DateTime(2026, 9, 9, 7)),
            ],
          ),
        ],
        filter: RecordCardActivity.race,
      );

      // 유형이 안 맞는 카드는 빠지지만 **뛴 날은 남는다** — 거르면
      // 필터를 켠 순간 운동화가 전부 사라진다.
      expect(data.visible.single.byDay, isEmpty);
      expect(data.visible.single.recordDays, {
        DateTime(2026, 9, 7),
        DateTime(2026, 9, 9),
      });
    });
  });

  group('zoomFor', () {
    test('많이 오므리면 분기로, 많이 벌리면 월로 간다', () {
      expect(zoomFor(CalendarZoom.month, 0.7), CalendarZoom.quarter);
      expect(zoomFor(CalendarZoom.quarter, 1.4), CalendarZoom.month);
    });

    test('⚠️ 조금 움직인 것으로는 안 바뀐다 — 스크롤하다 줌이 튄다', () {
      expect(zoomFor(CalendarZoom.month, 0.95), CalendarZoom.month);
      expect(zoomFor(CalendarZoom.month, 1.5), CalendarZoom.month);
      expect(zoomFor(CalendarZoom.quarter, 1.1), CalendarZoom.quarter);
      expect(zoomFor(CalendarZoom.quarter, 0.5), CalendarZoom.quarter);
    });
  });
}
