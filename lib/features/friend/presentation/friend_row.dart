import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/runner_avatar.dart';
import 'package:runiverse/features/friend/domain/friend_entry.dart';
import 'package:runiverse/features/friend/domain/friend_relation.dart';

/// 목록의 한 줄 — 사진 · 닉네임 · 한 줄 설명 · 버튼.
///
/// 치수는 시안 `79:2081`이다. 행 62 · 아바타 48 · 버튼 97×40 · 테두리 0.6.
///
/// ## ⚠️ 버튼은 관계가 정한다
///
/// 같은 줄이라도 관계마다 할 수 있는 일이 다르고, 서버는 엉뚱한 호출에
/// `404`·`409`로만 답한다. 여기가 틀리면 눌러도 아무 일이 안 일어난다.
///
/// 친구를 끊는 것만 `⋯` 뒤에 숨긴다 — **되돌릴 수 없는 동작이 목록에 그대로
/// 노출되면 손이 스친다.**
class FriendRow extends StatelessWidget {
  const FriendRow({
    required this.entry,
    this.meta,
    this.onTap,
    this.onRequest,
    this.onAccept,
    this.onReject,
    this.onCancel,
    this.onRemove,
    this.busy = false,
    super.key,
  });

  final FriendEntry entry;

  /// 사진 아래 한 줄. 추천이면 이유가 들어오고, 그 밖에는 비어 있다.
  final Widget? meta;

  final VoidCallback? onTap;
  final VoidCallback? onRequest;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onCancel;
  final VoidCallback? onRemove;

  /// 서버에 다녀오는 중. 버튼을 잠근다.
  final bool busy;

  static const _height = 62.0;
  static const _avatar = 48.0;
  static const _buttonWidth = 97.0;
  static const _halfWidth = 66.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: _height,
        child: Row(
          children: [
            RunnerAvatarV2(
              nickname: entry.nickname,
              imageUrl: entry.profileImageUrl,
              size: _avatar,
            ),
            const SizedBox(width: AppSpacing.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    entry.nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypographyV2.body05.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  ?meta,
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.space2),
            ..._actions(context),
          ],
        ),
      ),
    );
  }

  /// ⚠️ **관계를 모르면(`null`) 아무 버튼도 그리지 않는다.** 그 줄은 나
  /// 자신이다 — 타인의 친구 목록에는 내가 들어 있을 수 있다.
  List<Widget> _actions(BuildContext context) => switch (entry.relation) {
    FriendRelation.requestReceived => [
      _Pill(
        label: AppStrings.friendAccept,
        width: _halfWidth,
        onTap: busy ? null : onAccept,
        filled: true,
      ),
      const SizedBox(width: AppSpacing.space1),
      _Pill(
        label: AppStrings.friendReject,
        width: _halfWidth,
        onTap: busy ? null : onReject,
      ),
    ],
    FriendRelation.requestSent => [
      _Pill(
        label: AppStrings.friendCancel,
        width: _buttonWidth,
        onTap: busy ? null : onCancel,
      ),
    ],
    FriendRelation.friend => [
      // ⚠️ **두 번 눌러야 끊긴다.** 여기서 메뉴를 열고, 고르면 화면이 한 번
      // 더 묻는다([onRemove]가 확인 다이얼로그를 띄운다).
      PopupMenuButton<_RowMenu>(
        icon: Icon(
          LucideIcons.ellipsis,
          color: context.appColorsV2.textTertiary,
        ),
        tooltip: AppStrings.friendRemove,
        enabled: !busy,
        // ⚠️ **값을 `null`로 두면 안 된다.** Flutter는 `null` 선택을 취소로
        // 읽어 `onSelected`를 아예 부르지 않는다.
        onSelected: (_) => onRemove?.call(),
        itemBuilder: (context) => [
          PopupMenuItem<_RowMenu>(
            value: _RowMenu.remove,
            child: Text(
              AppStrings.friendRemove,
              style: AppTypographyV2.body05.copyWith(
                color: context.appColorsV2.error,
              ),
            ),
          ),
        ],
      ),
    ],
    FriendRelation.none => [
      _Pill(
        label: AppStrings.friendRequest,
        width: _buttonWidth,
        onTap: busy ? null : onRequest,
        filled: true,
      ),
    ],
    null => const [],
  };
}

/// `⋯` 뒤에 숨는 것들. 지금은 하나뿐이다.
enum _RowMenu { remove }

/// 시안의 외곽선 알약. 누를 수 없으면 흐려진다.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.width,
    this.onTap,
    this.filled = false,
  });

  final String label;
  final double width;
  final VoidCallback? onTap;

  /// 그 줄에서 **권하는 쪽**. 테두리와 글자가 강조색이다.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final enabled = onTap != null;
    final accent = filled ? colors.primary : colors.borderStrong;

    return SizedBox(
      width: width,
      height: 40,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.md),
          side: BorderSide(
            color: enabled ? accent : colors.borderDefault,
            width: 0.6,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: AppTypographyV2.body05.copyWith(
            color: enabled
                ? (filled ? colors.primary : colors.textSecondary)
                : colors.textDisabled,
          ),
        ),
      ),
    );
  }
}
