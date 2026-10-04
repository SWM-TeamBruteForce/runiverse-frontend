import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_sizes.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/features/record/domain/run_record.dart';

/// 고른 날의 기록들 — 시안 `158:3877`~`158:3887`.
///
/// ## ⚠️ 카드가 아니라 줄이다
///
/// 옛 화면은 기록 하나가 테두리 두른 카드였다. 시안은 **캘린더 카드 안쪽**에
/// 줄로 쌓는다 — 카드 안에 카드를 넣으면 테두리가 두 겹으로 보인다.
///
/// ## ⚠️ 뱃지 줄은 만들지 않았다
///
/// 시안 `158:3885`·`158:3886`이 `언덕 정복자 뱃지를 획득했습니다` 같은 줄을
/// 그리는데, **백엔드에 뱃지 기능이 아직 없다**(📅 기록 탭 연동 가이드 2장).
/// 지어내지 않는다.
class RecordDayList extends StatelessWidget {
  const RecordDayList({
    required this.day,
    required this.records,
    this.onOpen,
    super.key,
  });

  final DateTime day;
  final List<RunRecord> records;

  /// 기록을 눌렀을 때. `null`이면 줄이 눌리지 않는다.
  final ValueChanged<RunRecord>? onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DayHeader(day: day, count: records.length),
        const SizedBox(height: AppSpacing.space4),

        if (records.isEmpty)
          const _Empty()
        else
          for (final record in records) _Row(record: record, onOpen: onOpen),
      ],
    );
  }
}

/// `Today` 칩과 그날 한 줄 요약 — 시안 `158:3877`.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.count});

  final DateTime day;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Row(
      children: [
        // ⚠️ **오늘일 때만 붙인다.** 늘 띄우면 어느 날을 보고 있는지 흐려진다.
        if (_isToday(day)) ...[
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.primaryMuted,
              borderRadius: AppRadius.sm,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space3,
                vertical: AppSpacing.space1,
              ),
              child: Text(
                AppStrings.recordToday,
                style: AppTypographyV2.body18.copyWith(color: colors.primary),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.space3),
        ],

        Expanded(
          child: Text(
            AppStrings.recordDayLabel(day, count),
            style: AppTypographyV2.body11.copyWith(color: colors.textStrong),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// 기기의 오늘. 칩을 붙일지만 정하므로 시계를 주입하지 않는다.
  static bool _isToday(DateTime day) {
    final now = DateTime.now();
    return day.year == now.year && day.month == now.month && day.day == now.day;
  }
}

/// 러닝 한 건 — 시안 `158:3887`.
///
/// `17:00:00 시작 · 2.5 km · 00:30:00 소요`
class _Row extends StatelessWidget {
  const _Row({required this.record, required this.onOpen});

  final RunRecord record;
  final ValueChanged<RunRecord>? onOpen;

  /// ⚠️ **눌리는 높이를 여기서 보장한다.**
  ///
  /// 글자(14 × 1.5 ≈ 21)에 위아래 여백만 주면 45가 나오지만, 글꼴이나 배율이
  /// 바뀌면 44 아래로 내려갈 수 있다. 바닥을 못 박아 둔다.
  static const _minHeight = AppSizes.touchDefault;

  /// 줄 앞의 점. 러닝 하나라는 표시다.
  static const _bulletSize = 6.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final open = onOpen;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space2),
      child: Material(
        color: Colors.transparent,
        // ⚠️ **면을 깔지 않고 테두리만 두른다.** 이 줄은 캘린더 카드 **안**에
        // 있어서, 면까지 깔면 카드 안의 카드가 되어 테두리가 두 겹으로 보인다.
        // 테두리만 있으면 "누를 자리"로 읽힌다.
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.md,
          side: BorderSide(color: colors.borderDefault),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: open == null ? null : () => open(record),
          child: Container(
            constraints: const BoxConstraints(minHeight: _minHeight),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space4,
              vertical: AppSpacing.space3,
            ),
            child: Row(
              children: [
                Container(
                  width: _bulletSize,
                  height: _bulletSize,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.space3),

                Expanded(
                  child: Text(
                    AppStrings.recordRunLine(
                      record.startedAt,
                      record.distanceKm,
                      record.duration,
                    ),
                    style: AppTypographyV2.body11.copyWith(
                      color: colors.textStrong,
                      // 시각·거리·소요가 한 줄에 선다. 안 주면 줄마다 어긋난다.
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 그날 안 뛰었다.
class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space3),
      child: Text(
        AppStrings.recordDayEmpty,
        style: AppTypographyV2.body15.copyWith(color: colors.textTertiary),
      ),
    );
  }
}
