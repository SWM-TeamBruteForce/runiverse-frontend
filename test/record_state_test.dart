import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record/domain/record_summary.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record/presentation/record_state.dart';

/// 기록 탭 상태. **달 경계**가 이 화면의 유일한 까다로운 지점이다.
void main() {
  RunRecord record({
    required int id,
    required DateTime startedAt,
    required int meters,
  }) => RunRecord(
    id: id,
    runningRoomId: 100 + id,
    startedAt: startedAt,
    distanceMeters: meters,
    duration: const Duration(minutes: 30),
    averagePace: const Duration(minutes: 6),
    routePolyline: '',
  );

  // 9월 2일에 보는 화면. 최근 7일은 8월 27일부터다.
  final today = DateTime(2026, 9, 2);

  final september = record(
    id: 1,
    startedAt: DateTime(2026, 9, 2, 6, 40),
    meters: 5020,
  );
  final august = record(
    id: 2,
    startedAt: DateTime(2026, 8, 28, 7),
    meters: 10250,
  );

  RecordData data({required DateTime selectedDay}) => RecordData(
    month: DateTime(2026, 9),
    selectedDay: selectedDay,
    // 9월 조회 결과 — 8월 기록은 들어 있지 않다.
    monthRecords: [september],
    // 최근 7일 조회 결과 — 달을 넘어 8월이 섞인다.
    weekRecords: [august, september],
    weekDays: lastDays(today),
  );

  test('이번 달 날짜는 월 조회 결과에서 찾는다', () {
    final state = data(selectedDay: DateTime(2026, 9, 2));

    expect(state.selectedRecords.map((r) => r.id), [1]);
  });

  test('⚠️ 지난달 날짜를 골라도 기록을 찾는다', () {
    // 주간 막대는 8월 28일에 10.25km를 그리는데 목록이 "0회"라고 말하던
    // 버그다. 막대를 누르는 순간 재현된다.
    final state = data(selectedDay: DateTime(2026, 8, 28));

    expect(
      state.selectedRecords.map((r) => r.id),
      [2],
      reason: '주간 차트가 보여준 날인데 목록이 비면 서로 모순된다',
    );
  });

  test('정말 안 뛴 날은 비어 있다', () {
    final state = data(selectedDay: DateTime(2026, 9, 3));

    expect(state.selectedRecords, isEmpty);
  });

  test('주간 막대 높이의 기준은 가장 많이 뛴 날이다', () {
    final state = data(selectedDay: today);

    expect(state.weekPeakMeters, 10250);
    expect(state.metersOn(DateTime(2026, 8, 28)), 10250);
    expect(state.metersOn(DateTime(2026, 8, 30)), 0, reason: '안 뛴 날은 0이다');
  });

  test('날짜를 바꿔도 읽어 온 기록은 그대로다', () {
    final state = data(
      selectedDay: today,
    ).copyWith(selectedDay: DateTime(2026, 8, 28));

    expect(state.selectedRecords.map((r) => r.id), [2]);
    expect(state.monthSummary.count, 1, reason: '월 요약이 흔들리면 안 된다');
    expect(state.weekPeakMeters, 10250);
  });
}
