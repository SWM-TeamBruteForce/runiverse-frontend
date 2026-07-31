import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// 러닝 색 글로우 — 디자인 시스템 v1.1 §1-3.
///
/// 러닝 색이 "발광"하는 표현 전용이다. 기반 UI 그림자(`AppElevation`)와 **역할이 다르다.**
///
/// ## 왜 색을 인자로 받는가
///
/// 모든 메서드가 `runColor`를 요구한다. 값을 미리 담아두지 않는 게 의도다 —
/// 앱 크롬에는 넘길 러닝 색이 없으므로 실수로 쓸 수 없다.
/// 반대로 `AppElevation`에는 색을 받는 API가 아예 없다. 두 방향에서 막았다.
///
/// ```dart
/// // ✅ 러닝 색이 있는 자리
/// BoxDecoration(boxShadow: context.appGlow.md(runColor))
///
/// // ❌ 앱 크롬에 글로우 — 넘길 색이 없어서 애초에 못 쓴다
/// BoxDecoration(boxShadow: context.appGlow.md(???))
/// ```
///
/// ## 텍스트 뒤에 깔지 않는다
///
/// 러닝 중 수치는 대비 7:1을 만족해야 하는데 숫자 뒤 색 번짐이 이를 무너뜨린다.
/// 아우라·컬러 밴드 위에 텍스트를 얹을 때는 반드시 스크림 레이어를 사이에 둔다(§1-4).
@immutable
class AppGlow extends ThemeExtension<AppGlow> {
  const AppGlow({required this.intensity});

  /// 글로우 강도 배수. 다크 1.0, 라이트 0.5 — 밝은 배경에서는 절반만 쓴다.
  final double intensity;

  static const dark = AppGlow(intensity: 1);
  static const light = AppGlow(intensity: 0.5);

  /// 컬렉션 슬롯·아바타. `0 0 12px 0`
  List<BoxShadow> sm(Color runColor) => [
    BoxShadow(
      color: runColor.withValues(alpha: 0.4 * intensity),
      blurRadius: 12,
    ),
  ];

  /// 색 리빌 순간·프로필 아우라. `0 0 28px 4px`
  List<BoxShadow> md(Color runColor) => [
    BoxShadow(
      color: runColor.withValues(alpha: 0.5 * intensity),
      blurRadius: 28,
      spreadRadius: 4,
    ),
  ];

  /// 리빌 피크. `0 0 64px 12px`
  List<BoxShadow> lg(Color runColor) => [
    BoxShadow(
      color: runColor.withValues(alpha: 0.6 * intensity),
      blurRadius: 64,
      spreadRadius: 12,
    ),
  ];

  // 여러 색을 섞는 아우라(`glow.blend.aura`)는 radial-gradient라 BoxShadow가 아니다.
  // 프로필 헤더(S20)를 만들 때 그 화면의 요구에 맞춰 추가한다.

  @override
  AppGlow copyWith({double? intensity}) =>
      AppGlow(intensity: intensity ?? this.intensity);

  @override
  AppGlow lerp(covariant AppGlow? other, double t) {
    if (other == null) return this;
    return AppGlow(
      intensity: lerpDouble(intensity, other.intensity, t) ?? intensity,
    );
  }
}

/// `context.appGlow.md(runColor)`로 글로우를 만든다.
extension AppGlowContext on BuildContext {
  AppGlow get appGlow {
    final glow = Theme.of(this).extension<AppGlow>();
    assert(
      glow != null,
      'AppGlow가 ThemeData.extensions에 없다. '
      'MaterialApp의 theme/darkTheme으로 AppTheme.light()/dark()를 쓰고 있는지 확인한다.',
    );
    return glow ?? AppGlow.dark;
  }
}
