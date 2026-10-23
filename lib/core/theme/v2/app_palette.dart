import 'package:flutter/painting.dart';

/// 새 디자인의 원색 — 시안 `162:4905` `Color`.
///
/// ## 이건 시맨틱이 아니다
///
/// 여기 있는 것은 **이름 붙은 물감**이다. "배경은 무슨 색인가"는
/// `AppColorsV2`가 테마별로 정한다. 화면은 이 파일을 직접 읽지 않는다.
///
/// ## 중립 11단만 Figma 변수다
///
/// 시안은 이 램프만 변수로 묶어 뒀다(`--primary-100-f5f5f5` 꼴이라 변수
/// 이름에 값이 박혀 있다). 나머지는 전부 하드코딩 hex라, 값이 바뀌면
/// 시안을 다시 읽어 여기를 고쳐야 한다. 자동으로 따라오지 않는다.
abstract final class AppPaletteV2 {
  static const neutral50 = Color(0xFFFAFAFA);
  static const neutral100 = Color(0xFFF5F5F5);
  static const neutral200 = Color(0xFFE6E6E6);
  static const neutral300 = Color(0xFFD6D6D6);
  static const neutral400 = Color(0xFFA5A5A5);
  static const neutral500 = Color(0xFF767676);
  static const neutral600 = Color(0xFF575757);
  static const neutral700 = Color(0xFF434343);
  static const neutral800 = Color(0xFF292929);
  static const neutral900 = Color(0xFF171717);
  static const neutral950 = Color(0xFF0A0A0A);

  /// 하단 탭의 켜진 아이콘, 주 버튼. 시안에서 이름 없는 군의 50이다.
  static const brand = Color(0xFF227DFF);

  /// 같은 군의 100. 어두운 배경 위에서 브랜드색 면으로 쓴다.
  static const brandDeep = Color(0xFF202B43);

  /// 가장 밝은 끝. [neutral50]보다 한 칸 더 나간 값이다.
  ///
  /// 시안이 러닝 종료 요약의 큰 수치(`158:3775`)에만 `text-white`를 쓴다.
  /// 나머지 글자는 전부 [neutral50]이다 — **한 화면에서 제일 먼저 읽혀야
  /// 하는 숫자 하나**를 위한 값이다.
  static const white = Color(0xFFFFFFFF);

  /// 가장 어두운 끝. 밝은 테마에서 [white]와 짝이 된다.
  static const black = Color(0xFF000000);

  /// 카카오의 노랑. 시안 `158:2946`의 간편 로그인 타일 바탕이다.
  ///
  /// ⚠️ **우리 색이 아니다.** 카카오가 정한 값이라 테마가 바뀌어도 이 값이다 —
  /// 다크·라이트에서 갈리는 [AppColorsV2]에 두지 않고 팔레트에 둔다.
  /// 같은 이유로 구글 타일의 바탕은 [neutral50]이 아니라 흰색 계열 고정값이다.
  static const kakaoYellow = Color(0xFFFFE600);

  /// 본문 글자. 시안이 `--label/normal`로 쓰는 값이다.
  ///
  /// [neutral900]과 두 자리만 다르다(`171717` / `171719`). 시안이 둘을 따로
  /// 두고 있어 그대로 옮긴다 — 글자에는 이쪽, 면에는 저쪽이다.
  static const label = Color(0xFF171719);
}
