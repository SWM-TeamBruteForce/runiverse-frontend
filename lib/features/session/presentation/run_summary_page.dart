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
import 'package:runiverse/features/session/presentation/run_session_provider.dart';

/// 러닝 요약 (S15).
///
/// ## ⚠️ 나가면 사라진다
///
/// 기록을 저장할 서버도 저장소도 아직 없다. 이 화면을 닫는 순간 방금 달린 것이
/// 없어진다 — **알고 남겨둔 상태다**(`docs/specs/2026-08-05-solo-run-design.md` 9절).
///
/// ## 정본에 있는데 아직 없는 것 셋
///
/// 정본 S15는 `제목 · 획득 컬러 ◉ · 거리·시간 · 평균 페이스 · 버튼 셋`이다.
/// 이 중 셋은 지금 만들 수 없어 **자리까지 비워 두었다** — 나중에 넣을 때
/// 레이아웃이 흔들리는 편이, 눌러도 아무 일 없는 버튼을 두는 것보다 정직하다.
///
/// - **획득 컬러 ◉** — `features/color/`가 비어 있고 색 생성 규칙이 아직 없다.
///   원래는 이 앞에 S14(컬러 리빌)가 온다.
/// - **자세한 기록 보기 → S16** — S16 화면 자체가 없다.
/// - **피드에 공유하기** — 피드 탭이 `ComingSoonPage`다.
///
/// ## 지도는 여기 없다
///
/// 정본에서 경로 지도는 S15가 아니라 **S16의 "컬러 경로 지도"**다. S15의 규칙은
/// "요약은 짧고 가볍게 — 핵심 3~4개". 지도를 되살리려면 S16을 만들어 거기 둔다.
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
    final averagePace = PaceCalculator.format(
      PaceCalculator.perKilometer(
        meters: metrics.distanceMeters,
        elapsed: metrics.elapsed,
      ),
    );

    return Scaffold(
      backgroundColor: colors.bgBase,
      body: SafeArea(
        child: Column(
          children: [
            // 정본은 제목부터 페이스까지를 한 덩어리로 화면 가운데 세운다.
            // 지도가 빠진 자리를 여백으로 두는 편이 요약을 가볍게 만든다.
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppStrings.runSummaryTitle,
                      style: AppTypography.h2.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),

                    // 획득 컬러 ◉ 자리. 색 생성 규칙이 정해지면 여기 들어간다.
                    const SizedBox(height: AppSpacing.space7),

                    // 정본대로 거리와 시간을 한 줄에 잇는다. 셋을 나란히 놓으면
                    // 44px 숫자가 가로를 넘긴다 — 실제로 102px 넘쳤다.
                    Text(
                      '${(metrics.distanceMeters / 1000).toStringAsFixed(2)} km'
                      ' · ${_elapsedText(metrics.elapsed)}',
                      style: AppTypography.metricLg.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space2),
                    Text(
                      '${AppStrings.runSummaryAveragePace} '
                      '$averagePace${AppStrings.profilePacePerKm}',
                      style: AppTypography.body.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(AppSpacing.space5),
              // 정본에서 `홈으로`는 위의 버튼 둘에 밀린 3순위라 테두리가 없다.
              // 지금은 이 화면의 유일한 액션이다. 유일한 것을 ghost로 두면
              // 어디를 눌러야 하는지가 사라진다 — 둘이 생기면 ghost로 내린다.
              child: AppButton(
                label: AppStrings.runSummaryHome,
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

class _NothingToShow extends StatelessWidget {
  const _NothingToShow();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: AppButton(
        label: AppStrings.runSummaryHome,
        expand: false,
        onPressed: () => context.go(AppRoutes.home),
      ),
    ),
  );
}
