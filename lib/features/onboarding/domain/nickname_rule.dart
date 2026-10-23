/// 닉네임 판정 결과.
///
/// `bool` 하나로 두지 않은 이유는 화면이 **왜 안 되는지**를 말해야 해서다.
/// 짧아서 막힌 것과 길어서 막힌 것은 사용자가 할 행동이 다르다.
enum NicknameStatus {
  /// 아직 아무것도 입력하지 않았다. 오류가 아니라 시작 상태다.
  empty,

  tooShort,
  tooLong,

  /// 쓸 수 없는 문자가 들어 있다. 서버 정규식과 같은 기준이다.
  invalidChars,

  valid;

  bool get isValid => this == NicknameStatus.valid;
}

/// 닉네임 규칙 — 2~16자. **서버 명세와 같은 값이다.**
///
/// 순수 Dart다. import가 하나도 없어 위젯 없이 테스트할 수 있고,
/// 나중에 서버 중복 검사가 붙어도 이 길이 규칙은 그대로 남는다.
///
/// ## 왜 글자 수를 받기만 하는가
///
/// 세는 일은 화면이 한다. 사람이 보는 글자 수는 자소(grapheme) 단위여야 하는데,
/// 그건 `characters` 패키지가 하고 그 패키지는 아직 `pubspec.yaml`에 없다.
/// 화면은 `flutter/widgets`가 재수출하는 것을 쓰면 되지만, **domain은 순수 Dart여야 해서**
/// 그 경로를 쓸 수 없다.
///
/// 중요한 건 **입력을 자르는 쪽과 세는 쪽이 같은 기준을 쓰는 것**이다.
/// 화면이 `LengthLimitingTextInputFormatter`(자소 기준)로 자르고 `.characters`로 세면
/// 상한에서 막혔는데 카운터는 하나 적게 세는 일이 생기지 않는다.
abstract final class NicknameRule {
  static const min = 2;
  static const max = 16;

  /// 서버 `OnboardRequest`와 **같은 정규식**이다.
  ///
  /// ⚠️ 백엔드가 이 규칙을 바꾸면 앱이 어긋난다. 증상은 "앱은 통과시켰는데 서버가 400"이고,
  /// 비밀번호에서 이미 겪은 문제다.
  static final _allowed = RegExp(r'^[가-힣a-zA-Z0-9_]+$');

  /// [length]는 **앞뒤 공백을 제외한 자소 개수**, [value]는 그 원문이다.
  ///
  /// 길이를 밖에서 받는 이유는 위 문단과 같다 — 자소 단위 계산은 화면의 몫이다.
  /// [value]는 정규식 검사에만 쓴다.
  static NicknameStatus of(int length, String value) {
    if (length == 0) return NicknameStatus.empty;
    if (length < min) return NicknameStatus.tooShort;
    if (length > max) return NicknameStatus.tooLong;
    // 길이를 먼저 본다. 둘 다 틀렸을 때 길이가 고치기 쉽다.
    if (!_allowed.hasMatch(value)) return NicknameStatus.invalidChars;
    return NicknameStatus.valid;
  }
}
