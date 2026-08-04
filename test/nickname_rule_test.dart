import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/onboarding/domain/nickname_rule.dart';

/// 닉네임 길이 규칙 — 순수 계산 로직.
///
/// 경계값만 본다. 2와 12는 **통과해야 하고**, 1과 13은 막혀야 한다.
/// 부등호를 하나 잘못 쓰면(`<` 대신 `<=`) 여기서 걸린다.
void main() {
  test('아무것도 없으면 오류가 아니라 시작 상태다', () {
    expect(NicknameRule.of(0), NicknameStatus.empty);
    expect(NicknameRule.of(0).isValid, isFalse);
  });

  test('하한 경계 — 1자는 막히고 2자는 통과한다', () {
    expect(NicknameRule.of(1), NicknameStatus.tooShort);
    expect(NicknameRule.of(NicknameRule.min), NicknameStatus.valid);
  });

  test('상한 경계 — 12자는 통과하고 13자는 막힌다', () {
    expect(NicknameRule.of(NicknameRule.max), NicknameStatus.valid);
    expect(NicknameRule.of(NicknameRule.max + 1), NicknameStatus.tooLong);
  });

  test('짧아서 막힌 것과 길어서 막힌 것을 구분한다', () {
    // 화면이 서로 다른 문구를 띄워야 하므로 둘을 뭉뚱그리면 안 된다.
    expect(NicknameRule.of(1), isNot(NicknameRule.of(13)));
  });
}
