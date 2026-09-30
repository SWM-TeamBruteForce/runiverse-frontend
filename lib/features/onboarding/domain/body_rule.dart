/// 생년월일·키·몸무게를 **친 글자에서** 읽고 걸러낸다.
///
/// ## 왜 생겼나
///
/// 프로필 등록이 고르는 화면에서 **치는 화면**으로 바뀌었다(2026-09-30, 시안
/// `158:2758`). 휠로 고를 때는 만들 수 없던 값이 칠 때는 만들어진다 —
/// 키 700cm, 2월 31일 같은 것들이다. 휠이 하던 일을 여기가 대신한다.
///
/// ## ⚠️ 나이는 여기서 보지 않는다
///
/// 만 14세 하한은 [AgeRule]이 이미 갖고 있다. 여기에 다시 적으면 두 군데가
/// 갈리고, 그때 프로필 **수정** 화면과 어긋난다.
///
/// 이 클래스가 보는 것은 **날짜가 실재하는가**와 **범위 안인가**뿐이다.
abstract final class BodyRule {
  const BodyRule._();

  /// 옛 휠이 보여주던 키의 범위. 바꾸려면 프로필 수정 화면도 같이 본다.
  static const minHeight = 130;
  static const maxHeight = 210;

  /// 옛 휠이 보여주던 몸무게의 범위.
  static const minWeight = 30;
  static const maxWeight = 140;

  /// 옛 휠의 연도 아래 끝이 `now.year - 80`이었다.
  static const maxAge = 80;

  /// 생년월일 입력 자릿수. `19990116` 꼴이다.
  static const birthDigits = 8;

  /// `yyyyMMdd` 여덟 자리를 날짜로 읽는다. 읽을 수 없으면 `null`.
  ///
  /// ## ⚠️ 달에 없는 날을 반드시 걸러낸다
  ///
  /// `DateTime(1999, 2, 31)`은 예외를 던지지 않고 **3월 3일로 넘어간다.**
  /// 조용히 다른 날이 되는 쪽이 거절하는 쪽보다 나쁘다 — 만들어 놓고
  /// 되읽어서 같은 날인지 확인한다.
  static DateTime? parseBirth(String text) {
    if (text.length != birthDigits) return null;
    // ⚠️ `int.tryParse`로만 거르면 부호가 통과한다 — `-9990116`이 연도 -999로
    // 읽힌다. 숫자만 있는지 직접 본다.
    if (!_digitsOnly(text)) return null;

    final year = int.parse(text.substring(0, 4));
    final month = int.parse(text.substring(4, 6));
    final day = int.parse(text.substring(6, 8));
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;

    final date = DateTime(year, month, day);
    // 넘어갔으면 없는 날이다.
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  /// 아직 오지 않은 날인가.
  ///
  /// [AgeRule]에도 걸리지만 그때 나오는 말은 "너무 어려요"다. 미래 날짜에
  /// 그 문구를 보이면 무엇이 잘못됐는지 알 수 없다.
  static bool isFutureBirth(DateTime birth, {required DateTime now}) =>
      birth.isAfter(DateTime(now.year, now.month, now.day));

  /// 옛 휠이 보여주던 범위보다 오래됐는가.
  static bool isTooOldBirth(DateTime birth, {required DateTime now}) =>
      birth.year < now.year - maxAge;

  static bool isAllowedHeight(int cm) => cm >= minHeight && cm <= maxHeight;

  static bool isAllowedWeight(int kg) => kg >= minWeight && kg <= maxWeight;

  /// 친 글자를 정수로. 숫자만 있어야 한다.
  ///
  /// `17.5`나 `17o`는 읽지 않는다 — 자판을 숫자로 묶어도 붙여넣기로 들어온다.
  /// 앞에 0이 붙은 `0175`는 읽는다. 자판에서 흔히 만들어지고 막을 이유가 없다.
  static int? parseNumber(String text) {
    if (text.isEmpty || !_digitsOnly(text)) return null;
    return int.tryParse(text);
  }

  /// `0`~`9`만 있는가. 부호·소수점·공백을 전부 걸러낸다.
  static bool _digitsOnly(String text) {
    for (final unit in text.codeUnits) {
      if (unit < 0x30 || unit > 0x39) return false;
    }
    return true;
  }
}
