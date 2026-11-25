import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';

RecordCard _card({
  DateTime? startedAt,
  List<RecordCardPhoto> photos = const [],
}) => RecordCard(
  id: 'card-1',
  runningRecordId: 10,
  startedAt: startedAt ?? DateTime(2026, 9, 2, 18, 54),
  activity: RecordCardActivity.daily,
  visibility: RecordCardVisibility.friends,
  reviewText: '오늘도 즐거운 러닝',
  photos: photos,
  route: RouteArt.empty,
  distanceMeters: 5400,
  duration: const Duration(minutes: 28, seconds: 10),
  averagePace: const Duration(minutes: 5, seconds: 38),
  runners: const [],
);

void main() {
  group('RecordCardActivity', () {
    test('활동 유형은 서버 코드로 오간다', () {
      expect(RecordCardActivity.of('DAILY'), RecordCardActivity.daily);
      expect(RecordCardActivity.of('RACE'), RecordCardActivity.race);
      expect(RecordCardActivity.of('TRAVEL'), RecordCardActivity.travel);

      expect(RecordCardActivity.daily.wire, 'DAILY');
      expect(RecordCardActivity.race.wire, 'RACE');
      expect(RecordCardActivity.travel.wire, 'TRAVEL');
    });

    test('⚠️ 모르는 활동 유형은 null이다 — 아무 값으로도 뭉개지 않는다', () {
      expect(RecordCardActivity.of('COMMUTE'), isNull);
      expect(RecordCardActivity.of('daily'), isNull);
      expect(RecordCardActivity.of(null), isNull);
      expect(RecordCardActivity.of(3), isNull);
    });
  });

  group('RecordCardVisibility', () {
    test('공개범위는 서버 코드로 오간다', () {
      expect(RecordCardVisibility.of('PUBLIC'), RecordCardVisibility.public);
      expect(RecordCardVisibility.of('FRIENDS'), RecordCardVisibility.friends);
      expect(RecordCardVisibility.of('PRIVATE'), RecordCardVisibility.private);

      expect(RecordCardVisibility.public.wire, 'PUBLIC');
      expect(RecordCardVisibility.friends.wire, 'FRIENDS');
      expect(RecordCardVisibility.private.wire, 'PRIVATE');
    });

    test('⚠️ FOLLOWERS도 friends로 읽는다 — 서버 값 이름이 아직 협의 중이다', () {
      expect(
        RecordCardVisibility.of('FOLLOWERS'),
        RecordCardVisibility.friends,
      );
    });

    test('⚠️ 모르는 공개범위는 private으로 떨어진다 — 모르면 안 보여준다', () {
      expect(RecordCardVisibility.of('EVERYONE'), RecordCardVisibility.private);
      expect(RecordCardVisibility.of(null), RecordCardVisibility.private);
      expect(RecordCardVisibility.of(7), RecordCardVisibility.private);
    });
  });

  group('RecordCard', () {
    test('썸네일은 첫 사진의 작은 쪽이다', () {
      final card = _card(
        photos: const [
          RecordCardPhoto(
            id: 'img-1',
            url: 'full-1.jpg',
            thumbnailUrl: 'thumb-1.jpg',
          ),
          RecordCardPhoto(id: 'img-2', url: 'full-2.jpg'),
        ],
      );

      expect(card.thumbnailUrl, 'thumb-1.jpg');
    });

    test('작은 쪽이 없으면 원본을 쓴다', () {
      final card = _card(
        photos: const [RecordCardPhoto(id: 'img-1', url: 'full-1.jpg')],
      );

      expect(card.thumbnailUrl, 'full-1.jpg');
    });

    test('⚠️ 사진이 없으면 null이다 — 부르는 쪽이 선 아트를 그린다', () {
      expect(_card().thumbnailUrl, isNull);
    });

    test('⚠️ day는 시·분을 자른다 — 자정 직전 러닝이 다른 날에 붙으면 안 된다', () {
      expect(
        _card(startedAt: DateTime(2026, 9, 2, 23, 50)).day,
        DateTime(2026, 9, 2),
      );
      expect(
        _card(startedAt: DateTime(2026, 9, 3, 0, 10)).day,
        DateTime(2026, 9, 3),
      );
    });
  });
}
