import 'package:runiverse/features/record/domain/split_aggregator.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';

/// 러닝 하나의 상세. **S16 화면이 그리는 것 전부**다.
///
/// ## 서버가 확정한 값이다
///
/// `GET /running-rooms/{id}/results`(17번)와 `.../split-results`(18번)를
/// 합친 것이다. 앱이 좌표에서 다시 계산하지 않는다 — 서버는 목표 거리를
/// 넘긴 구간을 잘라내는 등 앱이 모르는 규칙으로 기록을 만들고, 앱이 따로
/// 계산하면 **같은 러닝의 숫자가 화면마다 달라진다.**
///
/// ## 구간은 두 단위로 쓴다
///
/// 서버는 **10m 고정 경계**로 준다(파티원 비교를 위해서다). 화면은 구간
/// 테이블에 **1km**, 페이스·케이던스 그래프에 **50m**를 쓴다. 원본을 들고
/// 있다가 필요할 때 묶는다 — [tableSplits]·[chartSamples].
class RunDetail {
  RunDetail({
    required this.runningRoomId,
    required this.distanceMeters,
    required this.duration,
    required this.rawSplits,
    this.track = const [],
    this.averagePace,
    this.cadenceSpm,
    this.caloriesKcal,
    this.elevationGainMeters,
    this.players = const [],
    this.splitsByPlayer = const {},
  });

  final int runningRoomId;

  /// 같은 방에서 달린 사람 전원. **나도 들어 있다**([RunPlayerResult.isMe]).
  ///
  /// 서버가 준 순서 그대로다 — 러닝 화면의 레인 색이 이 순서로 정해졌으므로
  /// 여기서도 같은 사람이 같은 색이다. 솔로면 나 하나다.
  final List<RunPlayerResult> players;

  /// `userId` → 그 사람의 10m 구간. **파티원 것만 있다** — 내 것은 [rawSplits].
  ///
  /// 기록이 없는 사람(너무 짧게 달린 사람)은 여기 없다.
  final Map<String, List<RawSplit>> splitsByPlayer;

  /// 나를 뺀 파티원. 솔로면 비어 있다.
  List<RunPlayerResult> get party => [
    for (final player in players)
      if (!player.isMe) player,
  ];

  final Map<String, List<SplitBucket>> _tableSplitsOf = {};

  /// 파티원의 1km 묶음. 내 [tableSplits]와 같은 경계라 줄이 맞는다.
  List<SplitBucket> tableSplitsOf(String userId) => _tableSplitsOf.putIfAbsent(
    userId,
    () => SplitAggregator.bucket(
      splitsByPlayer[userId] ?? const [],
      SplitAggregator.tableMeters,
    ),
  );

  final Map<String, List<SplitBucket>> _chartSamplesOf = {};

  /// 파티원의 50m 묶음. 그래프의 두 번째 선이 쓴다.
  List<SplitBucket> chartSamplesOf(String userId) =>
      _chartSamplesOf.putIfAbsent(
        userId,
        () => SplitAggregator.bucket(
          splitsByPlayer[userId] ?? const [],
          SplitAggregator.chartMeters,
        ),
      );

  /// 서버가 확정한 총 거리(m).
  final int distanceMeters;

  /// 총 러닝 시간. 일시정지는 서버가 이미 빼고 준다.
  final Duration duration;

  /// 전체 평균 페이스. 서버가 못 내면 `null`이다.
  final Duration? averagePace;

  /// 전체 평균 케이던스. 표본이 부족하면 `null`이다.
  final int? cadenceSpm;

  final int? caloriesKcal;

  /// 누적 상승 고도(m). 표본이 부족하면 `null`이다.
  final int? elevationGainMeters;

  /// 지도에 그릴 경로. **본인 것만이다** — 파티원 경로는 어떤 화면으로도
  /// 내보내지 않는다.
  ///
  /// 서버는 한 줄로 주므로 세그먼트가 하나다. 지도 위젯이 세그먼트 목록을
  /// 받기 때문에 형태만 맞춘다.
  final List<List<GeoPoint>> track;

  /// 서버가 준 10m 구간 원본.
  final List<RawSplit> rawSplits;

  double get distanceKm => distanceMeters / 1000;

  bool get hasSplits => rawSplits.isNotEmpty;

  /// 구간 테이블이 쓰는 1km 묶음. 마지막은 짧을 수 있다.
  late final List<SplitBucket> tableSplits = SplitAggregator.bucket(
    rawSplits,
    SplitAggregator.tableMeters,
  );

  /// 페이스·케이던스 그래프가 쓰는 50m 묶음.
  ///
  /// 10m 그대로 그리면 5km에 500점이라 화면 폭을 넘고 잡음이 심하다.
  late final List<SplitBucket> chartSamples = SplitAggregator.bucket(
    rawSplits,
    SplitAggregator.chartMeters,
  );

  /// 구간 케이던스를 하나라도 아는가. 모르면 그래프를 접는다 —
  /// 빈 그래프는 "0spm으로 뛰었다"로 읽힌다.
  bool get hasCadence => chartSamples.any((s) => s.cadenceSpm != null);

  @override
  String toString() =>
      'RunDetail(room $runningRoomId, ${distanceKm.toStringAsFixed(2)}km, '
      '구간 ${rawSplits.length}개)';
}

/// 같은 방에서 달린 사람 하나의 결과. `GET /running-rooms/{id}/results`의
/// `players[]` 한 원소다.
///
/// ## 기록이 없을 수 있다
///
/// 너무 짧게 달렸거나(서버 기준 100m·60초 미만) 출발하지 않은 사람은 방에는
/// 있지만 수치가 전부 `null`이다. **0으로 때우지 않는다** — 0km를 달린 것이
/// 아니라 기록이 없는 것이다.
class RunPlayerResult {
  const RunPlayerResult({
    required this.userId,
    required this.nickname,
    required this.isMe,
    this.profileImageUrl,
    this.isDeleted = false,
    this.distanceMeters,
    this.duration,
    this.averagePace,
    this.cadenceSpm,
    this.caloriesKcal,
  });

  final String userId;

  /// 탈퇴한 사람은 서버가 익명 처리해서 준다.
  final String nickname;
  final bool isMe;
  final String? profileImageUrl;
  final bool isDeleted;

  final int? distanceMeters;
  final Duration? duration;
  final Duration? averagePace;
  final int? cadenceSpm;
  final int? caloriesKcal;

  bool get hasRecord => duration != null;
}
