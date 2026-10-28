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
  @override
  void initState() {
    super.initState();
    // ⚠️ **들어오자마자 판을 받는다.** 조회가 거리를 필수로 받던 시절에는
    // 아무 거리로 한 번 물어 마감 여부만 보고 받은 숫자는 버렸다
    // (`probeToday`). 이제 한 번에 다 오므로 그 우회가 없다.
    //
    // 화면이 서기 전에 provider를 만지면 안 된다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_enter());
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
      // ⚠️ **마감과 이탈 제재는 여기서 다루지 않는다.** 둘은 팝업이고, 어느
      // 팝업인지는 재조회가 끝나야 갈린다 — `_submit`이 그 뒤에 띄운다.
      if (failure == MatchFailure.slotClosed ||
          failure == MatchFailure.cooldown) {
        return;
      }
      _tellInSnackBar(failure, ref.read(matchRegisterProvider).cooldownUntil);
      ref.read(matchRegisterProvider.notifier).clearFailure();
    });

    final time = state.time;

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
                  // ⚠️ **시간이 거리보다 위에 선다.** 2026-10-22에 뒤집은
                  // 이유는 조회가 거리를 필수로 받아서였다 — 거리를 모르면
                  // 시간 목록을 받을 수 없어 순서가 강제됐다. 그 제약이
                  // 사라졌으므로 시안의 순서로 돌아간다.
                  _Label(AppStrings.matchTimeLabel),
                  const SizedBox(height: AppSpacing.space3),

                  _SlotTrigger(
                    label: time == null
                        ? AppStrings.matchTimePlaceholder
                        : AppStrings.matchSlotTime(time.startAt),
                    // 고를 것이 없으면 열지 않는다. 아래 줄이 이유를 말한다.
                    onTap: state.slotsReady ? _pickSlot : null,
                  ),

                  // ⚠️ **잠긴 이유를 반드시 적는다.** 눌러도 아무 일이 없고
                  // 까닭도 없으면 고장난 화면으로 읽힌다.
                  if (!state.slotsReady) ...[
                    const SizedBox(height: AppSpacing.space2),
                    _SlotsLockedNote(
                      message: _lockedMessage(state),
                      // 실패했을 때만 다시 시도를 붙인다.
                      //
                      // ⚠️ **세션 만료에는 안 붙인다.** 눌러 봐야 같은 답이고,
                      // 할 일은 다시 로그인하는 것이라 엉뚱한 길을 권하게 된다.
                      //
                      // ⚠️ **거리를 다시 누르는 길이 없어졌다.** 전에는 그것이
                      // 곧 재조회여서 이 버튼이 없어도 빠져나올 수 있었다.
                      // 이제 부르는 곳은 `load()` 하나라 여기가 유일한 길이다.
                      onRetry:
                          state.loadFailure != null &&
                              state.loadFailure !=
                                  SlotLoadFailure.sessionExpired
                          ? () => unawaited(_load())
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

                  _Label(AppStrings.matchDistanceLabel),
                  const SizedBox(height: AppSpacing.space3),

                  // ⚠️ **칩이 응답에서 선다.** 앱이 목록을 갖지 않는다 —
                  // 명세가 못 박았고, 서버가 7km를 추가하면 앱을 다시 내지
                  // 않아도 나타난다. 순서도 서버가 준 것을 그대로 쓴다.
                  _DistanceChips(
                    meters: [
                      for (final d in state.board?.distances ?? const [])
                        d.meters,
                    ],
                    selected: state.meters,
                    // ⚠️ **어떤 상태에서도 잠그지 않는다.** 시간을 먼저 고르는
                    // 흐름이지만 순서를 강제하지 않는다(설계 5-3).
                    onTap: (meters) => ref
                        .read(matchRegisterProvider.notifier)
                        .selectDistance(meters),
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

            // ⚠️ **등록 버튼 위의 대기 인원 줄이 없어졌다.** 거리만 골랐을 때
            // 그 거리의 모든 시각 합을 보여주던 자리인데, 이제 거리를 먼저
            // 고르는 흐름이 아니다. 숫자는 시트와 버튼 둘로 갈렸다.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space4,
                0,
                AppSpacing.space4,
                AppSpacing.space4,
              ),
              child: AppButtonV2(
                // ⚠️ **시트의 합계가 아니라 고른 조건의 수다.** 시트는 그
                // 시각의 모든 거리를 더해 그리고, 여기는 고른 거리 하나의
                // 수다 — 거리를 고르면 숫자가 좁혀지는 것이 정상이다.
                label: _ctaLabel(state.pickedWaiting),
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

  /// 등록 버튼의 글자. 숫자는 **둘 다 골랐고 0이 아닐 때만** 붙는다.
  ///
  /// ⚠️ **0명이면 붙이지 않는다.** `0명 대기`는 비어 있다고 알리는 꼴이라
  /// 오히려 사람을 민다.
  static String _ctaLabel(int? waiting) => waiting == null || waiting == 0
      ? AppStrings.matchRegisterCta
      : AppStrings.matchRegisterCtaWaiting(waiting);

  /// 시간 선택기가 왜 잠겼는지.
  ///
  /// **순서가 규칙이다.** 받는 중이 가장 구체적인 사정이고, 실패가 그다음,
  /// 비었음이 마지막이다 — 뒤로 갈수록 "그래서 고를 수 없다"에 가깝다.
  ///
  /// ⚠️ **`거리를 먼저 골라주세요`가 죽었다.** 한 번에 다 받으므로 거리로
  /// 잠글 이유가 없다(설계 5-3).
  static String _lockedMessage(MatchRegisterState state) {
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

  /// 화면에 들어왔다. **지난번 흔적을 지우고** 판을 받는다.
  ///
  /// ⚠️ **둘을 따로 부른다.** `probeToday`가 초기화까지 겸하고 있었는데, 그
  /// 함수가 죽으면서 지우는 일이 갈 곳을 잃었다. 안 지우면 지난번에 고른
  /// 시각·거리가 **기본값처럼** 선택돼 있다. `다시 시도`는 지울 것이 없으므로
  /// [_load]만 부른다.
  Future<void> _enter() async {
    ref.read(matchRegisterProvider.notifier).reset();
    await _load();
  }

  /// 오늘의 판을 받는다. 진입과 `다시 시도`가 같이 쓴다.
  Future<void> _load() async {
    await ref.read(matchRegisterProvider.notifier).load();
    if (!mounted) return;
    if (ref.read(matchRegisterProvider).closedForToday) {
      await _tellClosedToday();
    }
  }

  /// 오늘은 더 고를 것이 없다. **홈으로 내보낸다** — 이 화면에서 할 수 있는
  /// 일이 없다.
  Future<void> _tellClosedToday() async {
    await showDialog<void>(
      context: context,
      // 닫을 길이 버튼 하나뿐이다. 바깥을 눌러 닫으면 잠긴 화면에 그대로
      // 남아, 왜 아무것도 못 고르는지 모른 채 서 있게 된다.
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.matchClosedTitle),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _TimePolicy(),
              SizedBox(height: AppSpacing.space4),
              // ⚠️ **빈손으로 돌려보내지 않는다.** 혼자 뛰기는 마감과 무관하다.
              _PolicyTell(AppStrings.matchClosedSolo),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(AppStrings.matchClosedGoHome),
          ),
        ],
      ),
    );
    if (!mounted) return;
    context.pop();
  }

  /// 누르는 사이에 그 시간대가 마감됐다(409).
  ///
  /// ⚠️ **화면에 남는다.** 다른 시각이 아직 열려 있으므로 고칠 자리가 이 화면
  /// 안에 있다 — 홈으로 내보내면 다시 신청할 길까지 끊는다.
  Future<void> _tellSlotClosed() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(AppStrings.matchSlotClosedTitle),
      content: const SingleChildScrollView(child: _TimePolicy()),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.matchPolicyClose),
        ),
      ],
    ),
  );

  /// 이탈 제재로 막혔다(409).
  Future<void> _tellCooldown(DateTime? until) {
    final when = AppStrings.matchCooldownUntil(until);
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.matchCooldownTitle),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const _PolicyTell(AppStrings.matchCooldownRule),
            // ⚠️ 서버가 해제 시각을 빠뜨릴 수 있다. 없으면 줄을 만들지 않는다.
            if (when.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.space2),
              _PolicyAsk(when),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(AppStrings.matchPolicyClose),
          ),
        ],
      ),
    );
  }

  Future<void> _pickSlot() async {
    final state = ref.read(matchRegisterProvider);
    final picked = await showMatchSlotSheet(
      context,
      // ⚠️ **마감된 시각도 넘긴다.** 빼면 "10:00이 왜 없지"가 되고, 시간이
      // 흐르며 목록이 줄어드는 것도 이상하게 읽힌다. 시트가 잠근다.
      slots: state.board?.times ?? const [],
      selected: state.time,
    );
    if (picked == null || !mounted) return;
    ref.read(matchRegisterProvider.notifier).selectTime(picked);
  }

  Future<void> _submit() async {
    final roomId = await ref.read(matchRegisterProvider.notifier).submit();
    if (!mounted) return;

    // ⚠️ **팝업 둘은 여기서 띄운다.** `submit`이 409 뒤 재조회까지 마치고
    // 돌아오므로, 이 자리에서야 "그 시간만 마감"인지 "오늘이 끝났는지"가
    // 갈린다. 리스너에서 띄우면 재조회 전에 먼저 떠서 둘이 겹친다.
    if (roomId == null) {
      final state = ref.read(matchRegisterProvider);
      switch (state.failure) {
        case MatchFailure.slotClosed:
          await (state.closedForToday ? _tellClosedToday() : _tellSlotClosed());
        case MatchFailure.cooldown:
          await _tellCooldown(state.cooldownUntil);
        default:
          break;
      }
      if (mounted) ref.read(matchRegisterProvider.notifier).clearFailure();
      return;
    }

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

  /// 한 줄로 끝나는 실패.
  void _tellInSnackBar(MatchFailure failure, DateTime? cooldownUntil) {
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

/// 목표 거리 칩 한 줄. **선택지는 [meters]가 정한다.**
///
/// ## ⚠️ 앱이 목록을 갖지 않는다
///
/// 전에는 `TargetDistance.values`로 그렸다. 그것이 선택지의 출처였고, 서버가
/// 7km를 추가하면 앱을 다시 내기 전까지 아무도 고를 수 없었다. 명세가 **응답을
/// 선택지로 쓰라**고 못 박았으므로 받은 것을 그대로 세운다 — 순서까지.
class _DistanceChips extends StatelessWidget {
  const _DistanceChips({
    required this.meters,
    required this.selected,
    required this.onTap,
  });

  /// 고를 수 있는 거리(m). 응답이 준 순서 그대로다.
  final List<int> meters;

  /// 고른 거리(m).
  final int? selected;

  final void Function(int meters) onTap;

  /// `5000` → `5km`.
  ///
  /// ⚠️ **`TargetDistance`를 거치지 않는다.** enum에 없는 거리(7km)가 오면
  /// 이름을 못 찾아 칩이 비거나 사라진다. 1000으로 안 나뉘는 값은 미터로
  /// 적는다 — 지어낸 `1km`보다 낯선 `1500m`가 낫다.
  static String _label(int meters) => meters % 1000 == 0
      ? AppStrings.matchDistanceText(meters ~/ 1000)
      : AppStrings.matchDistanceMeters(meters);

  @override
  Widget build(BuildContext context) {
    // ⚠️ **판을 못 받았으면 자리를 만들지 않는다.** 빈 `Row`를 두면 글자
    // 라벨만 떠 있는 줄이 남아 무엇이 빠진 것인지 알 수 없다. 까닭은 시간
    // 선택기 아래 줄이 이미 말한다.
    if (meters.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        for (final m in meters) ...[
          Expanded(
            child: PresetChipV2(
              label: _label(m),
              selected: selected == m,
              onTap: () => onTap(m),
            ),
          ),
          if (m != meters.last) const SizedBox(width: AppSpacing.space2),
        ],
      ],
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

/// 팝업 셋이 함께 쓰는 **시간 규칙** 두 묶음.
///
/// ⚠️ `18:00~22:00` · `30분` · `10분 전`은 전부 서버 설정값이다. 운영에서
/// 바뀌면 이 문구도 같이 고쳐야 한다 — 테스트가 그 짝을 묶어 둔다.
class _TimePolicy extends StatelessWidget {
  const _TimePolicy();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      _PolicyAsk(AppStrings.matchPolicyWhenAsk),
      _PolicyTell(AppStrings.matchPolicyWhenTell),
      SizedBox(height: AppSpacing.space4),
      _PolicyAsk(AppStrings.matchPolicyDeadlineAsk),
      _PolicyTell(AppStrings.matchPolicyDeadlineTell),
    ],
  );
}

/// 묻는 말. **질문을 세워 두면** 자기가 궁금한 줄부터 읽는다 — 줄글만
/// 늘어놓으면 무엇을 알아야 하는지 모른 채 글자만 훑는다.
class _PolicyAsk extends StatelessWidget {
  const _PolicyAsk(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.space1),
    child: Text(
      text,
      style: AppTypographyV2.body07.copyWith(
        color: context.appColorsV2.textPrimary,
      ),
    ),
  );
}

/// 그 답.
class _PolicyTell extends StatelessWidget {
  const _PolicyTell(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppTypographyV2.body12.copyWith(
      color: context.appColorsV2.textSecondary,
    ),
  );
}
