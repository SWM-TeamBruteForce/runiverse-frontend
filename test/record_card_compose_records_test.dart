import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record_card/domain/composable_record.dart';
import 'package:runiverse/features/record_card/domain/edit_record_card.dart';
import 'package:runiverse/features/record_card/domain/new_record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_list_item.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/presentation/compose_records_provider.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';

import 'record_card_fixtures.dart';

final _day = DateTime(2026, 9, 2);

/// 카드가 있는 7-1 한 줄.
ComposableRecord _card({
  required int id,
  required int runningRecordId,
  int hour = 18,
}) => runWith(
  summary(id: id, startedAt: DateTime(2026, 9, 2, hour)),
  runningRecordId: runningRecordId,
);

/// 카드가 없는 7-1 한 줄.
ComposableRecord _bare({required int id, int hour = 18}) => ComposableRecord(
  record: runOnly(DateTime(2026, 9, 2, hour), id: id).record,
);

/// 넘겨준 카드를 그대로 돌려주는 저장소.
class _Cards implements RecordCardRepository {
  /// 이 테스트는 프로필 그리드를 그리지 않는다. 불리면 테스트가 잘못 세워진
  /// 것이다.
  @override
  Future<RecordCardListPage> cardsOf({
    required String userId,
    int? limit,
    String? cursor,
  }) => throw UnsupportedError('이 테스트는 사람별 카드를 묻지 않는다');

  _Cards(this.cards);

  final List<ComposableRecord> cards;
  final queries = <({DateTime from, DateTime to})>[];

  @override
  Future<List<ComposableRecord>> runsInRange({
    required DateTime from,
    required DateTime to,
  }) async {
    queries.add((from: from, to: to));
    return cards;
  }

  /// 이 테스트는 **읽기만** 본다. 불리면 테스트가 잘못 세워진 것이다.
  @override
  Future<RecordCard> create(NewRecordCard card) =>
      throw UnsupportedError('이 테스트는 카드를 만들지 않는다');

  /// 이 테스트는 **읽기만** 본다. 불리면 테스트가 잘못 세워진 것이다.
  @override
  Future<RecordCard> update(EditRecordCard card) =>
      throw UnsupportedError('이 테스트는 카드를 고치지 않는다');

  /// 이 테스트는 **읽기만** 본다. 불리면 테스트가 잘못 세워진 것이다.
  @override
  Future<RecordCard> detailOf(String cardId) =>
      throw UnsupportedError('이 테스트는 상세를 열지 않는다');

  @override
  Future<void> delete(String cardId) =>
      throw UnsupportedError('이 테스트는 카드를 지우지 않는다');

  /// 이 테스트는 **음악을 보지 않는다.** 불리면 테스트가 잘못 세워진 것이다.
  @override
  Future<void> retryMusic(String cardId) =>
      throw UnsupportedError('이 테스트는 음악을 다시 만들지 않는다');
}

class _FailingCards implements RecordCardRepository {
  /// 이 테스트는 프로필 그리드를 그리지 않는다. 불리면 테스트가 잘못 세워진
  /// 것이다.
  @override
  Future<RecordCardListPage> cardsOf({
    required String userId,
    int? limit,
    String? cursor,
  }) => throw UnsupportedError('이 테스트는 사람별 카드를 묻지 않는다');

  @override
  Future<List<ComposableRecord>> runsInRange({
    required DateTime from,
    required DateTime to,
  }) async => throw const RecordCardException(RecordCardFailure.network);

  /// 이 테스트는 **읽기만** 본다. 불리면 테스트가 잘못 세워진 것이다.
  @override
  Future<RecordCard> create(NewRecordCard card) =>
      throw UnsupportedError('이 테스트는 카드를 만들지 않는다');

  /// 이 테스트는 **읽기만** 본다. 불리면 테스트가 잘못 세워진 것이다.
  @override
  Future<RecordCard> update(EditRecordCard card) =>
      throw UnsupportedError('이 테스트는 카드를 고치지 않는다');

  /// 이 테스트는 **읽기만** 본다. 불리면 테스트가 잘못 세워진 것이다.
  @override
  Future<RecordCard> detailOf(String cardId) =>
      throw UnsupportedError('이 테스트는 상세를 열지 않는다');

  @override
  Future<void> delete(String cardId) =>
      throw UnsupportedError('이 테스트는 카드를 지우지 않는다');

  /// 이 테스트는 **음악을 보지 않는다.** 불리면 테스트가 잘못 세워진 것이다.
  @override
  Future<void> retryMusic(String cardId) =>
      throw UnsupportedError('이 테스트는 음악을 다시 만들지 않는다');
}

/// ⚠️ **구독을 붙이고 읽는다.** `autoDispose` provider 는 듣는 사람이 없으면
/// 로딩 중에 버려져, 실패가 `RunRecordException` 대신 "disposed during
/// loading state" `StateError` 로 나온다.
Future<List<ComposableRecord>> _read(
  ProviderContainer container,
  DateTime when,
) {
  container.listen(composeRecordsProvider(when), (_, _) {});
  return container.read(composeRecordsProvider(when).future);
}

void main() {
  ProviderContainer build({RecordCardRepository? cards}) {
    final made = ProviderContainer(
      overrides: [
        recordCardRepositoryProvider.overrideWithValue(
          cards ?? _Cards(const []),
        ),
      ],
    );
    addTearDown(made.dispose);
    return made;
  }

  test('⚠️ 카드 유무가 응답에 실려 온다 — 앱이 맞춰 붙이지 않는다', () async {
    // 묶음 6까지는 기록과 카드를 따로 받아 `joinCards`로 붙였다. 7-1이 한
    // 응답에 싣기로 하면서 그 일은 **서버의 것**이 됐다(연동 가이드 1절).
    final container = build(
      cards: _Cards([
        _bare(id: 11, hour: 7),
        _card(id: 500, runningRecordId: 12),
      ]),
    );

    final joined = await _read(container, _day);

    expect(joined.map((r) => r.record.id), [11, 12]);
    expect(joined[0].hasCard, isFalse);
    expect(joined[1].existingCardId, 'card-500');
  });

  test('⚠️ 하루치만, 한 번만 묻는다', () async {
    // 묶음 6까지는 요청이 둘이었다. 7-1 하나로 줄었다.
    final cards = _Cards(const []);
    final container = build(cards: cards);

    await _read(container, _day);

    expect(cards.queries.single, (from: _day, to: _day));
  });

  test('⚠️ 시각이 붙은 날짜를 넘겨도 그날 것을 묻는다', () async {
    // family 키가 시·분으로 흔들리면 같은 날이 provider 여러 개가 된다.
    final cards = _Cards(const []);
    final container = build(cards: cards);

    await _read(container, DateTime(2026, 9, 2, 19, 30));

    expect(cards.queries.single, (from: _day, to: _day));
  });

  test('⚠️ 조회 실패를 없는 척하지 않는다', () async {
    // 카드가 있는 기록을 "없음"으로 보여 주면 중복 작성으로 끌고 가고,
    // 저장에서 거절당해 쓴 글을 잃는다. 한 줄 오류와 다시 시도가 낫다.
    final container = build(cards: _FailingCards());

    await expectLater(
      _read(container, _day),
      throwsA(isA<RecordCardException>()),
    );
  });

  test('그날 기록이 없으면 빈 목록이다 — 오류가 아니다', () async {
    final container = build();

    expect(await _read(container, _day), isEmpty);
  });
}
