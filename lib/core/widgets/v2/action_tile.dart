import 'package:flutter/material.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_icon.dart';

/// 아이콘 타일 + 라벨이 가로로 붙은 칸 — 시안 `158:2875` `158:2881`.
///
/// 홈 아래쪽의 `혼자연습하기` · `친구랑 뛰기` 두 칸이다.
///
/// ## 강조는 아이콘 타일의 면으로만 낸다
///
/// 시안이 두 칸을 **같은 크기·같은 배경**으로 두고 아이콘 타일 면만 다르게
/// 쓴다(`#227dff` ↔ `#202b43`). 칸 자체를 키우거나 테두리를 주지 않는다 —
/// 둘은 나란히 고르는 선택지이지 주·보조가 아니다.
class ActionTileV2 extends StatelessWidget {
  const ActionTileV2({
    required this.icon,
    required this.label,
    required this.onTap,
    this.emphasized = true,
    super.key,
  });

  /// [AppIcons]의 상수.
  final String icon;

  final String label;
  final VoidCallback onTap;

  /// 아이콘 타일 면을 [AppColorsV2.primary]로 채운다. 끄면 가라앉은 면이다.
  final bool emphasized;

  /// 아이콘이 앉는 정사각 타일.
  static const _badgeSize = 36.0;

  /// 그 안의 아이콘. 시안은 20이다.
  static const _iconSize = 20.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Material(
      color: colors.bgSurface,
      borderRadius: AppRadius.lg,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.lg,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space4),
          child: Row(
            children: [
              Container(
                width: _badgeSize,
                height: _badgeSize,
                decoration: BoxDecoration(
                  color: emphasized ? colors.primary : colors.primaryMuted,
                  // 시안은 10인데 우리 스케일에 없다. 8로 맞춘다.
                  borderRadius: AppRadius.sm,
                ),
                child: Center(
                  child: AppIcon(
                    icon,
                    size: _iconSize,
                    // 두 면 모두 어두워서 같은 색으로 읽힌다.
                    color: colors.textStrong,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.space3),

              // ⚠️ **긴 라벨이 넘칠 자리를 준다.** 두 칸이 화면을 반씩 나눠 갖는데
              // 라벨 길이는 문구에 달렸다. `Expanded` 없이 두면 글자가 길어지는
              // 순간 칸 전체가 오버플로로 빨갛게 줄이 간다.
              Expanded(
                child: Text(
                  label,
                  style: AppTypographyV2.body10.copyWith(
                    color: colors.textStrong,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
