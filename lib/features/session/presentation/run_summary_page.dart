import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_sizes.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/features/session/domain/pace_calculator.dart';
import 'package:runiverse/features/session/domain/run_session_state.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';

/// 러닝 요약 (S15) — Figma `46:27` 기준.
///
/// ## ⚠️ 나가면 사라진다
///
/// 기록을 저장할 서버도 저장소도 아직 없다. 이 화면을 닫는 순간 방금 달린 것이
/// 없어진다 — **알고 남겨둔 상태다**(`docs/specs/2026-08-05-solo-run-design.md` 9절).
///
/// ## Figma에 있는데 여기 없는 것 셋
///
/// 지금 만들 수 없어 **자리까지 비웠다.** 나중에 넣을 때 레이아웃이 흔들리는
/// 편이, 눌러도 아무 일 없는 버튼을 두는 것보다 정직하다.
///
/// - **거리 카드의 글로우** — Figma는 `0 0 52px -6px rgba(226,104,60,.55)`,
///   곧 `RunHue.company` 셰이드 2다. 그 색은 **그 러닝의 획득 컬러**이지 고정값이
///   아니다. 색 생성 규칙이 정해지면 `boxShadow` 한 줄로 살아난다.
/// - **`피드로 공유하기`** (primary) — 피드 탭이 `ComingSoonPage`다.
///
/// ## 제목이 Figma와 다르다
///
/// Figma의 `이서연 님과 함께 5km 완주!`는 **매칭 러닝 전용 문구**다. 지금 도달할
/// 수 있는 건 1인 러닝뿐이라 동행자도, 목표 거리도 없다. 솔로용 카피가 정해질
/// 때까지 기존 `러닝 완료`를 Figma의 자리·크기(H1 중앙)로만 옮겼다.
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
    // 결과 조회는 방 번호로 한다. 없으면 상세로 갈 수 없다.
    final room = ref.watch(runningConnectionProvider).room;
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
            // Figma는 하단 `홈으로` 대신 우상단 X로 닫는다. 버튼 둘이 빠진
            // 지금은 이게 이 화면을 벗어나는 유일한 길이다 — 없으면 갇힌다.
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space4,
                  vertical: AppSpacing.space2,
                ),
                child: IconButton(
                  onPressed: () => _leave(ref, context),
                  tooltip: AppStrings.runSummaryClose,
                  constraints: const BoxConstraints(
                    minWidth: AppSizes.touchDefault,
                    minHeight: AppSizes.touchDefault,
                  ),
                  icon: Icon(
                    LucideIcons.x,
                    size: AppSpacing.space6,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ),

            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.space4,
                      ),
                      child: Text(
                        AppStrings.runSummaryTitle,
                        textAlign: TextAlign.center,
                        style: AppTypography.h1.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space6),
                    _DistanceCard(meters: metrics.distanceMeters),
                    const SizedBox(height: AppSpacing.space6),

                    // 거리 하나만 키우고 나머지 둘은 나란히 눕힌다. 셋을 같은
                    // 크기로 두면 무엇을 봐야 하는지가 사라진다.
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _MetricPair(
                          value: _elapsedText(metrics.elapsed),
                          label: AppStrings.runSummaryTotalTime,
                        ),
                        const SizedBox(width: AppSpacing.space9),
                        _MetricPair(
                          value: averagePace,
                          label: AppStrings.runSummaryAveragePaceUnit,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Figma footer의 secondary 버튼. primary(`피드로 공유하기`)는
            // 피드가 준비되면 이 위에 붙는다.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space4,
                0,
                AppSpacing.space4,
                AppSpacing.space4,
              ),
              child: AppButton(
                label: AppStrings.runSummaryDetail,
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.lg,
                // `go`가 아니라 `push`다. 결과 화면이 요약 위에 얹혀야
                // 뒤로가기로 돌아오고, 그동안 트랙도 그대로 남는다.
                // ⚠️ **방 번호만 넘긴다.** 상세는 서버가 확정한 값을 읽는다
                // (17·18번). 앱이 계산한 값을 그리면 같은 러닝의 숫자가
                // 화면마다 달라진다.
                //
                // 방을 못 열었으면(409 등) 결과를 볼 수 없다. 그때는 버튼을
                // 비활성으로 둔다 — 눌러 봐야 빈 화면이다.
                onPressed: room == null
                    ? null
                    : () => context.push(AppRoutes.runResult, extra: room.id),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void _leave(WidgetRef ref, BuildContext context) {
    // 다음 러닝을 위해 비운다. 안 비우면 두 번째 러닝이 첫 러닝의 거리에서
    // 이어진다.
    ref.read(runSessionControllerProvider.notifier).reset();
    context.go(AppRoutes.home);
  }

  static String _elapsedText(Duration elapsed) {
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

/// 총 거리 카드. 이 화면에서 56px은 여기 하나뿐이다.
class _DistanceCard extends StatelessWidget {
  const _DistanceCard({required this.meters});

  final double meters;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        border: Border.all(color: colors.borderDefault),
        borderRadius: AppRadius.xl,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space8,
          vertical: AppSpacing.space6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppStrings.runSummaryTotalDistance,
              style: AppTypography.caption.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.space2),

            // 숫자와 단위를 베이스라인으로 맞춘다. 가운데 정렬하면 `km`가
            // 56px 숫자의 허리에 붙어 뜬다.
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  (meters / 1000).toStringAsFixed(2),
                  style: AppTypography.metricXl.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(width: AppSpacing.space1),
                Text(
                  AppStrings.runSummaryUnitKm,
                  style: AppTypography.h2.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 수치 하나와 그 아래 라벨. 라벨이 단위를 안고 있어 수치는 숫자만 남는다.
class _MetricPair extends StatelessWidget {
  const _MetricPair({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: AppTypography.h1.copyWith(
            color: colors.textPrimary,
            // h1은 램프상 tabular가 아니다. 요약은 갱신되지 않아 흔들릴 일은
            // 없지만, 두 값의 자릿수를 서로 맞춰 두면 가운데 축이 선다.
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: AppSpacing.space1),
        Text(
          label,
          style: AppTypography.caption.copyWith(color: colors.textTertiary),
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
        label: AppStrings.runSummaryHome,
        expand: false,
        onPressed: () => context.go(AppRoutes.home),
      ),
    ),
  );
}
