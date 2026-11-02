import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/app_update/presentation/app_update_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/notification/data/http_notification_repository.dart';
import 'package:runiverse/features/notification/data/sse_app_stream.dart';
import 'package:runiverse/features/notification/domain/app_notification.dart';
import 'package:runiverse/features/notification/domain/app_stream.dart';
import 'package:runiverse/features/notification/domain/notification_repository.dart';

final appStreamProvider = Provider<AppStream>(
  (ref) => SseAppStream(
    ref.watch(tokenStoreProvider),
    ref.watch(tokenRefresherProvider),
  ),
);

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => HttpNotificationRepository(
    ref.watch(dioProvider),
    ref.watch(tokenStoreProvider),
    ref.watch(tokenRefresherProvider),
  ),
);

/// 알림함과 배지가 보는 상태.
class NotificationState {
  const NotificationState({
    this.items = const [],
    this.unreadCount = 0,
    this.nextCursor,
    this.loading = false,
    this.connected = false,
    this.updateRequired = false,
    this.failure,
  });

  /// 최신 순. 서버가 준 순서 그대로이고, 실시간으로 온 것만 맨 위에 붙는다.
  final List<AppNotification> items;

  /// 배지의 바탕값. **숫자로 그리지 않는다** — [hasUnreadProvider]를 쓴다.
  final int unreadCount;

  final String? nextCursor;
  final bool loading;

  /// 앱 스트림이 붙어 있는가.
  final bool connected;

  /// 구버전 앱이라 스트림이 거절됐다. 화면이 업데이트를 안내한다.
  final bool updateRequired;

  final NotificationFailure? failure;

  /// 더 받을 페이지가 있는가. **`items` 개수로 판단하지 않는다.**
  bool get hasMore => nextCursor != null;

  /// 화면에 그릴 알림. **할 일이 끝난 것은 뺀다.**
  ///
  /// ⚠️ [items]를 그대로 두는 이유는 **방 단위 갱신과 중복 제거가 그것을
  /// 봐야** 하기 때문이다. 같은 방의 알림을 함께 바꿀 때 숨긴 줄도 함께
  /// 바뀌어야 하고, 이미 받은 `notificationId`를 또 받으면 걸러내야 한다.
  List<AppNotification> get visible => [
    for (final one in items)
      if (!one.isSettled) one,
  ];

  NotificationState copyWith({
    List<AppNotification>? items,
    int? unreadCount,
    String? nextCursor,
    bool? loading,
    bool? connected,
    bool? updateRequired,
    NotificationFailure? failure,
  }) => NotificationState(
    items: items ?? this.items,
    unreadCount: unreadCount ?? this.unreadCount,
    // ⚠️ `??`를 쓰지 않는다. 마지막 페이지에서 **지울** 수 있어야 한다.
    nextCursor: nextCursor,
    loading: loading ?? this.loading,
    connected: connected ?? this.connected,
    updateRequired: updateRequired ?? this.updateRequired,
    // ⚠️ 같은 이유로 실패도 지울 수 있어야 한다.
    failure: failure,
  );
}

final notificationProvider =
    NotifierProvider<NotificationController, NotificationState>(
      NotificationController.new,
    );

/// 배지를 **숫자가 아니라 있다/없다로** 본다.
///
/// 서버가 깨진 행을 건너뛰어 `unreadCount`가 목록보다 클 수 있다고 연동 가이드가
/// 직접 말한다. 어긋난 숫자는 틀린 숫자지만, 점은 "있다/없다"만 말해서 틀릴
/// 자리가 없다.
final hasUnreadProvider = Provider<bool>(
  (ref) => ref.watch(notificationProvider.select((s) => s.unreadCount > 0)),
);

/// 알림 목록과 배지를 옮긴다.
///
/// ## ⚠️ 순서가 규칙이다 — 스트림 먼저, 목록 나중
///
/// 목록을 먼저 받으면 **목록 응답과 스트림 연결 사이에 생긴 알림**을 실시간으로
/// 도 못 받고 목록에도 없다. 영영 사라진다.
///
/// 그래서 스트림을 먼저 열고, 그 사이에 오는 것은 [_buffer]에 담아 둔다. 목록이
/// 오면 `notificationId`로 대조해 **목록에 없는 것만** 더하고, 배지는 응답의
/// `unreadCount`에 그 수만 보탠다.
class NotificationController extends Notifier<NotificationState> {
  StreamSubscription<AppNotification>? _subscription;

  /// 목록 응답을 기다리는 동안 받아 둔 알림. 키는 `notificationId`다.
  ///
  /// ⚠️ **조회가 실패해도 비우지 않는다.** 비우면 그동안 받은 알림이 사라지고,
  /// 재연결로도 다시 오지 않는다(서버가 놓친 이벤트를 재생하지 않는다).
  final _buffer = <int, AppNotification>{};

  /// 지금 버퍼 모드인가. 목록을 기다리는 중이라는 뜻이다.
  var _buffering = false;

  var _loadingMore = false;

  final _backoff = AppStreamBackoff();
  Timer? _retry;

  static const _limit = 20;

  /// 다시 붙기를 예약해 뒀는가. **테스트가 읽는다** — "다시 붙지 않는다"를
  /// 눈으로 볼 방법이 없다(타이머가 돌기 전에 테스트가 끝난다).
  bool get retryPending => _retry?.isActive ?? false;

  /// ⚠️ **build에서 한 번 붙잡는다.** Riverpod 3는 `onDispose` 안에서
  /// `ref.read`를 막는다(생명주기 콜백에서 다른 provider를 건드릴 수 없다).
  /// 뒷정리할 때 읽으려 하면 단정문에서 죽는다.
  late final AppStream _stream;

  @override
  NotificationState build() {
    _stream = ref.read(appStreamProvider);
    ref.onDispose(() {
      _retry?.cancel();
      unawaited(_subscription?.cancel());
      unawaited(_stream.close());
    });
    return const NotificationState();
  }

  NotificationRepository get _repo => ref.read(notificationRepositoryProvider);

  /// 앱에 들어왔다. **스트림을 열고 그다음 목록을 받는다.**
  Future<void> start() async {
    _connect();
    await _loadFirstPage();
  }

  /// 포그라운드로 돌아왔다.
  ///
  /// ⚠️ **연결 여부와 무관하게 목록을 다시 받는다.** 스트림이 유지된 상태에서도
  /// 이벤트를 놓칠 수 있다(모바일 백그라운드·서버측 문제). 연결이 끊겨 있으면
  /// 먼저 다시 붙는다.
  Future<void> resume() async {
    if (!state.connected) _connect();
    await refresh();
  }

  /// 첫 페이지부터 다시 받는다.
  ///
  /// ⚠️ **뒤쪽 페이지와 커서를 버린다.** 이어 붙이면 그사이 지워진 알림이
  /// 남고, 새 커서와 옛 커서가 섞여 같은 페이지를 두 번 받는다.
  Future<void> refresh() => _loadFirstPage();

  void _connect() {
    _retry?.cancel();
    unawaited(_subscription?.cancel());

    // ⚠️ **연결보다 먼저 버퍼 모드로 바꾼다.** 순서가 뒤집히면 목록을 기다리는
    // 동안 온 알림이 화면에 바로 들어가 두 번 세어진다.
    _buffering = true;

    _subscription = _stream.connect().listen(
      _onEvent,
      onError: _onStreamError,
      onDone: () {
        if (!state.updateRequired) _scheduleRetry();
      },
    );
    state = state.copyWith(
      connected: true,
      updateRequired: false,
      nextCursor: state.nextCursor,
      failure: state.failure,
    );
  }

  void _onStreamError(Object error) {
    final failure = error is AppStreamException
        ? error.failure
        : AppStreamFailure.network;

    // ⚠️ **구버전이면 다시 붙지 않는다.** 같은 403이 돌아올 뿐이고, 화면이
    // 업데이트를 안내한다.
    if (failure == AppStreamFailure.updateRequired) {
      state = state.copyWith(
        connected: false,
        updateRequired: true,
        nextCursor: state.nextCursor,
        failure: state.failure,
      );
      // ⚠️ **상태만 세우면 아무도 읽지 않는다.** 게이트를 직접 깨운다 —
      // 매칭 스트림이 같은 일을 한다(`match_room_provider.dart`). 다시 붙어
      // 봐야 같은 403이고, 그동안 사용자는 왜 안 되는지 모른다.
      ref.read(appUpdateProvider.notifier).markRequired();
      return;
    }

    debugPrint('[notification] 앱 스트림이 끊겼다 · $failure');
    // ⚠️ **커서와 실패를 들고 간다.** `copyWith`가 둘을 지우도록 돼 있어
    // (지울 수 있어야 한다), 안 넘기면 **서버가 30분마다 정상으로 끊을 때마다
    // 목록이 거기서 끝난다.**
    state = state.copyWith(
      connected: false,
      nextCursor: state.nextCursor,
      failure: state.failure,
    );
    _scheduleRetry();
  }

  void _scheduleRetry() {
    _retry?.cancel();
    final wait = _backoff.next();
    debugPrint('[notification] ${wait.inSeconds}초 뒤에 다시 붙는다');
    _retry = Timer(wait, () async {
      _connect();
      await _loadFirstPage();
    });
  }

  void _onEvent(AppNotification notification) {
    _backoff.reset();

    // 목록을 기다리는 중이다. 화면에 바로 넣지 않는다.
    if (_buffering) {
      _buffer[notification.notificationId] = notification;
      return;
    }

    // ⚠️ **이미 있으면 무시한다.** 재연결이나 중복 전송으로 같은 알림이 두 번
    // 올 수 있고, 그때 배지만 올라가면 목록과 어긋난다.
    if (state.items.any(
      (n) => n.notificationId == notification.notificationId,
    )) {
      return;
    }

    state = state.copyWith(
      items: [notification, ...state.items],
      unreadCount: state.unreadCount + 1,
      // ⚠️ **커서와 실패를 함께 들고 간다.** `copyWith`가 둘을 지우도록 돼
      // 있어(지울 수 있어야 한다), 안 넘기면 **새 알림 하나가** 화면의 오류
      // 안내를 치우고 **목록을 그 자리에서 끝낸다** — 더 못 불러오고 옛 알림에
      // 닿을 길이 사라진다.
      nextCursor: state.nextCursor,
      failure: state.failure,
    );
  }

  Future<void> _loadFirstPage() async {
    _buffering = true;
    state = state.copyWith(loading: true, nextCursor: state.nextCursor);

    try {
      final page = await _repo.list(limit: _limit);

      // 버퍼에서 **목록에 없는 것만** 맨 위에 더한다.
      final known = {for (final one in page.items) one.notificationId};
      final fresh = [
        for (final one in _buffer.values)
          if (!known.contains(one.notificationId)) one,
      ]..sort((a, b) => b.notificationId.compareTo(a.notificationId));

      _buffer.clear();
      _buffering = false;

      state = NotificationState(
        items: [...fresh, ...page.items],
        // ⚠️ 목록이 센 것 + 버퍼에서 **새로 더한 것만**. 목록에 이미 있는
        // 알림을 다시 더하면 배지가 목록보다 커진다.
        unreadCount: page.unreadCount + fresh.length,
        nextCursor: page.nextCursor,
        connected: state.connected,
        updateRequired: state.updateRequired,
      );
    } on NotificationException catch (error) {
      // ⚠️ **버퍼를 지우지 않고, 버퍼 모드도 내리지 않는다.**
      //
      // 지우면 그동안 받은 알림이 사라진다(서버가 놓친 이벤트를 재생하지
      // 않는다). 모드를 내리면 더 나쁘다 — 그 뒤에 온 알림이 `items`에 바로
      // 들어가고, 재시도의 `_loadFirstPage`가 `items`를 통째로 갈아끼우면서
      // **그것까지 함께 버린다.** 서버와 맞춰 보기 전까지는 버퍼가 유일하게
      // 안전한 자리다.
      state = state.copyWith(
        loading: false,
        nextCursor: state.nextCursor,
        failure: error.failure,
      );
      // ⚠️ **다시 시도해야 버퍼 모드에서 나올 수 있다.** 안 하면 그 뒤 모든
      // 알림이 버퍼로 들어가고 배지가 영영 안 움직인다 — 초대받은 사람에게
      // 유일한 통로가 조용히 막힌다(포그라운드 복귀 전까지).
      _scheduleRetry();
    }
  }

  /// 보이는 줄이 없는데 받을 페이지가 남았으면 더 받는다.
  ///
  /// ## ⚠️ 끝난 알림을 걸러내면 **한 페이지가 통째로 빌 수 있다**
  ///
  /// 20개를 받아 전부 처리된 건이면 화면은 "아직 알림이 없어요"가 된다 —
  /// 실제로는 다음 페이지에 읽을 것이 있는데도. 스크롤이 닿을 자리도 없어서
  /// [loadMore]가 불릴 일이 없다.
  Future<void> fillVisible() async {
    // 상한을 둔다. 30일치가 전부 처리된 건이면 끝까지 긁게 되는데, 그동안
    // 화면은 비어 있고 서버는 같은 수의 요청을 받는다.
    for (var page = 0; page < _fillPages; page++) {
      if (state.visible.isNotEmpty || !state.hasMore) return;
      final before = state.nextCursor;
      await loadMore();
      // 더 나아가지 못했다(실패했거나 같은 자리다). 무한히 돌지 않는다.
      if (state.nextCursor == before) return;
    }
  }

  /// [fillVisible]이 더 받아 보는 페이지 수.
  static const _fillPages = 3;

  /// 스크롤이 끝에 닿았다.
  Future<void> loadMore() async {
    final cursor = state.nextCursor;
    // ⚠️ **`nextCursor`가 `null`일 때만 끝이다.** `items`가 비어 있어도 다음
    // 페이지가 있을 수 있다 — 서버가 깨진 행을 건너뛴다.
    if (cursor == null || _loadingMore) return;
    _loadingMore = true;

    try {
      final page = await _repo.list(cursor: cursor, limit: _limit);
      final known = {for (final one in state.items) one.notificationId};
      state = state.copyWith(
        items: [
          ...state.items,
          for (final one in page.items)
            if (!known.contains(one.notificationId)) one,
        ],
        nextCursor: page.nextCursor,
      );
    } on NotificationException catch (error) {
      state = state.copyWith(
        nextCursor: state.nextCursor,
        failure: error.failure,
      );
    } finally {
      _loadingMore = false;
    }
  }

  /// 알림함을 열었다. **목록을 받은 뒤에 부른다.**
  Future<void> markAllRead() async {
    if (state.unreadCount == 0) return;
    try {
      await _repo.readAll();
      // ⚠️ **`isRead`는 그대로 둔다.** 화면의 새 알림 강조가 남는 것은 의도된
      // 동작이다 — 화면은 조회 당시 안 읽은 것을 강조하고, 서버의 읽음 결과는
      // 배지에만 반영한다. 목록을 받은 뒤 이 호출 전에 도착한 알림까지 서버가
      // 함께 읽음 처리하므로 0으로 둔다.
      state = state.copyWith(unreadCount: 0, nextCursor: state.nextCursor);
    } on NotificationException catch (error) {
      // 못 내렸으면 배지를 그대로 둔다. 0으로 두면 서버와 어긋난 채 남는다.
      state = state.copyWith(
        nextCursor: state.nextCursor,
        failure: error.failure,
      );
    }
  }

  /// 한 방의 초대 알림을 **모두** 같은 상태로 바꾼다.
  ///
  /// ## ⚠️ 같은 방의 알림이 여럿일 수 있다
  ///
  /// A와 C가 각각 나를 같은 방에 초대하면 알림은 둘이고 `actor`도 다르지만
  /// **초대는 하나다.** 하나를 수락·거절하면 서버가 그 방의 초대를 함께
  /// 바꾸므로, 화면도 함께 바꿔야 한다. 받아 둔 **모든 페이지**를 훑는다 —
  /// 첫 페이지만 고치면 스크롤하면 낡은 버튼이 나온다.
  void updateRoom(int runningRoomId, InvitationStatus status) {
    state = state.copyWith(
      items: [
        for (final one in state.items)
          if (one.invitation?.runningRoomId == runningRoomId)
            one.withInvitation(one.invitation!.withStatus(status))
          else
            one,
      ],
      nextCursor: state.nextCursor,
    );
  }

  /// 로그아웃. 연결을 끊고 들고 있던 것을 버린다.
  Future<void> signOut() async {
    _retry?.cancel();
    await _subscription?.cancel();
    _subscription = null;
    await _stream.close();
    _buffer.clear();
    _buffering = false;
    state = const NotificationState();
  }
}
