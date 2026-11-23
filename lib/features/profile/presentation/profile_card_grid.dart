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
/// ## ⚠️ 좌우 여백은 **두는 쪽**이 정한다
///
/// 안쪽에 품으면 이미 여백이 있는 화면(남의 프로필의 `SingleChildScrollView`)
/// 에서 **두 번 들어가** 같은 위젯이 내 프로필보다 좁고 더 들여써진다. 설계
/// 6-7이 "같은 위젯"이라고 적은 뜻이 그렇게 깨진다.
///
/// ## ⚠️ 일곱 장을 묻고 여섯 장을 깐다
///
/// 여섯 장만 물으면 **더 있는지 알 수 없어** `더 보기`를 늘 세우게 되고, 딱
/// 여섯 장인 사람이 눌렀을 때 아무것도 더 없는 화면으로 간다.
class ProfileCardGrid extends ConsumerWidget {
  const ProfileCardGrid({required this.userId, super.key});

  /// 누구의 프로필인가.
  final String userId;


  /// 깔 장수. 3열 2줄이다.
  static const previewCount = 6;

  static const _columns = 3;
  static const _rows = 2;
  static const _spacing = AppSpacing.space2;

  /// 두 줄이 차지하는 높이. 칸 하나의 폭에서 나온다.
  static double blockHeight(double width) {
    final tile = (width - _spacing * (_columns - 1)) / _columns;
    return tile * 16 / 9 * _rows + _spacing * (_rows - 1);
  }

  /// 받아 오는 동안 잡아 두는 높이.
  ///
  /// ## ⚠️ 두 줄을 미리 잡지 않는다
  ///
  /// 412dp 기기에서 두 줄은 **약 440dp — 화면의 절반**이다. 그만큼 비워 두면
  /// **카드가 한 장도 없는 사람**(새 계정이 처음 자기 프로필을 볼 때, 그리고
  /// 그리드가 침묵해야 하는 남의 빈 프로필)에게 큰 빈 칸이 떴다가 통째로
  /// 사라지면서 아래가 440dp 솟는다.
  ///
  /// 그래서 **한 줄짜리 자리만** 잡는다. 카드가 있는 사람은 받아 온 뒤 아래가
  /// 내려가고(내용이 도착하는 모습이다), 없는 사람은 작은 자리만 걷힌다.
  static const loadingHeight = 48.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(
      profileCardsProvider((userId: userId, limit: previewCount + 1)),
    );

    return switch (cards) {
      AsyncLoading() => const SizedBox(
        height: loadingHeight,
        child: Center(child: CircularProgressIndicator()),
      ),
      AsyncError() => _Error(userId: userId),
      AsyncValue(:final value?) when value.isEmpty => const SizedBox.shrink(),
      AsyncValue(:final value?) => _Preview(
        cards: value.take(previewCount).toList(),
        // 일곱 번째가 왔다 = 더 있다.
        hasMore: value.length > previewCount,
        userId: userId,
      ),
    };
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.cards,
    required this.hasMore,
    required this.userId,
  });

  final List<RecordCard> cards;
  final bool hasMore;
  final String userId;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      GridView.builder(
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
            AppRoutes.recordCardDetailOf(cards[index].id),
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
              context.push(AppRoutes.recordCardsOf(userId)),
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

    return Column(
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
    );
  }
}
