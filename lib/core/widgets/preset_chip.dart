import 'package:flutter/material.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_motion.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_sizes.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';

/// 프리셋 칩 — 디자인 시스템 `PresetChip`. 단일 선택 pill.
///
/// 자유 입력 대신 프리셋만 쓰는 이유는 매칭 때문이다. 조건을 자유롭게 적게 하면
/// 조합이 흩어져 성사율이 떨어진다. 이 위젯은 그 규칙의 UI 쪽이다.
///
/// **선택 상태는 부모가 들고 있다.** 칩이 스스로 켜지지 않는다 — 한 그룹에서
/// 하나만 켜지는 규칙은 칩 하나가 알 수 없는 정보다.
class PresetChip extends StatelessWidget {
  const PresetChip({
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
    final colors = context.appColors;

    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedContainer(
        // 배경이 바깥에 있어야 잉크 리플이 그 위에 그려진다.
        // 안쪽에 두면 색이 리플을 덮어 눌러도 아무 반응이 없어 보인다.
        duration: AppMotion.fast,
        curve: AppMotion.easeStandard,
        decoration: BoxDecoration(
          color: selected ? colors.primaryMuted : colors.bgSurface,
          borderRadius: AppRadius.full,
          border: Border.all(
            color: selected ? colors.primary : colors.borderDefault,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.full,
            splashFactory: InkSparkle.splashFactory,
            child: Container(
              constraints: const BoxConstraints(
                minHeight: AppSizes.touchDefault,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space4,
              ),
              // `alignment`를 쓰지 않는다. alignment가 있는 Container는 주어진 제약을
              // **끝까지 채워서**, Wrap 안에서 칩 하나가 한 줄을 다 먹는다.
              // 정렬은 Row가 대신한다 — 부모가 너비를 정해주면(Expanded 안) 가운데로,
              // 정해주지 않으면 글자 크기만큼만 차지한다.
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
                      style: AppTypography.body.copyWith(
                        color: selected
                            ? colors.textPrimary
                            : colors.textSecondary,
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
