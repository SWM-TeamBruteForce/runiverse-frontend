import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record_card/data/fake_record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/edit_record_card.dart';
import 'package:runiverse/features/record_card/domain/new_record_card.dart';
import 'package:runiverse/features/record_card/domain/composable_record.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/profile/presentation/profile_cards_provider.dart';
import 'package:runiverse/features/record_card/presentation/card_delete_provider.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';

import 'record_card_fixtures.dart';

/// 카드 삭제 (설계 6-6).
///
/// ## ⚠️ 되돌릴 수 없다
///
/// 서버에 논리 삭제 컬럼이 없다(설계 3절). 확인을 받는 것은 화면의 일이고,
/// 여기는 **한 번 가면 끝**이라는 전제로 돈다.
void main() {
  test('지우면 그 카드가 목록에서 빠진다', () async {
    final repository = FakeRecordCardRepository(today: _today);
    final before = cardsOf(await repository.runsInRange(from: _from, to: _today));
    final target = before.first;

    await repository.delete(target.id);

    final after = cardsOf(await repository.runsInRange(from: _from, to: _today));
    expect(after.map((c) => c.id), isNot(contains(target.id)));
    expect(after, hasLength(before.length - 1));
  });

  test('⚠️ 목 데이터도 지워진다', () async {
    // `_all()`이 매번 목을 새로 만든다 — 거르지 않으면 지운 카드가 다음
    // 조회에 되살아난다.
    final repository = FakeRecordCardRepository(today: _today);
    final target = cardsOf(
      await repository.runsInRange(from: _from, to: _today),
    ).first;

    await repository.delete(target.id);
    cardsOf(await repository.runsInRange(from: _from, to: _today));
    final again = cardsOf(await repository.runsInRange(from: _from, to: _today));

    expect(again.map((c) => c.id), isNot(contains(target.id)));
  });

  test('없는 카드를 지우면 없다고 한다', () async {
    final repository = FakeRecordCardRepository(today: _today);

    expect(
      () => repository.delete('card-999999'),
      throwsA(
        isA<RecordCardException>().having(
          (e) => e.failure,
          'failure',
          RecordCardFailure.notFound,
        ),
      ),
    );
  });

  group('cardDeleteProvider', () {
    test('지우면 끝난 상태로 돌아온다', () async {
      final world = _World();

      final gone = await world.delete('card-7');

      expect(gone, isTrue);
      expect(world.repository.deleted, ['card-7']);
      expect(world.state, isA<CardDeleteIdle>());
    });

    // ⚠️ **달력 무효화는 여기서 못 본다.** 달력 컨트롤러가 인증·dio를
    // 깨워 서버 주소를 찾다 죽는다 — 실제 앱이 선 흐름 테스트가 본다
    // (`record_card_edit_flow_test.dart`).

    test('⚠️ 지우는 중에 또 누르면 한 번만 간다', () async {
      // 되돌릴 수 없는 일이다. 두 번 가면 두 번째는 404를 받는다.
      final world = _World(delay: const Duration(milliseconds: 50));

      final both = await Future.wait([world.delete('card-7'), world.delete('card-7')]);

      expect(world.repository.deleted, ['card-7']);
      expect(both.where((ok) => ok), hasLength(1));
    });

    test('도는 동안 상태가 Deleting이다', () async {
      final world = _World(delay: const Duration(milliseconds: 50));

      final soon = world.delete('card-7');
      expect(world.state, isA<CardDeleting>());

      await soon;
      expect(world.state, isA<CardDeleteIdle>());
    });

    test('⚠️ 지우면 프로필 그리드도 다시 받는다', () async {
      // 안 버리면 지운 카드가 프로필에 그대로 서 있다.
      final world = _World();
      world.container.listen(profileCardsProvider(_gridQuery), (_, _) {});
      await world.container.read(profileCardsProvider(_gridQuery).future);
      expect(world.repository.userCalls, 1);

      await world.delete('card-7');
      await Future<void>.delayed(Duration.zero);

      expect(world.repository.userCalls, 2);
    });

    test('⚠️ 실패하면 왜인지 들고 있고 다시 누를 수 있다', () async {
      final world = _World(failWith: RecordCardFailure.network);

      final gone = await world.delete('card-7');

      expect(gone, isFalse);
      expect(
        (world.state as CardDeleteFailed).failure,
        RecordCardFailure.network,
      );

      world.repository.failWith = null;
      expect(await world.delete('card-7'), isTrue);
    });
  });
}

// ── 도움 ──────────────────────────────────────────────────────

const _gridQuery = (userId: 'u-1', limit: 7);

final _today = DateTime(2026, 11, 18);
final _from = _today.subtract(const Duration(days: 20));

class _World {
  _World({Duration delay = Duration.zero, RecordCardFailure? failWith})
    : repository = _Repository(delay: delay, failWith: failWith) {
    container = ProviderContainer(
      overrides: [recordCardRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    addTearDown(container.listen(cardDeleteProvider, (_, _) {}).close);
  }

  final _Repository repository;
  late final ProviderContainer container;

  CardDeleteState get state => container.read(cardDeleteProvider);

  Future<bool> delete(String id) =>
      container.read(cardDeleteProvider.notifier).delete(id);
}

class _Repository implements RecordCardRepository {
  /// 몇 번 물었나. **저장·삭제가 프로필 그리드를 버리는지** 이 수로 본다.
  var userCalls = 0;

  @override
  Future<List<RecordCard>> byUser({required String userId, int? limit}) async {
    userCalls++;
    return const [];
  }

  _Repository({this.delay = Duration.zero, this.failWith});

  final Duration delay;
  RecordCardFailure? failWith;

  final deleted = <String>[];

  @override
  Future<RecordCard> detailOf(String cardId) =>
      throw UnsupportedError('이 테스트는 상세를 열지 않는다');

  @override
  Future<void> delete(String cardId) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final failure = failWith;
    if (failure != null) throw RecordCardException(failure);
    deleted.add(cardId);
  }

  @override
  Future<List<ComposableRecord>> runsInRange({
    required DateTime from,
    required DateTime to,
  }) async => const [];

  @override
  Future<RecordCard> create(NewRecordCard card) =>
      throw UnsupportedError('이 테스트는 카드를 만들지 않는다');

  @override
  Future<RecordCard> update(EditRecordCard card) =>
      throw UnsupportedError('이 테스트는 카드를 고치지 않는다');

  /// ⚠️ **곡은 카드가 들고 온다**(묶음 7 작업 5). 이 테스트는 삭제만 보므로
  /// 다시 만들 일이 없다.
  @override
  Future<void> retryMusic(String cardId) =>
      throw UnsupportedError('이 테스트는 음악을 다시 만들지 않는다');

}
