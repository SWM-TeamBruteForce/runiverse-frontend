import 'package:runiverse/features/record/domain/run_detail.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record/domain/run_record_repository.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/record/domain/split_aggregator.dart';

/// 서버 없이 기록 탭을 세우기 위한 목.
///
/// ## ⚠️ 진짜 기록이 아니다
///
/// 19번(`GET /users/me/running-records`)이 `개발전`이라 붙일 서버가 없다.
/// 화면의 세 상태(다회 / 단일 / 빈 날)와 월·주 요약을 모두 눈으로 확인할 수
/// 있도록 **일부러 그 셋이 다 나오게** 만든 값이다.
///
/// 서버가 열리면 provider에서 [HttpRunRecordRepository]로 바꾼다.
/// 이 파일은 그때 테스트용으로 남는다.
///
/// **경사는 채우지 않는다.** 19번이 아직 그 필드를 주지 않으므로, 목이 값을
/// 넣어 버리면 화면이 실제보다 잘 되는 것처럼 보인다 — 주간 요약의 누적 경사가
/// `--`로 나오는 지금 상태가 맞다.
class FakeRunRecordRepository implements RunRecordRepository {
  FakeRunRecordRepository({DateTime? today, this.delay = Duration.zero})
    : _today = today ?? DateTime.now();

  /// "오늘"을 어디로 볼 것인가. 목 데이터를 이 날 기준으로 만든다.
  final DateTime _today;

  /// 로딩 상태를 눈으로 보려고 두는 지연. 테스트에서는 0이다.
  final Duration delay;

  /// 몇 번 불렸나. 화면이 요청을 두 번 하는지(이번 달 + 최근 7일) 본다.
  var calls = 0;

  @override
  Future<List<RunRecord>> byDateRange({
    required DateTime from,
    required DateTime to,
  }) async {
    calls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);

    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);

    return [
      for (final record in _all())
        if (!record.day.isBefore(start) && !record.day.isAfter(end)) record,
    ];
  }

  @override
  Future<RunRecordPage> recent({String? cursor, int limit = 20}) async {
    calls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);

    final items = _all().toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return RunRecordPage(
      items: items.take(limit).toList(),
      // 목은 한 페이지뿐이다. 무한 스크롤을 시험하려면 여기를 늘린다.
      nextCursor: null,
    );
  }

  @override
  Future<RunDetail> byRoom(int runningRoomId) async {
    calls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);

    final record = _all().firstWhere(
      (r) => r.runningRoomId == runningRoomId,
      orElse: () => throw const RunRecordException(RunRecordFailure.server),
    );

    // 서버처럼 10m 고정 경계로 만든다. 화면이 다시 1km·50m로 묶는다.
    final count = record.distanceMeters ~/ 10;
    final perTen = record.duration.inMicroseconds / (count == 0 ? 1 : count);

    return RunDetail(
      runningRoomId: runningRoomId,
      distanceMeters: count * 10,
      duration: record.duration,
      averagePace: record.averagePace,
      cadenceSpm: 172,
      caloriesKcal: (record.distanceMeters * 0.06).round(),
      track: [_route(record)],
      rawSplits: [
        for (var i = 0; i < count; i++)
          RawSplit(
            startDistanceMeters: i * 10,
            endDistanceMeters: (i + 1) * 10,
            duration: Duration(
              microseconds: (perTen * _paceSwing[i % _paceSwing.length])
                  .round(),
            ),
            cadenceSpm: _cadencePattern[i % _cadencePattern.length],
            caloriesKcal: 1,
          ),
      ],
    );
  }

  static const _cadencePattern = [172, 176, 169, 178, 174, 171, 177];

  /// 구간 페이스 흔들림. 평균 언저리에서 ±6% 정도다.
  static const _paceSwing = [1.03, 0.96, 1.06, 0.98, 1.01, 0.94, 1.04];

  /// 지도에 그릴 가짜 경로. 북쪽으로 곧게 뻗는다.
  static List<GeoPoint> _route(RunRecord record) {
    const step = 0.0008983; // 위도 약 100m
    final points = (record.distanceMeters / 100).clamp(2, 200).toInt();
    return [
      for (var i = 0; i < points; i++)
        GeoPoint(
          latitude: 37.5 + step * i,
          longitude: 127.0,
          recordedAt: record.startedAt.add(Duration(seconds: i * 30)),
          accuracy: 5,
          speed: 3,
        ),
    ];
  }

  /// 오늘로부터 며칠 전에 무엇을 뛰었나.
  ///
  /// 하루에 둘(다회), 하루에 하나(단일), 아무것도 없는 날을 섞어 둔다.
  /// 화면의 날짜별 상태 3종이 전부 재현된다.
  static const _plan = <_Planned>[
    // 오늘 — 다회
    _Planned(daysAgo: 0, hour: 6, minute: 40, meters: 5020, seconds: 1800),
    _Planned(daysAgo: 0, hour: 19, minute: 10, meters: 3210, seconds: 1140),
    // 어제는 쉰다 — 캘린더에 점이 없는 날
    _Planned(daysAgo: 2, hour: 7, minute: 5, meters: 8040, seconds: 2760),
    _Planned(daysAgo: 4, hour: 20, minute: 30, meters: 4130, seconds: 1500),
    _Planned(daysAgo: 5, hour: 6, minute: 55, meters: 10250, seconds: 3480),
    // 주간 차트 밖, 이번 달 안 — 월 요약에만 잡힌다
    _Planned(daysAgo: 9, hour: 7, minute: 20, meters: 5000, seconds: 1770),
    _Planned(daysAgo: 12, hour: 18, minute: 45, meters: 6120, seconds: 2100),
    _Planned(daysAgo: 16, hour: 7, minute: 0, meters: 3050, seconds: 1080),
  ];

  Iterable<RunRecord> _all() sync* {
    for (var i = 0; i < _plan.length; i++) {
      final planned = _plan[i];
      final day = DateTime(
        _today.year,
        _today.month,
        _today.day,
      ).subtract(Duration(days: planned.daysAgo));

      yield RunRecord(
        id: 500 + i,
        runningRoomId: 120 + i,
        startedAt: DateTime(
          day.year,
          day.month,
          day.day,
          planned.hour,
          planned.minute,
        ),
        distanceMeters: planned.meters,
        duration: Duration(seconds: planned.seconds),
        averagePace: Duration(
          milliseconds: (planned.seconds * 1000 * 1000 / planned.meters)
              .round(),
        ),
        // 목록 카드는 아직 경로를 그리지 않는다. 빈 문자열로 둔다.
        routePolyline: '',
      );
    }
  }
}

class _Planned {
  const _Planned({
    required this.daysAgo,
    required this.hour,
    required this.minute,
    required this.meters,
    required this.seconds,
  });

  final int daysAgo;
  final int hour;
  final int minute;
  final int meters;
  final int seconds;
}
