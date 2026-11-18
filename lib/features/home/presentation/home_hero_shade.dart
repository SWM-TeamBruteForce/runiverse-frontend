import 'package:flutter/widgets.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';

/// 히어로 배경 빛이 나오는 쪽.
enum HomeHeroLight {
  /// 아래에서 올라온다 — 기본 카드.
  bottom,

  /// 위에서 내려온다 — 확정·혼자 남은 방·시작됨 카드.
  top,

  /// 동심원 한가운데([HomeHeroShade.ringCenter]) — 모집 중·상태 대기 카드.
  center,
}

/// 히어로 배경(그림 또는 동심원) 위에 까는 덮개. 상태 카드들이 함께 쓴다.
///
/// ## ⚠️ 빛 색은 그대로 두고 세기만 누른다
///
/// 시안 빛을 그대로 두면 쨍하다. 이미지 전체를 고르게 덮으면 빛이 어디서
/// 나오는지가 흐려져서, **나오는 쪽은 옅게([_weak]) 반대쪽은 짙게([_strong])**
/// 덮는다. 바탕을 회색으로 받친 뒤로는 그것만으로 빛이 덜 쨍해져서, 그 전에
/// 쓰던 15%→45%는 칙칙했다.
///
/// 색은 [AppColorsV2.bgSurface]다 — 카드 바탕과 같은 색으로 눌러야 바탕은
/// 그대로 두고 빛만 눌린다. 화면 바탕([AppColorsV2.bgBase])으로 누르면 카드
/// 위쪽이 화면에 녹아 카드가 어디서 시작하는지 안 보인다. 그래서 빛 그림도
/// 어두운 곳을 같은 색으로 받친다.
class HomeHeroShade extends StatelessWidget {
  const HomeHeroShade({
    required this.light,
    this.ringCenter = Alignment.center,
    super.key,
  });

  final HomeHeroLight light;

  /// [HomeHeroLight.center]일 때 빛이 나오는 동심원 중심. 동심원 배경을 까는
  /// 쪽(`HomeWaitingRing`)이 자기 배치에서 구해 넘긴다.
  final Alignment ringCenter;

  static const _weak = .0;
  static const _strong = .25;

  @override
  Widget build(BuildContext context) {
    final base = context.appColorsV2.bgSurface;
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
        center: ringCenter,
        radius: .8,
        colors: [weak, strong],
        stops: const [.4, 1],
      ),
    };

    return DecoratedBox(decoration: BoxDecoration(gradient: gradient));
  }
}
