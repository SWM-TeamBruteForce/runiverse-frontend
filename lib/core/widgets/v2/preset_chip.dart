import 'package:flutter/material.dart';
import 'package:runiverse/core/theme/v2/app_motion.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_sizes.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';

/// 새 디자인의 프리셋 칩 — 단일 선택.
///
/// 자유 입력 대신 프리셋만 쓰는 이유는 매칭 때문이다. 조건을 자유롭게 적게
/// 하면 조합이 흩어져 성사율이 떨어진다. 이 위젯은 그 규칙의 UI 쪽이다.
///
/// **선택 상태는 부모가 들고 있다.** 칩이 스스로 켜지지 않는다 — 한 그룹에서
/// 하나만 켜지는 규칙은 칩 하나가 알 수 없는 정보다.
///
/// ## 왜 기존 [PresetChip]을 안 쓰나
///
/// 모양이 다르다. 기존 칩은 **알약**에 골랐을 때 `primaryMuted`를 옅게 깔고,
/// 시안(`158:3198`)은 **반경 12**에 골랐을 때 브랜드 색을 **가득 채운다.**
/// 안 고른 칩도 다르다 — 기존은 면이 있고 시안은 **테두리만** 있다.
///
/// ## 모션 값은 기존 것을 그대로 쓴다
///
/// 시안에 모션 정의가 없다. `v2/app_motion`이 기존 값을 재수출한다 —
/// 지어낼 근거가 없으면 기존 값을 쓰되, **화면은 v2 경로만 본다.**
class PresetChipV2 extends StatelessWidget {
  const PresetChipV2({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedContainer(
        // 배경이 바깥에 있어야 잉크 리플이 그 위에 그려진다. 안쪽에 두면 색이
        // 리플을 덮어 눌러도 아무 반응이 없어 보인다.
        duration: AppMotion.fast,
        curve: AppMotion.easeStandard,
        decoration: BoxDecoration(
          color: selected ? colors.primary : null,
          borderRadius: AppRadius.md,
          border: selected ? null : Border.all(color: colors.textTertiary),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.md,
            child: Container(
              constraints: const BoxConstraints(
                minHeight: AppSizes.touchDefault,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space4,
                vertical: AppSpacing.space3,
              ),
              // `alignment`를 쓰지 않는다. alignment가 있는 Container는 주어진
              // 제약을 **끝까지 채워서**, Wrap 안에서 칩 하나가 한 줄을 다 먹는다.
              // 정렬은 Row가 대신한다.
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      // 좁은 칸에 긴 라벨이 들어와도 넘치는 대신 줄인다.
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppTypographyV2.body11.copyWith(
                        color: selected
                            ? colors.textPrimary
                            : colors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
