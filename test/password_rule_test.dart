import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/auth/domain/password_rule.dart';

/// 비밀번호 규칙 — 순수 계산 로직.
///
/// **이 규칙은 백엔드 `SignUpRequest`를 옮긴 것이다.** 서버가 규칙을 바꾸면 여기가 어긋나고,
/// 증상은 "앱은 통과시켰는데 서버가 400"으로 나타난다. 경계값을 촘촘히 본다.
///
/// 한 군데만 앱이 더 좁다 — **허용 문자**. 서버 정규식 본체는 `.{6,16}`이라 한글도 받지만
/// 앱은 영문·숫자·특수문자만 받는다.
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
    expect(PasswordRule.of('abc12 '), PasswordStatus.disallowedChar);
  });

  // ── 허용 문자 ────────────────────────────────────────────────
  //
  // 영문·숫자·특수문자만 받는다. 한/영을 깜빡하고 친 입력을 여기서 잡는다.
  //
  // ⚠️ 서버 정규식 본체는 `.{6,16}`이라 한글을 통과시킨다. **앱이 더 엄격하다.**
  // 방향이 이쪽인 것은 안전하다 — 앱이 통과시킨 값은 서버도 통과한다.

  test('한글만 치면 막는다', () {
    expect(PasswordRule.of('러너러너러너'), PasswordStatus.disallowedChar);
    expect(PasswordRule.of('ㄱㅕㅜㅜㄷㄱ'), PasswordStatus.disallowedChar);
  });

  test('한글이 한 글자만 섞여도 막는다', () {
    // 나머지가 규칙을 다 채워도 소용없다. 이걸 통과시키면
    // 한/영을 깜빡한 사람이 그대로 가입해 다음 로그인 때 못 들어온다.
    expect(PasswordRule.of('러너abc12!'), PasswordStatus.disallowedChar);
    expect(PasswordRule.of('abc12!러'), PasswordStatus.disallowedChar);
  });

  test('허용 문자 검사가 길이 검사보다 먼저다', () {
    // 한글을 친 사람에게 "6자 이상이어야 해요"부터 말하면 한글을 더 치게 된다.
    // 짧든 길든 **치는 방식이 틀렸다는 것**을 먼저 알린다.
    expect(PasswordRule.of('러너'), PasswordStatus.disallowedChar);
    expect(
      PasswordRule.of('러너러너러너러너러너러너러너러너러너'),
      PasswordStatus.disallowedChar,
    );
  });

  test('허용 문자만 쓰면 길이·종류 판정으로 넘어간다', () {
    // 허용 문자 검사가 앞으로 왔다고 뒤의 검사가 가려지면 안 된다.
    expect(PasswordRule.of('ab!'), PasswordStatus.tooShort);
    expect(PasswordRule.of('abcdef'), PasswordStatus.missingKind);
  });

  test('공백·이모지도 막는다', () {
    expect(PasswordRule.of('abc12 !'), PasswordStatus.disallowedChar);
    expect(PasswordRule.of('abc12!🏃'), PasswordStatus.disallowedChar);
  });
}
