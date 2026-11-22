import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/features/profile/presentation/profile_card_tile.dart';
import 'package:runiverse/features/profile/presentation/profile_cards_provider.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';

/// 프로필의 기록카드 그리드 — **3열 · 9:16 · 최신순 · 처음 6장**(설계 6-7).
///
/// 내 프로필(S22)과 남의 프로필(S20)이 **같은 위젯**을 쓴다. 두 화면이 이미
/// 같은 틀을 재사용한다.
///
/// ## ⚠️ 공개한 카드만 선다
///
/// `PUBLIC`과 `FRIENDS`다. **내 프로필에서도 비공개는 안 보인다**(사용자
/// 결정) — 나만 보는 카드를 보는 자리는 기록카드 탭이다. 거르는 것은
/// **서버**다(`RecordCardRepository.byUser`).
///
/// ## ⚠️ 카드가 없으면 아무것도 그리지 않는다
///
/// 남의 프로필에 "아직 없어요"를 띄울 이유가 없다(설계 6-7). 눌러서 들어온
/// 전체 보기 화면만 그 말을 한다([ProfileCardsPage]).
///
/// ## ⚠️ 일곱 장을 묻고 여섯 장을 깐다
///
/// 여섯 장만 물으면 **더 있는지 알 수 없어** `더 보기`를 늘 세우게 되고, 딱
/// 여섯 장인 사람이 눌렀을 때 아무것도 더 없는 화면으로 간다.
class ProfileCardGrid extends ConsumerWidget {
  const ProfileCardGrid({required this.userId, required this.mine, super.key});

  /// 누구의 프로필인가.
  final String userId;

  /// 내 카드들인가. **상세로 그대로 넘긴다** — 남의 카드에서는 상세가 `⋮`를
  /// 세우지 않는다(`AppRoutes.recordCardDetailOf`).
  final bool mine;

  /// 깔 장수. 3열 2줄이다.
  static const previewCount = 6;

  static const _columns = 3;
  static const _rows = 2;
  static const _spacing = AppSpacing.space2;

  /// 두 줄이 차지하는 높이.
  ///
  /// ⚠️ **받아 오는 동안에도 이 높이를 지킨다.** 로딩이 높이 0이면 프로필
  /// 아래가 튀어올랐다가 카드가 오는 순간 다시 내려앉는다.
  static double blockHeight(double width) {
    final tile = (width - _spacing * (_columns - 1)) / _columns;
    return tile * 16 / 9 * _rows + _spacing * (_rows - 1);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(
      profileCardsProvider((userId: userId, limit: previewCount + 1)),
    );

    return switch (cards) {
      AsyncLoading() => const _Reserved(child: CircularProgressIndicator()),
      AsyncError() => _Error(userId: userId),
      AsyncValue(:final value?) when value.isEmpty => const SizedBox.shrink(),
      AsyncValue(:final value?) => _Preview(
        cards: value.take(previewCount).toList(),
        // 일곱 번째가 왔다 = 더 있다.
        hasMore: value.length > previewCount,
        userId: userId,
        mine: mine,
      ),
    };
  }
}

/// 두 줄 자리를 잡아 둔 칸. 가운데에 [child]를 둔다.
class _Reserved extends StatelessWidget {
  const _Reserved({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
    child: LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        height: ProfileCardGrid.blockHeight(constraints.maxWidth),
        child: Center(child: child),
      ),
    ),
  );
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.cards,
    required this.hasMore,
    required this.userId,
    required this.mine,
  });

  final List<RecordCard> cards;
  final bool hasMore;
  final String userId;
  final bool mine;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
        child: GridView.builder(
          padding: EdgeInsets.zero,
          // 프로필이 이미 스크롤한다. 여기서 또 스크롤하면 손가락을 빼앗는다.
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: ProfileCardGrid._columns,
            childAspectRatio: 9 / 16,
            crossAxisSpacing: ProfileCardGrid._spacing,
            mainAxisSpacing: ProfileCardGrid._spacing,
          ),
          itemCount: cards.length,
          itemBuilder: (context, index) => ProfileCardTile(
            card: cards[index],
            onTap: () => context.push(
              AppRoutes.recordCardDetailOf(cards[index].id, mine: mine),
              extra: cards[index],
            ),
          ),
        ),
      ),
      if (hasMore) ...[
        const SizedBox(height: AppSpacing.space2),
        AppButtonV2(
          label: AppStrings.profileCardsMore,
          variant: AppButtonV2Variant.secondary,
          expand: false,
          onPressed: () =>
              context.push(AppRoutes.recordCardsOf(userId, mine: mine)),
        ),
      ],
    ],
  );
}

class _Error extends ConsumerWidget {
  const _Error({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColorsV2;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
      child: Column(
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
              profileCardsProvider((
                userId: userId,
                limit: ProfileCardGrid.previewCount + 1,
              )),
            ),
          ),
        ],
      ),
    );
  }
}
