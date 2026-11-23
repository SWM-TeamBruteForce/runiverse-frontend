import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record_card/data/fake_record_card_repository.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record_card/domain/edit_record_card.dart';
import 'package:runiverse/features/record_card/domain/new_record_card.dart';
import 'package:runiverse/features/record_card/domain/card_music.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_summary.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';

import 'record_card_fixtures.dart';

final _today = DateTime(2026, 11, 16);

DateTime _firstOf(DateTime month) => DateTime(month.year, month.month, 1);
DateTime _lastOf(DateTime month) => DateTime(month.year, month.month + 1, 0);

/// 두 달치를 **달마다 따로** 받아 합친다. 한 번에 31일을 넘길 수 없다.
Future<List<RecordCardSummary>> _twoMonths(FakeRecordCardRepository fake) async {
  final thisMonth = DateTime(_today.year, _today.month);
  final lastMonth = DateTime(_today.year, _today.month - 1);
  return [
    ...cardsOf(
      await fake.runsInRange(
        from: _firstOf(lastMonth),
        to: _lastOf(lastMonth),
      ),
    ),
    ...cardsOf(
      await fake.runsInRange(
        from: _firstOf(thisMonth),
        to: _lastOf(thisMonth),
      ),
    ),
  ];
}

/// 목에서 번호로 한 장 **전부**. 상세(8-1)가 주는 것과 같다.
Future<RecordCard> _cardOf(FakeRecordCardRepository repo, String id) =>
    repo.detailOf(id);

/// 두 달치 카드를 **전부** 받는다. 요약에는 사진·회고·공개범위가 없어서
/// 그것을 보는 테스트는 상세를 한 장씩 읽어야 한다.
Future<List<RecordCard>> _twoMonthsFull(FakeRecordCardRepository fake) async {
  final cards = await _twoMonths(fake);
  return [for (final card in cards) await fake.detailOf(card.id)];
}

NewRecordCard _newCard() => NewRecordCard(
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
);

void main() {
  late FakeRecordCardRepository fake;

  setUp(() => fake = FakeRecordCardRepository(today: _today));

  test('구간 밖의 카드는 안 준다', () async {
    final thisMonth = DateTime(_today.year, _today.month);
    final cards = await fake.runsInRange(
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
      () => fake.runsInRange(
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
      () => fake.runsInRange(
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
      () => failing.runsInRange(from: _firstOf(_today), to: _lastOf(_today)),
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
    await fake.runsInRange(from: _firstOf(_today), to: _lastOf(_today));

    expect(fake.calls, 1);
    expect(fake.queries.single.from, _firstOf(_today));
  });

  test('⚠️ 사진이 0장인 카드와 5장인 카드가 둘 다 있다', () async {
    final cards = await _twoMonthsFull(fake);

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
    final cards = await _twoMonthsFull(fake);

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
    final cards = await _twoMonthsFull(fake);

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

    /// 그 카드의 곡들. 0번이 기본곡이다.
    Future<List<CardMusic?>> tracks(String id) async {
      final card = await repo.detailOf(id);
      return [card.baseMusic, for (final photo in card.photos) photo.music];
    }

    test('⚠️ 목 카드가 곡별로 다른 상태를 보여 준다', () async {
      // 곡별 상태가 생긴 뒤에야 볼 수 있는 모양이다 — `card-1000`은 기본곡은
      // 다 됐고 첫 사진만 만드는 중이다.
      final mixed = await tracks('card-1000');
      expect(mixed.first!.status, MusicStatus.completed);
      expect(mixed[1]!.status, MusicStatus.generating);

      // 실패한 카드와, 서버가 아직 곡을 안 준 카드.
      expect((await tracks('card-1001')).first!.status, MusicStatus.failed);
      expect((await tracks('card-1002')).first, isNull);
      expect((await tracks('card-1003')).first!.status, MusicStatus.completed);
    });

    test('⚠️ 사진 없는 카드도 기본곡 하나는 있다', () async {
      // 번호 1001은 사진이 0장이다.
      expect(await tracks('card-1001'), hasLength(1));
    });

    test('⚠️ 못 만든 곡이 있으면 카드가 그렇다고 답한다', () async {
      expect((await repo.detailOf('card-1001')).hasFailedMusic, isTrue);
      expect((await repo.detailOf('card-1003')).hasFailedMusic, isFalse);
    });

    test('⚠️ 만드는 중인 곡이 하나라도 있으면 카드가 그렇다고 답한다', () async {
      // 기본곡은 다 됐는데 첫 사진이 만드는 중인 카드다.
      expect((await repo.detailOf('card-1000')).isMusicWorking, isTrue);
      expect((await repo.detailOf('card-1003')).isMusicWorking, isFalse);
    });

    test('다시 만들어 달라고 하면 만드는 중이 되고, 13초 뒤 끝난다', () async {
      await repo.retryMusic('card-1001');
      expect((await tracks('card-1001')).first!.status, MusicStatus.generating);

      now = now.add(const Duration(seconds: 13));
      expect((await tracks('card-1001')).first!.status, MusicStatus.completed);
    });

    test('⚠️ 다 되면 재생 주소가 붙는다', () async {
      await repo.retryMusic('card-1001');
      now = now.add(const Duration(seconds: 13));

      expect((await tracks('card-1001')).first!.url, isNotNull);
    });

    test('⚠️ 스무 번째 요청은 거치고 나서 실패한다 — 즉시가 아니다', () async {
      for (var i = 0; i < 19; i++) {
        await repo.retryMusic('card-1002');
      }
      await repo.retryMusic('card-1002');
      expect((await tracks('card-1002')).first!.status, MusicStatus.generating);

      now = now.add(const Duration(seconds: 13));
      expect((await tracks('card-1002')).first!.status, MusicStatus.failed);
    });

    test('⚠️ AI가 실패하면 그 요청의 곡이 함께 실패한다', () async {
      // 가이드 4절: 한 요청에 든 사진 곡과 기본곡이 함께 실패한다.
      for (var i = 0; i < 20; i++) {
        await repo.retryMusic('card-1002');
      }
      now = now.add(const Duration(seconds: 13));

      final all = await tracks('card-1002');
      expect(all, hasLength(6));
      for (final music in all) {
        expect(music!.status, MusicStatus.failed);
      }
    });

    test('⚠️ 저장하면 늘 음악을 요청한다', () async {
      // 서버는 카드를 확정할 때 기본곡과 사진별 곡 생성을 **항상** 요청한다
      // (연동 가이드 3절) — 끄는 인자가 요청에 없다. 가짜가 조건을 달면
      // "껐는데도 만들어진다"는 기기에서만 보이는 차이가 생긴다.
      final made = await repo.create(_newCard());

      expect((await tracks(made.id)).first!.status, MusicStatus.generating);
    });

    test('⚠️ 회고를 고치면 다 된 음악이 처음으로 돌아간다', () async {
      await repo.update(
        sameEdit(await _cardOf(repo, 'card-1003'), reviewText: '다른 글'),
      );

      expect((await tracks('card-1003')).first!.status, MusicStatus.generating);
    });

    test('⚠️ 공개범위만 바꾸면 음악은 그대로다', () async {
      await repo.update(
        sameEdit(
          await _cardOf(repo, 'card-1003'),
          visibility: RecordCardVisibility.public,
        ),
      );

      expect((await tracks('card-1003')).first!.status, MusicStatus.completed);
    });

    test('⚠️ 서버가 곡을 안 준 카드를 고치면 그때 만들기 시작한다', () async {
      // 저장이 늘 생성을 걸므로(가이드 3절) 수정도 같다 — AI가 읽는 값이
      // 바뀌면 다시 만든다. 묶음 5까지는 "안 만든 카드는 고쳐도 안 만든다"가
      // 규칙이었는데, 끄는 길이 없어지면서 그 구분도 사라졌다.
      await repo.update(
        sameEdit(await _cardOf(repo, 'card-1002'), reviewText: '다른 글'),
      );

      expect((await tracks('card-1002')).first!.status, MusicStatus.generating);
    });

    test('지운 카드는 없는 카드로 답한다', () async {
      await repo.delete('card-1003');

      expect(
        () => repo.detailOf('card-1003'),
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
      expect(
        () => repo.detailOf('card-77'),
        throwsA(isA<RecordCardException>()),
      );
      expect(
        () => repo.retryMusic('card-77'),
        throwsA(isA<RecordCardException>()),
      );
    });

    test('실패를 걸어 두면 상세도 못 읽는다 — 오류 줄을 눈으로 보는 길이다', () async {
      repo.failWith = RecordCardFailure.network;

      expect(
        () => repo.detailOf('card-1003'),
        throwsA(isA<RecordCardException>()),
      );
      expect(
        () => repo.retryMusic('card-1003'),
        throwsA(isA<RecordCardException>()),
      );
    });
  });
}
