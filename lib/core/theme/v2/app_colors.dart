import 'package:flutter/material.dart';
import 'package:runiverse/core/theme/v2/app_palette.dart';

/// 새 디자인의 시맨틱 색 — "이 자리는 무슨 색인가".
///
/// 화면 코드는 [AppPaletteV2]를 직접 쓰지 않고 이 확장을 통해 색을 얻는다.
/// `context.appColorsV2.bgSurface`처럼 쓰면 다크/라이트 전환이 따라온다.
///
/// **러닝 색은 여기 없다.** 테마가 아니라 데이터여서 한 화면에 여러 개가
/// 동시에 뜬다(컬렉션 30색). `RunPaletteV2`가 따로 든다.
///
/// ## 글자 넷은 램프와 불투명도를 섞어 쓴다
///
/// 시안이 그렇게 쓴다. 한 규칙으로 통일하려다 두 번 틀렸다.
///
/// - **본문**은 [AppPaletteV2.neutral50] — 시안이 `Primary-50-FAFAFA` 라는
///   이름 붙은 스타일로 들고 있다(`158:3415`)
/// - **보조**는 흰색 70% — `매칭실패`(`158:3048`)의 본문이 그렇다
/// - **작은 라벨**은 [AppPaletteV2.neutral600] — `시작 시간`·`목표 거리`·
///   `참여자`가 전부 `#575757` 이다(`158:3415`)
///
/// 그래서 위계는 불투명도가 아니라 **배경과의 밝기 차**로 선다. 테스트도
/// 그것을 본다.
///
/// ## ⚠️ 시안이 정해 주지 않은 값이 있다
///
/// 시안에는 원색 시트(`162:4905`)만 있고 "이 색이 배경"이라는 지정이 없다.
/// 확인된 것과 정한 것은 이렇게 갈린다.
///
/// **시안에서 직접 읽은 것** — [primaryMuted]와 [matchWaiting]
/// (`158:2976` 매칭대기중 배지: 면 `#202B43`, 글자 `#227DFF`), 글자 불투명도.
///
/// **규칙으로 정한 것** — 배경·테두리는 중립 램프를 깊은 쪽부터(어두운 테마)
/// 또는 뒤집어서(밝은 테마) 쓴다. 상태색 넷은 러닝 색 10군에서 성격이 맞는 것을
/// 빌린다. **디자이너 확인 전까지 임시다.**
@immutable
class AppColorsV2 extends ThemeExtension<AppColorsV2> {
  const AppColorsV2({
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

  /// 프라이머리 배경 틴트. 시안 `158:2976`의 배지 면이다.
  final Color primaryMuted;

  final Color success;
  final Color warning;
  final Color error;
  final Color info;

  // 매칭 상태 — 홈 히어로·글로벌 배너·인앱 토스트·시간 슬롯 네 곳에서 같은
  // 색으로 나타나야 해서 전용 토큰으로 둔다. 상태 색을 직접 쓰지 않는다.

  /// 매칭 대기. 시안 `158:2976`의 배지 글자색이다.
  final Color matchWaiting;

  /// 매칭 확정.
  final Color matchConfirmed;

  /// 매칭 실패. **순수 error 레드가 아니다** — 담담한 톤으로 한 단계 깊게 쓴다.
  ///
  /// ⚠️ 시안의 매칭실패 화면(`158:3048`)은 상태색을 아예 쓰지 않고 흰 글자만
  /// 쓴다. 이 값은 배너·슬롯에서 쓸 것을 규칙으로 정한 것이다.
  final Color matchFailed;

  /// 시안이 보여주는 쪽. 화면 시안이 전부 어두운 배경이다.
  static const dark = AppColorsV2(
    bgBase: AppPaletteV2.neutral950,
    bgSurface: AppPaletteV2.neutral900,
    bgElevated: AppPaletteV2.neutral800,
    bgScrim: Color(0x99000000),
    borderDefault: AppPaletteV2.neutral800,
    borderStrong: AppPaletteV2.neutral700,
    textPrimary: AppPaletteV2.neutral50,
    textSecondary: Color(0xB3FFFFFF),
    textTertiary: AppPaletteV2.neutral600,
    textDisabled: AppPaletteV2.neutral700,
    textOnPrimary: AppPaletteV2.neutral50,
    primary: AppPaletteV2.brand,
    primaryHover: Color(0xFF7CB5FF),
    primaryMuted: AppPaletteV2.brandDeep,
    success: Color(0xFF33D17A),
    warning: Color(0xFFFFD36B),
    error: Color(0xFFFF5B5B),
    info: AppPaletteV2.brand,
    matchWaiting: AppPaletteV2.brand,
    matchConfirmed: Color(0xFF33D17A),
    matchFailed: Color(0xFFB83C3C),
  );

  /// 램프를 뒤집은 쪽. **시안에 없다** — 규칙으로 만든 것이다.
  static const light = AppColorsV2(
    bgBase: Color(0xFFFFFFFF),
    bgSurface: AppPaletteV2.neutral50,
    bgElevated: AppPaletteV2.neutral100,
    bgScrim: Color(0x66171719),
    borderDefault: AppPaletteV2.neutral200,
    borderStrong: AppPaletteV2.neutral300,
    textPrimary: AppPaletteV2.label,
    textSecondary: Color(0xB3171719),
    textTertiary: AppPaletteV2.neutral500,
    textDisabled: AppPaletteV2.neutral400,
    textOnPrimary: Color(0xFFFFFFFF),
    primary: AppPaletteV2.brand,
    primaryHover: Color(0xFF1556B8),
    primaryMuted: Color(0xFF7CB5FF),
    success: Color(0xFF237A4A),
    warning: Color(0xFFB98A2F),
    error: Color(0xFFB83C3C),
    info: Color(0xFF1556B8),
    matchWaiting: Color(0xFF1556B8),
    matchConfirmed: Color(0xFF237A4A),
    matchFailed: Color(0xFFB83C3C),
  );

  @override
  AppColorsV2 copyWith({
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
  }) => AppColorsV2(
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

  @override
  AppColorsV2 lerp(covariant AppColorsV2? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColorsV2(
      bgBase: c(bgBase, other.bgBase),
      bgSurface: c(bgSurface, other.bgSurface),
      bgElevated: c(bgElevated, other.bgElevated),
      bgScrim: c(bgScrim, other.bgScrim),
      borderDefault: c(borderDefault, other.borderDefault),
      borderStrong: c(borderStrong, other.borderStrong),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textTertiary: c(textTertiary, other.textTertiary),
      textDisabled: c(textDisabled, other.textDisabled),
      textOnPrimary: c(textOnPrimary, other.textOnPrimary),
      primary: c(primary, other.primary),
      primaryHover: c(primaryHover, other.primaryHover),
      primaryMuted: c(primaryMuted, other.primaryMuted),
      success: c(success, other.success),
      warning: c(warning, other.warning),
      error: c(error, other.error),
      info: c(info, other.info),
      matchWaiting: c(matchWaiting, other.matchWaiting),
      matchConfirmed: c(matchConfirmed, other.matchConfirmed),
      matchFailed: c(matchFailed, other.matchFailed),
    );
  }
}

extension AppColorsV2Of on BuildContext {
  /// 새 디자인으로 옮긴 화면이 쓴다. 안 옮긴 화면은 `appColors`를 그대로 쓴다.
  AppColorsV2 get appColorsV2 {
    final colors = Theme.of(this).extension<AppColorsV2>();
    assert(colors != null, 'AppColorsV2를 ThemeData에 넣지 않았다');
    return colors!;
  }
}
