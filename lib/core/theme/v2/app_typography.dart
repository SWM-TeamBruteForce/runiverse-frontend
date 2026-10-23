import 'package:flutter/painting.dart';

/// 새 디자인의 글자 — 시안 `160:4574` `Typography`.
///
/// ## 이름을 시안 그대로 쓴다
///
/// `heading01` `body07`처럼 뜻이 없는 이름이다. 뜻을 담은 이름(`제목` `본문`)
/// 으로 바꾸면 **시안과 대조할 수 없다** — 디자이너가 "Body 07"이라고 말할 때
/// 코드에서 그것을 찾지 못한다. 31개를 다 쓰지는 않겠지만, 안 쓰는 것을
/// 지우는 것보다 이름이 어긋나는 쪽이 비싸다.
///
/// ## 행간은 배수, 자간은 픽셀이다
///
/// 시안은 둘 다 퍼센트로 적는다(`150%` `-2%`). [TextStyle.height]는 배수라
/// `150%`가 그대로 1.5지만, [TextStyle.letterSpacing]은 **논리 픽셀**이라
/// 글자 크기를 곱해야 한다. `-0.02`를 그대로 넣으면 24px 글자의 자간이
/// 0.02px이 되어 사실상 0이고, **눈으로는 안 보이고 시안과만 어긋난다.**
/// [_t]가 그 곱셈을 한다.
///
/// ## 러닝 수치에는 이걸 그대로 쓰지 않는다
///
/// 초당 여러 번 갱신되는 숫자는 `FontFeature.tabularFigures()`를 얹어야
/// 자릿수가 흔들리지 않는다. 화면에서 `copyWith`로 더한다.
abstract final class AppTypographyV2 {
  static const fontFamily = 'SUIT';

  /// [tracking]은 시안의 퍼센트다 — `-2%`면 `-0.02`.
  static TextStyle _t(
    double size,
    FontWeight weight,
    double height, [
    double tracking = 0,
  ]) => TextStyle(
    fontFamily: fontFamily,
    fontSize: size,
    fontWeight: weight,
    height: height,
    letterSpacing: size * tracking,
  );

  static final heading01 = _t(60, FontWeight.w700, 1.24);
  static final heading02 = _t(32, FontWeight.w600, 1.24);
  static final heading03 = _t(28, FontWeight.w600, 1.50);
  static final heading04 = _t(26, FontWeight.w800, 1.50);
  static final heading05 = _t(24, FontWeight.w600, 1.24);
  static final heading06 = _t(18, FontWeight.w600, 1.50);
  static final heading07 = _t(16, FontWeight.w600, 1.50);
  static final heading08 = _t(14, FontWeight.w600, 1.50);
  static final heading09 = _t(14, FontWeight.w500, 1.24);

  static final body01 = _t(24, FontWeight.w500, 1.24, -0.02);
  static final body02 = _t(20, FontWeight.w600, 1.24);
  static final body03 = _t(20, FontWeight.w600, 1.24, -0.02);
  static final body04 = _t(18, FontWeight.w500, 1.24, -0.02);
  static final body05 = _t(16, FontWeight.w600, 1.50);
  static final body06 = _t(16, FontWeight.w500, 1.50);
  static final body07 = _t(16, FontWeight.w400, 1.50);
  static final body08 = _t(16, FontWeight.w600, 1.50, -0.02);
  static final body09 = _t(16, FontWeight.w400, 1.50, -0.02);
  static final body10 = _t(14, FontWeight.w600, 1.50);
  static final body11 = _t(14, FontWeight.w500, 1.50);
  static final body12 = _t(14, FontWeight.w400, 1.50);
  static final body13 = _t(14, FontWeight.w500, 1.24);
  static final body14 = _t(14, FontWeight.w400, 1.50, -0.02);
  static final body15 = _t(13, FontWeight.w400, 1.50);
  static final body16 = _t(13, FontWeight.w500, 1.24);
  static final body17 = _t(13, FontWeight.w400, 1.24);
  static final body18 = _t(12, FontWeight.w400, 1.24);
  static final body19 = _t(12, FontWeight.w500, 1.50, -0.02);
  static final body20 = _t(12, FontWeight.w400, 1.50, -0.02);
  static final body21 = _t(12, FontWeight.w500, 1.24, -0.02);
  static final body22 = _t(12, FontWeight.w400, 1.24, -0.02);

  /// 31개 전부. 테스트가 하나도 빠뜨리지 않고 훑기 위한 것이다.
  static final all = <String, TextStyle>{
    'heading01': heading01,
    'heading02': heading02,
    'heading03': heading03,
    'heading04': heading04,
    'heading05': heading05,
    'heading06': heading06,
    'heading07': heading07,
    'heading08': heading08,
    'heading09': heading09,
    'body01': body01,
    'body02': body02,
    'body03': body03,
    'body04': body04,
    'body05': body05,
    'body06': body06,
    'body07': body07,
    'body08': body08,
    'body09': body09,
    'body10': body10,
    'body11': body11,
    'body12': body12,
    'body13': body13,
    'body14': body14,
    'body15': body15,
    'body16': body16,
    'body17': body17,
    'body18': body18,
    'body19': body19,
    'body20': body20,
    'body21': body21,
    'body22': body22,
  };
}
