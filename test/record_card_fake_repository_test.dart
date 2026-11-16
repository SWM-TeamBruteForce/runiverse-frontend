import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record_card/data/fake_record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';

final _today = DateTime(2026, 11, 16);

DateTime _firstOf(DateTime month) => DateTime(month.year, month.month, 1);
DateTime _lastOf(DateTime month) => DateTime(month.year, month.month + 1, 0);

/// 두 달치를 **달마다 따로** 받아 합친다. 한 번에 31일을 넘길 수 없다.
Future<List<RecordCard>> _twoMonths(FakeRecordCardRepository fake) async {
  final thisMonth = DateTime(_today.year, _today.month);
  final lastMonth = DateTime(_today.year, _today.month - 1);
  return [
    ...await fake.byDateRange(
      from: _firstOf(lastMonth),
      to: _lastOf(lastMonth),
    ),
    ...await fake.byDateRange(
      from: _firstOf(thisMonth),
      to: _lastOf(thisMonth),
    ),
  ];
}

void main() {
  late FakeRecordCardRepository fake;

  setUp(() => fake = FakeRecordCardRepository(today: _today));

  test('구간 밖의 카드는 안 준다', () async {
    final thisMonth = DateTime(_today.year, _today.month);
    final cards = await fake.byDateRange(
      from: _firstOf(thisMonth),
      to: _lastOf(thisMonth),
    );

    expect(cards, isNotEmpty);
    for (final card in cards) {
      expect(card.day.month, _today.month);
      expect(card.day.year, _today.year);
    }
  });

  test('⚠️ 31일을 넘기면 진짜처럼 거절한다', () async {
    // 가짜가 뭐든 받아 주면 화면이 구간을 넓혀도 테스트가 다 통과한다.
    expect(
      () => fake.byDateRange(
        from: _today.subtract(const Duration(days: 40)),
        to: _today,
      ),
      throwsA(
        isA<RecordCardException>().having(
          (e) => e.failure,
          'failure',
          RecordCardFailure.invalidRequest,
        ),
      ),
    );
  });

  test('시작일이 끝일보다 늦어도 거절한다', () async {
    expect(
      () => fake.byDateRange(
        from: _today,
        to: _today.subtract(const Duration(days: 3)),
      ),
      throwsA(isA<RecordCardException>()),
    );
  });

  test('⚠️ failWith를 주면 그 실패로 던진다 — 오류 화면을 보는 길이다', () async {
    final failing = FakeRecordCardRepository(
      today: _today,
      failWith: RecordCardFailure.network,
    );

    expect(
      () => failing.byDateRange(from: _firstOf(_today), to: _lastOf(_today)),
      throwsA(
        isA<RecordCardException>().having(
          (e) => e.failure,
          'failure',
          RecordCardFailure.network,
        ),
      ),
    );
  });

  test('물어본 구간을 적어 둔다', () async {
    await fake.byDateRange(from: _firstOf(_today), to: _lastOf(_today));

    expect(fake.calls, 1);
    expect(fake.queries.single.from, _firstOf(_today));
  });

  test('⚠️ 사진이 0장인 카드와 5장인 카드가 둘 다 있다', () async {
    final cards = await _twoMonths(fake);

    expect(cards.where((c) => c.photos.isEmpty), isNotEmpty);
    expect(cards.where((c) => c.photos.length == 5), isNotEmpty);
  });

  test('⚠️ 하루에 카드가 둘인 날이 있다', () async {
    final cards = await _twoMonths(fake);
    final byDay = <DateTime, int>{};
    for (final card in cards) {
      byDay[card.day] = (byDay[card.day] ?? 0) + 1;
    }

    expect(byDay.values.where((count) => count >= 2), isNotEmpty);
  });

  test('⚠️ 활동 유형 셋이 모두 나온다 — 필터를 눈으로 보는 길이다', () async {
    final cards = await _twoMonths(fake);
    final kinds = cards.map((c) => c.activity).toSet();

    expect(kinds, containsAll(RecordCardActivity.values));
  });

  test('공개범위 셋이 모두 나온다', () async {
    final cards = await _twoMonths(fake);

    expect(cards.map((c) => c.visibility).toSet(), hasLength(3));
  });

  test('⚠️ 모든 카드가 비어 있지 않은 경로를 들고 있다', () async {
    // 경로가 빈 카드가 섞이면 사진 없는 칸이 빈 날처럼 보인다.
    final cards = await _twoMonths(fake);

    expect(cards, isNotEmpty);
    for (final card in cards) {
      expect(card.route.isNotEmpty, isTrue, reason: '카드 ${card.id}');
    }
  });

  test('회고가 비어 있는 카드는 없다', () async {
    final cards = await _twoMonths(fake);

    for (final card in cards) {
      expect(card.reviewText.trim(), isNotEmpty);
    }
  });

  test('카드 번호가 겹치지 않는다', () async {
    final cards = await _twoMonths(fake);

    expect(cards.map((c) => c.id).toSet(), hasLength(cards.length));
  });
}
