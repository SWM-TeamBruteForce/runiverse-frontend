/// 러닝 방식. 서버가 `SOLO` 또는 `MATCH` 로 준다.
enum RunKind {
  /// 혼자 시작한 러닝.
  solo,

  /// 매칭으로 만들어진 방. **함께 달렸다는 뜻은 아니다** — [RunRecord.isAlone]
  /// 참고.
  match;

  /// 서버 값을 읽는다. **모르는 값이면 `null`이다.**
  ///
  /// ⚠️ 아무 값으로도 뭉개지 않는다. `solo`로 읽으면 함께 달린 기록이 혼자
  /// 달린 것으로 보이고, 그 반대도 마찬가지다. 모른다고 두는 편이 낫다.
  static RunKind? of(Object? wire) => switch (wire) {
    'SOLO' => RunKind.solo,
    'MATCH' => RunKind.match,
    _ => null,
  };
}

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
/// 적었는데, `GET /api/v1/users/me/running-records` 응답에 색 필드가 없다.
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
    required this.playerCount,
    this.kind,
    this.elevationGainMeters,
  });

  /// `runningRecordId`.
  ///
  /// ⚠️ **상세 조회에는 이것을 쓰지 않는다.** 기록 상세 API 는 삭제됐고,
  /// 상세는 [runningRoomId]로 러닝 결과·구간 결과를 부른다(가이드 5장).
  final int id;

  /// 이 기록이 나온 방. **상세는 기록이 아니라 이 번호로 조회한다.**
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
  /// 목록(19번)이 `totalElevationGainMeters`로 싣는다. 예전 주석은 "목록이 주지
  /// 않아 항상 `null`"이라 적어 두었는데, **2026-10-04에 실제로 값을 받았다.**
  ///
  /// GPS 고도로 직접 계산하지 않는다 — `GeoPoint.altitude`가 "경사를 내는 데
  /// 쓰지 않는다"고 못 박았다. 오차가 흔히 ±10~20m다.
  ///
  /// 서버 쪽도 **표본이 부족하면 `null`**이라, 값이 없을 수 있다.
  ///
  /// ## ⚠️ 서버가 고도 변화를 걸러낸다
  ///
  /// 같은 날 에뮬레이터로 두 번 쟀다.
  ///
  /// | 넣은 고도 | 넣은 누적 상승 | 서버가 답한 값 |
  /// |---|---|---|
  /// | ±7m 사인파(초당 0.17m) | 약 14m | **0m** |
  /// | 10초마다 5m 계단 | 35m | **20m** |
  ///
  /// 매끈한 변화는 통째로 0이 된다. **`0m`를 "평지"로 읽으면 안 된다** —
  /// "셀 만한 오르내림이 없었다"에 가깝다. 깎이는 비율이 얼마인지는 서버
  /// 구현을 봐야 알 수 있어 아직 모른다.
  final int? elevationGainMeters;

  /// 러닝 방식. **모르는 값이면 `null`이다.**
  final RunKind? kind;

  /// 이 러닝을 **시작한** 인원(본인 포함).
  ///
  /// ⚠️ 탈퇴한 사용자도 세고, **시작 전에 나간 사람은 안 센다.** 러닝 결과
  /// 화면의 참가자 수와 같은 값이다(📅 기록 탭 연동 가이드 3-3).
  final int playerCount;

  /// 화면이 쓰는 킬로미터.
  double get distanceKm => distanceMeters / 1000;

  /// 결국 혼자 달린 기록인가.
  ///
  /// ⚠️ **`kind`만으로는 모른다.** 매칭 방인데 상대가 안 나왔거나 시작 전에
  /// 빠지면 `MATCH` 인데 혼자 달린다 — 홈의 1인 러닝 카드와 같은 사건이다.
  ///
  /// ⚠️ **인원을 모르면(`0`) `null`이다.** 서버가 1 이상을 주므로 0은 우리가
  /// 못 읽었다는 뜻이고, 그때 "혼자"라고 단정하면 함께 달린 기록이 혼자로 보인다.
  bool? get isAlone => playerCount <= 0 ? null : playerCount == 1;

  /// 이 기록이 속한 **날짜**. 시각을 떼고 날짜만 남긴다.
  ///
  /// 캘린더와 주간 차트가 이 값으로 묶는다. `DateTime`을 그대로 Map 키로 쓰면
  /// 시·분·초가 달라 같은 날이 여러 칸으로 흩어진다.
  DateTime get day => DateTime(startedAt.year, startedAt.month, startedAt.day);

  @override
  String toString() =>
      'RunRecord($id, ${distanceKm.toStringAsFixed(2)}km, $startedAt)';
}
