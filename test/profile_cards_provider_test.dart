import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/profile/presentation/profile_cards_provider.dart';
import 'package:runiverse/features/record_card/data/fake_record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';

/// 프로필이 그 사람의 카드를 묻는다 (설계 6-7).
void main() {
  late FakeRecordCardRepository repo;
  late ProviderContainer container;

  setUp(() {
    repo = FakeRecordCardRepository(today: DateTime(2026, 11, 16));
    container = ProviderContainer(
      overrides: [recordCardRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
  });

  /// ⚠️ **듣는 사람을 붙인다.** `autoDispose`는 구독이 없으면 `read`마다 다시
  /// 만들어져, 두 번 읽으면 조회가 두 번 나간다(묶음 5에서 걸렸다).
  Future<List<RecordCard>> read(ProfileCardsQuery query) {
    container.listen(profileCardsProvider(query), (_, _) {});
    return container.read(profileCardsProvider(query).future);
  }

  test('공개된 카드를 최신순으로 돌려준다', () async {
    final cards = await read((userId: 'u-1', limit: null));

    expect(cards, isNotEmpty);
    expect(
      cards.every((c) => c.visibility != RecordCardVisibility.private),
      isTrue,
    );
    expect(cards.first.startedAt.isAfter(cards.last.startedAt), isTrue);
  });

  test('⚠️ 실패하면 바로 오류다 — 다시 부르지 않는다', () async {
    // Riverpod 3은 실패한 provider를 10번(약 38초) 다시 부른다. 그동안 화면은
    // 로딩만 돌고 **오류 분기에 닿지 못한다.**
    repo.failWith = RecordCardFailure.network;

    await expectLater(
      read((userId: 'u-1', limit: 7)),
      throwsA(isA<RecordCardException>()),
    );

    expect(repo.calls, 1);
  });

  test('⚠️ limit이 다르면 따로 받는다', () async {
    // 그리드는 7장(6 + 더 있나 한 장), 전체 보기는 전부다. 키에 limit이 없으면
    // 전체 보기가 그리드의 7장을 그대로 쓴다.
    await read((userId: 'u-1', limit: 7));
    await read((userId: 'u-1', limit: null));

    expect(repo.userQueries.map((q) => q.limit), [7, null]);
  });

  test('같은 물음은 한 번만 묻는다', () async {
    await read((userId: 'u-1', limit: 7));
    await read((userId: 'u-1', limit: 7));

    expect(repo.userQueries, hasLength(1));
  });
}
