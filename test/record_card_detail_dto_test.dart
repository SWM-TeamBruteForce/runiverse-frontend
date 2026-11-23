import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record_card/data/record_card_detail_dto.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';

/// 카드 상세(8-1) 응답 읽기.
///
/// 계약은 「💾 [1.3.2] 기록 카드 프론트엔드 연동 가이드」 2절이다.
void main() {
  Map<String, dynamic> body({
    Object? routeArt,
    Object? images,
    Object? companions,
    Object? isMine,
    Object? activityType = 'DAILY',
    Object? visibility = 'FRIENDS',
  }) => {
    'recordCardId': '019aa100-0000-7000-8000-000000000099',
    'isMine': isMine,
    'activityType': activityType,
    'visibility': visibility,
    'memo': '강변을 따라 5km를 달렸어요.',
    'record': {
      'runningRecordId': 123,
      'startedAt': '2026-11-22T18:10:00',
      'totalDistanceMeters': 5000,
      'totalDurationSeconds': 1800,
      'averagePaceSecondsPerKm': 360,
      'routeArt': routeArt,
    },
    'images': ?images,
    'companions': ?companions,
  };

  group('카드 한 장', () {
    test('번호는 문자열, 러닝 기록 번호는 숫자다', () {
      final card = RecordCardDetailDto.from(body());

      expect(card.id, '019aa100-0000-7000-8000-000000000099');
      expect(card.runningRecordId, 123);
    });

    test('⚠️ 오프셋 없는 KST를 그대로 읽는다 — 날짜 칸이 여기 달려 있다', () {
      final card = RecordCardDetailDto.from(body());

      expect(card.startedAt, DateTime(2026, 11, 22, 18, 10));
      expect(card.day, DateTime(2026, 11, 22));
    });

    test('지표는 초와 미터에서 도메인 단위로 옮긴다', () {
      final card = RecordCardDetailDto.from(body());

      expect(card.distanceMeters, 5000);
      expect(card.duration, const Duration(minutes: 30));
      expect(card.averagePace, const Duration(minutes: 6));
    });

    test('유형과 공개범위를 읽는다', () {
      final card = RecordCardDetailDto.from(
        body(activityType: 'RACE', visibility: 'PUBLIC'),
      );

      expect(card.activity, RecordCardActivity.race);
      expect(card.visibility, RecordCardVisibility.public);
    });

    test('⚠️ 모르는 공개범위는 가장 닫힌 쪽으로 읽는다', () {
      // `public`으로 읽으면 나만 보려던 카드가 남에게 보인다.
      final card = RecordCardDetailDto.from(body(visibility: 'WHAT'));

      expect(card.visibility, RecordCardVisibility.private);
    });

    test('⚠️ isMine이 없으면 내 것이 아니다 — 모르면 손을 뗀다', () {
      expect(RecordCardDetailDto.from(body()).isMine, isFalse);
      expect(RecordCardDetailDto.from(body(isMine: false)).isMine, isFalse);
      expect(RecordCardDetailDto.from(body(isMine: true)).isMine, isTrue);
    });
  });

  group('사진', () {
    test('순서와 캡션, 대표 표시를 읽는다', () {
      final card = RecordCardDetailDto.from(
        body(
          images: [
            {
              'recordCardImageId': 'img-a',
              'imageUrl': 'https://x/a.jpg',
              'caption': '다리 위에서 본 노을',
              'isThumbnail': false,
            },
            {
              'recordCardImageId': 'img-b',
              'imageUrl': 'https://x/b.jpg',
              'isThumbnail': true,
            },
          ],
        ),
      );

      expect(card.photos.map((p) => p.id), ['img-a', 'img-b']);
      expect(card.photos.first.caption, '다리 위에서 본 노을');
      expect(card.photos.last.caption, isNull);
    });

    test('⚠️ 대표가 첫 장이 아닐 수 있다', () {
      // 가이드 4절: 대표를 둔 채 순서만 바꾸면 그 사진이 계속 대표다.
      // 순서로 가늠하면 둘째 장이 대표인 카드에서 틀린다.
      final card = RecordCardDetailDto.from(
        body(
          images: [
            {'recordCardImageId': 'img-a', 'isThumbnail': false},
            {'recordCardImageId': 'img-b', 'isThumbnail': true},
          ],
        ),
      );

      expect(card.photos.first.isThumbnail, isFalse);
      expect(card.photos.last.isThumbnail, isTrue);
    });

    test('사진이 없으면 빈 목록이다 — 오류가 아니다', () {
      expect(RecordCardDetailDto.from(body()).photos, isEmpty);
      expect(RecordCardDetailDto.from(body(images: const [])).photos, isEmpty);
    });
  });

  group('파티원', () {
    test('⚠️ companions가 비면 솔로다', () {
      expect(RecordCardDetailDto.from(body()).runners, isEmpty);
      expect(
        RecordCardDetailDto.from(body(companions: const [])).runners,
        isEmpty,
      );
    });

    test('⚠️ 번호를 읽는다 — 닉네임으로 "나"를 가리면 같은 이름에서 틀린다', () {
      final card = RecordCardDetailDto.from(
        body(
          companions: [
            {'userId': 'u-1', 'nickname': '바람', 'profileImageUrl': null},
            {'userId': 'u-2', 'nickname': '바람'},
          ],
        ),
      );

      expect(card.runners.map((r) => r.userId), ['u-1', 'u-2']);
      expect(card.runners.map((r) => r.nickname), ['바람', '바람']);
    });
  });

  group('경로', () {
    test('조각을 따로 담는다 — 사이를 잇지 않는다', () {
      // 일시정지로 끊긴 자리가 직선으로 이어지면 가 본 적 없는 길이 생긴다.
      final card = RecordCardDetailDto.from(
        body(
          routeArt: [
            [
              [0.0, 0.8],
              [0.3, 0.4],
            ],
            [
              [0.7, 0.2],
              [1.0, 0.5],
            ],
          ],
        ),
      );

      expect(card.route.strokes, hasLength(2));
      expect(card.route.strokes.first, hasLength(2));
    });

    test('⚠️ y를 뒤집지 않는다 — 서버가 이미 화면 방향으로 준다', () {
      final card = RecordCardDetailDto.from(
        body(
          routeArt: [
            [
              [0.0, 0.0],
              [1.0, 1.0],
            ],
          ],
        ),
      );

      expect(card.route.strokes.first.first.y, 0.0);
      expect(card.route.strokes.first.last.y, 1.0);
    });

    test('⚠️ 점이 200개를 넘겨 와도 전부 든다', () {
      // 가이드 2절: 조각이 아주 많으면 응답이 200점을 조금 넘을 수 있다.
      // 앱이 자르면 끝이 잘린 경로가 그려진다.
      final card = RecordCardDetailDto.from(
        body(
          routeArt: [
            [for (var i = 0; i < 260; i++) [i / 260, 0.5]],
          ],
        ),
      );

      expect(card.route.strokes.first, hasLength(260));
    });

    test('⚠️ 모양이 깨진 점만 버린다 — 경로 전체를 날리지 않는다', () {
      final card = RecordCardDetailDto.from(
        body(
          routeArt: [
            [
              [0.0, 0.0],
              [0.5],
              'x',
              [1.0, 1.0],
            ],
          ],
        ),
      );

      expect(card.route.strokes.first, hasLength(2));
    });

    test('경로가 없거나 빈 배열이면 그릴 것이 없다', () {
      expect(RecordCardDetailDto.from(body()).route.isEmpty, isTrue);
      expect(
        RecordCardDetailDto.from(body(routeArt: const [])).route.isEmpty,
        isTrue,
      );
    });

    test('⚠️ 가로/세로 비도 받은 점에서 되찾는다', () {
      // 서버가 비를 주지 않는다. 짧은 축이 0~1을 다 쓰지 않으면 그 비가
      // 실제 비다(`RouteArt.fromNormalized`).
      final card = RecordCardDetailDto.from(
        body(
          routeArt: [
            [
              [0.0, 0.0],
              [1.0, 0.5],
            ],
          ],
        ),
      );

      expect(card.route.aspect, closeTo(2.0, 1e-9));
    });
  });
}
