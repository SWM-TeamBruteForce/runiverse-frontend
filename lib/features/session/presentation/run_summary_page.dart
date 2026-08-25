import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/features/session/domain/pace_calculator.dart';
import 'package:runiverse/features/session/domain/run_session_state.dart';
import 'package:runiverse/features/session/presentation/run_map_view.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';

/// 러닝 요약 (S15).
///
/// ## ⚠️ 나가면 사라진다
///
/// 기록을 저장할 서버도 저장소도 아직 없다. 이 화면을 닫는 순간 방금 달린 것이
/// 없어진다 — **알고 남겨둔 상태다**(`docs/specs/2026-08-05-solo-run-design.md` 9절).
///
/// 정본 S14(컬러 리빌)가 원래 이 앞에 온다. 색 생성 규칙을 먼저 정해야 해서
/// 지금은 건너뛴다.
class RunSummaryPage extends ConsumerWidget {
  const RunSummaryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final state = ref.watch(runSessionControllerProvider);

    // 요약이 아닌 상태로 여기 오면 보여줄 것이 없다. 홈으로 돌려보낸다 —
    // 앱을 재시작해 딥링크로 들어오는 경우가 그렇다.
    if (state is! RunFinished) return const _NothingToShow();

    final metrics = state.metrics;
    final track = ref.read(runSessionControllerProvider.notifier).track;

    return Scaffold(
      backgroundColor: colors.bgBase,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.space5),
              child: Text(
                AppStrings.runSummaryTitle,
                style: AppTypography.h2.copyWith(color: colors.textPrimary),
              ),
            ),

            // 달린 길을 보여준다. 숫자만 남기면 어디를 뛰었는지 잊는다.
            Expanded(child: RunMapView(track: track)),

            Padding(
              padding: const EdgeInsets.all(AppSpacing.space5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _Value(
                    label: AppStrings.runDistanceLabel,
                    value: (metrics.distanceMeters / 1000).toStringAsFixed(2),
                    unit: 'km',
                  ),
                  _Value(
                    label: AppStrings.runTimeLabel,
                    value: _elapsedText(metrics.elapsed),
                  ),
                  _Value(
                    label: AppStrings.runPaceLabel,
                    // 요약에서는 **평균**을 본다. 그 순간의 페이스가 아니라
                    // 오늘 어떻게 달렸는지가 궁금한 자리다.
                    value: PaceCalculator.format(
                      PaceCalculator.perKilometer(
                        meters: metrics.distanceMeters,
                        elapsed: metrics.elapsed,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space5,
                0,
                AppSpacing.space5,
                AppSpacing.space5,
              ),
              child: AppButton(
                label: AppStrings.runSummaryDone,
                size: AppButtonSize.lg,
                onPressed: () {
                  // 다음 러닝을 위해 비운다. 안 비우면 두 번째 러닝이 첫
                  // 러닝의 거리에서 이어진다.
                  ref.read(runSessionControllerProvider.notifier).reset();
                  context.go(AppRoutes.home);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _elapsedText(Duration elapsed) {
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _Value extends StatelessWidget {
  const _Value({required this.label, required this.value, this.unit});

  final String label;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final unit = this.unit;

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: AppTypography.metricLg.copyWith(color: colors.textPrimary),
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
        Text(
          label,
          style: AppTypography.caption.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _NothingToShow extends StatelessWidget {
  const _NothingToShow();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: AppButton(
        label: AppStrings.runSummaryDone,
        expand: false,
        onPressed: () => context.go(AppRoutes.home),
      ),
    ),
  );
}
