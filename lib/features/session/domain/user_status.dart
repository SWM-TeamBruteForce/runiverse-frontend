/// 지금 무엇을 하는 중인가. `GET /api/v1/users/me/status`의 답이다(명세 13번).
///
/// ## 왜 필요한가
///
/// 앱에 들어오거나 포그라운드로 돌아왔을 때 **어느 화면으로 갈지, 어떤 채널에
/// 연결할지**를 이 값이 정한다. 예전에는 `GET /users/me/running-match`가
/// 비슷한 일을 했지만 매칭만 답해서 `STARTED`를 표현하지 못했고, 지금은
/// 그 경로가 아예 없어졌다.
///
/// ## ⚠️ 서버가 계산해서 주는 값이다
///
/// 저장된 상태 컬럼이 아니라 **활성 신청·방 상태·모집 마감 시각으로 파생된다.**
/// 앱이 같은 판정을 흉내 내려 하면 서버와 어긋난다 — 받은 대로 쓴다.
///
/// 특히 **마감이 지난 `MATCHING` 방을 서버가 [UserStatusReady]로 답한다.**
/// 방은 아직 `MATCHING`이지만 곧 확정될 자리라, 대기 화면을 그리면 잠시 뒤
/// 화면이 다시 바뀐다.
sealed class UserStatus {
  const UserStatus({this.cooldownUntil});

  /// 매칭 제한이 풀리는 시각. 없으면 제한이 없다.
  ///
  /// ⚠️ **[UserStatusIdle]에서만 오는 값이 아니다.** 다른 상태에도 값이 있을 수
  /// 있어 상태와 따로 본다. 제재 근거가 되는 이탈은 서버에 남아 있다.
  final DateTime? cooldownUntil;

  /// 지금 매칭을 신청할 수 있는가.
  ///
  /// **쉬는 중이면서 제한도 없어야** 한다. [now]를 받는 이유는 기기 시계를
  /// 고정해 시험하기 위해서다.
  bool canApplyMatch({required DateTime now}) =>
      this is UserStatusIdle && remainingCooldown(now: now) == Duration.zero;

  /// 제한이 풀릴 때까지 남은 시간. 없거나 이미 지났으면 [Duration.zero]다.
  ///
  /// ⚠️ **음수를 돌려주지 않는다.** 화면이 "-3분 후"를 그리게 두면 안 된다.
  Duration remainingCooldown({required DateTime now}) {
    final until = cooldownUntil;
    if (until == null) return Duration.zero;
    final remaining = until.difference(now);
    return remaining.isNegative ? Duration.zero : remaining;
  }
}

/// 진행 중인 매칭도 러닝도 없다. 홈에 머문다.
final class UserStatusIdle extends UserStatus {
  const UserStatusIdle({super.cooldownUntil});
}

/// 매칭을 신청하고 모집 마감을 기다린다. **매칭만 가능한 상태다** —
/// 솔로는 모집 단계 없이 [UserStatusReady]로 태어난다.
final class UserStatusWaiting extends UserStatus {
  const UserStatusWaiting({
    required this.runningRoomId,
    required this.scheduledStartAt,
    this.targetDistanceMeters,
    super.cooldownUntil,
  });

  final int runningRoomId;
  final DateTime scheduledStartAt;

  /// 목표 없는 방이면 `null`이다.
  final int? targetDistanceMeters;
}

/// 시작 전이다. [isSolo]에 따라 할 일이 다르다.
///
/// - 매칭이면 스트림에 붙어 카운트다운을 복구한다
/// - 솔로면 준비 화면으로 가고, **사용자가 시작 버튼을 누를 때** 시작한다
final class UserStatusReady extends UserStatus {
  const UserStatusReady({
    required this.runningRoomId,
    required this.isSolo,
    required this.scheduledStartAt,
    this.targetDistanceMeters,
    super.cooldownUntil,
  });

  final int runningRoomId;
  final bool isSolo;
  final DateTime scheduledStartAt;
  final int? targetDistanceMeters;
}

/// 달리는 중이다. WebSocket에 붙어 `RUNNING_START`를 보내 이어 달린다.
///
/// ## ⚠️ 서버가 복구용 스냅샷을 주지 않는다
///
/// `RUNNING_STARTED` ack의 `data`는 비어 있다(WS 명세, 백엔드 코드 확인).
/// 경과 시간과 거리는 **앱이 가진 것으로 되살려야 한다** — 로컬에 쌓인 좌표와
/// [scheduledStartAt]이 전부다. 스냅샷이 정의되면 그때 갈아끼운다.
final class UserStatusRunning extends UserStatus {
  const UserStatusRunning({
    required this.runningRoomId,
    required this.isSolo,
    required this.scheduledStartAt,
    this.targetDistanceMeters,
    super.cooldownUntil,
  });

  final int runningRoomId;
  final bool isSolo;

  /// 시작 시각. **복구할 때 경과 시간의 근거다.**
  ///
  /// ⚠️ 일시정지 구간은 반영되지 않는다. 서버가 그것을 돌려주지 않는다.
  final DateTime scheduledStartAt;

  final int? targetDistanceMeters;
}
