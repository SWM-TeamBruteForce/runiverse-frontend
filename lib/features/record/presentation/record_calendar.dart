import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_sizes.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_icon.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record/presentation/record_day_list.dart';
import 'package:runiverse/features/record/presentation/record_state.dart';

/// 기록 캘린더 — 시안 `158:3847`.
///
/// ## 평소에는 **일곱 날만** 보여준다
///
/// 시안이 월 달력을 가로 스트립으로 바꿨다. 기록을 보는 사람이 가장 자주
/// 찾는 것은 **어제와 오늘**이고, 달 전체를 늘 펼쳐 두면 그 둘이 서른 칸
/// 사이에 묻힌다.
///
/// ⚠️ 시안(`158:3848`)은 오늘을 **맨 왼쪽**에 두고 여섯 칸을 그리는데,
/// 그러면 **지난 날을 볼 수가 없다.** 오늘을 가운데 두고 앞뒤 3일씩,
/// 일곱 칸으로 늘렸다(`stripAround`).
///
/// ## 더 넓게 보려면 월 달력을 편다
///
/// 우상단 달력 아이콘이 둘을 오간다. 스트립 밖의 날은 그쪽에서 고른다 —
/// 스트립을 좌우로 넘기게 만들면 **어디까지 왔는지 알 수 없다.**
///
/// ## ⚠️ 러닝한 날에만 점을 찍는다
///
/// 달 전체를 색으로 칠하지 않는다. 안 뛴 날이 결손으로 읽히면 안 된다 —
/// 어느 쪽 보기에서든 **점은 뛴 날에만** 있다.
class RecordCalendar extends StatefulWidget {
  const RecordCalendar({
    required this.data,
    required this.onSelect,
    required this.onMoveMonth,
    this.onOpen,
    super.key,
  });

  final RecordData data;
  final ValueChanged<DateTime> onSelect;

  /// `-1`이면 이전 달, `+1`이면 다음 달.
  final ValueChanged<int> onMoveMonth;

  /// 기록 한 줄을 눌렀을 때. `null`이면 줄이 눌리지 않는다.
  final ValueChanged<RunRecord>? onOpen;

  @override
  State<RecordCalendar> createState() => _RecordCalendarState();
}

class _RecordCalendarState extends State<RecordCalendar> {
  /// 달 전체를 펴 두었는가. **기본은 접힌 상태**다.
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final colors = context.appColorsV2;
    final summary = data.monthSummary;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        border: Border.all(color: colors.borderDefault),
        borderRadius: AppRadius.lg,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppStrings.recordCalendarTitle,
                  style: AppTypographyV2.body05.copyWith(
                    color: colors.textStrong,
                  ),
                ),
                // ⚠️ **상태를 아이콘으로 말한다.** 열고 닫는 버튼이 늘 같은
                // 모양이면 지금 무엇을 보고 있는지 알 수 없다.
                _ToggleButton(
                  expanded: _expanded,
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.space5),

            if (!_expanded)
              _Strip(data: data, onSelect: widget.onSelect)
            else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _MonthButton(
                    icon: AppIcons.left,
                    tooltip: AppStrings.recordPrevMonth,
                    onPressed: () => widget.onMoveMonth(-1),
                  ),
                  Text(
                    AppStrings.recordMonthLabel(data.month),
                    style: AppTypographyV2.body05.copyWith(
                      color: colors.textStrong,
                    ),
                  ),
                  _MonthButton(
                    icon: AppIcons.right,
                    tooltip: AppStrings.recordNextMonth,
                    onPressed: () => widget.onMoveMonth(1),
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
                style: AppTypographyV2.body15.copyWith(
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
                        style: AppTypographyV2.body18.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.space2),

              _Grid(data: data, onSelect: widget.onSelect),
            ],

            // ⚠️ **그날 내용이 같은 카드 안에 있다.** 시안 `158:3847`이
            // 캘린더와 그날 기록을 한 카드로 묶는다 — 날짜를 고르는 것과
            // 그 결과가 떨어져 있으면 무엇이 바뀌었는지 눈이 못 따라간다.
            const SizedBox(height: AppSpacing.space5),
            Divider(height: 1, color: colors.borderDefault),
            const SizedBox(height: AppSpacing.space5),

            RecordDayList(
              day: data.selectedDay,
              records: data.selectedRecords,
              onOpen: widget.onOpen,
            ),
          ],
        ),
      ),
    );
  }
}

/// 스트립과 월 달력을 오가는 버튼.
class _ToggleButton extends StatelessWidget {
  const _ToggleButton({required this.expanded, required this.onPressed});

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    tooltip: expanded
        ? AppStrings.recordCalendarCollapse
        : AppStrings.recordCalendarExpand,
    constraints: const BoxConstraints(
      minWidth: AppSizes.touchDefault,
      minHeight: AppSizes.touchDefault,
    ),
    icon: AppIcon(
      expanded ? AppIcons.close : AppIcons.calendar,
      size: AppSpacing.space6,
      color: context.appColorsV2.textSecondary,
    ),
  );
}

/// 오늘을 가운데 둔 일곱 날. 시안 `158:3848`.
class _Strip extends StatelessWidget {
  const _Strip({required this.data, required this.onSelect});

  final RecordData data;
  final ValueChanged<DateTime> onSelect;

  /// 뛴 날 아래 찍는 점.
  static const _dotSize = 6.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Row(
      children: [
        for (final day in data.stripDays)
          Expanded(
            child: GestureDetector(
              onTap: () => onSelect(day),
              // 글자가 좁아 빈 곳을 눌러도 잡히게 한다.
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.space2,
                ),
                child: Column(
                  children: [
                    Text(
                      AppStrings.recordWeekdayOf(day),
                      style: AppTypographyV2.body18.copyWith(
                        color: day == data.selectedDay
                            ? colors.primary
                            : colors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space2),
                    Text(
                      '${day.day}',
                      style: AppTypographyV2.body10.copyWith(
                        color: day == data.selectedDay
                            ? colors.primary
                            : colors.textStrong,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space2),

                    // ⚠️ **뛴 날에만 점이 있다.** 안 뛴 날에도 자리는 남겨
                    // 칸 높이가 들쭉날쭉하지 않게 한다.
                    SizedBox(
                      width: _dotSize,
                      height: _dotSize,
                      child: (data.rangeByDay[day] ?? const []).isEmpty
                          ? null
                          : DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MonthButton extends StatelessWidget {
  const _MonthButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  /// [AppIcons]의 상수.
  final String icon;
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
    icon: AppIcon(
      icon,
      size: AppSpacing.space5,
      color: context.appColorsV2.textSecondary,
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
    final colors = context.appColorsV2;

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
                  style: AppTypographyV2.body15.copyWith(
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
