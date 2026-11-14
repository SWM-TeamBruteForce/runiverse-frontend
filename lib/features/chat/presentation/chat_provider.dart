import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/chat/data/http_chat_repository.dart';
import 'package:runiverse/features/chat/domain/chat.dart';
import 'package:runiverse/features/chat/domain/chat_event_bus.dart';
import 'package:runiverse/features/chat/domain/chat_failure.dart';
import 'package:runiverse/features/chat/domain/chat_merge.dart';
import 'package:runiverse/features/chat/domain/chat_repository.dart';
import 'package:runiverse/features/matching/presentation/match_room_provider.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => HttpChatRepository(
    ref.watch(dioProvider),
    ref.watch(tokenStoreProvider),
    ref.watch(tokenRefresherProvider),
  ),
);

/// 대기방 스트림이 받은 채팅 변화가 지나가는 자리.
///
/// ⚠️ **`keepAlive`가 필요하다**(Provider는 기본이 그렇다). 채팅 화면이
/// 버려졌다 살아나는 사이에 버스까지 새로 생기면, 매칭 방이 들고 있던 것과
/// 다른 버스가 되어 **이벤트가 영영 닿지 않는다.**
final chatEventBusProvider = Provider<ChatEventBus>((ref) {
  final bus = ChatEventBus();
  ref.onDispose(bus.close);
  return bus;
});

/// 아직 서버가 받지 않은 내 말.
///
/// ## ⚠️ 보내는 즉시 보여야 한다
///
/// 응답을 기다려 그리면 느린 망에서 **먹통으로 느낀다.** 그렇다고 성공한 척
/// 목록에 섞으면 실패했을 때 지울 자리를 못 찾는다 — `chatId`가 없어서다.
/// 그래서 따로 둔다.
class PendingChat {
  const PendingChat({
    required this.localId,
    required this.content,
    this.failed = false,
  });

  /// 화면이 목록 key로 쓴다. 서버의 `chatId`와 섞이지 않게 **음수**다.
  final int localId;
  final String content;

  /// `false`면 보내는 중이다.
  final bool failed;

  PendingChat get asFailed =>
      PendingChat(localId: localId, content: content, failed: true);
}

/// 한 방의 채팅.
class ChatState {
  const ChatState({
    this.messages = const [],
    this.pending = const [],
    this.loading = false,
    this.failure,
    this.closed = false,
    this.runningRoomId,
    this.opened = false,
    this.nextCursor,
    this.loadingMore = false,
  });

  /// **`chatId` 오름차순이다.** 서버는 최신순으로 주고, 화면은 아래가 최신이다.
  final List<Chat> messages;

  final List<PendingChat> pending;

  final bool loading;

  /// 목록을 못 받은 이유. `null`이면 정상이다.
  final ChatFailure? failure;

  /// 러닝이 시작돼 채팅이 닫혔다(409). **입력·수정·삭제를 전부 닫는다.**
  ///
  /// ⚠️ [failure]와 따로 둔다 — 닫힘은 실패가 아니라 **되돌아오지 않는 상태**라
  /// "다시 시도"를 띄우면 안 된다.
  final bool closed;

  /// 어느 방인가. `null`이면 아직 안 붙었다.
  final int? runningRoomId;

  /// 채팅 페이지가 떠 있는가. **들어온 메시지를 셀지 말지를 이것이 가른다.**
  final bool opened;

  /// 다음(더 이전) 페이지 커서. `null`이면 방의 첫 메시지까지 다 받았다.
  final String? nextCursor;

  final bool loadingMore;

  bool get failed => failure != null;
  bool get hasMore => nextCursor != null;

  /// 배지의 숫자. 보고 있지 않은 동안 쌓인 것만 센다.
  int get unread => messages.where((one) => !one.isRead).length;

  /// ## ⚠️ 지우는 것은 플래그로 말한다
  ///
  /// `??`만 쓰면 성공했을 때 실패를 못 지운다. 그렇다고 `??`를 빼면 **넘기지
  /// 않은 값이 조용히 지워진다** — 메시지를 보낼 때마다 [nextCursor]가 날아가고
  /// 위로 긁을 수 없게 된다. 그래서 지우는 자리만 그렇다고 적는다.
  ChatState copyWith({
    List<Chat>? messages,
    List<PendingChat>? pending,
    bool? loading,
    ChatFailure? failure,
    bool clearFailure = false,
    bool? closed,
    int? runningRoomId,
    bool? opened,
    String? nextCursor,
    bool clearCursor = false,
    bool? loadingMore,
  }) => ChatState(
    messages: messages ?? this.messages,
    pending: pending ?? this.pending,
    loading: loading ?? this.loading,
    failure: clearFailure ? null : (failure ?? this.failure),
    closed: closed ?? this.closed,
    runningRoomId: runningRoomId ?? this.runningRoomId,
    opened: opened ?? this.opened,
    nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

final chatProvider = NotifierProvider<ChatController, ChatState>(
  ChatController.new,
  // ⚠️ **기본값이 `false`다.** 코드생성이 아닌 `NotifierProvider`는 auto-dispose가
  // 아니다(riverpod 3.4.2 `src/providers/notifier/orphan.dart`의
  // `super.isAutoDispose = false`). 안 켜면 방을 떠난 뒤에도 지난 방의 메시지를
  // 들고 있게 된다.
  isAutoDispose: true,
);

/// 대기방 채팅을 들고 있는다.
///
/// ## ⚠️ 방 번호를 스스로 읽는다
///
/// 화면이 [connect]로 넣어 주게 두면, **아무도 보지 않는 동안 버려졌다 살아난
/// 뒤에 영영 다시 붙지 않는다.** 화면은 "이미 붙였다"고 기억하는데 provider는
/// 비어 있어서, 혼자 있다가 사람이 들어온 방의 채팅이 빈 목록으로 남았다.
///
/// 그래서 `matchRoomProvider`를 **듣는다**(`watch`가 아니다 — [build]가 다시
/// 돌면 들고 있던 메시지가 통째로 날아간다). 반대 방향은 없다. 매칭 방은
/// [ChatEventBus]라는 **값만 지나가는 자리**에 밀어 넣을 뿐 이 provider를
/// 모른다 — 서로 들으면 Riverpod이 `CircularDependencyError`로 막는다.
///
/// ## ⚠️ 실시간 수신은 저장소가 아니라 버스로 온다
///
/// 채팅 이벤트는 대기방 SSE가 나른다. 그 연결은 사용자당 하나만 유지되므로
/// 채팅이 따로 열 수 없다 — [ChatEventBus] 참고.
///
/// 채팅은 방에 묶인 것이라 `keepAlive`를 걸지 않는다 — 방을 떠나면 함께 사라진다.
class ChatController extends Notifier<ChatState> {
  /// ⚠️ **미리 붙잡아 두지 않는다.** `late final`로 들면 **다시 `build`될 때**
  /// `LateInitializationError`가 난다 — auto-dispose라 그 일이 실제로 생긴다.
  ChatRepository get _repo => ref.read(chatRepositoryProvider);

  StreamSubscription<ChatChange>? _subscription;

  /// 아직 살아 있는가. `await` 뒤에 상태를 쓰기 전에 본다.
  var _alive = false;

  /// 보내는 중인 내 말에 붙이는 번호. **음수로 내려간다** — 서버의 `chatId`와
  /// 섞이면 화면이 같은 key로 둘을 그린다.
  var _localId = 0;

  /// 첫 페이지는 50으로 받는다. 대기방 대화는 길지 않아 거의 한 번에 다 온다.
  static const _pageSize = 50;

  /// 서버가 받는 길이. **입력 단계에서 막는다** — 보내 보고 400을 그리면 쓴
  /// 말이 날아간 것처럼 보인다.
  static const maxLength = 200;

  @override
  ChatState build() {
    // 다시 build될 수 있으므로 **여기서 되살린다.**
    _alive = true;
    _subscription = ref.read(chatEventBusProvider).stream.listen(received);

    // ⚠️ **`listen`이다.** `watch`로 읽으면 방이 바뀌거나 스트림이 끊길 때마다
    // [build]가 다시 돌아 **들고 있던 메시지가 통째로 날아간다.**
    //
    // `fireImmediately`가 없으면 **이미 지나간 값을 영영 못 본다** — 방은
    // 대개 이 provider보다 먼저 들어와 있다.
    ref.listen(
      matchRoomProvider.select(
        (state) => (state.room?.runningRoomId, state.connected),
      ),
      _syncRoom,
      fireImmediately: true,
    );

    ref.onDispose(() {
      _alive = false;
      unawaited(_subscription?.cancel());
      _subscription = null;
    });
    return const ChatState();
  }

  /// 방이 바뀌었거나 스트림이 다시 붙었다.
  void _syncRoom((int?, bool)? was, (int?, bool) now) {
    final (runningRoomId, connected) = now;
    if (runningRoomId == null) return;

    // ⚠️ **한 틱 미룬다.** `fireImmediately`로 [build] 도중에 들어올 수 있고,
    // 그때 상태를 건드리면 Riverpod이 막는다. [connect]가 멱등이라 늦어도
    // 두 번 싣지 않는다.
    Future.microtask(() {
      if (!_alive) return;

      if (state.runningRoomId != runningRoomId) {
        unawaited(connect(runningRoomId));
        return;
      }

      // 같은 방인데 끊겼다 다시 붙었다. **놓친 채팅 이벤트는 다시 오지 않으므로**
      // (변경분이다) 목록을 다시 받는 것이 유일한 방법이다. 연결 유지 시간이
      // 30분이라 몇 시간짜리 대기는 반드시 한 번 이상 끊긴다.
      if (connected && was != null && !was.$2) unawaited(reload());
    });
  }

  /// 방에 붙어 첫 페이지를 받는다.
  ///
  /// **같은 방이면 다시 싣지 않는다** — 화면이 다시 그려질 때마다 과거를 또
  /// 부르면 목록이 깜빡이고 서버를 두 번 때린다. 실패한 뒤에는 다시 싣는다.
  ///
  /// ⚠️ **닫힌 뒤에는 다시 부르지 않는다.** 409는 되돌아오지 않는 상태다.
  Future<void> connect(int runningRoomId, {int limit = _pageSize}) async {
    if (state.closed && state.runningRoomId == runningRoomId) return;
    if (!state.failed && state.runningRoomId == runningRoomId) return;

    // ⚠️ **전 방의 메시지를 버린다.** 남겨두면 다른 방의 말이 섞여 보인다.
    state = ChatState(
      runningRoomId: runningRoomId,
      loading: true,
      opened: state.opened,
    );
    await _load(runningRoomId, limit: limit);
  }

  /// 스트림이 다시 붙었다. **목록과 커서를 비우고 다시 받는다.**
  ///
  /// 끊긴 동안 놓친 채팅 이벤트는 다시 오지 않는다(변경분이다). 그래서 목록을
  /// 다시 받아 맞추는 것이 유일한 방법이다.
  ///
  /// ⚠️ **들고 있던 것을 먼저 비우지 않는다.** 새 연결에서 이미 받은 이벤트가
  /// 있을 수 있는데, 목록 응답이 왔다는 이유로 버리면 그 사이의 말이 사라진다.
  /// 합치는 규칙이 중복을 걸러 준다.
  Future<void> reload() async {
    final runningRoomId = state.runningRoomId;
    if (runningRoomId == null || state.closed) return;

    state = state.copyWith(
      loading: state.messages.isEmpty,
      clearCursor: true,
      clearFailure: true,
    );
    await _load(runningRoomId, limit: _pageSize);
  }

  Future<void> _load(int runningRoomId, {required int limit}) async {
    try {
      final page = await _repo.history(runningRoomId, limit: limit);
      if (!_current(runningRoomId)) return;
      state = state.copyWith(
        messages: mergeChats(state.messages, page.items),
        nextCursor: page.nextCursor,
        clearCursor: page.nextCursor == null,
        loading: false,
        clearFailure: true,
      );
    } on ChatException catch (error) {
      if (!_current(runningRoomId)) return;
      _tookFailure(error.failure);
    }
  }

  /// 위로 긁었다. 이전 페이지를 이어 받는다.
  ///
  /// ⚠️ **긁는 동안 또 부르지 않는다.** 스크롤이 한 프레임에 여러 번 닿는데,
  /// 그대로 두면 같은 페이지를 여러 번 받는다.
  Future<void> loadMore() async {
    final runningRoomId = state.runningRoomId;
    final cursor = state.nextCursor;
    if (runningRoomId == null || cursor == null) return;
    if (state.loadingMore || state.closed) return;

    state = state.copyWith(loadingMore: true);
    try {
      final page = await _repo.history(
        runningRoomId,
        cursor: cursor,
        limit: _pageSize,
      );
      if (!_current(runningRoomId)) return;
      state = state.copyWith(
        messages: mergeChats(state.messages, page.items),
        nextCursor: page.nextCursor,
        clearCursor: page.nextCursor == null,
        loadingMore: false,
      );
    } on ChatException catch (error) {
      if (!_current(runningRoomId)) return;
      // ⚠️ **커서가 깨졌으면 첫 페이지부터 다시 받는다.** 같은 커서로 다시
      // 부르면 영원히 400이다.
      if (error.failure == ChatFailure.invalidCursor) {
        debugPrint('[chat] 커서를 버리고 처음부터 다시 받는다');
        state = state.copyWith(loadingMore: false, clearCursor: true);
        await reload();
        return;
      }
      state = state.copyWith(
        loadingMore: false,
        closed: error.failure == ChatFailure.closed || state.closed,
      );
    }
  }

  /// 한 건 보낸다. **공백만이면 아무 일도 없다** — 빈 버블을 만들지 않는다.
  Future<void> send(String text) async {
    final content = text.trim();
    final runningRoomId = state.runningRoomId;
    if (runningRoomId == null || !_sendable(content)) return;

    final pending = PendingChat(localId: --_localId, content: content);
    state = state.copyWith(pending: [...state.pending, pending]);
    await _post(runningRoomId, pending);
  }

  /// 실패한 한 건을 다시 보낸다. **사람이 눌러야 보낸다.**
  ///
  /// ⚠️ 자동으로 다시 보내지 않는다 — 응답을 못 받았어도 서버에는 저장됐을 수
  /// 있어서, 자동 재전송은 같은 말을 두 번 남긴다. 손으로 다시 보내도 중복될
  /// 수 있다는 것은 감수한다(연동 가이드 3-2).
  Future<void> resend(PendingChat pending) async {
    final runningRoomId = state.runningRoomId;
    if (runningRoomId == null || state.closed) return;

    state = state.copyWith(
      pending: [
        for (final one in state.pending)
          if (one.localId == pending.localId)
            PendingChat(localId: one.localId, content: one.content)
          else
            one,
      ],
    );
    await _post(runningRoomId, pending);
  }

  /// 실패한 한 건을 버린다. 버릴 길이 없으면 방을 떠날 때까지 남는다.
  void discard(PendingChat pending) {
    if (!_alive) return;
    state = state.copyWith(pending: _without(pending));
  }

  Future<void> _post(int runningRoomId, PendingChat pending) async {
    try {
      final sent = await _repo.send(runningRoomId, pending.content);
      if (!_current(runningRoomId)) return;
      // ⚠️ **보낸 것은 응답으로만 온다.** 내가 보낸 `ROOM_CHAT_SENT`는 나에게
      // 오지 않는다 — 여기서 넣지 않으면 내 말이 영영 안 보인다.
      state = state.copyWith(
        messages: mergeChats(state.messages, [sent]),
        pending: _without(pending),
      );
    } on ChatException catch (error) {
      if (!_current(runningRoomId)) return;
      debugPrint('[chat] 보내지 못했다 · ${error.failure.name}');
      state = state.copyWith(
        pending: [
          for (final one in state.pending)
            if (one.localId == pending.localId) one.asFailed else one,
        ],
        closed: error.failure == ChatFailure.closed || state.closed,
      );
    }
  }

  List<PendingChat> _without(PendingChat pending) => [
    for (final one in state.pending)
      if (one.localId != pending.localId) one,
  ];

  /// 내 메시지를 고친다.
  ///
  /// ⚠️ **같은 내용이면 부르지 않는다.** 서버는 그래도 수정으로 쳐서
  /// "수정됨"이 붙는다.
  Future<void> edit(int chatId, String text) async {
    final content = text.trim();
    final runningRoomId = state.runningRoomId;
    if (runningRoomId == null || state.closed || !_sendable(content)) return;

    final kept = _messageOf(chatId);
    if (kept == null || kept.isDeleted || kept.content == content) return;

    try {
      final edited = await _repo.edit(
        runningRoomId,
        chatId: chatId,
        content: content,
      );
      if (!_current(runningRoomId)) return;
      state = state.copyWith(messages: mergeChats(state.messages, [edited]));
    } on ChatException catch (error) {
      await _afterChangeFailed(runningRoomId, error.failure);
    }
  }

  /// 내 메시지를 지운다. **되돌릴 수 없다** — 묻는 것은 화면이 한다.
  Future<void> remove(int chatId) async {
    final runningRoomId = state.runningRoomId;
    if (runningRoomId == null || state.closed) return;

    final kept = _messageOf(chatId);
    if (kept == null || kept.isDeleted) return;

    try {
      await _repo.delete(runningRoomId, chatId);
      if (!_current(runningRoomId)) return;
      // ⚠️ **204라 응답에 메시지가 없다.** 부른 쪽이 비운 모습을 만든다.
      state = state.copyWith(
        messages: mergeChats(state.messages, [kept.asDeleted]),
      );
    } on ChatException catch (error) {
      await _afterChangeFailed(runningRoomId, error.failure);
    }
  }

  /// 수정·삭제가 실패했다.
  ///
  /// ## ⚠️ 404만으로 방에서 나가지 않는다
  ///
  /// 서버는 **방 밖·없는 메시지·이미 지운 것·남의 메시지**를 모두 404로 답하고
  /// 가르지 않는다. 그것만으로 방을 떠나면 멀쩡한 방에서 쫓겨난다. 먼저 목록을
  /// 다시 받아 화면을 맞춘다 — 정말 방 밖이면 그 조회가 다시 404를 준다.
  Future<void> _afterChangeFailed(
    int runningRoomId,
    ChatFailure failure,
  ) async {
    if (!_current(runningRoomId)) return;

    if (failure == ChatFailure.closed) {
      state = state.copyWith(closed: true);
      return;
    }
    debugPrint('[chat] 바꾸지 못했다 · ${failure.name} · 목록을 다시 받는다');
    await reload();
  }

  /// 들어온 변화 한 건. **목록·이벤트·내 응답이 모두 같은 규칙으로 합쳐진다.**
  void received(ChatChange change) {
    // 끊기 전에 줄 서 있던 것이 뒤늦게 올 수 있다.
    if (!_alive) return;

    // ⚠️ **다른 방 것은 버린다.** 한 스트림이 쓰이고 방을 옮기는 사이에 지난
    // 방의 채팅이 올라올 수 있다.
    final runningRoomId = state.runningRoomId;
    if (runningRoomId == null || change.chat.runningRoomId != runningRoomId) {
      return;
    }

    // 보고 있는 동안 온 것은 읽은 것이다. 수정·삭제는 **새 말이 아니라서**
    // 세지 않는다 — 본 적 없는 "삭제된 메시지"가 배지에 세어지면 들어가 봐도
    // 새 말이 없다.
    final arrived = change.countsAsUnread
        ? change.chat.copyWith(isRead: state.opened)
        : change.chat;

    state = state.copyWith(messages: mergeChats(state.messages, [arrived]));
  }

  /// 채팅 페이지가 떴다. **그 자리에서 전부 읽음이 된다.**
  ///
  /// ⚠️ 버려진 뒤에 불릴 수 있다 — 화면이 내려갈 때 `dispose`가 [close]를
  /// 부르는데, 그 순간 이미 아무도 보지 않아 버려져 있을 수 있다.
  void open() {
    if (!_alive) return;
    state = state.copyWith(
      opened: true,
      messages: [
        for (final one in state.messages)
          one.isRead ? one : one.copyWith(isRead: true),
      ],
    );
  }

  /// 채팅 페이지를 떠났다. 이제 들어오는 것은 센다.
  void close() {
    if (!_alive) return;
    state = state.copyWith(opened: false);
  }

  bool _sendable(String content) =>
      content.isNotEmpty && content.length <= maxLength && !state.closed;

  Chat? _messageOf(int chatId) {
    for (final one in state.messages) {
      if (one.chatId == chatId) return one;
    }
    return null;
  }

  /// 목록을 못 받았다. **갈래마다 할 일이 다르다.**
  void _tookFailure(ChatFailure failure) {
    if (failure == ChatFailure.closed) {
      // 러닝이 시작됐다. 되돌아오지 않으므로 "다시 시도"를 띄우지 않는다.
      state = state.copyWith(loading: false, closed: true);
      return;
    }

    state = state.copyWith(loading: false, failure: failure);

    if (failure == ChatFailure.notFound) {
      // ⚠️ **화면을 여기서 옮기지 않는다.** 활성 신청이 없으면 상태 조회가
      // 홈으로 이끈다 — 그 판단은 `matchRoomProvider` 한 곳에 있다.
      debugPrint('[chat] 이 방이 아니다 · 참여 상태를 다시 읽는다');
      unawaited(ref.read(userStatusProvider.notifier).refresh());
    }
  }

  /// `await` 뒤에 **아직 이 방인가, 그리고 아직 살아 있는가.**
  ///
  /// 느린 응답이 돌아오는 사이에 방이 바뀌면 앞 방의 메시지가 새 방의 상태에
  /// 써진다. 그리고 보는 사람이 없는 동안 붙으면 응답이 오기 전에 버려져,
  /// 쓰는 순간 터진다 — `_alive`를 먼저 보는 이유다.
  bool _current(int runningRoomId) =>
      _alive && state.runningRoomId == runningRoomId;
}
