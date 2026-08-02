import 'package:flutter/material.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_motion.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';

/// 버튼 종류 — 디자인 시스템 v1.1 §7.
enum AppButtonVariant {
  /// 채운 브랜드 색. **화면당 하나만 둔다.**
  /// 둘 이상이면 무엇을 눌러야 하는지가 흐려진다.
  primary,

  /// 테두리만. primary 옆의 대등한 선택지.
  secondary,

  /// 배경도 테두리도 없는 텍스트 버튼. 3순위 액션.
  ghost,

  /// 파괴적 액션. 탈퇴·삭제.
  ///
  /// ⚠️ 러닝 중단처럼 되돌릴 수 없는 것은 이 버튼으로 만들지 않는다.
  /// **hold-to-end(2초)나 2단계 확인**을 쓴다(`docs/implementation-notes.md` §4).
  danger,
}

/// 버튼 높이 — 터치 타깃 규칙과 직결된다.
enum AppButtonSize {
  /// 44 — 일반 화면의 최소 터치 타깃.
  md(44),

  /// 56 — 주 CTA. 러닝 중 화면(S11~S13)은 **모든 버튼이 이 크기**여야 한다.
  lg(56);

  const AppButtonSize(this.height);

  final double height;
}

/// 앱 공통 버튼.
///
/// 높이를 [AppButtonSize]로만 정한다. 수직 패딩으로 높이를 만들면 글자 크기에 따라
/// 박스가 접혀 44px 아래로 내려간다 — v1에서 가장 많이 반복된 결함이다
/// (`AppSizes` 문서 주석 참조).
///
/// [onPressed]가 `null`이면 비활성이다. S03 약관 화면처럼 조건이 충족돼야
/// 누를 수 있는 CTA는 `null`을 넘겨 잠근다.
class AppButton extends StatelessWidget {
  const AppButton({
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.lg,
    this.expand = true,
    super.key,
  });

  final String label;

  /// `null`이면 비활성.
  final VoidCallback? onPressed;

  final AppButtonVariant variant;
  final AppButtonSize size;

  /// 가로를 꽉 채울지. 화면 하단 CTA는 채우고, 인라인 액션은 끈다.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final enabled = onPressed != null;
    final style = _styleOf(colors, enabled);

    final button = Material(
      color: style.background,
      // 완전한 pill. 56px 버튼이면 반지름 28이 되는데, 높이를 몰라도 되도록 큰 값을 쓴다.
      borderRadius: AppRadius.full,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        // 탭 피드백은 fast(120ms). 즉각 반응해야 눌린 느낌이 난다.
        splashFactory: InkSparkle.splashFactory,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.easeStandard,
          height: size.height,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space6),
          decoration: BoxDecoration(
            borderRadius: AppRadius.full,
            border: style.border == null
                ? null
                : Border.all(color: style.border!),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyLg.copyWith(
              color: style.foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }

  /// 종류·활성 여부에 따른 색 조합.
  ///
  /// ⚠️ 비활성 색은 디자인 시스템이 명시하지 않아 정한 값이다.
  /// 면은 elevated, 글자는 textDisabled — 눌리지 않음이 보이되 사라지지는 않게 했다.
  /// 디자인 확인이 필요하다.
  _ButtonStyle _styleOf(AppColors colors, bool enabled) {
    if (!enabled) {
      return _ButtonStyle(
        background: variant == AppButtonVariant.ghost
            ? Colors.transparent
            : colors.bgElevated,
        foreground: colors.textDisabled,
        border: variant == AppButtonVariant.secondary
            ? colors.borderDefault
            : null,
      );
    }

    return switch (variant) {
      AppButtonVariant.primary => _ButtonStyle(
        background: colors.primary,
        foreground: colors.textOnPrimary,
      ),
      AppButtonVariant.secondary => _ButtonStyle(
        background: Colors.transparent,
        foreground: colors.textPrimary,
        border: colors.borderStrong,
      ),
      AppButtonVariant.ghost => _ButtonStyle(
        background: Colors.transparent,
        foreground: colors.primary,
      ),
      AppButtonVariant.danger => _ButtonStyle(
        background: colors.error,
        foreground: colors.textOnPrimary,
      ),
    };
  }
}

class _ButtonStyle {
  const _ButtonStyle({
    required this.background,
    required this.foreground,
    this.border,
  });

  final Color background;
  final Color foreground;
  final Color? border;
}
