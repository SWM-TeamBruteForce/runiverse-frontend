import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_motion.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/features/session/domain/party_board.dart';

/// 파티원 비교 (S13 3페이지).
///
/// ## ⚠️ 위치를 그리지 않는다
///
/// 진행률과 격차만 보여준다. GPS 좌표·경로는 어떤 화면으로도 파티원에게
/// 드러내지 않는 것이 정책이다(`CLAUDE.md`).
///
/// ## 등수를 적지 않는다
///
/// 막대 길이로 앞뒤가 보이지만 `1등`·`2등`을 쓰지 않는다. 경쟁이 아니라
/// 동행이다 — 문구도 그 프레임으로 적었다.
///
/// ## 정본에서 뺀 것
///
/// - **참가자별 고유색** — 색을 모으는 기능이 아직 없다. 내 레인만 강조하고
///   나머지는 같은 톤으로 둔다
class RunPartyView extends StatelessWidget {
  const RunPartyView({
    required this.board,
    required this.myDistanceMeters,
    this.targetDistanceMeters,
    super.key,
  });

  final PartyBoard board;

  /// **앱이 계산한 내 거리다.** 서버 값이 아니다 — 서버는 본인 진행을 보내지
  /// 않고, 화면 표시는 로컬 계산값을 우선한다.
  final int myDistanceMeters;

  /// 목표 거리. 모르면 막대를 그리지 않는다.
  final int? targetDistanceMeters;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final rows = board.rows;

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space5,
        vertical: AppSpacing.space4,
      ),
      children: [
        Text(
          AppStrings.runPartyTitle,
          style: AppTypography.h3.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.space1),
        Text(
          AppStrings.runPartyHint,
          style: AppTypography.caption.copyWith(color: colors.textTertiary),
        ),
        const SizedBox(height: AppSpacing.space5),

        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.space8),
            child: Text(
              AppStrings.runPartyEmpty,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(color: colors.textSecondary),
            ),
          )
        else ...[
          // 내 레인을 함께 세운다. 나 없이 남들만 보이면 어디쯤인지 알 수 없다.
          _Lane(
            label: AppStrings.runPartyMe,
            meters: myDistanceMeters,
            targetMeters: targetDistanceMeters,
            isMe: true,
          ),
          for (final row in rows) ...[
            const SizedBox(height: AppSpacing.space3),
            _Lane(
              label: row.member?.nickname ?? AppStrings.runPartyUnknown,
              meters: row.progress?.distanceMeters ?? 0,
              targetMeters:
                  row.progress?.targetDistanceMeters ?? targetDistanceMeters,
              isMe: false,
              paused: row.progress?.paused ?? false,
            ),
          ],

          const SizedBox(height: AppSpacing.space6),
          for (final row in rows) ...[
            _GapRow(row: row, myDistanceMeters: myDistanceMeters),
            const SizedBox(height: AppSpacing.space2),
          ],
        ],
      ],
    );
  }
}

/// 진행률 막대 한 줄.
class _Lane extends StatelessWidget {
  const _Lane({
    required this.label,
    required this.meters,
    required this.isMe,
    this.targetMeters,
    this.paused = false,
  });

  final String label;
  final int meters;
  final bool isMe;
  final int? targetMeters;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final target = targetMeters;
    // ⚠️ 목표를 모르면 막대를 그리지 않는다. 임의의 기준으로 칠하면 거짓말이다.
    final ratio = target == null || target <= 0
        ? null
        : (meters / target).clamp(0.0, 1.0);

    return Row(
      children: [
        SizedBox(
          width: AppSpacing.space10,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(
              color: isMe ? colors.primary : colors.textSecondary,
              fontWeight: isMe ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.space2),

        Expanded(
          child: ClipRRect(
            borderRadius: AppRadius.full,
            child: SizedBox(
              height: AppSpacing.space2,
              child: Stack(
                children: [
                  ColoredBox(
                    color: colors.bgSurface,
                    child: const SizedBox.expand(),
                  ),
                  if (ratio != null)
                    // 10초마다 값이 튄다. 애니메이션이 없으면 막대가 뚝뚝 뛴다.
                    FractionallySizedBox(
                      widthFactor: ratio,
                      child: AnimatedContainer(
                        duration: AppMotion.base,
                        curve: AppMotion.easeStandard,
                        color: paused
                            ? colors.textTertiary
                            : isMe
                            ? colors.primary
                            : colors.matchWaiting,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.space2),

        SizedBox(
          width: AppSpacing.space10 + AppSpacing.space2,
          child: Text(
            AppStrings.runPartyDistance(meters),
            textAlign: TextAlign.end,
            style: AppTypography.caption.copyWith(
              color: colors.textPrimary,
              // 10초마다 갈리는 숫자다. 자릿수가 흔들리면 줄이 어긋난다.
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// 격차와 콤보 한 줄.
class _GapRow extends StatelessWidget {
  const _GapRow({required this.row, required this.myDistanceMeters});

  final PartyRow row;
  final int myDistanceMeters;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final progress = row.progress;

    // 서버가 준 콤보의 `gapMeters`를 우선한다 — 서버가 양쪽 누적 거리로 낸
    // 값이라 내 로컬 계산보다 두 사람 사이에서 일관된다.
    final gap =
        row.combo?.gapMeters ??
        (progress == null ? null : progress.distanceMeters - myDistanceMeters);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: AppRadius.md,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space3),
        child: Row(
          children: [
            Icon(
              LucideIcons.user,
              size: AppSpacing.space5,
              color: colors.textTertiary,
            ),
            const SizedBox(width: AppSpacing.space3),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.member?.nickname ?? AppStrings.runPartyUnknown,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  if (progress?.paused == true)
                    Text(
                      AppStrings.runPartyPaused,
                      style: AppTypography.caption.copyWith(
                        color: colors.textTertiary,
                      ),
                    )
                  else if (row.combo != null && row.combo!.comboCount > 0)
                    Text(
                      AppStrings.runPartyCombo(row.combo!.comboCount),
                      style: AppTypography.caption.copyWith(
                        color: colors.matchConfirmed,
                      ),
                    ),
                ],
              ),
            ),

            if (gap != null)
              Text(
                AppStrings.runPartyGap(gap),
                style: AppTypography.body.copyWith(
                  // 상대가 앞서면 눈에 띄게, 뒤처지면 차분하게. 어느 쪽도
                  // 오류색으로 칠하지 않는다 — 뒤처진 것은 잘못이 아니다.
                  color: gap > 0 ? colors.matchWaiting : colors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
