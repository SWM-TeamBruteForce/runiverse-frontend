import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_sizes.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/features/matching/domain/match_failure.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';
import 'package:runiverse/features/matching/domain/target_distance.dart';
import 'package:runiverse/features/matching/presentation/match_register_provider.dart';
import 'package:runiverse/features/matching/presentation/match_room_provider.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// 대기방 (S10).
///
/// **모집 중과 확정 뒤를 한 화면이 맡는다.** 확정은 순간이고, 그 앞뒤로 사람이
/// 보는 것은 같은 질문이다 — 누가 함께 뛰고, 언제 출발하는가.
///
/// ## 정본에서 뺀 것
///
/// - **참가자별 준비 완료 체크** — 서버가 참가자 `status`를 내려주지 않는다.
///   남아 있는 사람은 전부 `JOINED`라 표시할 상태가 없다
/// - **리액션 버튼(👍🔥💪👋)** — 주고받을 API가 없다. 눌러도 아무 데도 가지
///   않는 버튼을 두면 고장으로 읽힌다
/// - **시그니처 컬러 아바타** — 색을 모으는 기능이 아직 없다. 프로필 사진과
///   머리글자로 대신한다
///
/// 취소 문구도 고쳤다. 정본의 "우선순위가 낮아져요"는 실제 정책이 아니다 —
/// **확정 뒤에 나가면 20분 동안 다시 신청할 수 없다.**
class MatchRoomPage extends ConsumerStatefulWidget {
  const MatchRoomPage({super.key});

  @override
  ConsumerState<MatchRoomPage> createState() => _MatchRoomPageState();
}

class _MatchRoomPageState extends ConsumerState<MatchRoomPage> {
  Timer? _ticker;

  /// 지금. **1초마다 갈아끼운다** — 카운트다운이 이 값에서 나온다.
  var _now = DateTime.now();

  var _leaving = false;

  /// 출발 대기실로 넘어가는 중. 타이머가 두 번 밀지 않게 막는다.
  var _entering = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _enterIfDue();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final state = ref.watch(matchRoomProvider);
    final room = state.room;

    // 방이 없어졌다. 취소됐거나 나갔다 — 어느 쪽이든 여기 남을 이유가 없다.
    ref.listen(matchRoomProvider.select((state) => state.room == null), (
      _,
      gone,
    ) {
      if (!gone || _leaving || !mounted) return;
      if (context.canPop()) context.pop();
    });

    // 아직 첫 스냅샷이 오지 않았다. **비워두지 않는다** — 빈 화면은 고장으로
    // 읽히고, AppBar가 없으면 돌아갈 길도 사라진다.
    if (room == null) {
      return Scaffold(
        backgroundColor: colors.bgBase,
        appBar: AppBar(
          backgroundColor: colors.bgBase,
          surfaceTintColor: Colors.transparent,
          title: Text(AppStrings.matchRoomTitle, style: AppTypography.h3),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        surfaceTintColor: Colors.transparent,
        title: Text(AppStrings.matchRoomTitle, style: AppTypography.h3),
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
                  if (!state.connected)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.space4),
                      child: _Notice(AppStrings.matchRoomDisconnected),
                    ),

                  _Headline(room: room, now: _now),
                  const SizedBox(height: AppSpacing.space6),

                  _SessionBar(room: room),
                  const SizedBox(height: AppSpacing.space6),

                  Text(
                    AppStrings.matchRoomPlayers(room.players.length),
                    style: AppTypography.caption.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space3),

                  for (final player in room.players) ...[
                    _PlayerRow(player: player),
                    const SizedBox(height: AppSpacing.space2),
                  ],

                  const SizedBox(height: AppSpacing.space4),
                  _Notice(_leaveNotice(room)),
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
                label: room.status == RoomStatus.matching
                    ? AppStrings.matchRoomCancel
                    : AppStrings.matchRoomLeave,
                variant: AppButtonVariant.secondary,
                onPressed: _leaving ? null : () => _confirmLeave(room),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 출발이 가까우면 대기실로 옮긴다.
  ///
  /// ⚠️ **확정된 방에서만 넘어간다.** 모집 중인 방의 `scheduledStartAt`은 아직
  /// 이 사람의 출발 시각이 아니다 — 마감 전에 취소할 수도 있다.
  ///
  /// 넉넉히 앞서 들어가는 이유는 WebSocket을 미리 붙여야 해서다. 정각에
  /// 붙기 시작하면 첫 메시지가 그만큼 늦는다.
  void _enterIfDue() {
    if (_leaving || _entering) return;
    final state = ref.read(matchRoomProvider);
    final room = state.room;
    final launch = state.launch;
    if (room == null || launch == null) return;
    if (room.status == RoomStatus.matching) return;
    if (!launch.shouldEnter(_now)) return;

    _entering = true;
    _ticker?.cancel();
    // `pushReplacement` — 출발한 뒤에 뒤로 가서 대기방이 나오면 안 된다.
    context.pushReplacement(AppRoutes.matchCountdown);
  }

  /// 나가면 어떻게 되는지. **제재가 걸릴 때만 겁을 준다.**
  ///
  /// 판정 기준은 방의 `status`가 아니라 **모집 마감 시각**이다 — 마감이 지났는데
  /// 서버가 아직 방을 안 닫은 틈이 있어서, 서버도 시각으로 가른다.
  /// 혼자 남은 방은 마감이 지났어도 면제다.
  String _leaveNotice(RoomInfo room) {
    final closeAt = room.closeAt;
    final closed = closeAt != null && !_now.isBefore(closeAt);
    return closed && !room.isAlone
        ? AppStrings.matchRoomLeavePenalty
        : AppStrings.matchRoomLeaveFree;
  }

  Future<void> _confirmLeave(RoomInfo room) async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.appColors.bgElevated,
        title: Text(
          AppStrings.matchRoomLeaveTitle,
          style: AppTypography.h3.copyWith(
            color: context.appColors.textPrimary,
          ),
        ),
        content: Text(
          _leaveNotice(room),
          style: AppTypography.body.copyWith(
            color: context.appColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStrings.matchRoomStay),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(AppStrings.matchRoomLeaveConfirm),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;

    setState(() => _leaving = true);
    try {
      await ref.read(matchRepositoryProvider).cancel();
    } on MatchException catch (error) {
      // 취소할 것이 없다는 답은 실패가 아니다. 이미 원하던 상태다.
      if (error.failure != MatchFailure.nothingToCancel) {
        if (!mounted) return;
        setState(() => _leaving = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text(AppStrings.matchRoomLeaveFailed)),
          );
        return;
      }
    }

    // 스트림을 먼저 닫는다. 남겨두면 서버가 닫기 전까지 지난 방의 이벤트가
    // 계속 올라온다.
    await ref.read(matchRoomProvider.notifier).disconnect();
    await ref.read(userStatusProvider.notifier).refresh();
    if (!mounted) return;
    if (context.canPop()) context.pop();
  }
}

/// 화면 맨 위 — 지금이 어느 단계이고 얼마나 남았는가.
class _Headline extends StatelessWidget {
  const _Headline({required this.room, required this.now});

  final RoomInfo room;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final matching = room.status == RoomStatus.matching;
    final started = room.status == RoomStatus.started;

    // 모집 중에는 마감까지, 확정 뒤에는 출발까지 센다. 보는 사람이 기다리는
    // 것이 그 시점에 따라 다르다.
    final target = matching ? room.closeAt : room.scheduledStartAt;
    final remaining = target == null
        ? null
        : target.difference(now).isNegative
        ? Duration.zero
        : target.difference(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: AppSpacing.space2,
              height: AppSpacing.space2,
              decoration: BoxDecoration(
                color: matching ? colors.matchWaiting : colors.matchConfirmed,
                borderRadius: AppRadius.full,
              ),
            ),
            const SizedBox(width: AppSpacing.space2),
            Text(
              started
                  ? AppStrings.matchRoomStarted
                  : matching
                  ? AppStrings.matchRoomWaiting
                  : AppStrings.matchRoomMatched,
              style: AppTypography.bodyLg.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.space4),

        if (started)
          Text(
            AppStrings.matchRoomStartedHint,
            style: AppTypography.body.copyWith(color: colors.textSecondary),
          )
        else ...[
          Text(
            matching
                ? AppStrings.matchRoomCloseLabel
                : AppStrings.matchRoomStartLabel,
            style: AppTypography.caption.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.space1),
          Text(
            remaining == null
                ? '--:--'
                : AppStrings.matchRoomCountdown(remaining),
            style: AppTypography.h1.copyWith(
              color: colors.textPrimary,
              // 1초마다 갈리는 숫자다. 자릿수가 흔들리면 글자가 춤춘다.
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: AppSpacing.space3),
          Text(
            matching
                ? AppStrings.matchRoomJoined(room.players.length)
                : AppStrings.matchRoomWaitingHint,
            style: AppTypography.body.copyWith(color: colors.textSecondary),
          ),
        ],
      ],
    );
  }
}

/// 시작 시각과 목표 거리 2분할.
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
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Text(
              AppStrings.matchRoomStartAt(room.scheduledStartAt),
              style: AppTypography.body.copyWith(color: colors.textPrimary),
            ),
            // 거리를 모르면 칸을 비운다. 임의의 값을 넣으면 목표가 달라 보인다.
            if (km != null)
              Text(
                AppStrings.matchRoomTarget(km),
                style: AppTypography.body.copyWith(color: colors.textPrimary),
              ),
          ],
        ),
      ),
    );
  }
}

/// 파티원 한 줄.
///
/// ⚠️ **페이스를 적지 않는다.** 정본이 뺀 항목이다 — 경쟁이 아니라 동행이다.
class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.player});

  final RoomPlayer player;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final name = player.isDeleted
        ? AppStrings.matchRoomDeletedPlayer
        : player.nickname;
    final image = player.profileImageUrl;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: AppRadius.md,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space3),
        child: Row(
          children: [
            Container(
              width: AppSizes.touchDefault,
              height: AppSizes.touchDefault,
              decoration: BoxDecoration(
                color: colors.primaryMuted,
                borderRadius: AppRadius.full,
                image: image == null || player.isDeleted
                    ? null
                    : DecorationImage(
                        image: NetworkImage(image),
                        fit: BoxFit.cover,
                      ),
              ),
              alignment: Alignment.center,
              child: image != null && !player.isDeleted
                  ? null
                  : Icon(
                      LucideIcons.user,
                      size: AppSpacing.space5,
                      color: colors.primary,
                    ),
            ),
            const SizedBox(width: AppSpacing.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: AppTypography.body.copyWith(
                      color: player.isDeleted
                          ? colors.textTertiary
                          : colors.textPrimary,
                    ),
                  ),
                  if (!player.isDeleted && player.introduction != null)
                    Text(
                      player.introduction!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 알아야 하는 한 줄.
class _Notice extends StatelessWidget {
  const _Notice(this.text);

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
