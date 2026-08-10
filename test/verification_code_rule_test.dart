import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/auth/domain/verification_code_rule.dart';

/// 인증번호 모양 판정 — 순수 계산 로직.
///
/// **맞는 번호인지는 여기서 모른다.** 발급 여부와 만료는 서버만 안다.
/// 이 규칙이 정하는 것은 `확인` 버튼을 언제 열어줄지뿐이다.
void main() {
  test('아무것도 없으면 오류가 아니라 시작 상태다', () {
    expect(VerificationCodeRule.of(''), VerificationCodeStatus.empty);
    expect(VerificationCodeRule.of('').isValid, isFalse);
  });

  test('숫자 6자리여야 통과한다', () {
    expect(VerificationCodeRule.of('123456'), VerificationCodeStatus.valid);
    expect(VerificationCodeRule.of('000000'), VerificationCodeStatus.valid);
  });

  test('덜 쳤거나 더 쳤으면 막는다', () {
    expect(VerificationCodeRule.of('12345'), VerificationCodeStatus.incomplete);
    expect(
      VerificationCodeRule.of('1234567'),
      VerificationCodeStatus.incomplete,
    );
  });

  test('숫자가 아니면 막는다', () {
    // 입력칸이 숫자만 받게 막아두지만 도메인은 그것에 기대지 않는다.
    expect(
      VerificationCodeRule.of('12345a'),
      VerificationCodeStatus.incomplete,
    );
    expect(
      VerificationCodeRule.of('１２３４５６'),
      VerificationCodeStatus.incomplete,
    );
  });

  test('유효 시간은 5분이다', () {
    // 화면 카운트다운이 이 값을 쓴다. 서버가 `expiresIn`을 주면 그 값으로 바뀐다.
    expect(VerificationCodeRule.ttl, const Duration(minutes: 5));
  });
}
