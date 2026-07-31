import 'package:flutter/material.dart';
import 'package:runiverse/core/theme/tokens/app_palette.dart';

/// 시맨틱 컬러 토큰 — 디자인 시스템 v1.1 §1-1, §1-2, §1-2-1.
///
/// 화면 코드는 `AppPalette`를 직접 쓰지 않고 이 확장을 통해 색을 얻는다.
/// `context.appColors.bgSurface`처럼 쓰면 다크/라이트 전환이 자동으로 따라온다.
///
/// **러닝 색은 여기 없다.** 러닝 색은 테마가 아니라 데이터여서
/// 한 화면에 여러 개가 동시에 뜬다(컬렉션 30색). 위젯 파라미터로 전달한다.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bgBase,
    required this.bgSurface,
    required this.bgElevated,
    required this.bgScrim,
    required this.borderDefault,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.textOnPrimary,
    required this.primary,
    required this.primaryHover,
    required this.primaryMuted,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.matchWaiting,
    required this.matchConfirmed,
    required this.matchFailed,
  });

  /// 최하단 배경(스크롤 뒤).
  final Color bgBase;

  /// 카드·시트 기본 면.
  final Color bgSurface;

  /// 떠 있는 면(모달·팝오버).
  final Color bgElevated;

  /// 모달 뒤 딤.
  final Color bgScrim;

  final Color borderDefault;
  final Color borderStrong;

  /// 본문·제목·러닝 수치.
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;

  /// 프라이머리 면 위에 얹는 라벨.
  final Color textOnPrimary;

  /// 주 CTA·포커스·선택. 화면당 primary 버튼은 하나다.
  final Color primary;
  final Color primaryHover;

  /// 프라이머리 배경 틴트.
  final Color primaryMuted;

  final Color success;
  final Color warning;
  final Color error;
  final Color info;

  // 매칭 상태(§1-2-1) — 홈 히어로·글로벌 배너·인앱 토스트·시간 슬롯 4곳에서
  // 같은 색으로 나타나야 해서 전용 토큰으로 승격했다.
  // 상태 색을 직접 쓰지 말고 이 토큰을 쓴다.

  /// 매칭 대기.
  final Color matchWaiting;

  /// 매칭 확정.
  final Color matchConfirmed;

  /// 매칭 실패. **순수 error 레드가 아니다** — 담담한 톤을 위해 서피스에 블렌드했다.
  final Color matchFailed;

  /// 기본 테마.
  static const dark = AppColors(
    bgBase: AppPalette.darkBgBase,
    bgSurface: AppPalette.darkBgSurface,
    bgElevated: AppPalette.darkBgElevated,
    bgScrim: AppPalette.darkBgScrim,
    borderDefault: AppPalette.darkBorderDefault,
    borderStrong: AppPalette.darkBorderStrong,
    textPrimary: AppPalette.darkTextPrimary,
    textSecondary: AppPalette.darkTextSecondary,
    textTertiary: AppPalette.darkTextTertiary,
    textDisabled: AppPalette.darkTextDisabled,
    textOnPrimary: AppPalette.darkTextOnPrimary,
    primary: AppPalette.darkPrimary,
    primaryHover: AppPalette.darkPrimaryHover,
    primaryMuted: AppPalette.darkPrimaryMuted,
    success: AppPalette.darkSuccess,
    warning: AppPalette.darkWarning,
    error: AppPalette.darkError,
    info: AppPalette.darkInfo,
    matchWaiting: AppPalette.darkInfo,
    matchConfirmed: AppPalette.darkSuccess,
    matchFailed: AppPalette.darkMatchFailed,
  );

  static const light = AppColors(
    bgBase: AppPalette.lightBgBase,
    bgSurface: AppPalette.lightBgSurface,
    bgElevated: AppPalette.lightBgElevated,
    bgScrim: AppPalette.lightBgScrim,
    borderDefault: AppPalette.lightBorderDefault,
    borderStrong: AppPalette.lightBorderStrong,
    textPrimary: AppPalette.lightTextPrimary,
    textSecondary: AppPalette.lightTextSecondary,
    textTertiary: AppPalette.lightTextTertiary,
    textDisabled: AppPalette.lightTextDisabled,
    textOnPrimary: AppPalette.lightTextOnPrimary,
    primary: AppPalette.lightPrimary,
    primaryHover: AppPalette.lightPrimaryHover,
    primaryMuted: AppPalette.lightPrimaryMuted,
    success: AppPalette.lightSuccess,
    warning: AppPalette.lightWarning,
    error: AppPalette.lightError,
    info: AppPalette.lightInfo,
    matchWaiting: AppPalette.lightInfo,
    matchConfirmed: AppPalette.lightSuccess,
    matchFailed: AppPalette.lightMatchFailed,
  );

  @override
  AppColors copyWith({
    Color? bgBase,
    Color? bgSurface,
    Color? bgElevated,
    Color? bgScrim,
    Color? borderDefault,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textDisabled,
    Color? textOnPrimary,
    Color? primary,
    Color? primaryHover,
    Color? primaryMuted,
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
    Color? matchWaiting,
    Color? matchConfirmed,
    Color? matchFailed,
  }) {
    return AppColors(
      bgBase: bgBase ?? this.bgBase,
      bgSurface: bgSurface ?? this.bgSurface,
      bgElevated: bgElevated ?? this.bgElevated,
      bgScrim: bgScrim ?? this.bgScrim,
      borderDefault: borderDefault ?? this.borderDefault,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textDisabled: textDisabled ?? this.textDisabled,
      textOnPrimary: textOnPrimary ?? this.textOnPrimary,
      primary: primary ?? this.primary,
      primaryHover: primaryHover ?? this.primaryHover,
      primaryMuted: primaryMuted ?? this.primaryMuted,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      info: info ?? this.info,
      matchWaiting: matchWaiting ?? this.matchWaiting,
      matchConfirmed: matchConfirmed ?? this.matchConfirmed,
      matchFailed: matchFailed ?? this.matchFailed,
    );
  }

  /// 테마가 바뀔 때 두 색 사이를 보간한다. Flutter가 자동으로 호출한다.
  @override
  AppColors lerp(covariant AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      bgBase: Color.lerp(bgBase, other.bgBase, t)!,
      bgSurface: Color.lerp(bgSurface, other.bgSurface, t)!,
      bgElevated: Color.lerp(bgElevated, other.bgElevated, t)!,
      bgScrim: Color.lerp(bgScrim, other.bgScrim, t)!,
      borderDefault: Color.lerp(borderDefault, other.borderDefault, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      textOnPrimary: Color.lerp(textOnPrimary, other.textOnPrimary, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryHover: Color.lerp(primaryHover, other.primaryHover, t)!,
      primaryMuted: Color.lerp(primaryMuted, other.primaryMuted, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      info: Color.lerp(info, other.info, t)!,
      matchWaiting: Color.lerp(matchWaiting, other.matchWaiting, t)!,
      matchConfirmed: Color.lerp(matchConfirmed, other.matchConfirmed, t)!,
      matchFailed: Color.lerp(matchFailed, other.matchFailed, t)!,
    );
  }
}

/// `context.appColors.bgSurface`로 색을 꺼낸다.
extension AppColorsContext on BuildContext {
  AppColors get appColors {
    final colors = Theme.of(this).extension<AppColors>();
    assert(
      colors != null,
      'AppColors가 ThemeData.extensions에 없다. '
      'MaterialApp의 theme/darkTheme으로 AppTheme.light()/dark()를 쓰고 있는지 확인한다.',
    );
    return colors ?? AppColors.dark;
  }
}
