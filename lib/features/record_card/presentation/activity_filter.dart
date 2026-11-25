import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/presentation/activity_label.dart';

/// 러닝 유형으로 거르는 칩 줄.
///
/// ## ⚠️ 하나만 고른다
///
/// 여럿을 켜고 끄게 두면 "왜 이 날이 안 보이지"를 부른다. 고른 것을 다시
/// 누르면 [selected]가 `null`이 되어 전체로 돌아온다.
class ActivityFilter extends StatelessWidget {
  const ActivityFilter({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  /// `null`이면 전체다.
  final RecordCardActivity? selected;

  final ValueChanged<RecordCardActivity?> onChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
    child: Row(
      children: [
        _Chip(
          label: AppStrings.recordCardFilterAll,
          on: selected == null,
          onTap: () => onChanged(null),
        ),
        for (final activity in RecordCardActivity.values) ...[
          const SizedBox(width: AppSpacing.space2),
          _Chip(
            label: recordCardActivityLabel(activity),
            on: selected == activity,
            // 고른 것을 다시 누르면 전체로 돌아온다.
            onTap: () => onChanged(selected == activity ? null : activity),
          ),
        ],
      ],
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space3,
          vertical: AppSpacing.space2,
        ),
        decoration: BoxDecoration(
          color: on ? colors.primary : colors.bgSurface,
          borderRadius: AppRadius.full,
        ),
        child: Text(
          label,
          style: AppTypographyV2.body18.copyWith(
            color: on ? colors.textOnPrimary : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
