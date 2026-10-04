import 'package:flutter/material.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_sizes.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';

/// 새 디자인의 버튼 변형.
enum AppButtonV2Variant {
  /// 채운 브랜드 색. **화면당 하나만 둔다.**
  primary,

  /// 테두리만. 시안 `158:3433`의 `취소하기`가 이것이다.
  secondary,

  /// 브랜드 색을 옅게 깐 면. 시안 `158:3790`의 `자세한 기록 보기`가 이것이다.
  ///
  /// [primary] 옆에 둘 때 쓴다 — 테두리만 있는 [secondary]보다 무게가 있어서
  /// 둘 중 어느 쪽도 "덜 중요해" 보이지 않는다.
  tonal,

  /// 되돌릴 수 없는 것. 탈퇴가 이것이다.
  ///
  /// ⚠️ **시안에 이 변형이 없다.** 설정·탈퇴 화면이 시안에 없어서 색을
  /// `AppColorsV2.error`로 정했다 — 디자인 확인이 필요하다.
  ///
  /// ⚠️ 러닝 중단처럼 **한 번 누르면 끝나는 것**은 이 버튼으로 만들지 않는다.
  /// hold-to-end(2초)나 2단계 확인을 쓴다(`docs/implementation-notes.md` §4).
  /// 탈퇴가 이것을 써도 되는 이유는 **시트가 이미 2단계**이기 때문이다.
  danger,
}

/// 새 디자인의 버튼 — 시안 `Button-Solid` 컴포넌트.
///
/// ## 왜 기존 [AppButton]을 안 쓰나
///
/// 모양이 다르다. 기존 버튼은 **알약**(`AppRadius.full`)이고 시안은
/// **반경 16의 둥근 사각형**이다. 기존 것을 그대로 쓰면 옮긴 화면이
/// 반쯤 옛날 모습이 된다.
///
/// 색도 다르다 — 기존 버튼은 옛 토큰을 읽는다. 한 화면 안에서 두 세대가
/// 섞이는 것을 `test/theme_generation_test.dart`가 막는 이유이기도 하다.
///
/// ## API는 기존 것과 맞췄다
///
/// `label` · `onPressed` · `variant` · `expand`. 화면을 옮길 때 이름을
/// 갈아끼우는 일이 얹히지 않게 하려는 것이다.
class AppButtonV2 extends StatelessWidget {
  const AppButtonV2({
    required this.label,
    required this.onPressed,
    this.variant = AppButtonV2Variant.primary,
    this.expand = true,
    super.key,
  });

  final String label;

  /// `null`이면 비활성.
  final VoidCallback? onPressed;

  final AppButtonV2Variant variant;

  /// 가로를 꽉 채울지. 화면 하단 CTA는 채우고, 인라인 액션은 끈다.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final enabled = onPressed != null;
    final danger = variant == AppButtonV2Variant.danger;
    final filled = variant == AppButtonV2Variant.primary || danger;
    final tonal = variant == AppButtonV2Variant.tonal;

    // 비활성은 **투명도가 아니라 색으로** 표현한다. 투명도를 쓰면 뒤 배경이
    // 비쳐서 카드 위와 화면 위의 같은 버튼이 다르게 보인다.
    final accent = !enabled
        ? colors.textDisabled
        : danger
        ? colors.error
        : colors.primary;

    // 면을 까는 변형 둘. 잠기면 둘 다 같은 회색 면이 된다 — 무엇이 주
    // 버튼이었는지는 눌리지 않는 순간 의미가 없다.
    final surface = !enabled
        ? (filled || tonal ? colors.bgSurface : null)
        : filled
        ? accent
        : tonal
        ? colors.primaryMuted
        : null;

    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: surface ?? Colors.transparent,
        borderRadius: AppRadius.lg,
        child: InkWell(
          onTap: onPressed,
          borderRadius: AppRadius.lg,
          child: Container(
            height: AppSizes.touchRunning,
            width: expand ? double.infinity : null,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space6),
            decoration: BoxDecoration(
              borderRadius: AppRadius.lg,
              // 테두리는 secondary 만 두른다. 면이 있는 쪽에 테두리까지
              // 두르면 모서리가 두 겹으로 보인다.
              border: filled || tonal ? null : Border.all(color: accent),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AppTypographyV2.body05.copyWith(
                color: filled && enabled ? colors.textOnPrimary : accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
