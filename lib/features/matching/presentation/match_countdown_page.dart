import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';
import 'package:runiverse/features/matching/domain/target_distance.dart';
import 'package:runiverse/features/matching/presentation/match_room_provider.dart';
import 'package:runiverse/features/session/domain/party_board.dart';
import 'package:runiverse/features/session/presentation/party_provider.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';

/// 출발 대기실 (S11) — 매칭 러닝.
///
/// ## 여기서 나갈 수 없다
///
/// 취소 불가 구간이다. 뒤로가기를 막는다 — 3초 전에 빠져나가면 방은 시작했는데
/// 이 사람만 안 뛰는 상태가 되고, 서버는 그것을 조기 이탈로 본다.
///
/// ## ⚠️ 발사 시각은 서버가 정한다
///
/// `RUNNING_READY`를 **받은 순간 + `startsInMs`**가 기준이다. 정각에 신호를
/// 보내면 네트워크 지연만큼 참가자마다 출발이 어긋나서, 서버가 미리 알리고
/// 클라가 타이머로 맞춘다. 통지를 못 받았으면 방의 `scheduledStartAt`을 쓴다 —
/// SSE가 끊겼다고 출발을 포기하지는 않는다.
///
/// ## 정본에서 뺀 것
///
/// - **지도와 GPS 인디케이터** — 솔로의 출발 준비 화면이 이미 그 자리를 맡는다.
///   매칭은 출발 시각이 정해져 있어 "신호를 기다렸다 누른다"가 성립하지 않는다
/// - **준비 완료 버튼** — 누를 것이 없다. 서버가 시각으로 시작한다
/// - **파티원 준비 체크** — 서버가 참가자 상태를 내려주지 않는다
class MatchCountdownPage extends ConsumerStatefulWidget {
  const MatchCountdownPage({super.key});

  @override
  ConsumerState<MatchCountdownPage> createState() => _MatchCountdownPageState();
}

class _MatchCountdownPageState extends ConsumerState<MatchCountdownPage> {
  Timer? _ticker;
  var _now = DateTime.now();

  /// 마지막으로 햅틱을 울린 숫자. 같은 숫자에 두 번 울리지 않는다.
  int? _buzzed;

  var _launched = false;

  @override
  void initState() {
    super.initState();
    // 3-2-1을 그리려면 초보다 촘촘해야 한다. 1초 간격이면 숫자가 한 박자씩
    // 늦게 바뀐다.
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _tick();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _tick() {
    final launch = ref.read(matchRoomProvider).launch;
    if (launch == null) return;

    final number = launch.countdownNumber(_now);
    if (number != null && number != _buzzed) {
      // 화면을 안 보고 있어도 출발을 안다.
      HapticFeedback.mediumImpact();
      _buzzed = number;
    }

    if (launch.shouldLaunch(_now)) _launch();
  }

  /// 출발한다. **한 번만 쏜다.**
  void _launch() {
    if (_launched) return;
    _launched = true;
    _ticker?.cancel();
    HapticFeedback.heavyImpact();

    final room = ref.read(matchRoomProvider).room;
    if (room == null || !mounted) return;

    // ⚠️ **명단을 지금 넘긴다.** 러닝이 시작되면 SSE가 닫혀 이 정보를 다시
    // 받을 길이 없다 — 진행·콤보 통지는 `userId`만 싣고, 명세가 정한 출처인
    // `RUNNING_STARTED` 스냅샷은 서버가 비워 보낸다.
    //
    // ⚠️ 명단은 **방 전원**이라 나도 들어 있다. 내 `userId`를 함께 넘겨 그 줄을
    // 내 레인으로 삼는다 — 안 그러면 서버가 내 진행을 보내지 않아 0m에 멈춘
    // 내 이름이 "나" 레인 옆에 또 뜬다.
    final auth = ref.read(authControllerProvider);
    ref.read(partyProvider.notifier).setRoster([
      for (final player in room.players)
        PartyMember(
          userId: player.userId,
          nickname: player.nickname,
          profileImageUrl: player.profileImageUrl,
        ),
    ], myUserId: auth is AuthSignedIn ? auth.userId : PartyBoard.meId);

    // ⚠️ 연결을 기다리지 않는다. 기다리면 출발이 그만큼 늦고, 늦게 붙어도
    // 좌표는 쌓였다가 한꺼번에 올라간다.
    unawaited(
      ref
          .read(runningConnectionProvider.notifier)
          .openMatched(room.runningRoomId),
    );
    ref.read(runSessionControllerProvider.notifier).start();

    // `pushReplacement` — 달리는 중에 뒤로 가서 대기실이 나오면 안 된다.
    context.pushReplacement(AppRoutes.runSession);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final state = ref.watch(matchRoomProvider);
    final room = state.room;
    final launch = state.launch;

    final number = launch?.countdownNumber(_now);

    return PopScope(
      // 취소 불가 구간이다. 여기서 빠져나가면 방은 시작했는데 이 사람만
      // 안 뛰는 상태가 된다.
      canPop: false,
      child: Scaffold(
        backgroundColor: colors.bgBase,
        body: SafeArea(
          child: Center(
            child: number != null
                // 3-2-1 구간에는 숫자만 남긴다. 다른 것을 함께 두면 마지막
                // 3초에 눈이 흩어진다.
                ? Text(
                    '$number',
                    style: AppTypography.display.copyWith(
                      color: colors.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(AppSpacing.space6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          AppStrings.matchCountdownTitle,
                          style: AppTypography.h2.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.space6),

                        Text(
                          AppStrings.matchRoomStartLabel,
                          style: AppTypography.caption.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.space1),
                        Text(
                          launch == null
                              ? '--:--'
                              : AppStrings.matchRoomCountdown(
                                  launch.remaining(_now),
                                ),
                          style: AppTypography.h1.copyWith(
                            color: colors.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.space6),

                        if (room != null) _SessionBar(room: room),
                        const SizedBox(height: AppSpacing.space6),

                        Text(
                          AppStrings.matchCountdownHint,
                          textAlign: TextAlign.center,
                          style: AppTypography.body.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// 시작 시각과 목표 거리. 대기방과 같은 모양이다 — 같은 정보라 다르게 그릴
/// 이유가 없다.
class _SessionBar extends StatelessWidget {
  const _SessionBar({required this.room});

  final RoomInfo room;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final km = TargetDistance.fromMeters(room.targetDistanceMeters)?.km;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: AppRadius.md,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space4,
          vertical: AppSpacing.space3,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppStrings.matchRoomStartAt(room.scheduledStartAt),
              style: AppTypography.body.copyWith(color: colors.textPrimary),
            ),
            if (km != null) ...[
              const SizedBox(width: AppSpacing.space4),
              Text(
                AppStrings.matchRoomTarget(km),
                style: AppTypography.body.copyWith(color: colors.textPrimary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
