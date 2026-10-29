import 'package:runiverse/features/friend/domain/friend_relation.dart';

/// 알림이 무엇을 알리는가.
///
/// ⚠️ **모르는 값은 `null`이다.** 알 수 없는 알림은 목록에 넣지 않는다 —
/// 문구를 앱이 만들기 때문에(서버가 내려주지 않는다) 종류를 모르면 그릴 글이
/// 없다. 아무 종류로 뭉개면 엉뚱한 문장과 엉뚱한 버튼이 선다.
enum NotificationType {
  /// 누가 나에게 친구 요청을 보냈다.
  friendRequested,

  /// 내가 보낸 친구 요청을 상대가 수락했다.
  friendAccepted,

  /// 누가 나를 초대 방에 초대했다.
  runningInvited;

  static NotificationType? of(Object? wire) => switch (wire) {
    'FRIEND_REQUESTED' => NotificationType.friendRequested,
    'FRIEND_ACCEPTED' => NotificationType.friendAccepted,
    'RUNNING_INVITED' => NotificationType.runningInvited,
    _ => null,
  };
}

/// 받은 초대가 지금 어떤 상태인가.
///
/// ## ⚠️ 알림이 만들어진 때가 아니라 **지금** 상태다
///
/// 알림은 사건의 기록이고 이 값은 조회 시점의 상태다. 그래서 같은 알림을
/// 다시 받으면 버튼이 달라져 있을 수 있다 — 재초대되면 [declined]·[left]였던
/// 초대가 [pending]으로 **돌아온다.**
enum InvitationStatus {
  /// 답을 기다린다. **수락·거절 버튼은 이때만 그린다.**
  pending,

  /// 수락했다. 누르면 초대 방으로 간다.
  accepted,

  declined,

  /// 수락했다가 방을 나갔다.
  left,

  /// 모집이 마감됐거나 방이 사라졌다.
  expired;

  static InvitationStatus? of(Object? wire) => switch (wire) {
    'PENDING' => InvitationStatus.pending,
    'ACCEPTED' => InvitationStatus.accepted,
    'DECLINED' => InvitationStatus.declined,
    'LEFT' => InvitationStatus.left,
    'EXPIRED' => InvitationStatus.expired,
    _ => null,
  };

  /// 버튼을 그릴 상태인가.
  bool get isPending => this == InvitationStatus.pending;
}

/// 알림을 일으킨 사람.
class NotificationActor {
  const NotificationActor({
    required this.userId,
    required this.nickname,
    required this.isDeleted,
    this.profileImageUrl,
    this.relation,
  });

  final String userId;

  /// 탈퇴했으면 서버가 `"탈퇴한 사용자"`로 준다.
  final String nickname;

  final bool isDeleted;
  final String? profileImageUrl;

  /// **지금** 나와 이 사람의 관계.
  ///
  /// ⚠️ **탈퇴했으면 `null`이고, 그때 친구 관련 버튼을 전부 숨긴다.** `none`
  /// 으로 읽으면 없는 사람에게 "친구 요청" 버튼이 뜬다.
  ///
  /// ⚠️ 모르는 값도 `null`이다 — 서버가 관계를 늘려도 버튼을 임의로 세우지
  /// 않는다.
  final FriendRelation? relation;
}

/// 알림에 실려 온 초대의 지금 상태.
///
/// **`RUNNING_INVITED`에만 있다.** 친구 알림 둘은 `null`로 온다.
class NotificationInvitation {
  const NotificationInvitation({
    required this.runningRoomId,
    required this.status,
    required this.scheduledStartAt,
    required this.targetDistanceMeters,
  });

  /// 수락·거절 API 경로에 쓴다.
  ///
  /// ⚠️ **같은 방의 알림을 함께 갱신하는 기준이기도 하다.** A와 C가 각각 나를
  /// 같은 방에 초대하면 알림은 둘이고 `actor`도 다르지만 **초대는 하나다.**
  /// 하나를 수락하면 다른 줄의 버튼도 같이 사라져야 한다.
  final int runningRoomId;

  final InvitationStatus status;
  final DateTime scheduledStartAt;
  final int targetDistanceMeters;

  NotificationInvitation withStatus(InvitationStatus next) =>
      NotificationInvitation(
        runningRoomId: runningRoomId,
        status: next,
        scheduledStartAt: scheduledStartAt,
        targetDistanceMeters: targetDistanceMeters,
      );
}

/// 알림 한 건.
///
/// ## ⚠️ 이벤트와 목록 항목이 같은 모양이다
///
/// 앱 스트림 이벤트의 `data`는 이 구조에서 [type]만 뺀 것이고, 종류는 이벤트
/// 이름이 말한다. 덕분에 **목록 응답을 기다리는 동안 받은 이벤트를
/// [notificationId]로 대조**할 수 있다 — 그 대조가 배지를 목록과 맞추는 유일한
/// 수단이다.
class AppNotification {
  const AppNotification({
    required this.notificationId,
    required this.type,
    required this.isRead,
    required this.createdAt,
    required this.actor,
    this.invitation,
  });

  /// ⚠️ **`Long`이다. 숫자로 비교한다.** 문자열로 다루면 `"913"`과 `913`이
  /// 다른 알림이 되어 중복 제거가 깨지고 배지가 목록과 어긋난다.
  final int notificationId;

  final NotificationType type;

  /// 읽었는가. **화면의 새 알림 강조가 이 값으로 그려진다.**
  ///
  /// ⚠️ 배지와 따로 움직인다 — 모두 읽음을 부른 뒤에도 이 값은 그대로 남고,
  /// 배지만 0이 된다(의도된 동작이다).
  final bool isRead;

  final DateTime createdAt;
  final NotificationActor actor;

  /// [NotificationType.runningInvited]에만 있다.
  final NotificationInvitation? invitation;

  /// **할 일이 끝난 알림인가.** 끝난 것은 목록에서 빠진다.
  ///
  /// ## ⚠️ 서버는 지우지 않는다
  ///
  /// 항목별 삭제 API가 없고 서버는 30일을 보관한다(연동 가이드 2-3). 그래서
  /// 이 판정은 **화면에서만** 쓰고, 안 읽은 수(배지)는 서버 값을 그대로
  /// 따른다 — 숨긴 줄이 배지에 남는 일은 없다(끝난 것은 이미 읽힌 것뿐이다).
  ///
  /// ## 무엇이 끝난 것인가
  ///
  /// | | 끝났다고 보는 때 |
  /// |---|---|
  /// | 러닝 초대 | `PENDING`이 아니다 — 수락·거절·이탈·만료 |
  /// | 친구 요청 | 받은 요청이 아니다 — 이미 수락·거절했거나 상대가 탈퇴 |
  /// | 친구 수락 | **읽었다** — 결과 통보라 한 번은 보여야 한다 |
  ///
  /// ⚠️ **친구 수락만 `isRead`를 본다.** 나머지 둘은 버튼이 사라진 순간
  /// 쌓이기만 하는 줄이 되지만, 친구 수락은 그 자체가 전하려는 내용이다 —
  /// 열기도 전에 숨기면 "친구가 됐다"를 영영 못 본다.
  bool get isSettled => switch (type) {
    NotificationType.runningInvited => invitation?.status.isPending != true,
    NotificationType.friendRequested =>
      actor.relation != FriendRelation.requestReceived,
    NotificationType.friendAccepted => isRead,
  };

  AppNotification withInvitation(NotificationInvitation next) =>
      AppNotification(
        notificationId: notificationId,
        type: type,
        isRead: isRead,
        createdAt: createdAt,
        actor: actor,
        invitation: next,
      );
}
