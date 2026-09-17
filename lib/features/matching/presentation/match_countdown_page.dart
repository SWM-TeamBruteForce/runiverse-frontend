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
import 'package:runiverse/core/theme/tokens/run_palette.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';
import 'package:runiverse/features/matching/domain/target_distance.dart';
import 'package:runiverse/features/matching/presentation/match_room_provider.dart';
import 'package:runiverse/features/session/domain/location_repository.dart';
import 'package:runiverse/features/session/domain/party_board.dart';
import 'package:runiverse/features/session/domain/run_session_state.dart';
import 'package:runiverse/features/session/presentation/party_provider.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';

/// 출발 대기실 (S11, Figma `43:46` · `43:113`).
///
/// 30초 전에 들어와 GPS를 잡고, 3초 전부터 숫자를 세고, 시각이 되면 출발한다.
///
/// ## ⚠️ 들어오자마자 위치를 연다
///
/// 솔로는 준비 화면이 첫 신호를 기다린 뒤에야 출발 버튼을 연다. 매칭은 서버가
/// 정한 시각에 출발하므로 기다릴 수 없다 — 대신 **미리** 연다. 30초면 대개
/// 신호가 잡히고, 안 잡혔으면 첫 신호가 오는 즉시 출발한다
/// (`RunSessionController.startWhenReady`). 이것이 없으면 `start()`가
/// 준비 상태가 아니라 조용히 아무것도 하지 않아 **러닝이 시작되지 않는다.**
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
/// - **지도** — 표시 전용이라 GPS 칩이 같은 정보를 준다. 지도 SDK를 이 화면에
///   더 세우면 30초 동안 켤 것이 하나 늘 뿐이다
/// - **준비 완료 버튼·파티원 준비 체크** — 서버가 참가자 준비 상태를 내려주지
///   않고, 누를 것도 없다. 서버가 시각으로 시작한다
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

  /// 위치를 열 때 받은 답. 거절이면 화면이 설정으로 가는 길을 연다.
  LocationAccess? _access;

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
    // build 중에 provider를 건드리면 Riverpod이 막는다. 첫 프레임 뒤로 민다.
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
          .openMatched(
            room.runningRoomId,
            targetDistanceMeters: room.targetDistanceMeters,
          ),
    );
    // 신호가 있으면 지금, 없으면 첫 신호에 출발한다. 서버는 이미 시작했다.
    unawaited(ref.read(runSessionControllerProvider.notifier).startWhenReady());

    // `pushReplacement` — 달리는 중에 뒤로 가서 대기실이 나오면 안 된다.
    context.pushReplacement(AppRoutes.runSession);
  }

  Future<void> _openSettings() =>
      ref.read(locationRepositoryProvider).openSettings();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final state = ref.watch(matchRoomProvider);
    final room = state.room;
    final launch = state.launch;
    final number = launch?.countdownNumber(_now);

    final players = room?.players ?? const <RoomPlayer>[];

    return PopScope(
      // 취소 불가 구간이다. 여기서 빠져나가면 방은 시작했는데 이 사람만
      // 안 뛰는 상태가 된다.
      canPop: false,
      child: Scaffold(
        backgroundColor: colors.bgBase,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.space4),
            child: number != null
                // 3-2-1 구간에는 숫자와 파티원만 남긴다. 다른 것을 함께 두면
                // 마지막 3초에 눈이 흩어진다.
                ? Column(
                    children: [
                      _Head(
                        subtitle: AppStrings.matchCountdownSoon,
                        colors: colors,
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            '$number',
                            style: AppTypography.display.copyWith(
                              color: colors.primary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      _PartyAvatars(players: players, size: AppSpacing.space9),
                      const SizedBox(height: AppSpacing.space6),
                    ],
                  )
                : Column(
                    children: [
                      _Head(
                        subtitle: launch == null
                            ? AppStrings.matchCountdownSoon
                            : '${AppStrings.matchRoomStartLabel} '
                                  '${AppStrings.matchRoomCountdown(launch.remaining(_now))}',
                        colors: colors,
                      ),
                      const SizedBox(height: AppSpacing.space4),
                      if (room != null) _SessionBar(room: room),
                      const SizedBox(height: AppSpacing.space4),
                      Expanded(
                        child: _GpsCard(
                          access: _access,
                          onOpenSettings: _openSettings,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.space4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          AppStrings.matchCountdownParty,
                          style: AppTypography.caption.copyWith(
                            color: colors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.space2),
                      _PartyAvatars(
                        players: players,
                        size: AppSpacing.space9 + AppSpacing.space2,
                        withNames: true,
                      ),
                      const SizedBox(height: AppSpacing.space5),
                      Text(
                        AppStrings.matchCountdownAuto,
                        textAlign: TextAlign.center,
                        style: AppTypography.body.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.space1),
                      Text(
                        AppStrings.matchCountdownHint,
                        textAlign: TextAlign.center,
                        style: AppTypography.caption.copyWith(
                          color: colors.textTertiary,
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

class _Head extends StatelessWidget {
  const _Head({required this.subtitle, required this.colors});

  final String subtitle;
  final AppColors colors;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        AppStrings.matchCountdownTitle,
        style: AppTypography.h3.copyWith(color: colors.textPrimary),
      ),
      const SizedBox(height: AppSpacing.space0),
      Text(
        subtitle,
        style: AppTypography.caption.copyWith(
          color: colors.textSecondary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
}

/// 시작 시각 │ 목표 거리. 값 위, 라벨 아래 — 정본 S11의 세션 바.
class _SessionBar extends StatelessWidget {
  const _SessionBar({required this.room});

  final RoomInfo room;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final km = TargetDistance.fromMeters(room.targetDistanceMeters)?.km;

    Widget cell(String value, String label) => Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: AppTypography.h3.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.space0),
          Text(
            label,
            style: AppTypography.micro.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: AppRadius.md,
        border: Border.all(color: colors.borderDefault),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space2,
          vertical: AppSpacing.space3,
        ),
        child: Row(
          children: [
            cell(
              AppStrings.matchSlotTime(room.scheduledStartAt),
              AppStrings.matchRoomStartTimeLabel,
            ),
            SizedBox(
              width: 1,
              height: AppSpacing.space7,
              child: ColoredBox(color: colors.borderDefault),
            ),
            cell(
              km == null ? AppStrings.runUnavailable : '${km}km',
              AppStrings.matchDistanceLabel,
            ),
          ],
        ),
      ),
    );
  }
}

/// 지도 자리. 표시 전용 지도 대신 GPS 상태를 크게 보여준다.
class _GpsCard extends ConsumerWidget {
  const _GpsCard({required this.access, required this.onOpenSettings});

  final LocationAccess? access;
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final session = ref.watch(runSessionControllerProvider);
    final hasFix = session is RunPreparing && session.hasFix;
    // ⚠️ 구독을 연 뒤에 실패하는 경우가 있다. 상태의 실패를 먼저 본다.
    final blocked =
        (session is RunPreparing ? session.failure : null) ??
        (access != null && !access!.isGranted ? access : null);

    final (label, dot) = blocked != null
        ? (AppStrings.matchCountdownGpsDenied, colors.error)
        : hasFix
        ? (AppStrings.matchCountdownGpsReady, colors.success)
        : (AppStrings.matchCountdownGpsWaiting, colors.warning);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: AppRadius.xl,
        border: Border.all(color: colors.borderDefault),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: AppSpacing.space5,
              height: AppSpacing.space5,
              decoration: BoxDecoration(
                color: dot,
                shape: BoxShape.circle,
                boxShadow: RunPalette.glow(dot),
              ),
            ),
            const SizedBox(height: AppSpacing.space4),
            Text(
              label,
              style: AppTypography.body.copyWith(color: colors.textPrimary),
            ),
            if (blocked == null && !hasFix) ...[
              const SizedBox(height: AppSpacing.space1),
              Text(
                AppStrings.runWaitingFixWhy,
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ],
            if (blocked != null) ...[
              const SizedBox(height: AppSpacing.space4),
              AppButton(
                label: AppStrings.runPermissionOpenSettings,
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.md,
                expand: false,
                onPressed: onOpenSettings,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 파티원 아바타. 색은 명단 순서 — 러닝 화면의 레인과 같은 자리, 같은 색이다.
class _PartyAvatars extends StatelessWidget {
  const _PartyAvatars({
    required this.players,
    required this.size,
    this.withNames = false,
  });

  final List<RoomPlayer> players;
  final double size;
  final bool withNames;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.space3,
      runSpacing: AppSpacing.space2,
      children: [
        for (var i = 0; i < players.length; i++)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: RunPalette.lane(i),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  players[i].nickname.isEmpty
                      ? ''
                      : players[i].nickname.characters.first,
                  style: AppTypography.body.copyWith(
                    color: colors.textOnPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (withNames) ...[
                const SizedBox(height: AppSpacing.space1),
                Text(
                  players[i].nickname,
                  style: AppTypography.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }
}
