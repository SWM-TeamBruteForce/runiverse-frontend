import 'package:runiverse/features/record/domain/run_record.dart';

/// 기록 여러 개를 한 줄로 줄인 것.
///
/// 화면 두 곳이 같은 값을 다르게 골라 쓴다.
///
/// | 자리 | 보여주는 것 |
/// |---|---|
/// | 월 요약 | 러닝 횟수 · 누적 거리 · 누적 시간 |
/// | 주간 요약 | 누적 거리 · 누적 시간 · 누적 경사 |
///
/// **평균 페이스는 넣지 않는다.** 기간 요약에 쓰지 않기로 했다 — 기록 하나의
/// 평균 페이스는 서버가 주지만(`RunRecord.averagePace`), 여러 개를 합친
/// 평균은 화면에서 요구하지 않는다.
class RecordSummary {
  const RecordSummary({
    required this.count,
    required this.totalMeters,
    required this.totalDuration,
    required this.elevationGainMeters,
  });

  /// 기록이 하나도 없을 때.
  static const empty = RecordSummary(
    count: 0,
    totalMeters: 0,
    totalDuration: Duration.zero,
    elevationGainMeters: null,
  );

  final int count;
  final int totalMeters;
  final Duration totalDuration;

  /// 누적 상승 고도(m). 주간 요약이 쓴다.
  ///
  /// ## ⚠️ 하나라도 모르면 통째로 `null`이다
  ///
  /// 아는 것만 더해 보여주면 **실제보다 반드시 작은 값**이 "누적 경사"라는
  /// 이름으로 확정돼 나간다. 사용자는 그게 부분합인지 알 길이 없다.
  /// 모를 때는 `--`로 두는 편이 맞다.
  ///
  /// 지금은 목록(19번)이 고도를 주지 않아 **항상 `null`이다.**
  /// → `RunRecord.elevationGainMeters`
  final int? elevationGainMeters;

  double get totalKm => totalMeters / 1000;

  bool get isEmpty => count == 0;

  /// [records]를 통째로 합친다.
  static RecordSummary of(Iterable<RunRecord> records) {
    var count = 0;
    var meters = 0;
    var duration = Duration.zero;

    // 하나라도 모르면 합계를 포기한다. 위 주석 참조.
    var elevation = 0;
    var knowsElevation = true;

    for (final record in records) {
      count++;
      meters += record.distanceMeters;
      duration += record.duration;

      final gain = record.elevationGainMeters;
      if (gain == null) {
        knowsElevation = false;
      } else {
        elevation += gain;
      }
    }

    return RecordSummary(
      count: count,
      totalMeters: meters,
      totalDuration: duration,
      // 기록이 없으면 "0m 올랐다"가 아니라 "모른다"다.
      elevationGainMeters: knowsElevation && count > 0 ? elevation : null,
    );
  }

  @override
  String toString() =>
      'RecordSummary($count회, ${totalKm.toStringAsFixed(1)}km)';
}

/// 기록을 날짜별로 묶는다. 캘린더의 점과 날짜별 목록이 이걸 쓴다.
///
/// 키는 [RunRecord.day]라 시·분·초가 0이다. 같은 날 두 번 뛰면 값이 2개다.
/// 각 날의 목록은 **시작 시각 오름차순**이다 — 화면이 `오전 6:40` → `오후 7:10`
/// 순서로 보여야 한다.
Map<DateTime, List<RunRecord>> groupRecordsByDay(Iterable<RunRecord> records) {
  final byDay = <DateTime, List<RunRecord>>{};

  for (final record in records) {
    byDay.putIfAbsent(record.day, () => []).add(record);
  }
  for (final list in byDay.values) {
    list.sort((a, b) => a.startedAt.compareTo(b.startedAt));
  }

  return byDay;
}

/// [end]까지의 [days]일치 날짜를 **과거→현재** 순으로 만든다.
///
/// 주간 바차트가 이걸로 칸을 세운다. 기록이 없는 날도 칸이 있어야 막대가
/// 빈 자리로 보인다 — 기록이 있는 날만 그리면 요일이 밀린다.
List<DateTime> lastDays(DateTime end, {int days = 7}) {
  final last = DateTime(end.year, end.month, end.day);
  return [for (var i = days - 1; i >= 0; i--) last.subtract(Duration(days: i))];
}
