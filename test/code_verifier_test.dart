import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/auth/domain/code_verifier.dart';

/// PKCE 검증값 — 순수 계산 로직.
///
/// 값 자체는 무작위라 결과를 못 박을 수 없다. 대신 **규격을 지키는지**와
/// **매번 다른지**를 본다. 이 둘이 깨지면 PKCE가 막으려던 것을 막지 못한다.
void main() {
  test('RFC 7636이 정한 길이 안에 든다', () {
    // 43자 미만이면 추측할 수 있고, 128자를 넘으면 인가 서버가 거절한다.
    final value = CodeVerifier.generate();

    expect(value.length, greaterThanOrEqualTo(43));
    expect(value.length, lessThanOrEqualTo(128));
  });

  test('허용된 문자만 쓴다', () {
    // unreserved = ALPHA / DIGIT / "-" / "." / "_" / "~"
    // 다른 문자가 섞이면 URL 인코딩 단계에서 값이 달라져,
    // 서버가 보내는 검증값과 카카오가 기억하는 해시가 어긋난다.
    for (var i = 0; i < 20; i++) {
      expect(CodeVerifier.generate(), matches(RegExp(r'^[A-Za-z0-9\-._~]+$')));
    }
  });

  test('부를 때마다 다른 값이 나온다', () {
    // 같은 값이 반복되면 인가 코드를 가로챈 쪽이 검증값도 알게 된다.
    final values = List.generate(100, (_) => CodeVerifier.generate());

    expect(values.toSet(), hasLength(100));
  });
}
