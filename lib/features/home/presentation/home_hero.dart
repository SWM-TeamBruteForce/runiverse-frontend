import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/theme/tokens/run_palette.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/core/widgets/color/aura_orb.dart';

/// 홈 히어로 (S05 상태 1 · 기본).
///
/// 정본은 히어로가 **매칭 상태를 전담**하고 4상태로 갈린다고 정했다.
/// 매칭이 아직 없어 기본 상태 하나만 있다. 나머지 셋은 매칭이 붙을 때 여기서 갈린다.
///
/// ## 아우라를 텍스트 뒤에 깔지 않는다
///
/// 정본 와이어프레임은 히어로 가운데에 아우라 글로우를 두지만,
/// `docs/implementation-notes.md` §3-4가 **글로우를 텍스트 뒤에 깔지 말라**고 못 박았다.
/// 러닝 색은 채도가 높아 그 위 글자가 대비 기준을 통과하지 못한다.
/// 그래서 우측 상단 밖으로 흘려보내고, 글자는 깨끗한 배경 위에 둔다.
///
/// ## 아직 임시인 값 둘
///
/// - **색**: 시그니처 컬러를 저장하는 곳이 없다. 이 앱이 홈에서 권하는 행동이
///   함께 달리기라 `RunHue.company`(동행·코럴)를 자리표시자로 쓴다.
/// - **생기**: 기록이 하나도 없으므로 [AuraOrb.vitality]를 낮췄다.
///   임의로 흐리게 만든 게 아니라 "활동이 없으면 빛이 바랜다"는 위젯의 규칙대로다.
///   러닝 기록이 쌓이면 이 값이 올라간다.
class HomeHero extends StatelessWidget {
  const HomeHero({
    required this.greeting,
    required this.onMatch,
    required this.onSolo,
    super.key,
  });

  /// 시간대 인사. 어느 문구인지는 부르는 쪽이 정한다.
  final String greeting;

  /// 매칭 시작. 지금은 준비 중 안내로 이어진다.
  final VoidCallback onMatch;

  /// 1인 러닝 시작.
  final VoidCallback onSolo;

  /// 기록이 없을 때의 아우라 밝기.
  static const _restingVitality = 0.5;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return ClipRRect(
      // 아우라가 히어로 밖으로 새어 아래 카드를 덮지 않게 자른다.
      borderRadius: AppRadius.xl,
      child: ConstrainedBox(
        // 정본이 정한 히어로 최소 높이.
        constraints: const BoxConstraints(minHeight: 236),
        child: Stack(
          children: [
            Positioned(
              top: -AppSpacing.space10,
              right: -AppSpacing.space10,
              child: AuraOrb(
                colors: [RunPalette.shadesOf(RunHue.company)[1]],
                size: 240,
                vitality: _restingVitality,
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(AppSpacing.space6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    greeting,
                    style: AppTypography.body.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space1),

                  Text(
                    AppStrings.homeHeroPrompt,
                    style: AppTypography.h1.copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.space6),

                  AppButton(label: AppStrings.homeMatchCta, onPressed: onMatch),
                  const SizedBox(height: AppSpacing.space2),

                  AppButton(
                    label: AppStrings.homeSoloCta,
                    onPressed: onSolo,
                    variant: AppButtonVariant.secondary,
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
