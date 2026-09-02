import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_sizes.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/features/record/presentation/record_state.dart';

/// 월 캘린더. 정본 S21의 두 번째 카드다.
///
/// ## ⚠️ 러닝한 날에만 점을 찍는다
///
/// 달 전체를 색으로 칠하지 않는다. 안 뛴 날이 결손으로 읽히면 잔디와 같은
/// 문제가 된다(디자인 시스템 v1.1 §5-5). 점 색은 정본상 그날 획득한 러닝
/// 컬러지만, 규칙이 아직 없어 `primary` 단색이다.
class RecordCalendar extends StatelessWidget {
  const RecordCalendar({
    required this.data,
    required this.onSelect,
    required this.onMoveMonth,
    super.key,
  });

  final RecordData data;
  final ValueChanged<DateTime> onSelect;

  /// `-1`이면 이전 달, `+1`이면 다음 달.
  final ValueChanged<int> onMoveMonth;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final summary = data.monthSummary;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        border: Border.all(color: colors.borderDefault),
        borderRadius: AppRadius.lg,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _MonthButton(
                  icon: LucideIcons.chevronLeft,
                  tooltip: AppStrings.recordPrevMonth,
                  onPressed: () => onMoveMonth(-1),
                ),
                Text(
                  AppStrings.recordMonthLabel(data.month),
                  style: AppTypography.h3.copyWith(color: colors.textPrimary),
                ),
                _MonthButton(
                  icon: LucideIcons.chevronRight,
                  tooltip: AppStrings.recordNextMonth,
                  onPressed: () => onMoveMonth(1),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.space2),

            // 월 요약 — 횟수 · 누적 거리 · 누적 시간.
            Text(
              '${AppStrings.recordMonthCount} ${summary.count}회 · '
              '${AppStrings.recordSummaryDistanceText(summary.totalKm)} · '
              '${AppStrings.recordDurationText(summary.totalDuration)}',
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(
                color: colors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: AppSpacing.space4),

            Row(
              children: [
                for (final label in AppStrings.recordWeekdays)
                  Expanded(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: AppTypography.micro.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.space2),

            _Grid(data: data, onSelect: onSelect),
          ],
        ),
      ),
    );
  }
}

class _MonthButton extends StatelessWidget {
  const _MonthButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    tooltip: tooltip,
    constraints: const BoxConstraints(
      minWidth: AppSizes.touchDefault,
      minHeight: AppSizes.touchDefault,
    ),
    icon: Icon(
      icon,
      size: AppSpacing.space5,
      color: context.appColors.textSecondary,
    ),
  );
}

/// 날짜 칸. 1일이 무슨 요일인지에 따라 앞을 비운다.
class _Grid extends StatelessWidget {
  const _Grid({required this.data, required this.onSelect});

  final RecordData data;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final month = data.month;

    // `DateTime(년, 월 + 1, 0)`은 다음 달 0일 = 이번 달 말일이다.
    final lastDay = DateTime(month.year, month.month + 1, 0).day;

    // 일요일 시작이므로 `weekday % 7`이 곧 앞의 빈 칸 수다(일=7→0).
    final leading = DateTime(month.year, month.month).weekday % 7;

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      // Figma는 칸이 47×47 정사각이다(`52:177` 이하). 기본값 1.0이 곧 그것이라
      // 따로 지정하지 않는다. 납작하게 만들었다가 정본과 어긋나 되돌렸다.
      // 카드 안에 통째로 펼친다. 캘린더가 따로 스크롤되면 안 된다.
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var i = 0; i < leading; i++) const SizedBox.shrink(),
        for (var day = 1; day <= lastDay; day++)
          _DayCell(
            date: DateTime(month.year, month.month, day),
            hasRecord: data.byDay.containsKey(
              DateTime(month.year, month.month, day),
            ),
            selected:
                data.selectedDay == DateTime(month.year, month.month, day),
            onTap: onSelect,
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.hasRecord,
    required this.selected,
    required this.onTap,
  });

  final DateTime date;
  final bool hasRecord;
  final bool selected;
  final ValueChanged<DateTime> onTap;

  /// Figma 실측. 선택 원 40, 러닝한 날의 점 5.
  static const _selectionSize = 40.0;
  static const _dotSize = 5.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return GestureDetector(
      onTap: () => onTap(date),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Figma `63:224` — 고른 날 뒤에 지름 40 원이 깔린다.
          SizedBox(
            width: _selectionSize,
            height: _selectionSize,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: selected ? colors.primary : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '${date.day}',
                  style: AppTypography.caption.copyWith(
                    // 채운 원 위라 글자는 뒤집힌다.
                    color: selected ? colors.bgBase : colors.textPrimary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
          // Figma는 원(끝 y=29)과 점(y=31.5) 사이를 살짝 띄운다.
          const SizedBox(height: AppSpacing.space0),
          // 뛴 날에만 점(Figma 5×5). 안 뛴 날은 빈 자리로 남긴다 —
          // 월 전체를 칠하지 않는 이유와 같다.
          SizedBox(
            height: _dotSize,
            child: hasRecord
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      // ⚠️ 정본은 그날 획득한 러닝 컬러다. 규칙이 없어 단색이다.
                      color: colors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox(width: _dotSize, height: _dotSize),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
