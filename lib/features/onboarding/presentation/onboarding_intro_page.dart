import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_motion.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_sizes.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/core/widgets/v2/page_indicator.dart';

/// 온보딩 소개 (S02) — 카드 4장. 시안 `158:2699`.
///
/// 네 장이 **러닝 하루**를 따라간다.
/// 함께 달린다 → 곁에 있으면 콤보가 쌓인다 → 끝나고 구간을 돌아본다 →
/// 그날이 사진과 음악으로 남는다.
///
/// 그림은 앱 화면의 한 부분만 잘라 쓴다. 폰 테두리를 그리지 않아 iOS와
/// 안드로이드가 같은 그림을 본다 — 다른 것은 2장의 워치뿐이다.
///
/// ## ⚠️ 4장은 아직 없는 기능이다
///
/// 기록카드도 AI 음악도 화면과 API가 없다. 온보딩은 설치 직후 첫 화면이라
/// 없는 것을 있는 것처럼 말하면 바로 들통난다 — 그래서 그 장에만
/// `런칭 준비 중` 배지를 단다.
///
/// ## 세로 리듬은 네 장이 같다
///
/// 그림과 제목이 늘 같은 높이에 선다. 4장의 배지는 줄을 따로 차지하지 않고
/// 그림 왼쪽 위에 얹는다. 넘길 때 그림도 글자도 위아래로 튀지 않는다.
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

  static const _cards = [
    _IntroCard(
      title: AppStrings.onboardingCard1Title,
      body: AppStrings.onboardingCard1Body,
      art: _Art.home,
    ),
    _IntroCard(
      title: AppStrings.onboardingCard2Title,
      body: AppStrings.onboardingCard2Body,
      art: _Art.combo,
    ),
    _IntroCard(
      title: AppStrings.onboardingCard3Title,
      body: AppStrings.onboardingCard3Body,
      art: _Art.compare,
    ),
    _IntroCard(
      title: AppStrings.onboardingCard4Title,
      body: AppStrings.onboardingCard4Body,
      art: _Art.record,
      comingSoon: true,
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
    final colors = context.appColorsV2;

    return Scaffold(
      // 앱 테마는 아직 옛 세대라 scaffold 배경이 푸른 회색(#0B0E14)이다.
      // 옮긴 화면은 자기 배경을 직접 깐다 — 전역 테마를 바꾸는 것은
      // 마지막 화면이 넘어온 뒤의 일이다.
      backgroundColor: colors.bgBase,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = math.max(
              0.0,
              constraints.maxWidth - AppSpacing.space6 * 2,
            );
            double textHeight(String text, TextStyle style) {
              final painter = TextPainter(
                text: TextSpan(text: text, style: style),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout(maxWidth: width);
              final height = painter.height;
              painter.dispose();
              return height;
            }

            // 실제 가용 공간과 글자 배율로 계산한다. 기기별 높이 분기는 없다.
            // 모든 장에 가장 큰 글자 영역을 예약해 페이지 이동 시 높이를 유지한다.
            final titleHeight = _cards
                .map(
                  (card) => textHeight(card.title, AppTypographyV2.heading04),
                )
                .reduce(math.max);
            final bodyHeight = _cards
                .map((card) => textHeight(card.body, AppTypographyV2.body06))
                .reduce(math.max);
            return Column(
              children: [
                const SizedBox(height: AppSpacing.space4),

                // 이탈 경로는 최우선이다. 카드를 다 보지 않아도 나갈 수 있어야 한다.
                //
                // ⚠️ 시안의 좌측 뒤로가기는 넣지 않는다. 온보딩은 스플래시 다음
                // 첫 화면이라 뒤로 갈 곳이 없다.
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.space3,
                    ),
                    child: TextButton(
                      onPressed: _finish,
                      style: TextButton.styleFrom(
                        // 글자는 14px이지만 히트 박스는 44px를 지킨다.
                        minimumSize: const Size(
                          AppSizes.touchDefault,
                          AppSizes.touchDefault,
                        ),
                        foregroundColor: colors.textSecondary,
                      ),
                      child: Text(
                        AppStrings.onboardingSkip,
                        style: AppTypographyV2.body11,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.space4),

                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _cards.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) => _IntroCardView(
                      card: _cards[i],
                      titleHeight: titleHeight,
                      bodyHeight: bodyHeight,
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.space5),
                PageIndicatorV2(count: _cards.length, currentIndex: _index),
                const SizedBox(height: AppSpacing.space7),

                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space6,
                  ),
                  child: AppButtonV2(
                    // 마지막 장에서 라벨이 바뀐다 — 다음이 없다는 신호다.
                    label: _isLast
                        ? AppStrings.onboardingStart
                        : AppStrings.onboardingNext,
                    onPressed: _onNext,
                  ),
                ),

                const SizedBox(height: AppSpacing.space7),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 장마다 다른 그림.
enum _Art {
  /// 홈의 매칭 카드(`HomeIdle`)를 찍은 것.
  home,

  /// 파티원 비교 화면에서 콤보 임팩트가 터지는 **실제 녹화**에 워치가 걸친다.
  combo,

  /// 결과 화면의 파티원 비교 카드와 구간별 페이스 그래프를 찍은 것.
  compare,

  /// 기록카드와 곡 카드. 아직 없는 화면이라 여기서 그린다.
  record,
}

/// 카드 한 장의 내용.
class _IntroCard {
  const _IntroCard({
    required this.title,
    required this.body,
    required this.art,
    this.comingSoon = false,
  });

  final String title;
  final String body;
  final _Art art;

  /// 아직 만들지 않은 기능을 소개하는 장인가.
  final bool comingSoon;
}

class _IntroCardView extends StatelessWidget {
  const _IntroCardView({
    required this.card,
    required this.titleHeight,
    required this.bodyHeight,
  });

  final _IntroCard card;
  final double titleHeight;
  final double bodyHeight;

  /// 그림과 제목 사이. 시안 실측(539 → 575)이고 토큰에 없는 값이다.
  static const artToTitle = 36.0;

  /// 제목과 본문 사이. 시안 `158:2705`의 gap 14.
  static const titleToBody = 14.0;

  /// 그림 칸의 가로세로 비. **네 장이 같은 칸을 쓴다** — 그림마다 제 비율로
  /// 두면 장을 넘길 때 그림 크기가 들쑥날쑥하다. 그림 파일도 이 비율로 자른다.
  static const artAspect = 336 / 360;

  // 기본 그림 칸보다 크게 확대하지 않는다. 좁거나 짧은 화면에서는
  // 목표 크기의 80%까지만 줄이고, 그 아래는 문구를 스크롤로 제공한다.
  static const _maxArtHeight = 360.0;
  static const _minArtScale = 0.8;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(
          0.0,
          constraints.maxWidth - AppSpacing.space6 * 2,
        );
        final targetArtHeight = math.min(width / artAspect, _maxArtHeight);
        final minArtHeight = targetArtHeight * _minArtScale;
        const minArtToTitle = AppSpacing.space6;
        final preferredHeight =
            targetArtHeight +
            artToTitle +
            titleHeight +
            titleToBody +
            bodyHeight;
        final reducibleHeight =
            targetArtHeight - minArtHeight + artToTitle - minArtToTitle;
        final compression =
            ((preferredHeight - constraints.maxHeight) / reducibleHeight).clamp(
              0.0,
              1.0,
            );
        final artHeight =
            targetArtHeight - (targetArtHeight - minArtHeight) * compression;
        final artGap = artToTitle - (artToTitle - minArtToTitle) * compression;

        // 하단 조작 영역은 그대로 두고 중앙 영역 안에서만 크기를 조절한다.
        // 여유는 위아래로 나누고, 최소 크기로도 부족할 때만 스크롤한다.
        return SingleChildScrollView(
          key: PageStorageKey(card.art),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space6),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: artHeight * artAspect,
                  height: artHeight,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        // 그림 속 예시 UI는 PNG와 같은 배율로 유지한다.
                        // 실제 제목·설명·버튼은 시스템 글자 배율을 따른다.
                        child: MediaQuery.withNoTextScaling(
                          child: _ArtView(art: card.art),
                        ),
                      ),
                      if (card.comingSoon)
                        const Positioned(
                          top: 0,
                          left: 0,
                          child: _ComingSoonBadge(),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: artGap),
                SizedBox(
                  height: titleHeight,
                  child: Text(
                    card.title,
                    textAlign: TextAlign.center,
                    style: AppTypographyV2.heading04.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: titleToBody),
                SizedBox(
                  height: bodyHeight,
                  child: Text(
                    card.body,
                    textAlign: TextAlign.center,
                    style: AppTypographyV2.body06.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// `● 런칭 준비 중` — 아직 없는 기능임을 밝히는 배지.
class _ComingSoonBadge extends StatelessWidget {
  const _ComingSoonBadge();

  static const _dotSize = 5.0;

  /// 점과 글자 사이. 토큰에 6이 없다.
  static const _dotGap = 6.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primaryMuted,
        borderRadius: AppRadius.full,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space3,
          vertical: AppSpacing.space1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 점은 장식이다. 글자가 이미 상태를 말하므로 색만 남아도 잃는 것이 없다.
            Container(
              width: _dotSize,
              height: _dotSize,
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: _dotGap),
            Text(
              AppStrings.onboardingComingSoon,
              style: AppTypographyV2.body21.copyWith(
                color: colors.primaryHover,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtView extends StatelessWidget {
  const _ArtView({required this.art});

  final _Art art;

  @override
  Widget build(BuildContext context) => switch (art) {
    _Art.home => Image.asset(
      'assets/images/onboarding_home.webp',
      fit: BoxFit.contain,
    ),
    _Art.combo => const _ComboArt(),
    _Art.compare => Image.asset(
      'assets/images/onboarding_compare.webp',
      fit: BoxFit.contain,
    ),
    _Art.record => const _RecordArt(),
  };
}

/// 2장의 그림 — 파티원 비교 녹화의 오른쪽 아래에 워치가 걸친다.
///
/// 워치는 같은 콤보 순간(`11 COMBO`)을 띄워, 손목에서도 보인다는 것을 글 없이
/// 알린다. 워치 화면은 두 워치 앱의 콤보 순간 시안이다.
///
/// ⚠️ **세 그림이 같은 시간표로 움직인다** — 시작 전 0.4초, 0.04초 간격 38장,
/// 끝 0.7초. 셋 중 하나만 다시 만들면 폰과 워치의 콤보 순간이 어긋난다.
///
/// ⚠️ **워치는 플랫폼에 맞는 것만 보인다.** 애플워치는 아이폰하고만 쓰이고,
/// iOS 앱에 안드로이드 기기를 보이면 심사(2.3.10)에 걸린다. 두 그림은 몸체
/// 스타일이 같고 화면 모양만 다르다.
class _ComboArt extends StatelessWidget {
  const _ComboArt();

  /// 워치 그림의 가로세로 비. 두 워치 그림이 같은 캔버스다.
  static const _watchAspect = 540 / 690;

  /// 그림 칸 폭 대비 워치 폭.
  static const _watchShare = 0.42;

  /// 워치가 그림 칸 밖으로 나가도 되는 너비 — 오른쪽 화면 여백 안쪽이다.
  static const _spillX = AppSpacing.space4;

  /// 워치가 칸 아래로 내려가는 몫(워치 높이 대비). 칸 안에만 두면 상대
  /// 카드의 숫자를 많이 가린다. 그림과 제목 사이(36) 안에서만 내려가야
  /// 제목과 겹치지 않는다 — 줄 끝이 칸 아래로 약 20 나온다.
  static const _belowShare = 0.15;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    // 녹화는 그림 칸과 같은 비율로 찍어 칸을 꽉 채운다 — 다른 장 그림과 크기가
    // 같다. 워치는 오른쪽 아래 모서리에 걸친다.
    builder: (context, constraints) => Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          // 애니메이션 WebP다. `Image`가 스스로 돌린다 — 컨트롤러가 필요 없다.
          child: ClipRRect(
            borderRadius: AppRadius.xl,
            child: Image.asset(
              'assets/images/onboarding_combo.webp',
              fit: BoxFit.cover,
            ),
          ),
        ),
        Positioned(
          right: -_spillX,
          bottom:
              -constraints.maxWidth * _watchShare / _watchAspect * _belowShare,
          width: constraints.maxWidth * _watchShare,
          child: Image.asset(
            defaultTargetPlatform == TargetPlatform.iOS
                ? 'assets/images/onboarding_watch_apple.webp'
                : 'assets/images/onboarding_watch_galaxy.webp',
          ),
        ),
      ],
    ),
  );
}

/// 4장의 그림 — 기록카드 한 장 위에 곡 카드가 걸친다.
///
/// 기록카드 화면이 아직 없어 **여기서 그린다.** 화면이 생기면 그 화면의
/// 부품으로 갈아끼운다.
class _RecordArt extends StatelessWidget {
  const _RecordArt();

  /// 시안 실측. 카드 272 · 사진 186 · 기울기 3°.
  static const _cardWidth = 272.0;
  static const _photoHeight = 186.0;
  static const _tilt = -3 * math.pi / 180;
  static const _glowSize = 300.0;

  /// 그림이 설계된 폭. 시안의 본문 폭(412 - 24×2)이다.
  static const _artWidth = 364.0;

  /// 곡 카드가 기록카드를 파고드는 깊이.
  ///
  /// ⚠️ 둘을 위아래 끝에 붙여 두면 **간격이 화면 높이를 따라간다** — 큰 기기에서는
  /// 벌어져 따로 놀고 작은 기기에서는 포개진다. 겹치는 깊이를 고정해 어느
  /// 기기에서나 같은 관계로 보이게 한다.
  static const _overlap = 18.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    // ⚠️ 두 카드는 제 높이대로 쌓이고, 남는 세로가 모자라면 **통째로 줄어든다.**
    // 안에서 늘였다 줄였다 하면 겹치는 깊이와 기울기가 기기마다 달라진다 —
    // 비율을 지킨 채 작아지는 편이 낫다. 넘쳐서 노란 줄이 뜨는 일도 없다.
    // 곡 카드가 차지하는 높이에서 겹치는 부분을 빼야 카드 하단이 그림 칸의
    // 하단에 닿는다. 그리는 위치만 옮기면 아래에 빈 공간이 남는다.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: _artWidth,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: _glowSize,
              height: _glowSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    colors.primary.withValues(alpha: 0.30),
                    colors.primary.withValues(alpha: 0.10),
                    colors.primary.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.46, 0.70],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.only(
                bottom: _SongCard._height - _overlap,
              ),
              child: Align(
                heightFactor: 1,
                child: Transform.rotate(
                  angle: _tilt,
                  child: _RecordCard(
                    width: _cardWidth,
                    photoHeight: _photoHeight,
                  ),
                ),
              ),
            ),
            const Positioned(left: 0, right: 0, bottom: 0, child: _SongCard()),
          ],
        ),
      ),
    );
  }
}

/// 사진 + 수치 + 그날의 한 줄.
class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.width, required this.photoHeight});

  final double width;
  final double photoHeight;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: AppRadius.xl,
        border: Border.all(color: colors.bgElevated),
      ),
      child: ClipRRect(
        borderRadius: AppRadius.xl,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/onboarding_record.jpg',
              width: width,
              height: photoHeight,
              fit: BoxFit.cover,
            ),
            Padding(
              // ⚠️ 아래만 넉넉하다. 곡 카드가 이 카드를 파고들기 때문에,
              // 여백이 같으면 그 밑에서 회고 한 줄이 가려진다.
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space4,
                AppSpacing.space4,
                AppSpacing.space4,
                AppSpacing.space7,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        AppStrings.onboardingSampleDistance,
                        style: AppTypographyV2.heading03.copyWith(
                          color: colors.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.space2),
                      Text(
                        AppStrings.onboardingSampleUnit,
                        style: AppTypographyV2.body10.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.space2),
                      Text(
                        AppStrings.onboardingSampleDuration,
                        style: AppTypographyV2.body11.copyWith(
                          color: colors.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.space2),
                  Text(
                    AppStrings.onboardingSampleNote,
                    style: AppTypographyV2.body12.copyWith(
                      color: colors.textPrimary,
                    ),
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

/// 파형 + 제목 + 재생 — 러닝 데이터로 만들어진 곡.
class _SongCard extends StatelessWidget {
  const _SongCard();

  /// 제목(21)과 메타 정보(18), 상하 여백과 테두리가 들어가는 그림 속 높이.
  static const _height = 66.0;
  static const _playSize = 34.0;

  /// 파형 막대의 상대 높이. 콤보 구간이 도드라지게 가운데가 높다.
  static const _bars = <double>[
    0.30,
    0.58,
    0.42,
    0.76,
    1.00,
    0.64,
    0.88,
    0.46,
    0.70,
    0.34,
  ];

  static const _waveHeight = 34.0;
  static const _barWidth = 3.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Container(
      height: _height,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space4,
        vertical: AppSpacing.space3,
      ),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: AppRadius.card,
        border: Border.all(color: colors.primaryMuted),
      ),
      child: Row(
        children: [
          SizedBox(
            height: _waveHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final bar in _bars) ...[
                  Container(
                    width: _barWidth,
                    height: _waveHeight * bar,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: AppRadius.xs,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space0),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.space3),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.onboardingSampleSong,
                  style: AppTypographyV2.body10.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  AppStrings.onboardingSampleSongMeta,
                  style: AppTypographyV2.body20.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.space3),

          // 그림 속 재생 버튼이다. 들을 곡이 아직 없으므로 누를 수 없다 —
          // 눌리는 것처럼 보이면 안 되니 [IconButton]을 쓰지 않는다.
          //
          // ⚠️ 삼각형을 직접 그린다. 디자인 아이콘 33개에 재생이 없고,
          // Material 아이콘을 섞으면 선 굵기와 모서리가 달라 눈에 띈다.
          Container(
            width: _playSize,
            height: _playSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primary,
              shape: BoxShape.circle,
            ),
            child: CustomPaint(
              size: const Size.square(AppSpacing.space4),
              painter: _PlayTrianglePainter(color: colors.textOnPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// 오른쪽을 가리키는 둥근 삼각형.
///
/// 디자인 아이콘 33개에 재생이 없어 직접 그린다. Material 아이콘을 섞으면
/// 선 굵기와 모서리가 달라 한 화면 안에서 튄다 (`CLAUDE.md`).
class _PlayTrianglePainter extends CustomPainter {
  const _PlayTrianglePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        // 꼭짓점을 둥글려 재생 버튼답게 만든다. 날카로우면 경고 표시로 읽힌다.
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_PlayTrianglePainter old) => old.color != color;
}
