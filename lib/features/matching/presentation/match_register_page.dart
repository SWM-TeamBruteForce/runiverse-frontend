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
import 'package:runiverse/features/matching/domain/slot_load_failure.dart';
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
/// - **위치 권한 시트** — 위치가 실제로 필요한 시점은 달리기 시작할 때이고,
///   출발 준비 화면이 이미 그 자리에서 묻는다
class MatchRegisterPage extends ConsumerStatefulWidget {
  const MatchRegisterPage({super.key});

  @override
  ConsumerState<MatchRegisterPage> createState() => _MatchRegisterPageState();
}

class _MatchRegisterPageState extends ConsumerState<MatchRegisterPage> {
  // ⚠️ **진입에 목록을 받지 않는다.** 조회가 거리를 반드시 받는데 거리는
  // `null`로 시작하므로, 부를 수 있는 가장 이른 시점이 **거리를 고른 순간**이다
  // (`selectDistance`).

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
    final distance = state.distance;

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
                  // ⚠️ **거리가 시간보다 위에 선다.** 슬롯 목록을 받으려면
                  // 거리가 먼저 있어야 한다(조회가 필수로 받는다) — 화면
                  // 순서가 데이터가 흐르는 순서와 같아진다.
                  _Label(AppStrings.matchDistanceLabel),
                  const SizedBox(height: AppSpacing.space3),

                  Row(
                    children: [
                      for (final distance in TargetDistance.values) ...[
                        Expanded(
                          child: PresetChipV2(
                            label: AppStrings.matchDistanceText(distance.km),
                            selected: state.distance == distance,
                            // ⚠️ **어떤 상태에서도 잠그지 않는다.** 거리를
                            // 다시 고르는 것이 곧 다시 시도하는 길이다.
                            onTap: () => unawaited(
                              ref
                                  .read(matchRegisterProvider.notifier)
                                  .selectDistance(distance),
                            ),
                          ),
                        ),
                        if (distance != TargetDistance.values.last)
                          const SizedBox(width: AppSpacing.space2),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.space6),

                  _Label(AppStrings.matchTimeLabel),
                  const SizedBox(height: AppSpacing.space3),

                  _SlotTrigger(
                    label: selected == null
                        ? AppStrings.matchTimePlaceholder
                        : AppStrings.matchSlotTime(selected.startAt),
                    // 고를 것이 없으면 열지 않는다. 아래 줄이 이유를 말한다.
                    onTap: state.slotsReady ? _pickSlot : null,
                  ),

                  // ⚠️ **잠긴 이유를 반드시 적는다.** 눌러도 아무 일이 없고
                  // 까닭도 없으면 고장난 화면으로 읽힌다.
                  if (!state.slotsReady) ...[
                    const SizedBox(height: AppSpacing.space2),
                    _SlotsLockedNote(
                      message: _lockedMessage(state),
                      // 실패했을 때만 다시 시도를 붙인다. 거리를 안 고른
                      // 사람에게는 누를 것이 거리 칩이다.
                      //
                      // ⚠️ **세션 만료에는 안 붙인다.** 눌러 봐야 같은 답이고,
                      // 할 일은 다시 로그인하는 것이라 엉뚱한 길을 권하게 된다.
                      onRetry:
                          state.loadFailure != null &&
                              state.loadFailure !=
                                  SlotLoadFailure.sessionExpired &&
                              distance != null
                          ? () => unawaited(
                              ref
                                  .read(matchRegisterProvider.notifier)
                                  .selectDistance(distance),
                            )
                          : null,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.space3),

                  Text(
                    AppStrings.matchTimeHint,
                    style: AppTypographyV2.body12.copyWith(
                      color: colors.textTertiary,
                    ),
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

            // ⚠️ **거리만 골랐을 때만 선다.** 시간까지 고른 사람은 시트에서
            // 이미 그 시각의 수를 보고 골랐다 — 같은 말을 한 번 더 적는 셈이다.
            //
            // ⚠️ 자리를 미리 잡지 않는다. 늘 비워 두면 0명일 때 화면에 구멍이
            // 남는다. 나타날 때 CTA가 한 번 밀리는 쪽을 골랐다.
            if (distance != null && selected == null && state.waitingTotal > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space4,
                  0,
                  AppSpacing.space4,
                  AppSpacing.space3,
                ),
                child: _WaitingBanner(
                  km: distance.km,
                  count: state.waitingTotal,
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

  /// 시간 선택기가 왜 잠겼는지.
  ///
  /// **순서가 규칙이다.** 거리를 안 고른 것이 가장 구체적인 사정이고, 실패가
  /// 그다음, 비었음이 마지막이다 — 뒤로 갈수록 "그래서 고를 수 없다"에 가깝다.
  static String _lockedMessage(MatchRegisterState state) {
    if (state.distance == null) return AppStrings.matchSlotsLockedByDistance;
    if (state.loadingSlots) return AppStrings.matchSlotsLoading;
    // ⚠️ **세션 만료를 따로 말한다.** "불러오지 못했어요"로 묶으면 눌러도
    // 영원히 같은 화면이고, 빠져나오려면 다시 로그인해야 한다는 걸 알 길이
    // 없다. 신청 경로가 같은 상황에서 이미 이렇게 말한다.
    if (state.loadFailure == SlotLoadFailure.sessionExpired) {
      return AppStrings.matchFailedExpired;
    }
    if (state.loadFailure != null) return AppStrings.matchSlotsLoadFailed;
    return AppStrings.matchSlotsEmpty;
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
/// 시간 선택기가 잠긴 이유 한 줄. 실패했을 때만 다시 시도가 붙는다.
class _SlotsLockedNote extends StatelessWidget {
  const _SlotsLockedNote({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Row(
      children: [
        Expanded(
          child: Text(
            message,
            style: AppTypographyV2.body12.copyWith(color: colors.textTertiary),
          ),
        ),
        if (onRetry != null)
          TextButton(
            onPressed: onRetry,
            child: Text(
              AppStrings.matchSlotsRetry,
              style: AppTypographyV2.body12.copyWith(color: colors.primary),
            ),
          ),
      ],
    );
  }
}

class _WaitingBanner extends StatelessWidget {
  const _WaitingBanner({required this.km, required this.count});

  /// 고른 거리. 문구가 "현재 3km에"로 시작한다.
  final int km;

  /// **그 거리의 모든 시각을 더한 값**이다. 한 시각의 수가 아니다.
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
            Expanded(
              child: Text(
                AppStrings.matchWaitingTotal(km, count),
                style: AppTypographyV2.body11.copyWith(
                  color: colors.textPrimary,
                  // 거리를 바꾸면 자릿수가 흔들린다. 고정폭이라야 줄이 안 튄다.
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
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
