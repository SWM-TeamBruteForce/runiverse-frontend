/// 이메일 판정 결과.
///
/// `bool` 하나로 두지 않은 이유는 **비어 있는 것과 잘못 쓴 것이 다르기 때문**이다.
/// 화면을 열자마자 빨간 글씨가 뜨면 아직 아무것도 안 했는데 혼난 것처럼 보인다.
enum EmailStatus {
  /// 아직 입력하지 않았다. 오류가 아니라 시작 상태다.
  empty,

  invalid,
  valid;

  bool get isValid => this == EmailStatus.valid;
}

/// 이메일 형태 규칙.
///
/// 순수 Dart다. import가 하나도 없어 위젯 없이 테스트할 수 있다.
///
/// ## 느슨하게 본다
///
/// RFC 5322를 그대로 구현하지 않는다. 그 정규식은 아무도 못 읽고, 통과해도 실제로
/// 메일이 가는지는 여전히 모른다. **화면이 할 일은 명백한 미완성 입력을 되돌리는 것**이고
/// 진짜 판정은 서버가 한다.
///
/// ## ASCII만 받는다
///
/// 한글이 섞인 주소를 막는 것이 이 규칙의 실질적인 쓸모다.
/// **한/영을 깜빡하고 친 입력**(`ㄱㅕㅜㅜㄷㄱ@...`)이 통과하면 로그인 버튼이 켜지고,
/// 사용자는 눌러본 뒤에야 틀린 것을 안다. 치는 동안 잡아준다.
///
/// 한글 도메인(`example.한국`)은 실재하지만 그 주소로 메일을 받는 사람은 사실상 없다.
/// 그런 사용자가 나타나면 그때 연다.
abstract final class EmailRule {
  /// `로컬@도메인.TLD`
  ///
  /// 세 조각으로 읽는다.
  /// - `[A-Za-z0-9._%+-]+` 로컬 — Gmail의 `+태그`와 점을 허용한다
  /// - `[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?` 도메인 — **영숫자로 시작하고 끝난다.**
  ///   그래서 `-b.com`(하이픈 시작)과 `b..com`(점 연속)이 막힌다
  /// - `\.[A-Za-z]{2,}` TLD — **2글자 이상.** `.co` `.io` `.kr`은 실재하므로 통과시키고,
  ///   1글자 TLD는 존재하지 않으므로 막는다
  static final _shape = RegExp(
    r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,}$',
  );

  static EmailStatus of(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return EmailStatus.empty;
    return _shape.hasMatch(value) ? EmailStatus.valid : EmailStatus.invalid;
  }
}
