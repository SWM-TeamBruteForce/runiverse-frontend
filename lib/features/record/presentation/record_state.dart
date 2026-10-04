import 'package:runiverse/features/record/domain/record_summary.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record/domain/run_record_repository.dart';

/// 기록 탭(S21)의 상태. loading / data / error 세 갈래다.
///
/// freezed를 아직 안 쓰므로 sealed class로 직접 적는다 — `RunSessionState`와
/// 같은 방식이라 화면의 `switch`가 세 갈래를 빠짐없이 처리하도록 강제된다.
sealed class RecordState {
  const RecordState();
}

class RecordLoading extends RecordState {
  const RecordLoading();
}

class RecordError extends RecordState {
  const RecordError(this.failure);

  final RunRecordFailure failure;
}

/// 읽어 온 기록. **집계는 여기서 끝나 있다.**
///
/// 화면이 합계를 내지 않는다(`docs/implementation-notes.md` 5-3). 위젯이
/// 매 빌드마다 다시 더하면 달을 넘길 때마다 같은 계산이 반복된다.
class RecordData extends RecordState {
  RecordData({
    required this.month,
    required this.selectedDay,
    required List<RunRecord> monthRecords,
    required List<RunRecord> rangeRecords,
    required this.weekDays,
    required this.stripDays,
  }) : byDay = groupRecordsByDay(monthRecords),
       monthSummary = RecordSummary.of(monthRecords),
       rangeByDay = groupRecordsByDay(rangeRecords),
       // ⚠️ **[rangeRecords] 전부를 더하지 않는다.** 그 구간은 주간 차트의
       // 7일과 가로 스트립의 7일을 **합친 것**이라 월~일 밖의 날이 섞인다.
       // 통째로 더하면 `주간 누적 거리`가 한 주보다 커진다.
       weekSummary = RecordSummary.of([
         for (final record in rangeRecords)
           if (weekDays.contains(record.day)) record,
       ]);

  /// 캘린더가 보고 있는 달. 항상 그 달 **1일 0시**다.
  final DateTime month;

  /// 지금 고른 날. 아래 목록이 이 날의 기록을 보여준다.
  final DateTime selectedDay;

  /// 이번 달 기록을 날짜별로 묶은 것. 캘린더의 점과 날짜별 목록이 쓴다.
  final Map<DateTime, List<RunRecord>> byDay;

  /// 월 요약 — 횟수 · 누적 거리 · 누적 시간.
  final RecordSummary monthSummary;

  /// 주간 차트의 칸. 과거→현재 7개다.
  ///
  /// ⚠️ **이 7일이 [month] 밖으로 나갈 수 있다.** 달 초에는 지난달 날짜가
  /// 섞이므로 캘린더와 **별도로 조회한** 결과를 쓴다.
  final List<DateTime> weekDays;

  /// 가로 스트립이 보여주는 7일. **오늘이 가운데**이고 앞뒤로 3일씩이다.
  ///
  /// ⚠️ [weekDays]와 **다른 7일이다.** 그쪽은 월~일 한 주이고 차트의 가로축
  /// 이다. 이쪽은 날짜를 고르는 자리라 오늘을 중심에 둔다.
  final List<DateTime> stripDays;

  /// [weekDays]와 [stripDays]를 **합친 구간**의 기록을 날짜별로 묶은 것.
  ///
  /// 둘이 겹치지 않을 수 있어(달 초) 한 번에 넓게 받아 나눠 쓴다.
  final Map<DateTime, List<RunRecord>> rangeByDay;

  /// 주간 요약 — 누적 거리 · 누적 시간 · 누적 경사.
  final RecordSummary weekSummary;

  /// [selectedDay]에 뛴 것들. 없으면 빈 목록이다.
  ///
  /// ## ⚠️ 이번 달 밖의 날도 찾는다
  ///
  /// 주간 차트의 7일이 **달 경계를 넘는다.** 9월 2일에 보는 주간 차트에는
  /// 8월 28일 막대가 서 있고, 그 막대를 누르면 8월 28일이 선택된다.
  /// [byDay]만 보면 "막대는 10km인데 목록은 0회"라고 말하게 된다 — 실제로
  /// 그렇게 났다.
  ///
  /// [rangeByDay]까지 뒤진다. 이번 달 날짜는 [byDay]가 완전하므로(한 달을
  /// 통째로 조회한다) 먼저 보고, 없을 때만 주간을 본다.
  List<RunRecord> get selectedRecords =>
      byDay[selectedDay] ?? rangeByDay[selectedDay] ?? const <RunRecord>[];

  /// 주간 차트에서 가장 긴 하루의 거리(m). 막대 높이의 기준이다.
  ///
  /// 하나도 없으면 `0`이라 부르는 쪽이 0으로 나누지 않게 막아야 한다.
  int get weekPeakMeters {
    var peak = 0;
    for (final day in weekDays) {
      final meters = RecordSummary.of(rangeByDay[day] ?? const []).totalMeters;
      if (meters > peak) peak = meters;
    }
    return peak;
  }

  /// [day]에 뛴 거리(m). 안 뛰었으면 0이다.
  int metersOn(DateTime day) =>
      RecordSummary.of(rangeByDay[day] ?? const []).totalMeters;

  RecordData copyWith({DateTime? selectedDay}) => RecordData(
    month: month,
    selectedDay: selectedDay ?? this.selectedDay,
    monthRecords: [for (final list in byDay.values) ...list],
    rangeRecords: [for (final list in rangeByDay.values) ...list],
    weekDays: weekDays,
    stripDays: stripDays,
  );
}
