import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/runner_avatar.dart';
import 'package:runiverse/features/friend/domain/friend_relation.dart';
import 'package:runiverse/features/notification/domain/app_notification.dart';

/// 알림 한 줄 — 사진 · 문구 · (초대면) 시각·거리 · 버튼.
///
/// ## ⚠️ 버튼은 **지금** 상태로 그린다
///
/// 알림은 사건의 기록이고, `relationshipType`과 `invitation.status`는 조회
/// 시점의 값이다. 알림이 만들어진 때를 기준으로 그리면 **이미 수락한 요청에
/// 수락 버튼이** 서고, 눌러 봐야 409만 돌아온다.
///
/// 탈퇴한 사람의 관계는 `null`이고, 그때 **친구 버튼을 전부 숨긴다.**
class NotificationRow extends StatelessWidget {
  const NotificationRow({
    required this.notification,
    this.onTap,
    this.onAcceptFriend,
    this.onDeclineFriend,
    this.onAcceptInvite,
    this.onDeclineInvite,
    this.busy = false,
    super.key,
  });

  final AppNotification notification;

  /// 줄을 눌렀을 때. 랜딩 규칙은 와이어프레임 C7을 따른다.
  final VoidCallback? onTap;

  final VoidCallback? onAcceptFriend;
  final VoidCallback? onDeclineFriend;
  final VoidCallback? onAcceptInvite;
  final VoidCallback? onDeclineInvite;

  /// 서버에 다녀오는 중. 버튼을 잠근다.
  final bool busy;

  static const _avatar = 44.0;

  /// 안 읽은 표시. **숫자가 아니라 점이다.**
  static const _dot = 6.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final actor = notification.actor;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space4,
          vertical: AppSpacing.space3,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 안 읽은 줄에만 점이 선다. 읽은 줄에도 같은 폭을 비워 두어야
            // 아바타가 좌우로 흔들리지 않는다.
            SizedBox(
              width: _dot + AppSpacing.space2,
              child: notification.isRead
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(
                        top: _avatar / 2 - _dot / 2,
                      ),
                      child: Container(
                        width: _dot,
                        height: _dot,
                        decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: BorderRadius.circular(_dot / 2),
                        ),
                      ),
                    ),
            ),
            RunnerAvatarV2(
              nickname: actor.nickname,
              imageUrl: actor.profileImageUrl,
              size: _avatar,
            ),
            const SizedBox(width: AppSpacing.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _message(actor.nickname),
                    style: AppTypographyV2.body12.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  ?_detail(colors),
                  ?_buttons(colors),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// `type`이 문구를 정한다. 서버는 문구를 내려주지 않는다.
  String _message(String nickname) => switch (notification.type) {
    NotificationType.friendRequested => AppStrings.notificationFriendRequested(
      nickname,
    ),
    NotificationType.friendAccepted => AppStrings.notificationFriendAccepted(
      nickname,
    ),
    NotificationType.runningInvited => AppStrings.notificationRunningInvited(
      nickname,
    ),
  };

  /// 초대의 시각·거리, 또는 버튼이 없는 상태의 안내.
  Widget? _detail(AppColorsV2 colors) {
    final invitation = notification.invitation;
    if (invitation == null) return null;

    final text = switch (invitation.status) {
      InvitationStatus.pending ||
      InvitationStatus.accepted => AppStrings.notificationInviteDetail(
        AppStrings.matchSlotTime(invitation.scheduledStartAt),
        AppStrings.distanceKm(invitation.targetDistanceMeters),
      ),
      InvitationStatus.declined => AppStrings.notificationInviteDeclined,
      InvitationStatus.left => AppStrings.notificationInviteLeft,
      InvitationStatus.expired => AppStrings.notificationInviteExpired,
    };

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.space1),
      child: Text(
        text,
        style: AppTypographyV2.body18.copyWith(color: colors.textSecondary),
      ),
    );
  }

  /// 버튼 줄. **그릴 것이 없으면 `null`이다** — 빈 자리를 남기지 않는다.
  Widget? _buttons(AppColorsV2 colors) {
    final invitation = notification.invitation;

    // 러닝 초대 — `PENDING`일 때만 그린다.
    if (invitation != null) {
      if (!invitation.status.isPending) return null;
      return _ButtonRow(
        onAccept: busy ? null : onAcceptInvite,
        onDecline: busy ? null : onDeclineInvite,
        colors: colors,
      );
    }

    // 친구 요청 — **받은 요청이 아직 처리되지 않았을 때만** 그린다.
    // 탈퇴한 사람은 관계가 `null`이라 여기서 함께 걸러진다.
    if (notification.actor.relation != FriendRelation.requestReceived) {
      return null;
    }
    return _ButtonRow(
      onAccept: busy ? null : onAcceptFriend,
      onDecline: busy ? null : onDeclineFriend,
      colors: colors,
    );
  }
}

class _ButtonRow extends StatelessWidget {
  const _ButtonRow({
    required this.onAccept,
    required this.onDecline,
    required this.colors,
  });

  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final AppColorsV2 colors;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.space2),
    child: Row(
      children: [
        // 거절이 앞에 선다 — 되돌리기 어려운 쪽을 먼저 두면 손이 스친다.
        _Button(
          label: AppStrings.notificationDecline,
          onPressed: onDecline,
          background: Colors.transparent,
          border: colors.borderStrong,
          foreground: colors.textSecondary,
        ),
        const SizedBox(width: AppSpacing.space2),
        _Button(
          label: AppStrings.notificationAccept,
          onPressed: onAccept,
          background: colors.primary,
          border: colors.primary,
          foreground: colors.bgBase,
        ),
      ],
    ),
  );
}

class _Button extends StatelessWidget {
  const _Button({
    required this.label,
    required this.onPressed,
    required this.background,
    required this.border,
    required this.foreground,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color background;
  final Color border;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Material(
    color: onPressed == null ? Colors.transparent : background,
    borderRadius: AppRadius.sm,
    child: InkWell(
      onTap: onPressed,
      borderRadius: AppRadius.sm,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space4,
          vertical: AppSpacing.space2,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: border, width: 0.6),
          borderRadius: AppRadius.sm,
        ),
        child: Text(
          label,
          style: AppTypographyV2.body21.copyWith(color: foreground),
        ),
      ),
    ),
  );
}
