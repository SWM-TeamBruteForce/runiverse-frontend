import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/auth/domain/password_rule.dart';

/// 비밀번호 규칙 — 순수 계산 로직.
///
/// **이 규칙은 백엔드 `SignUpRequest`의 사본이다.** 서버가 규칙을 바꾸면 여기가 어긋나고,
/// 증상은 "앱은 통과시켰는데 서버가 400"으로 나타난다. 경계값을 촘촘히 본다.
void main() {
  test('아무것도 없으면 오류가 아니라 시작 상태다', () {
    expect(PasswordRule.of(''), PasswordStatus.empty);
    expect(PasswordRule.of('').isValid, isFalse);
  });

  test('길이 하한 — 5자는 막히고 6자는 통과한다', () {
    expect(PasswordRule.of('ab12!'), PasswordStatus.tooShort);
    expect(PasswordRule.of('ab123!'), PasswordStatus.valid);
  });

  test('길이 상한 — 16자는 통과하고 17자는 막힌다', () {
    expect(PasswordRule.of('abcdefghij12345!'), PasswordStatus.valid);
    expect(PasswordRule.of('abcdefghij123456!'), PasswordStatus.tooLong);
  });

  test('영문·숫자·특수문자 중 하나라도 빠지면 막힌다', () {
    expect(PasswordRule.of('abcdef!'), PasswordStatus.missingKind); // 숫자 없음
    expect(PasswordRule.of('abc123'), PasswordStatus.missingKind); // 특수문자 없음
    expect(PasswordRule.of('123456!'), PasswordStatus.missingKind); // 영문 없음
  });

  test('길이 검사가 종류 검사보다 먼저다', () {
    // 둘 다 틀렸을 때 "6자 이상이어야 해요"부터 보여줘야 한다.
    // 종류를 먼저 말하면 사용자는 글자를 채우고도 계속 막힌다.
    expect(PasswordRule.of('ab!'), PasswordStatus.tooShort);
  });

  test('백엔드 정규식이 허용하는 특수문자를 모두 받는다', () {
    for (final ch in PasswordRule.specials.split('')) {
      expect(
        PasswordRule.of('abc12$ch'),
        PasswordStatus.valid,
        reason: '특수문자 "$ch"가 막혔다',
      );
    }
  });

  test('공백은 특수문자로 치지 않는다', () {
    // 백엔드 문자 집합에 공백이 없다. 앱이 통과시키면 서버에서 400이 난다.
    expect(PasswordRule.of('abc12 '), PasswordStatus.missingKind);
  });

  // ── 한글 ────────────────────────────────────────────────────
  //
  // 한/영을 깜빡하고 친 입력이 어떻게 판정되는지 고정한다.
  // 비밀번호는 이메일과 달리 **한글을 막지 않는다** — 백엔드 정규식도 `.{6,16}`이라
  // 한글을 허용하기 때문이다. 두 쪽 판정이 갈리면 앱이 통과시킨 값을 서버가 거절한다.

  test('한글만으로는 통과하지 못한다', () {
    // 영문·숫자·특수문자가 하나도 없다. 한/영을 깜빡한 입력이 여기서 걸린다.
    expect(PasswordRule.of('러너러너러너'), PasswordStatus.missingKind);
    expect(PasswordRule.of('ㄱㅕㅜㅜㄷㄱ'), PasswordStatus.missingKind);
  });

  test('한글이 섞여도 영문·숫자·특수문자가 있으면 통과한다', () {
    // 막지 않는다. 서버가 받는 값을 앱이 거절하면 쓸 수 있는 비밀번호를 못 만든다.
    expect(PasswordRule.of('러너abc12!'), PasswordStatus.valid);
  });

  test('한글 한 글자를 1자로 센다', () {
    // 서버 `@Size`는 Java `String.length()`(UTF-16 코드 단위)를 센다.
    // 한글 음절은 BMP 안에 있어 양쪽 모두 1이다 — 길이 판정이 갈리지 않는다.
    expect(PasswordRule.of('러너a1!'), PasswordStatus.tooShort); // 5자
    expect(PasswordRule.of('러너남a1!'), PasswordStatus.valid); // 6자
  });
}
