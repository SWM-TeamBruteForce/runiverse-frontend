import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record_card/domain/card_draft.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
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

CardDraft _draft({
  RunRecord? record,
  RouteArt? route,
  RecordCardActivity? activity,
  String reviewText = '',
}) => CardDraft(
  record: record,
  route: route,
  activity: activity,
  reviewText: reviewText,
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
      _draft(
        activity: RecordCardActivity.race,
        reviewText: '대회 완주',
      ).canProceed,
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
}
