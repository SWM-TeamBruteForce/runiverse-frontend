import 'package:flutter/widgets.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';

/// 히어로 배경 빛이 나오는 쪽.
enum HomeHeroLight {
  /// 아래에서 올라온다 — 기본 카드.
  bottom,

  /// 위에서 내려온다 — 확정·혼자 남은 방·시작됨 카드.
  top,

  /// 동심원 한가운데 — 모집 중·상태 대기 카드.
  center,
}

/// 히어로 배경 이미지 위에 까는 덮개. 상태 카드들이 함께 쓴다.
///
/// ## ⚠️ 빛 색은 그대로 두고 세기만 누른다
///
/// 시안 빛을 그대로 두면 쨍하다. 이미지 전체를 고르게 덮으면 빛이 어디서
/// 나오는지가 흐려져서, **나오는 쪽은 옅게([_weak]) 반대쪽은 짙게([_strong])**
/// 덮는다. 25%→55%는 살짝 어두웠다.
///
/// 색은 [AppColorsV2.bgBase]다 — 카드 둘레 화면 바탕과 같은 색으로 눌러야
/// 빛이 바탕으로 스며드는 것처럼 보인다.
class HomeHeroShade extends StatelessWidget {
  const HomeHeroShade({required this.light, super.key});

  final HomeHeroLight light;

  static const _weak = .15;
  static const _strong = .45;

  /// 모집 중 카드의 동심원 중심. 340 카드 한가운데(170)에서 가운데 원을
  /// 24 내린 자리(194)다 — `HomeWaiting`이 원과 배경을 같이 내린다.
  static const _ringCenter = Alignment(0, 24 / 170);

  @override
  Widget build(BuildContext context) {
    final base = context.appColorsV2.bgBase;
    final weak = base.withValues(alpha: _weak);
    final strong = base.withValues(alpha: _strong);

    final gradient = switch (light) {
      HomeHeroLight.bottom => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [strong, weak],
      ),
      HomeHeroLight.top => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [weak, strong],
      ),
      HomeHeroLight.center => RadialGradient(
        center: _ringCenter,
        radius: .8,
        colors: [weak, strong],
        stops: const [.4, 1],
      ),
    };

    return DecoratedBox(decoration: BoxDecoration(gradient: gradient));
  }
}
