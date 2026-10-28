import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
class UserProfilePage extends ConsumerWidget {
  const UserProfilePage({required this.userId, super.key});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColorsV2;

    return Scaffold(
      backgroundColor: colors.bgBase,
      body: SafeArea(
        child: ref
            .watch(userProfileProvider(userId))
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
              data: (summary) => _body(context, summary),
            ),
      ),
    );
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
              _RelationAction(summary: summary),
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
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

/// 우상단 버튼. **관계가 정한다.**
class _RelationAction extends ConsumerWidget {
  const _RelationAction({required this.summary});

  final ProfileSummary summary;

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
        () => notifier.request(summary.userId),
        filled: true,
      ),
      FriendRelation.requestSent => pill(
        AppStrings.friendCancel,
        () => notifier.cancel(summary.userId),
      ),
      FriendRelation.requestReceived => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          pill(
            AppStrings.friendAccept,
            () => notifier.accept(summary.userId),
            filled: true,
          ),
          const SizedBox(width: AppSpacing.space2),
          pill(AppStrings.friendReject, () => notifier.cancel(summary.userId)),
        ],
      ),
      FriendRelation.friend => pill(AppStrings.friendSectionFriends, null),
      null => const SizedBox.shrink(),
    };
  }
}
