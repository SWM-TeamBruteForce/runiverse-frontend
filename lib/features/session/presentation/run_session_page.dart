import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/core/widgets/page_indicator.dart';
import 'package:runiverse/features/session/domain/pace_calculator.dart';
import 'package:runiverse/features/session/domain/run_metrics.dart';
import 'package:runiverse/features/session/domain/run_session_state.dart';
import 'package:runiverse/features/session/presentation/run_map_view.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';
import 'package:runiverse/features/session/presentation/run_stop_sheet.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 러닝 진행 (S13).
///
/// ## 2페이지다
///
/// 정본은 지도 · 실시간 기록 · 파티원 비교 셋인데 **혼자 달릴 때는 파티원이
/// 없다.** 빈 페이지를 두면 스와이프해서 아무것도 없는 화면을 만나게 된다.
/// 매칭이 붙으면 셋째 장으로 들어간다.
///
/// 첫 장은 **실시간 기록**이다. 가장 자주 보는 화면이라 정본이 그렇게 정했다.
///
/// ## 화면을 켜 둔다
///
/// 포그라운드에서만 추적하므로 화면이 꺼지면 기록이 멈춘다. 러닝을 벗어날 때
/// 반드시 해제한다 — 안 하면 앱을 나가도 화면이 안 꺼진다.
class RunSessionPage extends ConsumerStatefulWidget {
  const RunSessionPage({super.key});

  @override
  ConsumerState<RunSessionPage> createState() => _RunSessionPageState();
}

class _RunSessionPageState extends ConsumerState<RunSessionPage> {
  // 기록 페이지에서 시작한다. 지도는 왼쪽으로 스와이프해서 본다.
  final _pages = PageController(initialPage: 1);
  int _page = 1;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _pages.dispose();
    super.dispose();
  }

  Future<void> _openStopSheet() async {
    final controller = ref.read(runSessionControllerProvider.notifier);
    controller.pause();

    final action = await showRunStopSheet(
      context,
      metrics: _metricsOf(ref.read(runSessionControllerProvider)),
    );
    if (!mounted) return;

    switch (action) {
      case RunStopAction.resume || null:
        // 시트를 쓸어내려 닫아도 재개한다. 멈춘 채로 두면 시간이 흐르지 않는데
        // 화면은 러닝 중으로 보인다.
        controller.resume();
      case RunStopAction.finish:
        controller.finish();
        // ⚠️ **기다리지 않는다.** 남은 좌표를 보내고 서버 확인까지 받는 데
        // 몇 초가 걸리는데, 요약에 뜨는 값은 러닝 중 계산한 것이라 그것과
        // 무관하다. 기다리게 하면 신호가 나쁜 곳에서 요약을 못 본다.
        //
        // 끝나면 소켓도 함께 닫힌다 — 안 닫으면 다음 러닝에서 서버가 중복
        // 연결로 보고 이쪽을 4001로 끊는다.
        unawaited(ref.read(runningConnectionProvider.notifier).finish());
        if (mounted) context.pushReplacement(AppRoutes.runSummary);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final state = ref.watch(runSessionControllerProvider);
    final metrics = _metricsOf(state);

    return PopScope(
      // 달리는 도중에 뒤로 나가지 못한다. 나가려면 중지 시트를 거쳐야 한다.
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.space3,
                ),
                child: PageIndicator(count: 2, currentIndex: _page),
              ),

              Expanded(
                child: PageView(
                  controller: _pages,
                  onPageChanged: (index) => setState(() => _page = index),
                  children: [
                    // ⚠️ 보정된 좌표를 그린다. 원본으로 선을 그리고 보정값으로
                    // 거리를 세면 화면의 선과 숫자가 다른 이야기를 한다.
                    RunMapView(
                      track: ref
                          .read(runSessionControllerProvider.notifier)
                          .track,
                    ),
                    _MetricsPage(metrics: metrics),
                  ],
                ),
              ),

              // 연결이 없는 채로 달리는 중이면 알린다. **막지는 않는다** —
              // 기록은 계속 재고, 붙으면 쌓인 좌표가 올라간다(설계 문서 4절).
              if (!ref.watch(runningConnectionProvider).isReady)
                const _OfflineNotice(),

              Padding(
                padding: const EdgeInsets.all(AppSpacing.space5),
                child: AppButton(
                  label: AppStrings.runStopCta,
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.lg,
                  onPressed: state is RunRunning ? _openStopSheet : null,
                ),
              ),
            ],
          ),
        ),
        backgroundColor: colors.bgBase,
      ),
    );
  }

  static RunMetrics _metricsOf(RunSessionState state) => switch (state) {
    RunRunning(:final metrics) || RunPaused(:final metrics) => metrics,
    RunFinished(:final metrics) => metrics,
    _ => const RunMetrics(
      distanceMeters: 0,
      elapsed: Duration.zero,
      currentPace: null,
    ),
  };
}

/// 실시간 기록 — 페이스 히어로 + 2×2 그리드.
class _MetricsPage extends StatelessWidget {
  const _MetricsPage({required this.metrics});

  final RunMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            AppStrings.runPaceLabel,
            style: AppTypography.caption.copyWith(color: colors.textSecondary),
          ),
          Text(
            PaceCalculator.format(metrics.currentPace),
            style: AppTypography.metricHero.copyWith(color: colors.textPrimary),
          ),
          Text(
            AppStrings.profilePacePerKm,
            style: AppTypography.caption.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.space8),

          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: AppStrings.runTimeLabel,
                  value: _elapsedText(metrics.elapsed),
                ),
              ),
              Expanded(
                child: _Metric(
                  label: AppStrings.runDistanceLabel,
                  value: (metrics.distanceMeters / 1000).toStringAsFixed(2),
                  unit: 'km',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space5),
          Row(
            children: [
              // 아직 못 재는 값이다. **지어낸 숫자를 넣지 않는다** —
              // 걸음 센서를 읽지 않는다.
              const Expanded(
                child: _Metric(
                  label: AppStrings.runCadenceLabel,
                  value: AppStrings.runUnavailable,
                ),
              ),
              Expanded(
                child: _Metric(
                  label: AppStrings.runCaloriesLabel,
                  // 몸무게를 모르면 `null`이고 그때는 `--`다. 기본 체중으로
                  // 때우면 그 사람의 칼로리가 조용히 틀린다.
                  value:
                      metrics.calories?.toString() ?? AppStrings.runUnavailable,
                  unit: metrics.calories == null ? null : 'kcal',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _elapsedText(Duration elapsed) {
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.unit});

  final String label;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final unit = this.unit;

    return Column(
      children: [
        Text(
          label,
          style: AppTypography.caption.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space1),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: AppTypography.metricMd.copyWith(color: colors.textPrimary),
            ),
            if (unit != null) ...[
              const SizedBox(width: AppSpacing.space1),
              Text(
                unit,
                style: AppTypography.caption.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// 서버에 아직 못 붙었다.
///
/// ⚠️ **경고가 아니라 안내다.** 기록은 계속 재고 있고, 연결되면 쌓인 좌표가
/// 올라간다. 빨간색으로 겁을 주면 달리는 사람이 폰을 들여다보게 된다.
class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5),
      child: Row(
        children: [
          Icon(
            LucideIcons.cloudOff,
            size: AppSpacing.space4,
            color: colors.textTertiary,
          ),
          const SizedBox(width: AppSpacing.space2),
          Expanded(
            child: Text(
              AppStrings.runOffline,
              style: AppTypography.caption.copyWith(color: colors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}
