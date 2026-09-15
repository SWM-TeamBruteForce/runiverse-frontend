/// 매칭 신청·취소가 실패하는 이유.
///
/// **서버가 주는 코드를 그대로 옮기지 않고 앱이 대응할 수 있는 갈래로 줄인다.**
/// 화면이 해야 할 일이 같으면 같은 값으로 묶는다.
enum MatchFailure {
  /// 모집이 마감된 시간대다(`MATCH_SLOT_CLOSED`).
  ///
  /// 슬롯 목록의 `selectable`로 1차로 막으므로, **모달을 열어둔 사이 마감이
  /// 지나가는 경합에서만** 나온다. 받으면 목록을 다시 받는다.
  slotClosed,

  /// 이탈 제재로 신청이 막혔다(`MATCH_COOLDOWN`).
  ///
  /// 해제 시각은 [MatchException.cooldownUntil]에 담긴다.
  cooldown,

  /// 이미 활성 신청이나 확정된 방이 있다(`MATCH_ALREADY_IN_PROGRESS`).
  ///
  /// ⚠️ **러닝 중에도 여기 걸린다.** 서버의 활성 판정이 방 종류를 보지 않는다.
  alreadyInProgress,

  /// 매칭 조건에 쓸 평균 페이스가 없다(`ONBOARDING_NOT_COMPLETED`).
  onboardingNotCompleted,

  /// 취소할 활성 신청이 없다(404).
  ///
  /// 다른 기기에서 이미 취소했거나 서버가 방을 닫은 뒤다. 실패로 알리기보다
  /// **이미 원하던 상태**라고 보는 편이 맞는 경우가 많다.
  nothingToCancel,

  /// ⚠️ 서버가 값을 거절했다(400).
  ///
  /// 앱은 고정 선택지만 보내므로 정상 경로에서는 나오지 않는다. 나오면
  /// **앱의 선택지가 서버 규칙과 어긋났다는 신호**다.
  invalidRequest,

  /// 요청이 서버에 닿지 못했다.
  ///
  /// ⚠️ **신청됐는지 알 수 없는 상태다.** 다시 보내면 중복 신청이 된다.
  network,

  /// 다시 로그인해야 한다.
  sessionExpired,

  unknown,
}

/// 매칭 요청이 실패했다.
class MatchException implements Exception {
  const MatchException(this.failure, {this.cooldownUntil});

  final MatchFailure failure;

  /// [MatchFailure.cooldown]일 때만 담긴다. 서버가 이 오류에만 실어 준다.
  ///
  /// 값이 없을 수도 있다 — 그때는 시각 없이 제한 사실만 알린다.
  final DateTime? cooldownUntil;

  @override
  String toString() => 'MatchException($failure, until: $cooldownUntil)';
}
