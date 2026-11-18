import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record_card/domain/card_draft.dart';
import 'package:runiverse/features/record_card/domain/card_photo_draft.dart';
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

CardPhotoDraft _photo({String caption = ''}) => CardPhotoDraft(
  image: PickedImage.validated(path: '/tmp/a.jpg', sizeBytes: 1024),
  caption: caption,
);

CardDraft _draft({
  RunRecord? record,
  RouteArt? route,
  RecordCardActivity? activity,
  String reviewText = '',
  List<CardPhotoDraft> photos = const [],
  RecordCardVisibility visibility = RecordCardVisibility.friends,
  bool musicEnabled = true,
}) => CardDraft(
  record: record,
  route: route,
  activity: activity,
  reviewText: reviewText,
  photos: photos,
  visibility: visibility,
  musicEnabled: musicEnabled,
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

  group('공개범위와 음악', () {
    test('기본값은 친구 공개와 음악 켜짐이다', () {
      // 설계 6-4가 정한 값이다.
      expect(const CardDraft().visibility, RecordCardVisibility.friends);
      expect(const CardDraft().musicEnabled, isTrue);
    });

    test('⚠️ 기본값에서 바뀌면 버리기 전에 묻는다', () {
      // 고른 공개범위를 안 세면, 나만 보기로 바꿔 둔 사람이 뒤로 눌렀을 때
      // 아무 경고 없이 그 선택이 사라진다.
      expect(_draft(visibility: RecordCardVisibility.private).isDirty, isTrue);
      expect(_draft(musicEnabled: false).isDirty, isTrue);
    });

    test('기본값 그대로면 묻지 않는다', () {
      expect(const CardDraft().isDirty, isFalse);
    });

    test('copyWith가 셋을 함께 옮긴다', () {
      final next = const CardDraft().copyWith(
        photos: [_photo()],
        visibility: RecordCardVisibility.public,
        musicEnabled: false,
      );

      expect(next.photos, hasLength(1));
      expect(next.visibility, RecordCardVisibility.public);
      expect(next.musicEnabled, isFalse);
    });
  });
}
