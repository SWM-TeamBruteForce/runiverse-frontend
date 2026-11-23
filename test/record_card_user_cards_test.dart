import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record_card/data/fake_record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/edit_record_card.dart';
import 'package:runiverse/features/record_card/domain/new_record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';

/// 프로필 그리드가 읽는 조회 — **그 사람의 공개된 카드**(설계 6-7).
///
/// ## ⚠️ 거르는 것은 서버다
///
/// 앱이 `PRIVATE`를 거르면 **안 보여야 할 카드가 이미 기기에 와 있다**는 뜻이
/// 된다. 가짜가 서버 자리라 가짜가 거른다.
void main() {
  final today = DateTime(2026, 11, 16);
  const me = 'u-me';

  late FakeRecordCardRepository repo;

  setUp(() => repo = FakeRecordCardRepository(today: today));

  NewRecordCard newCard({
    RecordCardVisibility visibility = RecordCardVisibility.public,
  }) => NewRecordCard(
    record: RunRecord(
      id: 11,
      runningRoomId: 911,
      // ⚠️ **오늘 밤으로 둔다.** 목 카드가 오늘 저녁에도 있어, 자정으로 두면
      // 방금 만든 카드가 최신순에서 뒤로 간다.
      startedAt: today.add(const Duration(hours: 23)),
      distanceMeters: 5400,
      duration: const Duration(minutes: 28),
      averagePace: const Duration(minutes: 5, seconds: 13),
      playerCount: 1,
    ),
    route: RouteArt.empty,
    activity: RecordCardActivity.daily,
    visibility: visibility,
    reviewText: '좋았다',
    photos: const [],
  );

  EditRecordCard hide(RecordCard card) => EditRecordCard(
    cardId: card.id,
    activity: card.activity,
    visibility: RecordCardVisibility.private,
    reviewText: card.reviewText,
    photos: [
      for (final photo in card.photos)
        EditCardPhoto.saved(savedId: photo.id, caption: photo.caption),
    ],
  );

  test('⚠️ 비공개는 빠진다 — 내 카드여도', () async {
    // 사용자가 그렇게 정했다. 나만 보는 카드를 보는 자리는 기록카드 탭이다.
    final cards = await repo.byUser(userId: me);

    expect(cards, isNotEmpty);
    expect(
      cards.every((c) => c.visibility != RecordCardVisibility.private),
      isTrue,
    );
  });

  test('공개와 친구 공개는 둘 다 선다', () async {
    final cards = await repo.byUser(userId: me);

    expect(
      cards.map((c) => c.visibility).toSet(),
      containsAll(<RecordCardVisibility>[
        RecordCardVisibility.public,
        RecordCardVisibility.friends,
      ]),
    );
  });

  test('⚠️ 최신순이다 — 달력과 반대다', () async {
    // 달력은 날짜 오름차순으로 칸을 채우고, 그리드는 최근 것이 위다.
    final cards = await repo.byUser(userId: me);

    for (var i = 1; i < cards.length; i++) {
      expect(
        cards[i - 1].startedAt.isAfter(cards[i].startedAt) ||
            cards[i - 1].startedAt.isAtSameMomentAs(cards[i].startedAt),
        isTrue,
        reason: '$i번째가 앞보다 최근이다',
      );
    }
  });

  test('limit만큼만 준다', () async {
    final cards = await repo.byUser(userId: me, limit: 7);

    expect(cards, hasLength(7));
  });

  test('limit이 없으면 전부 준다', () async {
    final all = await repo.byUser(userId: me);
    final some = await repo.byUser(userId: me, limit: 3);

    expect(all.length, greaterThan(some.length));
    expect(all.take(3).map((c) => c.id), some.map((c) => c.id));
  });

  test('방금 만든 공개 카드가 맨 앞에 선다', () async {
    final made = await repo.create(newCard());

    final cards = await repo.byUser(userId: me, limit: 1);

    expect(cards.single.id, made.id);
  });

  test('⚠️ 지운 카드는 빠진다', () async {
    final before = await repo.byUser(userId: me);
    await repo.delete(before.first.id);

    final after = await repo.byUser(userId: me);

    expect(after.map((c) => c.id), isNot(contains(before.first.id)));
    expect(after, hasLength(before.length - 1));
  });

  test('⚠️ 고쳐서 비공개가 된 카드는 빠진다', () async {
    final before = await repo.byUser(userId: me);
    await repo.update(hide(before.first));

    final after = await repo.byUser(userId: me);

    expect(after.map((c) => c.id), isNot(contains(before.first.id)));
  });

  test('⚠️ 실패를 흉내낸다 — 오류 화면을 눈으로 본다', () async {
    repo.failWith = RecordCardFailure.network;

    expect(
      () => repo.byUser(userId: me),
      throwsA(
        isA<RecordCardException>().having(
          (e) => e.failure,
          'failure',
          RecordCardFailure.network,
        ),
      ),
    );
  });

  test('누가 물었는지 적어 둔다', () async {
    await repo.byUser(userId: 'u-7', limit: 7);

    expect(repo.userQueries.single, (userId: 'u-7', limit: 7));
  });
}
