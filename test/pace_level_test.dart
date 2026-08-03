import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/onboarding/domain/pace_level.dart';

/// 페이스 구간 판정 — 순수 계산 로직.
///
/// 이 구간이 시그니처 컬러의 hue를 가른다. 경계에서 한 칸 밀리면
/// 사용자가 받는 **색이 바뀐다.** 경계값만 본다.
void main() {
  test('재보지 않았으면 미측정이다', () {
    expect(PaceRule.levelOf(null), PaceLevel.unmeasured);
  });

  test('숙련 경계 — 5분 미만은 숙련, 5분 정각은 중급', () {
    expect(PaceRule.levelOf(PaceRule.advancedBelow - 1), PaceLevel.advanced);
    expect(PaceRule.levelOf(PaceRule.advancedBelow), PaceLevel.intermediate);
  });

  test('중급 경계 — 6분 30초 미만은 중급, 정각은 입문', () {
    expect(
      PaceRule.levelOf(PaceRule.intermediateBelow - 1),
      PaceLevel.intermediate,
    );
    expect(PaceRule.levelOf(PaceRule.intermediateBelow), PaceLevel.beginner);
  });

  test('분·초를 초로 합친다', () {
    expect(PaceRule.toSeconds(5, 42), 342);
    expect(PaceRule.toSeconds(6, 0), 360);
  });

  test('연습 유도는 입문과 미측정에만 붙는다', () {
    // 재본 적 없는 사람이야말로 한 번 뛰어봐야 하는 쪽이다.
    expect(PaceLevel.beginner.needsPracticeNudge, isTrue);
    expect(PaceLevel.unmeasured.needsPracticeNudge, isTrue);

    expect(PaceLevel.intermediate.needsPracticeNudge, isFalse);
    expect(PaceLevel.advanced.needsPracticeNudge, isFalse);
  });
}
