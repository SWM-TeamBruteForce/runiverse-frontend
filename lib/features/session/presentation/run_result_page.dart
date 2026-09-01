import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/storage/body_profile_provider.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_sizes.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/features/session/domain/calorie_calculator.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/pace_calculator.dart';
import 'package:runiverse/features/session/domain/run_metrics.dart';
import 'package:runiverse/features/session/domain/run_split.dart';
import 'package:runiverse/features/session/domain/run_session_state.dart';
import 'package:runiverse/features/session/domain/split_calculator.dart';
import 'package:runiverse/features/session/presentation/run_map_view.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/split_line_chart.dart';

/// 러닝 결과 (S16) — Figma `46:69`에 `47:65`(S16.5)를 이어 붙인 한 화면.
///
/// ## 정본과 다른 점: 두 화면을 합쳤다
///
/// 정본은 S16 안의 `구간별 상세 비교 ›` 카드로 별도 화면(S16.5)에 들어가게 했다.
/// 그 진입 카드를 없애고 **스크롤로 내려가면 나오도록** 합쳤다. 한 러닝의
/// 결과를 두 번 열어야 할 이유가 없다.
///
/// ## Figma에 있는데 여기 없는 것
///
/// - **획득 컬러 카드** — 색 생성 규칙이 아직 없다(S15와 같은 이유)
/// - **파티원 비교 · 러너 칩 · 차트의 두 번째 선** — 매칭 러닝이 없어 비교할
///   대상 자체가 없다. 붙일 때 섹션 하나를 얹으면 되도록 남겨 두었다
/// - **구간별 경사** — `GeoPoint.altitude`가 "경사를 내는 데 쓰지 않는다"고
///   못 박고 있다. GPS 고도 오차가 ±10~20m다
///
/// ## ⚠️ 케이던스 차트는 지어낸 값이다
///
/// 케이던스는 `TrackPoint`에만 실리는데 그건 서버 ack 뒤 지워지고, 화면에 남는
/// `GeoPoint`에는 그 값이 없다. 컨트롤러의 걸음 표본도 최근 창만 남기고 계속
/// 버린다. 그래서 [_sampleCadence]가 **고정값**을 만든다 — 대신 차트에 `예시`
/// 꼬리표가 붙어 그 사실을 화면에서 밝힌다. 실측값을 남기려면 러닝 중 컨트롤러가
/// 1km마다 스냅샷을 들어야 하고, 그건 실기기 검증과 함께 갈 별도 작업이다.
class RunResultPage extends ConsumerWidget {
  const RunResultPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final state = ref.watch(runSessionControllerProvider);

    // 결과가 아닌 상태로 들어오면 보여줄 것이 없다. 요약과 같은 규칙이다.
    if (state is! RunFinished) {
      return Scaffold(
        backgroundColor: colors.bgBase,
        body: const SafeArea(child: SizedBox.shrink()),
      );
    }

    final controller = ref.read(runSessionControllerProvider.notifier);
    final metrics = state.metrics;
    final track = controller.track;
    final splits = SplitCalculator.from(track);
    final weightKg = ref.read(bodyProfileProvider).weightKg;

    return Scaffold(
      backgroundColor: colors.bgBase,
      body: SafeArea(
        child: Column(
          children: [
            _Header(onBack: () => context.pop()),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space4,
                  AppSpacing.space5,
                  AppSpacing.space4,
                  AppSpacing.space8,
                ),
                children: [
                  _RouteCard(track: track, metrics: metrics),
                  const SizedBox(height: AppSpacing.space6),
                  _MetricGrid(metrics: metrics),
                  const SizedBox(height: AppSpacing.space6),

                  if (splits.isEmpty)
                    const _NoSplits()
                  else ...[
                    SplitLineChart(
                      title: AppStrings.runResultPaceChart,
                      unit: AppStrings.profilePacePerKm,
                      values: [
                        for (final split in splits)
                          split.pace.inSeconds.toDouble(),
                      ],
                      labels: _labels(splits, metrics.distanceKm),
                      format: (v) =>
                          PaceCalculator.format(Duration(seconds: v.round())),
                      color: colors.primary,
                      hint: AppStrings.runResultChartHint,
                    ),
                    const SizedBox(height: AppSpacing.space4),
                    _SplitTable(
                      splits: splits,
                      totalKm: metrics.distanceKm,
                      average: metrics.averagePace,
                      weightKg: weightKg,
                    ),
                    const SizedBox(height: AppSpacing.space4),
                    SplitLineChart(
                      title: AppStrings.runResultCadenceChart,
                      unit: AppStrings.runResultCadenceUnit,
                      values: _sampleCadence(splits.length),
                      labels: _labels(splits, metrics.distanceKm),
                      format: (v) => v.round().toString(),
                      color: colors.primary,
                      hint: AppStrings.runResultChartHint,
                      badge: AppStrings.runResultSample,
                    ),
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
  static List<String> _labels(List<RunSplit> splits, double totalKm) => [
    for (final split in splits)
      split.isPartial
          ? AppStrings.runResultPartialLabel(totalKm)
          : AppStrings.runResultSplitLabel(split.index),
  ];

  /// ⚠️ **진짜 케이던스가 아니다.** 구간별 실측값이 남지 않아 만들어 낸 값이다.
  ///
  /// 실측이 붙는 날 이 함수를 지우고 그 값을 넘기면 된다 — 차트는 그대로 쓴다.
  /// 달리기 케이던스가 보통 170~180spm이라 그 언저리에서 흔들리게 두었다.
  static List<double> _sampleCadence(int count) {
    const pattern = [172.0, 176.0, 169.0, 178.0, 174.0, 171.0, 177.0];
    return [for (var i = 0; i < count; i++) pattern[i % pattern.length]];
  }
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
  const _RouteCard({required this.track, required this.metrics});

  final List<List<GeoPoint>> track;
  final RunMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return ClipRRect(
      borderRadius: AppRadius.lg,
      child: SizedBox(
        height: 238,
        child: Stack(
          children: [
            Positioned.fill(child: RunMapView(track: track)),
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
                    '${metrics.distanceKm.toStringAsFixed(2)}'
                    '${AppStrings.runSummaryUnitKm} · '
                    '${_elapsedText(metrics.elapsed)}',
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
  const _MetricGrid({required this.metrics});

  final RunMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final cadence = metrics.cadenceSpm;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _Metric(
                label: AppStrings.runResultTime,
                value: _elapsedText(metrics.elapsed),
              ),
            ),
            Expanded(
              child: _Metric(
                label: AppStrings.runResultDistance,
                value:
                    '${metrics.distanceKm.toStringAsFixed(2)}'
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
                value: PaceCalculator.format(metrics.averagePace),
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
  const _SplitTable({
    required this.splits,
    required this.totalKm,
    required this.average,
    required this.weightKg,
  });

  final List<RunSplit> splits;
  final double totalKm;
  final Duration? average;
  final int? weightKg;

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
    final all = widget.splits;
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
              totalKm: widget.totalKm,
              average: widget.average,
              weightKg: widget.weightKg,
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
    required this.weightKg,
  });

  final RunSplit split;
  final double totalKm;
  final Duration? average;
  final int? weightKg;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final burned = CalorieCalculator.burned(
      meters: split.distanceMeters,
      elapsed: split.duration,
      weightKg: weightKg,
    );
    final gap = average == null ? null : split.gapTo(average!);

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
              split.isPartial
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
                    style: AppTypography.micro.copyWith(
                      // 평균보다 빨랐으면 success, 느렸으면 error. 순위가
                      // 아니라 내 평균과의 거리다.
                      color: gap.isNegative ? colors.success : colors.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            burned == null ? '--' : '$burned${AppStrings.runResultUnitKcal}',
            style: AppTypography.caption.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  static String _gapText(Duration gap) {
    final seconds = gap.inSeconds;
    return seconds >= 0 ? '+${seconds}s' : '${seconds}s';
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
