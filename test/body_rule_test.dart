import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/onboarding/domain/body_rule.dart';

/// 휠 피커가 막아주던 것을 규칙이 대신 막는가.
///
/// 프로필 등록이 **고르는 화면에서 치는 화면으로** 바뀌었다(2026-09-30).
/// 고를 때는 만들 수 없던 값이 칠 때는 만들어진다 — 그 자리를 여기서 막는다.
void main() {
  group('생년월일', () {
    test('여덟 자리 숫자를 날짜로 읽는다', () {
      expect(BodyRule.parseBirth('19990116'), DateTime(1999, 1, 16));
      expect(BodyRule.parseBirth('20001231'), DateTime(2000, 12, 31));
    });

    test('⚠️ 달에 없는 날을 막는다', () {
      // ⚠️ 휠도 이건 못 막았다 — 일 칸이 달과 무관하게 1~31이었다.
      // Dart 의 `DateTime(1999, 2, 31)`은 **3월 3일로 넘어간다.** 조용히
      // 다른 날이 되는 쪽이 거절하는 쪽보다 나쁘다.
      expect(BodyRule.parseBirth('19990231'), isNull);
      expect(BodyRule.parseBirth('19990431'), isNull);
      expect(BodyRule.parseBirth('19991301'), isNull);
      expect(BodyRule.parseBirth('19990100'), isNull);
    });

    test('윤년은 통과하고 평년은 막는다', () {
      expect(BodyRule.parseBirth('20240229'), DateTime(2024, 2, 29));
      expect(BodyRule.parseBirth('20230229'), isNull);
      // 100으로 나뉘지만 400으로 안 나뉘는 해는 평년이다.
      expect(BodyRule.parseBirth('19000229'), isNull);
      expect(BodyRule.parseBirth('20000229'), DateTime(2000, 2, 29));
    });

    test('여덟 자리가 아니면 막는다', () {
      expect(BodyRule.parseBirth('1999116'), isNull);
      expect(BodyRule.parseBirth('199901160'), isNull);
      expect(BodyRule.parseBirth(''), isNull);
    });

    test('숫자가 아닌 것이 섞이면 막는다', () {
      expect(BodyRule.parseBirth('1999-1-16'), isNull);
      expect(BodyRule.parseBirth('1999011a'), isNull);
    });

    test('⚠️ 부호가 붙어도 막는다', () {
      // `int.tryParse('-9990116')`은 성공한다. 그대로 두면 연도 -999 가 된다.
      expect(BodyRule.parseBirth('-9990116'), isNull);
      expect(BodyRule.parseNumber('-175'), isNull);
      expect(BodyRule.parseNumber('+175'), isNull);
    });

    test('⚠️ 아직 오지 않은 날을 막는다', () {
      // 만 14세 판정(`AgeRule`)에 걸려 어차피 막히지만, 그때 나오는 말은
      // "너무 어려요"다. 미래 날짜에 그 문구를 보이면 무엇이 잘못됐는지 모른다.
      final now = DateTime(2026, 9, 30);
      expect(BodyRule.isFutureBirth(DateTime(2026, 10, 1), now: now), isTrue);
      expect(BodyRule.isFutureBirth(DateTime(2026, 9, 30), now: now), isFalse);
      expect(BodyRule.isFutureBirth(DateTime(1999, 1, 16), now: now), isFalse);
    });

    test('너무 오래된 날을 막는다', () {
      // 옛 휠의 아래 끝이 `now.year - 80`이었다. 그 범위를 그대로 쓴다.
      final now = DateTime(2026, 9, 30);
      expect(BodyRule.isTooOldBirth(DateTime(1946, 1, 1), now: now), isFalse);
      expect(BodyRule.isTooOldBirth(DateTime(1945, 12, 31), now: now), isTrue);
    });
  });

  group('키와 몸무게', () {
    test('⚠️ 옛 휠이 주던 범위를 그대로 쓴다', () {
      // 130~210 / 30~140. 바꾸려면 프로필 수정 화면도 같이 본다.
      expect(BodyRule.isAllowedHeight(129), isFalse);
      expect(BodyRule.isAllowedHeight(130), isTrue);
      expect(BodyRule.isAllowedHeight(210), isTrue);
      expect(BodyRule.isAllowedHeight(211), isFalse);

      expect(BodyRule.isAllowedWeight(29), isFalse);
      expect(BodyRule.isAllowedWeight(30), isTrue);
      expect(BodyRule.isAllowedWeight(140), isTrue);
      expect(BodyRule.isAllowedWeight(141), isFalse);
    });

    test('숫자가 아니면 읽지 않는다', () {
      expect(BodyRule.parseNumber(''), isNull);
      expect(BodyRule.parseNumber('17o'), isNull);
      expect(BodyRule.parseNumber('17.5'), isNull);
      expect(BodyRule.parseNumber('175'), 175);
    });

    test('⚠️ 앞에 0이 붙어도 읽는다', () {
      // 자판에서 `0175`가 만들어진다. 막을 이유가 없다.
      expect(BodyRule.parseNumber('0175'), 175);
    });
  });
}
