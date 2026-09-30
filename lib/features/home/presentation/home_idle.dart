import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';

/// 기본 — 아직 매칭 중이 아니다. 시안 `158:2848`.
///
/// 시안은 가운데 정렬이고 **CTA가 카드 바닥에 붙는다.** 가운데 글이 위에,
/// 버튼이 아래에 떨어져 있어야 빛이 지나갈 자리가 생긴다.
class HomeIdle extends StatelessWidget {
  const HomeIdle({
    required this.onMatch,
    required this.now,
    this.name,
    this.cooldownUntil,
    super.key,
  });

  /// 부를 이름. 없으면 그 줄을 뺀다.
  final String? name;
  final VoidCallback onMatch;

  /// 지금. **부르는 쪽이 갈아끼운다** — 제한이 풀리는 순간 버튼이 열려야 한다.
  final DateTime now;

  /// 매칭 신청이 풀리는 시각. 지났거나 없으면 제한이 없다.
  ///
  /// ⚠️ **솔로는 막지 않는다.** 제재는 매칭 신청에만 걸린다 — 혼자 달리는 것은
  /// 누구를 기다리게 하지도, 방을 비우지도 않는다. 솔로 버튼은 이제 카드 밖
  /// 하단 칸(`ActionTileV2`)이라 여기서 잠글 것도 없다.
  final DateTime? cooldownUntil;

  /// 시안 `158:2860`의 높이.
  static const _height = 452.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final until = cooldownUntil;
    final locked = until != null && until.isAfter(now);
    final called = name;

    return ClipRRect(
      borderRadius: AppRadius.card,
      child: SizedBox(
        // ⚠️ **높이를 고정한다.**
        //
        // 시안이 452 이기도 하지만, 그보다 **`Spacer`가 무한한 높이 안에서는
        // 못 산다.** 이 위젯은 `ListView` 안에 들어가 높이가 위에서 내려오지
        // 않는다 — 안 걸면 제목과 버튼을 카드 양 끝으로 밀 수가 없고
        // 레이아웃이 그 자리에서 죽는다.
        height: _height,
        child: Stack(
          children: [
            const Positioned.fill(child: _IdleLight()),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.space6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.space3),

                  Text(
                    // ⚠️ 이름이 없으면 **줄째 뺀다.** `님`만 남으면 이름을 잃은 것처럼
                    // 보이고, 빈 줄을 두면 제목이 아래로 밀린다.
                    called == null || called.isEmpty
                        ? AppStrings.homeHeroPrompt
                        : '${AppStrings.homeHeroName(called)}\n${AppStrings.homeHeroPrompt}',
                    textAlign: TextAlign.center,
                    style: AppTypographyV2.heading03.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space3),

                  Text(
                    AppStrings.homeHeroSubtitle,
                    textAlign: TextAlign.center,
                    style: AppTypographyV2.body07.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),

                  // 빛이 지나갈 자리. 시안은 제목과 버튼이 카드 양 끝에 붙어 있다.
                  const Spacer(),

                  // ⚠️ **눌러 보고 409를 받게 두지 않는다.** 서버가 이미 언제까지인지
                  // 말해 줬는데 그것을 숨기면, 사용자는 눌러야만 이유를 알 수 있다.
                  AppButtonV2(
                    label: AppStrings.homeMatchCta,
                    onPressed: locked ? null : onMatch,
                  ),
                  if (locked) ...[
                    const SizedBox(height: AppSpacing.space2),
                    Text(
                      AppStrings.matchFailedCooldown(until),
                      textAlign: TextAlign.center,
                      style: AppTypographyV2.body20.copyWith(
                        color: colors.textTertiary,
                      ),
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
}

/// 기본 상태의 배경 — 아래에서 올라오는 파란 빛.
///
/// ⚠️ **그리지 않고 이미지를 쓴다.** 시안(`158:2861`)이 blur 를 먹인 그러데이션
/// 일곱 겹을 `mix-blend-plus-lighter`로 겹쳐 만든 것이라, Flutter 로 옮기면
/// 겹치는 규칙이 달라 다른 색이 나온다.
class _IdleLight extends StatelessWidget {
  const _IdleLight();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/home_hero_light.webp',
      // 카드 폭이 기기마다 다르다. 빛은 가장자리가 없어 늘려도 티가 안 난다.
      fit: BoxFit.cover,
      alignment: Alignment.bottomCenter,
      // 사람이 읽을 것이 아니라 분위기다. 스크린리더가 읽을 것이 없다.
      excludeFromSemantics: true,
    );
  }
}
