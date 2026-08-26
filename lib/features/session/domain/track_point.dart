import 'package:runiverse/features/session/domain/geo_point.dart';

/// 서버로 보낼 좌표 한 점. `RUNNING_LOCATION_UPDATE`의 `locations[]` 항목.
///
/// ## [GeoPoint]와 무엇이 다른가
///
/// [GeoPoint]는 **기기가 준 것**이고, 이쪽은 **서버에 보낼 것**이다.
/// 순번([sequence])과 그 시점의 페이스·케이던스가 더 붙는다 — 기기가 주지 않고
/// 앱이 계산하는 값이다.
///
/// ## 저장할 때 계산해 박아 둔다
///
/// 페이스를 **전송 시점이 아니라 저장 시점에** 계산한다. 전송 시점에 하면
/// 재전송할 때마다 이미 지나간 시점의 페이스를 재현해야 한다. 박아 두면
/// 재전송이 **읽어서 보내기**로 끝난다(설계 문서 6절).
class TrackPoint {
  const TrackPoint({
    required this.sequence,
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.speedMetersPerSecond,
    required this.recordedAt,
    this.altitudeMeters,
    this.headingDegrees,
    this.cadenceSpm,
    this.currentPaceSecondsPerKm,
  });

  /// 이 러닝 안의 순번. 1부터 센다.
  ///
  /// 서버가 `(runningRoomId, userId, sequence)`로 중복을 거른다. 그래서 같은
  /// 좌표를 두 번 보내도 안전하고, 재전송이 겹쳐도 문제가 없다.
  final int sequence;

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final double speedMetersPerSecond;

  /// 못 구하면 `null`. 명세도 nullable이다.
  final double? altitudeMeters;

  /// 못 구하면 `null`. **보낼 때 `0`으로 눌린다** — [toJson] 참조.
  final double? headingDegrees;

  /// 걸음 센서가 붙기 전까지 항상 `null`이다(5단계).
  final int? cadenceSpm;

  /// 그 시점의 최근 30초 페이스. 러닝 초반에는 낼 수 없어 `null`이다.
  final int? currentPaceSecondsPerKm;

  final DateTime recordedAt;

  /// 기기가 준 좌표에 순번과 계산값을 얹는다.
  factory TrackPoint.from(
    GeoPoint point, {
    required int sequence,
    int? cadenceSpm,
    Duration? currentPace,
  }) => TrackPoint(
    sequence: sequence,
    latitude: point.latitude,
    longitude: point.longitude,
    accuracyMeters: point.accuracy,
    // ⚠️ 센서가 못 구하면 음수가 온다. 서버에 음수 속도를 보낼 이유가 없다.
    speedMetersPerSecond: point.speed < 0 ? 0 : point.speed,
    altitudeMeters: point.altitude,
    headingDegrees: point.heading,
    cadenceSpm: cadenceSpm,
    currentPaceSecondsPerKm: currentPace?.inSeconds,
    recordedAt: point.recordedAt,
  );

  /// 서버가 받는 모양 그대로.
  ///
  /// **`runningRoomId`는 여기 없다.** 방 번호는 `RUNNING_START`에서 한 번만
  /// 보내고, 서버가 WS 세션에서 알아낸다.
  Map<String, dynamic> toJson() => {
    'sequence': sequence,
    'latitude': latitude,
    'longitude': longitude,
    'altitudeMeters': altitudeMeters,
    'accuracyMeters': accuracyMeters,
    'speedMetersPerSecond': speedMetersPerSecond,
    // ⚠️ 명세가 `0~360`이고 nullable 표기가 없어 **모르면 `0`으로 보낸다.**
    // 0은 "정북"이라는 뜻이라 엄밀히는 거짓이다. 서버가 방향을 어디에 쓰는지
    // 확정되면 바뀔 수 있어 판단을 이 한 줄에 모아 둔다.
    'headingDegrees': headingDegrees ?? 0,
    'cadenceSpm': cadenceSpm,
    'currentPaceSecondsPerKm': currentPaceSecondsPerKm,
    'recordedAt': formatServerTime(recordedAt),
  };

  /// 서버가 받는 시각 형식 — `yyyy-MM-ddTHH:mm:ss`, **오프셋 없는 KST**.
  ///
  /// ## ⚠️ `toIso8601String()`을 쓸 수 없다
  ///
  /// 마이크로초가 붙고 UTC면 `Z`까지 붙어 형식이 다르다.
  ///
  /// ## ⚠️ `.toLocal()`을 반드시 거친다
  ///
  /// `Position.timestamp`가 **UTC로 온다.** 그대로 잘라 보내면 9시간 어긋난
  /// 기록이 쌓이는데, **에러가 나지 않아 한참 뒤에 발견된다.**
  static String formatServerTime(DateTime time) {
    final t = time.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}'
        'T${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}
