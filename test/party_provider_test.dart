import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/network/ws_client.dart';
import 'package:runiverse/core/network/ws_message.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/session/data/fake_track_repository.dart';
import 'package:runiverse/features/session/domain/run_progress.dart';
import 'package:runiverse/features/session/domain/running_channel.dart';
import 'package:runiverse/features/session/domain/track_point.dart';
import 'package:runiverse/features/session/presentation/party_provider.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';

/// 파티 보드가 **통지에 붙는 시점.**
///
/// 방이 열리는 것과 이 provider가 처음 읽히는 것 중 어느 쪽이 먼저인지는
/// 경로마다 다르다. 어느 순서로도 통지를 받아야 한다.
void main() {
  late _PushChannel channel;

  Future<ProviderContainer> makeContainer() async {
    final tokens = InMemoryTokenStore();
    await tokens.saveSession(
      userId: 'u-1',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: true,
    );
    channel = _PushChannel();
    return ProviderContainer.test(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
        runningChannelFactoryProvider.overrideWithValue((_) => channel),
      ],
    );
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  RunProgress progress(String userId, int meters) =>
      RunProgress(userId: userId, distanceMeters: meters);

  test('방을 연 뒤에 읽어도 통지가 보드에 붙는다', () async {
    // 화면보다 방이 먼저 열리는 경로다. 앱을 껐다 켜면 스플래시가 방을 먼저
    // 열고 러닝 화면을 뒤에 띄운다 — 그때 `room`이 바뀌는 일이 없어서, 변화만
    // 듣는 구독은 영영 붙지 않는다(2026-09-18 실주행에서 파티원이 안 보였다).
    final container = await makeContainer();
    await container
        .read(runningConnectionProvider.notifier)
        .openMatched(13, targetDistanceMeters: 3000);

    // 여기서 처음 읽는다. 방은 이미 열려 있다.
    expect(container.read(partyProvider).rows, isEmpty);

    channel.progress_.add(progress('u-9', 1800));
    await settle();

    final board = container.read(partyProvider);
    expect(board.rows, hasLength(1));
    expect(board.rows.single.userId, 'u-9');
    expect(board.rows.single.progress?.distanceMeters, 1800);
  });

  test('읽은 뒤에 방을 열어도 붙는다', () async {
    // 평소 경로다. 러닝 화면이 먼저 서고 그 다음 방이 열린다.
    final container = await makeContainer();
    expect(container.read(partyProvider).rows, isEmpty);

    await container
        .read(runningConnectionProvider.notifier)
        .openMatched(13, targetDistanceMeters: 3000);
    channel.progress_.add(progress('u-9', 400));
    await settle();

    expect(container.read(partyProvider).rows.single.userId, 'u-9');
  });

  test('⚠️ 두 번 붙어 통지를 두 번 세지 않는다', () async {
    // 첫 build에서 한 번, `room` 변화로 또 한 번 붙을 수 있다. 구독이 겹치면
    // 콤보 햅틱이 두 번 울리고 보드가 같은 값을 두 번 덮는다.
    final container = await makeContainer();
    await container
        .read(runningConnectionProvider.notifier)
        .openMatched(13, targetDistanceMeters: 3000);
    container.read(partyProvider);
    await settle();

    expect(channel.progressListeners, 1);
    expect(channel.comboListeners, 1);
  });
}

/// 진행·콤보를 손으로 흘려보낼 수 있는 채널. 구독 수도 센다.
class _PushChannel implements RunningChannel {
  final progress_ = StreamController<RunProgress>.broadcast();
  final combos_ = StreamController<RunCombo>.broadcast();
  var progressListeners = 0;
  var comboListeners = 0;

  @override
  Stream<WsConnectionState> get states => const Stream.empty();

  @override
  WsConnectionState get state => WsConnectionState.connected;

  @override
  Stream<WsErrorCode> get errors => const Stream.empty();

  @override
  Stream<RunProgress> get progress {
    progressListeners++;
    return progress_.stream;
  }

  @override
  Stream<RunCombo> get combos {
    comboListeners++;
    return combos_.stream;
  }

  @override
  Future<void> start(int runningRoomId) async {}

  @override
  bool sendLocations(List<TrackPoint> points) => true;

  @override
  Future<bool> finish({bool forced = false}) async => true;

  @override
  Future<void> close() async {}
}
