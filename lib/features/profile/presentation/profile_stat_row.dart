import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';

/// 닉네임 아래 두 줄 — 시안 `85:2882`.
///
/// ```
/// 👥  친구 · 12   [2]  ›
/// 🏅  업적   준비중
/// ────────────────────
///      러닝 업적 준비중
///   거리 ▓▓▓▓▓░░⚑░
/// ```
///
/// ## ⚠️ 시안의 네 줄이 두 줄이 됐다
///
/// 시안은 `팔로워 · 24` `팔로우 · 32` `컬러 · 1/30` `뱃지 · 1/10` 넷을 세운다.
///
/// - 관계가 **양방향 친구**라 팔로워·팔로우 두 줄이 한 줄이 된다.
/// - 컬러는 범위에서 빠졌다.
/// - 뱃지 자리는 **업적**이 받고, 다음 업데이트 몫이라 눌리지 않는다.
class ProfileStatRow extends StatelessWidget {
  const ProfileStatRow({
    required this.friendCount,
    required this.receivedCount,
    required this.onTap,
    super.key,
  });

  final int friendCount;

  /// 내가 답해야 할 요청 수.
  ///
  /// ⚠️ **친구 목록 첫 장(20개)에서 센 값이다.** 받은 요청 수를 주는 API가
  /// 따로 없다. 서버가 받은 요청을 맨 앞에 두므로 대개 맞지만, 20이면 그보다
  /// 많다는 뜻이라 `20+`로 적는다.
  final int receivedCount;

  final VoidCallback onTap;

  /// 첫 장에 담기는 수. 이만큼이면 그보다 많다는 뜻이다.
  static const _badgeMax = 20;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.space2),
            child: Row(
              children: [
                // 시안의 팔로우 행이 쓰던 사람 글리프를 그대로 쓴다.
                SvgPicture.asset(
                  'assets/icons/people.svg',
                  width: 18,
                  height: 18,
                  colorFilter: ColorFilter.mode(
                    colors.primary,
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(width: AppSpacing.space3),
                Text(
                  AppStrings.friendProfileEntry(friendCount),
                  style: AppTypographyV2.body05.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                if (receivedCount > 0) ...[
                  const SizedBox(width: AppSpacing.space2),
                  _Badge(count: receivedCount),
                ],
                const Spacer(),
                Icon(
                  LucideIcons.chevronRight,
                  size: 18,
                  color: colors.textTertiary,
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.space2),
          child: Row(
            children: [
              Icon(LucideIcons.medal, size: 18, color: colors.textTertiary),
              const SizedBox(width: AppSpacing.space3),
              Text(
                AppStrings.friendAchievement,
                style: AppTypographyV2.body05.copyWith(
                  color: colors.textTertiary,
                ),
              ),
              const SizedBox(width: AppSpacing.space2),
              _SoonTag(label: AppStrings.friendAchievementSoon),
            ],
          ),
        ),
        const _AchievementSilhouette(),
      ],
    );
  }

  static String labelOf(int count) =>
      count >= _badgeMax ? AppStrings.friendBadgeOverflow : '$count';
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.error,
        borderRadius: AppRadius.full,
      ),
      child: Text(
        ProfileStatRow.labelOf(count),
        style: AppTypographyV2.body11.copyWith(color: colors.bgBase),
      ),
    );
  }
}

class _SoonTag extends StatelessWidget {
  const _SoonTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2),
      decoration: BoxDecoration(
        border: Border.all(color: colors.borderDefault),
        borderRadius: AppRadius.sm,
      ),
      child: Text(
        label,
        style: AppTypographyV2.body11.copyWith(color: colors.textTertiary),
      ),
    );
  }
}

/// 다음 업데이트에 올 것의 윤곽.
///
/// ## ⚠️ 빈 자리를 그냥 두지 않는다
///
/// 러닝 기록 항목마다 한 줄, 단계 진행률을 막대로, **다음 단계 자리에 깃발**을
/// 꽂는다. 흐리게 깔아 "여기에 무엇이 올지"만 보여 주고 누를 수는 없다.
///
/// 항목과 단계 수는 아직 정해지지 않았다. 정해지면 이 상수만 갈아끼운다.
class _AchievementSilhouette extends StatelessWidget {
  const _AchievementSilhouette();

  /// (항목, 지금까지, 다음 단계) — 모두 0~1.
  static const _rows = [
    ('거리', 0.62, 0.82),
    ('속도', 0.35, 0.50),
    ('지구력', 0.78, 0.90),
    ('꾸준함', 0.18, 0.33),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(color: colors.borderDefault, height: 1),
          const SizedBox(height: AppSpacing.space4),
          Text(
            AppStrings.friendAchievementTitle,
            textAlign: TextAlign.center,
            style: AppTypographyV2.body07.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.space4),
          Opacity(
            opacity: .5,
            child: Column(
              children: [
                for (final (label, done, next) in _rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.space3),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 52,
                          child: Text(
                            label,
                            style: AppTypographyV2.body11.copyWith(
                              color: colors.textTertiary,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.space3),
                        Expanded(
                          child: _Bar(done: done, next: next),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.done, required this.next});

  final double done;
  final double next;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        height: 14,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            Container(
              height: 8,
              decoration: BoxDecoration(
                color: colors.bgElevated,
                borderRadius: AppRadius.full,
              ),
            ),
            FractionallySizedBox(
              widthFactor: done,
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  color: colors.textTertiary,
                  borderRadius: AppRadius.full,
                ),
              ),
            ),
            // 다음 단계 자리. 채워진 곳보다 앞에 꽂혀, 얼마나 남았는지가
            // 그림으로 읽힌다.
            Positioned(
              left: constraints.maxWidth * next - 5,
              child: Icon(
                LucideIcons.flag,
                size: 11,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
