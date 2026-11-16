import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';
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

void main() {
  group('MonthCards', () {
    test('카드를 날짜별로 묶는다', () {
      final month = MonthCards(
        month: DateTime(2026, 9),
        cards: [
          _card(id: 1, startedAt: DateTime(2026, 9, 2, 18, 54)),
          _card(id: 2, startedAt: DateTime(2026, 9, 7, 7, 10)),
        ],
      );

      expect(month.byDay.keys, containsAll([DateTime(2026, 9, 2), DateTime(2026, 9, 7)]));
      expect(month.byDay[DateTime(2026, 9, 2)], hasLength(1));
      expect(month.cardCount, 2);
    });

    test('⚠️ 자정 직전에 시작한 러닝도 그날 칸에 붙는다', () {
      final month = MonthCards(
        month: DateTime(2026, 9),
        cards: [_card(id: 1, startedAt: DateTime(2026, 9, 2, 23, 50))],
      );

      expect(month.byDay[DateTime(2026, 9, 2)], hasLength(1));
      expect(month.byDay[DateTime(2026, 9, 3)], isNull);
    });

    test('⚠️ 하루에 둘이면 한 키에 둘이 담긴다', () {
      final month = MonthCards(
        month: DateTime(2026, 9),
        cards: [
          _card(id: 1, startedAt: DateTime(2026, 9, 2, 8)),
          _card(id: 2, startedAt: DateTime(2026, 9, 2, 21)),
        ],
      );

      expect(month.byDay[DateTime(2026, 9, 2)], hasLength(2));
    });

    test('필터를 걸면 그 유형만 남고 카드 수도 따라 준다', () {
      final month = MonthCards(
        month: DateTime(2026, 9),
        cards: [
          _card(id: 1, startedAt: DateTime(2026, 9, 2)),
          _card(id: 2, startedAt: DateTime(2026, 9, 3)),
          _card(
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
    MonthCards september({RecordCardActivity activity = RecordCardActivity.daily}) =>
        MonthCards(
          month: DateTime(2026, 9),
          cards: [
            _card(id: 1, startedAt: DateTime(2026, 9, 2), activity: activity),
          ],
        );

    MonthCards october() => MonthCards(
      month: DateTime(2026, 10),
      cards: [_card(id: 2, startedAt: DateTime(2026, 10, 5))],
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

    test('⚠️ 필터는 visible만 바꾼다 — 원본은 그대로다', () {
      final data = RecordCardData(
        months: [september()],
        filter: RecordCardActivity.race,
      );

      expect(data.visible.single.cardCount, 0);
      expect(data.months.single.cardCount, 1);
    });

    test('⚠️ 카드가 하나도 없는 것과 필터로 0장인 것을 가른다', () {
      final empty = RecordCardData(months: [
        MonthCards(month: DateTime(2026, 9), cards: const []),
      ]);
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
