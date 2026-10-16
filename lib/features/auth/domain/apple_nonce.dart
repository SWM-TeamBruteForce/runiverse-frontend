import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:runiverse/features/auth/domain/code_verifier.dart';

/// 애플 로그인 한 번에 쓰는 nonce. **원본과 해시를 한 묶음으로 들고 있다.**
///
/// ## ⚠️ 애플에는 해시를, 서버에는 원본을 보낸다
///
/// 둘을 바꿔 보내면 **앱에서는 아무 일도 없고 서버가 401을 돌려준다.** 애플은
/// 받은 문자열을 그대로 ID 토큰에 박아 주므로 원본을 넘겨도 로그인은 성공하고,
/// 그 토큰을 받은 서버가 원본을 해시해 대조할 때 비로소 어긋난다
/// (연동 가이드 5절의 첫 번째 증상).
///
/// 따로 들고 다니면 그 실수를 할 자리가 생긴다. 한 묶음으로 만들어 두면
/// [raw]와 [hashed] 중 어느 쪽을 쓰는지 부르는 자리에서 드러난다 —
/// 카카오의 `OauthCode`가 코드와 검증값을 묶어 둔 것과 같은 판단이다.
///
/// ## 로그인마다 새로 만든다
///
/// nonce 가 막는 것은 **재사용**이다. 한 번 가로챈 ID 토큰을 다시 보내도
/// 서버가 그때의 원본을 모르니 통과하지 못한다. 값을 재활용하면 그 보호가
/// 사라지므로 캐시하지 않는다.
class AppleNonce {
  const AppleNonce._(this.raw, this.hashed);

  /// ⚠️ **부를 때마다 다른 값이 나온다.** `CodeVerifier`를 쓰는 이유는
  /// `Random.secure()`와 안전한 길이 선택이 이미 거기 있어서다 — 예측 가능한
  /// 난수를 쓰면 nonce 가 막으려던 것을 막지 못한다.
  factory AppleNonce.generate() {
    final raw = CodeVerifier.generate();
    return AppleNonce._(raw, hash(raw));
  }

  /// SHA-256 **소문자 hex**. 애플이 ID 토큰에 넣는 형식이고, 서버가 같은
  /// 방식으로 계산해 대조한다(연동 가이드 2절).
  ///
  /// `Digest.toString()`이 소문자 hex 를 준다. 대문자로 보내면 서버의 비교가
  /// 어긋나 401이 된다.
  static String hash(String raw) => sha256.convert(utf8.encode(raw)).toString();

  /// 서버에 보내는 값.
  final String raw;

  /// 애플에 넘기는 값.
  final String hashed;
}
