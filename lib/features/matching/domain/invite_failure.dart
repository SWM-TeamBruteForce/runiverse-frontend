/// 초대 방 개설·초대·수락·거절이 실패하는 이유.
///
/// ## ⚠️ `MatchFailure`를 쓰지 않는다
///
/// 저쪽은 서버 코드를 **앱이 대응할 갈래로 줄이고** 문구를 버린다. 초대는
/// 반대다 — 명세가 `message`를 그대로 보여 주라고 하고, 실패 사유가 상대의
/// 상태(매칭 중·러닝 중·이미 참여 중)라서 앱이 바꿔 쓸 말이 없다.
///
/// 또 404의 뜻이 다르다. `MatchFailure.nothingToCancel`을 그대로 쓰면 초대
/// 실패에 "취소할 활성 신청이 없어요"가 뜬다.
enum InviteFailure {
  /// 모집이 마감됐다(`RUNNING_INVITATION_CLOSED`). 시작 1분 전이다.
  closed,

  /// 친구가 아니다(`NOT_FRIEND`). **자신을 초대해도 이것이다.**
  notFriend,

  /// 상대가 이미 이 방에 있다(`INVITEE_ALREADY_IN_ROOM`).
  alreadyInRoom,

  /// 상대가 매칭 중이다(`INVITEE_IN_MATCHING`).
  inMatching,

  /// 상대가 달리는 중이다(`INVITEE_RUNNING`).
  running,

  /// 내가 이 친구에게 보낼 수 있는 횟수를 넘겼다(`INVITE_COUNT_EXCEEDED`).
  ///
  /// ⚠️ **미리 막을 수 없다.** 남은 횟수를 서버가 내려주지 않고, 보낸 사람별로
  /// 세니 앱이 셀 수도 없다 — 눌러 보고 여기서 안다(설계 §8-3).
  countExceeded,

  /// 답할 수 있는 상태의 초대가 아니다(`RUNNING_INVITATION_NOT_PENDING`).
  ///
  /// 다른 기기에서 이미 수락·거절했거나 만료됐다. **버튼을 지우고 목록을 다시
  /// 읽는다.**
  notPending,

  /// 방이 꽉 찼다(`RUNNING_ROOM_FULL`).
  ///
  /// ⚠️ **초대는 `PENDING`으로 남는다.** 자리가 생기면 다시 누를 수 있어서,
  /// 이 하나만 버튼을 지우지 않는다.
  roomFull,

  /// 시작 시각이 범위를 벗어났다(`INVITE_START_AT_OUT_OF_RANGE`).
  ///
  /// 기기 시계가 느려서 화면에서 합법이던 값이 거절되는 경우가 여기 온다.
  startAtOutOfRange,

  /// 이미 활성 신청이나 방이 있다(`RUNNING_ALREADY_IN_PROGRESS`).
  alreadyInProgress,

  /// 페이스를 만들 온보딩이 안 끝났다(`ONBOARDING_NOT_COMPLETED`).
  onboardingNotCompleted,

  /// 서버가 값을 거절했다(400 `INVALID_REQUEST`).
  ///
  /// 시각 형식·거리 범위가 어긋났다. 네 종류가 있고, 둘을 함께 위반하면
  /// 서버가 두 문장을 공백으로 이어 보낸다.
  invalidRequest,

  /// 방이 없거나, 초대 방이 아니거나, 내가 참가자가 아니다(404).
  ///
  /// ⚠️ **서버가 셋을 구분하지 않는다.** 한 문장으로 말한다.
  notFound,

  network,
  sessionExpired,
  unknown,
}

/// 초대 요청이 실패했다.
class InviteException implements Exception {
  const InviteException(this.failure, {this.message});

  final InviteFailure failure;

  /// 서버가 준 문구. **그대로 보여 준다.**
  ///
  /// 명세가 그러라고 한다 — 실패 사유가 상대의 상태라서 앱이 더 잘 쓸 말이
  /// 없고, 사유가 늘어날 때 앱을 고치지 않아도 된다.
  ///
  /// ⚠️ 없을 수 있다. 그때는 화면이 [failure]별 기본 문구를 쓴다.
  final String? message;

  @override
  String toString() => 'InviteException($failure, message: $message)';
}
