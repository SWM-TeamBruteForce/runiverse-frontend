import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/utils/age_rule.dart';

/// 만 나이 — **하루 차이로 갈리는 곳만 본다.**
///
/// 연도만 빼면 같은 해에 태어난 사람이 전부 같은 나이가 된다. 실제로는
/// 생일이 지났는지에 따라 갈리고, 그 하루가 가입 가능 여부를 뒤집는다.
void main() {
  group('만 나이', () {
    test('생일이 지났으면 그 나이다', () {
      expect(
        AgeRule.ageOn(DateTime(2012, 3, 1), now: DateTime(2026, 9, 7)),
        14,
      );
    });

    test('⚠️ 생일 당일이면 이미 그 나이다', () {
      // 하루 늦게 세면 생일에 가입하려는 사람이 막힌다.
      expect(
        AgeRule.ageOn(DateTime(2012, 9, 7), now: DateTime(2026, 9, 7)),
        14,
      );
    });

    test('⚠️ 생일 하루 전이면 아직 한 살 아래다', () {
      expect(
        AgeRule.ageOn(DateTime(2012, 9, 8), now: DateTime(2026, 9, 7)),
        13,
      );
    });

    test('⚠️ 같은 해에 태어나도 월에 따라 갈린다', () {
      // 연도만 보고 자르면 이 둘이 같은 취급을 받는다. 하나는 받아야 하고
      // 하나는 막아야 한다.
      expect(
        AgeRule.ageOn(DateTime(2012, 1, 5), now: DateTime(2026, 9, 7)),
        14,
      );
      expect(
        AgeRule.ageOn(DateTime(2012, 12, 5), now: DateTime(2026, 9, 7)),
        13,
      );
    });

    test('2월 29일생은 평년 3월 1일에 한 살 더 먹는다', () {
      // 2월 29일이 없는 해에는 2월 28일까지 아직 생일 전이다.
      expect(
        AgeRule.ageOn(DateTime(2012, 2, 29), now: DateTime(2026, 2, 28)),
        13,
      );
      expect(
        AgeRule.ageOn(DateTime(2012, 2, 29), now: DateTime(2026, 3, 1)),
        14,
      );
    });
  });

  group('가입 가능 여부', () {
    test('만 14세부터 받는다', () {
      expect(
        AgeRule.isAllowed(DateTime(2012, 9, 7), now: DateTime(2026, 9, 7)),
        isTrue,
      );
    });

    test('⚠️ 만 13세는 막는다', () {
      // 같은 2012년생이라도 생일이 안 지났으면 아직 13세다.
      expect(
        AgeRule.isAllowed(DateTime(2012, 12, 1), now: DateTime(2026, 9, 7)),
        isFalse,
      );
    });

    test('한참 위는 당연히 받는다', () {
      expect(
        AgeRule.isAllowed(DateTime(1990, 4, 12), now: DateTime(2026, 9, 7)),
        isTrue,
      );
    });
  });

  group('휠 상한', () {
    test('올해에서 14를 뺀 연도까지 보여준다', () {
      expect(AgeRule.latestYear(DateTime(2026, 9, 7)), 2012);
    });

    test('⚠️ 상한 연도에도 막히는 날이 섞여 있다', () {
      // 휠을 한 해 더 좁히면 생일이 지난 만 14세까지 함께 막힌다.
      // 연도로는 고를 수 있고, 판정은 [AgeRule.isAllowed]가 한다.
      final year = AgeRule.latestYear(DateTime(2026, 9, 7));
      expect(
        AgeRule.isAllowed(DateTime(year, 1, 1), now: DateTime(2026, 9, 7)),
        isTrue,
      );
      expect(
        AgeRule.isAllowed(DateTime(year, 12, 31), now: DateTime(2026, 9, 7)),
        isFalse,
      );
    });
  });
}
