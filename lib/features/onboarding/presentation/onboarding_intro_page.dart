import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_motion.dart';
import 'package:runiverse/core/theme/tokens/app_sizes.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/theme/tokens/run_palette.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/core/widgets/color/run_color_orb.dart';
import 'package:runiverse/core/widgets/page_indicator.dart';

/// 온보딩 소개 (S02) — 카드 3장.
///
/// 카드마다 다른 러닝 색을 쓴다. 이 화면의 목적이 기능 설명이 아니라
/// **"이 앱은 색이 남는 앱"이라는 인상**을 만드는 것이라, 색이 바뀌는 것 자체가 메시지다.
///
/// 상태는 [PageController]와 현재 인덱스뿐이라 provider를 두지 않았다.
/// 화면 밖에서 이 값을 알 필요가 없고, 화면을 떠나면 버려도 되는 상태다.
class OnboardingIntroPage extends StatefulWidget {
  const OnboardingIntroPage({super.key});

  @override
  State<OnboardingIntroPage> createState() => _OnboardingIntroPageState();
}

class _OnboardingIntroPageState extends State<OnboardingIntroPage> {
  final _controller = PageController();
  int _index = 0;

  /// 카드 순서는 "무엇을 하는가 → 무엇을 얻는가 → 어떻게 남는가"다.
  ///
  /// ⚠️ hue 선택은 Figma가 카드 1장만 담고 있어 나머지를 내가 골랐다.
  /// 1번은 Figma의 블루를 따랐고, 2·3번은 서로 대비되게 배치했다. 디자인 확인이 필요하다.
  static const _cards = [
    _IntroCard(
      title: AppStrings.onboardingCard1Title,
      body: AppStrings.onboardingCard1Body,
      hue: RunHue.endurance,
    ),
    _IntroCard(
      title: AppStrings.onboardingCard2Title,
      body: AppStrings.onboardingCard2Body,
      hue: RunHue.interval,
    ),
    _IntroCard(
      title: AppStrings.onboardingCard3Title,
      body: AppStrings.onboardingCard3Body,
      hue: RunHue.consistency,
    ),
  ];

  bool get _isLast => _index == _cards.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onNext() {
    if (_isLast) {
      _finish();
      return;
    }
    _controller.nextPage(duration: AppMotion.slow, curve: AppMotion.easeSlow);
  }

  void _finish() {
    // 소개가 끝나면 로그인(S02.5)이다. 약관(S03)은 **가입하는 사람만** 지나간다 —
    // 이미 계정이 있는 사람에게 약관을 다시 받으면 로그인 길이 두 배로 길어진다.
    //
    // go라 소개로 되돌아가지 않는다. 그래서 로그인 화면에는 뒤로가기가 없다.
    context.go(AppRoutes.signIn);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 이탈 경로는 최우선이다. 카드를 다 보지 않아도 나갈 수 있어야 한다.
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space2,
                ),
                child: TextButton(
                  onPressed: _finish,
                  style: TextButton.styleFrom(
                    // 글자는 13px이지만 히트 박스는 44px를 지킨다.
                    minimumSize: const Size(
                      AppSizes.touchDefault,
                      AppSizes.touchDefault,
                    ),
                    foregroundColor: colors.textTertiary,
                  ),
                  child: Text(
                    AppStrings.onboardingSkip,
                    style: AppTypography.caption,
                  ),
                ),
              ),
            ),

            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _cards.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _IntroCardView(card: _cards[i]),
              ),
            ),

            PageIndicator(count: _cards.length, currentIndex: _index),
            const SizedBox(height: AppSpacing.space6),

            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space4,
                0,
                AppSpacing.space4,
                AppSpacing.space4,
              ),
              child: AppButton(
                // 마지막 장에서 라벨이 바뀐다 — 다음이 없다는 신호다.
                label: _isLast
                    ? AppStrings.onboardingStart
                    : AppStrings.onboardingNext,
                onPressed: _onNext,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 카드 한 장의 내용.
class _IntroCard {
  const _IntroCard({
    required this.title,
    required this.body,
    required this.hue,
  });

  final String title;
  final String body;

  /// 오브에 쓸 러닝 색.
  final RunHue hue;
}

class _IntroCardView extends StatelessWidget {
  const _IntroCardView({required this.card});

  final _IntroCard card;

  /// 오브 지름. 412 캔버스 기준 Figma 실측값이다.
  static const _orbSize = 180.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 아우라가 아니라 또렷한 오브다. 여기서는 "이게 그 색"이라고 짚어야 해서
          // 경계가 살아 있어야 한다. 섞이는 연출은 스플래시(S01)가 맡는다.
          RunColorOrb(color: RunPalette.color(card.hue, 2), size: _orbSize),
          const SizedBox(height: AppSpacing.space6),

          Text(
            card.title,
            textAlign: TextAlign.center,
            style: AppTypography.h1.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.space4),

          Text(
            card.body,
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
