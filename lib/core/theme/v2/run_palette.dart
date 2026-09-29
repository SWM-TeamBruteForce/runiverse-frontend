import 'package:flutter/painting.dart';
import 'package:runiverse/core/theme/tokens/run_palette.dart';

/// [RunHue] 를 함께 내보낸다.
///
/// enum 은 복제하지 않기로 했는데(아래 주석), 그러면 화면이 색을 쓰려고
/// **옛 경로를 한 줄 더 import** 하게 되고 세대 혼용 테스트가 그것을 막는다.
/// 값만 새로 들고 이름은 그대로 통과시킨다.
export 'package:runiverse/core/theme/tokens/run_palette.dart' show RunHue;

/// 새 디자인의 러닝 색 — 시안 `162:4905`의 `거리`~`악조건 극복` 10군.
///
/// ## [RunHue]는 여기서 새로 만들지 않는다
///
/// `features/color/domain/`이 그 enum을 쓴다. 두 벌이 되면 도메인이 어느 쪽을
/// 가리키는지 알 수 없어진다. **이름은 기존 것을 그대로 쓰고 값만 바꾼다.**
///
/// ## ⚠️ 색값이 통째로 달라진다
///
/// 옛 `거리`는 틸(`#42DCCC`), 새 `거리`는 파랑(`#227DFF`)이다. 10군이 전부
/// 이렇게 바뀐다. 서버는 hue 이름만 들고 있으므로 **데이터 마이그레이션은 없고
/// 보이는 것만 바뀐다** — 이미 색을 모은 사용자에게는 같은 색이 다르게 보인다.
///
/// ## 시안의 `동맹`이 우리 [RunHue.company]다
///
/// 우리는 `동행`이라 부른다. 이름을 맞출지는 아직 정하지 않았다.
///
/// ## API를 기존 [RunPalette]와 똑같이 맞췄다
///
/// 화면을 옮길 때 **import 한 줄만** 바꾸면 되도록 하려는 것이다. 이름이
/// 다르면 화면마다 호출부를 갈아끼우는 일이 얹힌다.
abstract final class RunPaletteV2 {
  /// hue마다 shade 3개. 순서는 **얕은 것 → 깊은 것** — 기존과 같다.
  /// 시안의 200 / 100 / 50 순서다.
  static const _shades = <RunHue, List<Color>>{
    RunHue.distance: [Color(0xFF7CB5FF), Color(0xFF227DFF), Color(0xFF1556B8)],
    RunHue.speed: [Color(0xFF79E4FF), Color(0xFF18C8FF), Color(0xFF0C7899)],
    RunHue.endurance: [Color(0xFFB09CFF), Color(0xFF6F5CFF), Color(0xFF4B3899)],
    RunHue.consistency: [
      Color(0xFF79E8A8),
      Color(0xFF33D17A),
      Color(0xFF237A4A),
    ],
    RunHue.cadence: [Color(0xFFDEA2FF), Color(0xFFC05CFF), Color(0xFF743899)],
    RunHue.interval: [Color(0xFFFF91C7), Color(0xFFFF4FA3), Color(0xFF9B3266)],
    RunHue.hills: [Color(0xFFFFC278), Color(0xFFFF9F43), Color(0xFFA8642B)],
    RunHue.recovery: [Color(0xFFA0F1E1), Color(0xFF56E0C5), Color(0xFF2D8C7A)],
    RunHue.company: [Color(0xFFFFE9A8), Color(0xFFFFD36B), Color(0xFFB98A2F)],
    RunHue.adversity: [Color(0xFFFF9C9C), Color(0xFFFF5B5B), Color(0xFFB83C3C)],
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

  /// 파티원 카드·레인의 색 4벌.
  ///
  /// **기존 값을 그대로 쓴다.** 옛 팔레트가 이미 이 시안에서 가져온 값이라
  /// (`#227DFF`·`#FF4FA3`·`#33D17A`가 새 팔레트와 일치한다) 바꿀 것이 없다.
  static const _party = <Color>[
    Color(0xFF227DFF),
    Color(0xFFFF8335),
    Color(0xFFFF4FA3),
    Color(0xFF33D17A),
  ];

  /// 파티원의 색. [slot]은 `PartyBoard.colorSlotOf`가 준 자리 번호다.
  static Color lane(int slot) => _party[slot % _party.length];

  /// 러닝 색이 "발광"하는 그림자. 기존과 같다 — 시안이 글로우를 따로 정의하지
  /// 않아서 바꿀 근거가 없다.
  static List<BoxShadow> glow(Color color) => [
    BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 12),
  ];
}
