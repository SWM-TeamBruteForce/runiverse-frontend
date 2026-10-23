import 'package:flutter/painting.dart';

/// 원시 색값(팔레트) — 디자인 시스템 v1.1 §1.
///
/// **이 파일은 프로젝트에서 `Color(0x...)` 리터럴이 허용되는 유일한 곳이다.**
/// 화면 코드는 이 값을 직접 쓰지 않고 `context.appColors`(시맨틱 토큰)를 통해 접근한다.
/// 팔레트를 직접 참조하면 다크/라이트 대칭이 깨진다.
///
/// 러닝에서 파생되는 고유 색(30색 참조 팔레트)은 여기 없다.
/// 그것은 테마가 아니라 데이터이므로 `features/color/`가 소유한다.
abstract final class AppPalette {
  // ── Dark (기본 테마) ─────────────────────────────────────────

  /// 최하단 배경(스크롤 뒤).
  static const darkBgBase = Color(0xFF0B0E14);

  /// 카드·시트 기본 면.
  static const darkBgSurface = Color(0xFF141924);

  /// 떠 있는 면(모달·팝오버). 다크에서는 그림자 대신 면 밝기로 높이를 표현한다.
  static const darkBgElevated = Color(0xFF1C2230);

  /// 모달 뒤 딤. rgba(0,0,0,0.60)
  static const darkBgScrim = Color(0x99000000);

  static const darkBorderDefault = Color(0xFF2A3140);
  static const darkBorderStrong = Color(0xFF3A4356);

  static const darkTextPrimary = Color(0xFFF5F7FA);
  static const darkTextSecondary = Color(0xFFAEB7C5);
  static const darkTextTertiary = Color(0xFF7E8798);
  static const darkTextDisabled = Color(0xFF4A5261);

  /// 프라이머리 면 위에 얹는 라벨.
  static const darkTextOnPrimary = Color(0xFF0B0E14);

  // ── Light (완전 대칭) ────────────────────────────────────────

  static const lightBgBase = Color(0xFFFAFBFC);
  static const lightBgSurface = Color(0xFFFFFFFF);

  /// 라이트의 elevated는 면색이 같고 그림자로 높이를 표현한다.
  static const lightBgElevated = Color(0xFFFFFFFF);

  /// rgba(15,19,26,0.45)
  static const lightBgScrim = Color(0x730F131A);

  static const lightBorderDefault = Color(0xFFE4E8ED);
  static const lightBorderStrong = Color(0xFFCDD3DB);

  static const lightTextPrimary = Color(0xFF0F131A);
  static const lightTextSecondary = Color(0xFF454D5C);
  static const lightTextTertiary = Color(0xFF6E7788);
  static const lightTextDisabled = Color(0xFFAAB2BF);

  static const lightTextOnPrimary = Color(0xFFFFFFFF);

  // ── 브랜드 ───────────────────────────────────────────────────
  //
  // 절제된 블루 하나. 주 CTA와 포커스에만 쓴다.
  // 러닝 색과 채도로 경쟁하면 기반 UI가 색을 양보한다는 제1원칙이 무너진다.

  static const darkPrimary = Color(0xFF5B8CFF);
  static const darkPrimaryHover = Color(0xFF7AA0FF);

  /// 프라이머리 배경 틴트. rgba(91,140,255,0.16)
  static const darkPrimaryMuted = Color(0x295B8CFF);

  static const lightPrimary = Color(0xFF2F6BFF);
  static const lightPrimaryHover = Color(0xFF1E56E6);

  /// rgba(47,107,255,0.10)
  static const lightPrimaryMuted = Color(0x1A2F6BFF);

  // ── 상태 ─────────────────────────────────────────────────────

  static const darkSuccess = Color(0xFF3DDC84);
  static const darkWarning = Color(0xFFFFB020);
  static const darkError = Color(0xFFFF5A6E);
  static const darkInfo = Color(0xFF4FC3F7);

  static const lightSuccess = Color(0xFF0B7A3E);
  static const lightWarning = Color(0xFF9A5200);
  static const lightError = Color(0xFFD42843);
  static const lightInfo = Color(0xFF0A6FA8);

  // ── 매칭 상태 (§1-2-1) ───────────────────────────────────────
  //
  // 매칭 상태는 홈 히어로·글로벌 배너·인앱 토스트·시간 슬롯 4곳에서
  // 같은 색으로 나타나야 해서 전용 토큰으로 승격했다.
  //
  // 실패는 순수 error 레드를 쓰지 않는다. 기능명세서의 "담담한 톤, 사과·과장 없음"을
  // 지키려고 서피스에 블렌드한 저채도 톤을 쓴다.
  // 산식: alphaBlend(error @ 22%(dark) / 14%(light), bgSurface)
  // ⚠️ 디자인 시스템이 블렌드 비율을 명시하지 않아 임의로 정한 값이다. 디자인 확인이 필요하다.

  static const darkMatchFailed = Color(0xFF482734);
  static const lightMatchFailed = Color(0xFFF9E1E5);
}
