import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record_card/data/recorded_run_dto.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';

/// 러닝 기록 목록(7-1) 읽기 — **카드 유무가 같은 행에 실려 온다.**
///
/// 계약은 「💾 [1.3.2] 기록 카드 프론트엔드 연동 가이드」 1절이다.
void main() {
  Map<String, dynamic> row({
    int id = 123,
    String startedAt = '2026-11-22T18:10:00',
    Object? type = 'SOLO',
    Object? recordCard,
  }) => {
    'runningRecordId': id,
    'runningRoomId': id + 900,
    'startedAt': startedAt,
    'totalDistanceMeters': 5000,
    'totalDurationSeconds': 1800,
    'averagePaceSecondsPerKm': 360,
    'type': type,
    'playerCount': 1,
    'recordCard': recordCard,
  };

  Map<String, dynamic> body(List<Map<String, dynamic>> rows) => {
    'runningRecords': rows,
  };

  group('러닝 기록', () {
    test('기간에 기록이 없으면 빈 목록이다 — 오류가 아니다', () {
      expect(RecordedRunDto.listFrom(body(const [])), isEmpty);
      expect(RecordedRunDto.listFrom(const {}), isEmpty);
    });

    test('⚠️ 오프셋 없는 KST를 그대로 읽는다', () {
      final rows = RecordedRunDto.listFrom(body([row()]));

      expect(rows.single.record.startedAt, DateTime(2026, 11, 22, 18, 10));
      expect(rows.single.day, DateTime(2026, 11, 22));
    });

    test('⚠️ 자정 직전에 시작한 러닝은 시작한 날에 붙는다', () {
      final rows = RecordedRunDto.listFrom(
        body([row(startedAt: '2026-11-22T23:50:00')]),
      );

      expect(rows.single.day, DateTime(2026, 11, 22));
    });

    test('러닝 종류를 읽는다 — 모르는 값은 null이다', () {
      expect(
        RecordedRunDto.listFrom(body([row(type: 'MATCH')])).single.record.kind,
        RunKind.match,
      );
      expect(
        RecordedRunDto.listFrom(body([row(type: 'WHAT')])).single.record.kind,
        isNull,
      );
    });
  });

  group('카드 유무', () {
    test('⚠️ recordCard가 null이면 카드가 없는 기록이다', () {
      final rows = RecordedRunDto.listFrom(body([row()]));

      expect(rows.single.hasCard, isFalse);
      expect(rows.single.existingCardId, isNull);
    });

    test('카드가 있으면 번호와 유형이 붙어 온다', () {
      final rows = RecordedRunDto.listFrom(
        body([
          row(
            recordCard: {
              'recordCardId': 'card-99',
              'thumbnailUrl': 'https://x/t.jpg',
              'activityType': 'TRAVEL',
              'routeArt': const [],
            },
          ),
        ]),
      );

      final card = rows.single.existingCard!;
      expect(card.id, 'card-99');
      expect(card.thumbnailUrl, 'https://x/t.jpg');
      expect(card.activity, RecordCardActivity.travel);
    });

    test('⚠️ 날짜와 거리는 행 바깥에서 온다 — 카드 안에는 없다', () {
      final rows = RecordedRunDto.listFrom(
        body([row(recordCard: {'recordCardId': 'card-99'})]),
      );

      final card = rows.single.existingCard!;
      expect(card.startedAt, rows.single.record.startedAt);
      expect(card.distanceMeters, 5000);
    });

    test('⚠️ 사진을 다 지운 카드는 썸네일이 없고 경로만 남는다', () {
      // 가이드 1절 표의 마지막 갈래다. 썸네일이 `null`이면 칸은 선을 긋는다.
      final rows = RecordedRunDto.listFrom(
        body([
          row(
            recordCard: {
              'recordCardId': 'card-99',
              'thumbnailUrl': null,
              'routeArt': [
                [
                  [0.0, 0.0],
                  [1.0, 0.5],
                ],
              ],
            },
          ),
        ]),
      );

      final card = rows.single.existingCard!;
      expect(card.thumbnailUrl, isNull);
      expect(card.route.isNotEmpty, isTrue);
      // 비도 받은 점에서 되찾는다.
      expect(card.route.aspect, closeTo(2.0, 1e-9));
    });

    test('⚠️ 사진도 경로도 없으면 그릴 것이 없다 — 칸이 점 하나를 남긴다', () {
      final rows = RecordedRunDto.listFrom(
        body([
          row(recordCard: {'recordCardId': 'card-99', 'routeArt': const []}),
        ]),
      );

      final card = rows.single.existingCard!;
      expect(card.thumbnailUrl, isNull);
      expect(card.route.isEmpty, isTrue);
    });

    test('⚠️ 모르는 활동 유형은 null이다 — 일상으로 뭉개지 않는다', () {
      // 대회에서 뛴 카드가 일상 필터에 걸리면 필터가 거짓말을 한다.
      final rows = RecordedRunDto.listFrom(
        body([
          row(recordCard: {'recordCardId': 'card-99', 'activityType': 'WHAT'}),
        ]),
      );

      expect(rows.single.existingCard!.activity, isNull);
    });

    test('⚠️ y를 뒤집지 않는다 — 서버가 이미 화면 방향으로 준다', () {
      final rows = RecordedRunDto.listFrom(
        body([
          row(
            recordCard: {
              'recordCardId': 'card-99',
              'routeArt': [
                [
                  [0.0, 0.0],
                  [1.0, 1.0],
                ],
              ],
            },
          ),
        ]),
      );

      final stroke = rows.single.existingCard!.route.strokes.single;
      expect(stroke.first.y, 0.0);
      expect(stroke.last.y, 1.0);
    });
  });

  group('여러 줄', () {
    test('서버가 준 순서를 지킨다 — 시작 시각 오름차순이다', () {
      final rows = RecordedRunDto.listFrom(
        body([
          row(id: 1, startedAt: '2026-11-22T07:00:00'),
          row(
            id: 2,
            startedAt: '2026-11-22T19:00:00',
            recordCard: {'recordCardId': 'card-2'},
          ),
        ]),
      );

      expect(rows.map((r) => r.record.id), [1, 2]);
      expect(rows.first.hasCard, isFalse);
      expect(rows.last.existingCardId, 'card-2');
    });

    test('⚠️ 모양이 깨진 줄은 버린다 — 목록 전체를 날리지 않는다', () {
      final rows = RecordedRunDto.listFrom({
        'runningRecords': ['x', row(id: 1), 7],
      });

      expect(rows.map((r) => r.record.id), [1]);
    });
  });
}
