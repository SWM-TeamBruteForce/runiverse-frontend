import 'package:flutter/painting.dart';

/// 새 디자인의 모서리.
///
/// ## 재수출이 아니라 실물이다
///
/// 처음에는 기존 값을 그대로 재수출했다. 시안에 반경 정의 시트가 없어서
/// 지어낼 근거가 없었기 때문이다.
///
/// 첫 화면(`158:3415` 매칭 대기방)을 옮기면서 **20이 필요해졌다** — 카드가
/// `rounded-[20px]`인데 기존 스케일은 16 다음이 24다. 그래서 여기서 실제
/// 값을 든다. 나머지는 시안과 맞는 것을 확인하고 그대로 옮겼다.
///
/// | 이름 | 값 | 시안에서 확인한 자리 |
/// |---|---|---|
/// | [md] | 12 | 매칭대기중 배지(`158:2976`) |
/// | [lg] | 16 | 하단 버튼(`158:3433`) |
/// | [card] | 20 | 시작 시간·목표 거리 카드(`158:3425`) |
/// | [full] | — | 알약 배지(`158:3420`, 시안은 37) · 아바타 |
///
/// [sm]과 [xl]은 아직 시안에서 확인하지 못했다. 기존 값을 그대로 둔다.
abstract final class AppRadius {
  static const sm = BorderRadius.all(Radius.circular(8));
  static const md = BorderRadius.all(Radius.circular(12));
  static const lg = BorderRadius.all(Radius.circular(16));

  /// 카드. 기존 스케일에 없던 값이라 이름을 따로 줬다.
  static const card = BorderRadius.all(Radius.circular(20));

  static const xl = BorderRadius.all(Radius.circular(24));

  /// 알약·원형. 시안의 `37`이나 `100`은 전부 "끝까지 둥글게"라는 뜻이다.
  static const full = BorderRadius.all(Radius.circular(999));
}
