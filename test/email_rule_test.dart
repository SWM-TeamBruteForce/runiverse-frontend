import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/auth/domain/email_rule.dart';

/// 이메일 형태 판정 — 순수 계산 로직.
///
/// 여기서 보는 것은 **오타를 걸러내는 정도**지 실제로 받을 수 있는 주소인지가 아니다.
/// 그건 서버만 안다. 화면이 미리 막아야 하는 것은 `runner@`처럼 명백히 미완성인 입력이다.
void main() {
  test('아무것도 없으면 오류가 아니라 시작 상태다', () {
    expect(EmailRule.of(''), EmailStatus.empty);
    expect(EmailRule.of('   '), EmailStatus.empty);
    expect(EmailRule.of('').isValid, isFalse);
  });

  test('@와 점이 모두 있어야 통과한다', () {
    expect(EmailRule.of('runner@example.com'), EmailStatus.valid);
    expect(EmailRule.of('runner@example'), EmailStatus.invalid);
    expect(EmailRule.of('runner.example.com'), EmailStatus.invalid);
  });

  test('앞뒤 공백은 무시한다', () {
    // 자판이 자동으로 넣는 공백 하나 때문에 가입이 막히면 안 된다.
    expect(EmailRule.of('  runner@example.com  '), EmailStatus.valid);
  });

  test('가운데 공백이나 @ 두 개는 막는다', () {
    expect(EmailRule.of('run ner@example.com'), EmailStatus.invalid);
    expect(EmailRule.of('a@b@example.com'), EmailStatus.invalid);
  });
}
