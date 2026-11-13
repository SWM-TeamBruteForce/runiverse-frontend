import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/theme/v2/run_palette.dart';
import 'package:runiverse/core/utils/profanity_filter.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/chat/domain/chat.dart';
import 'package:runiverse/features/chat/domain/chat_title.dart';
import 'package:runiverse/features/chat/presentation/chat_bubble.dart';
import 'package:runiverse/features/chat/presentation/chat_composer.dart';
import 'package:runiverse/features/chat/presentation/chat_provider.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';
import 'package:runiverse/features/matching/presentation/match_room_provider.dart';
import 'package:runiverse/features/session/domain/party_color.dart';

/// 대기방 채팅 — `AppRoutes.matchRoom`의 자식 라우트.
///
/// ## ⚠️ provider 둘을 각각 watch해서 합친다
///
/// `chatProvider`가 `matchRoomProvider`를 듣지 않는다 — 서로 들으면 Riverpod이
/// `CircularDependencyError`로 막는다. 그래서 **메시지는 채팅에서, 색은 방에서**
/// 읽고 이 화면이 둘을 맞춘다.
///
/// 이름·사진은 **메시지가 들고 온다**(`Chat.sender`). 방 명단에서 찾으면 방을
/// 떠난 사람의 지난 메시지가 전부 '탈퇴한 사용자'로 그려진다. 명단이 정하는
/// 것은 색뿐이다 — 러닝 화면에서 본 그 사람 색과 같아야 한다.
///
/// ## ⚠️ 방 화면은 이 페이지를 띄운 동안에도 살아 있다
///
/// go_router는 자식을 띄워도 부모를 내리지 않는다. 방이 사라지거나 출발 시각이
/// 닥칠 때 **이 페이지를 먼저 닫는 일은 방 화면이 한다**(`match_room_page.dart`).
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  /// 전송 버튼. **라벨이 없는 아이콘 버튼이라** 테스트가 글자로 찾을 수 없다.
  static const sendKey = Key('chat_send');

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  /// ⚠️ **미리 붙잡는다.** [dispose]에서 `ref.read`를 부르면 이미 내려간
  /// 트리에서 provider를 찾게 된다.
  late final ChatController _chat;

  final _scroll = ScrollController();

  /// 수정 중인 메시지. `null`이면 새 메시지를 쓰는 중이다.
  Chat? _editing;

  @override
  void initState() {
    super.initState();
    _chat = ref.read(chatProvider.notifier);
    // ⚠️ 첫 프레임 뒤에 연다. build 중에 provider 상태를 바꾸면 Riverpod이 막는다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _chat.open();
    });
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    // 떠났으니 이제 들어오는 것은 안 읽음으로 쌓인다.
    _chat.close();
    super.dispose();
  }

  /// 위로 끝까지 긁으면 이전 페이지를 받는다.
  ///
  /// ⚠️ **`reverse`라 "위"가 `maxScrollExtent`다.** 목록이 뒤집혀 있어서
  /// 아래(최신)가 0이고 위(과거)로 갈수록 값이 커진다.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels < position.maxScrollExtent - 200) return;
    // 부를지는 provider가 가린다 — 커서가 없거나 이미 긁는 중이면 안 부른다.
    unawaited(_chat.loadMore());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final state = ref.watch(chatProvider);
    final room = ref.watch(matchRoomProvider.select((state) => state.room));
    final auth = ref.watch(authControllerProvider);
    final myUserId = auth is AuthSignedIn ? auth.userId : null;

    final players = room?.players ?? const <RoomPlayer>[];

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: _Title(room: room, myUserId: myUserId),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: _body(
                state: state,
                players: players,
                myUserId: myUserId,
                colors: colors,
              ),
            ),
            // ⚠️ **닫혔으면 입력창을 치운다.** 러닝이 시작돼 되돌아오지 않는
            // 상태라, 두면 눌러도 아무 일이 없는 버튼이 남는다.
            if (state.closed)
              _Closed(colors: colors)
            else
              ChatComposer(
                sendButtonKey: ChatPage.sendKey,
                editing: _editing?.content,
                onCancelEdit: () => setState(() => _editing = null),
                onSend: _submit,
              ),
          ],
        ),
      ),
    );
  }

  /// 보내거나 고친다. **수정 중인지는 화면이 안다.**
  Future<void> _submit(String text) async {
    final editing = _editing;
    if (editing == null) {
      await _chat.send(text);
      return;
    }

    await _chat.edit(editing.chatId, text);
    if (mounted) setState(() => _editing = null);
  }

  /// loading · error · closed · empty · 목록. **모두 그린다.**
  Widget _body({
    required ChatState state,
    required List<RoomPlayer> players,
    required String? myUserId,
    required AppColorsV2 colors,
  }) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppStrings.chatFailed,
                textAlign: TextAlign.center,
                style: AppTypographyV2.body12.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.space4),
              AppButtonV2(
                label: AppStrings.chatRetry,
                variant: AppButtonV2Variant.secondary,
                onPressed: _retry,
              ),
            ],
          ),
        ),
      );
    }

    if (state.messages.isEmpty && state.pending.isEmpty) {
      // ⚠️ 칩과 입력창은 이때도 보인다 — 먼저 말을 걸 수 있어야 한다.
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space6),
          child: Text(
            AppStrings.chatEmpty,
            textAlign: TextAlign.center,
            style: AppTypographyV2.body12.copyWith(color: colors.textTertiary),
          ),
        ),
      );
    }

    final order = [for (final player in players) player.userId];

    // ⚠️ **아래가 최신이다.** `reverse`라 index 0이 맨 아래라, 뒤집어 넣는다.
    // 보내는 중인 내 말은 가장 아래 — 방금 쓴 것이므로.
    final rows = <Object>[
      for (final one in state.pending.reversed) one,
      for (final one in state.messages.reversed) one,
      // 이전 페이지를 긁는 중이면 맨 위(= 목록의 끝)에 표시가 붙는다.
      if (state.loadingMore) _loadingMore,
    ];

    return ListView.separated(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.all(AppSpacing.space4),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.space3),
      itemBuilder: (context, index) {
        final row = rows[index];

        if (row == _loadingMore) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.space2),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        if (row is PendingChat) {
          return ChatPendingBubble(
            content: maskProfanity(row.content),
            failed: row.failed,
            onResend: () => unawaited(_chat.resend(row)),
            onDiscard: () => _chat.discard(row),
          );
        }

        final message = row as Chat;
        final mine = message.sender.userId == myUserId;

        return ChatBubble(
          // ⚠️ **가리는 것은 여기뿐이다.** 보내는 쪽에서 막으면 클라이언트를
          // 고친 사람에게 효력이 없고, 그리는 쪽에서 가리면 상대가 무슨 앱을
          // 쓰든 보는 사람이 보호된다. 원문은 상태에 그대로 남는다 — 신고
          // 기능이 붙을 때 넘길 것이 있어야 한다.
          text: maskProfanity(message.content ?? ''),
          time: AppStrings.matchSlotTime(message.createdAt),
          mine: mine,
          nickname: message.sender.nickname,
          deleted: message.isDeleted,
          edited: message.isEdited,
          // ⚠️ **명단에 없으면 방을 떠난 것이다.** 자리는 두고 본문만 가린다.
          //
          // 명단이 비었을 때는 **가리지 않는다.** 모집 마감이나 재연결 사이에
          // 빈 채로 올 수 있고, 그때 가리면 멀쩡한 대화가 통째로 흐려진다 —
          // 못 믿을 때는 가리지 않는 쪽이 안전하다.
          //
          // 내 말은 절대 가리지 않는다. 명단이 한 박자 늦게 오는 사이 내가 쓴
          // 말이 흐려지면 보낸 사람이 자기 말을 못 읽는다.
          blinded:
              !mine &&
              order.isNotEmpty &&
              !order.contains(message.sender.userId),
          // ⚠️ **내 것이고 안 지워졌을 때만** 수정·삭제가 있다. 남의 말은
          // 서버가 404로 막지만, 누를 수 있게 두면 안 되는 것을 눌러 보게 된다.
          onLongPress: mine && !message.isDeleted
              ? () => unawaited(_actionsFor(message))
              : null,
          // 명단에 없는 사람은 `partyColorSlot`이 팔레트 끝 색으로 떨군다.
          accent: _legible(
            RunPaletteV2.lane(
              partyColorSlot(
                userId: message.sender.userId,
                myUserId: myUserId,
                order: order,
              ),
            ),
            colors,
            Theme.of(context).brightness,
          ),
          imageUrl: message.sender.isDeleted
              ? null
              : message.sender.profileImageUrl,
        );
      },
    );
  }

  /// 긁는 중 표시를 목록에 끼우는 표식. 타입으로 가리기 위해 값 하나를 쓴다.
  static const _loadingMore = 'loading-more';

  /// 내 말을 길게 눌렀다. **수정과 삭제를 고른다.**
  Future<void> _actionsFor(Chat message) async {
    final colors = context.appColorsV2;

    final action = await showModalBottomSheet<_ChatAction>(
      context: context,
      backgroundColor: colors.bgElevated,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(LucideIcons.pencil, color: colors.textPrimary),
              title: Text(
                AppStrings.chatEditAction,
                style: AppTypographyV2.body07.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              onTap: () => Navigator.of(context).pop(_ChatAction.edit),
            ),
            ListTile(
              leading: Icon(LucideIcons.trash2, color: colors.error),
              title: Text(
                AppStrings.chatDeleteAction,
                style: AppTypographyV2.body07.copyWith(color: colors.error),
              ),
              onTap: () => Navigator.of(context).pop(_ChatAction.delete),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;

    switch (action) {
      case _ChatAction.edit:
        setState(() => _editing = message);
      case _ChatAction.delete:
        await _confirmDelete(message);
    }
  }

  /// ⚠️ **되돌릴 수 없어서 묻는다.** 길게 눌러 한 번 더 누르면 지워지는 자리에
  /// 확인이 없으면, 잘못 누른 말이 영영 사라진다.
  Future<void> _confirmDelete(Chat message) async {
    final colors = context.appColorsV2;

    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.bgElevated,
        title: Text(
          AppStrings.chatDeleteConfirmTitle,
          style: AppTypographyV2.heading06.copyWith(color: colors.textPrimary),
        ),
        content: Text(
          AppStrings.chatDeleteConfirmBody,
          style: AppTypographyV2.body07.copyWith(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStrings.chatEditCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(AppStrings.chatDeleteAction),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;

    await _chat.remove(message.chatId);
    // 고치려던 것을 지웠을 수 있다. 수정 중 상태를 들고 있으면 없는 메시지를
    // 고치려 든다.
    if (mounted && _editing?.chatId == message.chatId) {
      setState(() => _editing = null);
    }
  }

  /// 파티 색을 **이 테마에서 읽히는 색으로** 만든다.
  ///
  /// ## ⚠️ 레인 색은 어두운 러닝 화면을 기준으로 고른 것이다
  ///
  /// 라이트 테마의 흰 `bgBase` 위에서 측정하면 초록이 **1.99:1**, 주황이
  /// 2.46:1까지 떨어진다 — WCAG AA가 요구하는 4.5:1의 절반도 안 되고, 12px
  /// 닉네임은 사실상 안 보인다. 라이트에서만 `textPrimary` 쪽으로 45% 섞어
  /// 5.09~8.02:1로 올린다.
  ///
  /// 다크에서는 원색 그대로가 5.13~9.94:1이라 **건드리지 않는다** — 러닝 중·
  /// 결과 화면에서 본 그 사람 색과 같아야 한다.
  static Color _legible(
    Color lane,
    AppColorsV2 colors,
    Brightness brightness,
  ) => brightness == Brightness.light
      ? Color.lerp(lane, colors.textPrimary, 0.45)!
      : lane;

  void _retry() {
    final runningRoomId = ref.read(chatProvider).runningRoomId;
    if (runningRoomId == null) return;
    unawaited(_chat.connect(runningRoomId));
  }
}

enum _ChatAction { edit, delete }

/// 러닝이 시작돼 채팅이 닫혔다. **입력창 자리를 안내로 바꾼다.**
class _Closed extends StatelessWidget {
  const _Closed({required this.colors});

  final AppColorsV2 colors;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.space4),
    child: Text(
      AppStrings.chatClosed,
      textAlign: TextAlign.center,
      style: AppTypographyV2.body12.copyWith(color: colors.textTertiary),
    ),
  );
}

/// 두 줄 제목. 한 줄로 붙이면 닉네임이 길 때 `외 n명`이 먼저 잘려 나간다.
class _Title extends StatelessWidget {
  const _Title({required this.room, required this.myUserId});

  final RoomInfo? room;
  final String? myUserId;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final room = this.room;

    // 방이 아직(또는 이미) 없다. 제목을 비우지 않는다 — 빈 헤더는 고장으로 읽힌다.
    if (room == null) {
      return Text(
        AppStrings.matchRoomTitleLobby,
        style: AppTypographyV2.heading06.copyWith(color: colors.textPrimary),
      );
    }

    final title = chatTitleOf(
      scheduledStartAt: room.scheduledStartAt,
      targetDistanceMeters: room.targetDistanceMeters,
      players: room.players,
      myUserId: myUserId,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title.top,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypographyV2.heading08.copyWith(color: colors.textPrimary),
        ),
        if (title.bottom.isNotEmpty)
          Text(
            title.bottom,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypographyV2.body18.copyWith(color: colors.textSecondary),
          ),
      ],
    );
  }
}
