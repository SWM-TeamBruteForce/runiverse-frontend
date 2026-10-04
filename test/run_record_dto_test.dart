import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record/data/run_record_dto.dart';
import 'package:runiverse/features/record/domain/run_record.dart';

/// `RunRecordDto`가 지키는 약속.
///
/// ## ⚠️ 2026-10-01 에 응답 모양이 바뀌었다
///
/// 옛 `items[]` + `nextCursor` 가 **`runningRecords[]` 하나**가 됐고 페이지가
/// 사라졌다. 앱이 옛 키를 읽는 동안 **기록 탭이 빈 목록으로 떨어졌다** —
/// 오류가 아니라 조용히 비는 종류라 여기서 못 박는다.
///
/// 📅 기록 탭 연동 가이드 2장 · BE PR #72
void main() {
  Map<String, dynamic> record({
    Object? type = 'MATCH',
    Object? playerCount = 3,
    Object? elevation = 42,
  }) => {
    'runningRecordId': 501,
    'runningRoomId': 125,
    'type': ?type,
    'playerCount': ?playerCount,
    'startedAt': '2026-09-30T19:02:11',
    'totalDistanceMeters': 5020,
    'totalDurationSeconds': 1648,
    'averagePaceSecondsPerKm': 328,
    'totalElevationGainMeters': ?elevation,
    'routePolyline': 'u{~vFvyys@fS]pT_@',
  };

  group('응답 모양', () {
    test('⚠️ `runningRecords` 를 읽는다', () {
      final list = RunRecordDto.listFrom({
        'runningRecords': [record()],
      });

      expect(list, hasLength(1));
      expect(list.single.id, 501);
      expect(list.single.runningRoomId, 125);
    });

    test('⚠️ 옛 키(`items`)로는 아무것도 못 읽는다', () {
      // 이 테스트가 깨지는 날은 서버가 되돌아간 날이다. 그때 조용히 빈
      // 목록으로 떨어지는 대신 여기서 드러나게 한다.
      final list = RunRecordDto.listFrom({
        'items': [record()],
      });

      expect(list, isEmpty);
    });

    test('⚠️ 기록이 없으면 빈 목록이다 — 오류가 아니다', () {
      expect(RunRecordDto.listFrom({'runningRecords': <Object>[]}), isEmpty);
    });

    test('키가 아예 없어도 죽지 않는다', () {
      expect(RunRecordDto.listFrom(const {}), isEmpty);
    });
  });

  group('값 옮기기', () {
    test('초와 미터를 도메인 단위로 옮긴다', () {
      final it = RunRecordDto.recordFrom(record());

      expect(it.distanceMeters, 5020);
      expect(it.duration, const Duration(seconds: 1648));
      expect(it.averagePace, const Duration(seconds: 328));
    });

    test('⚠️ 오프셋 없는 KST 를 그대로 읽는다', () {
      // `.toUtc()`를 붙이면 9시간 밀려 **기록이 다른 날짜 칸에 붙는다.**
      final it = RunRecordDto.recordFrom(record());

      expect(it.startedAt, DateTime(2026, 9, 30, 19, 2, 11));
      expect(it.day, DateTime(2026, 9, 30));
    });

    test('누적 경사가 `null` 로 올 수 있다', () {
      // 유효 표본이 부족하면 서버가 `null`을 준다. **0으로 메우지 않는다** —
      // 합계를 낼 때 모르는 것과 0 m 를 구분해야 한다(가이드 3-2).
      expect(
        RunRecordDto.recordFrom(record(elevation: null)).elevationGainMeters,
        isNull,
      );
    });
  });

  group('방식과 인원', () {
    test('`SOLO` 와 `MATCH` 를 읽는다', () {
      expect(RunRecordDto.recordFrom(record(type: 'SOLO')).kind, RunKind.solo);
      expect(RunRecordDto.recordFrom(record()).kind, RunKind.match);
    });

    test('⚠️ 모르는 방식은 `null` 이다', () {
      // 아무 값으로도 뭉개지 않는다. `solo`로 읽으면 함께 달린 기록이 혼자
      // 달린 것으로 보인다.
      expect(RunRecordDto.recordFrom(record(type: 'PARTY')).kind, isNull);
      expect(RunRecordDto.recordFrom(record(type: null)).kind, isNull);
    });

    test('⚠️ 매칭인데 혼자 달린 기록을 가려낸다', () {
      // 상대가 안 나왔거나 시작 전에 빠지면 `MATCH` 인데 혼자 달린다 —
      // 홈의 1인 러닝 카드와 같은 사건이다(가이드 3-3).
      final alone = RunRecordDto.recordFrom(record(playerCount: 1));

      expect(alone.kind, RunKind.match);
      expect(alone.isAlone, isTrue);
    });

    test('함께 달린 기록은 혼자가 아니다', () {
      expect(RunRecordDto.recordFrom(record()).isAlone, isFalse);
    });

    test('⚠️ 인원을 못 읽으면 "혼자"라고 단정하지 않는다', () {
      // 서버는 1 이상을 준다. 없다는 것은 우리가 못 읽었다는 뜻이고, 그때
      // `isAlone`을 `false`로 두면 **함께 달린 기록이 혼자로 보인다.**
      final unknown = RunRecordDto.recordFrom(record(playerCount: null));

      expect(unknown.playerCount, 0);
      expect(unknown.isAlone, isNull);
    });
  });
}
