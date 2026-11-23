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
import 'package:runiverse/features/record_card/domain/record_card.dart';

/// 그 사람의 기록카드 **전체 보기** — 프로필 그리드의 `더 보기`가 오는 곳
/// (설계 6-7).
///
/// ## ⚠️ 그리드와 다른 점은 둘이다
///
/// ① **전부 받는다**(`limit`을 주지 않는다) ② **빈 경우에 한 줄을 둔다.**
/// 그리드는 카드가 없으면 아무 말도 하지 않지만(남의 프로필에 "아직 없어요"를
/// 띄울 이유가 없다), 눌러서 들어온 화면이 텅 비면 고장으로 읽힌다.
///
/// ## ⚠️ 탭 셸 밖이다
///
/// 남의 프로필에서 들어와도 기록카드 탭으로 바뀌면 안 된다(설계 7절).
class ProfileCardsPage extends ConsumerWidget {
  const ProfileCardsPage({required this.userId, super.key});

  final String userId;


  /// 3열. 설계 6-7의 그리드와 같은 칸이다.
  static const _columns = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColorsV2;
    // ⚠️ **`limit`을 주지 않는다** — 여기가 "전체"다. 그리드는 7장만 묻는다.
    final cards = ref.watch(
      profileCardsProvider((userId: userId, limit: null)),
    );

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
        child: switch (cards) {
          AsyncLoading() => const Center(child: CircularProgressIndicator()),
          AsyncError() => _Error(userId: userId),
          AsyncValue(:final value?) when value.isEmpty => Center(
            child: Text(
              AppStrings.profileCardsEmpty,
              style: AppTypographyV2.body18.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          AsyncValue(:final value?) => _Grid(cards: value),
        },
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.cards});

  final List<RecordCard> cards;

  @override
  Widget build(BuildContext context) => GridView.builder(
    padding: const EdgeInsets.all(AppSpacing.space4),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: ProfileCardsPage._columns,
      // 9:16. 카드 사진이 잘린 비율과 같다.
      childAspectRatio: 9 / 16,
      crossAxisSpacing: AppSpacing.space2,
      mainAxisSpacing: AppSpacing.space2,
    ),
    itemCount: cards.length,
    itemBuilder: (context, index) => ProfileCardTile(
      card: cards[index],
      onTap: () =>
          context.push(AppRoutes.recordCardDetailOf(cards[index].id)),
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
            onPressed: () => ref.invalidate(
              profileCardsProvider((userId: userId, limit: null)),
            ),
          ),
        ],
      ),
    );
  }
}
