import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/network/ws_client.dart';
import 'package:runiverse/core/network/ws_message.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/session/data/fake_track_repository.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/session/domain/run_progress.dart';
import 'package:runiverse/features/session/domain/run_snapshot.dart';
import 'package:runiverse/features/session/domain/running_channel.dart';
import 'package:runiverse/features/session/domain/track_point.dart';
import 'package:runiverse/features/session/domain/user_status.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// `RUNNING_START`가 거절됐을 때 **다시 보내는가.**
///
/// 예전에는 로그만 찍고 끝났다. 한 번 거절되면 앱은 좌표를 계속 올리는데
/// 서버는 전부 버리는 상태로 러닝이 끝났다 — 뛴 만큼이 기록에 안 남는다.
void main() {
  late _RestartChannel channel;
  late FakeUserStatusRepository status;

  /// 실제 2·5·15초를 기다릴 수 없다. 간격만 줄이고 횟수(3)는 그대로 둔다.
  const backoff = [
    Duration(milliseconds: 10),
    Duration(milliseconds: 10),
    Duration(milliseconds: 10),
  ];

  Future<ProviderContainer> makeContainer() async {
    final tokens = InMemoryTokenStore();
    await tokens.saveSession(
      userId: 'u-1',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: true,
    );
    channel = _RestartChannel();
    status = FakeUserStatusRepository(
      status: UserStatusRunning(
        runningRoomId: 125,
        isSolo: false,
        scheduledStartAt: DateTime(2026, 9, 18, 15, 5),
      ),
    );
    return ProviderContainer.test(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
        userStatusRepositoryProvider.overrideWithValue(status),
        runningRestartBackoffProvider.overrideWithValue(backoff),
        runningChannelFactoryProvider.overrideWithValue((_) => channel),
      ],
    );
  }

  /// 예약된 재시도가 돌 시간을 준다.
  Future<void> waitRetry() =>
      Future<void>.delayed(const Duration(milliseconds: 60));

  test('⚠️ INVALID_ROOM_STATE면 간격을 두고 다시 보낸다', () async {
    final container = await makeContainer();
    final connection = container.read(runningConnectionProvider.notifier);
    await connection.openMatched(125, targetDistanceMeters: 3000);
    expect(channel.starts, 1);

    channel.errors_.add(WsErrorCode.invalidRoomState);
    await waitRetry();

    expect(channel.starts, 2);
    // 보내기 전에 서버가 아는 상태를 확인한다.
    expect(status.calls, 1);
  });

  test('RUNNING_SESSION_UNAVAILABLE도 같은 길이다', () async {
    final container = await makeContainer();
    final connection = container.read(runningConnectionProvider.notifier);
    await connection.openMatched(125, targetDistanceMeters: 3000);

    channel.errors_.add(WsErrorCode.runningSessionUnavailable);
    await waitRetry();

    expect(channel.starts, 2);
  });

  test('⚠️ 서버가 이 방을 달리는 중으로 보지 않으면 그만둔다', () async {
    // 이미 끝난 방이다. 몇 번을 보내도 같은 답이 온다.
    final container = await makeContainer();
    final connection = container.read(runningConnectionProvider.notifier);
    await connection.openMatched(125, targetDistanceMeters: 3000);
    status.status = UserStatusRunning(
      runningRoomId: 999,
      isSolo: false,
      scheduledStartAt: DateTime(2026, 9, 18, 15, 5),
    );

    channel.errors_.add(WsErrorCode.invalidRoomState);
    await waitRetry();

    expect(channel.starts, 1);
  });

  test('⚠️ 거절이 쏟아져도 재시도가 겹쳐 쌓이지 않는다', () async {
    // 좌표를 보낼 때마다 오류가 온다. 그대로 두면 예약이 겹쳐 쌓인다.
    final container = await makeContainer();
    final connection = container.read(runningConnectionProvider.notifier);
    await connection.openMatched(125, targetDistanceMeters: 3000);

    for (var i = 0; i < 20; i++) {
      channel.errors_.add(WsErrorCode.invalidRoomState);
    }
    await waitRetry();

    expect(channel.starts, 2);
  });

  test('⚠️ 정해진 횟수를 넘으면 그만둔다', () async {
    // 무한히 두드리면 앱이 서버 장애를 키운다.
    final container = await makeContainer();
    final connection = container.read(runningConnectionProvider.notifier);
    await connection.openMatched(125, targetDistanceMeters: 3000);

    for (var i = 0; i < backoff.length + 3; i++) {
      channel.errors_.add(WsErrorCode.invalidRoomState);
      await waitRetry();
    }

    expect(channel.starts, 1 + backoff.length);
  });
}

/// `RUNNING_START`가 몇 번 나갔는지 센다.
class _RestartChannel implements RunningChannel {
  final errors_ = StreamController<WsErrorCode>.broadcast();
  var starts = 0;
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
  Future<void> start(int runningRoomId) async {
    starts++;
  }

  @override
  bool sendLocations(List<TrackPoint> points) => true;

  @override
  Future<bool> finish({bool forced = false}) async => true;

  @override
  Future<void> close() async {
    closed = true;
  }
}
