import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/core/widgets/v2/app_icon.dart';
import 'package:runiverse/core/widgets/v2/fact_card.dart';
import 'package:runiverse/core/widgets/v2/party_chip.dart';
import 'package:runiverse/core/widgets/v2/surface_card.dart';
import 'package:runiverse/features/matching/domain/invite_limits.dart';
import 'package:runiverse/features/matching/domain/room_invitation.dart';
import 'package:runiverse/features/matching/presentation/invite_friend_sheet.dart';
import 'package:runiverse/features/session/domain/user_status.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';
import 'package:runiverse/features/matching/presentation/match_room_provider.dart';

/// 대기방 (S10). 시안 `158:3415` `매칭 완료 / 세션 로비 페이지`.
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
///
/// 취소 문구도 고쳤다. 정본의 "우선순위가 낮아져요"는 실제 정책이 아니다 —
/// **확정 뒤에 나가면 20분 동안 다시 신청할 수 없다.**
///
/// ## 시안과 다르게 둔 것
///
/// - **나가기 안내 한 줄을 남겼다.** 시안에는 없지만 20분 제재를 알리는
///   유일한 자리다. 없애면 사람이 모르고 나간다
/// - **오른쪽 위 아이콘을 넣지 않았다.** 시안에 있지만 무엇을 하는지 정해진
///   바가 없고, 하단에 이미 나가기 버튼이 있다
/// - **한 줄 소개를 뺐다.** 시안의 참여자 카드는 사진과 이름만 보여준다
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
    final colors = context.appColorsV2;
    final state = ref.watch(matchRoomProvider);
    final room = state.room;

    // 방이 없어졌다. 취소됐거나 나갔다 — 어느 쪽이든 여기 남을 이유가 없다.
    ref.listen(matchRoomProvider.select((state) => state.room == null), (
      _,
      gone,
    ) {
      if (!gone || _leaving || !mounted) return;
      _leaveScreen();
    });

    // 아직 첫 스냅샷이 오지 않았다. **비워두지 않는다** — 빈 화면은 고장으로
    // 읽히고, AppBar가 없으면 돌아갈 길도 사라진다.
    if (room == null) {
      return Scaffold(
        backgroundColor: colors.bgBase,
        appBar: _appBar(colors, AppStrings.matchRoomTitleLobby),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: _appBar(
        colors,
        // ⚠️ **제목이 곧 상태다.** 시안(`158:3416`)이 여기에 `매칭완료`를
        // 둔다. 상태를 따로 표시하는 줄이 없으므로, 제목을 `로비`·`대기실`
        // 같은 장소 이름으로 두면 지금이 어느 단계인지 알 길이 사라진다.
        _title(room),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space4,
                  AppSpacing.space6,
                  AppSpacing.space4,
                  AppSpacing.space6,
                ),
                children: [
                  // ⚠️ `connected`가 아니라 `failure`를 본다. 서버가 30분마다
                  // 스트림을 정상으로 닫는데(`match-stream.timeout`), 그때마다
                  // 1초 남짓 이 문구를 띄우면 **스스로 낫는 일에 겁을 주는
                  // 셈**이다. 정상 종료는 실패를 남기지 않고 조용히 다시 붙고,
                  // 다시 붙는 데 실패한 경우에만 여기가 켜진다.
                  if (state.failure != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.space6),
                      child: _Notice(AppStrings.matchRoomDisconnected),
                    ),

                  // ⚠️ **기기 시계가 아니라 서버 시계로 센다.** 시계가 틀린
                  // 기기에서 `모집 마감까지 23:58:26`이 떴다.
                  _Headline(room: room, now: state.serverNow(_now)),
                  const SizedBox(height: AppSpacing.space10),

                  _SessionCards(room: room),
                  const SizedBox(height: AppSpacing.space5),

                  _PartyCard(
                    players: room.players,
                    // ⚠️ **모집 마감 뒤에는 서버가 빈 배열을 보낸다.** 그래서
                    // 마감되면 초대 현황이 저절로 사라진다 — 따로 지우지
                    // 않는다.
                    invitations: room.invitations,
                  ),

                  if (_invitable(room)) ...[
                    const SizedBox(height: AppSpacing.space4),
                    AppButtonV2(
                      label: AppStrings.inviteRoomInviteCta,
                      variant: AppButtonV2Variant.secondary,
                      onPressed: () => _openInviteSheet(room),
                    ),
                  ],

                  const SizedBox(height: AppSpacing.space5),
                  if (_warnsAlone(room))
                    _Notice(AppStrings.inviteRoomAloneWarning)
                  else
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
              child: AppButtonV2(
                label: _leaveLabel(room),
                variant: AppButtonV2Variant.secondary,
                onPressed: _leaving ? null : () => _confirmLeave(room),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 제목만 가운데 두는 헤더. 시안이 그렇게 생겼다.
  PreferredSizeWidget _appBar(AppColorsV2 colors, String title) => AppBar(
    backgroundColor: colors.bgBase,
    surfaceTintColor: Colors.transparent,
    centerTitle: true,
    title: Text(
      title,
      style: AppTypographyV2.heading06.copyWith(color: colors.textPrimary),
    ),
  );

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

  /// 제목만으로 지금이 어느 단계인지 알아야 한다.
  ///
  /// ⚠️ **초대 방은 `매칭 완료`라고 하지 않는다.** 매칭이 성사된 것이 아니라
  /// 더 들어올 자리가 닫힌 것뿐이다.
  String _title(RoomInfo room) {
    final waiting = room.status == RoomStatus.matching;
    if (room.type == RoomType.invite) {
      return waiting
          ? AppStrings.inviteRoomWaiting
          : AppStrings.inviteRoomClosed;
    }
    return waiting ? AppStrings.matchRoomWaiting : AppStrings.matchRoomMatched;
  }

  /// 지금 더 초대할 수 있는가.
  ///
  /// 초대 방이고, 모집 중이고, 자리가 남아야 한다. **꽉 찬 방에도 서버는
  /// 초대를 받아 주지만** 상대가 수락할 때 `RUNNING_ROOM_FULL`로 막히므로
  /// 보내 봐야 헛일이다.
  bool _invitable(RoomInfo room) =>
      room.type == RoomType.invite &&
      room.status == RoomStatus.matching &&
      room.players.length + room.invitations.length < InviteLimits.capacity;

  /// 혼자인 방에 마감이 가까운가.
  ///
  /// ## ⚠️ 마감 전 유일한 출구를 알리는 자리다
  ///
  /// 초대 취소가 없고 `CANCELLED`도 오지 않아서, 마감되면 **혼자 출발한다.**
  /// 그 전에 나가는 것 말고 길이 없다.
  ///
  /// 답을 기다리는 초대가 남아 있으면 경고하지 않는다 — 아직 올 사람이 있다.
  /// 서버가 말하는 지금. 화면의 모든 시각 판정이 이것을 본다.
  DateTime get _serverNow => ref.read(matchRoomProvider).serverNow(_now);

  bool _warnsAlone(RoomInfo room) {
    if (room.type != RoomType.invite) return false;
    if (room.status != RoomStatus.matching) return false;
    if (!room.isAlone || room.invitations.isNotEmpty) return false;

    final closeAt = room.closeAt;
    if (closeAt == null) return false;
    final left = closeAt.difference(_serverNow);
    return !left.isNegative && left <= _aloneWarning;
  }

  /// 마감 몇 분 전부터 경고하는가. 초대 방 마감이 시작 1분 전이라 그보다
  /// 넉넉히 둔다 — 1분 전에 알리면 나갈 시간이 없다.
  static const _aloneWarning = Duration(minutes: 3);

  Future<void> _openInviteSheet(RoomInfo room) async {
    await showInviteFriendSheet(context, room: room);
  }

  /// 나가기 버튼의 글자.
  ///
  /// ⚠️ **초대 방에서는 `매칭 취소하기`가 거짓이다.** 매칭을 신청한 적이 없고,
  /// 나가도 제재가 없다.
  String _leaveLabel(RoomInfo room) {
    if (room.type == RoomType.invite) return AppStrings.inviteRoomLeave;
    return room.status == RoomStatus.matching
        ? AppStrings.matchRoomCancel
        : AppStrings.matchRoomLeave;
  }

  /// 나가면 어떻게 되는지. **제재가 걸릴 때만 겁을 준다.**
  ///
  /// 판정 기준은 방의 `status`가 아니라 **모집 마감 시각**이다 — 마감이 지났는데
  /// 서버가 아직 방을 안 닫은 틈이 있어서, 서버도 시각으로 가른다.
  /// 혼자 남은 방은 마감이 지났어도 면제다.
  String _leaveNotice(RoomInfo room) {
    // ⚠️ **초대 방은 제재가 없다.** 매칭 방의 문구를 그대로 쓰면 "20분 동안
    // 다시 신청할 수 없어요"라고 거짓말을 한다.
    if (room.type == RoomType.invite) {
      return room.isAlone
          ? AppStrings.inviteRoomLeaveLast
          : AppStrings.inviteRoomLeaveFree;
    }

    final closeAt = room.closeAt;
    final closed = closeAt != null && !_serverNow.isBefore(closeAt);
    return closed && !room.isAlone
        ? AppStrings.matchRoomLeavePenalty
        : AppStrings.matchRoomLeaveFree;
  }

  Future<void> _confirmLeave(RoomInfo room) async {
    final colors = context.appColorsV2;
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.bgElevated,
        title: Text(
          AppStrings.matchRoomLeaveTitle,
          style: AppTypographyV2.heading06.copyWith(color: colors.textPrimary),
        ),
        content: Text(
          _leaveNotice(room),
          style: AppTypographyV2.body07.copyWith(color: colors.textSecondary),
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
    // 나가는 순서는 provider가 안다. 히어로에서 취소할 때와 같은 순서여야 한다.
    final left = await ref.read(matchRoomProvider.notifier).leave();
    if (!mounted) return;

    if (!left) {
      setState(() => _leaving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text(AppStrings.matchRoomLeaveFailed)),
        );
      return;
    }

    _leaveScreen();
  }

  /// 이 화면에서 빠져나간다.
  ///
  /// ## ⚠️ `pop`만으로는 부족하다
  ///
  /// 이 화면에 **스택 없이 들어올 수 있다.** 초대 등록이 `go`로 들어오던 동안
  /// 방을 나가도 `pop()`이 아무 일도 하지 않아 **빈 방 화면에 갇혔다**(실측
  /// 2026-10-29). 지금은 `pushReplacement`로 들어오지만, 딥링크나 다음에 생길
  /// 경로가 같은 함정을 다시 밟지 않게 여기서 막는다.
  void _leaveScreen() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(AppRoutes.home);
  }
}

/// 화면 맨 위 — 지금이 어느 단계이고 얼마나 남았는가.
class _Headline extends StatelessWidget {
  const _Headline({required this.room, required this.now});

  final RoomInfo room;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
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
        // 무엇을 세고 있는지. 시안의 알약 배지다(`158:3420`).
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.primaryMuted,
            borderRadius: AppRadius.full,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space5,
              vertical: AppSpacing.space3,
            ),
            child: Text(
              started
                  ? AppStrings.matchRoomStarted
                  : matching
                  ? AppStrings.matchRoomCloseLabel
                  : AppStrings.matchRoomStartLabel,
              style: AppTypographyV2.body06.copyWith(
                color: colors.matchWaiting,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.space3),

        if (!started) ...[
          Text(
            remaining == null
                ? '--:--'
                : AppStrings.matchRoomCountdown(remaining),
            textAlign: TextAlign.center,
            style: AppTypographyV2.heading01.copyWith(
              color: colors.textPrimary,
              // 1초마다 갈리는 숫자다. 자릿수가 흔들리면 글자가 춤춘다.
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: AppSpacing.space3),
          Text(
            matching
                ? AppStrings.matchRoomJoined(room.players.length)
                : AppStrings.matchRoomMatchedHint,
            textAlign: TextAlign.center,
            style: AppTypographyV2.body06.copyWith(color: colors.textTertiary),
          ),
        ],
      ],
    );
  }
}

/// 시작 시각과 목표 거리 — 시안은 카드 두 장이다(`158:3425`·`158:3429`).
class _SessionCards extends StatelessWidget {
  const _SessionCards({required this.room});

  final RoomInfo room;

  @override
  Widget build(BuildContext context) {
    final meters = room.targetDistanceMeters;

    // ⚠️ 값에는 **숫자와 단위만** 둔다. 카드가 `시작 시간`·`목표 거리`를
    // 이미 이고 있어서, 값에 다시 `시작`·`목표`를 붙이면 같은 말이
    // 두 번 나온다.

    return Row(
      children: [
        Expanded(
          child: FactCard(
            label: AppStrings.matchRoomStartTimeLabel,
            value: AppStrings.matchSlotTime(room.scheduledStartAt),
          ),
        ),
        const SizedBox(width: AppSpacing.space3),
        Expanded(
          // ⚠️ **`TargetDistance`를 거치지 않는다.** 그쪽은 3/5/10km만 아는
          // enum이라 초대 러닝의 자유 거리(7km·하프·풀)가 `null`이 되고, 그러면
          // **옆 칸이 그대로 빈다**(실측 2026-10-29).
          //
          // 거리를 모를 때만 비운다. 임의의 값을 넣으면 목표가 달라 보인다.
          child: meters == null
              ? const SizedBox.shrink()
              : FactCard(
                  label: AppStrings.matchDistanceLabel,
                  value: AppStrings.distanceKm(meters),
                ),
        ),
      ],
    );
  }
}

/// 함께 뛸 사람들 — 시안은 카드 하나에 아바타를 가로로 늘어놓는다(`158:3435`).
///
/// ⚠️ **페이스를 적지 않는다.** 정본이 뺀 항목이다 — 경쟁이 아니라 동행이다.
/// 참가자와 **답을 기다리는 초대**를 함께 깐다.
///
/// 초대는 점선 칩으로 서고, `players`보다 뒤에 온다 — 들어온 사람이 먼저다.
class _PartyCard extends StatelessWidget {
  const _PartyCard({required this.players, this.invitations = const []});

  final List<RoomPlayer> players;

  /// 답을 기다리는 초대. **매칭 방은 늘 비어 있다.**
  final List<RoomInvitation> invitations;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space4,
        vertical: AppSpacing.space5,
      ),
      child: Column(
        children: [
          Text(
            AppStrings.matchRoomPlayers(players.length),
            style: AppTypographyV2.body13.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.space4),
          // 방은 최대 4명이다. 사람마다 같은 폭의 칸을 줘서 아바타 중심
          // 간격을 맞춘다 — 이름 길이에 칩 폭을 맡기면 들쭉날쭉해진다.
          PartyChipRow(
            maxChipWidth: AppSpacing.space10,
            children: [
              for (final player in players)
                PartyChip(
                  name: player.isDeleted
                      ? AppStrings.matchRoomDeletedPlayer
                      : player.nickname,
                  imageUrl: player.isDeleted ? null : player.profileImageUrl,
                  // 탈퇴한 사람은 흐리게. 시안은 이 대비를 준비 상태에 쓰는데,
                  // 우리는 서버가 참가자 상태를 안 줘서 표시할 것이 없다.
                  accent: player.isDeleted
                      ? colors.textTertiary
                      : colors.primary,
                ),
              // 답을 기다리는 사람. 들어온 사람 뒤에 선다.
              for (final one in invitations)
                PartyChip(
                  name: AppStrings.inviteRoomPending(one.nickname),
                  imageUrl: one.profileImageUrl,
                  // 아직 들어오지 않았다는 뜻으로 흐리게 둔다.
                  accent: colors.textTertiary,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);

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
