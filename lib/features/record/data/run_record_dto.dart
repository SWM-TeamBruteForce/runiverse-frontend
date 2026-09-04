import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record/domain/run_record_repository.dart';

/// `GET /api/v1/users/me/running-records`(19번) 응답을 엔티티로 옮긴다.
///
/// **여기가 서버 형식을 아는 유일한 곳이다.** 필드 이름·단위가 도메인 밖으로
/// 새지 않게 한다 — 서버는 초와 미터로 주고, 도메인은 [Duration]으로 든다.
abstract final class RunRecordDto {
  const RunRecordDto._();

  /// 목록 응답 한 덩어리.
  ///
  /// 캘린더 모드는 `nextCursor`가 항상 `null`이라 페이지가 하나뿐이다.
  static RunRecordPage pageFrom(Map<String, dynamic> json) {
    final items = json['items'];
    return RunRecordPage(
      items: [
        if (items is List)
          for (final item in items)
            if (item is Map<String, dynamic>) recordFrom(item),
      ],
      nextCursor: json['nextCursor'] as String?,
    );
  }

  static RunRecord recordFrom(Map<String, dynamic> json) => RunRecord(
    id: json['runningRecordId'] as int,
    runningRoomId: json['runningRoomId'] as int,
    // ⚠️ **오프셋 없는 KST로 온다**(`2026-07-25T19:00:30`). `DateTime.parse`가
    // 이것을 로컬 시각으로 읽는데, 기기가 KST면 그게 맞다. `.toUtc()`를
    // 붙이면 9시간 밀려 **기록이 다른 날짜 칸에 붙는다.**
    startedAt: DateTime.parse(json['startedAt'] as String),
    distanceMeters: json['totalDistanceMeters'] as int,
    duration: Duration(seconds: json['totalDurationSeconds'] as int),
    averagePace: Duration(seconds: json['averagePaceSecondsPerKm'] as int),
    routePolyline: json['routePolyline'] as String? ?? '',
    // ⚠️ **19번 응답에 아직 없는 필드다.** 서버가 실어 주기 전까지 `null`이고,
    // 그동안 주간 요약의 누적 경사는 `--`로 나온다. 상세(20번)에는 이미 있다.
    elevationGainMeters: json['totalElevationGainMeters'] as int?,
  );
}
