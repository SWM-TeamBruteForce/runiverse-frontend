/// 러너의 페이스 등급.
///
/// 숫자(초/km)를 그대로 들고 다니지 않고 등급으로 한 번 접는 이유는, 이 값을 읽는 쪽이
/// **숫자가 아니라 구간**을 원해서다. 시그니처 컬러는 등급마다 hue가 다르고
/// (입문 민트 / 중급 딥블루 / 숙련 선셋레드 / 미정 코럴), 홈의 연습 유도도 구간으로 갈린다.
enum PaceLevel {
  beginner,
  intermediate,
  advanced,

  /// 아직 재보지 않았다. **모른다는 것도 정보다** — 숨기거나 기본값으로 때우지 않는다.
  unmeasured;

  /// 홈에서 '혼자 연습하기'를 권할 대상인가.
  ///
  /// 미측정도 포함한다. 재본 적 없는 사람이야말로 한 번 뛰어봐야 하는 쪽이고,
  /// 그 결과가 이 값을 채운다.
  bool get needsPracticeNudge =>
      this == PaceLevel.beginner || this == PaceLevel.unmeasured;
}

/// 5km 기준 페이스 규칙 — 1km를 몇 분 몇 초에 뛰는가.
///
/// 순수 Dart다. import가 없어 위젯 없이 테스트할 수 있다.
///
/// ## 왜 5초 단위인가
///
/// 스스로 신고하는 값이라 1초 단위 정확도는 의미가 없다. 5초 단위면 휠에 12칸만 있으면 되고
/// (59칸이면 한참 굴려야 한다), 구간 판정에도 영향이 없다.
abstract final class PaceRule {
  /// 휠에 올릴 분 범위. 3분/km 아래는 세계기록권, 12분/km 위는 걷기에 가깝다.
  static const minMinutes = 3;
  static const maxMinutes = 12;

  static const secondStep = 5;

  /// ⚠️ 경계값은 **내가 정한 값이다.** 아마추어 5km 기록을 기준으로 잡았다 —
  /// 5분/km면 5km 25분, 6분 30초/km면 32분 30초. 디자인·기획 확인이 필요하다.
  static const advancedBelow = 5 * 60; // 5'00"/km
  static const intermediateBelow = 6 * 60 + 30; // 6'30"/km

  /// [secondsPerKm]가 `null`이면 [PaceLevel.unmeasured].
  static PaceLevel levelOf(int? secondsPerKm) {
    if (secondsPerKm == null) return PaceLevel.unmeasured;
    if (secondsPerKm < advancedBelow) return PaceLevel.advanced;
    if (secondsPerKm < intermediateBelow) return PaceLevel.intermediate;
    return PaceLevel.beginner;
  }

  /// 휠이 돌려준 분·초를 초로 합친다.
  static int toSeconds(int minutes, int seconds) => minutes * 60 + seconds;
}
