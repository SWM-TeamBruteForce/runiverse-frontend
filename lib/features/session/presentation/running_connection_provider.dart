import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/config/app_config.dart';
import 'package:runiverse/core/network/ws_client.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/session/data/http_running_room_repository.dart';
import 'package:runiverse/features/session/data/ws_running_channel.dart';
import 'package:runiverse/features/session/domain/running_channel.dart';
import 'package:runiverse/features/session/domain/running_room.dart';
import 'package:runiverse/features/session/domain/running_room_repository.dart';

final runningRoomRepositoryProvider = Provider<RunningRoomRepository>(
  (ref) => HttpRunningRoomRepository(
    ref.watch(dioProvider),
    ref.watch(tokenStoreProvider),
    ref.watch(authRepositoryProvider),
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
/// ## ⚠️ 아직 좌표를 보내지 않는다
///
/// `RUNNING_LOCATION_UPDATE`가 명세상 `개발전`이다. 지금은 연결을 세우고
/// 유지하는 데까지가 범위다(설계 문서 3절).
class RunningConnectionController extends Notifier<RunningConnectionState> {
  RunningChannel? _channel;

  @override
  RunningConnectionState build() {
    // provider가 버려지면 소켓도 닫는다. 안 닫으면 러닝이 끝나도 연결이 남는다.
    ref.onDispose(() => _channel?.close());
    return const RunningConnectionState();
  }

  /// 방을 열고 연결한다. 이미 준비됐으면 아무것도 하지 않는다.
  Future<void> open() async {
    if (state.opening || state.isReady) return;
    state = state.copyWith(opening: true);

    final RunningRoom room;
    try {
      room = await ref.read(runningRoomRepositoryProvider).openSolo();
    } on RunningRoomException catch (error) {
      state = RunningConnectionState(failure: error.failure);
      return;
    }

    final accessToken = (await ref.read(tokenStoreProvider).read()).accessToken;
    if (accessToken == null) {
      state = const RunningConnectionState(
        failure: RunningRoomFailure.sessionExpired,
      );
      return;
    }

    final channel = WsRunningChannel(
      WsClient(url: _url, accessToken: accessToken),
    );
    _channel = channel;
    channel.states.listen((connection) {
      state = state.copyWith(connection: connection);
    });

    state = state.copyWith(room: room, opening: false);
    await channel.start(room.id);
  }

  /// 러닝을 끝내거나 화면을 벗어날 때. 연결을 닫고 처음 상태로 돌아간다.
  Future<void> close() async {
    await _channel?.close();
    _channel = null;
    state = const RunningConnectionState();
  }

  /// `wss://host/api/v1/ws/running`
  static String get _url => '${AppConfig.wsBaseUrl}/api/v1/ws/running';
}
