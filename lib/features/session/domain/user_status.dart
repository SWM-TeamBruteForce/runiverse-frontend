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
/// 지금 들어가 있는 방이 어떤 방인가. 서버 `type`이다.
///
/// ## ⚠️ 모르는 값은 `null`이다
///
/// [RoomStatus.of]와 같은 판단이다. 아무 값으로 뭉개면 안 된다 —
/// `match`로 접으면 초대 방에 매칭 방 화면이 뜨고, `solo`로 접으면 함께
/// 달릴 사람이 있는 방을 혼자 뛰는 방으로 그린다.
///
/// ## ⚠️ `INVITE`는 2026-10-29부터 실제로 내려온다
///
/// 1.1.0 명세에도 값은 있었지만 초대 방이 없어서 오지 않았다. 그래서 앱이
/// `SOLO`만 보고 둘로 갈랐고, **초대 방이 매칭 방으로 읽혔다.**
enum RoomType {
  match,
  invite,
  solo;

  static RoomType? of(Object? wire) => switch (wire) {
    'MATCH' => RoomType.match,
    'INVITE' => RoomType.invite,
    'SOLO' => RoomType.solo,
    _ => null,
  };

  /// 서버가 쓰는 이름. 로그에 적을 때 쓴다.
  String get wire => switch (this) {
    RoomType.match => 'MATCH',
    RoomType.invite => 'INVITE',
    RoomType.solo => 'SOLO',
  };
}

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

  /// 지금 **혼자 뛰기를 시작할 수 있는가.**
  ///
  /// 매칭이 걸려 있으면 `POST /running-rooms/solo`가 409
  /// `RUNNING_ALREADY_IN_PROGRESS`로 막힌다. 눌러 보고 알아내는 대신 **누르기
  /// 전에 알려 준다** — 막힌 이유도 상태마다 다르다.
  ///
  /// ⚠️ **쿨다운은 보지 않는다.** 이탈 제재는 매칭 신청만 막고 솔로는 열어
  /// 둔다([canApplyMatch]와 갈리는 자리다).
  ///
  /// ⚠️ **솔로 `READY`는 막지 않는다.** 내가 만들어 둔 방이라 새로 만드는 것이
  /// 아니라 그 방에 붙어 시작한다.
  bool get canStartSolo => switch (this) {
    UserStatusIdle() => true,
    UserStatusWaiting() => false,
    // ⚠️ **`!= match`가 아니다.** 초대 방도 함께 달릴 사람이 있는 방이라
    // 혼자 시작하면 안 된다. `solo`만 참이다.
    UserStatusReady(:final type) => type == RoomType.solo,
    UserStatusRunning() => false,
  };

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
/// 서버가 말하는 **지금 그 사람의 방 번호.** 진행 중인 것이 없으면 `null`.
///
/// ⚠️ 스트림이 남의 방이나 옛 방을 보내올 때 이것이 유일한 대조 근거다
/// (2026-09-18: 방 22에 배정된 직후 방 18 스냅샷이 왔다).
extension UserStatusRoom on UserStatus {
  int? get roomId => switch (this) {
    UserStatusIdle() => null,
    UserStatusWaiting(:final runningRoomId) => runningRoomId,
    UserStatusReady(:final runningRoomId) => runningRoomId,
    UserStatusRunning(:final runningRoomId) => runningRoomId,
  };
}

final class UserStatusIdle extends UserStatus {
  const UserStatusIdle({super.cooldownUntil});
}

/// 사람이 더 들어올 수 있는 방에서 모집 마감을 기다린다.
///
/// **솔로는 여기 오지 않는다** — 모집 단계 없이 [UserStatusReady]로 태어난다.
/// 그래서 [type]은 `match` 아니면 `invite`다.
///
/// ⚠️ **마감 경계가 방마다 다르다.** 매칭 방은 시작 10분 전, **초대 방은 1분
/// 전**까지 이 상태로 있다. 앱이 그 시각을 계산하지 않는다 — 서버가 상태를
/// 바꿔 준다.
final class UserStatusWaiting extends UserStatus {
  const UserStatusWaiting({
    required this.runningRoomId,
    required this.type,
    required this.scheduledStartAt,
    this.targetDistanceMeters,
    super.cooldownUntil,
  });

  final int runningRoomId;

  /// ⚠️ **2026-10-29에 생겼다.** 그전에는 `WAITING`이 매칭뿐이어서 가를 것이
  /// 없었다. 초대 방이 같은 상태를 쓰면서 필요해졌다.
  final RoomType type;

  final DateTime scheduledStartAt;

  /// 목표 없는 방이면 `null`이다.
  final int? targetDistanceMeters;
}

/// 시작 전이다. [type]에 따라 할 일이 다르다.
///
/// - 매칭·초대면 스트림에 붙어 카운트다운을 복구한다 (할 일이 같다)
/// - 솔로면 준비 화면으로 가고, **사용자가 시작 버튼을 누를 때** 시작한다
final class UserStatusReady extends UserStatus {
  const UserStatusReady({
    required this.runningRoomId,
    required this.type,
    required this.scheduledStartAt,
    this.targetDistanceMeters,
    super.cooldownUntil,
  });

  final int runningRoomId;
  final RoomType type;
  final DateTime scheduledStartAt;
  final int? targetDistanceMeters;

  /// 혼자 뛰는 방인가. **[type]에서 파생된다.**
  ///
  /// ⚠️ **셋 중 무엇인지를 묻는 자리에서는 [type]을 읽는다.** 이 값은
  /// "솔로인가" 하나만 묻는 자리의 지름길이고, 초대 방은 매칭 방과 함께
  /// `false`로 접힌다 — 두 방에서 할 일이 같은 자리에서만 맞는 말이다.
  bool get isSolo => type == RoomType.solo;
}

/// 달리는 중이다. WebSocket에 붙어 `RUNNING_START`를 보내 이어 달린다.
///
/// ## 복구의 출발점일 뿐이다
///
/// 방 번호와 [scheduledStartAt]으로 일단 이어 붙고, **정확한 값은
/// `RUNNING_STARTED` 스냅샷이 실어 온다** — 실제 시작 시각·내 누적 거리·
/// 파티원 명단. 받으면 세션이 그 값으로 바닥을 메운다
/// (`RunSessionController.seedDistance` · `seedStartedAt`).
final class UserStatusRunning extends UserStatus {
  const UserStatusRunning({
    required this.runningRoomId,
    required this.type,
    required this.scheduledStartAt,
    this.targetDistanceMeters,
    super.cooldownUntil,
  });

  final int runningRoomId;
  final RoomType type;

  /// 예약된 시작 시각. **복구가 경과 시간을 재기 시작하는 값이다.**
  ///
  /// ⚠️ **실제 시작 시각이 아니다.** 매칭 방은 이 시각에 서버가 시작하므로
  /// 대개 맞지만, 솔로 방은 만들어진 순간이 시작이라 갈린다. 스냅샷이 오면
  /// 그쪽으로 맞춘다.
  ///
  /// ⚠️ 일시정지 구간은 반영되지 않는다. 서버가 그것을 돌려주지 않는다.
  final DateTime scheduledStartAt;

  final int? targetDistanceMeters;

  /// 혼자 뛰는 방인가. **[type]에서 파생된다.**
  ///
  /// ⚠️ **셋 중 무엇인지를 묻는 자리에서는 [type]을 읽는다.** 이 값은
  /// "솔로인가" 하나만 묻는 자리의 지름길이고, 초대 방은 매칭 방과 함께
  /// `false`로 접힌다 — 두 방에서 할 일이 같은 자리에서만 맞는 말이다.
  bool get isSolo => type == RoomType.solo;
}
