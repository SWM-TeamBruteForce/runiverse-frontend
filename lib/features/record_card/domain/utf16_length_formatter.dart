import 'package:flutter/services.dart';

/// 입력을 **UTF-16 코드 단위**로 센다.
///
/// ## ⚠️ `LengthLimitingTextInputFormatter`를 쓸 수 없는 자리
///
/// 그쪽은 **grapheme(사람이 보는 글자)**로 센다. 이모지 하나가 코드 단위로는
/// 둘이라, 이모지 600개는 포매터에 600으로 읽히고 **서버에는 1,200으로
/// 간다** — 칸은 통과시키고 서버가 `400`으로 거절한다. 거절당하는 자리가
/// 저장 버튼이라, 그때는 쓴 글을 되돌릴 길이 없다.
///
/// 서버가 `String.length`로 세므로(연동 가이드 3절) 여기도 그렇게 센다. 세는
/// 칸(`0/1000`)도 같은 값을 보여 **보이는 수와 막히는 수가 같아진다.**
///
/// ## ⚠️ 서로게이트 쌍을 가르지 않는다
///
/// 상한에서 그냥 자르면 이모지 한 글자의 반쪽만 남아 서버로 `U+FFFD`가 간다.
/// 넘치면 **그 글자를 통째로 버린다.**
class Utf16LengthFormatter extends TextInputFormatter {
  const Utf16LengthFormatter(this.maxLength);

  /// UTF-16 코드 단위 상한.
  final int maxLength;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.length <= maxLength) return newValue;

    final kept = StringBuffer();
    var length = 0;
    // 글자(rune) 단위로 담는다 — 코드 단위로 자르면 쌍이 갈라진다.
    for (final rune in newValue.text.runes) {
      final one = String.fromCharCode(rune);
      if (length + one.length > maxLength) break;
      kept.write(one);
      length += one.length;
    }

    final text = kept.toString();
    return TextEditingValue(
      text: text,
      // 커서를 끝에 둔다. 넘쳐서 잘린 뒤라 들고 있던 자리가 의미를 잃는다.
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
