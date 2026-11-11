import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/theme/v2/run_palette.dart';
import 'package:runiverse/core/utils/profanity_filter.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/chat/domain/chat_message.dart';
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
/// `CircularDependencyError`로 막는다. 그래서 **메시지는 채팅에서, 사람은 방에서**
/// 읽고 이 화면이 둘을 맞춘다. 이름·사진·색이 전부 방 명단에서 나온다.
///
/// ## ⚠️ 방 화면은 이 페이지를 띄운 동안에도 살아 있다
///
/// go_router는 자식을 띄워도 부모를 내리지 않는다. 방이 사라지거나 출발 시각이
/// 닥칠 때 **이 페이지를 먼저 닫는 일은 방 화면이 한다**(`match_room_page.dart`).
/// 여기서 할 일은 없지만, 이 페이지가 맨 위에 있다는 사실이 그쪽 동작을 바꾼다.
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

  @override
  void initState() {
    super.initState();
    _chat = ref.read(chatProvider.notifier);
    // ⚠️ 첫 프레임 뒤에 연다. build 중에 provider 상태를 바꾸면 Riverpod이 막는다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _chat.open();
    });
  }

  @override
  void dispose() {
    // 떠났으니 이제 들어오는 것은 안 읽음으로 쌓인다.
    _chat.close();
    super.dispose();
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
            ChatComposer(sendButtonKey: ChatPage.sendKey, onSend: _chat.send),
          ],
        ),
      ),
    );
  }

  /// loading · error · empty · 목록. **네 가지를 모두 그린다.**
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

    if (state.messages.isEmpty) {
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

    // ⚠️ `reverse`로 둔다. 아래가 최신이고, **열면 맨 아래에서 시작한다** —
    // 스크롤 위치를 손으로 옮기면 목록이 자랄 때마다 어긋난다.
    return ListView.separated(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.space4,
        AppSpacing.space4,
        AppSpacing.space4,
        AppSpacing.space4,
      ),
      itemCount: state.messages.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.space3),
      itemBuilder: (context, index) {
        final message = state.messages[state.messages.length - 1 - index];
        final sender = _senderIn(players, message.senderUserId);
        final nickname = sender == null || sender.isDeleted
            ? AppStrings.matchRoomDeletedPlayer
            : sender.nickname;

        if (message.kind == ChatMessageKind.joined) {
          return ChatJoinedNotice(nickname: nickname);
        }

        return ChatBubble(
          // ⚠️ **가리는 것은 여기뿐이다.** 보내는 쪽에서 막으면 클라이언트를
          // 고친 사람에게 효력이 없고, 그리는 쪽에서 가리면 상대가 무슨 앱을
          // 쓰든 보는 사람이 보호된다. 원문은 상태에 그대로 남는다 — 신고
          // 기능이 붙을 때 넘길 것이 있어야 한다.
          text: maskProfanity(message.text ?? ''),
          time: AppStrings.matchSlotTime(message.sentAt),
          mine: message.senderUserId == myUserId,
          nickname: nickname,
          // 명단에 없는 사람은 `partyColorSlot`이 팔레트 끝 색으로 떨군다.
          accent: _legible(
            RunPaletteV2.lane(
              partyColorSlot(
                userId: message.senderUserId,
                myUserId: myUserId,
                order: order,
              ),
            ),
            colors,
            Theme.of(context).brightness,
          ),
          imageUrl: sender == null || sender.isDeleted
              ? null
              : sender.profileImageUrl,
        );
      },
    );
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
    final seed = ref.read(chatProvider).seed;
    if (seed == null) return;
    _chat.connect(seed);
  }

  /// 명단에서 찾는다. 없으면 `null` — 나갔거나 탈퇴한 사람이다.
  static RoomPlayer? _senderIn(List<RoomPlayer> players, String userId) {
    for (final player in players) {
      if (player.userId == userId) return player;
    }
    return null;
  }
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
