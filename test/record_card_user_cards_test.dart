import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record_card/data/fake_record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/new_record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';

import 'record_card_fixtures.dart';

/// 프로필 그리드·전체 보기가 읽는 조회 (10-3).
///
/// ## ⚠️ 거르는 것은 서버다
///
/// 보는 사람과 작성자의 관계로 서버가 인가를 적용한다(연동 가이드 5절) —
/// 앱이 거르면 **안 보여야 할 카드가 이미 기기에 와 있다**는 뜻이 된다.
/// 본인에게는 비공개도 온다(사용자 결정 2026-11-24).
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

  test('⚠️ 비공개도 온다 — 본인이 보는 자리다', () async {
    // 2026-11-24에 뒤집혔다. 10-3 항목에 `visibility`가 없어 **앱이 가려낼
    // 근거도 없다** — 서버가 보내면 그대로 선다.
    final page = await repo.cardsOf(userId: me, limit: 50);
    final ids = page.items.map((i) => i.id).toSet();
    final all = cardsOf(
      await repo.runsInRange(
        from: today.subtract(const Duration(days: 25)),
        to: today,
      ),
    );

    expect(ids, isNotEmpty);
    // 그 기간의 카드는 전부 들어 있다 — 걸러진 것이 없다.
    for (final card in all) {
      expect(ids, contains(card.id), reason: card.id);
    }
  });

  test('⚠️ 최신순이다 — 달력과 반대다', () async {
    // 달력은 날짜 오름차순으로 칸을 채우고, 그리드는 최근 것이 위다.
    final items = (await repo.cardsOf(userId: me, limit: 50)).items;

    for (var i = 1; i < items.length; i++) {
      expect(
        !items[i - 1].startedAt.isBefore(items[i].startedAt),
        isTrue,
        reason: '$i번째가 앞보다 최근이다',
      );
    }
  });

  test('limit만큼만 준다', () async {
    final page = await repo.cardsOf(userId: me, limit: 6);

    expect(page.items, hasLength(6));
    expect(page.hasMore, isTrue, reason: '더 있으면 커서를 준다');
  });

  test('⚠️ limit이 없으면 서버 기본값이다 — 전부가 아니다', () async {
    final page = await repo.cardsOf(userId: me);

    expect(
      page.items.length,
      lessThanOrEqualTo(FakeRecordCardRepository.defaultLimit),
    );
  });

  test('⚠️ 50을 넘기면 깎는다 — 거절이 아니다', () async {
    // 가이드 5절 3번: "50을 넘기면 50으로 적용되고".
    final page = await repo.cardsOf(userId: me, limit: 999);

    expect(
      page.items.length,
      lessThanOrEqualTo(FakeRecordCardRepository.maxLimit),
    );
  });

  test('⚠️ 1 미만과 잘못된 커서는 400이다', () async {
    expect(
      () => repo.cardsOf(userId: me, limit: 0),
      throwsA(
        isA<RecordCardException>().having(
          (e) => e.failure,
          'failure',
          RecordCardFailure.invalidRequest,
        ),
      ),
    );
    expect(
      () => repo.cardsOf(userId: me, cursor: 'x'),
      throwsA(isA<RecordCardException>()),
    );
  });

  test('⚠️ 커서로 이어 받으면 겹치지 않는다', () async {
    final first = await repo.cardsOf(userId: me, limit: 6);
    expect(first.nextCursor, isNotNull);

    final second = await repo.cardsOf(
      userId: me,
      limit: 6,
      cursor: first.nextCursor,
    );

    final firstIds = first.items.map((i) => i.id).toSet();
    final secondIds = second.items.map((i) => i.id).toSet();
    expect(firstIds.intersection(secondIds), isEmpty);
  });

  test('⚠️ 끝에 닿으면 커서가 없다 — 끝나지 않는 목록이 되지 않게', () async {
    var cursor = (await repo.cardsOf(userId: me, limit: 6)).nextCursor;
    final seen = <String>{};
    // 넉넉히 돈다. 커서가 사라지지 않으면 여기서 멈춘다.
    for (var i = 0; i < 50 && cursor != null; i++) {
      final page = await repo.cardsOf(userId: me, limit: 6, cursor: cursor);
      for (final item in page.items) {
        expect(seen.add(item.id), isTrue, reason: '${item.id}가 두 번 왔다');
      }
      cursor = page.nextCursor;
    }

    expect(cursor, isNull);
  });

  test('방금 만든 카드가 맨 앞에 선다', () async {
    final made = await repo.create(newCard());

    final page = await repo.cardsOf(userId: me, limit: 1);

    expect(page.items.single.id, made.id);
  });

  test('⚠️ 지운 카드는 빠진다', () async {
    final before = await repo.cardsOf(userId: me, limit: 50);
    await repo.delete(before.items.first.id);

    final after = await repo.cardsOf(userId: me, limit: 50);

    expect(
      after.items.map((i) => i.id),
      isNot(contains(before.items.first.id)),
    );
    expect(after.items, hasLength(before.items.length - 1));
  });

  test('사진 수를 함께 준다 — 칸이 그것으로 배지를 세울 수 있다', () async {
    final page = await repo.cardsOf(userId: me, limit: 50);

    expect(page.items.map((i) => i.imageCount), contains(greaterThan(0)));
  });

  test('⚠️ 실패를 흉내낸다 — 오류 화면을 눈으로 본다', () async {
    repo.failWith = RecordCardFailure.network;

    expect(
      () => repo.cardsOf(userId: me),
      throwsA(
        isA<RecordCardException>().having(
          (e) => e.failure,
          'failure',
          RecordCardFailure.network,
        ),
      ),
    );
  });

  test('누가 무엇을 물었는지 적어 둔다', () async {
    await repo.cardsOf(userId: 'u-7', limit: 6, cursor: '6');

    expect(repo.userQueries.single, (userId: 'u-7', limit: 6, cursor: '6'));
  });
}
