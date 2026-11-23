import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/core/widgets/v2/app_icon.dart';
import 'package:runiverse/features/profile/presentation/profile_card_tile.dart';
import 'package:runiverse/features/profile/presentation/profile_cards_provider.dart';

/// 그 사람의 기록카드 **전체 보기** — 프로필 그리드의 `더 보기`가 오는 곳
/// (설계 6-7).
///
/// ## ⚠️ 그리드와 다른 점은 둘이다
///
/// ① **커서로 이어 받는다**(그리드는 첫 여섯 장만) ② **빈 경우에 한 줄을
/// 둔다.** 그리드는 카드가 없으면 아무 말도 하지 않지만(남의 프로필에 "아직
/// 없어요"를 띄울 이유가 없다), 눌러서 들어온 화면이 텅 비면 고장으로 읽힌다.
///
/// ## ⚠️ 그리드의 커서를 물려받지 않는다
///
/// 첫 요청은 **커서 없이** 보낸다(연동 가이드 5절 2번). 그리드가 떠 있었는지에
/// 따라 첫 요청이 달라지면 같은 화면이 두 가지로 돈다.
///
/// ## ⚠️ 탭 셸 밖이다
///
/// 남의 프로필에서 들어와도 기록카드 탭으로 바뀌면 안 된다(설계 7절).
class ProfileCardsPage extends ConsumerWidget {
  const ProfileCardsPage({required this.userId, super.key});

  final String userId;

  /// 3열. 설계 6-7의 그리드와 같은 칸이다.
  static const _columns = 3;

  /// 바닥에서 이만큼 남았을 때 다음 페이지를 부른다.
  ///
  /// ⚠️ **0으로 두지 않는다.** 바닥에 완전히 닿은 뒤 받으면 빈 화면을 보며
  /// 기다린다. 한 화면쯤 미리 받는다.
  static const prefetchExtent = 600.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColorsV2;
    final state = ref.watch(profileCardsPageProvider(userId));

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        leading: IconButton(
          icon: const AppIcon(AppIcons.left),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: AppStrings.authBack,
        ),
        title: Text(
          AppStrings.profileCardsTitle,
          style: AppTypographyV2.body04.copyWith(color: colors.textPrimary),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: switch (state) {
          ProfileCardsLoading() => const Center(
            child: CircularProgressIndicator(),
          ),
          ProfileCardsError() => _Error(userId: userId),
          ProfileCardsData(:final items) when items.isEmpty => Center(
            child: Text(
              AppStrings.profileCardsEmpty,
              style: AppTypographyV2.body18.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          final ProfileCardsData data => _Grid(userId: userId, data: data),
        },
      ),
    );
  }
}

class _Grid extends ConsumerWidget {
  const _Grid({required this.userId, required this.data});

  final String userId;
  final ProfileCardsData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      NotificationListener<ScrollNotification>(
        // ⚠️ **스크롤로 이어 받는다.** 바닥에 `더 보기` 버튼을 또 두면,
        // 그리드에서 누르고 들어온 사람이 같은 버튼을 한 번 더 누른다.
        //
        // ⚠️ **매 프레임 불린다.** 막는 일은 컨트롤러가 한다
        // (`ProfileCardsController._loadingMore`).
        onNotification: (notification) {
          if (notification is! ScrollUpdateNotification) return false;
          if (notification.metrics.extentAfter <
              ProfileCardsPage.prefetchExtent) {
            ref.read(profileCardsPageProvider(userId).notifier).loadMore();
          }
          return false;
        },
        child: GridView.builder(
          padding: const EdgeInsets.all(AppSpacing.space4),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: ProfileCardsPage._columns,
            // 9:16. 카드 사진이 잘린 비율과 같다.
            childAspectRatio: 9 / 16,
            crossAxisSpacing: AppSpacing.space2,
            mainAxisSpacing: AppSpacing.space2,
          ),
          // 마지막 칸은 더 받는 중 표시다.
          itemCount: data.items.length + (data.loadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= data.items.length) {
              return const Center(child: CircularProgressIndicator());
            }
            final item = data.items[index];
            return ProfileCardTile(
              card: item,
              onTap: () => context.push(AppRoutes.recordCardDetailOf(item.id)),
            );
          },
        ),
      );
}

class _Error extends ConsumerWidget {
  const _Error({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColorsV2;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            AppStrings.profileCardsError,
            style: AppTypographyV2.body18.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.space2),
          AppButtonV2(
            label: AppStrings.recordRetry,
            variant: AppButtonV2Variant.secondary,
            expand: false,
            onPressed: () =>
                ref.read(profileCardsPageProvider(userId).notifier).load(),
          ),
        ],
      ),
    );
  }
}
