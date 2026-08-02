import 'package:flutter/painting.dart';

/// 러닝 색 참조 팔레트 — 디자인 시스템 v1.1 §5-2. **10 hue × 3 shade = 30색.**
///
/// ## 이건 테마가 아니다
///
/// [AppColors]와 성격이 다르다. 시맨틱 색은 화면당 한 벌이지만 러닝 색은
/// **한 화면에 여러 개가 동시에 뜬다**(컬렉션 그리드는 30색을 한 번에 그린다).
/// 그래서 `ThemeExtension`에 넣지 않고 **위젯 파라미터로 전달한다.**
/// 다크/라이트에 따라 바뀌지도 않는다 — 획득한 색은 테마와 무관하게 그 색이다.
///
/// 색값을 여기 두는 이유는 하나다. `Color(0x...)` 리터럴은
/// `core/theme/tokens/` 안에서만 허용된다(CLAUDE.md). `domain/`은 순수 Dart여야 해서
/// [Color]를 들 수 없다. **지표→hue 매핑 같은 도메인 로직은 `features/color/domain/`이**
/// 맡고, 그쪽은 [RunHue]만 다루면 된다.
///
/// ## shade는 전 hue 3개로 균일하다
///
/// v1의 3~4개 혼재는 컬렉션 그리드를 불규칙하게 만들고 달성률 분모를 설명하기
/// 어려웠다. 3개 균일이라야 2×5 그리드와 30색 분모가 동시에 성립한다.
/// **`shade` 개수를 hue마다 다르게 만들지 않는다.**
///
/// ## 폐기된 hue 2개
///
/// `균일페이스`(시안)는 속도·지구력과 지표가 겹쳐 제거됐고,
/// `마일스톤`(골드)은 성격이 다른 축이라 별도 기능으로 분리됐다.
/// 옛 코드나 Figma에서 이 이름을 보면 낡은 것이다.
enum RunHue {
  /// 거리 · 틸 — 3km / 7km / 하프 완주
  distance,

  /// 속도 · 레드오렌지 — 6'00" / 5'30" / 5'00" 페이스
  speed,

  /// 지구력 · 블루 — 40 / 70 / 100분 연속
  endurance,

  /// 꾸준함 · 그린 — 3 / 7 / 14일 연속
  consistency,

  /// 케이던스 · 바이올렛 — 160 / 170 / 180 spm
  cadence,

  /// 인터벌 · 마젠타 — 인터벌 1 / 5 / 10회
  interval,

  /// 언덕 · 앰버 — 누적 상승 100 / 300 / 600m
  hills,

  /// 회복 · 민트 — 회복주 1 / 5 / 10회
  recovery,

  /// 동행 · 코럴 — 매칭 1 / 5 / 10회
  company,

  /// 악조건극복 · 슬레이트인디고 — 우천 / 영하 / 혹서 러닝
  adversity,
}

/// [RunHue]에서 실제 색을 꺼낸다.
abstract final class RunPalette {
  /// hue마다 shade 3개. 순서는 얕은 것 → 깊은 것이다.
  static const _shades = <RunHue, List<Color>>{
    RunHue.distance: [Color(0xFF73DDD3), Color(0xFF42DCCC), Color(0xFF21CAB9)],
    RunHue.speed: [Color(0xFFE7836A), Color(0xFFE95834), Color(0xFFD93912)],
    RunHue.endurance: [Color(0xFF6F8AE2), Color(0xFF3C62E2), Color(0xFF1A45D1)],
    RunHue.consistency: [
      Color(0xFF76DAA8),
      Color(0xFF46D78F),
      Color(0xFF26C575),
    ],
    RunHue.cadence: [Color(0xFF9475DC), Color(0xFF7144D9), Color(0xFF5423C7)],
    RunHue.interval: [Color(0xFFDD73B3), Color(0xFFDC429E), Color(0xFFCA2186)],
    RunHue.hills: [Color(0xFFE0AC71), Color(0xFFDF943F), Color(0xFFCD7B1D)],
    RunHue.recovery: [Color(0xFF80D1B9), Color(0xFF54C9A6), Color(0xFF35B68F)],
    RunHue.company: [Color(0xFFE28D6F), Color(0xFFE2683C), Color(0xFFD14B1A)],
    RunHue.adversity: [Color(0xFF8990C7), Color(0xFF626BBC), Color(0xFF444EA7)],
  };

  /// 전 hue 공통 shade 개수.
  static const shadeCount = 3;

  /// [hue]의 shade 3개. 얕은 것부터.
  static List<Color> shadesOf(RunHue hue) => _shades[hue]!;

  /// [hue]의 [shade]번 색. **`shade`는 1부터 3까지다** — 문서 표기와 맞췄다.
  static Color color(RunHue hue, int shade) {
    assert(
      shade >= 1 && shade <= shadeCount,
      'shade는 1~$shadeCount다. 0부터 세지 않는다. 받은 값: $shade',
    );
    return _shades[hue]![shade - 1];
  }
}
