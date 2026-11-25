import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record_card/data/route_art_wire.dart';
import 'package:runiverse/features/record_card/domain/composable_record.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_summary.dart';

/// `GET /api/v1/users/me/running-records?from=&to=` 응답을 읽는다 (7-1).
///
/// 한 행이 러닝 기록 하나이고, `recordCard`가 있으면 그 기록에 쓴 카드가 있다.
/// **내 비공개 카드도 포함된다**(연동 가이드 1절).
///
/// ## ⚠️ 기록 탭의 `RunRecordDto`를 쓰지 않는다
///
/// 같은 엔드포인트를 읽지만 **파서를 따로 둔다.**
///
/// - `record/data`를 import하면 `record_card/data → record/data`가 된다.
/// - 기록 탭 DTO에 `recordCard`를 더하면 **기록 탭이 카드를 알게 된다** —
///   방향이 거꾸로다. 기록 탭은 카드를 모른 채 돌아야 한다.
///
/// 값: 필드 이름이 같은 파서가 두 벌이다. **7-1 응답이 바뀌면 두 곳을 고친다.**
abstract final class RecordedRunDto {
  const RecordedRunDto._();

  /// 목록 한 덩어리. 기간에 기록이 없으면 **빈 배열**이고 오류가 아니다.
  ///
  /// 순서는 서버가 준 대로다 — `startedAt` 오름차순이다(가이드 1절).
  static List<ComposableRecord> listFrom(Map<String, dynamic> json) {
    final items = json['runningRecords'];
    return [
      if (items is List)
        for (final item in items)
          if (item is Map<String, dynamic>) rowFrom(item),
    ];
  }

  static ComposableRecord rowFrom(Map<String, dynamic> json) {
    // ⚠️ **오프셋 없는 KST로 온다**(`2026-07-25T19:00:30`). `DateTime.parse`가
    // 이것을 로컬 시각으로 읽는데, 기기가 KST면 그게 맞다. `.toUtc()`를
    // 붙이면 9시간 밀려 **카드가 다른 날짜 칸에 붙는다.**
    final startedAt = DateTime.parse(json['startedAt'] as String);
    final distanceMeters = json['totalDistanceMeters'] as int;

    return ComposableRecord(
      record: RunRecord(
        id: json['runningRecordId'] as int,
        runningRoomId: json['runningRoomId'] as int,
        startedAt: startedAt,
        distanceMeters: distanceMeters,
        duration: Duration(seconds: json['totalDurationSeconds'] as int),
        averagePace: Duration(seconds: json['averagePaceSecondsPerKm'] as int),
        // ⚠️ **모르는 값은 `null`이다.** 아무 값으로도 뭉개지 않는다.
        kind: RunKind.of(json['type']),
        // ⚠️ **못 읽으면 0이다.** 서버는 1 이상을 주므로 0은 "우리가 못
        // 읽었다"는 뜻이고, `RunRecord.isAlone`이 그때 `null`을 돌려준다.
        playerCount: json['playerCount'] as int? ?? 0,
        elevationGainMeters: json['totalElevationGainMeters'] as int?,
      ),
      // ⚠️ **`null`이면 카드가 없는 기록이다** — 오류가 아니다. 달력은 그 날에
      // 운동화를 두고, 작성 화면은 고를 수 있는 줄로 세운다.
      existingCard: switch (json['recordCard']) {
        final Map<String, dynamic> card => _summary(
          card,
          startedAt: startedAt,
          distanceMeters: distanceMeters,
        ),
        _ => null,
      },
    );
  }

  static RecordCardSummary _summary(
    Map<String, dynamic> json, {
    required DateTime startedAt,
    required int distanceMeters,
  }) => RecordCardSummary(
    id: json['recordCardId'] as String,
    // 같은 행의 바깥에서 왔다 — `recordCard` 안에는 없다.
    startedAt: startedAt,
    distanceMeters: distanceMeters,
    // ⚠️ **사진을 다 지운 카드는 `null`이다.** 그때 경로로 선을 긋는다.
    thumbnailUrl: json['thumbnailUrl'] as String?,
    route: routeArtFrom(json['routeArt']),
    // ⚠️ **모르는 값을 일상으로 뭉개지 않는다** — 필터가 거짓말을 한다.
    activity: RecordCardActivity.of(json['activityType']),
  );
}
