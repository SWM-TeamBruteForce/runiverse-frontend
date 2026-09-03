import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_sizes.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/features/record/domain/run_detail.dart';
import 'package:runiverse/features/record/domain/split_aggregator.dart';
import 'package:runiverse/features/record/presentation/split_line_chart.dart';
import 'package:runiverse/features/session/domain/pace_calculator.dart';
import 'package:runiverse/core/widgets/run_map_view.dart';

/// 러닝 결과 (S16) — Figma `46:69`에 `47:65`(S16.5)를 이어 붙인 한 화면.
///
/// ## 두 곳에서 열린다
///
/// 러닝을 막 끝냈을 때(S15 → S16)와 기록 탭에서 지난 기록을 눌렀을 때다.
/// **화면은 어느 쪽인지 모른다** — [RunDetail] 하나만 받는다. 그래서 세션
/// provider를 읽지 않고, `record`가 `session/presentation`에 기대지도 않는다.
///
/// ## 정본과 다른 점: 두 화면을 합쳤다
///
/// 정본은 S16 안의 `구간별 상세 비교 ›` 카드로 별도 화면(S16.5)에 들어가게
/// 했다. 그 진입 카드를 없애고 **스크롤로 내려가면 나오도록** 합쳤다.
///
/// ## Figma에 있는데 여기 없는 것
///
/// - **획득 컬러 카드** — 색 생성 규칙이 아직 없다
/// - **파티원 비교 · 러너 칩 · 차트의 두 번째 선** — 매칭 러닝이 없어 비교할
///   대상 자체가 없다
/// - **구간별 경사** — `GeoPoint.altitude`가 "경사를 내는 데 쓰지 않는다"고
///   못 박고 있다. GPS 고도 오차가 ±10~20m다
class RunResultView extends StatelessWidget {
  const RunResultView({required this.detail, super.key});

  final RunDetail detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // 테이블은 1km, 그래프는 50m다. 같은 러닝을 두 배율로 본다 — 표는
    // "몇 번째 킬로를 몇 분에 뛰었나"를, 그래프는 "어디서 흔들렸나"를 답한다.
    final splits = detail.tableSplits;
    final samples = detail.chartSamples;

    return Scaffold(
      backgroundColor: colors.bgBase,
      body: SafeArea(
        child: Column(
          children: [
            _Header(onBack: () => Navigator.of(context).maybePop()),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space4,
                  AppSpacing.space5,
                  AppSpacing.space4,
                  AppSpacing.space8,
                ),
                children: [
                  _RouteCard(detail: detail),
                  const SizedBox(height: AppSpacing.space6),
                  _MetricGrid(detail: detail),
                  const SizedBox(height: AppSpacing.space6),

                  if (splits.isEmpty)
                    const _NoSplits()
                  else ...[
                    SplitLineChart(
                      title: AppStrings.runResultPaceChart,
                      unit: AppStrings.profilePacePerKm,
                      values: [
                        for (final s in samples)
                          (s.pace ?? Duration.zero).inSeconds.toDouble(),
                      ],
                      labels: _sampleLabels(samples),
                      format: (v) =>
                          PaceCalculator.format(Duration(seconds: v.round())),
                      color: colors.primary,
                      hint: AppStrings.runResultChartHint,
                      // ⚠️ 페이스만 뒤집는다. 작을수록 빠르므로 그대로 올리면
                      // 솟은 봉우리가 "느렸던 구간"이 되어 거꾸로 읽힌다.
                      inverted: true,
                    ),
                    const SizedBox(height: AppSpacing.space4),
                    _SplitTable(detail: detail),
                    const SizedBox(height: AppSpacing.space4),
                    // 구간 케이던스를 하나도 모르면 차트를 아예 접는다.
                    // 빈 차트를 그리면 "0spm으로 뛰었다"로 읽힌다.
                    if (detail.hasCadence) ...[
                      SplitLineChart(
                        title: AppStrings.runResultCadenceChart,
                        unit: AppStrings.runResultCadenceUnit,
                        values: [
                          for (final s in samples)
                            (s.cadenceSpm ?? 0).toDouble(),
                        ],
                        labels: _sampleLabels(samples),
                        format: (v) => v.round().toString(),
                        color: colors.primary,
                        hint: AppStrings.runResultChartHint,
                        // 서버 실측값이라 꼬리표를 달지 않는다.
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// x축 라벨. 마지막 자투리 구간만 실제로 닿은 지점을 적는다.
  /// 50m 표본의 x축·툴팁 라벨. **닿은 지점의 누적 거리**다.
  ///
  /// 구간 번호(`1km` `2km`)를 쓰지 않는다 — 50m면 5km에 100개가 되어 번호가
  /// 아무 뜻도 갖지 못한다. 어디쯤이었는지가 읽고 싶은 값이다.
  static List<String> _sampleLabels(List<SplitBucket> samples) => [
    for (final sample in samples)
      AppStrings.runResultPartialLabel(sample.endDistanceMeters / 1000),
  ];

}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          tooltip: AppStrings.runResultBack,
          constraints: const BoxConstraints(
            minWidth: AppSizes.touchDefault,
            minHeight: AppSizes.touchDefault,
          ),
          icon: Icon(
            LucideIcons.chevronLeft,
            size: AppSpacing.space6,
            color: colors.textPrimary,
          ),
        ),
        Text(
          AppStrings.runResultTitle,
          style: AppTypography.h3.copyWith(color: colors.textPrimary),
        ),
      ],
    );
  }
}

/// 달린 길. Figma 프레임 이름이 `route (내 경로만)`인 그대로다 — 파티원 경로는
/// 어떤 화면으로도 내보내지 않는다.
class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.detail});

  final RunDetail detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return ClipRRect(
      borderRadius: AppRadius.lg,
      child: SizedBox(
        height: 238,
        child: Stack(
          children: [
            Positioned.fill(child: RunMapView(track: detail.track)),
            Positioned(
              left: AppSpacing.space3,
              top: AppSpacing.space3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.bgSurface,
                  borderRadius: AppRadius.full,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space3,
                    vertical: AppSpacing.space1,
                  ),
                  child: Text(
                    '${detail.distanceKm.toStringAsFixed(2)}'
                    '${AppStrings.runSummaryUnitKm} · '
                    '${_elapsedText(detail.duration)}',
                    style: AppTypography.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 시간 · 거리 · 페이스 · 케이던스 2×2. Figma `46:96`.
class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.detail});

  final RunDetail detail;

  @override
  Widget build(BuildContext context) {
    final cadence = detail.cadenceSpm;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _Metric(
                label: AppStrings.runResultTime,
                value: _elapsedText(detail.duration),
              ),
            ),
            Expanded(
              child: _Metric(
                label: AppStrings.runResultDistance,
                value:
                    '${detail.distanceKm.toStringAsFixed(2)}'
                    '${AppStrings.runSummaryUnitKm}',
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.space3),
        Row(
          children: [
            Expanded(
              child: _Metric(
                label: AppStrings.runResultPace,
                value: PaceCalculator.format(detail.averagePace),
              ),
            ),
            Expanded(
              child: _Metric(
                label: AppStrings.runResultCadence,
                // 케이던스는 못 낼 때가 흔하다. 0으로 때우지 않는다.
                value: cadence == null ? '--' : '$cadence',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: AppTypography.metricMd.copyWith(color: colors.textPrimary),
        ),
        Text(
          label,
          style: AppTypography.caption.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }
}

/// 구간 리스트. 정본의 `경사`는 빼고 `구간 · 페이스(격차) · 소모`만 남았다.
class _SplitTable extends StatefulWidget {
  const _SplitTable({required this.detail});

  final RunDetail detail;

  /// 이만큼 넘어가면 접는다. 10km(10구간)에서도 차트 둘이 한 화면에 들어오게.
  static const collapsedCount = 5;

  @override
  State<_SplitTable> createState() => _SplitTableState();
}

class _SplitTableState extends State<_SplitTable> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final all = widget.detail.tableSplits;
    final collapsed = !_expanded && all.length > _SplitTable.collapsedCount;
    final shown = collapsed ? all.take(_SplitTable.collapsedCount) : all;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        border: Border.all(color: colors.borderDefault),
        borderRadius: AppRadius.lg,
      ),
      child: Column(
        children: [
          const _SplitHead(),
          for (final split in shown)
            _SplitRow(
              split: split,
              totalKm: widget.detail.distanceKm,
              average: widget.detail.averagePace,
            ),
          if (collapsed)
            InkWell(
              onTap: () => setState(() => _expanded = true),
              child: SizedBox(
                height: AppSizes.touchDefault,
                child: Center(
                  child: Text(
                    AppStrings.runResultMoreSplits,
                    style: AppTypography.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SplitHead extends StatelessWidget {
  const _SplitHead();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final style = AppTypography.micro.copyWith(color: colors.textTertiary);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.space4,
        AppSpacing.space3,
        AppSpacing.space4,
        AppSpacing.space2,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(AppStrings.runResultSplitColumn, style: style),
          ),
          Expanded(child: Text(AppStrings.runResultPace, style: style)),
          Text(AppStrings.runResultBurnedColumn, style: style),
        ],
      ),
    );
  }
}

class _SplitRow extends StatelessWidget {
  const _SplitRow({
    required this.split,
    required this.totalKm,
    required this.average,
  });

  final SplitBucket split;
  final double totalKm;
  final Duration? average;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final burned = split.caloriesKcal;
    // 평균과의 거리. 순위가 아니라 내 평균 대비다.
    final pace = split.pace;
    final gap = (average == null || pace == null) ? null : pace - average!;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space4,
        vertical: AppSpacing.space3,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              split.isPartialOf(SplitAggregator.tableMeters)
                  ? AppStrings.runResultPartialLabel(totalKm)
                  : AppStrings.runResultSplitLabel(split.index),
              style: AppTypography.body.copyWith(color: colors.textSecondary),
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  PaceCalculator.format(split.pace),
                  style: AppTypography.body.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (gap != null) ...[
                  const SizedBox(width: AppSpacing.space2),
                  Text(
                    _gapText(gap),
                    // 평균보다 빨랐으면 success, 느렸으면 error. 순위가
                    // 아니라 내 평균과의 거리다.
                    //
                    // ⚠️ **0은 어느 쪽도 아니다.** `isNegative`만 보면 0이
                    // 느린 쪽으로 빨갛게 칠해진다 — 평균과 같은 구간을
                    // 나무라는 셈이다.
                    style: AppTypography.micro.copyWith(
                      color: switch (gap.inSeconds) {
                        < 0 => colors.success,
                        > 0 => colors.error,
                        _ => colors.textTertiary,
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            '$burned${AppStrings.runResultUnitKcal}',
            style: AppTypography.caption.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  static String _gapText(Duration gap) {
    final seconds = gap.inSeconds;
    // 부호를 반드시 붙인다 — 색만으로 빠르고 느림을 알리지 않는다(색맹 대응,
    // `implementation-notes` 3-5). 0에는 부호가 없다.
    if (seconds == 0) return '0s';
    return seconds > 0 ? '+${seconds}s' : '${seconds}s';
  }
}

class _NoSplits extends StatelessWidget {
  const _NoSplits();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space8),
      child: Text(
        AppStrings.runResultNoSplits,
        textAlign: TextAlign.center,
        style: AppTypography.body.copyWith(color: colors.textTertiary),
      ),
    );
  }
}

String _elapsedText(Duration elapsed) {
  final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
  final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
