import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_sizes.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/features/matching/domain/match_slot.dart';

/// 시간대를 고르는 바텀시트. 고르면 그 슬롯을, 닫으면 `null`을 돌려준다.
Future<MatchSlot?> showMatchSlotSheet(
  BuildContext context, {
  required List<MatchSlot> slots,
  MatchSlot? selected,
}) {
  return showModalBottomSheet<MatchSlot>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: context.appColors.bgScrim,
    isScrollControlled: true,
    builder: (context) => _SlotSheet(slots: slots, selected: selected),
  );
}

class _SlotSheet extends StatelessWidget {
  const _SlotSheet({required this.slots, this.selected});

  final List<MatchSlot> slots;
  final MatchSlot? selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: colors.bgElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.space5,
          AppSpacing.space3,
          AppSpacing.space5,
          AppSpacing.space5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.borderStrong,
                  borderRadius: AppRadius.full,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.space4),

            Text(
              AppStrings.matchSlotSheetTitle,
              style: AppTypography.h3.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.space3),

            if (slots.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.space6,
                ),
                child: Text(
                  AppStrings.matchSlotEmpty,
                  textAlign: TextAlign.center,
                  style: AppTypography.body.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              )
            else
              // 아홉 칸이 화면 높이를 넘긴다. 시트가 화면을 다 먹지 않도록
              // 위쪽을 남기고 안에서 굴린다.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: slots.length,
                  itemBuilder: (context, index) => _SlotRow(
                    slot: slots[index],
                    isSelected: slots[index].raw == selected?.raw,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 시간대 한 줄.
///
/// **마감된 줄도 남긴다.** 목록에서 빼면 "18:00이 왜 없지"가 되고, 시간이
/// 흐르며 목록이 줄어드는 것도 이상하게 읽힌다. 남기되 눌리지 않게 한다.
class _SlotRow extends StatelessWidget {
  const _SlotRow({required this.slot, required this.isSelected});

  final MatchSlot slot;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final closed = !slot.selectable;

    return Semantics(
      selected: isSelected,
      enabled: !closed,
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: closed ? null : () => Navigator.of(context).pop(slot),
          borderRadius: AppRadius.sm,
          child: Container(
            constraints: const BoxConstraints(minHeight: AppSizes.touchDefault),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3),
            child: Row(
              children: [
                Text(
                  AppStrings.matchSlotTime(slot.startAt),
                  style: AppTypography.bodyLg.copyWith(
                    color: closed ? colors.textTertiary : colors.textPrimary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    // 시각이 세로로 나열된다. 자릿수가 흔들리면 줄이 어긋난다.
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: AppSpacing.space3),

                if (closed)
                  Text(
                    AppStrings.matchSlotClosed,
                    style: AppTypography.caption.copyWith(
                      color: colors.textTertiary,
                    ),
                  )
                else if ((slot.waitingCount ?? 0) > 0)
                  // 대기 인원은 강조색이다 — 사회적 증거로 슬롯을 유도한다.
                  // 모르면(`null`) 아무것도 적지 않는다 — 0으로 그리면 사람이
                  // 없다고 잘못 알린다.
                  Text(
                    AppStrings.matchWaitingCount(slot.waitingCount!),
                    style: AppTypography.caption.copyWith(
                      color: colors.matchWaiting,
                    ),
                  ),

                const Spacer(),

                if (isSelected)
                  Icon(
                    LucideIcons.check,
                    size: AppSpacing.space5,
                    color: colors.primary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
