import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/runner_avatar.dart';
import 'package:runiverse/features/friend/domain/friend_relation.dart';
import 'package:runiverse/features/friend/presentation/friend_provider.dart';
import 'package:runiverse/features/profile/domain/profile_summary.dart';
import 'package:runiverse/features/profile/presentation/profile_provider.dart';
import 'package:runiverse/features/profile/presentation/profile_stat_row.dart';

/// 남의 프로필 — 내 프로필과 **같은 틀**이다.
///
/// 다른 것은 둘뿐이다.
///
/// | | 내 프로필 | 여기 |
/// |---|---|---|
/// | 우상단 | 프로필 편집 | **관계별 버튼** |
/// | 좌상단 | 종 · 설정 | 뒤로 |
///
/// ## ⚠️ 이 화면이 `profile` 에 있는 이유
///
/// 설계는 처음에 `friend`에 두려 했다. 그런데 프로필 탭이 받은 요청 수를
/// 세려고 `friendProvider`를 읽으면서 **`profile → friend` 의존이 이미
/// 생겼다.** 여기서 반대 방향을 만들면 Riverpod이 `CircularDependencyError`로
/// 막는다. 게다가 `ProfileSummary`가 처음부터 "본인과 타인이 같은 것을 쓴다,
/// 누구를 보는지는 `userId`가 정한다"로 적혀 있다.
class UserProfilePage extends ConsumerStatefulWidget {
  const UserProfilePage({required this.userId, super.key});

  final String userId;

  @override
  ConsumerState<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends ConsumerState<UserProfilePage> {
  /// 이 화면에서 바꾼 관계.
  ///
  /// ⚠️ **서버 응답을 화면이 들고 있어야 한다.** [userProfileProvider]는 한 번
  /// 받고 끝이라, 버튼을 눌러도 요약은 그대로다. 그러면 사용자는 실패한 줄
  /// 알고 또 누르고, 두 번째 호출은 `409`나 `404`로 돌아온다.
  FriendRelation? _changed;

  /// 서버에 다녀오는 중. 연타를 막는다.
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Scaffold(
      backgroundColor: colors.bgBase,
      body: SafeArea(
        child: ref
            .watch(userProfileProvider(widget.userId))
            .when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: Text(
                  AppStrings.friendProfileLoadFailed,
                  style: AppTypographyV2.body05.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ),
              data: (summary) => _body(
                context,
                // 바꾼 적이 있으면 그 값이 최신이다.
                _changed == null ? summary : summary.withRelation(_changed),
              ),
            ),
      ),
    );
  }

  /// 버튼 하나를 누른다. 돌아온 관계로 화면을 다시 그린다.
  Future<void> _act(Future<void> Function() call, FriendRelation after) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await call();
      if (!mounted) return;
      // 실패했으면 관계를 그대로 둔다 — 틀린 버튼을 그리느니 안 바꾼다.
      final failed = ref.read(friendProvider).actionFailure != null;
      setState(() {
        _busy = false;
        if (!failed) _changed = after;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Widget _body(BuildContext context, ProfileSummary summary) {
    final colors = context.appColorsV2;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(LucideIcons.chevronLeft),
                color: colors.textPrimary,
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const Spacer(),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              RunnerAvatarV2(
                nickname: summary.nickname ?? '',
                imageUrl: summary.profileImageUrl,
                size: 86,
              ),
              const Spacer(),
              _RelationAction(summary: summary, busy: _busy, onAct: _act),
            ],
          ),
          const SizedBox(height: AppSpacing.space4),
          Text(
            summary.nickname ?? '',
            style: AppTypographyV2.heading03.copyWith(
              color: colors.textPrimary,
            ),
          ),
          if (summary.introduction case final intro?) ...[
            const SizedBox(height: AppSpacing.space1),
            Text(
              intro,
              style: AppTypographyV2.body07.copyWith(
                color: colors.textTertiary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.space4),
          ProfileStatRow(
            friendCount: summary.friendCount,
            // 남의 화면에는 내가 답할 요청이 없다.
            receivedCount: 0,
            onTap: () => context.push(
              '${AppRoutes.userFriendsOf(summary.userId)}'
              '?nickname=${Uri.encodeComponent(summary.nickname ?? '')}',
            ),
          ),
        ],
      ),
    );
  }
}

/// 우상단 버튼. **관계가 정한다.**
class _RelationAction extends ConsumerWidget {
  const _RelationAction({
    required this.summary,
    required this.busy,
    required this.onAct,
  });

  final ProfileSummary summary;
  final bool busy;
  final Future<void> Function(Future<void> Function(), FriendRelation) onAct;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColorsV2;
    final notifier = ref.read(friendProvider.notifier);

    Widget pill(String label, VoidCallback? onTap, {bool filled = false}) =>
        OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            shape: const RoundedRectangleBorder(borderRadius: AppRadius.md),
            side: BorderSide(
              color: filled ? colors.primary : colors.borderStrong,
              width: 0.6,
            ),
          ),
          child: Text(
            label,
            style: AppTypographyV2.body05.copyWith(
              color: filled ? colors.primary : colors.textSecondary,
            ),
          ),
        );

    // ⚠️ 내 프로필이거나 관계를 못 읽었으면 아무것도 그리지 않는다.
    if (summary.isMe) return const SizedBox.shrink();

    return switch (summary.relation) {
      FriendRelation.none => pill(
        AppStrings.friendRequest,
        busy
            ? null
            : () => onAct(
                () => notifier.request(summary.userId),
                FriendRelation.requestSent,
              ),
        filled: true,
      ),
      FriendRelation.requestSent => pill(
        AppStrings.friendCancel,
        busy
            ? null
            : () => onAct(
                () => notifier.cancel(summary.userId),
                FriendRelation.none,
              ),
      ),
      FriendRelation.requestReceived => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          pill(
            AppStrings.friendAccept,
            busy
                ? null
                : () => onAct(
                    () => notifier.accept(summary.userId),
                    FriendRelation.friend,
                  ),
            filled: true,
          ),
          const SizedBox(width: AppSpacing.space2),
          pill(
            AppStrings.friendReject,
            busy
                ? null
                : () => onAct(
                    () => notifier.cancel(summary.userId),
                    FriendRelation.none,
                  ),
          ),
        ],
      ),
      FriendRelation.friend => pill(AppStrings.friendSectionFriends, null),
      null => const SizedBox.shrink(),
    };
  }
}
