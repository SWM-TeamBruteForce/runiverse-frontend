import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/features/record_card/domain/record_card_summary.dart';
import 'package:runiverse/features/record_card/presentation/activity_label.dart';

/// 하루에 카드가 둘 이상일 때 고르는 시트.
///
/// ## ⚠️ 없으면 두 번째 카드가 갇힌다
///
/// 달력 칸은 하나인데 러닝 기록 1건당 카드가 1개라, 하루에 두 번 뛰면 카드도
/// 둘이다. 칸을 눌러 최신 것만 열면 나머지는 **어디로도 갈 수 없다.**
class DayCardsSheet extends StatelessWidget {
  const DayCardsSheet({
    required this.day,
    required this.cards,
    required this.onOpen,
    super.key,
  });

  final DateTime day;
  final List<RecordCardSummary> cards;
  final ValueChanged<RecordCardSummary> onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.space4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space4,
              ),
              child: Text(
                AppStrings.recordCardDaySheetTitle(day),
                style: AppTypographyV2.body12.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.space3),
            for (final card in cards)
              _Row(
                card: card,
                onTap: () {
                  // 시트를 먼저 닫는다 — 열린 채로 상세를 밀어 올리면
                  // 돌아올 때 시트가 그대로 남아 있다.
                  Navigator.of(context).pop();
                  onOpen(card);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.card, required this.onTap});

  final RecordCardSummary card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space4,
          vertical: AppSpacing.space3,
        ),
        child: Row(
          children: [
            Text(
              AppStrings.recordCardStartedAt(card.startedAt),
              style: AppTypographyV2.body12.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(width: AppSpacing.space3),
            Text(
              AppStrings.kmFloor(card.distanceMeters),
              style: AppTypographyV2.body18.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const Spacer(),
            // ⚠️ **유형을 못 읽은 카드는 자리를 비운다.** 일상으로 적으면
            // 대회에서 뛴 카드가 일상으로 보이고, `유형 없음` 같은 말을 넣으면
            // 사용자가 고르지 않은 상태를 새로 만든다 — 작성에는 유형이
            // 필수라 그런 카드는 **우리가 못 읽은 것**이다.
            if (card.activity case final activity?)
              Text(
                recordCardActivityLabel(activity),
                style: AppTypographyV2.body18.copyWith(
                  color: colors.textTertiary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// [DayCardsSheet]를 띄운다.
Future<void> showDayCardsSheet(
  BuildContext context, {
  required DateTime day,
  required List<RecordCardSummary> cards,
  required ValueChanged<RecordCardSummary> onOpen,
}) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: context.appColorsV2.bgElevated,
  builder: (_) => DayCardsSheet(day: day, cards: cards, onOpen: onOpen),
);
