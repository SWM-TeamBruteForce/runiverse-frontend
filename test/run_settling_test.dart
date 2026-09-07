import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/network/ws_client.dart';
import 'package:runiverse/core/network/ws_message.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/session/data/fake_running_room_repository.dart';
import 'package:runiverse/features/session/data/fake_track_repository.dart';
import 'package:runiverse/features/session/domain/running_channel.dart';
import 'package:runiverse/features/session/domain/track_point.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';

/// 종료 확정 구간 — **상세로 가는 문이 언제 잠기고 언제 열리는가.**
///
/// 상세(17·18번)는 서버가 `RUNNING_FINISH`를 처리한 뒤에야 값이 찬다. 그 전에
/// 부르면 200에 빈 기록이 와서 화면이 `0.00km · 구간 0개`가 된다. 실제로
/// 44분 6.38km 러닝에서 그렇게 됐고, 짧은 러닝은 ack가 빨라 안 보였다.
///
/// 그래서 `finish()`가 도는 동안 `settling`이 서 있어야 하고, **어떻게 끝나든
/// 내려가야 한다** — 안 내려가면 버튼이 영영 잠긴다.
void main() {
  const roomId = 700;

  late FakeTrackRepository track;
  late FakeRunningRoomRepository rooms;
  late _SlowFinishChannel channel;

  setUp(() {
    track = FakeTrackRepository();
    rooms = FakeRunningRoomRepository(roomId: roomId);
    channel = _SlowFinishChannel();
  });

  Future<ProviderContainer> make() async {
    final tokens = InMemoryTokenStore();
    await tokens.saveSession(
      userId: 'u-1',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: true,
    );
    return ProviderContainer.test(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        trackRepositoryProvider.overrideWithValue(track),
        runningRoomRepositoryProvider.overrideWithValue(rooms),
        runningChannelFactoryProvider.overrideWithValue((_) => channel),
      ],
    );
  }

  test('달리는 동안에는 서 있지 않는다', () async {
    final container = await make();
    await container.read(runningConnectionProvider.notifier).open();

    expect(container.read(runningConnectionProvider).settling, isFalse);
  });

  test('⚠️ ack를 기다리는 동안 서 있다', () async {
    // 이 사이에 상세를 열면 빈 기록을 받는다.
    final container = await make();
    await container.read(runningConnectionProvider.notifier).open();

    final finishing = container
        .read(runningConnectionProvider.notifier)
        .finish();
    await channel.arrived;
    // ack가 아직이다.
    expect(container.read(runningConnectionProvider).settling, isTrue);

    channel.ackNow(true);
    await finishing;
  });

  test('ack를 받으면 내려간다', () async {
    final container = await make();
    await container.read(runningConnectionProvider.notifier).open();

    final finishing = container
        .read(runningConnectionProvider.notifier)
        .finish();
    await channel.arrived;
    channel.ackNow(true);
    await finishing;

    final state = container.read(runningConnectionProvider);
    expect(state.settling, isFalse);
    // 방 번호는 남아야 상세를 열 수 있다.
    expect(state.room?.id, roomId);
  });

  test('⚠️ ack를 못 받아도 내려간다', () async {
    // 15초 타임아웃으로 `false`가 돌아오는 경우다. 여기서 안 내리면 버튼이
    // 영영 잠긴 채로 남는다.
    final container = await make();
    await container.read(runningConnectionProvider.notifier).open();

    final finishing = container
        .read(runningConnectionProvider.notifier)
        .finish();
    await channel.arrived;
    channel.ackNow(false);
    await finishing;

    expect(container.read(runningConnectionProvider).settling, isFalse);
  });

  test('⚠️ 종료가 실패해도 내려간다', () async {
    // 저장소가 던지든 채널이 던지든, 잠긴 문을 남기면 안 된다.
    final container = await make();
    await container.read(runningConnectionProvider.notifier).open();

    final finishing = container
        .read(runningConnectionProvider.notifier)
        .finish();
    await channel.arrived;
    channel.failNow(Exception('끊겼다'));

    await expectLater(finishing, throwsA(isA<Exception>()));
    expect(container.read(runningConnectionProvider).settling, isFalse);
  });
}

/// ack가 언제 오는지를 테스트가 정하는 채널.
///
/// 실제 채널은 서버 응답을 기다린다. 그 대기 구간을 손으로 잡고 있어야
/// `settling`이 서 있는 순간을 볼 수 있다.
class _SlowFinishChannel implements RunningChannel {
  Completer<bool>? _pending;
  final _arrived = Completer<void>();

  /// 종료가 여기까지 왔는가. **이걸 기다리지 않고 ack를 쏘면 아무도 못 받는다**
  /// — `finish()`는 남은 좌표를 먼저 보내느라 아직 도착하지 않았다.
  Future<void> get arrived => _arrived.future;

  void ackNow(bool acked) => _pending?.complete(acked);

  void failNow(Object error) => _pending?.completeError(error);

  @override
  Stream<WsConnectionState> get states => const Stream.empty();

  @override
  WsConnectionState get state => WsConnectionState.connected;

  @override
  Stream<WsErrorCode> get errors => const Stream.empty();

  @override
  Future<void> start(int runningRoomId) async {}

  @override
  bool sendLocations(List<TrackPoint> points) => true;

  @override
  Future<bool> finish({bool forced = false}) {
    final waiting = Completer<bool>();
    _pending = waiting;
    if (!_arrived.isCompleted) _arrived.complete();
    return waiting.future;
  }

  @override
  Future<void> close() async {}
}
