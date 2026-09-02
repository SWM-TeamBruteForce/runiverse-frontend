/// 끝난 러닝 하나. 기록 탭(S21)의 캘린더·주간 차트·목록이 전부 이것을 센다.
///
/// ## 서버가 정본이다
///
/// 러닝 중 화면은 앱이 계산한 값을 쓰지만, **끝난 뒤의 기록은 서버가 확정한
/// 값만 쓴다.** 서버는 목표 거리를 넘긴 구간을 잘라내는 등 앱이 모르는 규칙으로
/// 기록을 만든다(`RUNNING_FINISH` 명세). 앱이 다시 계산하면 두 숫자가 갈린다.
///
/// ## ⚠️ 색이 없다
///
/// 정본 S21은 주간 막대와 캘린더 점을 **그날 획득한 러닝 컬러**로 칠하라고
/// 적었는데, `GET /users/me/running-records`(19번) 응답에 색 필드가 없다.
/// 지표에서 색을 만드는 규칙도 아직 없다(`features/color/`가 비어 있다).
/// 그래서 화면은 당분간 단색으로 그린다 — 규칙이 정해지면 여기에 필드가 는다.
class RunRecord {
  const RunRecord({
    required this.id,
    required this.runningRoomId,
    required this.startedAt,
    required this.distanceMeters,
    required this.duration,
    required this.averagePace,
    required this.routePolyline,
    this.elevationGainMeters,
  });

  /// `runningRecordId`. 상세 조회(20번)의 키다.
  final int id;

  /// 이 기록이 나온 방. 구간별 상세(18번)는 **기록이 아니라 방**으로 조회한다.
  final int runningRoomId;

  /// 시작 시각.
  ///
  /// ⚠️ **서버는 오프셋 없는 KST로 준다**(`2026-07-25T19:00:30`). 그대로
  /// `DateTime.parse`하면 로컬 시각으로 읽히는데, 기기가 KST면 그게 맞다.
  /// 날짜별로 묶는 화면이라 여기서 시간대가 틀어지면 **기록이 다른 날에 붙는다.**
  final DateTime startedAt;

  /// 총 이동 거리(m). 서버가 확정한 값이다.
  final int distanceMeters;

  /// 총 러닝 시간. 일시정지는 서버가 이미 빼고 준다.
  final Duration duration;

  /// 1km당 평균 페이스.
  final Duration averagePace;

  /// 카드의 경로 미리보기용 Google Encoded Polyline.
  ///
  /// 목록에서는 지도를 띄우지 않고 이 문자열만 들고 있는다 — 카드마다 지도를
  /// 올리면 목록 스크롤이 버틴다.
  final String routePolyline;

  /// 누적 상승 고도(m). 주간 요약이 이걸 더한다.
  ///
  /// ## ⚠️ 목록(19번)이 주지 않아 지금은 항상 `null`이다
  ///
  /// 서버는 이 값을 갖고 있다 — 기록 상세(20번)의 `totalElevationGainMeters`다.
  /// 그런데 목록 응답에는 없고, 주간 요약은 목록으로 그린다. 기록마다 상세를
  /// 부르면 주 7회면 요청이 7개가 되므로 그렇게 하지 않는다.
  /// **19번에 이 필드를 실어 달라고 요청해 두었다.**
  ///
  /// GPS 고도로 직접 계산하지 않는다 — `GeoPoint.altitude`가 "경사를 내는 데
  /// 쓰지 않는다"고 못 박았다. 오차가 흔히 ±10~20m다.
  ///
  /// 서버 쪽도 **표본이 부족하면 `null`**이라, 필드가 와도 값이 없을 수 있다.
  final int? elevationGainMeters;

  /// 화면이 쓰는 킬로미터.
  double get distanceKm => distanceMeters / 1000;

  /// 이 기록이 속한 **날짜**. 시각을 떼고 날짜만 남긴다.
  ///
  /// 캘린더와 주간 차트가 이 값으로 묶는다. `DateTime`을 그대로 Map 키로 쓰면
  /// 시·분·초가 달라 같은 날이 여러 칸으로 흩어진다.
  DateTime get day => DateTime(startedAt.year, startedAt.month, startedAt.day);

  @override
  String toString() =>
      'RunRecord($id, ${distanceKm.toStringAsFixed(2)}km, $startedAt)';
}
