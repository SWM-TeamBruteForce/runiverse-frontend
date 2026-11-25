import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record_card/domain/card_draft.dart';
import 'package:runiverse/features/record_card/domain/card_photo_draft.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';

RunRecord _record({int id = 11}) => RunRecord(
  id: id,
  runningRoomId: id + 900,
  startedAt: DateTime(2026, 9, 2, 18, 54),
  distanceMeters: 5400,
  duration: const Duration(minutes: 28, seconds: 10),
  averagePace: const Duration(minutes: 5, seconds: 13),
  playerCount: 1,
);

const _route = RouteArt(
  strokes: [
    [RoutePoint(0, 0), RoutePoint(1, 1)],
  ],
  aspect: 1,
);

PickedImage _image() =>
    PickedImage.validated(path: '/tmp/a.jpg', sizeBytes: 1024);

RecordCard _card({int id = 7}) => RecordCard(
  id: 'card-$id',
  runningRecordId: 11,
  startedAt: DateTime(2026, 11, 2, 7),
  activity: RecordCardActivity.travel,
  visibility: RecordCardVisibility.public,
  reviewText: '여행에서 뛰었다',
  photos: const [
    RecordCardPhoto(id: 'img-70', url: 'https://x/a.jpg', caption: '첫째'),
    RecordCardPhoto(
      id: 'img-71',
      url: 'https://x/b.jpg',
      thumbnailUrl: 'https://x/b_s.jpg',
    ),
  ],
  route: _route,
  distanceMeters: 3050,
  duration: const Duration(minutes: 18),
  averagePace: const Duration(minutes: 5, seconds: 54),
  runners: const [],
);

CardPhotoDraft _photo({String caption = ''}) =>
    PickedPhoto(image: _image(), caption: caption);

CardDraft _draft({
  RunRecord? record,
  RouteArt? route,
  RecordCardActivity? activity,
  String reviewText = '',
  List<CardPhotoDraft> photos = const [],
  RecordCardVisibility visibility = RecordCardVisibility.friends,
}) => CardDraft(
  record: record,
  route: route,
  activity: activity,
  reviewText: reviewText,
  photos: photos,
  visibility: visibility,
);

void main() {
  test('⚠️ 다음은 기록·유형·회고가 다 차야 켜진다', () {
    expect(const CardDraft().canProceed, isFalse);
    expect(_draft(record: _record()).canProceed, isFalse);
    expect(
      _draft(record: _record(), activity: RecordCardActivity.daily).canProceed,
      isFalse,
    );
    expect(
      _draft(
        record: _record(),
        activity: RecordCardActivity.daily,
        reviewText: '좋았다',
      ).canProceed,
      isTrue,
    );
  });

  test('⚠️ 회고 없이 기록·유형만으로는 켜지지 않는다', () {
    // 설계 6-2가 회고를 필수로 못 박았다. 사진은 선택이지만 글은 아니다.
    expect(
      _draft(activity: RecordCardActivity.race, reviewText: '대회 완주').canProceed,
      isFalse,
    );
  });

  test('⚠️ 공백뿐인 회고는 쓴 것이 아니다', () {
    expect(
      _draft(
        record: _record(),
        activity: RecordCardActivity.daily,
        reviewText: '   \n ',
      ).canProceed,
      isFalse,
    );
  });

  test('⚠️ 경로가 없어도 쓸 수 있다 — 트레드밀 러닝이다', () {
    final draft = _draft(
      record: _record(),
      activity: RecordCardActivity.daily,
      reviewText: '실내에서',
    );

    expect(draft.route, isNull);
    expect(draft.canProceed, isTrue);
  });

  test('⚠️ 꽂혀 들어온 기록만으로는 버릴 때 묻지 않는다', () {
    // 진입할 때 앱이 꽂아 준 기록은 사용자가 쓴 것이 아니다. 그것만 보고
    // 확인을 받으면 잘못 들어온 사람이 나갈 때마다 막힌다.
    expect(const CardDraft().isDirty, isFalse);
    expect(_draft(record: _record()).isDirty, isFalse);
    expect(_draft(record: _record(), route: _route).isDirty, isFalse);
    expect(_draft(activity: RecordCardActivity.race).isDirty, isTrue);
    expect(_draft(reviewText: '한').isDirty, isTrue);
    expect(_draft(reviewText: '   ').isDirty, isFalse);
  });

  test('copyWith가 준 것만 바꾼다', () {
    final draft = _draft(
      record: _record(),
      activity: RecordCardActivity.daily,
      reviewText: '처음',
    );
    final next = draft.copyWith(reviewText: '고침');

    expect(next.reviewText, '고침');
    expect(next.activity, RecordCardActivity.daily);
    expect(next.record?.id, 11);
  });

  test('⚠️ clearRecord·clearRoute가 값을 비운다', () {
    // `copyWith(record: null)`로는 비울 수 없다 — null 은 "안 바꾼다"와
    // 구별되지 않는다. `RecordCardData.copyWith(clearFilter:)`와 같은 꼴이다.
    final draft = _draft(record: _record(), route: _route);

    expect(draft.copyWith(clearRoute: true).route, isNull);
    expect(draft.copyWith(clearRoute: true).record, isNotNull);
    expect(draft.copyWith(clearRecord: true).record, isNull);
  });

  test('회고 상한은 1000자다', () {
    expect(CardDraft.reviewMaxLength, 1000);
  });

  group('사진', () {
    test('상한은 다섯 장이다', () {
      // 기본 음악 1곡 + 사진 음악 5곡 = 6곡. 설계 6-3이 정한 값이다.
      expect(CardDraft.maxPhotos, 5);
      expect(const CardDraft().canAddPhoto, isTrue);
      expect(_draft(photos: List.filled(5, _photo())).canAddPhoto, isFalse);
    });

    test('⚠️ 사진은 다음 버튼의 조건이 아니다', () {
      // 설계 6-3: "사진은 선택이다. 한 장도 없이 다음을 누를 수 있다."
      final ready = _draft(
        record: _record(),
        activity: RecordCardActivity.daily,
        reviewText: '좋았다',
      );

      expect(ready.photos, isEmpty);
      expect(ready.canProceed, isTrue);
    });

    test('⚠️ 사진만 넣어도 버리기 전에 묻는다', () {
      // 사용자가 손으로 고른 것이다. 안 세면 뒤로 누른 사람의 사진을 조용히
      // 버린다 — 기록·경로와 달리 앱이 꽂아 준 것이 아니다.
      expect(_draft(photos: [_photo()]).isDirty, isTrue);
    });

    test('캡션 상한은 100자다', () {
      expect(CardPhotoDraft.captionMaxLength, 100);
    });

    test('사진 틀은 9:16이다', () {
      expect(CardPhotoDraft.aspectRatio, closeTo(9 / 16, 1e-9));
    });
  });

  /// 카드를 고치려고 뜬 초안 (설계 6-6).
  group('카드에서 뜬 초안', () {
    test('카드의 값이 그대로 들어온다', () {
      final draft = CardDraft.fromCard(_card());

      expect(draft.activity, _card().activity);
      expect(draft.visibility, _card().visibility);
      expect(draft.reviewText, _card().reviewText);
      expect(draft.photos, hasLength(2));
      expect(draft.photos.first, isA<SavedPhoto>());
      expect((draft.photos.first as SavedPhoto).caption, '첫째');
      expect(draft.route, same(_card().route));
    });

    test('⚠️ 고치는 카드를 들고 있다 — 러닝 기록이 아니다', () {
      // 카드는 **방 번호를 모른다**(설계 3절). `RunRecord`를 지어내면 가짜
      // 값이 들어가므로, 읽기 전용으로 보여 줄 것은 카드에서 바로 읽는다.
      final draft = CardDraft.fromCard(_card());

      expect(draft.editing?.id, _card().id);
      expect(draft.record, isNull);
    });

    test('⚠️ 뜬 초안은 아직 손대지 않은 것이다', () {
      // 참이면 들어오자마자 "이어 쓸까요?"를 묻는다 — 고치러 들어온 사람에게
      // 아무 말이나 묻는 꼴이다.
      expect(CardDraft.fromCard(_card()).isDirty, isFalse);
    });

    test('⚠️ 한 글자만 고쳐도 손댄 것이 된다', () {
      // 안 그러면 고치다 뒤로 나갈 때 아무 말 없이 버려진다.
      final draft = CardDraft.fromCard(_card());

      expect(draft.copyWith(reviewText: '고친 글').isDirty, isTrue);
      expect(draft.copyWith(photos: const []).isDirty, isTrue);
      expect(
        draft.copyWith(visibility: RecordCardVisibility.public).isDirty,
        isTrue,
      );
    });

    test('⚠️ 기록 없이도 저장할 수 있다 — 고치는 카드가 있으면', () {
      // `canProceed`가 `record`만 보면 수정이 영원히 못 저장한다.
      expect(CardDraft.fromCard(_card()).canProceed, isTrue);
    });

    test('회고를 비우면 저장하지 못한다', () {
      expect(
        CardDraft.fromCard(_card()).copyWith(reviewText: ' ').canProceed,
        isFalse,
      );
    });
  });

  /// 수정에서 작성 2를 다시 쓴다. 기존 사진이 안 보이면 **3장짜리 카드가
  /// 0장으로 열린다** — 그래서 초안이 두 종류를 함께 담는다.
  group('사진은 올린 것과 고른 것으로 갈린다', () {
    test('이미 올린 사진은 주소와 번호를 든다', () {
      const photo = SavedPhoto(
        id: 'img-7',
        url: 'https://x/a.jpg',
        thumbnailUrl: 'https://x/a_s.jpg',
        caption: '바다',
      );

      expect(photo.id, 'img-7');
      expect(photo.url, 'https://x/a.jpg');
      expect(photo.thumbnailUrl, 'https://x/a_s.jpg');
      expect(photo.caption, '바다');
    });

    test('새로 고른 사진은 파일과 민 위치를 든다', () {
      final photo = PickedPhoto(image: _image(), alignX: -0.5);

      expect(photo.image.path, '/tmp/a.jpg');
      expect(photo.alignX, -0.5);
      expect(photo.alignY, 0);
    });

    test('캡션은 종류와 상관없이 바뀐다', () {
      expect(const SavedPhoto(id: 'img-7', url: 'u').withCaption('가').caption, '가');
      expect(PickedPhoto(image: _image()).withCaption('가').caption, '가');
    });

    test('⚠️ 캡션을 바꿔도 종류와 나머지 값이 그대로다', () {
      // 종류가 섞이면 저장이 올린 사진을 새 사진으로 보고 다시 자른다.
      // ⚠️ 돌려주는 타입이 **자식 그대로**라 캐스트가 필요 없다 —
      // `CardPhotoDraft`로 좁아지면 여기서 캐스트가 생기고, 그것이 종류를
      // 잃었다는 신호다.
      final saved = const SavedPhoto(id: 'img-7', url: 'u').withCaption('가');
      expect(saved.id, 'img-7');
      expect(saved.url, 'u');

      final picked = PickedPhoto(image: _image(), alignX: 0.3).withCaption('가');
      expect(picked.alignX, 0.3);
      expect(picked.image.path, '/tmp/a.jpg');
    });

    test('⚠️ 민 위치는 새로 고른 것에만 있다', () {
      // 이미 9:16으로 잘려 올라간 사진은 옮길 데가 없다.
      final moved = PickedPhoto(
        image: _image(),
        caption: '가',
      ).withAlign(alignX: 1);

      expect(moved.alignX, 1);
      expect(moved.alignY, 0);
      expect(moved.caption, '가');
    });

    test('한 축만 주면 다른 축은 그대로다', () {
      final photo = PickedPhoto(image: _image(), alignX: -0.5, alignY: 0.3);

      expect(photo.withAlign(alignX: 0.8).alignY, 0.3);
      expect(photo.withAlign(alignY: -1).alignX, -0.5);
    });
  });

  group('공개범위', () {
    test('기본값은 친구 공개다', () {
      // 설계 6-4가 정한 값이다.
      expect(const CardDraft().visibility, RecordCardVisibility.friends);
    });

    test('⚠️ 기본값에서 바뀌면 버리기 전에 묻는다', () {
      // 고른 공개범위를 안 세면, 나만 보기로 바꿔 둔 사람이 뒤로 눌렀을 때
      // 아무 경고 없이 그 선택이 사라진다.
      expect(_draft(visibility: RecordCardVisibility.private).isDirty, isTrue);
    });

    test('기본값 그대로면 묻지 않는다', () {
      expect(const CardDraft().isDirty, isFalse);
    });

    test('copyWith가 둘을 함께 옮긴다', () {
      final next = const CardDraft().copyWith(
        photos: [_photo()],
        visibility: RecordCardVisibility.public,
      );

      expect(next.photos, hasLength(1));
      expect(next.visibility, RecordCardVisibility.public);
    });
  });
}
