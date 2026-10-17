import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';
import 'package:runiverse/features/matching/domain/run_launch.dart';
import 'package:runiverse/features/matching/presentation/match_room_provider.dart';

/// 출발 시각이 오면 **어느 화면에 있든** 러닝으로 데려간다.
///
/// ## ⚠️ 예전에는 로비에 서 있어야만 출발했다
///
/// 카운트다운으로 들어가는 길이 대기방 화면 안에만 있었다
/// (`MatchRoomPage._enterIfDue`). 로비에서 홈으로 한 번만 나와도 **시작
/// 시각이 지나도록 아무 일도 일어나지 않았다.** 매칭은 예약이라 신청해 두고
/// 다른 화면을 보는 것이 자연스러운데, 그 사이에 러닝을 통째로 놓쳤다.
///
/// ## 두 단계로 데려간다
///
/// | 시점 | 하는 일 |
/// |---|---|
/// | [noticeFrom] 전 | 안내를 띄우고 **로비로 옮긴다** |
/// | [RunLaunch.enterFrom] 전 | 아직 다른 화면이면 **카운트다운으로 직행** |
///
/// 1분 전에 미리 옮기는 이유는 로비에서 WebSocket을 붙일 시간을 벌기
/// 위해서다. 그래도 못 옮겼으면(안내를 못 봤거나, 앱이 백그라운드였거나)
/// 30초 전에 바로 카운트다운으로 보낸다 — 거기서 3·2·1이 돌고 정각에 쏜다.
///
/// ## ⚠️ 로비에 있을 때는 손대지 않는다
///
/// 그 자리는 [MatchRoomPage]가 맡는다. 둘이 같이 밀면 카운트다운이 두 번
/// 쌓인다. 여기는 **로비 밖**만 본다.
class LaunchGate extends ConsumerStatefulWidget {
  const LaunchGate({required this.router, required this.child, super.key});

  /// 화면을 옮길 라우터. 이 위젯은 [Navigator] 위에 있어 `context`로는 못 민다.
  final GoRouter router;

  final Widget child;

  /// 안내를 띄우는 지점. [RunLaunch.enterFrom](30초)보다 앞서야 한다 —
  /// 같으면 로비에 닿자마자 카운트다운으로 튕겨 안내가 의미를 잃는다.
  static const noticeFrom = Duration(minutes: 1);

  /// 안내를 띄워 두는 시간. 읽을 틈은 주되 기다리게 하지는 않는다.
  static const noticeLinger = Duration(seconds: 2);

  @override
  ConsumerState<LaunchGate> createState() => _LaunchGateState();
}

class _LaunchGateState extends ConsumerState<LaunchGate> {
  Timer? _ticker;
  ProviderSubscription<MatchRoomState>? _rooms;

  /// 안내를 띄운 방·카운트다운으로 보낸 방. **방마다 한 번씩만** 한다.
  int? _noticed;
  int? _entered;

  /// 띄워 둔 안내. 지울 때 **이 경로만** 집어서 지운다 — `pop()`으로 걷으면
  /// 안내가 이미 닫힌 뒤에 엉뚱한 화면이 닫힌다.
  DialogRoute<void>? _notice;

  /// ⚠️ **첫 프레임 뒤에 붙는다.** `build` 에서 `ref.watch` 로 보면 이 위젯이
  /// 트리의 꼭대기라 [matchRoomProvider] 가 **`AppShell` 보다 먼저** 생긴다.
  /// 그러면 그 provider 가 `userStatusProvider` 를 깨우는 시점이 당겨져 앱이
  /// 뜨는 순서가 바뀐다 — 실제로 상태 조회가 한 박자 어긋나 테스트가 깨졌다.
  /// 여기는 출발을 지키는 자리지 시작을 당기는 자리가 아니다.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _rooms = ref.listenManual(
        matchRoomProvider,
        (_, next) => _watch(next),
        fireImmediately: true,
      );
    });
  }

  @override
  void dispose() {
    _rooms?.close();
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  /// 방이 확정돼 있는 동안만 시계를 돌린다. 매칭 전·러닝 후에는 멈춘다.
  void _watch(MatchRoomState state) {
    _run(state.room?.status == RoomStatus.matched && state.launch != null);
  }

  void _run(bool pending) {
    if (pending == (_ticker != null)) return;
    _ticker?.cancel();
    _ticker = pending
        ? Timer.periodic(const Duration(seconds: 1), (_) => _tick())
        : null;
  }

  void _tick() {
    final state = ref.read(matchRoomProvider);
    final room = state.room;
    final launch = state.launch;
    if (room == null || launch == null) return;
    if (room.status != RoomStatus.matched) return;

    final where = widget.router.state.matchedLocation;
    // 로비는 저쪽이 맡고, 카운트다운·러닝 중이면 이미 도착한 것이다.
    if (where == AppRoutes.matchRoom ||
        where == AppRoutes.matchCountdown ||
        where == AppRoutes.runSession) {
      return;
    }

    final now = DateTime.now();

    if (launch.shouldEnter(now)) {
      if (_entered == room.runningRoomId) return;
      _entered = room.runningRoomId;
      _dismiss();
      widget.router.pushReplacement(AppRoutes.matchCountdown);
      return;
    }

    if (launch.remaining(now) <= LaunchGate.noticeFrom &&
        _noticed != room.runningRoomId) {
      _noticed = room.runningRoomId;
      unawaited(_notify());
    }
  }

  /// 안내를 띄우고 로비로 옮긴다.
  Future<void> _notify() async {
    final navigator = widget.router.routerDelegate.navigatorKey.currentState;
    final context = widget.router.routerDelegate.navigatorKey.currentContext;
    if (navigator == null || context == null) return;

    final notice = DialogRoute<void>(
      context: context,
      // 눌러서 넘길 것이 없다. 바깥을 눌러도 닫히지 않는다.
      barrierDismissible: false,
      builder: (_) => const _Notice(),
    );
    _notice = notice;
    unawaited(navigator.push(notice));

    await Future<void>.delayed(LaunchGate.noticeLinger);
    if (!mounted) return;
    _dismiss();
    // 그 사이에 스스로 로비로 갔을 수 있다.
    if (widget.router.state.matchedLocation != AppRoutes.matchRoom) {
      widget.router.go(AppRoutes.matchRoom);
    }
  }

  void _dismiss() {
    final notice = _notice;
    if (notice == null) return;
    _notice = null;
    widget.router.routerDelegate.navigatorKey.currentState?.removeRoute(notice);
  }
}

/// 누를 것이 없는 안내. **무엇이 일어나는지만 말한다.**
class _Notice extends StatelessWidget {
  const _Notice();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return AlertDialog(
      backgroundColor: colors.bgSurface,
      title: const Text(AppStrings.matchLaunchNoticeTitle),
      content: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.space2),
        child: Text(
          AppStrings.matchLaunchNoticeBody,
          style: AppTypographyV2.body15.copyWith(color: colors.textSecondary),
        ),
      ),
    );
  }
}
