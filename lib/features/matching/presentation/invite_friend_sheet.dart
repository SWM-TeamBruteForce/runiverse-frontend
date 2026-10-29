import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/empty_state.dart';
import 'package:runiverse/core/widgets/v2/runner_avatar.dart';
import 'package:runiverse/features/friend/domain/friend_entry.dart';
import 'package:runiverse/features/friend/presentation/friend_provider.dart';
import 'package:runiverse/features/matching/domain/invite_failure.dart';
import 'package:runiverse/features/matching/domain/invite_limits.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';
import 'package:runiverse/features/matching/presentation/match_register_provider.dart';

/// 방에서 러너를 골라 초대하는 바텀시트.
Future<void> showInviteFriendSheet(
  BuildContext context, {
  required RoomInfo room,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => InviteFriendSheet(room: room),
);

/// ## ⚠️ 한 번에 한 명씩 보낸다
///
/// 서버가 `inviteeId` 하나만 받는다. 그래서 다중 선택 + "초대하기" 한 방이
/// 아니라 **줄마다 버튼**이다 — 결과도 한 줄씩 돌아오고, 실패 사유가 사람마다
/// 다르다.
///
/// ## ⚠️ 친구별 "지금 초대 가능"을 서버가 주지 않는다
///
/// 실패 사유가 다섯인데(친구 아님·이미 방에·매칭 중·러닝 중·횟수 초과) 친구
/// 목록은 그 정보를 주지 않는다(설계 §8-4). 전원 멀쩡한 것처럼 그리고,
/// **눌러서 실패를 알게 된다.** 실패 문구는 서버 `message`를 그대로 쓴다.
///
/// ## ⚠️ 독촉을 내보내지 않는다
///
/// 서버는 `PENDING`인 사람에게 다시 보내는 것을 허용하지만, 그 줄의 버튼은
/// 잠겨 있다. **남은 횟수를 알 수 없기 때문이다** — 상한이 5회인데
/// `invitations[]`에 횟수가 없고 보낸 사람별로 세니 앱이 셀 수도 없다. 몇 번
/// 남았는지 못 말하면서 누르라고 권하는 버튼이 된다. 횟수 필드가 생기면
/// 잠긴 줄에 `다시 알림`을 붙인다.
class InviteFriendSheet extends ConsumerStatefulWidget {
  const InviteFriendSheet({required this.room, super.key});

  final RoomInfo room;

  @override
  ConsumerState<InviteFriendSheet> createState() => _InviteFriendSheetState();
}

class _InviteFriendSheetState extends ConsumerState<InviteFriendSheet> {
  /// 이 시트에서 초대를 보낸 사람. 스트림이 `invitations`를 갱신하기 전까지
  /// 버튼을 잠가 둔다 — 두 번 눌려 횟수가 헛되이 줄어드는 것을 막는다.
  final _sent = <String>{};

  /// 실패한 사람과 그 문구. **서버가 준 말을 그대로 들고 있는다.**
  final _failed = <String, String>{};

  /// 지금 서버에 다녀오는 사람.
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(friendProvider.notifier).load());
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final state = ref.watch(friendProvider);
    final room = widget.room;

    final taken = {for (final one in room.players) one.userId};
    final pending = {for (final one in room.invitations) one.userId};
    final seatsLeft =
        InviteLimits.capacity - room.players.length - room.invitations.length;

    // 검색 중이면 결과를, 아니면 친구 묶음을 깐다.
    final entries = state.searching
        ? state.results
        : [for (final group in state.groups) ...group.entries];

    return Padding(
      // 키보드가 올라오면 시트가 그 위로 따라 올라간다(FE노트 S17).
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: colors.bgSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: colors.borderDefault)),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.space4,
          AppSpacing.space3,
          AppSpacing.space4,
          AppSpacing.space6,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.space4),
              Text(
                AppStrings.inviteSheetTitle,
                style: AppTypographyV2.heading07.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.space3),
              _SearchField(colors: colors),
              const SizedBox(height: AppSpacing.space2),
              Flexible(
                child: entries.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: AppSpacing.space8,
                        ),
                        child: EmptyStateV2(
                          icon: LucideIcons.userPlus,
                          message: AppStrings.inviteSheetEmpty,
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return _Row(
                            entry: entry,
                            state: _stateOf(
                              entry,
                              taken: taken,
                              pending: pending,
                              seatsLeft: seatsLeft,
                            ),
                            failure: _failed[entry.userId],
                            busy: _busy.contains(entry.userId),
                            onInvite: () => unawaited(_invite(entry)),
                          );
                        },
                      ),
              ),
              const SizedBox(height: AppSpacing.space3),
              Text(
                AppStrings.inviteRoomSeatsLeft(seatsLeft < 0 ? 0 : seatsLeft),
                textAlign: TextAlign.center,
                style: AppTypographyV2.body18.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 그 줄이 지금 어떤 상태인가.
  _RowState _stateOf(
    FriendEntry entry, {
    required Set<String> taken,
    required Set<String> pending,
    required int seatsLeft,
  }) {
    if (taken.contains(entry.userId)) return _RowState.joined;
    if (pending.contains(entry.userId) || _sent.contains(entry.userId)) {
      return _RowState.invited;
    }
    if (_failed.containsKey(entry.userId)) return _RowState.retry;
    // ⚠️ **자리가 없으면 잠근다.** 서버는 꽉 찬 방에도 초대를 받아 주지만,
    // 상대가 수락할 때 막힌다 — 보내 봐야 상대만 헛걸음한다.
    if (seatsLeft <= 0) return _RowState.full;
    return _RowState.invitable;
  }

  Future<void> _invite(FriendEntry entry) async {
    if (_busy.contains(entry.userId)) return;
    setState(() {
      _busy.add(entry.userId);
      _failed.remove(entry.userId);
    });

    try {
      await ref
          .read(matchRepositoryProvider)
          .invite(roomId: widget.room.runningRoomId, inviteeId: entry.userId);
      if (!mounted) return;
      // 스트림이 `invitations`를 실어 올 때까지 이 표시가 자리를 지킨다.
      setState(() => _sent.add(entry.userId));
    } on InviteException catch (error) {
      if (!mounted) return;
      setState(() => _failed[entry.userId] = _message(error));
    } finally {
      if (mounted) setState(() => _busy.remove(entry.userId));
    }
  }

  /// **서버 문구를 그대로 쓴다.** 없으면 갈래별 기본 문구다.
  String _message(InviteException error) =>
      error.message ??
      switch (error.failure) {
        InviteFailure.notFriend => AppStrings.inviteSheetNotFriend,
        InviteFailure.alreadyInRoom => AppStrings.inviteSheetAlreadyInRoom,
        InviteFailure.inMatching => AppStrings.inviteSheetInMatching,
        InviteFailure.running => AppStrings.inviteSheetRunning,
        InviteFailure.countExceeded => AppStrings.inviteSheetCountExceeded,
        InviteFailure.closed => AppStrings.notificationInviteExpired,
        InviteFailure.notFound => AppStrings.inviteSheetRoomGone,
        _ => AppStrings.inviteSheetFailed,
      };
}

enum _RowState { invitable, invited, joined, retry, full }

class _SearchField extends ConsumerWidget {
  const _SearchField({required this.colors});

  final AppColorsV2 colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) => TextField(
    onChanged: ref.read(friendProvider.notifier).onQuery,
    style: AppTypographyV2.body12.copyWith(color: colors.textPrimary),
    decoration: InputDecoration(
      hintText: AppStrings.inviteSheetSearchHint,
      hintStyle: AppTypographyV2.body12.copyWith(color: colors.textTertiary),
      prefixIcon: Icon(
        LucideIcons.search,
        size: AppSpacing.space4,
        color: colors.textTertiary,
      ),
      filled: true,
      fillColor: colors.bgBase,
      border: OutlineInputBorder(
        borderRadius: AppRadius.md,
        borderSide: BorderSide(color: colors.borderDefault),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppRadius.md,
        borderSide: BorderSide(color: colors.borderDefault),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space3,
        vertical: AppSpacing.space3,
      ),
    ),
  );
}

/// 한 줄 — 사진 · 닉네임 · (실패하면) 이유 · 버튼.
///
/// ⚠️ **`FriendRow`를 재사용하지 않는다.** 저쪽은 **관계**(`FriendRelation`)로
/// 버튼을 가르는데, 초대의 상태는 관계가 아니라 **방 안의 자리**다. 같은
/// 위젯에 두 체계를 섞으면 어느 쪽이 버튼을 정하는지 읽을 수 없게 된다.
class _Row extends StatelessWidget {
  const _Row({
    required this.entry,
    required this.state,
    required this.busy,
    required this.onInvite,
    this.failure,
  });

  final FriendEntry entry;
  final _RowState state;
  final bool busy;
  final VoidCallback onInvite;
  final String? failure;

  static const _avatar = 36.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final locked = state != _RowState.invitable && state != _RowState.retry;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space2),
      child: Row(
        children: [
          RunnerAvatarV2(
            nickname: entry.nickname,
            imageUrl: entry.profileImageUrl,
            size: _avatar,
          ),
          const SizedBox(width: AppSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.nickname,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypographyV2.body11.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                if (failure != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      failure!,
                      style: AppTypographyV2.body18.copyWith(
                        color: colors.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.space2),
          _InviteButton(
            label: switch (state) {
              _RowState.invitable ||
              _RowState.full => AppStrings.inviteSheetInvite,
              _RowState.invited => AppStrings.inviteSheetInvited,
              _RowState.joined => AppStrings.inviteSheetJoined,
              _RowState.retry => AppStrings.inviteSheetRetry,
            },
            onPressed: locked || busy ? null : onInvite,
            colors: colors,
          ),
        ],
      ),
    );
  }
}

class _InviteButton extends StatelessWidget {
  const _InviteButton({
    required this.label,
    required this.onPressed,
    required this.colors,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppColorsV2 colors;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return Material(
      color: enabled ? colors.primary : Colors.transparent,
      borderRadius: AppRadius.sm,
      child: InkWell(
        onTap: onPressed,
        borderRadius: AppRadius.sm,
        child: Container(
          constraints: const BoxConstraints(minWidth: 72),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space3,
            vertical: AppSpacing.space2,
          ),
          decoration: BoxDecoration(
            border: Border.all(
              color: enabled ? colors.primary : colors.borderStrong,
              width: 0.6,
            ),
            borderRadius: AppRadius.sm,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppTypographyV2.body21.copyWith(
              color: enabled ? colors.bgBase : colors.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}
