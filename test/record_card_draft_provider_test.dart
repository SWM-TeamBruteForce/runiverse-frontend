import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record_card/domain/card_draft.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';
import 'package:runiverse/features/record_card/presentation/card_draft_provider.dart';

RunRecord _record({required int id}) => RunRecord(
  id: id,
  runningRoomId: id + 900,
  startedAt: DateTime(2026, 9, 2, 18),
  distanceMeters: 5400,
  duration: const Duration(minutes: 28),
  averagePace: const Duration(minutes: 5, seconds: 13),
  playerCount: 1,
);

const _route = RouteArt(
  strokes: [
    [RoutePoint(0, 0), RoutePoint(1, 1)],
  ],
  aspect: 1,
);

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  CardDraftController notifier([int? cardId]) =>
      container.read(cardDraftProvider(cardId).notifier);

  CardDraft draft([int? cardId]) => container.read(cardDraftProvider(cardId));

  test('새 초안은 비어 있다', () {
    expect(draft().record, isNull);
    expect(draft().activity, isNull);
    expect(draft().reviewText, '');
  });

  test('⚠️ 기록을 바꾸면 앞 기록의 경로가 남지 않는다', () {
    // 남으면 11번 기록의 선 아트가 12번 카드에 그려진다.
    notifier().pickRecord(_record(id: 11));
    notifier().setRoute(_route);
    expect(draft().route, isNotNull);

    notifier().pickRecord(_record(id: 12));

    expect(draft().record?.id, 12);
    expect(draft().route, isNull);
  });

  test('⚠️ 같은 기록을 다시 골라도 경로를 버리지 않는다', () {
    // 목록을 다시 눌렀다고 받아 온 경로를 버리면 조회가 또 나간다.
    notifier().pickRecord(_record(id: 11));
    notifier().setRoute(_route);
    notifier().pickRecord(_record(id: 11));

    expect(draft().route, isNotNull);
  });

  test('⚠️ 회고가 1000자를 넘으면 잘라서 담는다', () {
    // 통째로 담으면 저장에서 거절당하고 쓴 글을 잃는다.
    notifier().setReview('가' * 1200);

    expect(draft().reviewText.length, CardDraft.reviewMaxLength);
  });

  test('⚠️ 보던 화면이 떠나도 초안은 남는다', () {
    // 작성이 세 화면이라 라우트를 넘나든다. autoDispose면 사진 화면으로 가는
    // 순간 작성 1의 구독이 끊겨 쓴 것이 사라진다(implementation-notes 5-1).
    final sub = container.listen(cardDraftProvider(null), (_, _) {});
    notifier().setReview('쓴 글');
    sub.close();

    expect(draft().reviewText, '쓴 글');
  });

  test('⚠️ 새 카드와 수정 중인 카드는 섞이지 않는다', () {
    // 작성 중에 남의 카드 수정으로 들어가도 안 섞여야 한다(설계 7절).
    notifier().setReview('새 카드');
    notifier(7).setReview('7번 수정');

    expect(draft().reviewText, '새 카드');
    expect(draft(7).reviewText, '7번 수정');
  });

  test('컨트롤러가 자기 카드 번호를 안다', () {
    expect(notifier().cardId, isNull);
    expect(notifier(7).cardId, 7);
  });

  test('유형을 고른다', () {
    notifier().setActivity(RecordCardActivity.travel);

    expect(draft().activity, RecordCardActivity.travel);
  });

  test('clear가 비운다', () {
    notifier().pickRecord(_record(id: 11));
    notifier().setActivity(RecordCardActivity.race);
    notifier().setReview('대회');

    notifier().clear();

    expect(draft().record, isNull);
    expect(draft().activity, isNull);
    expect(draft().reviewText, '');
  });

  test('경로를 null로 되돌릴 수 있다 — 못 받았을 때다', () {
    notifier().pickRecord(_record(id: 11));
    notifier().setRoute(_route);
    notifier().setRoute(null);

    expect(draft().route, isNull);
  });
}
