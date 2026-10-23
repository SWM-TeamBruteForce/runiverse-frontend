import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// 러닝 색이 번지는 아우라. 스플래시 배경(S01)과 온보딩 오브(S02)가 같이 쓴다.
///
/// **색을 스스로 고르지 않는다.** 어떤 색을 넣을지는 부르는 쪽이 정하고,
/// 이 위젯은 받은 색을 그리기만 한다. 그래야 `features/color/`의 도메인 로직과
/// 표현이 분리된다(`docs/implementation-notes.md` §3-1).
///
/// ## 색 개수에 따라 달라진다
///
/// - 1개 → 가운데서 바깥으로 잦아드는 단색 번짐
/// - 여러 개 → 원 둘레에 고르게 배치해 서로 겹치며 섞인다 (블렌드 예고)
///
/// ## 텍스트를 얹을 때
///
/// ⚠️ **아우라 위에 텍스트를 올리면 스크림을 사이에 둔다**(디자인 시스템 §1-4).
/// 러닝 색은 채도가 높아 그 위 텍스트가 대비 기준을 통과하지 못한다.
/// 이 위젯은 스크림을 넣지 않는다 — 배경으로도 쓰이기 때문이다. 얹는 쪽이 책임진다.
///
/// ## 성능
///
/// 블러가 들어가서 매 프레임 다시 그리면 비싸다. **애니메이션 대상으로 삼지 않는다.**
/// 리빌 연출이 필요하면 이 위젯을 [Transform.scale]이나 [Opacity]로 감싼다.
class AuraOrb extends StatelessWidget {
  const AuraOrb({
    required this.colors,
    required this.size,
    this.vitality = 1,
    super.key,
  }) : assert(colors.length > 0, '색이 최소 하나는 있어야 한다');

  /// 번지게 할 러닝 색. 순서가 배치 각도를 정한다.
  final List<Color> colors;

  /// 아우라 전체 지름.
  final double size;

  /// 생기(0~1). 낮을수록 옅어진다.
  ///
  /// 프로필 아우라는 활동이 없으면 이 값이 내려가 빛이 바랜다.
  /// S01 스플래시는 0.7로 살짝 눌러 쓴다.
  final double vitality;

  @override
  Widget build(BuildContext context) {
    final v = vitality.clamp(0.0, 1.0);

    // 색이 하나면 중심에, 여러 개면 둘레에 고르게 놓는다.
    final blobSize = colors.length == 1 ? size : size * 0.62;
    final orbitRadius = colors.length == 1 ? 0.0 : size * 0.19;

    return SizedBox(
      width: size,
      height: size,
      child: ImageFiltered(
        // 블롭 경계를 지워 서로 섞이게 한다. 지름에 비례시켜야 크기가 달라져도 같아 보인다.
        imageFilter: ui.ImageFilter.blur(
          sigmaX: size * 0.09,
          sigmaY: size * 0.09,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            for (final (i, color) in colors.indexed)
              Transform.translate(
                offset: _offsetFor(i, colors.length, orbitRadius),
                child: Container(
                  width: blobSize,
                  height: blobSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        color.withValues(alpha: 0.9 * v),
                        color.withValues(alpha: 0),
                      ],
                      // 절반까지는 색을 유지하고 그 뒤로 잦아든다.
                      stops: const [0.45, 1],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// [count]개를 원 둘레에 고르게 놓았을 때 [index]번째의 위치.
  /// 12시 방향부터 시계 방향으로 돈다.
  Offset _offsetFor(int index, int count, double radius) {
    if (radius == 0) return Offset.zero;
    final angle = (2 * math.pi * index / count) - math.pi / 2;
    return Offset(math.cos(angle) * radius, math.sin(angle) * radius);
  }
}
