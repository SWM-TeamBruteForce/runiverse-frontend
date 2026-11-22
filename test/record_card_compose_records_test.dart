import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record/domain/run_record_repository.dart';
import 'package:runiverse/features/record/presentation/record_provider.dart';
import 'package:runiverse/features/record_card/domain/composable_record.dart';
import 'package:runiverse/features/record_card/domain/edit_record_card.dart';
import 'package:runiverse/features/record_card/domain/new_record_card.dart';
import 'package:runiverse/features/record_card/domain/music_generation.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';
import 'package:runiverse/features/record_card/presentation/compose_records_provider.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';

final _day = DateTime(2026, 9, 2);

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

/// 넘겨준 기록을 그대로 돌려주는 저장소. 구간도 적어 둔다.
class _Records implements RunRecordRepository {
  _Records(this.records, {this.delay = Duration.zero});

  final List<RunRecord> records;
  final Duration delay;
  final queries = <({DateTime from, DateTime to})>[];

  @override
  Future<List<RunRecord>> byDateRange({
    required DateTime from,
    required DateTime to,
  }) async {
    queries.add((from: from, to: to));
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return records;
  }

  @override
  Future<Never> byRoom(int runningRoomId) =>
      throw UnimplementedError('이 테스트는 상세를 부르지 않는다');
}

class _FailingRecords implements RunRecordRepository {
  @override
  Future<List<RunRecord>> byDateRange({
    required DateTime from,
    required DateTime to,
  }) async => throw const RunRecordException(RunRecordFailure.sessionExpired);

  @override
  Future<Never> byRoom(int runningRoomId) =>
      throw UnimplementedError('이 테스트는 상세를 부르지 않는다');
}

/// 넘겨준 카드를 그대로 돌려주는 저장소.
class _Cards implements RecordCardRepository {
  /// 이 테스트는 프로필 그리드를 그리지 않는다. 불리면 테스트가 잘못 세워진
  /// 것이다.
  @override
  Future<List<RecordCard>> byUser({required String userId, int? limit}) =>
      throw UnsupportedError('이 테스트는 사람별 카드를 묻지 않는다');

  _Cards(this.cards, {this.delay = Duration.zero});

  final List<RecordCard> cards;
  final Duration delay;
  final queries = <({DateTime from, DateTime to})>[];

  @override
  Future<List<RecordCard>> byDateRange({
    required DateTime from,
    required DateTime to,
  }) async {
    queries.add((from: from, to: to));
    if (delay > Duration.zero) await Future<void>.delayed(delay);
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
  Future<void> delete(int cardId) =>
      throw UnsupportedError('이 테스트는 카드를 지우지 않는다');

  /// 이 테스트는 **음악을 보지 않는다.** 불리면 테스트가 잘못 세워진 것이다.
  @override
  Future<MusicGeneration> musicOf(int cardId) =>
      throw UnsupportedError('이 테스트는 음악을 보지 않는다');

  /// 이 테스트는 **음악을 보지 않는다.** 불리면 테스트가 잘못 세워진 것이다.
  @override
  Future<MusicGeneration> requestMusic(int cardId) =>
      throw UnsupportedError('이 테스트는 음악을 만들지 않는다');
}

class _FailingCards implements RecordCardRepository {
  /// 이 테스트는 프로필 그리드를 그리지 않는다. 불리면 테스트가 잘못 세워진
  /// 것이다.
  @override
  Future<List<RecordCard>> byUser({required String userId, int? limit}) =>
      throw UnsupportedError('이 테스트는 사람별 카드를 묻지 않는다');

  @override
  Future<List<RecordCard>> byDateRange({
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
  Future<void> delete(int cardId) =>
      throw UnsupportedError('이 테스트는 카드를 지우지 않는다');

  /// 이 테스트는 **음악을 보지 않는다.** 불리면 테스트가 잘못 세워진 것이다.
  @override
  Future<MusicGeneration> musicOf(int cardId) =>
      throw UnsupportedError('이 테스트는 음악을 보지 않는다');

  /// 이 테스트는 **음악을 보지 않는다.** 불리면 테스트가 잘못 세워진 것이다.
  @override
  Future<MusicGeneration> requestMusic(int cardId) =>
      throw UnsupportedError('이 테스트는 음악을 만들지 않는다');
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
  ProviderContainer build({
    RunRecordRepository? records,
    RecordCardRepository? cards,
  }) {
    final made = ProviderContainer(
      overrides: [
        runRecordRepositoryProvider.overrideWithValue(
          records ?? _Records(const []),
        ),
        recordCardRepositoryProvider.overrideWithValue(
          cards ?? _Cards(const []),
        ),
      ],
    );
    addTearDown(made.dispose);
    return made;
  }

  test('그날 기록에 카드 유무가 붙어 온다', () async {
    final container = build(
      records: _Records([_record(id: 11, hour: 7), _record(id: 12)]),
      cards: _Cards([_card(id: 500, runningRecordId: 12)]),
    );

    final joined = await _read(container, _day);

    expect(joined.map((r) => r.record.id), [11, 12]);
    expect(joined[0].hasCard, isFalse);
    expect(joined[1].existingCardId, 500);
  });

  test('⚠️ 하루치만 묻는다 — from과 to가 같은 날이다', () async {
    final records = _Records([_record(id: 11)]);
    final cards = _Cards(const []);
    final container = build(records: records, cards: cards);

    await _read(container, _day);

    expect(records.queries.single, (from: _day, to: _day));
    expect(cards.queries.single, (from: _day, to: _day));
  });

  test('⚠️ 시각이 붙은 날짜를 넘겨도 그날 것을 묻는다', () async {
    // family 키가 시·분으로 흔들리면 같은 날이 provider 여러 개가 된다.
    final records = _Records([_record(id: 11)]);
    final container = build(records: records);

    await _read(container, DateTime(2026, 9, 2, 19, 30));

    expect(records.queries.single, (from: _day, to: _day));
  });

  test('⚠️ 두 조회를 줄 세우지 않는다', () async {
    // 줄 세우면 왕복이 두 배다. 지연 60ms짜리 둘을 겹쳐 부르면 전체가
    // 120ms보다 짧다.
    final container = build(
      records: _Records([
        _record(id: 11),
      ], delay: const Duration(milliseconds: 60)),
      cards: _Cards(const [], delay: const Duration(milliseconds: 60)),
    );

    final watch = Stopwatch()..start();
    await _read(container, _day);
    watch.stop();

    expect(watch.elapsedMilliseconds, lessThan(120));
  });

  test('기록 조회가 실패하면 오류가 올라온다', () async {
    final container = build(records: _FailingRecords());

    await expectLater(
      _read(container, _day),
      throwsA(isA<RunRecordException>()),
    );
  });

  test('⚠️ 카드 조회 실패도 오류다 — 없는 척하지 않는다', () async {
    // 카드가 있는 기록을 "없음"으로 보여 주면 중복 작성으로 끌고 가고,
    // 저장에서 거절당해 쓴 글을 잃는다. 한 줄 오류와 다시 시도가 낫다.
    final container = build(
      records: _Records([_record(id: 11)]),
      cards: _FailingCards(),
    );

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
