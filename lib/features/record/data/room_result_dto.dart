import 'package:runiverse/features/record/domain/run_detail.dart';
import 'package:runiverse/features/record/domain/split_aggregator.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';

/// 러닝 결과 두 API를 [RunDetail] 하나로 합친다.
///
/// - `GET /running-rooms/{id}/results`(17번) — 합계·경로
/// - `GET /running-rooms/{id}/split-results`(18번) — 10m 구간
///
/// **여기가 서버 형식을 아는 유일한 곳이다.**
abstract final class RoomResultDto {
  const RoomResultDto._();

  static RunDetail merge({
    required Map<String, dynamic> results,
    required Map<String, dynamic> splitResults,
  }) {
    final players = _players(results['players']);
    final me = _me(results['players']);
    final myUserId = me?['userId'] as String?;
    final splitsByPlayer = _splitsByPlayer(splitResults);

    return RunDetail(
      runningRoomId: results['runningRoomId'] as int,
      // ⚠️ 두 API가 총 거리를 각각 준다. **18번 쪽이 구간과 맞는 값**이다
      // (마지막 10m 경계에서 끊은 값). 17번은 기록 그대로라 미세하게 다를
      // 수 있어, 구간 합계와 어긋나지 않도록 18번을 먼저 본다.
      distanceMeters:
          (splitResults['totalDistanceMeters'] as int?) ??
          (me?['totalDistanceMeters'] as int?) ??
          0,
      duration: Duration(seconds: (me?['totalDurationSeconds'] as int?) ?? 0),
      averagePace: _seconds(me?['averagePaceSecondsPerKm']),
      cadenceSpm: me?['averageCadenceSpm'] as int?,
      caloriesKcal: me?['totalCaloriesKcal'] as int?,
      elevationGainMeters:
          (splitResults['totalElevationGainMeters'] as int?) ??
          (me?['totalElevationGainMeters'] as int?),
      track: _track(results['routes']),
      rawSplits: splitsByPlayer[myUserId] ?? const [],
      players: players,
      // 내 것은 `rawSplits`에 있다. 두 곳에 두면 언젠가 한쪽만 고쳐진다.
      splitsByPlayer: {
        for (final entry in splitsByPlayer.entries)
          if (entry.key != myUserId) entry.key: entry.value,
      },
    );
  }

  /// `players[]` 전원. 서버가 준 순서를 지킨다 — 레인 색의 근거다.
  ///
  /// 수치가 `null`인 사람(기록 없음)도 남긴다. 빼면 "같이 달린 적 없는" 것처럼
  /// 보인다.
  static List<RunPlayerResult> _players(Object? players) {
    if (players is! List) return const [];
    return [
      for (final player in players)
        if (player is Map<String, dynamic> && player['userId'] is String)
          RunPlayerResult(
            userId: player['userId'] as String,
            nickname: (player['nickname'] as String?) ?? '',
            isMe: player['isMe'] == true,
            isDeleted: player['isDeleted'] == true,
            profileImageUrl: player['profileImageUrl'] as String?,
            distanceMeters: player['totalDistanceMeters'] as int?,
            duration: _seconds(player['totalDurationSeconds']),
            averagePace: _seconds(player['averagePaceSecondsPerKm']),
            cadenceSpm: player['averageCadenceSpm'] as int?,
            caloriesKcal: player['totalCaloriesKcal'] as int?,
          ),
    ];
  }

  /// `players[]`에서 **본인**을 찾는다.
  ///
  /// ⚠️ 파티원이 섞여 오므로 `isMe`로 골라야 한다. 첫 원소를 쓰면 남의
  /// 기록을 내 화면에 그리게 된다.
  static Map<String, dynamic>? _me(Object? players) {
    if (players is! List) return null;
    for (final player in players) {
      if (player is Map<String, dynamic> && player['isMe'] == true) {
        return player;
      }
    }
    return null;
  }

  static Duration? _seconds(Object? value) =>
      value is int ? Duration(seconds: value) : null;

  /// ⚠️ **위도가 먼저다**(`[[위도, 경도], …]`). GeoJSON과 반대라 뒤집어
  /// 읽으면 경로가 엉뚱한 곳에 그려진다 — 명세가 따로 못 박은 지점이다.
  ///
  /// 본인 기록이 없으면 `null`이 온다(빈 배열이 아니다).
  static List<List<GeoPoint>> _track(Object? routes) {
    if (routes is! List || routes.isEmpty) return const [];

    final points = <GeoPoint>[
      for (final point in routes)
        if (point is List && point.length >= 2)
          GeoPoint(
            latitude: (point[0] as num).toDouble(),
            longitude: (point[1] as num).toDouble(),
            // 서버 경로에 시각이 없다. 지도만 그리므로 쓰이지 않는다.
            recordedAt: DateTime.fromMillisecondsSinceEpoch(0),
          ),
    ];

    // 지도 위젯이 세그먼트 목록을 받는다. 서버는 한 줄로 주므로 하나다.
    return points.length < 2 ? const [] : [points];
  }

  /// 18번의 `splits[]`를 **사람별로** 가른다.
  ///
  /// 구간마다 `players[]`가 있고 그 안에 사람별 수치가 들어 있다. 구간 경계는
  /// 방 전체가 같으므로(10m 고정) 사람별 목록의 같은 자리가 같은 구간이다 —
  /// 다만 늦게 끝난 사람의 목록이 더 길다.
  static Map<String, List<RawSplit>> _splitsByPlayer(
    Map<String, dynamic> json,
  ) {
    final splits = json['splits'];
    if (splits is! List) return const {};

    final byPlayer = <String, List<RawSplit>>{};
    for (final split in splits) {
      if (split is! Map<String, dynamic>) continue;

      final players = split['players'];
      if (players is! List) continue;

      for (final player in players) {
        if (player is! Map<String, dynamic>) continue;
        final userId = player['userId'];
        final duration = player['durationSeconds'];
        if (userId is! String || duration is! int) continue;

        byPlayer
            .putIfAbsent(userId, () => [])
            .add(
              RawSplit(
                startDistanceMeters: split['startDistanceMeters'] as int,
                endDistanceMeters: split['endDistanceMeters'] as int,
                duration: Duration(seconds: duration),
                cadenceSpm: player['averageCadenceSpm'] as int?,
                caloriesKcal: (player['caloriesKcal'] as int?) ?? 0,
              ),
            );
      }
    }
    return byPlayer;
  }
}
