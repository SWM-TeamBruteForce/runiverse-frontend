import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_sizes.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/utils/kst_time.dart';
import 'package:runiverse/features/matching/domain/match_slot.dart';

/// 평소 신청이 가장 많이 모이는 시각. 앞에서부터 **아직 열린 첫 시각**에
/// `추천`이 붙는다 — 18:00이 마감되면 19:00으로 넘어간다.
///
/// 운영 DB(2026-10-23~11-09)에서 신청한 사람이 18:00 20명, 19:00 14명이고
/// 나머지 시각은 8명 이하였다.
///
/// ⚠️ **앱이 시각을 들고 있다.** 시간대는 서버 설정값이라 앱이 적어 두지
/// 않는다는 원칙([MatchSlot])과 어긋난다. 서버가 시각을 바꾸면 추천이 조용히
/// 안 뜰 뿐 엉뚱한 줄에 붙지는 않아서, 응답을 늘리지 않고 여기 둔다.
const _recommendedHours = [18, 19];

/// `추천`을 붙일 줄. **없으면 `null`이다.**
///
/// ## ⚠️ 고른 거리에 누가 있으면 붙이지 않는다
///
/// 그 줄의 `N명 대기`가 가장 확실한 추천이다. 빈 18:00에 `추천`이 남아 있으면
/// 추천을 믿고 고른 사람과 먼저 신청한 사람이 각자 혼자 남는다. 마감된 줄의
/// 숫자는 세지 않는다 — 이제 들어갈 수 없는 사람이다.
///
/// ## ⚠️ 한 줄만 고른다
///
/// 18:00과 19:00에 둘 다 붙이면 신청이 다시 두 시각으로 갈린다. 같은 거리인데
/// 18:00과 19:00으로 나뉘어 둘 다 혼자 남은 날이 실제로 있었다.
MatchSlot? recommendedSlot(List<MatchSlot> slots) {
  final open = [
    for (final slot in slots)
      if (slot.selectable) slot,
  ];
  if (open.any((slot) => slot.waitingCount > 0)) return null;

  for (final hour in _recommendedHours) {
    for (final slot in open) {
      // ⚠️ **정각만 본다.** 시만 보면 30분 간격일 때 18:30도 18시라, 18:00이
      // 마감된 뒤 19:00이 아니라 18:30에 붙는다.
      final wall = KstTime.wallOf(slot.startAt);
      if (wall.hour == hour && wall.minute == 0) return slot;
    }
  }
  return null;
}

/// 시간대를 고르는 바텀시트. 고르면 그 칸을, 닫으면 `null`을 돌려준다.
///
/// ## ⚠️ 고른 거리 하나의 줄이다
///
/// 한 줄이 그 거리의 [MatchSlot]이다. 숫자도 잠금도 **그 거리의 것**이라,
/// 적힌 `1명 대기`가 곧 들어갔을 때 만나는 사람이다. 그래서 거리를 고르기
/// 전에는 열리지 않는다.
///
/// 전에는 한 줄이 모든 거리를 접은 합계였다. 거리가 다르면 같은 방에 매칭되지
/// 않으므로, 10km의 1명을 보고 5km로 들어가면 아무도 없었다.
Future<MatchSlot?> showMatchSlotSheet(
  BuildContext context, {
  required List<MatchSlot> slots,
  MatchSlot? selected,
}) {
  return showModalBottomSheet<MatchSlot>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: context.appColors.bgScrim,
    isScrollControlled: true,
    builder: (context) => _SlotSheet(slots: slots, selected: selected),
  );
}

class _SlotSheet extends StatelessWidget {
  const _SlotSheet({required this.slots, this.selected});

  final List<MatchSlot> slots;
  final MatchSlot? selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final recommended = recommendedSlot(slots);

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: colors.bgElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.space5,
          AppSpacing.space3,
          AppSpacing.space5,
          AppSpacing.space5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.borderStrong,
                  borderRadius: AppRadius.full,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.space4),

            Text(
              AppStrings.matchSlotSheetTitle,
              style: AppTypography.h3.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.space3),

            if (slots.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.space6,
                ),
                child: Text(
                  AppStrings.matchSlotEmpty,
                  textAlign: TextAlign.center,
                  style: AppTypography.body.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              )
            else
              // 아홉 칸이 화면 높이를 넘긴다. 시트가 화면을 다 먹지 않도록
              // 위쪽을 남기고 안에서 굴린다.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: slots.length,
                  itemBuilder: (context, index) => _SlotRow(
                    slot: slots[index],
                    isSelected: slots[index].raw == selected?.raw,
                    isRecommended: slots[index].raw == recommended?.raw,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 시간대 한 줄.
///
/// **마감된 줄도 남긴다.** 목록에서 빼면 "18:00이 왜 없지"가 되고, 시간이
/// 흐르며 목록이 줄어드는 것도 이상하게 읽힌다. 남기되 눌리지 않게 한다.
class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.slot,
    required this.isSelected,
    required this.isRecommended,
  });

  final MatchSlot slot;
  final bool isSelected;

  /// [recommendedSlot]이 고른 줄인가.
  final bool isRecommended;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final closed = !slot.selectable;

    return Semantics(
      selected: isSelected,
      enabled: !closed,
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: closed ? null : () => Navigator.of(context).pop(slot),
          borderRadius: AppRadius.sm,
          child: Container(
            constraints: const BoxConstraints(minHeight: AppSizes.touchDefault),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3),
            child: Row(
              children: [
                Text(
                  AppStrings.matchSlotTime(slot.startAt),
                  style: AppTypography.bodyLg.copyWith(
                    color: closed ? colors.textTertiary : colors.textPrimary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    // 시각이 세로로 나열된다. 자릿수가 흔들리면 줄이 어긋난다.
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: AppSpacing.space3),

                if (closed)
                  Text(
                    AppStrings.matchSlotClosed,
                    style: AppTypography.caption.copyWith(
                      color: colors.textTertiary,
                    ),
                  )
                else if (slot.waitingCount > 0)
                  // 대기 인원은 강조색이다 — 사회적 증거로 슬롯을 유도한다.
                  // **0이면 아무것도 적지 않는다.** `0명 대기`는 비어 있다고
                  // 알리는 꼴이라 오히려 사람을 민다.
                  //
                  // ⚠️ **고른 거리의 수다.** 등록 버튼의 숫자와 같다.
                  Text(
                    AppStrings.matchWaitingCount(slot.waitingCount),
                    style: AppTypography.caption.copyWith(
                      color: colors.matchWaiting,
                    ),
                  )
                else if (isRecommended)
                  // `1명 대기`·`마감`과 같은 자리·크기의 글씨다. 색은 대기와
                  // 갈라 둔다 — 같은 색이면 아무도 없는 줄이 "누가 있다"로 읽힌다.
                  Text(
                    AppStrings.matchSlotRecommended,
                    style: AppTypography.caption.copyWith(
                      color: colors.primary,
                    ),
                  ),

                const Spacer(),

                if (isSelected)
                  Icon(
                    LucideIcons.check,
                    size: AppSpacing.space5,
                    color: colors.primary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
