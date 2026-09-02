import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record/domain/record_summary.dart';
import 'package:runiverse/features/record/domain/run_record.dart';

/// 기록 집계 — 화면 없이 여기서 다 확인한다.
void main() {
  RunRecord record({
    required int id,
    required DateTime startedAt,
    required int meters,
    required Duration duration,
    int? elevationGainMeters,
  }) => RunRecord(
    id: id,
    runningRoomId: 100 + id,
    startedAt: startedAt,
    distanceMeters: meters,
    duration: duration,
    // 서버가 준 값을 그대로 들고 있을 뿐이라 집계에 쓰이지 않는다.
    averagePace: Duration(
      microseconds: (duration.inMicroseconds * 1000 / meters).round(),
    ),
    routePolyline: '',
    elevationGainMeters: elevationGainMeters,
  );

  group('요약', () {
    test('기록이 없으면 비어 있고 경사도 모른다', () {
      final summary = RecordSummary.of([]);

      expect(summary.isEmpty, isTrue);
      expect(summary.count, 0);
      expect(summary.elevationGainMeters, isNull, reason: '0m 오른 게 아니라 모른다');
    });

    test('횟수와 거리를 더한다', () {
      final summary = RecordSummary.of([
        record(
          id: 1,
          startedAt: DateTime(2026, 7, 13, 6, 40),
          meters: 5000,
          duration: const Duration(minutes: 25),
        ),
        record(
          id: 2,
          startedAt: DateTime(2026, 7, 13, 19, 10),
          meters: 3200,
          duration: const Duration(minutes: 16),
        ),
      ]);

      expect(summary.count, 2);
      expect(summary.totalMeters, 8200);
      expect(summary.totalKm, closeTo(8.2, 0.001));
    });

    test('누적 경사를 더한다', () {
      final summary = RecordSummary.of([
        record(
          id: 1,
          startedAt: DateTime(2026, 7, 13),
          meters: 5000,
          duration: const Duration(minutes: 25),
          elevationGainMeters: 42,
        ),
        record(
          id: 2,
          startedAt: DateTime(2026, 7, 14),
          meters: 3000,
          duration: const Duration(minutes: 15),
          elevationGainMeters: 18,
        ),
      ]);

      expect(summary.elevationGainMeters, 60);
    });

    test('⚠️ 경사를 하나라도 모르면 통째로 모른다고 한다', () {
      // 아는 것만 더하면 실제보다 반드시 작은 값이 "누적 경사"로 확정된다.
      // 사용자는 그게 부분합인지 알 길이 없다.
      final summary = RecordSummary.of([
        record(
          id: 1,
          startedAt: DateTime(2026, 7, 13),
          meters: 5000,
          duration: const Duration(minutes: 25),
          elevationGainMeters: 42,
        ),
        record(
          id: 2,
          startedAt: DateTime(2026, 7, 14),
          meters: 3000,
          duration: const Duration(minutes: 15),
        ),
      ]);

      expect(summary.elevationGainMeters, isNull);
      expect(summary.totalMeters, 8000, reason: '거리는 그대로 더해야 한다');
    });
  });

  group('날짜별 묶기', () {
    test('같은 날의 두 러닝이 한 칸에 들어간다', () {
      final byDay = groupRecordsByDay([
        record(
          id: 1,
          startedAt: DateTime(2026, 7, 13, 6, 40),
          meters: 5000,
          duration: const Duration(minutes: 25),
        ),
        record(
          id: 2,
          startedAt: DateTime(2026, 7, 13, 19, 10),
          meters: 3200,
          duration: const Duration(minutes: 16),
        ),
        record(
          id: 3,
          startedAt: DateTime(2026, 7, 14, 7),
          meters: 4000,
          duration: const Duration(minutes: 20),
        ),
      ]);

      expect(byDay, hasLength(2), reason: '시·분이 달라도 같은 날이다');
      expect(byDay[DateTime(2026, 7, 13)], hasLength(2));
      expect(byDay[DateTime(2026, 7, 14)], hasLength(1));
    });

    test('⚠️ 하루 안에서는 시작 시각 순이다', () {
      // 화면이 `오전 6:40` → `오후 7:10` 순서로 보여야 한다.
      final byDay = groupRecordsByDay([
        record(
          id: 2,
          startedAt: DateTime(2026, 7, 13, 19, 10),
          meters: 3200,
          duration: const Duration(minutes: 16),
        ),
        record(
          id: 1,
          startedAt: DateTime(2026, 7, 13, 6, 40),
          meters: 5000,
          duration: const Duration(minutes: 25),
        ),
      ]);

      expect(byDay[DateTime(2026, 7, 13)]!.map((r) => r.id), [1, 2]);
    });
  });

  group('주간 구간', () {
    test('월요일에서 시작해 일요일에 끝난다', () {
      // 2026-09-02는 수요일이다.
      final days = weekOf(DateTime(2026, 9, 2, 22, 30));

      expect(days, hasLength(7));
      expect(days.first, DateTime(2026, 8, 31), reason: '그 주 월요일');
      expect(days.last, DateTime(2026, 9, 6), reason: '그 주 일요일');
      expect(days.first.weekday, DateTime.monday);
      expect(days.last.weekday, DateTime.sunday);
    });

    test('⚠️ 같은 주 안에서는 언제 봐도 같은 구간이다', () {
      // "최근 7일"이면 날마다 구간이 밀려 수요일과 목요일의 "이번 주"가
      // 달라진다. 주 단위로 고정한 이유다.
      final wednesday = weekOf(DateTime(2026, 9, 2));
      final saturday = weekOf(DateTime(2026, 9, 5));

      expect(wednesday, saturday);
    });

    test('⚠️ 일요일은 그 주의 끝이지 다음 주의 시작이 아니다', () {
      // `weekday`가 일=7이라 잘못 다루면 일요일 하루만 다음 주로 튄다.
      final sunday = weekOf(DateTime(2026, 9, 6));

      expect(sunday.first, DateTime(2026, 8, 31));
      expect(sunday.last, DateTime(2026, 9, 6));
    });

    test('달을 넘어가도 이어진다', () {
      // 주가 월 경계를 넘으므로 캘린더와 별도로 조회해야 한다.
      final days = weekOf(DateTime(2026, 9, 1));

      expect(days.first, DateTime(2026, 8, 31));
      expect(days.last, DateTime(2026, 9, 6));
    });
  });
}
