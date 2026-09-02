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

/// [date]가 속한 주의 **월요일부터 일요일까지** 7일.
///
/// 주간 바차트와 주간 요약이 이 7일을 센다.
///
/// ## ⚠️ "최근 7일"이 아니다
///
/// 오늘부터 거꾸로 7일을 세면 **같은 주인데 날마다 집계 구간이 달라진다** —
/// 수요일에 본 "이번 주"와 목요일에 본 "이번 주"가 서로 다른 기간이 된다.
/// 요일 칸도 매일 밀려서 월요일이 왼쪽 끝에 있다가 오른쪽으로 옮겨 간다.
/// Figma S21도 `월 화 수 목 금 토 일` 순으로 고정해 두었다.
///
/// 아직 오지 않은 요일도 칸으로 남는다. 막대가 비어 있는 것이 곧 "아직
/// 안 뛴 날"이라 주의 남은 몫이 보인다.
///
/// 날짜 산술에 [Duration]을 쓰지 않는다 — `DateTime(년, 월, 일 ± n)`이
/// 월말·윤년을 알아서 넘겨 주고 서머타임에도 흔들리지 않는다.
List<DateTime> weekOf(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  // `weekday`는 월=1 … 일=7이다. 그만큼 되돌리면 그 주 월요일이다.
  final monday = DateTime(
    day.year,
    day.month,
    day.day - (day.weekday - DateTime.monday),
  );
  return [
    for (var i = 0; i < 7; i++)
      DateTime(monday.year, monday.month, monday.day + i),
  ];
}
