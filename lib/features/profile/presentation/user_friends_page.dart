import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/empty_state.dart';
import 'package:runiverse/features/friend/presentation/friend_provider.dart';
import 'package:runiverse/features/friend/presentation/friend_row.dart';
import 'package:runiverse/features/profile/presentation/profile_provider.dart';

/// 남의 친구 목록.
///
/// ## ⚠️ 내 목록과 세 가지가 다르다
///
/// - **친구만 담긴다.** 누구에게 요청했고 누가 요청했는지는 본인만 안다. 가를
///   것이 없으니 **묶음 머리글도 탭도 없다.**
/// - **`relationshipType`은 나와 그 사람의 관계다.** 목록 주인과의 관계가
///   아니다 — 모르는 사람이면 `NONE`이라 "친구 요청" 버튼이 선다.
/// - **내가 그 목록에 있을 수 있다.** 그 줄의 관계는 `null`이고,
///   [FriendRow]가 버튼을 그리지 않는다.
class UserFriendsPage extends ConsumerWidget {
  const UserFriendsPage({
    required this.userId,
    required this.nickname,
    super.key,
  });

  final String userId;

  /// 제목에 쓴다. 목록을 받기 전에도 누구의 목록인지 보여야 한다.
  final String nickname;

  /// 좌우 여백. 친구 화면과 같은 시안값이다.
  static const _gutter = 14.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColorsV2;

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          AppStrings.userFriendsTitle(nickname),
          style: AppTypographyV2.body05.copyWith(color: colors.textPrimary),
        ),
      ),
      // ⚠️ **바닥을 비킨다.** 목록 맨 아래 줄이 제스처 바에 덮인다.
      body: SafeArea(
        child: ref
            .watch(userFriendsProvider(userId))
            .when(
              loading: () => const Center(child: CircularProgressIndicator()),
              // ⚠️ **"없다"고 하지 않는다.** 못 받은 것과 아무도 없는 것은
              // 다른 일이다.
              error: (_, _) => EmptyStateV2(
                icon: LucideIcons.cloudOff,
                message: AppStrings.friendLoadFailed,
                cta: TextButton(
                  onPressed: () => ref.invalidate(userFriendsProvider(userId)),
                  child: Text(AppStrings.friendRetry),
                ),
              ),
              data: (page) => page.items.isEmpty
                  ? EmptyStateV2(
                      icon: LucideIcons.users,
                      message: AppStrings.userFriendsEmpty(nickname),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: _gutter),
                      children: [
                        for (final entry in page.items)
                          FriendRow(
                            key: ValueKey(entry.userId),
                            entry: entry,
                            onTap: () => context.push(
                              AppRoutes.userProfileOf(entry.userId),
                            ),
                            onRequest: () => ref
                                .read(friendProvider.notifier)
                                .request(entry.userId),
                          ),
                        const SizedBox(height: AppSpacing.space6),
                      ],
                    ),
            ),
      ),
    );
  }
}
