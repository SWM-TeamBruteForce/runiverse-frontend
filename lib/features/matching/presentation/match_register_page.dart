import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_sizes.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/core/widgets/preset_chip.dart';
import 'package:runiverse/features/matching/domain/match_failure.dart';
import 'package:runiverse/features/matching/domain/target_distance.dart';
import 'package:runiverse/features/matching/presentation/match_register_provider.dart';
import 'package:runiverse/features/matching/presentation/match_room_provider.dart';
import 'package:runiverse/features/matching/presentation/match_slot_sheet.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// 매칭 등록 (S08).
///
/// 시간대와 목표 거리를 골라 서버에 신청한다. **페이스와 인원은 받지 않는다** —
/// 페이스는 서버가 보관한 평균을 쓰고, 인원은 서버가 2~4명으로 편성한다.
///
/// ## 정본에서 뺀 것
///
/// - **시그니처 컬러 확인 줄** — 색을 모으는 기능이 아직 없다. 확인할 색도
///   바꿀 셰이드도 없는 자리에 줄을 두면 고장 난 것으로 읽힌다
/// - **위치 권한 시트** — 위치가 실제로 필요한 시점은 달리기 시작할 때이고,
///   출발 준비 화면이 이미 그 자리에서 묻는다
class MatchRegisterPage extends ConsumerStatefulWidget {
  const MatchRegisterPage({super.key});

  @override
  ConsumerState<MatchRegisterPage> createState() => _MatchRegisterPageState();
}

class _MatchRegisterPageState extends ConsumerState<MatchRegisterPage> {
  @override
  void initState() {
    super.initState();
    // 화면이 서기 전에 provider를 만지면 안 된다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(matchRegisterProvider.notifier).loadSlots();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final state = ref.watch(matchRegisterProvider);

    // 실패는 스낵바로 알리고 곧바로 지운다. 상태에 남겨두면 화면이 다시
    // 그려질 때마다 같은 말을 되풀이한다.
    ref.listen(matchRegisterProvider.select((state) => state.failure), (
      _,
      failure,
    ) {
      if (failure == null) return;
      _tell(failure, ref.read(matchRegisterProvider).cooldownUntil);
      ref.read(matchRegisterProvider.notifier).clearFailure();
    });

    final selected = state.selected;

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        surfaceTintColor: Colors.transparent,
        title: Text(AppStrings.matchRegisterTitle, style: AppTypography.h3),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space4,
                  AppSpacing.space2,
                  AppSpacing.space4,
                  AppSpacing.space6,
                ),
                children: [
                  Text(
                    AppStrings.matchTimeLabel,
                    style: AppTypography.h3.copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.space3),

                  _SlotTrigger(
                    label: selected == null
                        ? AppStrings.matchTimePlaceholder
                        : AppStrings.matchSlotTime(selected.startAt),
                    waitingCount: selected?.waitingCount ?? 0,
                    // 목록을 받아오는 동안에는 열지 않는다. 빈 시트를 열면
                    // "고를 것이 없다"로 읽힌다.
                    onTap: state.loading ? null : _pickSlot,
                  ),
                  const SizedBox(height: AppSpacing.space3),

                  Text(
                    AppStrings.matchTimeHint,
                    style: AppTypography.caption.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space6),

                  Text(
                    AppStrings.matchDistanceLabel,
                    style: AppTypography.h3.copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.space3),

                  Row(
                    children: [
                      for (final distance in TargetDistance.values) ...[
                        Expanded(
                          child: PresetChip(
                            label: AppStrings.matchDistanceText(distance.km),
                            selected: state.distance == distance,
                            onTap: () => ref
                                .read(matchRegisterProvider.notifier)
                                .selectDistance(distance),
                          ),
                        ),
                        if (distance != TargetDistance.values.last)
                          const SizedBox(width: AppSpacing.space2),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.space6),

                  const _NoticeCard(
                    icon: LucideIcons.gauge,
                    message: AppStrings.matchPaceAuto,
                  ),
                  const SizedBox(height: AppSpacing.space4),

                  _Note(AppStrings.matchPlayerCountInfo),
                  const SizedBox(height: AppSpacing.space2),
                  _Note(AppStrings.matchCancelPolicy),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space4,
                0,
                AppSpacing.space4,
                AppSpacing.space4,
              ),
              child: AppButton(
                label: AppStrings.matchRegisterCta,
                // 둘 다 골라야 열린다. 보내는 중에도 잠근다 — 두 번 누르면
                // 중복 신청이 된다.
                onPressed: state.canSubmit ? _submit : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickSlot() async {
    final state = ref.read(matchRegisterProvider);
    final picked = await showMatchSlotSheet(
      context,
      slots: state.slots,
      selected: state.selected,
    );
    if (picked == null || !mounted) return;
    ref.read(matchRegisterProvider.notifier).selectSlot(picked);
  }

  Future<void> _submit() async {
    final roomId = await ref.read(matchRegisterProvider.notifier).submit();
    if (roomId == null || !mounted) return;

    // ⚠️ 순서가 정해져 있다 — 신청 응답을 받은 **뒤에** 붙는다. 활성 신청이
    // 없는데 열면 서버가 404로 거절하고, 그 뒤에 신청해도 이벤트가 오지 않는
    // 연결이 된다. 상태 갱신보다 먼저 붙어야 모집 중 인원 변동을 처음부터 받는다.
    ref.read(matchRoomProvider.notifier).connect();

    // 신청이 됐으니 서버가 아는 상태가 달라졌다. 홈 배너가 그 값을 본다.
    await ref.read(userStatusProvider.notifier).refresh();
    if (!mounted) return;

    // 등록 화면을 닫고 홈으로 돌아간다. **모집 중에는 갈 화면이 따로 없다** —
    // 홈 히어로가 몇 명 모였는지와 마감까지를 보여주고, 방으로 가는 문은
    // 확정된 뒤에야 열린다(정본 S05).
    context.pop();
  }

  /// 실패를 말로 옮긴다. **서버 문장을 그대로 띄우지 않는다** — 사용자가
  /// 무엇을 할 수 있는지가 문구에 들어가야 한다.
  void _tell(MatchFailure failure, DateTime? cooldownUntil) {
    final message = switch (failure) {
      MatchFailure.slotClosed => AppStrings.matchFailedSlotClosed,
      MatchFailure.cooldown => AppStrings.matchFailedCooldown(cooldownUntil),
      MatchFailure.alreadyInProgress => AppStrings.matchFailedAlready,
      // 신청 경로에서는 나오지 않는다 — 취소에만 걸리는 코드다. 그래도
      // `unknown`으로 뭉개지 않는다. 나오면 그 자체가 알아야 할 신호다.
      MatchFailure.alreadyStarted => AppStrings.matchFailedAlreadyStarted,
      MatchFailure.onboardingNotCompleted => AppStrings.matchFailedOnboarding,
      MatchFailure.invalidRequest => AppStrings.matchFailedInvalid,
      MatchFailure.network => AppStrings.matchFailedNetwork,
      MatchFailure.sessionExpired => AppStrings.matchFailedExpired,
      // ⚠️ `network`와 같은 말을 쓰지 않는다. 그쪽은 "신청이 나갔는지 모른다"는
      // 뜻이라 재시도를 막는 문구인데, 여기는 서버가 답은 했지만 읽지 못한
      // 경우다. 사용자가 할 일이 달라 문구도 달라야 한다.
      MatchFailure.nothingToCancel ||
      MatchFailure.unknown => AppStrings.matchFailedUnknown,
    };

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 시간대를 고르는 트리거. 고른 뒤에는 시각과 대기 인원을 함께 보여준다.
class _SlotTrigger extends StatelessWidget {
  const _SlotTrigger({
    required this.label,
    required this.waitingCount,
    required this.onTap,
  });

  final String label;
  final int waitingCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.md,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSizes.touchDefault),
          decoration: BoxDecoration(
            color: colors.bgSurface,
            borderRadius: AppRadius.md,
            border: Border.all(color: colors.borderDefault),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space4,
            vertical: AppSpacing.space3,
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.clock,
                size: AppSpacing.space5,
                color: colors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.space3),
              Text(
                label,
                style: AppTypography.bodyLg.copyWith(
                  color: colors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (waitingCount > 0) ...[
                const SizedBox(width: AppSpacing.space3),
                Text(
                  AppStrings.matchWaitingCount(waitingCount),
                  style: AppTypography.caption.copyWith(
                    color: colors.matchWaiting,
                  ),
                ),
              ],
              const Spacer(),
              Icon(
                LucideIcons.chevronRight,
                size: AppSpacing.space5,
                color: colors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 사용자가 입력하지 않는 조건을 밝히는 카드.
class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: AppRadius.md,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: Row(
          children: [
            Icon(icon, size: AppSpacing.space5, color: colors.textSecondary),
            const SizedBox(width: AppSpacing.space3),
            Expanded(
              child: Text(
                message,
                style: AppTypography.body.copyWith(color: colors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 등록 전에 알아야 하는 규칙 한 줄.
class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          LucideIcons.info,
          size: AppSpacing.space4,
          color: colors.textTertiary,
        ),
        const SizedBox(width: AppSpacing.space2),
        Expanded(
          child: Text(
            text,
            style: AppTypography.caption.copyWith(color: colors.textTertiary),
          ),
        ),
      ],
    );
  }
}
