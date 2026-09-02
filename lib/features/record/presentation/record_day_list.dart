import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/features/record/domain/run_record.dart';

/// 고른 날의 기록들. 정본 S21 `52:274`다.
///
/// ## 날짜별 상태 3종을 여기서 다 처리한다
///
/// **다회**면 카드가 여러 장, **단일**이면 한 장, **빈 날**이면 안내 문구다.
/// 정본은 단일일 때 상세로 직행하라고 적었지만, 그건 캘린더를 누르는 쪽의
/// 동작이라 이 위젯은 언제나 목록을 그린다.
///
/// ## ⚠️ 행마다 카드가 따로다
///
/// 한 카드 안에 구분선으로 나누지 않는다. Figma는 행 하나가 곧 카드
/// (`radius 16` + 테두리)이고 사이가 12만큼 벌어져 있다.
class RecordDayList extends StatelessWidget {
  const RecordDayList({
    required this.day,
    required this.records,
    this.onOpen,
    super.key,
  });

  final DateTime day;
  final List<RunRecord> records;

  /// 기록을 눌렀을 때. **아직 없다** — 상세는 서버 값(20번)으로 붙일 예정이라
  /// `null`이면 카드가 눌리지 않는다.
  final ValueChanged<RunRecord>? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppStrings.recordDayLabel(day, records.length),
          style: AppTypography.body.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.space3),

        if (records.isEmpty)
          const _Empty()
        else
          for (var i = 0; i < records.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.space3),
            _Card(record: records[i], onOpen: onOpen),
          ],
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        border: Border.all(color: colors.borderDefault),
        borderRadius: AppRadius.lg,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space4,
          vertical: AppSpacing.space6,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.footprints,
              size: AppSpacing.space5,
              color: colors.textTertiary,
            ),
            const SizedBox(width: AppSpacing.space2),
            Flexible(
              child: Text(
                AppStrings.recordDayEmpty,
                style: AppTypography.body.copyWith(color: colors.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 러닝 한 건. Figma `52:277`.
class _Card extends StatelessWidget {
  const _Card({required this.record, required this.onOpen});

  final RunRecord record;
  final ValueChanged<RunRecord>? onOpen;

  /// 왼쪽 컬러 막대. Figma 실측 그대로다.
  ///
  /// **이 높이가 카드 높이를 정한다.** 글 두 줄(22 + 3 + 14 = 39)보다 커서,
  /// 동행 정보 줄이 없어도 카드가 눌리지 않는다.
  static const _accentWidth = 10.0;
  static const _accentHeight = 44.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final open = onOpen;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        border: Border.all(color: colors.borderDefault),
        borderRadius: AppRadius.lg,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: open == null ? null : () => open(record),
          borderRadius: AppRadius.lg,
          child: Padding(
            // Figma `px-16 py-14`. 14는 토큰에 없어 space3(12)과 space4(16)
            // 사이인데, 막대가 높이를 정하므로 space3으로 둬도 카드 높이는
            // 72로 같다.
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space4,
              vertical: AppSpacing.space3,
            ),
            child: Row(
              children: [
                // 그날 획득한 러닝 컬러.
                //
                // ⚠️ Figma는 러닝 팔레트 색(`run-company-2` 등)에 글로우까지
                // 얹었지만, **색 생성 규칙이 아직 없어** 단색으로 둔다.
                // 규칙이 정해지면 색과 `AppGlow`를 함께 붙인다.
                Container(
                  width: _accentWidth,
                  height: _accentHeight,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: AppRadius.sm,
                  ),
                ),
                const SizedBox(width: AppSpacing.space3),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        // 숫자 크기가 달라도 글자 바닥을 맞춘다.
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(
                              AppStrings.recordRunLabel(
                                record.startedAt,
                                record.distanceKm,
                              ),
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.body.copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.space2),
                          Text(
                            AppStrings.recordRunDuration(record.duration),
                            style: AppTypography.body.copyWith(
                              color: colors.textTertiary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // ⚠️ **둘째 줄이 비어 있다.** Figma는 여기에
                      // `이서연 님과 매칭` / `혼자 연습하기`를 적지만,
                      // 목록 API(19번)가 동행 정보를 주지 않는다.
                      // 서버가 실어 주면 이 자리에 붙인다.
                    ],
                  ),
                ),

                const SizedBox(width: AppSpacing.space2),
                Icon(
                  LucideIcons.chevronRight,
                  size: AppSpacing.space5,
                  color: colors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
