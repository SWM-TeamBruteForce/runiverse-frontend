import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_sizes.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/core/widgets/v2/app_icon.dart';
import 'package:runiverse/core/widgets/v2/preset_chip.dart';
import 'package:runiverse/core/widgets/v2/surface_card.dart';
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
    final colors = context.appColorsV2;
    final state = ref.watch(matchRegisterProvider);

    // ⚠️ **홈이 막아도 여기까지 와 있을 수 있다.** 화면을 열어 둔 사이에 러닝을
    // 중간에 그만두면 제한이 새로 걸린다 — 그때 보내면 409만 받는다.
    final cooldownUntil = ref.watch(
      userStatusProvider.select((status) => status?.cooldownUntil),
    );
    final cooling =
        cooldownUntil != null && cooldownUntil.isAfter(DateTime.now());

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
    // 슬롯을 아직 안 골랐거나 서버가 안 알려주면 0으로 본다. `int?`라 그대로
    // 넘기면 배너가 "null명 대기"를 그린다.
    final waiting = selected?.waitingCount ?? 0;

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        surfaceTintColor: Colors.transparent,
        title: Text(
          AppStrings.matchRegisterTitle,
          style: AppTypographyV2.heading06.copyWith(color: colors.textPrimary),
        ),
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
                  _Label(AppStrings.matchTimeLabel),
                  const SizedBox(height: AppSpacing.space3),

                  _SlotTrigger(
                    label: selected == null
                        ? AppStrings.matchTimePlaceholder
                        : AppStrings.matchSlotTime(selected.startAt),
                    onTap: _pickSlot,
                  ),

                  // ⚠️ 대기 인원을 **시각 카드에서 떼어냈다.** 시안(`158:3186`)이
                  // 별도 줄로 둔다 — 시각은 내가 고르는 것이고 대기 인원은
                  // 그 결과라, 한 줄에 섞으면 무엇이 입력인지 흐려진다.
                  if (waiting > 0) ...[
                    const SizedBox(height: AppSpacing.space3),
                    _WaitingBanner(count: waiting),
                  ],
                  const SizedBox(height: AppSpacing.space3),

                  Text(
                    AppStrings.matchTimeHint,
                    style: AppTypographyV2.body12.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space6),

                  _Label(AppStrings.matchDistanceLabel),
                  const SizedBox(height: AppSpacing.space3),

                  Row(
                    children: [
                      for (final distance in TargetDistance.values) ...[
                        Expanded(
                          child: PresetChipV2(
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

                  // ⚠️ 시안에는 이 셋의 자리가 없다. **그래도 남긴다** —
                  // 사용자가 고르지 않는 조건(페이스·인원)과 20분 제재를
                  // 알리는 유일한 자리다. 시안은 `도움말 / 취소정책` 카드로
                  // 대신하는데, 우리에겐 그 화면이 없어 눌러도 갈 곳이 없다.
                  const _NoticeCard(message: AppStrings.matchPaceAuto),
                  const SizedBox(height: AppSpacing.space4),

                  _Note(AppStrings.matchPlayerCountInfo),
                  const SizedBox(height: AppSpacing.space2),
                  _Note(AppStrings.matchCancelPolicy),
                ],
              ),
            ),

            // 잠긴 이유를 글로 말한다. 누를 수도 없고 까닭도 없으면 고장난
            // 것으로 읽힌다.
            if (cooling)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space4,
                  0,
                  AppSpacing.space4,
                  AppSpacing.space2,
                ),
                child: Text(
                  AppStrings.matchFailedCooldown(cooldownUntil),
                  style: AppTypographyV2.body12.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ),

            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space4,
                0,
                AppSpacing.space4,
                AppSpacing.space4,
              ),
              child: AppButtonV2(
                label: AppStrings.matchRegisterCta,
                // 둘 다 골라야 열린다. 보내는 중에도 잠근다 — 두 번 누르면
                // 중복 신청이 된다. 제한 중이면 보낼 이유가 없다.
                onPressed: state.canSubmit && !cooling ? _submit : null,
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
/// 화면 안의 작은 제목.
class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppTypographyV2.body05.copyWith(
      color: context.appColorsV2.textStrong,
    ),
  );
}

/// 시각을 고르는 자리. 시안 `158:3218`.
class _SlotTrigger extends StatelessWidget {
  const _SlotTrigger({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final picked = onTap != null;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.lg,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSizes.touchDefault),
          decoration: BoxDecoration(
            color: colors.bgSurface,
            borderRadius: AppRadius.lg,
          ),
          padding: const EdgeInsets.all(AppSpacing.space5),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTypographyV2.body04.copyWith(
                    color: colors.textTertiary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              AppIcon(
                AppIcons.right,
                size: AppSpacing.space6,
                color: picked ? colors.textTertiary : colors.textDisabled,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 고른 시각에 몇 명이 기다리는지. 시안 `158:3186`.
class _WaitingBanner extends StatelessWidget {
  const _WaitingBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: AppRadius.md,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space5,
          vertical: AppSpacing.space3,
        ),
        child: Row(
          children: [
            AppIcon(
              AppIcons.people,
              size: AppSpacing.space6,
              color: colors.matchWaiting,
            ),
            const SizedBox(width: AppSpacing.space3),
            Text(
              AppStrings.matchWaitingCount(count),
              style: AppTypographyV2.body11.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

/// 사용자가 입력하지 않는 조건을 밝히는 카드.
class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return SurfaceCard(
      padding: const EdgeInsets.all(AppSpacing.space4),
      child: Row(
        children: [
          AppIcon(
            AppIcons.running,
            size: AppSpacing.space5,
            color: colors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.space3),
          Expanded(
            child: Text(
              message,
              style: AppTypographyV2.body12.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
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
    final colors = context.appColorsV2;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppIcon(
          AppIcons.guide,
          size: AppSpacing.space4,
          color: colors.textTertiary,
        ),
        const SizedBox(width: AppSpacing.space2),
        Expanded(
          child: Text(
            text,
            style: AppTypographyV2.body12.copyWith(color: colors.textTertiary),
          ),
        ),
      ],
    );
  }
}
