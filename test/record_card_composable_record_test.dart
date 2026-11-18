import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record_card/domain/composable_record.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';

RunRecord _record({required int id, int hour = 18}) => RunRecord(
  id: id,
  runningRoomId: id + 900,
  startedAt: DateTime(2026, 9, 2, hour),
  distanceMeters: 5400,
  duration: const Duration(minutes: 28),
  averagePace: const Duration(minutes: 5, seconds: 13),
  playerCount: 1,
);

RecordCard _card({required int id, required int runningRecordId}) => RecordCard(
  id: id,
  runningRecordId: runningRecordId,
  startedAt: DateTime(2026, 9, 2, 18),
  activity: RecordCardActivity.daily,
  visibility: RecordCardVisibility.friends,
  reviewText: '회고',
  photos: const [],
  route: RouteArt.empty,
  distanceMeters: 5400,
  duration: const Duration(minutes: 28),
  averagePace: const Duration(minutes: 5),
  runners: const [],
);

void main() {
  test('카드가 있는 기록에는 그 카드 번호가 붙는다', () {
    final joined = joinCards(
      records: [_record(id: 11, hour: 7), _record(id: 12, hour: 18)],
      cards: [_card(id: 500, runningRecordId: 12)],
    );

    // ⚠️ 기록 순서를 유지한다. 목록이 화면에 뜨는 차례다.
    expect(joined.map((r) => r.record.id), [11, 12]);
    expect(joined[0].existingCardId, isNull);
    expect(joined[0].hasCard, isFalse);
    expect(joined[1].existingCardId, 500);
    expect(joined[1].hasCard, isTrue);
  });

  test('⚠️ 한 기록에 카드가 둘로 오면 첫 카드를 쓴다', () {
    // 서버에 unique(running_record_id)가 있지만, 앱은 그것을 믿고 터지지
    // 않는다. 둘 중 아무거나 고르는 것보다 늘 같은 것을 고르는 편이 낫다.
    final joined = joinCards(
      records: [_record(id: 11)],
      cards: [
        _card(id: 500, runningRecordId: 11),
        _card(id: 501, runningRecordId: 11),
      ],
    );

    expect(joined.single.existingCardId, 500);
  });

  test('기록이 없으면 빈 목록이다 — 카드가 있어도', () {
    expect(
      joinCards(
        records: const [],
        cards: [_card(id: 500, runningRecordId: 11)],
      ),
      isEmpty,
    );
  });

  test('카드가 없으면 전부 쓸 수 있는 기록이다', () {
    final joined = joinCards(
      records: [_record(id: 11), _record(id: 12)],
      cards: const [],
    );

    expect(joined, hasLength(2));
    expect(joined.every((r) => !r.hasCard), isTrue);
  });

  test('⚠️ 그날 기록과 상관없는 카드는 아무 기록에도 안 붙는다', () {
    // 날짜를 옮겨 다니며 조회하므로 두 쪽이 어긋날 수 있다.
    final joined = joinCards(
      records: [_record(id: 11)],
      cards: [_card(id: 500, runningRecordId: 99)],
    );

    expect(joined.single.hasCard, isFalse);
  });
}
