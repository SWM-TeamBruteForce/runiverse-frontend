import 'package:flutter/material.dart';
import 'package:runiverse/core/theme/extensions/app_glow.dart';

/// 러닝 색 하나를 또렷한 원으로 보여준다. 온보딩 오브(S02)와 시그니처 리빌(S04.5)이 쓴다.
///
/// ## [AuraOrb]와 어떻게 다른가
///
/// | | [RunColorOrb] | [AuraOrb] |
/// |---|---|---|
/// | 색 | 하나 | 여럿이 섞임 |
/// | 경계 | 또렷하다 | 번져서 사라진다 |
/// | 뜻 | **이게 그 색이다** | 색들이 합쳐진다 |
///
/// 색 하나를 "이 색이 당신 색"이라고 제시할 때는 경계가 또렷해야 한다.
/// 흐릿하면 어느 색인지 특정되지 않아 메시지가 죽는다.
/// 반대로 블렌드를 예고하는 자리(스플래시)는 경계가 없어야 한다.
///
/// ## 글로우는 색을 인자로 받는다
///
/// [AppGlow]의 메서드는 전부 `Color`를 요구한다. 앱 크롬에 러닝 색이 새지 않도록
/// 타입으로 막아둔 것이다(`docs/implementation-notes.md` §3-3).
/// 여기서 그 통로를 처음 쓴다.
///
/// ⚠️ **이 위젯 위에 텍스트를 얹지 않는다.** 러닝 색은 채도가 높아 대비 기준을
/// 통과하지 못한다. 글자는 원 바깥에 둔다(디자인 시스템 §1-4).
class RunColorOrb extends StatelessWidget {
  const RunColorOrb({
    required this.color,
    required this.size,
    this.glow = RunColorOrbGlow.medium,
    super.key,
  });

  /// 보여줄 러닝 색. **위젯이 고르지 않는다.**
  final Color color;

  /// 원의 지름.
  final double size;

  final RunColorOrbGlow glow;

  @override
  Widget build(BuildContext context) {
    final glowTokens = Theme.of(context).extension<AppGlow>() ?? AppGlow.dark;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: switch (glow) {
          RunColorOrbGlow.small => glowTokens.sm(color),
          RunColorOrbGlow.medium => glowTokens.md(color),
          RunColorOrbGlow.large => glowTokens.lg(color),
        },
      ),
    );
  }
}

/// 원 바깥으로 번지는 빛의 세기.
enum RunColorOrbGlow {
  /// 목록 안 스와치처럼 작게 놓일 때.
  small,

  /// 기본. 온보딩 오브.
  medium,

  /// 색 리빌처럼 이 색이 화면의 주인공일 때.
  large,
}
