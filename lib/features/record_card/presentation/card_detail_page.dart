import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_icon.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/presentation/activity_label.dart';
import 'package:runiverse/features/record_card/presentation/card_media_pager.dart';

/// 기록카드 한 장 — **읽기만 한다.**
///
/// ## ⚠️ 없는 버튼을 그려 두지 않는다
///
/// 수정·삭제(`⋮`)와 음악 줄은 다음 PR이다. 자리를 비워 두되 **눌러도 아무 데도
/// 가지 않는 버튼을 두지 않는다** — 고장으로 읽힌다(`run_summary_page.dart`가
/// 같은 이유를 적어 두었다).
///
/// ## ⚠️ 탭 셸 밖이다
///
/// 프로필 그리드나 러닝 요약에서 열어도 탭이 바뀌면 안 된다
/// (`app_routes.dart`의 `recordCardDetail`).
class CardDetailPage extends StatelessWidget {
  const CardDetailPage({required this.card, super.key});

  final RecordCard card;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

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
          '${AppStrings.recordMonthLabel(card.day)} ${card.day.day}일 · '
          '${AppStrings.recordCardStartedAt(card.startedAt)}',
          style: AppTypographyV2.body12.copyWith(color: colors.textPrimary),
        ),
        centerTitle: true,
      ),
      body: ListView(
        // ⚠️ **바닥을 시스템에 비킨다.** 제스처 바가 맨 아래를 덮는다. 여기는
        // `SafeArea`로 감싸지 않고 여백에 직접 더한다 — 페이저가 화면 폭을
        // 꽉 써야 해서 좌우까지 깎이면 안 된다(`test/bottom_inset_test.dart`).
        padding: EdgeInsets.only(
          bottom: AppSpacing.space8 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          CardMediaPager(card: card),
          const SizedBox(height: AppSpacing.space5),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ActivityChip(card: card),
                const SizedBox(height: AppSpacing.space4),
                _Stats(card: card),
                if (card.runners.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.space4),
                  Text(
                    AppStrings.recordCardRunnerCount(card.runners.length),
                    style: AppTypographyV2.body18.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.space5),
                Text(
                  AppStrings.recordCardReview,
                  style: AppTypographyV2.body12.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.space2),
                Text(
                  card.reviewText,
                  style: AppTypographyV2.body12.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityChip extends StatelessWidget {
  const _ActivityChip({required this.card});

  final RecordCard card;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space3,
          vertical: AppSpacing.space1,
        ),
        decoration: BoxDecoration(
          color: colors.bgSurface,
          borderRadius: AppRadius.full,
        ),
        child: Text(
          recordCardActivityLabel(card.activity),
          style: AppTypographyV2.body18.copyWith(color: colors.textSecondary),
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.card});

  final RecordCard card;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _Stat(
          label: AppStrings.recordCardDistance,
          value: AppStrings.kmFloor(card.distanceMeters),
        ),
      ),
      Expanded(
        child: _Stat(
          label: AppStrings.recordCardPace,
          value: AppStrings.recordRunDuration(card.averagePace),
        ),
      ),
      Expanded(
        child: _Stat(
          label: AppStrings.recordCardDuration,
          value: AppStrings.recordRunDuration(card.duration),
        ),
      ),
    ],
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypographyV2.body18.copyWith(color: colors.textTertiary),
        ),
        const SizedBox(height: AppSpacing.space1),
        Text(
          value,
          style: AppTypographyV2.body12.copyWith(color: colors.textPrimary),
        ),
      ],
    );
  }
}
