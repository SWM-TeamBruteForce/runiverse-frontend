import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_palette.dart';

/// 새 시맨틱 색 — **두 테마가 다 살아 있는가.**
void main() {
  const themes = [AppColorsV2.dark, AppColorsV2.light];

  test('⚠️ 다크와 라이트가 실제로 다르다', () {
    // 한쪽을 복사해 두고 값을 안 바꾸면 라이트 테마에서 글자가 안 보인다.
    expect(AppColorsV2.dark.bgBase, isNot(AppColorsV2.light.bgBase));
    expect(AppColorsV2.dark.textPrimary, isNot(AppColorsV2.light.textPrimary));
    expect(AppColorsV2.dark.bgSurface, isNot(AppColorsV2.light.bgSurface));
  });

  test('⚠️ 글자가 배경에 묻히지 않는다', () {
    // 램프에서 규칙으로 뽑다가 한 칸 어긋나면 같은 색이 된다.
    for (final c in themes) {
      expect(c.textPrimary, isNot(c.bgBase));
      expect(c.textSecondary, isNot(c.bgSurface));
      expect(c.textOnPrimary, isNot(c.primary));
      expect(c.borderDefault, isNot(c.bgSurface));
    }
  });

  test('⚠️ 글자 넷이 점점 흐려진다', () {
    // 시안이 불투명도로 위계를 만든다. 순서가 뒤집히면 보조 글자가 본문보다
    // 진해져서 화면의 강약이 거꾸로 선다.
    for (final c in themes) {
      expect(c.textPrimary.a, greaterThan(c.textSecondary.a));
      expect(c.textSecondary.a, greaterThan(c.textTertiary.a));
      expect(c.textTertiary.a, greaterThan(c.textDisabled.a));
    }
  });

  test('⚠️ 시안에서 직접 읽은 값이 그대로다', () {
    // `158:2976` 매칭대기중 배지 — 면 #202B43, 글자 #227DFF.
    // 이 둘은 규칙으로 정한 것이 아니라 시안이 준 값이라 흔들리면 안 된다.
    expect(AppColorsV2.dark.primaryMuted, AppPaletteV2.brandDeep);
    expect(AppColorsV2.dark.matchWaiting, AppPaletteV2.brand);
  });

  test('딤은 반투명이다', () {
    // 불투명하면 모달 뒤가 통째로 가려져 맥락이 사라진다.
    for (final c in themes) {
      expect(c.bgScrim.a, lessThan(1.0));
      expect(c.bgScrim.a, greaterThan(0.0));
    }
  });

  test('lerp는 양 끝을 그대로 돌려준다', () {
    expect(
      AppColorsV2.dark.lerp(AppColorsV2.light, 0).bgBase,
      AppColorsV2.dark.bgBase,
    );
    expect(
      AppColorsV2.dark.lerp(AppColorsV2.light, 1).bgBase,
      AppColorsV2.light.bgBase,
    );
  });

  test('copyWith는 준 것만 바꾼다', () {
    const red = Color(0xFFFF0000);
    final changed = AppColorsV2.dark.copyWith(primary: red);

    expect(changed.primary, red);
    expect(changed.bgBase, AppColorsV2.dark.bgBase);
  });
}
