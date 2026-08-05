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
abstract final class EmailRule {
  /// `무언가@무언가.무언가` — 공백과 두 번째 `@`를 막는다.
  static final _shape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static EmailStatus of(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return EmailStatus.empty;
    return _shape.hasMatch(value) ? EmailStatus.valid : EmailStatus.invalid;
  }
}
