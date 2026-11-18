import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/features/home/presentation/home_hero_shade.dart';
import 'package:runiverse/features/home/presentation/home_waiting.dart';

/// 서버가 이미 시작한 러닝. **들어갈 문 하나만 둔다.**
///
/// 카운트다운도 파티원 줄도 그리지 않는다 — 기다릴 것이 없고, 이 화면에서
/// 머무는 시간이 그대로 기록에서 빠진다.
///
/// 배경은 바로 앞 단계인 확정 카드의 위 빛이다.
class HomeStarted extends StatelessWidget {
  const HomeStarted({required this.onEnter, super.key});

  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context) {
    return _HeroCard(
      background: [
        Image(
          image: const AssetImage('assets/images/home_confirmed_bg.webp'),
          fit: BoxFit.cover,
          // 어두운 곳을 카드 바탕색으로 받친다(`HomeHeroShade` 참고).
          color: context.appColorsV2.bgSurface,
          colorBlendMode: BlendMode.screen,
          // 사람이 읽을 것이 아니라 분위기다.
          excludeFromSemantics: true,
        ),
        const HomeHeroShade(light: HomeHeroLight.top),
      ],
      title: AppStrings.homeRunStarted,
      body: AppStrings.homeRunStartedHint,
      button: AppButtonV2(
        label: AppStrings.homeRunToSession,
        onPressed: onEnter,
      ),
    );
  }
}

/// 매칭 중인데 방 정보가 아직 없다.
///
/// 짧게 지나가는 구간이지만 **비워 둘 수 없다.** 여기가 비면 매칭을 신청한
/// 사람이 기본 히어로를 보고 다시 신청하려 든다.
///
/// 배경은 모집 중 카드의 동심원을 같은 자리에 깐다([HomeWaitingRing]) — 방
/// 정보가 오면 바로 모집 중 카드로 바뀌는데, 그때 동심원이 움직이지 않는다.
class HomePending extends StatelessWidget {
  const HomePending({required this.onCancel, super.key});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return _HeroCard(
      background: const [HomeWaitingRing()],
      title: AppStrings.homeMatchWaiting,
      body: AppStrings.homeMatchPending,
      // 방 정보가 없어도 나갈 수는 있다 — 취소는 방 번호를 쓰지 않는다.
      button: AppButtonV2(
        label: AppStrings.homeMatchCancel,
        // 시안 `158:3433`은 테두리만 있는 버튼(`secondary`)인데, 배경이 비쳐
        // 밝은 빛 위에서 글씨가 묻힌다. 같은 배경 위의 모집 중 `로비로
        // 가기`와 같은 옅은 면으로 둔다.
        variant: AppButtonV2Variant.tonal,
        onPressed: onCancel,
      ),
    );
  }
}

/// 다른 상태 카드와 같은 틀 — 340 높이, 위 24에 제목과 설명, 바닥에 버튼.
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.background,
    required this.title,
    required this.body,
    required this.button,
  });

  /// 카드를 꽉 채워 차례로 까는 배경과 덮개.
  final List<Widget> background;
  final String title;
  final String body;
  final Widget button;

  /// 상태 카드 모두 같은 높이다(시안 452에서 줄였다).
  static const _height = 340.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return ClipRRect(
      borderRadius: AppRadius.card,
      child: SizedBox(
        height: _height,
        child: Stack(
          children: [
            for (final layer in background) Positioned.fill(child: layer),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 다른 상태 카드와 같이 제목을 위 24(안쪽 여백 16 + 8)에 둔다.
                  const SizedBox(height: AppSpacing.space2),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: AppTypographyV2.heading03.copyWith(
                      color: colors.textStrong,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space3),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: AppTypographyV2.body07.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  button,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
