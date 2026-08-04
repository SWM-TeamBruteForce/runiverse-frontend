/// 비밀번호 판정 결과.
///
/// 막힌 이유마다 사용자가 할 행동이 다르다 — 짧으면 더 치고, 종류가 빠졌으면 다른 글자를 넣는다.
enum PasswordStatus {
  /// 아직 입력하지 않았다. 오류가 아니라 시작 상태다.
  empty,

  tooShort,
  tooLong,

  /// 영문·숫자·특수문자 중 빠진 것이 있다.
  ///
  /// 셋을 나누지 않은 이유는, 무엇이 빠졌는지 하나씩 알려주면 문구가 세 번 바뀌면서
  /// 사용자가 규칙 전체를 파악하지 못하기 때문이다. 규칙 한 줄을 통째로 보여준다.
  missingKind,

  valid;

  bool get isValid => this == PasswordStatus.valid;
}

/// 비밀번호 규칙 — 6~16자, 영문·숫자·특수문자 각 1개 이상.
///
/// ## ⚠️ 이것은 백엔드 규칙의 사본이다
///
/// 서버 `SignUpRequest`의 `@Size` + `@Pattern`을 그대로 옮겼다.
/// 규칙을 물어볼 API가 없어서 두 곳에 같은 값이 존재한다.
/// **백엔드가 규칙을 바꾸면 여기도 바꿔야 한다** — 증상은 "앱은 통과, 서버는 400"이다.
///
/// ## 길이는 코드 단위로 센다
///
/// 서버 `@Size`는 Java `String.length()`(UTF-16 코드 단위)를 센다. Dart의 `String.length`도
/// 같은 단위라 **두 쪽이 같은 수를 센다.** 자소(grapheme)로 세면 오히려 어긋난다.
abstract final class PasswordRule {
  static const min = 6;
  static const max = 16;

  /// 백엔드 정규식의 특수문자 집합을 그대로 옮겼다. 순서까지 같게 뒀다 — 대조하기 쉽게.
  static const specials = r'''!@#$%^&*()_+-={}[]:;"'<>,.?/\|`~''';

  static final _letter = RegExp(r'[A-Za-z]');
  static final _digit = RegExp(r'\d');

  static PasswordStatus of(String raw) {
    if (raw.isEmpty) return PasswordStatus.empty;

    // 길이를 먼저 본다. 둘 다 틀렸을 때 종류부터 말하면
    // 사용자는 글자 종류를 고치고도 계속 막힌다.
    if (raw.length < min) return PasswordStatus.tooShort;
    if (raw.length > max) return PasswordStatus.tooLong;

    final hasSpecial = raw.split('').any(specials.contains);

    if (!_letter.hasMatch(raw)) return PasswordStatus.missingKind;
    if (!_digit.hasMatch(raw)) return PasswordStatus.missingKind;
    if (!hasSpecial) return PasswordStatus.missingKind;

    return PasswordStatus.valid;
  }
}
