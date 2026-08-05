/// 비밀번호 판정 결과.
///
/// 막힌 이유마다 사용자가 할 행동이 다르다 — 짧으면 더 치고, 종류가 빠졌으면 다른 글자를 넣는다.
enum PasswordStatus {
  /// 아직 입력하지 않았다. 오류가 아니라 시작 상태다.
  empty,

  tooShort,
  tooLong,

  /// 영문·숫자·특수문자가 아닌 글자가 섞였다. 한글이 대부분이다.
  ///
  /// [missingKind]와 나눈 이유는 사용자가 할 행동이 다르기 때문이다 —
  /// 이쪽은 **치는 방식**이 틀린 것이고, 저쪽은 글자 종류를 더 넣으면 되는 것이다.
  disallowedChar,

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
/// ## ⚠️ 백엔드 규칙의 사본이되, 한 군데가 더 엄격하다
///
/// 서버 `SignUpRequest`의 `@Size` + `@Pattern`을 옮겼다.
/// 규칙을 물어볼 API가 없어서 두 곳에 같은 값이 존재한다.
/// **백엔드가 규칙을 바꾸면 여기도 바꿔야 한다** — 증상은 "앱은 통과, 서버는 400"이다.
///
/// 다만 **허용 문자는 앱이 더 좁다.** 서버 정규식의 본체는 `.{6,16}`이라 한글도 통과한다.
/// 앱은 영문·숫자·특수문자만 받는다.
///
/// 방향이 이쪽인 것은 안전하다 — 앱이 통과시킨 값은 서버도 통과한다.
/// 반대로 서버를 좁히지 않으면 **다른 클라이언트로는 한글 비밀번호를 만들 수 있고,
/// 그 계정은 이 앱의 가입 화면 기준으로는 만들 수 없는 계정이 된다.**
/// 서버 정규식 본체를 같은 문자 집합으로 좁히자고 백엔드에 요청해 둔다.
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

    // 허용 문자를 가장 먼저 본다. 한글을 친 사람에게 "6자 이상이어야 해요"부터
    // 말하면 한글을 더 치게 된다. **치는 방식이 틀렸다는 것을 먼저 알린다.**
    if (!raw.split('').every(_isAllowed)) return PasswordStatus.disallowedChar;

    // 그다음 길이. 종류를 먼저 말하면 사용자는 글자 종류를 고치고도 계속 막힌다.
    if (raw.length < min) return PasswordStatus.tooShort;
    if (raw.length > max) return PasswordStatus.tooLong;

    final hasSpecial = raw.split('').any(specials.contains);

    if (!_letter.hasMatch(raw)) return PasswordStatus.missingKind;
    if (!_digit.hasMatch(raw)) return PasswordStatus.missingKind;
    if (!hasSpecial) return PasswordStatus.missingKind;

    return PasswordStatus.valid;
  }

  /// 글자 하나가 쓸 수 있는 것인가.
  ///
  /// 종류 검사와 **같은 판정 세 개**를 쓴다. 여기만 따로 정규식을 두면
  /// "허용은 되는데 종류로는 안 세지는" 글자가 생겨 아무리 쳐도 통과하지 못한다.
  ///
  /// 이모지는 UTF-16 서러게이트 쌍이라 [String.split]이 반쪽으로 쪼갠다.
  /// 반쪽은 어느 판정에도 걸리지 않아 자연히 막힌다.
  static bool _isAllowed(String ch) =>
      _letter.hasMatch(ch) || _digit.hasMatch(ch) || specials.contains(ch);
}
