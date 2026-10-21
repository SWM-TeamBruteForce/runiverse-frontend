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
    required this.pauseSegment,
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

  /// **몇 번째 멈춤 이후에 찍힌 좌표인가.** 0부터 센다 — 1.1.1 2절.
  ///
  /// ## ⚠️ 저장할 때 박고, 재전송할 때 바꾸지 않는다
  ///
  /// 서버는 **번호가 다른 연속 좌표 사이**를 멈춘 구간으로 보고 거리·시간·
  /// 고도에서 뺀다. 그래서 과거 좌표를 다시 보내면서 지금 번호로 갈아 끼우면
  /// **경계가 사라져 멈춘 사이 이동이 거리에 들어간다** — 고치려던 버그로
  /// 돌아간다.
  ///
  /// ## ⚠️ 빠지거나 줄어들면 배치 전체가 거부된다
  ///
  /// 없으면 `INVALID_REQUEST`, 순번 순으로 줄어들면 `PAUSE_SEGMENT_DECREASED`
  /// 다. **그 배치의 좌표가 하나도 저장되지 않는다**(1.1.1 3절). 그래서
  /// nullable이 아니고 기본값도 없다 — 빠뜨린 자리를 컴파일러가 잡아야 한다.
  final int pauseSegment;

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
  /// [headingDegrees]는 **직전 좌표로부터 계산한 진행 방향**이다.
  ///
  /// ⚠️ 센서가 주는 `point.heading`보다 이것을 먼저 쓴다. 안드로이드에서
  /// 측정해 보니 센서 값이 실제 방향과 무관했다(`GeoPoint.bearingTo` 참조).
  /// 계산할 수 없을 때만 — 첫 좌표이거나 거의 제자리일 때 — 센서 값으로
  /// 물러선다. iOS는 아직 재보지 않았다.
  factory TrackPoint.from(
    GeoPoint point, {
    required int sequence,
    required int pauseSegment,
    int? cadenceSpm,
    Duration? currentPace,
    double? headingDegrees,
  }) => TrackPoint(
    sequence: sequence,
    pauseSegment: pauseSegment,
    latitude: point.latitude,
    longitude: point.longitude,
    accuracyMeters: point.accuracy,
    // ⚠️ 센서가 못 구하면 음수가 온다. 서버에 음수 속도를 보낼 이유가 없다.
    speedMetersPerSecond: point.speed < 0 ? 0 : point.speed,
    altitudeMeters: point.altitude,
    headingDegrees: headingDegrees ?? point.heading,
    cadenceSpm: cadenceSpm,
    currentPaceSecondsPerKm: currentPace?.inSeconds,
    recordedAt: point.recordedAt,
  );

  /// 번호만 바꾼 사본.
  ///
  /// **아직 저장도 전송도 안 된 좌표에만 쓴다.** 앱이 러닝 도중에 죽었다
  /// 살아나면 방을 알기 전에 들어온 좌표가 1번부터 번호를 받는데, 그 번호는
  /// 재시작 전에 이미 쓴 것이다. 저장소에 쓰기 직전 뒤로 밀어야 한다.
  ///
  /// ## ⚠️ [pauseSegment]도 함께 받는다
  ///
  /// 방을 모르는 동안 쌓인 좌표는 구간 번호도 0부터 붙는다. 멈춘 채로 앱이
  /// 죽었다 살아난 경우 되살린 번호가 그보다 크므로, 0을 그대로 보내면
  /// **번호가 줄어들어 배치 전체가 `PAUSE_SEGMENT_DECREASED`로 거부된다.**
  ///
  /// 순번만 바꾸는 사본을 두지 않는 이유가 그것이다 — 한쪽만 밀면 조용히
  /// 거부된다.
  TrackPoint withNumbers({required int sequence, required int pauseSegment}) =>
      TrackPoint(
        sequence: sequence,
        pauseSegment: pauseSegment,
        latitude: latitude,
        longitude: longitude,
        accuracyMeters: accuracyMeters,
        speedMetersPerSecond: speedMetersPerSecond,
        recordedAt: recordedAt,
        altitudeMeters: altitudeMeters,
        headingDegrees: headingDegrees,
        cadenceSpm: cadenceSpm,
        currentPaceSecondsPerKm: currentPaceSecondsPerKm,
      );

  /// 서버가 받는 모양 그대로.
  ///
  /// **`runningRoomId`는 여기 없다.** 방 번호는 `RUNNING_START`에서 한 번만
  /// 보내고, 서버가 WS 세션에서 알아낸다.
  Map<String, dynamic> toJson() => {
    'sequence': sequence,
    // ⚠️ **빠지면 배치 전체가 거부된다**(`INVALID_REQUEST`). 필수 필드가
    // 5개에서 6개로 늘었다 — 1.1.1 2절.
    'pauseSegment': pauseSegment,
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
