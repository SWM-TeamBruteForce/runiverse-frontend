/// 만 나이와 가입 하한.
///
/// ## 왜 만 14세인가
///
/// 만 14세 미만은 **법정대리인 동의 없이 개인정보를 처리할 수 없다.** 동의를
/// 받는 흐름을 만들지 않기로 해서 아예 받지 않는다. 서버도 같은 기준으로
/// `POST /users/me/onboarding`과 `PATCH /users/me/profile`에서 막는다.
///
/// ## ⚠️ 연도만 봐서는 안 된다
///
/// 같은 해에 태어나도 갈린다. 2026년 기준 2012년 1월생은 만 14세라 통과해야
/// 하고, 2012년 12월생은 아직 만 13세라 막아야 한다. 그래서 휠은 연도까지만
/// 좁히고(`latestYear`), 실제 판정은 [isAllowed]가 월·일까지 본다.
///
/// `now.year - 15`로 좁히면 반대로 **정상적인 만 14세를 막는다.**
///
/// ## 앱도 막는다
///
/// 서버가 400으로 거절하지만 그 메시지는 화면에 닿지 않는다. 앱이 먼저 막지
/// 않으면 사용자는 왜 넘어가지 않는지 알 수 없다.
abstract final class AgeRule {
  const AgeRule._();

  /// 가입할 수 있는 가장 어린 만 나이.
  static const minimum = 14;

  /// 생일이 지났는지까지 반영한 **만 나이**.
  ///
  /// [now]를 받는 이유는 테스트가 시간을 고정해야 경계를 검증할 수 있어서다.
  /// 안에서 `DateTime.now()`를 부르면 생일 당일 같은 경우를 시험할 수 없다.
  static int ageOn(DateTime birth, {required DateTime now}) {
    var age = now.year - birth.year;
    // 올해 생일이 아직 안 왔으면 한 살 뺀다.
    if (now.month < birth.month ||
        (now.month == birth.month && now.day < birth.day)) {
      age--;
    }
    return age;
  }

  /// 가입·수정할 수 있는 생년월일인가.
  static bool isAllowed(DateTime birth, {required DateTime now}) =>
      ageOn(birth, now: now) >= minimum;

  /// 생년월일 휠이 보여줄 **가장 늦은 연도**.
  ///
  /// 이 연도에도 [isAllowed]가 `false`인 날이 섞여 있다 — 아직 생일이 안 지난
  /// 사람이다. 휠에서 고를 수는 있고, 고른 뒤에 걸린다. 연도를 한 해 더
  /// 좁히면 같은 해 생일이 지난 만 14세까지 함께 막힌다.
  static int latestYear(DateTime now) => now.year - minimum;
}
