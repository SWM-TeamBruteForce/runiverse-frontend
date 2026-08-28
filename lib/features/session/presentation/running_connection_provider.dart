import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/config/app_config.dart';
import 'package:runiverse/core/network/ws_client.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/session/data/http_running_room_repository.dart';
import 'package:runiverse/features/session/data/ws_running_channel.dart';
import 'package:runiverse/features/session/domain/running_channel.dart';
import 'package:runiverse/features/session/domain/running_room.dart';
import 'package:runiverse/features/session/domain/running_room_repository.dart';
import 'package:runiverse/features/session/domain/track_sender.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';

final runningRoomRepositoryProvider = Provider<RunningRoomRepository>(
  (ref) => HttpRunningRoomRepository(
    ref.watch(dioProvider),
    ref.watch(tokenStoreProvider),
    ref.watch(tokenRefresherProvider),
  ),
);

/// 연결 하나를 만드는 법.
///
/// **provider로 뺀 이유는 테스트 때문이다.** 컨트롤러가 `WsClient`를 직접
/// 만들면 위젯 테스트가 진짜 소켓을 열려 하고, 주소가 없어 죽는다.
/// 토큰을 **문자열이 아니라 함수로** 넘긴다.
///
/// 핸드셰이크가 401로 거절되면 `WsClient`가 갱신해서 다시 붙어야 하는데,
/// 문자열을 한 번 건네면 그 자리에서 값이 굳어 죽은 토큰으로 계속 두드리게 된다.
typedef RunningChannelFactory = RunningChannel Function(WsAccessToken token);

final runningChannelFactoryProvider = Provider<RunningChannelFactory>(
  (ref) =>
      (token) => WsRunningChannel(
        WsClient(url: '${AppConfig.wsBaseUrl}/api/v1/ws/running', token: token),
      ),
);

/// 서버와 이어진 상태.
///
/// 방과 연결이 **따로** 있는 이유는 실패 지점이 둘이기 때문이다 —
/// 방은 만들었는데 WS가 안 붙을 수 있고, 그때 화면이 하는 말이 달라야 한다.
class RunningConnectionState {
  const RunningConnectionState({
    this.room,
    this.connection = WsConnectionState.disconnected,
    this.failure,
    this.opening = false,
  });

  /// 서버가 준 방. `null`이면 아직 못 열었다.
  final RunningRoom? room;

  final WsConnectionState connection;

  /// 방을 못 연 이유. 연결 실패는 [connection]이 나타낸다.
  final RunningRoomFailure? failure;

  final bool opening;

  /// 달릴 준비가 됐는가. **방과 연결이 둘 다 있어야 한다.**
  bool get isReady => room != null && connection == WsConnectionState.connected;

  RunningConnectionState copyWith({
    RunningRoom? room,
    WsConnectionState? connection,
    RunningRoomFailure? failure,
    bool? opening,
  }) => RunningConnectionState(
    room: room ?? this.room,
    connection: connection ?? this.connection,
    // ⚠️ `??`를 쓰지 않는다. 다시 시도해서 성공하면 실패를 **지워야** 한다.
    failure: failure,
    opening: opening ?? this.opening,
  );
}

final runningConnectionProvider =
    NotifierProvider<RunningConnectionController, RunningConnectionState>(
      RunningConnectionController.new,
    );

/// 방을 열고 WebSocket에 붙인다.
///
/// ## 순서가 정해져 있다
///
/// `POST /running-rooms/solo` → `runningRoomId` → WS 연결 → `RUNNING_START`
///
/// 방 번호가 WS 모든 메시지의 payload에 들어가므로 **뒤바뀔 수 없다.**
///
/// ## 좌표는 [TrackSender]가 올린다
///
/// 방이 생기고 `RUNNING_START`가 나간 **뒤에** 띄운다. 서버가 방을 알기 전에
/// 좌표를 받으면 버린다. 닫을 때는 소켓보다 **먼저** 멈춘다.
class RunningConnectionController extends Notifier<RunningConnectionState> {
  RunningChannel? _channel;
  Timer? _retry;

  /// 쌓인 좌표를 10초마다 올리는 것. 방이 생긴 뒤에만 있다.
  TrackSender? _sender;

  /// 연속 실패 횟수. backoff 간격을 정한다.
  var _attempt = 0;

  @override
  RunningConnectionState build() {
    // provider가 버려지면 소켓도 닫는다. 안 닫으면 러닝이 끝나도 연결이 남는다.
    ref.onDispose(() {
      _retry?.cancel();
      // ⚠️ 전송기를 먼저 멈춘다. 소켓이 닫힌 뒤에도 타이머가 돌면 매 10초
      // "못 보냈다"만 찍힌다.
      _sender?.stop();
      _channel?.close();
    });
    return const RunningConnectionState();
  }

  /// 방을 열고 연결한다. 이미 준비됐으면 아무것도 하지 않는다.
  ///
  /// ## ⚠️ 실패해도 포기하지 않는다
  ///
  /// 지하철·엘리베이터·터널에서는 몇 초 뒤면 대개 성공한다. 한 번 실패했다고
  /// 러닝을 막으면 **신호가 잠깐 없는 곳에서 아예 못 뛰게 된다.**
  /// 뒤에서 계속 시도하고, 방이 늦게라도 생기면 그때부터 좌표가 올라간다.
  ///
  /// **딱 하나 [RunningRoomFailure.alreadyRunning](409)만 멈춘다.** 재시도해도
  /// 계속 실패하고, 원인이 "이전 러닝이 안 끝났다"라서 사용자가 조치해야 한다.
  Future<void> open() async {
    if (state.opening || state.isReady) return;
    _retry?.cancel();
    state = state.copyWith(opening: true, failure: null);

    final RunningRoom room;
    try {
      room = await ref.read(runningRoomRepositoryProvider).openSolo();
    } on RunningRoomException catch (error) {
      state = RunningConnectionState(failure: error.failure);
      // 409는 다시 시도해도 같은 답이 온다.
      if (error.failure != RunningRoomFailure.alreadyRunning) _scheduleRetry();
      return;
    }

    final accessToken = (await ref.read(tokenStoreProvider).read()).accessToken;
    if (accessToken == null) {
      state = const RunningConnectionState(
        failure: RunningRoomFailure.sessionExpired,
      );
      return;
    }

    final channel = ref.read(runningChannelFactoryProvider)(_accessToken);
    _channel = channel;
    channel.states.listen((connection) {
      state = state.copyWith(connection: connection);
    });

    _attempt = 0;
    state = state.copyWith(room: room, opening: false, failure: null);

    // ⚠️ **방을 알게 된 순간 좌표 기록기에 알린다.** 방이 늦게 생기는 동안
    // 쌓아 둔 좌표가 여기서 한꺼번에 저장된다 — 안 알리면 러닝 초반 좌표가
    // 메모리에만 남아 앱이 죽으면 사라진다.
    await ref.read(trackRecorderProvider).bind(room.id);

    await channel.start(room.id);

    // 이제부터 10초마다 쌓인 좌표가 올라간다. **`start()` 뒤여야 한다** —
    // 서버가 `RUNNING_START`로 방을 알기 전에 좌표를 받으면 버린다.
    _sender = TrackSender(ref.read(trackRepositoryProvider), channel)
      ..start(room.id);

    // ⚠️ **구독만으로는 부족하다.** `states`가 broadcast 스트림이라 구독 전에
    // 지나간 상태는 다시 오지 않는다. `start()` 안에서 `connected`로 바뀌면
    // 그 이벤트를 놓치고, 소켓은 붙었는데 화면은 "연결하는 중"이라고 말한다.
    // 시작 직후 현재값을 한 번 읽어 맞춘다.
    state = state.copyWith(connection: channel.state);
  }

  /// 러닝을 끝낸다. 남은 좌표를 마저 보내고, 확인을 받으면 트랙을 지운다.
  ///
  /// ## 순서가 정해져 있다
  ///
  /// ```
  /// 남은 좌표 전송 → RUNNING_FINISH → RUNNING_FINISHED → 로컬 트랙 삭제 → 닫기
  /// ```
  ///
  /// **좌표를 먼저 보내야 한다.** 서버가 마지막으로 받은 트랙으로 기록을
  /// 확정하므로, 남겨둔 채 끝내면 **그 구간이 빠진 기록이 만들어지고 되돌릴
  /// 수 없다.**
  ///
  /// ## ⚠️ 확인을 못 받으면 트랙을 지우지 않는다
  ///
  /// 명세가 "ack를 받은 뒤 삭제한다"고 정했다. 못 받았는데 지우면 서버에 없는
  /// 구간을 다시 보낼 방법이 사라진다. 남겨두면 자리를 차지하지만 그뿐이다.
  ///
  /// ## 화면은 이것을 기다리지 않는다
  ///
  /// 요약에 뜨는 값은 러닝 중 계산한 것이라 서버 확정과 무관하다. 기다리게
  /// 하면 신호가 나쁜 곳에서 사용자가 요약을 못 본다.
  Future<void> finish({bool forced = false}) async {
    final channel = _channel;
    if (channel == null) {
      await close();
      return;
    }

    await _sender?.drain();
    // 다 보냈으면 타이머를 세운다. ack를 기다리는 동안 또 돌 이유가 없다.
    _sender?.stop();

    final acked = await channel.finish(forced: forced);
    if (acked) {
      await ref.read(trackRecorderProvider).discard();
    } else {
      debugPrint('[running] 종료 확인을 못 받아 로컬 트랙을 남긴다');
    }

    await close();
  }

  /// 연결을 닫고 처음 상태로 돌아간다. **종료를 알리지는 않는다** — 화면을
  /// 벗어나기만 할 때 쓴다. 러닝을 끝낼 때는 [finish]를 부른다.
  Future<void> close() async {
    _retry?.cancel();
    _retry = null;
    _attempt = 0;
    _sender?.stop();
    _sender = null;
    await _channel?.close();
    _channel = null;
    state = const RunningConnectionState();
  }

  /// 붙을 때마다 `WsClient`가 부른다.
  ///
  /// [refresh]가 `true`면 핸드셰이크가 401로 거절된 뒤다. 그때만 갱신한다 —
  /// 매번 갱신하면 멀쩡한 토큰까지 회전시켜 다른 요청을 죽인다.
  ///
  /// ⚠️ **갱신은 [tokenRefresherProvider]를 거친다.** 직접 부르면 러닝 시작
  /// 순간에 `POST /running-rooms/solo`의 갱신과 겹쳐, 서버가 그것을 탈취로 보고
  /// 사용자를 로그아웃시킨다(`docs/implementation-notes.md` 9-6).
  Future<String?> _accessToken({bool refresh = false}) async {
    if (refresh) return ref.read(tokenRefresherProvider).refresh();
    return (await ref.read(tokenStoreProvider).read()).accessToken;
  }

  /// 잠시 뒤 다시 시도한다.
  ///
  /// 1 · 2 · 4 · 8 … 최대 30초. `WsClient`의 재연결과 같은 규칙이다 —
  /// 서버가 죽었을 때 초당 두드리지 않는다.
  void _scheduleRetry() {
    _retry?.cancel();
    final seconds = _attempt >= 5 ? 30 : 1 << _attempt;
    _attempt++;
    _retry = Timer(Duration(seconds: seconds), open);
  }
}
