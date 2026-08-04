/// 닉네임 판정 결과.
///
/// `bool` 하나로 두지 않은 이유는 화면이 **왜 안 되는지**를 말해야 해서다.
/// 짧아서 막힌 것과 길어서 막힌 것은 사용자가 할 행동이 다르다.
enum NicknameStatus {
  /// 아직 아무것도 입력하지 않았다. 오류가 아니라 시작 상태다.
  empty,

  tooShort,
  tooLong,
  valid;

  bool get isValid => this == NicknameStatus.valid;
}

/// 닉네임 규칙 — 2~12자.
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
/// 12자에서 막혔는데 카운터는 11이라고 하는 일이 생기지 않는다.
abstract final class NicknameRule {
  static const min = 2;
  static const max = 12;

  /// [length]는 **앞뒤 공백을 제외한 자소 개수**다.
  static NicknameStatus of(int length) {
    if (length == 0) return NicknameStatus.empty;
    if (length < min) return NicknameStatus.tooShort;
    if (length > max) return NicknameStatus.tooLong;
    return NicknameStatus.valid;
  }
}
