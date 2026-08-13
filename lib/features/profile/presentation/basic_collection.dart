import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/theme/tokens/run_palette.dart';

/// 기본 컬렉션 2×5 — 10범주 × 셰이드 3개 = 30색.
///
/// ## ⚠️ 잠긴 칸도 자기 색을 비춘다
///
/// **전부 회색으로 그리면 무엇을 모으는 것인지 알 수 없다.** 30개의 회색 원은
/// 정보를 하나도 주지 않고, 화면이 로딩에 실패한 것처럼 읽힌다.
///
/// 그래서 잠긴 칸도 `RunPalette`의 색을 **낮은 투명도로** 깐다. "이런 색을 모은다"가
/// 눈에 먼저 들어오고, 획득하면 같은 색이 선명해지는 것으로 진행이 보인다.
///
/// 투명도만으로 상태를 알리지 않는다 — 잠긴 칸에는 자물쇠 글리프가 함께 선다
/// (디자인 시스템 §1-5 · 색만으로 정보를 전달하지 않는다).
class BasicCollection extends StatelessWidget {
  const BasicCollection({this.owned = const {}, super.key});

  /// 획득한 색. `hue → 획득한 shade 번호(1~3)`.
  ///
  /// 비어 있으면 아직 한 번도 달리지 않은 사람이다. **그것이 기본값이다** —
  /// 이 화면을 처음 보는 사람 대부분이 여기 해당한다.
  final Map<RunHue, Set<int>> owned;

  /// 범주 이름. `RunHue`에 붙이지 않는 이유는 `domain`이 순수 Dart여야 하고
  /// UI 문구는 `AppStrings`에 모여야 하기 때문이다.
  static const _labels = <RunHue, String>{
    RunHue.distance: AppStrings.hueDistance,
    RunHue.speed: AppStrings.hueSpeed,
    RunHue.endurance: AppStrings.hueEndurance,
    RunHue.consistency: AppStrings.hueConsistency,
    RunHue.cadence: AppStrings.hueCadence,
    RunHue.interval: AppStrings.hueInterval,
    RunHue.hills: AppStrings.hueHills,
    RunHue.recovery: AppStrings.hueRecovery,
    RunHue.company: AppStrings.hueCompany,
    RunHue.adversity: AppStrings.hueAdversity,
  };

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      // 화면 전체가 하나의 스크롤이다. 격자가 자기 스크롤을 가지면
      // 손가락이 어느 쪽을 미는지 알 수 없어진다.
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      crossAxisCount: 5,
      mainAxisSpacing: AppSpacing.space4,
      crossAxisSpacing: AppSpacing.space2,
      childAspectRatio: 0.72,
      children: [
        for (final hue in RunHue.values)
          _HueCell(
            hue: hue,
            label: _labels[hue]!,
            owned: owned[hue] ?? const {},
          ),
      ],
    );
  }
}

/// 한 범주. 큰 원 하나 + 셰이드 점 3개 + 이름.
class _HueCell extends StatelessWidget {
  const _HueCell({required this.hue, required this.label, required this.owned});

  final RunHue hue;
  final String label;
  final Set<int> owned;

  /// 잠긴 색을 얼마나 비출 것인가.
  ///
  /// 낮추면 회색과 구분되지 않고, 높이면 획득한 것과 헷갈린다.
  /// **획득한 칸과 나란히 놓고 정한 값이다.**
  static const _lockedOpacity = 0.28;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final hasAny = owned.isNotEmpty;
    // 가진 것 중 가장 깊은 셰이드를 대표로 보인다. 얕은 것을 보이면
    // 더 깊은 색을 이미 얻었는데 화면이 그것을 숨기는 셈이다.
    final deepest = hasAny ? owned.reduce((a, b) => a > b ? a : b) : 2;
    final color = RunPalette.color(hue, deepest);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: AppSpacing.space9,
          height: AppSpacing.space9,
          decoration: BoxDecoration(
            color: hasAny ? color : color.withValues(alpha: _lockedOpacity),
            shape: BoxShape.circle,
          ),
          child: hasAny
              ? null
              // 색만으로 알리지 않는다. 자물쇠가 함께 서야 색각 이상에서도 읽힌다.
              //
              // ⚠️ 색을 `bgBase`로 두지 않는다. 다크에서는 읽히지만 **라이트에서는
              // 밝은 자물쇠가 옅은 색 위에 얹혀 사라진다.** `textSecondary`는
              // 두 테마에서 배경과 반대쪽으로 움직여 양쪽 다 읽힌다.
              : Icon(
                  LucideIcons.lock,
                  size: AppSpacing.space3,
                  color: colors.textSecondary,
                ),
        ),
        const SizedBox(height: AppSpacing.space2),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var shade = 1; shade <= RunPalette.shadeCount; shade++) ...[
              if (shade > 1) const SizedBox(width: AppSpacing.space1),
              Container(
                width: AppSpacing.space1,
                height: AppSpacing.space1,
                decoration: BoxDecoration(
                  color: owned.contains(shade)
                      ? RunPalette.color(hue, shade)
                      : colors.borderStrong,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.space1),

        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.micro.copyWith(
            color: hasAny ? colors.textSecondary : colors.textTertiary,
          ),
        ),
      ],
    );
  }
}

/// 섹션 제목 한 줄 — `기본 컬렉션        0/30`
///
/// 제목과 수치를 한 줄에 둔다. 수치를 아래로 내리면 섹션마다 높이가 달라져
/// 스크롤할 때 리듬이 깨진다.
class ProfileSectionTitle extends StatelessWidget {
  const ProfileSectionTitle({
    required this.title,
    this.trailing,
    this.hint,
    super.key,
  });

  final String title;

  /// 오른쪽 끝 수치. `0/30` · `2개` 같은 것.
  final String? trailing;

  /// 제목 아래 한 줄. 무엇을 하면 채워지는지 알려준다.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final trailing = this.trailing;
    final hint = this.hint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: AppTypography.bodyLg.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (trailing != null)
              Text(
                trailing,
                style: AppTypography.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
          ],
        ),
        if (hint != null) ...[
          const SizedBox(height: AppSpacing.space1),
          Text(
            hint,
            style: AppTypography.caption.copyWith(color: colors.textTertiary),
          ),
        ],
      ],
    );
  }
}

/// 섹션을 감싸는 카드. 격자와 빈 상태가 같은 판 위에 서게 한다.
class ProfileSectionCard extends StatelessWidget {
  const ProfileSectionCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.space4),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: colors.borderDefault),
      ),
      child: child,
    );
  }
}
