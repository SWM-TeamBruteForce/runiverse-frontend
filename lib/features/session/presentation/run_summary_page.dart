import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_sizes.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/core/widgets/v2/app_icon.dart';
import 'package:runiverse/core/widgets/v2/fact_card.dart';
import 'package:runiverse/features/session/domain/pace_calculator.dart';
import 'package:runiverse/features/session/domain/run_session_state.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';

/// 러닝 요약 (S15) — 시안 `158:3764` `러닝 종료 요약 페이지`.
///
/// ## ⚠️ 나가면 사라진다
///
/// 기록을 저장할 서버도 저장소도 아직 없다. 이 화면을 닫는 순간 방금 달린 것이
/// 없어진다 — **알고 남겨둔 상태다**(`docs/specs/2026-08-05-solo-run-design.md` 9절).
///
/// ## 시안에 있는데 여기 없는 것
///
/// - **`기록카드 남기기`** — 기록카드 탭이 `ComingSoonPage`다. 눌러도 아무 데도
///   가지 않는 버튼을 두면 고장으로 읽힌다. 탭이 살아나면 이 위에 붙는다.
///
/// ## 시안과 다르게 둔 것
///
/// - **오른쪽 위 닫기.** 시안에는 없지만 버튼 하나가 빠진 지금은 이것이 이
///   화면을 벗어나는 유일한 길이다 — 없으면 갇힌다
/// - **큰 수치의 단위를 `km`로 썼다.** 시안은 `5.02 /km`인데 `/km`는 페이스의
///   단위다. 총거리에 붙을 자리가 아니라 시안 쪽 오기로 본다
///
/// ## 제목이 시안과 다르다
///
/// 시안의 `러닝종료`는 이 화면이 무엇인지가 아니라 방금 한 일을 가리킨다.
/// 우리는 `러닝 완료`를 그대로 쓴다 — 같은 뜻이고 이미 쓰던 말이다.
class RunSummaryPage extends ConsumerWidget {
  const RunSummaryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColorsV2;
    final state = ref.watch(runSessionControllerProvider);

    // 요약이 아닌 상태로 여기 오면 보여줄 것이 없다. 홈으로 돌려보낸다 —
    // 앱을 재시작해 딥링크로 들어오는 경우가 그렇다.
    if (state is! RunFinished) return const _NothingToShow();

    final metrics = state.metrics;
    // 결과 조회는 방 번호로 한다. 없으면 상세로 갈 수 없다.
    final room = ref.watch(runningConnectionProvider).room;
    // 서버가 아직 기록을 확정하는 중이면 상세로 가는 문을 잠근다.
    final settling = ref.watch(
      runningConnectionProvider.select((it) => it.settling),
    );
    final averagePace = PaceCalculator.format(
      PaceCalculator.perKilometer(
        meters: metrics.distanceMeters,
        elapsed: metrics.elapsed,
      ),
    );

    return Scaffold(
      backgroundColor: colors.bgBase,
      body: Stack(
        children: [
          const Positioned.fill(child: _Glow()),
          SafeArea(
            child: Column(
              children: [
                _TopBar(onClose: () => _leave(ref, context)),

                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.space4,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _Distance(meters: metrics.distanceMeters),
                          const SizedBox(height: AppSpacing.space8),

                          // 거리 하나만 키우고 나머지 둘은 나란히 눕힌다. 셋을
                          // 같은 크기로 두면 무엇을 봐야 하는지가 사라진다.
                          Row(
                            children: [
                              Expanded(
                                child: FactCard(
                                  label: AppStrings.runSummaryTotalTime,
                                  value: _elapsedText(metrics.elapsed),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.space3),
                              Expanded(
                                child: FactCard(
                                  label: AppStrings.runSummaryAveragePace,
                                  value: averagePace,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.space4,
                    0,
                    AppSpacing.space4,
                    AppSpacing.space4,
                  ),
                  child: AppButtonV2(
                    label: settling
                        ? AppStrings.runSummaryDetailSettling
                        : AppStrings.runSummaryDetail,
                    variant: AppButtonV2Variant.tonal,
                    // `go`가 아니라 `push`다. 결과 화면이 요약 위에 얹혀야
                    // 뒤로가기로 돌아오고, 그동안 트랙도 그대로 남는다.
                    // ⚠️ **방 번호만 넘긴다.** 상세는 서버가 확정한 값을 읽는다.
                    // 앱이 계산한 값을 그리면 같은 러닝의 숫자가 화면마다
                    // 달라진다.
                    //
                    // 방을 못 열었으면(409 등) 결과를 볼 수 없다. 그때는 버튼을
                    // 비활성으로 둔다 — 눌러 봐야 빈 화면이다.
                    //
                    // ⚠️ **확정 중에도 잠근다.** 서버가 `RUNNING_FINISH`를
                    // 처리하기 전에 부르면 200에 빈 기록이 와서
                    // `0.00km · 구간 0개`가 된다([RunningConnectionState.settling]).
                    onPressed: room == null || settling
                        ? null
                        : () =>
                              context.push(AppRoutes.runResult, extra: room.id),
                  ),
                ),
              ],
            ),
          ),
        ],
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

/// 위에서 번지는 브랜드 빛.
///
/// 시안(`158:3765`~`158:3768`)은 50px 블러를 먹인 색면 셋을 겹쳐 만든다.
/// **그라디언트로 근사한다** — 화면 높이만 한 면에 실제 블러를 걸면 매 프레임
/// 값이 나가고, 이 화면은 어차피 움직이지 않아 결과가 같다.
class _Glow extends StatelessWidget {
  const _Glow();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          // ⚠️ **같은 색의 투명도만 낮춰 내려간다.** 중간에 다른 색을 끼우면
          // 경계가 띠로 보인다 — 빛이 번지는 것이 아니라 두 면이 만난 것처럼
          // 된다.
          colors: [
            colors.primary.withValues(alpha: 0.48),
            colors.primary.withValues(alpha: 0.22),
            colors.bgBase,
          ],
          // 시안(`158:3765`)의 파란 면이 화면 높이의 3분의 2까지 내려온다.
          stops: const [0, 0.36, 0.82],
        ),
      ),
    );
  }
}

/// 제목과 닫기.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
      child: Row(
        children: [
          // 제목이 가운데 오도록 오른쪽 버튼만큼 왼쪽을 비운다.
          const SizedBox(width: AppSizes.touchDefault),
          Expanded(
            child: Text(
              AppStrings.runSummaryTitle,
              textAlign: TextAlign.center,
              style: AppTypographyV2.heading06.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
          IconButton(
            onPressed: onClose,
            tooltip: AppStrings.runSummaryClose,
            constraints: const BoxConstraints(
              minWidth: AppSizes.touchDefault,
              minHeight: AppSizes.touchDefault,
            ),
            icon: AppIcon(
              AppIcons.close,
              size: AppSpacing.space6,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 총 거리 — 이 화면에서 60px은 여기 하나뿐이다.
class _Distance extends StatelessWidget {
  const _Distance({required this.meters});

  final double meters;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 무엇의 숫자인지. 시안의 알약 배지다(`158:3773`).
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.primaryMuted,
            borderRadius: AppRadius.full,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space5,
              vertical: AppSpacing.space3,
            ),
            child: Text(
              AppStrings.runSummaryTotalDistance,
              style: AppTypographyV2.body06.copyWith(
                color: colors.matchWaiting,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.space3),

        // 숫자와 단위를 베이스라인으로 맞춘다. 가운데 정렬하면 `km`가 60px
        // 숫자의 허리에 붙어 뜬다.
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              (meters / 1000).toStringAsFixed(2),
              style: AppTypographyV2.heading01.copyWith(
                color: colors.textStrong,
                // 파란 빛 위에 얹히는 흰 글자다. 굵기를 한 칸 올리고 뒤에
                // 어두운 그림자를 깔아야 가장자리가 뭉개지지 않는다.
                fontWeight: FontWeight.w800,
                shadows: [
                  Shadow(
                    color: colors.bgBase.withValues(alpha: 0.55),
                    blurRadius: AppSpacing.space6,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.space1),
            Text(
              AppStrings.runSummaryUnitKm,
              style: AppTypographyV2.heading02.copyWith(
                color: colors.textTertiary,
              ),
            ),
          ],
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
      child: AppButtonV2(
        label: AppStrings.runSummaryHome,
        expand: false,
        onPressed: () => context.go(AppRoutes.home),
      ),
    ),
  );
}
