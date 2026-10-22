import 'package:flutter/material.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_sizes.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/widgets/v2/app_icon.dart';

/// 커버 사진 위에 서는 원형 버튼 — 시안 `158:3938`.
///
/// ## ⚠️ 어두운 원이 장식이 아니다
///
/// 2026-10-22에는 이 버튼을 커버 **아래**로 내렸다. "사진 위 흰 아이콘은 밝은
/// 사진에서 안 보인다"는 이유였고, 그때는 가릴 장치가 없었다.
///
/// 시안은 원래부터 **아이콘 뒤에 어두운 원**을 깔아 그것을 풀고 있었다. 커버
/// 위로 되돌리면서 그 원을 함께 가져온다 — [AppColorsV2.coverScrim]은 상태바
/// 그늘막과 같은 값이고, 기기에서 밝은 사진으로 흰 글자 4.9:1을 확인한 값이다.
///
/// **원을 빼면 버튼이 사라진다.** 색을 옅게 바꿀 때도 같은 자리에서 확인한다.
///
/// ## ⚠️ 글자가 없으므로 [Semantics]를 반드시 붙인다
///
/// 안 붙이면 스크린리더가 읽을 것이 없다 — 탭 바에서 같은 실수를 한 적이 있다.
class ProfileCoverAction extends StatelessWidget {
  const ProfileCoverAction({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;

  /// 시안은 21. 24는 이 원 안에서 꽉 차 보인다.
  static const _glyph = AppSpacing.space5;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return MergeSemantics(
      child: Semantics(
        label: label,
        button: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.coverScrim,
            shape: BoxShape.circle,
          ),
          child: Material(
            // 원은 위에서 그렸다. 여기서 색을 또 깔면 그늘막을 덮는다.
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: SizedBox(
                // ⚠️ **시안은 41이지만 44로 그린다.** 44 미만은 손가락이
                // 빗나간다(`AppSizes` 주석). 글리프만 시안 크기에 맞춘다.
                width: AppSizes.touchDefault,
                height: AppSizes.touchDefault,
                child: Center(
                  child: AppIcon(icon, size: _glyph, color: colors.textPrimary),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
