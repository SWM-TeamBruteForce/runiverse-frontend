import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/empty_state.dart';
import 'package:runiverse/features/friend/presentation/friend_provider.dart';
import 'package:runiverse/features/matching/domain/invite_failure.dart';
import 'package:runiverse/features/matching/presentation/match_register_provider.dart';
import 'package:runiverse/features/notification/domain/app_notification.dart';
import 'package:runiverse/features/notification/presentation/notification_provider.dart';
import 'package:runiverse/features/notification/presentation/notification_row.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// 알림함 — 친구 요청·수락과 러닝 초대가 한 목록에 모인다.
///
/// ## ⚠️ 열면 목록을 받은 **뒤에** 모두 읽음을 부른다
///
/// 순서를 바꾸면 목록 응답에서 안 읽은 표시가 사라져 **새 알림을 강조할 수
/// 없다.** 모두 읽음이 성공하면 배지는 0이 되고, 화면의 강조는 그대로 남는다 —
/// 연동 가이드가 의도된 동작이라고 못 박았다.
class NotificationPage extends ConsumerStatefulWidget {
  const NotificationPage({super.key});

  @override
  ConsumerState<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends ConsumerState<NotificationPage> {
  final _scroll = ScrollController();

  /// 지금 서버에 다녀오는 알림. 그 줄의 버튼만 잠근다.
  final _busy = <int>{};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // 화면이 서기 전에 provider를 만지지 않는다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_enter());
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 목록을 받고, 그다음 모두 읽음.
  Future<void> _enter() async {
    final notifier = ref.read(notificationProvider.notifier);
    await notifier.refresh();
    if (!mounted) return;
    // ⚠️ **읽음 처리보다 먼저 채운다.** 한 페이지가 전부 처리된 건이면 화면이
    // 비는데, 그 상태로 "없어요"를 그리면 다음 페이지의 알림을 못 본다.
    await notifier.fillVisible();
    if (!mounted) return;
    await notifier.markAllRead();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final remaining = _scroll.position.maxScrollExtent - _scroll.offset;
    if (remaining > 240) return;
    unawaited(ref.read(notificationProvider.notifier).loadMore());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final state = ref.watch(notificationProvider);

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          color: colors.textPrimary,
          // 글자가 없는 단추라 읽을 것을 붙인다.
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          AppStrings.notificationTitle,
          style: AppTypographyV2.heading07.copyWith(color: colors.textPrimary),
        ),
      ),
      body: SafeArea(child: _body(state, colors)),
    );
  }

  Widget _body(NotificationState state, AppColorsV2 colors) {
    if (state.loading && state.visible.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // ⚠️ **"없다"보다 먼저 본다.** 못 받았는데 빈 상태를 그리면 알림이 쌓인
    // 사람에게 "아직 알림이 없어요"라고 말하게 된다.
    if (state.failure != null && state.visible.isEmpty) {
      return EmptyStateV2(
        icon: LucideIcons.cloudOff,
        message: AppStrings.notificationLoadFailed,
        cta: TextButton(
          onPressed: () => unawaited(_enter()),
          child: Text(
            AppStrings.notificationRetry,
            style: AppTypographyV2.body11.copyWith(color: colors.primary),
          ),
        ),
      );
    }

    if (state.visible.isEmpty) {
      return const EmptyStateV2(
        icon: LucideIcons.bell,
        message: AppStrings.notificationEmpty,
        why: AppStrings.notificationEmptyWhy,
      );
    }

    final rows = state.visible;

    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: AppSpacing.space6),
      itemCount: rows.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, thickness: 0.6, color: colors.borderDefault),
      itemBuilder: (context, index) {
        final one = rows[index];
        return NotificationRow(
          notification: one,
          busy: _busy.contains(one.notificationId),
          onTap: () => _open(one),
          onAcceptFriend: () => unawaited(_acceptFriend(one)),
          onDeclineFriend: () => unawaited(_declineFriend(one)),
          onAcceptInvite: () => unawaited(_acceptInvite(one)),
          onDeclineInvite: () => unawaited(_declineInvite(one)),
        );
      },
    );
  }

  /// 줄을 눌렀을 때 어디로 가는가. **와이어프레임 C7의 랜딩 규칙을 따른다.**
  void _open(AppNotification one) {
    final invitation = one.invitation;
    if (invitation == null) {
      // 친구 요청·수락 → 상대 프로필(C7 "새 팔로워 → 상대 프로필").
      context.push(AppRoutes.userProfileOf(one.actor.userId));
      return;
    }
    // 이미 수락한 초대만 방으로 보낸다. 그 밖의 상태는 줄에 안내만 있다.
    if (invitation.status == InvitationStatus.accepted) {
      context.push(AppRoutes.matchRoom);
    }
  }

  Future<void> _acceptFriend(AppNotification one) => _guard(one, () async {
    await ref.read(friendProvider.notifier).accept(one.actor.userId);
    // 관계가 바뀌었으니 줄의 버튼이 사라져야 한다. 목록을 다시 읽는다 —
    // 같은 사람의 알림이 여러 개일 수 있고, 그 전부가 함께 바뀐다.
    await ref.read(notificationProvider.notifier).refresh();
  });

  Future<void> _declineFriend(AppNotification one) => _guard(one, () async {
    // ⚠️ 거절과 취소가 같은 `DELETE /{userId}/friend-request`다 — 저장소에
    // 메서드가 하나뿐이다.
    await ref.read(friendProvider.notifier).cancel(one.actor.userId);
    await ref.read(notificationProvider.notifier).refresh();
  });

  Future<void> _acceptInvite(AppNotification one) => _guard(one, () async {
    final roomId = one.invitation!.runningRoomId;
    final notifier = ref.read(notificationProvider.notifier);

    try {
      await ref.read(matchRepositoryProvider).acceptInvitation(roomId);
    } on InviteException catch (error) {
      if (!mounted) return;
      _say(_inviteMessage(error));
      // ⚠️ **꽉 찬 방만 초대가 `PENDING`으로 남는다.** 자리가 생기면 다시
      // 누를 수 있어서 버튼을 지우지 않는다. 나머지는 상태가 바뀌었으니
      // 목록을 다시 읽어 버튼을 거둔다.
      if (error.failure != InviteFailure.roomFull) await notifier.refresh();
      return;
    }

    // ⚠️ **상태를 다시 읽어야 방 화면이 스트림을 연다.** `match_room_provider`
    // 는 `userStatusProvider`가 `WAITING`·`READY`를 말할 때만 붙는다 —
    // 건너뛰면 방 화면이 빈 채로 선다.
    await ref.read(userStatusProvider.notifier).refresh();
    // 같은 방의 알림이 여럿일 수 있다. 전부 함께 바꾼다.
    notifier.updateRoom(roomId, InvitationStatus.accepted);
    if (!mounted) return;
    context.push(AppRoutes.matchRoom);
  });

  Future<void> _declineInvite(AppNotification one) => _guard(one, () async {
    final roomId = one.invitation!.runningRoomId;
    final notifier = ref.read(notificationProvider.notifier);

    try {
      await ref.read(matchRepositoryProvider).declineInvitation(roomId);
    } on InviteException catch (error) {
      if (!mounted) return;
      _say(_inviteMessage(error));
      await notifier.refresh();
      return;
    }
    notifier.updateRoom(roomId, InvitationStatus.declined);
  });

  /// 같은 줄을 두 번 누르는 것을 막고, 누르는 동안 잠근다.
  Future<void> _guard(AppNotification one, Future<void> Function() run) async {
    if (_busy.contains(one.notificationId)) return;
    setState(() => _busy.add(one.notificationId));
    try {
      await run();
    } finally {
      if (mounted) setState(() => _busy.remove(one.notificationId));
    }
  }

  /// **서버 문구를 그대로 쓴다.** 없으면 갈래별 기본 문구다.
  String _inviteMessage(InviteException error) =>
      error.message ??
      switch (error.failure) {
        InviteFailure.closed => AppStrings.notificationInviteExpired,
        InviteFailure.notPending => AppStrings.notificationInviteExpired,
        InviteFailure.roomFull => AppStrings.inviteRoomFull,
        _ => AppStrings.notificationLoadFailed,
      };

  void _say(String message) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}
