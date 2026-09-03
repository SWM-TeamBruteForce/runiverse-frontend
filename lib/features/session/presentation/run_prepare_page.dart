import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_motion.dart';
import 'package:runiverse/core/theme/tokens/app_sizes.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/features/session/domain/location_repository.dart';
import 'package:runiverse/features/session/domain/run_session_state.dart';
import 'package:runiverse/features/session/domain/running_room.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';

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

  @override
  void initState() {
    super.initState();
    // ⚠️ `initState`에서 provider를 고치면 빌드 도중 상태가 바뀌어 죽는다.
    // 첫 프레임 뒤로 미룬다(`implementation-notes.md` §10-1).
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  Future<void> _prepare() async {
    final access = await ref
        .read(runSessionControllerProvider.notifier)
        .prepare();
    if (mounted) setState(() => _access = access);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// 카운트다운을 시작하고, **그 뒤에서 서버에 붙는다.**
  void _start() {
    // 연결을 기다리지 않는다. 3초 안에 되면 좋고, 안 되면 달리면서 계속 시도한다.
    unawaited(ref.read(runningConnectionProvider.notifier).open());

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
    final colors = context.appColors;
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

    final conflicted =
        ref.watch(runningConnectionProvider).failure ==
        RunningRoomFailure.alreadyRunning;
    if (conflicted) {
      return _Conflicted(onLeave: () => _leave(context));
    }

    final countdown = _countdown;
    if (countdown != null) return _Countdown(value: countdown);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: () => _leave(context),
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
              child: AppButton(
                label: AppStrings.runStartCta,
                size: AppButtonSize.lg,
                // 신호를 받기 전에는 잠긴다. 이 잠금이 이 화면의 존재 이유다.
                onPressed: hasFix ? _start : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 준비를 그만두고 나간다. **구독을 반드시 끊는다** —
  /// 안 끊으면 홈으로 돌아가서도 GPS가 계속 돌아 배터리를 먹는다.
  void _leave(BuildContext context) {
    ref.read(runSessionControllerProvider.notifier).reset();
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
    final colors = context.appColors;

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
          style: AppTypography.h2.copyWith(color: colors.textPrimary),
        ),
        if (!hasFix) ...[
          const SizedBox(height: AppSpacing.space2),
          Text(
            AppStrings.runWaitingFixWhy,
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(color: colors.textSecondary),
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
    final colors = context.appColors;

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
          style: AppTypography.h3.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.space2),
        Text(
          AppStrings.runPermissionBody,
          textAlign: TextAlign.center,
          style: AppTypography.caption.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space5),
        AppButton(
          label: AppStrings.runPermissionOpenSettings,
          variant: AppButtonVariant.secondary,
          size: AppButtonSize.md,
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
    final colors = context.appColors;

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
              style: AppTypography.metricHero.copyWith(
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
  const _Conflicted({required this.onLeave});

  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

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
                AppStrings.runAlreadyInProgress,
                textAlign: TextAlign.center,
                style: AppTypography.h2.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.space3),
              Text(
                AppStrings.runAlreadyInProgressWhy,
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.space7),
              AppButton(label: AppStrings.runBackToHome, onPressed: onLeave),
            ],
          ),
        ),
      ),
    );
  }
}
