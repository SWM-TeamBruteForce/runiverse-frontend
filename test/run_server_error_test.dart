import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/network/ws_client.dart';
import 'package:runiverse/core/network/ws_message.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/session/data/fake_track_repository.dart';
import 'package:runiverse/features/session/domain/run_progress.dart';
import 'package:runiverse/features/session/domain/run_snapshot.dart';
import 'package:runiverse/features/session/domain/running_channel.dart';
import 'package:runiverse/features/session/domain/running_room.dart';
import 'package:runiverse/features/session/domain/track_point.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';

/// 러닝 중 서버가 보내는 `ERROR`에 연결이 **어떻게 반응하는가.**
///
/// 명세는 오류를 보내도 연결을 끊지 않는다. 그래서 앱이 코드마다 다르게
/// 움직여야 한다 — 저장 실패는 알리기만 하고, 참가자가 아니면 접는다.
void main() {
  late _ErrorChannel channel;

  Future<ProviderContainer> makeContainer() async {
    final tokens = InMemoryTokenStore();
    await tokens.saveSession(
      userId: 'u-1',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: true,
    );
    channel = _ErrorChannel();
    return ProviderContainer.test(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
        runningChannelFactoryProvider.overrideWithValue((_) => channel),
      ],
    );
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('저장 실패는 배너 하나로 알리고 러닝은 계속된다', () async {
    final container = await makeContainer();
    final connection = container.read(runningConnectionProvider.notifier);
    await connection.openMatched(125, targetDistanceMeters: 3000);

    channel.errors_.add(WsErrorCode.runningTrackUnavailable);
    channel.errors_.add(WsErrorCode.runningTrackUnavailable);
    await settle();

    final state = container.read(runningConnectionProvider);
    expect(state.trackUnavailable, isTrue);
    expect(state.failure, isNull);
    expect(channel.closed, isFalse);
  });

  test('⚠️ 참가자가 아니라는 답이 오면 연결을 접는다', () async {
    // 다른 기기에서 취소했거나 서버가 방에서 뺀 경우. 재시도해도 같은 답이다.
    final container = await makeContainer();
    final connection = container.read(runningConnectionProvider.notifier);
    await connection.openMatched(125, targetDistanceMeters: 3000);

    channel.errors_.add(WsErrorCode.notRoomPlayer);
    await settle();

    final state = container.read(runningConnectionProvider);
    expect(state.failure, RunningRoomFailure.notRoomPlayer);
    expect(state.connection, WsConnectionState.closed);
    expect(channel.closed, isTrue);
    // 방 번호는 남긴다. 화면이 상태를 다시 읽을 때 근거가 된다.
    expect(state.room?.id, 125);
  });

  test('다른 오류는 연결을 건드리지 않는다', () async {
    final container = await makeContainer();
    final connection = container.read(runningConnectionProvider.notifier);
    await connection.openMatched(125, targetDistanceMeters: 3000);

    channel.errors_.add(WsErrorCode.invalidRequest);
    await settle();

    final state = container.read(runningConnectionProvider);
    expect(state.failure, isNull);
    expect(state.trackUnavailable, isFalse);
    expect(channel.closed, isFalse);
  });
}

/// 오류를 손으로 흘려보낼 수 있는 채널.
class _ErrorChannel implements RunningChannel {
  final errors_ = StreamController<WsErrorCode>.broadcast();
  var closed = false;

  @override
  Stream<WsConnectionState> get states => const Stream.empty();

  @override
  WsConnectionState get state => WsConnectionState.connected;

  @override
  Stream<WsErrorCode> get errors => errors_.stream;

  @override
  Stream<RunProgress> get progress => const Stream.empty();

  @override
  Stream<RunCombo> get combos => const Stream.empty();

  @override
  Stream<RunSnapshot> get snapshots => const Stream.empty();

  @override
  Future<void> start(int runningRoomId) async {}

  @override
  bool sendLocations(List<TrackPoint> points) => true;

  @override
  Future<bool> finish({bool forced = false}) async => true;

  @override
  Future<void> close() async {
    closed = true;
  }
}
