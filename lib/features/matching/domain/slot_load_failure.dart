/// 슬롯 목록 조회(명세 No 16)가 실패하는 이유.
///
/// ## ⚠️ `MatchFailure`와 합치지 않는다
///
/// 저쪽은 **신청·취소**의 갈래다. `slotClosed` · `cooldown` · `alreadyInProgress` ·
/// `nothingToCancel` — 조회에는 하나도 해당되지 않는다. 더 큰 이유는 담기는
/// 자리다: 신청 실패는 `state.failure`에 들어가고 화면이 스낵바를 띄운 뒤
/// **곧바로 지운다.** 조회 실패는 반대로 **그 자리에 머물러야** 한다 —
/// 시간 선택기를 잠그고 다시 시도할 길을 주는 것이 그 역할이다.
enum SlotLoadFailure {
  /// 서버에 닿지 못했다. 타임아웃과 5xx도 여기로 묶는다 — 사용자가 할 일이
  /// 같다(다시 눌러본다).
  network,

  /// 토큰이 죽었고 갱신도 실패했다(401).
  sessionExpired,

  /// ⚠️ 서버가 값을 거절했다(400).
  ///
  /// 앱은 거리 셋만 보내고 날짜는 안 보내므로 **정상 경로에서는 나오지
  /// 않는다.** 나오면 앱 규칙이 서버와 어긋났다는 신호라 로그로 남긴다.
  /// 화면에는 [network]와 같게 보인다 — 사용자가 할 수 있는 일이 같다.
  invalidRequest,

  /// 그 밖. 404도 여기다 — 신청용 매핑처럼 "취소할 신청이 없다"로 읽으면
  /// 목록을 못 받은 사람에게 엉뚱한 말이 뜬다.
  unknown,
}

/// 조회가 실패했다.
class SlotLoadException implements Exception {
  const SlotLoadException(this.failure);

  final SlotLoadFailure failure;

  @override
  String toString() => 'SlotLoadException($failure)';
}
