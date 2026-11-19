import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record_card/domain/card_draft.dart';
import 'package:runiverse/features/record_card/domain/edit_record_card.dart';
import 'package:runiverse/features/record_card/domain/music_inputs.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';

RecordCard _card({int photos = 0, String? caption}) => RecordCard(
  id: 7,
  runningRecordId: 107,
  startedAt: DateTime(2026, 9, 2, 18, 54),
  activity: RecordCardActivity.daily,
  visibility: RecordCardVisibility.friends,
  reviewText: '오늘은 성수동에서 달렸다.',
  photos: [
    for (var i = 0; i < photos; i++)
      RecordCardPhoto(
        id: 10 + i,
        url: 'assets/images/sign_in_hero.png',
        caption: caption ?? '사진 $i의 한마디',
      ),
  ],
  route: RouteArt.empty,
  distanceMeters: 5400,
  duration: const Duration(minutes: 28),
  averagePace: const Duration(minutes: 5, seconds: 38),
  runners: const [],
);

void main() {
  test('카드에서 뜬 초안은 입력이 같다 — 아무것도 안 건드렸다', () {
    final card = _card(photos: 2);

    expect(
      MusicInputs.ofDraft(CardDraft.fromCard(card)),
      MusicInputs.ofCard(card),
    );
  });

  test('⚠️ 공개범위만 바꾸면 입력이 같다 — AI가 읽는 값이 아니다', () {
    final card = _card(photos: 1);
    final draft = CardDraft.fromCard(
      card,
    ).copyWith(visibility: RecordCardVisibility.public);

    expect(MusicInputs.ofDraft(draft), MusicInputs.ofCard(card));
  });

  test('회고를 고치면 입력이 달라진다', () {
    final card = _card();
    final draft = CardDraft.fromCard(card).copyWith(reviewText: '다른 글');

    expect(MusicInputs.ofDraft(draft), isNot(MusicInputs.ofCard(card)));
  });

  test('유형을 바꾸면 입력이 달라진다', () {
    final card = _card();
    final draft = CardDraft.fromCard(
      card,
    ).copyWith(activity: RecordCardActivity.race);

    expect(MusicInputs.ofDraft(draft), isNot(MusicInputs.ofCard(card)));
  });

  test('⚠️ 캡션만 고쳐도 입력이 달라진다 — 사진 음악이 캡션을 읽는다', () {
    final card = _card(photos: 1);
    final draft = CardDraft.fromCard(card);
    final changed = draft.copyWith(
      photos: [draft.photos.first.withCaption('다른 한마디')],
    );

    expect(MusicInputs.ofDraft(changed), isNot(MusicInputs.ofCard(card)));
  });

  test('사진을 한 장 빼면 입력이 달라진다', () {
    final card = _card(photos: 2);
    final draft = CardDraft.fromCard(card);
    final changed = draft.copyWith(photos: [draft.photos.first]);

    expect(MusicInputs.ofDraft(changed), isNot(MusicInputs.ofCard(card)));
  });

  test('⚠️ 순서만 바꿔도 입력이 달라진다 — 장마다 곡이 따로다', () {
    final card = _card(photos: 2);
    final draft = CardDraft.fromCard(card);
    final changed = draft.copyWith(photos: draft.photos.reversed.toList());

    expect(MusicInputs.ofDraft(changed), isNot(MusicInputs.ofCard(card)));
  });

  test('⚠️ 캡션을 안 쓴 사진은 빈 글과 같다 — 카드는 null, 초안은 빈 문자열이다', () {
    final card = RecordCard(
      id: 7,
      runningRecordId: 107,
      startedAt: DateTime(2026, 9, 2),
      activity: RecordCardActivity.daily,
      visibility: RecordCardVisibility.friends,
      reviewText: '글',
      photos: const [RecordCardPhoto(id: 10, url: 'a.png')],
      route: RouteArt.empty,
      distanceMeters: 1,
      duration: Duration.zero,
      averagePace: Duration.zero,
      runners: const [],
    );

    expect(
      MusicInputs.ofDraft(CardDraft.fromCard(card)),
      MusicInputs.ofCard(card),
    );
  });

  test('수정 요청과 카드를 맞대 볼 수 있다', () {
    final card = _card(photos: 1);
    final same = EditRecordCard(
      cardId: card.id,
      activity: card.activity,
      // 공개범위는 세지 않는다.
      visibility: RecordCardVisibility.public,
      reviewText: card.reviewText,
      photos: [
        EditCardPhoto.saved(
          savedId: card.photos.first.id,
          caption: card.photos.first.caption,
        ),
      ],
    );

    expect(MusicInputs.ofEdit(same), MusicInputs.ofCard(card));
  });

  test('새로 넣은 사진이 있으면 입력이 달라진다', () {
    final card = _card(photos: 1);
    final added = EditRecordCard(
      cardId: card.id,
      activity: card.activity,
      visibility: card.visibility,
      reviewText: card.reviewText,
      photos: [
        EditCardPhoto.saved(
          savedId: card.photos.first.id,
          caption: card.photos.first.caption,
        ),
        const EditCardPhoto.added(path: '/tmp/b.jpg', thumbnailPath: null),
      ],
    );

    expect(MusicInputs.ofEdit(added), isNot(MusicInputs.ofCard(card)));
  });

  test('같은 입력이면 해시도 같다 — 맵의 열쇠로 쓸 수 있다', () {
    final card = _card(photos: 2);

    expect(
      MusicInputs.ofDraft(CardDraft.fromCard(card)).hashCode,
      MusicInputs.ofCard(card).hashCode,
    );
  });

  test('⚠️ 번호 12와 경로 12가 섞이지 않는다', () {
    final saved = MusicInputs.ofEdit(
      EditRecordCard(
        cardId: 7,
        activity: RecordCardActivity.daily,
        visibility: RecordCardVisibility.friends,
        reviewText: '글',
        photos: [const EditCardPhoto.saved(savedId: 12, caption: '한마디')],
      ),
    );
    final added = MusicInputs.ofEdit(
      EditRecordCard(
        cardId: 7,
        activity: RecordCardActivity.daily,
        visibility: RecordCardVisibility.friends,
        reviewText: '글',
        photos: [
          const EditCardPhoto.added(
            path: '12',
            thumbnailPath: null,
            caption: '한마디',
          ),
        ],
      ),
    );

    expect(saved, isNot(added));
  });
}
