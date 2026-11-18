/// `run_finish` 의 `run_outcome`. **목표 거리를 채웠는가**다.
///
/// ## ⚠️ 서버 `status: COMPLETED` 로는 못 가린다
///
/// 결과 API(17번)의 `players[].status` 는 `RUNNING`·`COMPLETED` 둘뿐이고,
/// **중도 이탈도 종료 뒤에는 `COMPLETED`** 다(3차 명세). `early` 도 같다 —
/// 본인이 일찍 끝내기로 했는지일 뿐 거리를 채웠는지가 아니다. 그래서 17번의
/// 내 거리와 방의 목표 거리를 직접 비교한다.
enum RunOutcome {
  /// 목표 거리 이상을 달렸다.
  completed,

  /// 목표 거리에 못 미쳤다.
  incomplete,

  /// 가릴 수 없다. 목표가 없는 방이거나, 거리를 못 읽었다.
  ///
  /// ⚠️ **모르면 여기로 보낸다.** `incomplete` 로 접으면 결과 API가 한 번
  /// 실패한 것이 완주율을 깎는다.
  unknown;

  /// [targetMeters] 는 방의 목표 거리, [distanceMeters] 는 17번의 내
  /// `totalDistanceMeters` 다.
  static RunOutcome judge({
    required int? targetMeters,
    required int? distanceMeters,
  }) {
    if (targetMeters == null || targetMeters <= 0) return unknown;
    if (distanceMeters == null) return unknown;
    return distanceMeters >= targetMeters ? completed : incomplete;
  }
}
