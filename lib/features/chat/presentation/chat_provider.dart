import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/chat/data/fake_chat_repository.dart';
import 'package:runiverse/features/chat/domain/chat_message.dart';
import 'package:runiverse/features/chat/domain/chat_repository.dart';

/// 지금 끼워 둔 구현은 **가짜 하나뿐이다.** 서버가 정해지면 이 한 줄만 바뀐다.
final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => FakeChatRepository(),
);

/// 한 방의 채팅.
class ChatState {
  const ChatState({
    this.messages = const [],
    this.loading = false,
    this.failed = false,
    this.seed,
    this.opened = false,
  });

  final List<ChatMessage> messages;
  final bool loading;
  final bool failed;

  /// 어느 방에 붙어 있는가. `null`이면 아직 안 붙었다.
  final ChatRoomSeed? seed;

  /// 채팅 페이지가 떠 있는가. **들어온 메시지를 셀지 말지를 이것이 가른다.**
  final bool opened;

  /// 배지의 숫자. 보고 있지 않은 동안 쌓인 것만 센다.
  int get unread => messages.where((message) => !message.isRead).length;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? loading,
    bool? failed,
    ChatRoomSeed? seed,
    bool? opened,
  }) => ChatState(
    messages: messages ?? this.messages,
    loading: loading ?? this.loading,
    failed: failed ?? this.failed,
    seed: seed ?? this.seed,
    opened: opened ?? this.opened,
  );
}

final chatProvider = NotifierProvider<ChatController, ChatState>(
  ChatController.new,
  // ⚠️ **기본값이 `false`다.** 코드생성이 아닌 `NotifierProvider`는 auto-dispose가
  // 아니다(riverpod 3.4.2 `src/providers/notifier/orphan.dart`의
  // `super.isAutoDispose = false`). 안 켜면 아래 `ref.onDispose`가 **제품 경로에서
  // 한 번도 돌지 않는다** — 테스트가 `container.dispose()`를 손으로 불러 통과할
  // 뿐이고, 서버가 붙는 날 방이 끝나도 연결이 열려 있게 된다.
  isAutoDispose: true,
);

/// 대기방 채팅을 들고 있는다.
///
/// ## ⚠️ `matchRoomProvider`를 듣지 않는다
///
/// 서로 들으면 Riverpod이 `CircularDependencyError`로 막는다. 방 번호와 파티원
/// 명단은 **화면이 [connect]로 넣어 준다.** 화면은 두 provider를 각각 watch해서
/// 합친다.
///
/// 채팅은 방에 묶인 것이라 `keepAlive`를 걸지 않는다 — 방을 떠나면 함께 사라진다.
class ChatController extends Notifier<ChatState> {
  /// ⚠️ **미리 붙잡아 두지 않는다.** `onDispose` 클로저가 저장소를 건드리지
  /// 않으므로 필드로 들 이유가 없고, `late final`로 들면 **다시 `build`될 때**
  /// `LateInitializationError`가 난다 — auto-dispose라 그 일이 실제로 생긴다.
  ChatRepository get _repo => ref.read(chatRepositoryProvider);

  StreamSubscription<ChatMessage>? _subscription;

  /// 아직 살아 있는가. `await` 뒤에 상태를 쓰기 전에 본다.
  var _alive = false;

  @override
  ChatState build() {
    // 다시 build될 수 있으므로 **여기서 되살린다.** 한 번만 세우면 버려졌다
    // 살아난 provider가 영영 죽은 것으로 남는다.
    _alive = true;
    ref.onDispose(() {
      _alive = false;
      unawaited(_subscription?.cancel());
      _subscription = null;
    });
    return const ChatState();
  }

  /// 방에 붙는다. **같은 방이면 다시 싣지 않는다** — 화면이 다시 그려질 때마다
  /// 과거 메시지를 또 불러오면 목록이 깜빡이고 서버를 두 번 때린다.
  ///
  /// 실패한 뒤에는 같은 방이라도 다시 싣는다. 그래야 "다시 시도"가 일을 한다.
  Future<void> connect(ChatRoomSeed seed) async {
    if (!state.failed && state.seed?.runningRoomId == seed.runningRoomId) {
      return;
    }

    // ⚠️ **상태를 먼저 세운다.** 구독 취소를 먼저 await하면 `null`이어도 한 번
    // 양보하므로, 부른 쪽이 loading을 못 보고 빈 화면을 그린다.
    final previous = _subscription;
    _subscription = null;
    // ⚠️ **전 방의 메시지를 버린다.** 남겨두면 다른 방의 말이 섞여 보인다.
    state = ChatState(seed: seed, loading: true, opened: state.opened);
    await previous?.cancel();

    if (!_current(seed)) return;

    _subscription = _repo.incoming(seed).listen(_received);
    try {
      final history = await _repo.history(seed);
      if (!_current(seed)) return;
      // 싣는 동안 들어온 것은 과거 뒤에 붙인다 — 시간 순이 유지된다.
      state = state.copyWith(
        messages: [...history, ...state.messages],
        loading: false,
      );
    } on ChatException {
      if (!_current(seed)) return;
      state = state.copyWith(loading: false, failed: true);
    }
  }

  /// `await` 뒤에 **아직 이 방인가, 그리고 아직 살아 있는가.**
  ///
  /// ## ⚠️ 둘 다 봐야 한다
  ///
  /// 느린 `history`가 돌아오는 사이에 방이 바뀌면 **앞 방의 메시지가 새 방의
  /// 상태에 써진다** — 실패도 같아서 앞 방의 실패가 새 방을 `failed`로 만든다.
  /// 지금 가짜는 마이크로태스크로 끝나 닿지 않지만, `history`가 네트워크가 되는
  /// 순간 방을 빠르게 옮기면 재현된다.
  ///
  /// 그리고 **보는 사람이 없는 동안** 붙으면(혼자인 방은 채팅 버튼이 숨어
  /// 아무도 watch하지 않는다) 응답이 오기 전에 버려져, 쓰는 순간 터진다.
  /// `_alive`를 먼저 보는 이유는 버려진 뒤에는 `state`도 읽을 수 없기 때문이다.
  bool _current(ChatRoomSeed seed) =>
      _alive && state.seed?.runningRoomId == seed.runningRoomId;

  /// 채팅 페이지가 떴다. **그 자리에서 전부 읽음이 된다.**
  ///
  /// ⚠️ 버려진 뒤에 불릴 수 있다 — 화면이 내려갈 때 `dispose`가 [close]를
  /// 부르는데, 그 순간 이미 아무도 보지 않아 버려져 있을 수 있다.
  void open() {
    if (!_alive) return;
    state = state.copyWith(
      opened: true,
      messages: [
        for (final message in state.messages) message.copyWith(isRead: true),
      ],
    );
  }

  /// 채팅 페이지를 떠났다. 이제 들어오는 것은 센다.
  void close() {
    if (!_alive) return;
    state = state.copyWith(opened: false);
  }

  /// 한 건 보낸다. **공백만이면 아무 일도 없다** — 빈 버블을 만들지 않는다.
  Future<void> send(String text) async {
    final trimmed = text.trim();
    final seed = state.seed;
    if (trimmed.isEmpty || seed == null) return;

    try {
      await _repo.send(seed, trimmed);
    } on ChatException {
      // ⚠️ 전송 실패 UI는 이번 범위가 아니다(설계 8절) — 서버가 없으면 실패
      // 조건을 정할 수 없다. 조용히 삼키되 로그는 남긴다.
      debugPrint('[chat] 보내지 못했다 · 방 ${seed.runningRoomId}');
    }
  }

  /// 들어온 한 건. **보고 있는 동안 온 것은 읽은 것으로 넣는다.**
  void _received(ChatMessage message) {
    // 끊기 전에 줄 서 있던 것이 뒤늦게 올 수 있다.
    if (!_alive) return;
    final one = state.opened ? message.copyWith(isRead: true) : message;
    state = state.copyWith(messages: [...state.messages, one]);
  }
}
