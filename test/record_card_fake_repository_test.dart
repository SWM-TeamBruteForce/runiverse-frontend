import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record_card/data/fake_record_card_repository.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record_card/domain/edit_record_card.dart';
import 'package:runiverse/features/record_card/domain/new_record_card.dart';
import 'package:runiverse/features/record_card/domain/music_generation.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';

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

/// 목에서 번호로 한 장. **단건 조회가 없어** 구간으로 받아 고른다.
Future<RecordCard> _cardOf(FakeRecordCardRepository repo, int id) async {
  final cards = await _twoMonths(repo);
  return cards.firstWhere((card) => card.id == id);
}

NewRecordCard _newCard({required bool musicEnabled}) => NewRecordCard(
  record: RunRecord(
    id: 11,
    runningRoomId: 911,
    startedAt: _today,
    distanceMeters: 5400,
    duration: const Duration(minutes: 28),
    averagePace: const Duration(minutes: 5, seconds: 13),
    playerCount: 1,
  ),
  route: RouteArt.empty,
  activity: RecordCardActivity.daily,
  visibility: RecordCardVisibility.friends,
  reviewText: '좋았다',
  photos: const [],
  musicEnabled: musicEnabled,
);

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

  // ── 음악 흉내 (설계 8절) ───────────────────────────────────────
  //
  // ⚠️ **타이머를 쓰지 않는다.** 요청 시각만 적어 두고 `clock()`과의 차로
  // 상태를 계산하므로, 테스트가 시계를 밀어 13초를 즉시 지난다.

  group('음악', () {
    late DateTime now;
    late FakeRecordCardRepository repo;

    setUp(() {
      now = DateTime(2026, 11, 16, 10);
      repo = FakeRecordCardRepository(today: _today, clock: () => now);
    });

    /// 카드를 **아무것도 안 바꾸고** 보내는 수정 요청.
    EditRecordCard sameEdit(
      RecordCard card, {
      String? reviewText,
      RecordCardVisibility? visibility,
    }) => EditRecordCard(
      cardId: card.id,
      activity: card.activity,
      visibility: visibility ?? card.visibility,
      reviewText: reviewText ?? card.reviewText,
      photos: [
        for (final photo in card.photos)
          EditCardPhoto.saved(savedId: photo.id, caption: photo.caption),
      ],
    );

    test('목 카드가 네 상태를 한 번씩 보여 준다', () async {
      expect((await repo.musicOf(1000)).status, MusicStatus.processing);
      expect((await repo.musicOf(1001)).status, MusicStatus.failed);
      expect((await repo.musicOf(1002)).status, MusicStatus.none);
      expect((await repo.musicOf(1003)).status, MusicStatus.succeeded);
    });

    test('⚠️ 사진 없는 카드도 한 곡이다', () async {
      // 번호 1001은 사진이 0장이다.
      expect((await repo.musicOf(1001)).trackCount, 1);
    });

    test('만들지 않은 카드는 곡이 0개다', () async {
      expect((await repo.musicOf(1002)).trackCount, 0);
    });

    test('요청하면 준비 중이고, 3초 뒤 만드는 중, 13초 뒤 끝난다', () async {
      expect((await repo.requestMusic(1002)).status, MusicStatus.queued);

      now = now.add(const Duration(seconds: 3));
      expect((await repo.musicOf(1002)).status, MusicStatus.processing);

      now = now.add(const Duration(seconds: 10));
      expect((await repo.musicOf(1002)).status, MusicStatus.succeeded);
    });

    test('요청하면 곡 수가 선다 — 사진 5장이면 6곡', () async {
      // 번호 1002는 사진이 5장이다.
      expect((await repo.requestMusic(1002)).trackCount, 6);
    });

    test('⚠️ 스무 번째 요청은 거치고 나서 실패한다 — 즉시가 아니다', () async {
      for (var i = 0; i < 19; i++) {
        await repo.requestMusic(1002);
      }
      expect((await repo.requestMusic(1002)).status, MusicStatus.queued);

      now = now.add(const Duration(seconds: 3));
      expect((await repo.musicOf(1002)).status, MusicStatus.processing);

      now = now.add(const Duration(seconds: 10));
      expect((await repo.musicOf(1002)).status, MusicStatus.failed);
    });

    test('실패한 뒤 다시 만들면 준비 중으로 돌아간다', () async {
      expect((await repo.requestMusic(1001)).status, MusicStatus.queued);
    });

    test('음악을 켜고 만든 카드는 준비 중으로 선다', () async {
      final made = await repo.create(_newCard(musicEnabled: true));

      expect((await repo.musicOf(made.id)).status, MusicStatus.queued);
    });

    test('음악을 끄고 만든 카드는 만들지 않는다', () async {
      final made = await repo.create(_newCard(musicEnabled: false));

      expect((await repo.musicOf(made.id)).status, MusicStatus.none);
    });

    test('⚠️ 회고를 고치면 다 된 음악이 처음으로 돌아간다', () async {
      final card = (await repo.musicOf(1003)).cardId;
      expect(card, 1003);

      await repo.update(sameEdit(await _cardOf(repo, 1003), reviewText: '다른 글'));

      expect((await repo.musicOf(1003)).status, MusicStatus.queued);
    });

    test('⚠️ 공개범위만 바꾸면 음악은 그대로다', () async {
      await repo.update(
        sameEdit(
          await _cardOf(repo, 1003),
          visibility: RecordCardVisibility.public,
        ),
      );

      expect((await repo.musicOf(1003)).status, MusicStatus.succeeded);
    });

    test('⚠️ 만들지 않은 카드를 고쳐도 만들기 시작하지 않는다', () async {
      await repo.update(sameEdit(await _cardOf(repo, 1002), reviewText: '다른 글'));

      expect((await repo.musicOf(1002)).status, MusicStatus.none);
    });

    test('지운 카드의 음악은 없는 카드로 답한다', () async {
      await repo.delete(1003);

      expect(
        () => repo.musicOf(1003),
        throwsA(
          isA<RecordCardException>().having(
            (e) => e.failure,
            'failure',
            RecordCardFailure.notFound,
          ),
        ),
      );
    });

    test('모르는 카드도 없는 카드다', () async {
      expect(() => repo.musicOf(77), throwsA(isA<RecordCardException>()));
      expect(() => repo.requestMusic(77), throwsA(isA<RecordCardException>()));
    });

    test('실패를 걸어 두면 음악도 못 읽는다 — 오류 줄을 눈으로 보는 길이다', () async {
      repo.failWith = RecordCardFailure.network;

      expect(() => repo.musicOf(1003), throwsA(isA<RecordCardException>()));
    });
  });
}
