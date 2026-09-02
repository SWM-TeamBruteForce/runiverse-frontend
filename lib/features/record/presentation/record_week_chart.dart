import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/features/record/presentation/record_state.dart';

/// 최근 7일 막대. 정본 S21의 맨 위 카드다.
///
/// ## ⚠️ 잔디가 아니다
///
/// 월 전체를 칠하지 않는다. 안 뛴 날을 결손으로 보이게 하면 잔디의 죄책감
/// 문제를 그대로 답습한다(디자인 시스템 v1.1 §5-5). **뛴 날에만 막대가 선다.**
///
/// ## ⚠️ 막대 색이 정본과 다르다
///
/// 정본은 "막대가 그날 컬러"라고 적었지만 **그 색을 만들 규칙이 아직 없다**
/// (`features/color/`가 비어 있고, 목록 API도 색을 주지 않는다).
/// 지금은 `primary` 단색으로 그린다 — 규칙이 정해지면 [_Bar]의 색 한 줄이다.
class RecordWeekChart extends StatelessWidget {
  const RecordWeekChart({
    required this.data,
    required this.onSelect,
    super.key,
  });

  final RecordData data;
  final ValueChanged<DateTime> onSelect;

  /// 막대가 설 수 있는 최대 높이. Figma `52:134`의 그림 영역이 74다
  /// (막대 바닥 y=74, 그 아래가 라벨).
  static const _barMaxHeight = 74.0;

  /// 막대 아래 요일 라벨이 차지하는 높이. Figma는 96 − 74 = 22다.
  ///
  /// ⚠️ **micro 줄높이(14)보다 커야 한다.** 딱 맞게 잡았다가 2px 넘쳐
  /// `RenderFlex overflowed`가 났다.
  static const _labelHeight = 22.0;

  /// 막대 사이 간격의 절반. Figma는 칸 44에 간격 8이다.
  static const _barGap = AppSpacing.space1;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final peak = data.weekPeakMeters;
    final summary = data.weekSummary;

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
            Text(
              AppStrings.recordWeekTitle,
              style: AppTypography.caption.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.space2),

            // 누적 거리 · 누적 시간 · 누적 경사.
            Row(
              children: [
                _Stat(
                  label: AppStrings.recordWeekDistance,
                  value: AppStrings.recordSummaryDistanceText(summary.totalKm),
                ),
                _Stat(
                  label: AppStrings.recordWeekTime,
                  value: AppStrings.recordDurationText(summary.totalDuration),
                ),
                _Stat(
                  label: AppStrings.recordWeekElevation,
                  // ⚠️ 지금은 늘 `--`다. 목록 API가 고도를 주지 않는다.
                  value: AppStrings.recordElevationText(
                    summary.elevationGainMeters,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.space4),

            SizedBox(
              height: _barMaxHeight + _labelHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final day in data.weekDays)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: _barGap,
                        ),
                        child: _Bar(
                          day: day,
                          meters: data.metersOn(day),
                          peakMeters: peak,
                          selected: day == data.selectedDay,
                          maxHeight: _barMaxHeight,
                          onTap: () => onSelect(day),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTypography.h3.copyWith(
              color: colors.textPrimary,
              // 요약 숫자도 자릿수가 흔들리지 않게 한다.
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            label,
            style: AppTypography.micro.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.day,
    required this.meters,
    required this.peakMeters,
    required this.selected,
    required this.maxHeight,
    required this.onTap,
  });

  final DateTime day;
  final int meters;
  final int peakMeters;
  final bool selected;
  final double maxHeight;
  final VoidCallback onTap;

  /// 안 뛴 날에도 남는 자국. Figma가 높이 3짜리 막대를 그려 둔다(`52:139`).
  ///
  /// **0으로 두면 칸이 통째로 비어 요일 리듬이 끊긴다.** 뛴 날만 막대가
  /// 서는 것은 맞지만, 자국까지 지우면 어디가 빈 날인지 읽기 어려워진다.
  static const _emptyStub = 3.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    // 가장 긴 날이 꼭대기를 차지한다.
    final ratio = peakMeters <= 0 ? 0.0 : meters / peakMeters;
    final height = meters <= 0
        ? _emptyStub
        : (ratio * maxHeight).clamp(_emptyStub, maxHeight);

    return GestureDetector(
      onTap: onTap,
      // 막대가 얇아 빈 곳을 눌러도 잡히게 한다.
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            // Figma는 칸(44) 폭을 막대가 꽉 채운다. 칸 자체가 `Expanded`라
            // 폭을 지정하지 않고 늘린다.
            width: double.infinity,
            height: height,
            decoration: BoxDecoration(
              // ⚠️ 정본은 "그날 획득한 러닝 컬러"다. 규칙이 없어 단색으로 둔다.
              // 안 뛴 날의 자국은 테두리 색으로 낮춰 러닝과 구분한다.
              color: meters <= 0 ? colors.borderDefault : colors.primary,
              borderRadius: AppRadius.sm,
            ),
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            AppStrings.recordWeekdays[day.weekday % 7],
            style: AppTypography.micro.copyWith(
              // 고른 날은 글자로도 표시한다 — 색만으로 알리지 않는다(3-5).
              color: selected ? colors.primary : colors.textTertiary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
