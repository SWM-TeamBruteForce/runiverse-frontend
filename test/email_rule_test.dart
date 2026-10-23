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

  test('2글자 TLD는 통과한다', () {
    // `.co`(콜롬비아) `.io` `.me` `.kr`은 전부 실재한다.
    // 3글자를 요구하면 진짜 주소를 가진 사람이 가입하지 못한다.
    expect(EmailRule.of('runner@example.co'), EmailStatus.valid);
    expect(EmailRule.of('runner@example.io'), EmailStatus.valid);
    expect(EmailRule.of('runner@example.co.kr'), EmailStatus.valid);
  });

  test('1글자 TLD는 막는다', () {
    // 실재하지 않는다. `.com`을 치다 만 상태다.
    expect(EmailRule.of('runner@example.c'), EmailStatus.invalid);
  });

  test('점이 연속이거나 끝에 붙으면 막는다', () {
    expect(EmailRule.of('runner@example..com'), EmailStatus.invalid);
    expect(EmailRule.of('runner@example.com.'), EmailStatus.invalid);
  });

  test('도메인이 하이픈으로 시작하거나 끝나면 막는다', () {
    expect(EmailRule.of('runner@-example.com'), EmailStatus.invalid);
    expect(EmailRule.of('runner@example-.com'), EmailStatus.invalid);
  });

  test('한글이 섞이면 막는다', () {
    // 한/영을 깜빡하고 친 입력이 여기서 걸린다.
    // 통과시키면 로그인 버튼이 켜지고, 눌러본 뒤에야 틀린 것을 알게 된다.
    expect(EmailRule.of('러너@example.com'), EmailStatus.invalid);
    expect(EmailRule.of('ㄱㅕㅜㅜㄷㄱ@example.com'), EmailStatus.invalid);
    expect(EmailRule.of('runner@네이버.com'), EmailStatus.invalid);
    expect(EmailRule.of('runner@example.한국'), EmailStatus.invalid);
  });

  test('실제로 쓰는 형태는 계속 통과한다', () {
    // 규칙을 조일 때 이것들이 막히면 조인 것이 지나친 것이다.
    expect(EmailRule.of('run.ner+tag@example.com'), EmailStatus.valid);
    expect(EmailRule.of('Runner@Example.COM'), EmailStatus.valid);
    expect(EmailRule.of('runner_42@my-domain.com'), EmailStatus.valid);
  });
}
