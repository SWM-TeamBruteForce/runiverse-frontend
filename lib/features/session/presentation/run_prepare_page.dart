import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_motion.dart';
import 'package:runiverse/core/theme/v2/app_sizes.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/features/session/domain/location_repository.dart';
import 'package:runiverse/features/session/domain/run_session_state.dart';
import 'package:runiverse/features/session/domain/running_room.dart';
import 'package:runiverse/features/session/domain/user_status.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// 출발 준비 — **GPS 첫 신호를 기다린다.**
///
/// ## 왜 이 화면이 있나
///
/// GPS는 앱을 켜자마자 위치를 알지 못한다. 실내에서는 위성을 잡는 데 수십 초가
/// 걸리고, 그 전에 출발하면 **초반 거리가 통째로 빠진다.** 사용자는 자기가 뛴
/// 만큼 기록이 안 나온 이유를 알 수 없다.
///
/// 그래서 신호를 받기 전에는 시작 버튼을 잠그고, **잠긴 이유를 글로 보여준다** —
/// 색만으로 알리지 않는다(정본 C9).
class RunPreparePage extends ConsumerStatefulWidget {
  const RunPreparePage({super.key});

  @override
  ConsumerState<RunPreparePage> createState() => _RunPreparePageState();
}

class _RunPreparePageState extends ConsumerState<RunPreparePage> {
  /// 위치를 쓸 수 있는가. `null`이면 아직 묻는 중이다.
  LocationAccess? _access;

  /// 카운트다운 남은 수. `null`이면 아직 시작하지 않았다.
  ///
  /// **이 3초가 서버에 붙는 시간이다.** 사용자에게는 출발 신호로 보이고,
  /// 그동안 방을 만들고 WebSocket을 연결한다(설계 문서 4절).
  int? _countdown;

  Timer? _ticker;

  /// 설정에 다녀온 사람을 받는 자리([_recheck]).
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _recheck);
    // ⚠️ `initState`에서 provider를 고치면 빌드 도중 상태가 바뀌어 죽는다.
    // 첫 프레임 뒤로 미룬다(`implementation-notes.md` §10-1).
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  /// 다시 묻는 중인가. 겹쳐 부르면 플랫폼이 **"요청이 이미 진행 중"으로
  /// 거절한다**(iOS `GeolocatorErrorPermissionRequestInProgress`).
  var _rechecking = false;

  /// 앱으로 돌아왔다. **막혀 있었으면 권한을 다시 읽는다.**
  ///
  /// ## 왜 필요한가
  ///
  /// iOS는 한 번 거절하면 곧바로 `deniedForever`라 앱에서 다시 물을 길이 없다 —
  /// 사용자는 **설정 앱에 다녀와야** 한다. 그런데 권한은 [initState]에서 한 번만
  /// 읽으므로, 켜고 돌아와도 화면은 "위치 권한이 필요해요"인 채로 남는다.
  /// 홈으로 나갔다 다시 들어와야 맞는 값이 나왔다.
  ///
  /// ## 막혀 있을 때만 다시 읽는다
  ///
  /// ⚠️ **[_prepare]를 아무 때나 다시 부르면 안 된다.** 그 안의 `prepare()`가
  /// 위치 구독을 끊고 새로 연다 — 달리는 중에 앱을 다시 띄울 때마다 러닝이
  /// 끊긴다.
  ///
  /// ⚠️ **아직 묻는 중(`_access == null`)이면 손대지 않는다.** 권한 팝업이
  /// 떠 있는 동안에도 앱은 `inactive`를 거쳐 `resumed`로 돌아온다. 그때 또
  /// 물으면 첫 번째 요청이 거절당한다.
  Future<void> _recheck() async {
    final access = _access;
    if (access == null || access.isGranted || _rechecking) return;

    _rechecking = true;
    try {
      await _prepare();
    } finally {
      _rechecking = false;
    }
  }

  Future<void> _prepare() async {
    // ⚠️ **들어올 때 상태를 다시 읽는다.**
    //
    // 매칭이 걸려 있으면 솔로 방을 못 만든다. 그 판정을 **마지막으로 읽은
    // 값**으로 하면, 다른 기기에서 취소했거나 방금 홈에서 취소한 사람을
    // 앱이 혼자 막아 세운다 — 되돌릴 길이 화면에 없다.
    //
    // 기다리지 않는다. GPS를 잡는 동안 뒤에서 돌고, 답이 오면 화면이 다시
    // 그려진다.
    unawaited(ref.read(userStatusProvider.notifier).refresh());

    final access = await ref
        .read(runSessionControllerProvider.notifier)
        .prepare();
    if (mounted) setState(() => _access = access);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  /// 복구로 들어온 경우 **서버에 이미 있는 솔로 방.** 평소 경로에서는 `null`이다.
  ///
  /// 솔로 방은 `POST /running-rooms/solo` 순간에 `READY`로 태어난다. 그 뒤
  /// 앱을 껐다 켜면 서버가 여전히 `READY`라고 답하고 스플래시가 이 화면을
  /// 복구한다 — 그때는 방을 새로 만들 것이 아니라 그 방에 붙어야 한다.
  UserStatusReady? get _pendingSolo {
    final status = ref.read(userStatusProvider);
    return status is UserStatusReady && status.isSolo ? status : null;
  }

  /// 나가는 중인가. 취소 요청이 도는 동안 두 번 누르는 것을 막는다.
  var _leaving = false;

  /// 카운트다운을 시작하고, **그 뒤에서 서버에 붙는다.**
  void _start() {
    final connection = ref.read(runningConnectionProvider.notifier);
    final pending = _pendingSolo;

    // 연결을 기다리지 않는다. 3초 안에 되면 좋고, 안 되면 달리면서 계속 시도한다.
    //
    // ⚠️ **복구로 들어왔으면 있는 방에 붙는다.** 새로 만들면 서버가 409로
    // 막고, 그 정리 경로는 "끝내지 못한 방"으로 보고 **지금 쓸 방을 끝내 버린다.**
    unawaited(
      pending == null
          ? connection.open()
          : connection.reopen(
              pending.runningRoomId,
              targetDistanceMeters: pending.targetDistanceMeters,
              matched: false,
            ),
    );

    setState(() => _countdown = _countdownFrom);
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      final left = (_countdown ?? 1) - 1;
      if (left > 0) {
        // 매 숫자마다 햅틱. 화면을 안 보고 있어도 출발을 안다(정본 S11).
        HapticFeedback.mediumImpact();
        setState(() => _countdown = left);
        return;
      }
      timer.cancel();
      HapticFeedback.heavyImpact();
      _enterRunning();
    });
  }

  void _enterRunning() {
    if (!mounted) return;
    ref.read(runSessionControllerProvider.notifier).start();
    // `pushReplacement` — 준비 화면으로 되돌아올 자리를 남기지 않는다.
    // 달리는 중에 뒤로 가면 준비 화면이 나오는 것은 말이 안 된다.
    context.pushReplacement(AppRoutes.runSession);
  }

  /// 이전 러닝이 남아 있다. 카운트다운을 멈추고 홈으로 돌려보낸다.
  void _cancelForConflict() {
    _ticker?.cancel();
    setState(() => _countdown = null);
  }

  /// 정본 S11과 같은 3초. 명세의 "시작 3초 전부터 카운트다운"과도 맞는다.
  static const _countdownFrom = 3;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final state = ref.watch(runSessionControllerProvider);
    final hasFix = state is RunPreparing && state.hasFix;

    // ⚠️ **구독을 연 뒤에 실패하는 경우가 있다.** `_access`는 `prepare()`가
    // 돌려준 한 번뿐인 답이라 그 뒤의 실패를 모른다. 상태 쪽 이유를 먼저 본다 —
    // 이게 없으면 화면이 "위치를 찾고 있어요"에서 영원히 멈춘다.
    final access = (state is RunPreparing ? state.failure : null) ?? _access;

    // ⚠️ **이전 러닝이 남아 있으면 카운트다운을 멈춘다.** 그대로 두면 방 없이
    // 러닝 화면으로 들어가고, 30분을 뛰어도 기록이 서버에 남지 않는다.
    ref.listen(runningConnectionProvider, (_, next) {
      if (next.failure == RunningRoomFailure.alreadyRunning) {
        _cancelForConflict();
      }
    });

    // ⚠️ **눌러 보기 전에도 막는다.** 매칭이 걸려 있으면 `시작`은 409로만
    // 끝난다 — 3초를 세고 나서 알려 주는 것은 알려 주는 것이 아니다.
    //
    // 상태를 못 읽었으면(`null`) 막지 않는다. 판정에 실패했다고 막으면 신호가
    // 나쁜 곳에서 아무도 못 뛴다 — 그때는 서버의 409가 다시 걸러 준다.
    final status = ref.watch(userStatusProvider);
    final rejectedByServer =
        ref.watch(runningConnectionProvider).failure ==
        RunningRoomFailure.alreadyRunning;
    // ⚠️ **세기 시작했으면 서버 상태로 막지 않는다.**
    //
    // 시작을 누르면 이 3초 안에 방이 생기고(`POST /running-rooms/solo` 201)
    // 시작 확인이 오며, 그 자리에서 앱이 상태를 다시 읽는다 — 서버는 당연히
    // `RUNNING`이라고 답한다. 그것을 충돌로 읽으면 **방금 시작한 내 러닝을
    // 이유로 "이전 러닝이 아직 끝나지 않았어요"가 뜬다**(2026-10-21 기기
    // 확인 · 시작 1.3초 뒤부터 약 2초).
    //
    // 눈에 거슬리는 데서 끝나지 않는다. 그 화면의 `홈으로`를 누르면 방금
    // 시작한 러닝을 두고 나가고, 복구로 들어온 경우에는 [_leave]가 그 방을
    // 서버에서 **없앤다.**
    //
    // 진짜 충돌은 서버가 409로 말해 준다. 그때는 위의 `ref.listen`이
    // [_cancelForConflict]로 **세던 것을 멈추므로** 여기 조건이 그대로 선다 —
    // 그 길 하나로 모은다. 세는 중에도 409를 따로 보게 두면 **닿지 않는
    // 가지**가 되어, 어느 쪽이 일하는지 테스트로 가릴 수 없다.
    final conflicted =
        _countdown == null &&
        (status?.canStartSolo == false || rejectedByServer);
    if (conflicted) {
      return _Conflicted(status: status, onLeave: () => unawaited(_leave()));
    }

    final countdown = _countdown;
    if (countdown != null) return _Countdown(value: countdown);

    return PopScope(
      // ⚠️ **뒤로 밀기(제스처)도 취소를 거쳐야 한다.** 그냥 pop되면 복구로
      // 들어온 경우 서버에 `READY` 방이 남는다 — [_leave] 참조.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        // ⚠️ **앱 테마가 아직 옛 세대라 바탕을 직접 깐다.** 안 깔면 토큰은
        // 전부 새것인데 바탕만 `#0b0e14` 로 남는다(`v2_screen_background_test`).
        backgroundColor: colors.bgBase,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => unawaited(_leave()),
                  tooltip: AppStrings.authBack,
                  constraints: const BoxConstraints(
                    minWidth: AppSizes.touchDefault,
                    minHeight: AppSizes.touchDefault,
                  ),
                  icon: Icon(
                    LucideIcons.arrowLeft,
                    size: AppSpacing.space6,
                    color: colors.textSecondary,
                  ),
                ),
              ),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space5,
                  ),
                  child: access != null && access != LocationAccess.granted
                      ? _Blocked(access: access, onOpenSettings: _openSettings)
                      : _Waiting(hasFix: hasFix),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(AppSpacing.space5),
                child: AppButtonV2(
                  label: AppStrings.runStartCta,
                  size: AppButtonV2Size.regular,
                  // 신호를 받기 전에는 잠긴다. 이 잠금이 이 화면의 존재 이유다.
                  onPressed: hasFix ? _start : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 준비를 그만두고 나간다. **구독을 반드시 끊는다** —
  /// 안 끊으면 홈으로 돌아가서도 GPS가 계속 돌아 배터리를 먹는다.
  ///
  /// ## ⚠️ 복구로 들어왔으면 서버의 방도 없앤다
  ///
  /// 그냥 나가면 `READY` 방이 서버에 남고, 이후 매칭 신청이 전부
  /// 409(`MATCH_ALREADY_IN_PROGRESS`)로 막힌다. 사용자는 아무것도 신청하지
  /// 않았는데 "이미 진행 중"이라는 말만 듣는다.
  ///
  /// **취소에 실패해도 나간다.** 준비 화면에 가둘 이유가 없다 — 남은 방은
  /// 다음 시작의 409 정리 경로가 다시 맡는다.
  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;

    ref.read(runSessionControllerProvider.notifier).reset();
    final pending = _pendingSolo;

    if (pending != null) {
      await ref.read(runningConnectionProvider.notifier).cancelPending();
      // 방이 없어졌으니 서버가 아는 상태도 달라졌다. 홈이 옛 값으로 배너를
      // 그리지 않도록 여기서 다시 읽는다.
      await ref.read(userStatusProvider.notifier).refresh();
    }

    if (!mounted) return;
    context.pop();
  }

  Future<void> _openSettings() async {
    await ref.read(locationRepositoryProvider).openSettings();
  }
}

/// 신호를 기다리는 동안.
class _Waiting extends StatelessWidget {
  const _Waiting({required this.hasFix});

  final bool hasFix;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 신호를 받으면 아이콘이 바뀐다. **색만 바꾸지 않는다.**
        AnimatedSwitcher(
          duration: AppMotion.base,
          child: Icon(
            hasFix ? LucideIcons.locateFixed : LucideIcons.locate,
            key: ValueKey(hasFix),
            size: AppSpacing.space10,
            color: hasFix ? colors.success : colors.textTertiary,
          ),
        ),
        const SizedBox(height: AppSpacing.space5),

        Text(
          hasFix ? AppStrings.runFixReady : AppStrings.runWaitingFix,
          style: AppTypographyV2.heading02.copyWith(color: colors.textPrimary),
        ),
        if (!hasFix) ...[
          const SizedBox(height: AppSpacing.space2),
          Text(
            AppStrings.runWaitingFixWhy,
            textAlign: TextAlign.center,
            style: AppTypographyV2.body15.copyWith(color: colors.textSecondary),
          ),
        ],
      ],
    );
  }
}

/// 위치를 쓸 수 없다. **왜 막혔는지와 어디로 가야 하는지**를 함께 말한다.
class _Blocked extends StatelessWidget {
  const _Blocked({required this.access, required this.onOpenSettings});

  final LocationAccess access;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          LucideIcons.mapPinOff,
          size: AppSpacing.space10,
          color: colors.textTertiary,
        ),
        const SizedBox(height: AppSpacing.space5),
        Text(
          access == LocationAccess.serviceDisabled
              ? AppStrings.runServiceDisabled
              : AppStrings.runPermissionTitle,
          textAlign: TextAlign.center,
          style: AppTypographyV2.heading06.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.space2),
        Text(
          AppStrings.runPermissionBody,
          textAlign: TextAlign.center,
          style: AppTypographyV2.body15.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space5),
        AppButtonV2(
          label: AppStrings.runPermissionOpenSettings,
          variant: AppButtonV2Variant.secondary,
          size: AppButtonV2Size.compact,
          expand: false,
          onPressed: onOpenSettings,
        ),
      ],
    );
  }
}

/// 카운트다운 — 숫자 하나만 크게.
///
/// 정본 S11이 "지도·파티원을 숨기고 숫자만"으로 정했다. 솔로는 파티원이 없어
/// 숫자만 남는다.
///
/// **뒤로가기를 막는다.** 정본이 "취소·뒤로가기 없음(취소 불가 구간)"이라고
/// 못박았고, 이 3초 사이에 나가면 서버에는 방이 만들어진 채로 남는다.
class _Countdown extends StatelessWidget {
  const _Countdown({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: colors.bgBase,
        body: Center(
          child: AnimatedSwitcher(
            duration: AppMotion.fast,
            // 숫자가 바뀔 때마다 살짝 커졌다 제자리로. 스프링 느낌을 낸다.
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: Text(
              '$value',
              // 키가 없으면 AnimatedSwitcher가 같은 위젯으로 보고 넘어간다.
              key: ValueKey(value),
              style: AppTypographyV2.heading01.copyWith(
                fontSize: 160,
                height: 1,
                color: colors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 이전 러닝이 아직 끝나지 않았다. 서버 409.
///
/// ⚠️ **"다시 시도"를 주지 않는다.** 몇 번을 눌러도 같은 답이 온다 —
/// 서버에 남은 러닝이 정리돼야 풀린다.
class _Conflicted extends StatelessWidget {
  const _Conflicted({required this.status, required this.onLeave});

  /// 서버가 아는 상태. 막힌 이유가 여기서 갈린다. `null`이면 못 읽었다.
  final UserStatus? status;

  final VoidCallback onLeave;

  /// 무엇이 막고 있는지.
  ///
  /// 서버는 매칭이든 러닝이든 같은 409로 답하지만 **사용자가 할 일이 다르다.**
  /// 못 읽었거나 러닝이 남은 경우가 기본이다 — 그쪽이 원래 이 화면이 맡던 일이고,
  /// 상태를 모를 때 "매칭을 취소하세요"라고 하면 없는 매칭을 찾게 된다.
  (String, String) get _copy => switch (status) {
    UserStatusWaiting() => (
      AppStrings.runBlockedByMatch,
      AppStrings.runBlockedByMatchWhy,
    ),
    UserStatusReady(isSolo: false) => (
      AppStrings.runBlockedByMatched,
      AppStrings.runBlockedByMatchedWhy,
    ),
    _ => (AppStrings.runAlreadyInProgress, AppStrings.runAlreadyInProgressWhy),
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final (title, why) = _copy;

    return Scaffold(
      backgroundColor: colors.bgBase,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space5),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                LucideIcons.circleAlert,
                size: AppSpacing.space8,
                color: colors.warning,
              ),
              const SizedBox(height: AppSpacing.space5),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTypographyV2.heading02.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.space3),
              Text(
                why,
                textAlign: TextAlign.center,
                style: AppTypographyV2.body07.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.space7),
              AppButtonV2(label: AppStrings.runBackToHome, onPressed: onLeave),
            ],
          ),
        ),
      ),
    );
  }
}
