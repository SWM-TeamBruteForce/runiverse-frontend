import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/matching/data/sse_match_stream.dart';
import 'package:runiverse/features/matching/domain/match_event.dart';
import 'package:runiverse/features/matching/domain/match_failure.dart';
import 'package:runiverse/features/matching/domain/match_stream.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';
import 'package:runiverse/features/matching/domain/run_launch.dart';
import 'package:runiverse/features/matching/presentation/match_register_provider.dart';
import 'package:runiverse/features/session/domain/user_status.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

final matchStreamProvider = Provider<MatchStream>(
  (ref) => SseMatchStream(
    ref.watch(dioProvider),
    ref.watch(tokenStoreProvider),
    ref.watch(authRepositoryProvider),
  ),
);

/// 지금 속한 매칭방.
class MatchRoomState {
  const MatchRoomState({
    this.room,
    this.connected = false,
    this.failure,
    this.justMatched = false,
    this.ready,
    this.launchAt,
  });

  /// 마지막으로 받은 방 정보. `null`이면 속한 방이 없다.
  final RoomInfo? room;

  final bool connected;

  final MatchStreamFailure? failure;

  /// 방금 확정됐는가. **연출을 한 번만 띄우기 위한 것이다.**
  ///
  /// ⚠️ `status == matched`로는 알 수 없다. 재연결 스냅샷도 같은 값을 실어
  /// 와서, 앱을 껐다 켤 때마다 다시 축하하게 된다.
  final bool justMatched;

  /// 마지막으로 받은 시작 통지.
  final RunningReady? ready;

  /// 언제 쏘는가.
  ///
  /// ⚠️ **통지를 받은 순간 + `startsInMs`로 잡는다.** 서버가 시각이 아니라
  /// 간격을 주는 이유가 이것이다 — 기기 시계가 어긋나 있어도 맞는다.
  ///
  /// 통지가 없으면 방의 `scheduledStartAt`을 쓴다. SSE가 끊겼거나 앱이
  /// 백그라운드였으면 이벤트가 오지 않는데, 그렇다고 출발을 포기하지 않는다.
  final DateTime? launchAt;

  /// 발사 시각을 들고 있는 계산기. 들고 있을 방이 없으면 `null`이다.
  RunLaunch? get launch {
    final at = launchAt ?? room?.scheduledStartAt;
    return at == null ? null : RunLaunch(at);
  }

  MatchRoomState copyWith({
    RoomInfo? room,
    bool? connected,
    MatchStreamFailure? failure,
    bool? justMatched,
    RunningReady? ready,
    DateTime? launchAt,
  }) => MatchRoomState(
    room: room ?? this.room,
    connected: connected ?? this.connected,
    // ⚠️ `??`를 쓰지 않는다. 실패를 **지울** 수 있어야 한다.
    failure: failure,
    justMatched: justMatched ?? this.justMatched,
    ready: ready ?? this.ready,
    launchAt: launchAt ?? this.launchAt,
  );
}

final matchRoomProvider = NotifierProvider<MatchRoomController, MatchRoomState>(
  MatchRoomController.new,
);

/// 매칭 스트림을 들고 있는다.
///
/// ## ⚠️ 화면이 소유하지 않는다
///
/// 홈을 벗어나도 스트림은 살아 있어야 한다. 대기방을 보다가 기록 탭에 다녀오는
/// 사이에 확정 통지가 오는데, 화면에 묶어두면 그걸 놓친다.
///
/// ## 붙을지는 유저 상태가 정한다
///
/// 활성 신청이 없는데 열면 서버가 404로 거절한다. 그래서 [userStatusProvider]를
/// 지켜보다가 대기·확정일 때만 붙는다 — 진입과 포그라운드 복귀에서 그 값이
/// 갱신되므로, 다시 붙는 일도 여기서 저절로 일어난다.
class MatchRoomController extends Notifier<MatchRoomState> {
  StreamSubscription<MatchEvent>? _subscription;

  /// 붙을 때 잡아둔다.
  ///
  /// ⚠️ **`_stop()`에서 `ref.read`를 부르면 안 된다.** provider가 버려진 뒤에도
  /// 닫아야 하는데, 그때는 `ref`가 죽어 있어 `UnmountedRefException`이 난다.
  MatchStream? _stream;

  /// 예약된 재연결. 없으면 `null`.
  Timer? _retry;

  /// 연달아 실패한 횟수. 붙는 데 성공하면 0으로 돌아간다.
  int _retryStep = 0;

  /// 간격 상한을 32초로 둔다(`1 << 5`). 모집 대기는 몇 시간짜리라 더 벌리면
  /// 확정 통지를 받기까지 그만큼 늦어진다.
  static const _maxRetryStep = 5;

  @override
  MatchRoomState build() {
    // ⚠️ Riverpod 3은 기본이 auto-dispose다. 보는 화면이 잠깐 없어지는 순간
    // 스트림이 통째로 닫히고, 그사이에 오는 확정 통지를 놓친다.
    ref.keepAlive();
    // ⚠️ `fireImmediately`가 없으면 **이미 지나간 상태를 영영 못 본다.**
    // 상태는 스플래시가 읽고, 이 provider는 그 뒤 `AppShell`이 만들어질 때
    // 생긴다 — 변화만 들으면 앱을 켤 때마다 대기 중인 매칭에 안 붙는다.
    ref.listen(
      userStatusProvider,
      (_, status) => _syncWith(status),
      fireImmediately: true,
    );
    ref.onDispose(() {
      // 타이머는 provider보다 오래 산다. 두면 버려진 뒤에 깨어나 `ref`를 만진다.
      _cancelRetry();
      unawaited(_stop());
    });
    return const MatchRoomState();
  }

  /// 서버가 아는 상태에 맞춰 붙거나 끊는다.
  void _syncWith(UserStatus? status) {
    // ⚠️ 못 읽었으면 아무것도 하지 않는다. 상태 조회가 한 번 실패했다고 살아
    // 있는 연결을 버리면 그사이에 오는 확정 통지를 놓친다.
    if (status == null) return;

    final wants = switch (status) {
      UserStatusWaiting() => true,
      // 솔로는 SSE를 쓰지 않는다. 맞출 상대가 없어 모집 단계 자체가 없다.
      UserStatusReady(:final isSolo) => !isSolo,
      // 러닝이 시작되면 WebSocket이 맡는다. 스트림은 닫혀 있어야 한다.
      UserStatusRunning() || UserStatusIdle() => false,
    };

    // ⚠️ `fireImmediately`로 **`build()` 도중에** 들어올 수 있다. 그때 state를
    // 건드리면 Riverpod이 막는다. 한 틱 미룬다 — [connect]가 멱등이라 늦어도
    // 두 번 붙지 않는다.
    Future.microtask(() {
      if (!ref.mounted) return;
      if (wants) {
        connect();
      } else {
        unawaited(disconnect());
      }
    });
  }

  /// 붙는다. **이미 붙어 있으면 아무것도 하지 않는다.**
  ///
  /// 신청 응답을 받은 직후에도 부른다 — 유저 상태를 다시 읽기 전에 붙어야
  /// 모집 중 인원 변동을 처음부터 받는다.
  void connect() {
    if (_subscription != null) return;

    final stream = ref.read(matchStreamProvider);
    _stream = stream;

    state = state.copyWith(connected: true, failure: null);
    _subscription = stream.connect().listen(
      _onEvent,
      onError: (Object error) {
        final failure = error is MatchStreamException
            ? error.failure
            : MatchStreamFailure.unknown;
        debugPrint('[match] 스트림이 끊겼다 · ${failure.name}');
        unawaited(_stop());
        // ⚠️ 방 정보는 지우지 않는다. 끊겼다고 대기방을 비우면 잠깐의
        // 네트워크 끊김에 사람이 홈으로 튕긴다.
        state = state.copyWith(connected: false, failure: failure);
        // 다시 로그인해야 하는 것은 기다린다고 풀리지 않는다.
        if (failure != MatchStreamFailure.sessionExpired) _scheduleRetry();
      },
      onDone: () {
        // ⚠️ **서버가 정상으로 닫아도 여기로 온다.** `match-stream.timeout`이
        // 30분이라 몇 시간짜리 모집 대기는 반드시 한 번 이상 끊긴다 — 오류가
        // 아니므로 `onError`가 아니라 이쪽으로 떨어진다.
        debugPrint('[match] 스트림이 닫혔다');
        unawaited(_stop());
        // ⚠️ **`failure`를 그대로 넘긴다.** `copyWith`는 실패를 지울 수 있도록
        // `??`를 쓰지 않는데, 끊김은 `onError` 직후에 `onDone`이 따라온다 —
        // 여기서 빼먹으면 방금 기록한 이유가 곧바로 지워진다.
        state = state.copyWith(connected: false, failure: state.failure);
        _scheduleRetry();
      },
    );
  }

  /// 끊긴 뒤 다시 붙을 준비를 한다.
  ///
  /// ## 바로 붙지 않고 상태부터 다시 읽는다
  ///
  /// 연동 가이드가 정한 순서다 — *"예상치 못하게 연결이 종료되면 상태 조회
  /// API로 현재 상태를 확인한 후 필요한 연결을 복구"*. 끊겨 있는 동안 다른
  /// 기기에서 취소했거나 방이 닫혔을 수 있는데, 그대로 다시 열면 서버가
  /// 404로 거절한다. **무엇이 진행 중인지는 언제나 `/users/me/status`가 정한다.**
  ///
  /// 그래서 재연결 판단이 [_syncWith] 한 곳에 그대로 남는다. 여기는 그것을
  /// 다시 부를 계기만 만든다.
  void _scheduleRetry() {
    // 이미 예약돼 있으면 둔다. `_stop()`과 `onDone`이 겹쳐 두 번 들어올 수 있다.
    if (_retry != null) return;

    // ⚠️ **첫 번은 기다리지 않는다.** 침묵으로 끊김을 판정한 시점에 이미 30초를
    // 쓴 뒤라, 여기서 더 재는 시간은 그대로 갱신 지연에 더해진다. 진짜로 망가진
    // 경우에만 2·4·8초로 간격이 벌어진다.
    final wait = Duration(seconds: _retryStep == 0 ? 0 : 1 << _retryStep);
    if (_retryStep < _maxRetryStep) _retryStep++;

    _retry = Timer(wait, () async {
      _retry = null;
      if (!ref.mounted) return;
      final status = await ref.read(userStatusProvider.notifier).refresh();
      if (!ref.mounted) return;
      // 못 읽었으면 붙을지 알 수 없다. 다음 기회를 만든다.
      if (status == null) {
        _scheduleRetry();
        return;
      }
      _syncWith(status);
    });
  }

  /// 예약된 재연결을 버린다. **의도한 종료가 되살아나지 않게 한다.**
  void _cancelRetry() {
    _retry?.cancel();
    _retry = null;
    _retryStep = 0;
  }

  void _onEvent(MatchEvent event) {
    // 이벤트가 왔다는 것은 연결이 실제로 살아 있다는 뜻이다. 다음에 끊기면
    // 다시 처음 간격부터 시작한다 — 30분마다 닫히는 연결에 간격이 누적되면
    // 하루 종일 기다리는 동안 재연결이 점점 늦어진다.
    _retryStep = 0;
    switch (event) {
      // ⚠️ **두 이벤트를 같게 다룬다.** 서버 코드가 정본이다 — 연결하면
      // `MATCH_ROOM_UPDATED`가 스냅샷으로 오고(`OpenMatchStreamHandler`),
      // `MATCH_STARTED`는 **모집 마감에 단 한 번** 나온다
      // (`CloseMatchingHandler`, 인원과 무관하게 1인도 확정이다).
      //
      // 연동 가이드는 "SSE에 연결하면 서버가 `MATCH_STARTED`를 전송한다"고
      // 적었지만 실제 동작은 위와 같다. 어느 쪽이든 **이벤트 종류로 확정을
      // 판정하지 않는다** — 그 판정은 [_applyRoom]이 상태 전이로 한다.
      case MatchStarted(:final room) || MatchRoomUpdated(:final room):
        _applyRoom(room);
      case RunningReady():
        // ⚠️ 받은 순간을 기준으로 발사 시각을 잡는다. `scheduledStartAt`을
        // 그대로 쓰면 기기 시계가 어긋난 만큼 출발이 어긋난다.
        state = state.copyWith(
          ready: event,
          launchAt: DateTime.now().add(
            Duration(milliseconds: event.startsInMs),
          ),
          failure: null,
        );
    }
  }

  /// 방 정보를 들인다. **어느 이벤트로 왔든 같게 다룬다.**
  ///
  /// 확정 판정은 이벤트 종류가 아니라 **상태 전이**로 한다 — 모집 중이던 방이
  /// 확정으로 넘어간 그 순간만 연출을 띄운다. 재연결로 같은 `MATCHED`가 다시
  /// 와도 전이가 아니므로 조용하다.
  void _applyRoom(RoomInfo room) {
    // 서버는 **방 평균 페이스 ±30초** 안에 드는 사람만 같은 방에 넣는다
    // (`MatchRoomAssigner.ranked`). 혼자 남는 이유가 대개 이 값이라, 방이
    // 바뀔 때마다 남긴다 — 없으면 "왜 나만 있나"를 로그로 답할 수 없다.
    debugPrint(
      '[match] 방 ${room.runningRoomId} · ${room.status.name} · '
      '${room.players.length}명 · 팀 평균 ${room.teamAveragePaceSecondsPerKm}s/km',
    );

    if (room.status == RoomStatus.cancelled) {
      // 참가자가 모두 빠졌다. 들고 있을 방이 없다.
      unawaited(disconnect());
      return;
    }

    final justMatched =
        state.room?.status != RoomStatus.matched &&
        room.status == RoomStatus.matched;

    state = state.copyWith(
      room: room,
      justMatched: justMatched || state.justMatched,
      failure: null,
    );
  }

  /// 확정 연출을 띄운 뒤에 부른다. 같은 확정으로 두 번 축하하지 않는다.
  void consumeMatched() {
    if (!state.justMatched) return;
    state = state.copyWith(justMatched: false);
  }

  /// 매칭에서 빠진다. 성공했으면 `true`.
  ///
  /// ## 화면이 아니라 여기에 둔다
  ///
  /// 나가기를 누를 수 있는 곳이 둘이다 — 모집 중에는 홈 히어로, 확정 뒤에는
  /// 로비. **같은 순서를 두 화면이 각자 적으면 언젠가 한쪽만 고쳐진다.**
  /// 물어보는 방식(다이얼로그 문구)은 화면마다 다르므로 그쪽에 남긴다.
  ///
  /// ⚠️ **순서가 정해져 있다.** 서버에 취소를 알리고 → 스트림을 닫고 →
  /// 상태를 다시 읽는다. 스트림을 남겨두면 서버가 닫기 전까지 지난 방의
  /// 이벤트가 계속 올라온다.
  Future<bool> leave() async {
    try {
      await ref.read(matchRepositoryProvider).cancel();
    } on MatchException catch (error) {
      // 러닝이 이미 시작됐다 — 나가지 못한 것이 맞지만, 여기서 할 일은
      // 재시도가 아니라 **앱이 늦게 아는 상태를 따라잡는 것**이다. 다시 읽으면
      // `RUNNING`이 올라오고 화면이 러닝으로 옮겨간다.
      if (error.failure == MatchFailure.alreadyStarted) {
        debugPrint('[match] 이미 시작한 러닝이다 · 상태를 다시 읽는다');
        await ref.read(userStatusProvider.notifier).refresh();
        return false;
      }
      // 취소할 것이 없다는 답은 실패가 아니다. 이미 원하던 상태다 —
      // 다른 기기에서 먼저 나갔거나 서버가 방을 닫은 뒤다.
      if (error.failure != MatchFailure.nothingToCancel) {
        debugPrint('[match] 나가지 못했다 · ${error.failure.name}');
        return false;
      }
    }

    await disconnect();
    if (!ref.mounted) return true;
    // 그 방과의 관계가 끝났다. 남겨두면 다음 신청 때 지난 번호를 들고 있다.
    await ref.read(matchRoomStoreProvider).clear();
    if (!ref.mounted) return true;
    await ref.read(userStatusProvider.notifier).refresh();
    return true;
  }

  /// 끊고 방을 비운다. 취소·나가기·방 취소에서 부른다.
  Future<void> disconnect() async {
    // ⚠️ **예약을 먼저 버린다.** 나가기 직전에 끊김이 있었으면 재연결이 예약돼
    // 있는데, 그대로 두면 나간 뒤에 살아나 없는 방에 붙으려 든다.
    _cancelRetry();
    await _stop();
    // ⚠️ 닫는 동안 provider가 버려졌을 수 있다. 그때 state를 건드리면 던진다.
    if (!ref.mounted) return;
    state = const MatchRoomState();
  }

  Future<void> _stop() async {
    final subscription = _subscription;
    _subscription = null;
    // ⚠️ 해지를 기다리지 않는다. 브로드캐스트 스트림의 `cancel()`이 언제
    // 끝나는지는 우리가 통제하지 못하는데, 그걸 기다리다 **닫기 자체가 뒤로
    // 밀린다.** 닫는 것이 목적이고 해지는 그 부수 효과다.
    unawaited(subscription?.cancel());

    final stream = _stream;
    _stream = null;
    await stream?.close();
  }
}
