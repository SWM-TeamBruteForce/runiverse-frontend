import 'package:flutter/material.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/extensions/app_elevation.dart';
import 'package:runiverse/core/theme/extensions/app_glow.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';

/// 앱 테마 조립 — 토큰을 `ThemeData`에 실어 위젯 트리 전체에 내려보낸다.
///
/// `MaterialApp`에 이렇게 연결한다:
///
/// ```dart
/// MaterialApp(
///   theme: AppTheme.light(),
///   darkTheme: AppTheme.dark(),
///   themeMode: ThemeMode.dark, // 기본 테마는 다크다
/// )
/// ```
///
/// 여기서 등록한 확장만 `context.appColors` 같은 접근자가 찾을 수 있다.
/// 확장을 새로 만들면 이 파일의 [_extensions]에도 추가해야 한다.
abstract final class AppTheme {
  static ThemeData dark() => _build(
    brightness: Brightness.dark,
    colors: AppColors.dark,
    elevation: AppElevation.dark,
    glow: AppGlow.dark,
  );

  static ThemeData light() => _build(
    brightness: Brightness.light,
    colors: AppColors.light,
    elevation: AppElevation.light,
    glow: AppGlow.light,
  );

  static ThemeData _build({
    required Brightness brightness,
    required AppColors colors,
    required AppElevation elevation,
    required AppGlow glow,
  }) {
    return ThemeData(
      brightness: brightness,
      // Material 기본 위젯(AppBar·버튼 라벨 등)도 Pretendard로 그려지게 한다.
      fontFamily: AppTypography.fontFamily,
      scaffoldBackgroundColor: colors.bgBase,
      colorScheme: _colorScheme(brightness, colors),
      extensions: _extensions(colors, elevation, glow),
    );
  }

  /// Material 위젯이 참조하는 색. 우리 시맨틱 토큰을 Material 슬롯에 대응시킨다.
  ///
  /// 이 시스템에는 secondary가 없다. 브랜드 색은 절제된 블루 하나뿐이고,
  /// 강조는 러닝 색이 담당하기 때문이다. 그래서 secondary에도 primary를 넣는다.
  static ColorScheme _colorScheme(Brightness brightness, AppColors colors) {
    return ColorScheme(
      brightness: brightness,
      primary: colors.primary,
      onPrimary: colors.textOnPrimary,
      secondary: colors.primary,
      onSecondary: colors.textOnPrimary,
      surface: colors.bgSurface,
      onSurface: colors.textPrimary,
      error: colors.error,
      onError: colors.textOnPrimary,
      outline: colors.borderDefault,
    );
  }

  static List<ThemeExtension<dynamic>> _extensions(
    AppColors colors,
    AppElevation elevation,
    AppGlow glow,
  ) => [colors, elevation, glow];
}
