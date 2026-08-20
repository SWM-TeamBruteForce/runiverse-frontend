import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/onboarding/domain/nickname_rule.dart';

/// 닉네임 규칙 — 순수 계산 로직.
///
/// 길이는 경계값만 본다. 상한은 **서버 명세(2~16자)와 같아야 한다** —
/// 앱이 더 빡빡하면 서버가 받아주는 이름을 앱이 거절한다.
/// 부등호를 하나 잘못 쓰면(`<` 대신 `<=`) 여기서 걸린다.
///
/// 문자 규칙은 **서버 정규식과 같은 기준**이라, 여기가 통과시키는 값은
/// 서버도 통과시켜야 한다. 어긋나면 "앱은 됐는데 서버가 400"이 된다.
void main() {
  test('아무것도 없으면 오류가 아니라 시작 상태다', () {
    expect(NicknameRule.of(0, ''), NicknameStatus.empty);
    expect(NicknameRule.of(0, '').isValid, isFalse);
  });

  test('하한 경계 — 1자는 막히고 2자는 통과한다', () {
    expect(NicknameRule.of(1, '가'), NicknameStatus.tooShort);
    expect(NicknameRule.of(NicknameRule.min, '가나'), NicknameStatus.valid);
  });

  test('상한은 서버 명세와 같은 16자다', () {
    // 앱이 더 빡빡하면 13~16자를 쓰려는 사람이 앱에서만 막힌다.
    // 서버는 받아주므로 증상이 "왜 안 되지"로만 남는다.
    expect(NicknameRule.max, 16);
  });

  test('상한 경계 — 상한까지는 통과하고 한 자 더는 막힌다', () {
    final atMax = '가' * NicknameRule.max;
    expect(NicknameRule.of(NicknameRule.max, atMax), NicknameStatus.valid);
    expect(
      NicknameRule.of(NicknameRule.max + 1, '$atMax가'),
      NicknameStatus.tooLong,
    );
  });

  test('짧아서 막힌 것과 길어서 막힌 것을 구분한다', () {
    // 화면이 서로 다른 문구를 띄워야 하므로 둘을 뭉뚱그리면 안 된다.
    expect(
      NicknameRule.of(1, '가'),
      isNot(
        NicknameRule.of(NicknameRule.max + 1, '가' * (NicknameRule.max + 1)),
      ),
    );
  });

  test('공백이 들어가면 막힌다', () {
    // 서버 정규식이 공백을 거절한다. 여기서 막지 않으면
    // 사용자는 다 채우고 나서 400을 받는다.
    expect(NicknameRule.of(4, '런서 김'), NicknameStatus.invalidChars);
  });

  test('특수문자와 이모지도 막힌다', () {
    expect(NicknameRule.of(7, 'runner!'), NicknameStatus.invalidChars);
    expect(NicknameRule.of(3, '러너🏃'), NicknameStatus.invalidChars);
  });

  test('한글 영문 숫자 밑줄은 통과한다', () {
    expect(NicknameRule.of(4, '러너42'), NicknameStatus.valid);
    expect(NicknameRule.of(8, 'runner_1'), NicknameStatus.valid);
  });

  test('길이를 먼저 본다', () {
    // 길이가 틀렸으면 문자 규칙보다 길이를 먼저 알린다.
    // 둘 다 틀렸을 때 "2자 이상"이 "쓸 수 없는 문자"보다 고치기 쉽다.
    expect(NicknameRule.of(1, '!'), NicknameStatus.tooShort);
  });
}
