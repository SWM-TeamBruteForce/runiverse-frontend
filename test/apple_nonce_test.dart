import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/auth/domain/apple_nonce.dart';

/// 애플 nonce — **해시가 서버의 계산과 같은 모양인가.**
///
/// ## ⚠️ 왜 이것부터 지키는가
///
/// nonce 가 어긋나면 **앱에서는 아무 증상이 없다.** 애플은 받은 문자열을
/// 그대로 ID 토큰에 박아 주므로 로그인 창은 정상적으로 닫히고, 그 토큰을 받은
/// 서버가 원본을 해시해 대조할 때 비로소 401이 난다. 연동 가이드 5절이 "토큰은
/// 받았는데 서버가 401을 준다"의 원인으로 가장 먼저 꼽는 것이 이것이다.
///
/// 기기에서는 나중에야, 그것도 서버 응답으로만 드러나므로 여기서 잡는다.
void main() {
  test('⚠️ 해시는 SHA-256 소문자 hex 다', () {
    // RFC 6234 의 알려진 벡터. 우리 구현이 아니라 **표준과 맞추는 것**이라
    // 서버가 무엇으로 계산하든 같은 값이 나온다.
    expect(
      AppleNonce.hash('abc'),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  test('⚠️ 대문자가 섞이지 않는다', () {
    // 대문자 hex 를 보내면 서버의 문자열 비교가 어긋나 401이 된다.
    final hashed = AppleNonce.generate().hashed;

    expect(hashed, hashed.toLowerCase());
    expect(hashed, matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('⚠️ 애플에 넘기는 값과 서버에 보내는 값이 다르다', () {
    // 둘이 같아지면 해시를 건너뛴 것이다 — 서버가 해시해서 대조하므로
    // 원본을 두 번 보내면 통과하지 못한다.
    final nonce = AppleNonce.generate();

    expect(nonce.hashed, isNot(nonce.raw));
    expect(nonce.hashed, AppleNonce.hash(nonce.raw));
  });

  test('⚠️ 로그인마다 새 값이다', () {
    // 값을 재활용하면 nonce 가 막으려던 재전송을 막지 못한다.
    final raws = {for (var i = 0; i < 50; i++) AppleNonce.generate().raw};

    expect(raws, hasLength(50));
  });
}
