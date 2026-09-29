import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/theme/tokens/run_palette.dart';
import 'package:runiverse/core/theme/v2/run_palette.dart';

/// 새 러닝 팔레트 — **빠진 hue도 겹치는 색도 없다.**
///
/// 컬렉션 그리드는 30칸을 한 번에 그린다. hue 하나가 비면 그 자리에서 죽고,
/// 두 hue가 같은 색이면 무엇을 모았는지 구분할 수 없다.
void main() {
  test('⚠️ 모든 hue에 색이 있다', () {
    // `_shades`에서 하나만 빠져도 `shadesOf`가 죽는다. enum에 hue를 더하고
    // 여기를 안 채우는 것이 가장 흔한 실수다.
    for (final hue in RunHue.values) {
      expect(RunPaletteV2.shadesOf(hue), hasLength(RunPaletteV2.shadeCount));
    }
  });

  test('⚠️ 30색이 전부 다르다', () {
    final all = [
      for (final hue in RunHue.values) ...RunPaletteV2.shadesOf(hue),
    ];

    expect(all.toSet(), hasLength(all.length));
  });

  test('⚠️ 옛 팔레트와 색이 실제로 달라졌다', () {
    // 옮기다 한 군을 빠뜨리면 그 hue만 옛 색으로 남는다. 눈으로는
    // "왜 이것만 촌스럽지" 정도로 보이고 원인을 찾기 어렵다.
    for (final hue in RunHue.values) {
      expect(
        RunPaletteV2.shadesOf(hue),
        isNot(RunPalette.shadesOf(hue)),
        reason: '$hue 가 옛 색 그대로다',
      );
    }
  });

  test('shade는 1부터 센다', () {
    // 0부터 세면 `assert`가 잡는다. 화면이 문서 표기(1~3)를 그대로 쓴다.
    final shades = RunPaletteV2.shadesOf(RunHue.distance);

    expect(RunPaletteV2.color(RunHue.distance, 1), shades.first);
    expect(RunPaletteV2.color(RunHue.distance, 3), shades.last);
  });

  test('파티원 색은 자리 번호로 돌아간다', () {
    // 방은 최대 4명이지만 slot이 그보다 커도 죽지 않아야 한다.
    expect(RunPaletteV2.lane(4), RunPaletteV2.lane(0));
  });

  test('기존 팔레트와 shade 개수가 같다', () {
    // 옛 화면과 새 화면이 같은 분모(30색)를 말해야 한다.
    expect(RunPaletteV2.shadeCount, RunPalette.shadeCount);
  });
}
