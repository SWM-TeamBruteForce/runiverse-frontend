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
import 'package:runiverse/features/session/domain/running_room.dart';
import 'package:runiverse/features/session/domain/track_point.dart';
import 'package:runiverse/features/session/domain/user_status.dart';
import 'package:runiverse/features/session/presentation/party_provider.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// 서버가 **진행 중인 것이 없다**고 답했을 때 앱이 무엇을 내려놓는가.
///
/// 러닝은 서버가 강제로 끝낼 수 있다. 예전에는 매칭 스트림만 `IDLE`에
/// 반응해서, 소켓·좌표 전송 타이머·헬스체크가 그대로 살아 **이미 끝난 방에
/// 10초마다 좌표를 계속 올렸다.**
void main() {
  late _TrackedChannel channel;
  late FakeUserStatusRepository status;

  Future<ProviderContainer> makeContainer() async {
    final tokens = InMemoryTokenStore();
    await tokens.saveSession(
      userId: 'u-1',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: true,
    );
    channel = _TrackedChannel();
    status = FakeUserStatusRepository();
    return ProviderContainer.test(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
        userStatusRepositoryProvider.overrideWithValue(status),
        runningChannelFactoryProvider.overrideWithValue((_) => channel),
      ],
    );
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// 서버가 그 상태를 답하게 하고, 앱이 한 번 읽게 한다.
  Future<void> reads(ProviderContainer container, UserStatus value) async {
    status.status = value;
    await container.read(userStatusProvider.notifier).refresh();
    await settle();
  }

  test('⚠️ IDLE이면 소켓을 닫는다', () async {
    final container = await makeContainer();
    final connection = container.read(runningConnectionProvider.notifier);
    await connection.openMatched(125, targetDistanceMeters: 3000);
    expect(channel.closed, isFalse);

    await reads(container, const UserStatusIdle());

    expect(channel.closed, isTrue);
    expect(
      container.read(runningConnectionProvider).failure,
      RunningRoomFailure.endedByServer,
    );
  });

  test('⚠️ 파티 보드도 함께 비워진다', () async {
    final container = await makeContainer();
    final connection = container.read(runningConnectionProvider.notifier);
    await connection.openMatched(125, targetDistanceMeters: 3000);
    container.read(partyProvider);

    channel.progress_.add(
      const RunProgress(userId: 'u-9', distanceMeters: 1800),
    );
    await settle();
    expect(container.read(partyProvider).rows, hasLength(1));

    await reads(container, const UserStatusIdle());

    expect(container.read(partyProvider).rows, isEmpty);
  });

  test('달리는 중이라고 답하면 건드리지 않는다', () async {
    final container = await makeContainer();
    final connection = container.read(runningConnectionProvider.notifier);
    await connection.openMatched(125, targetDistanceMeters: 3000);

    await reads(
      container,
      UserStatusRunning(
        runningRoomId: 125,
        isSolo: false,
        scheduledStartAt: DateTime(2026, 9, 18, 15, 5),
      ),
    );

    expect(channel.closed, isFalse);
    expect(container.read(runningConnectionProvider).failure, isNull);
  });

  test('⚠️ 시작 확인을 받으면 상태를 다시 읽는다', () async {
    // 매칭 SSE는 상태가 `RUNNING`이 되면 닫힌다. 그것을 알려 줄 사람이 없어서
    // 예전에는 러닝 내내 열린 채 남아 있다가 30초 무음 감시로 겨우 닫혔다.
    final container = await makeContainer();
    final connection = container.read(runningConnectionProvider.notifier);
    status.status = UserStatusRunning(
      runningRoomId: 125,
      isSolo: false,
      scheduledStartAt: DateTime(2026, 9, 18, 15, 5),
    );
    await connection.openMatched(125, targetDistanceMeters: 3000);
    final before = status.calls;

    channel.snapshots_.add(
      const RunSnapshot(runningRoomId: 125, players: [], combos: RunCombo([])),
    );
    await settle();
    await settle();

    expect(status.calls, before + 1);
    expect(container.read(userStatusProvider), isA<UserStatusRunning>());
  });

  test('⚠️ 붙어 있지 않으면 아무것도 하지 않는다', () async {
    // 러닝을 막 끝낸 직후가 그렇다. 소켓은 닫혔고 **방 번호만 남아** 요약
    // 화면이 상세를 부르는데, 그때 상태를 읽으면 당연히 `IDLE`이다.
    // 여기서 비우면 `자세한 기록 보기`가 영영 잠긴다.
    final container = await makeContainer();
    final connection = container.read(runningConnectionProvider.notifier);
    await connection.openMatched(125, targetDistanceMeters: 3000);
    await connection.finish();

    await reads(container, const UserStatusIdle());

    expect(container.read(runningConnectionProvider).room?.id, 125);
    expect(container.read(runningConnectionProvider).failure, isNull);
  });
}

/// 닫혔는지 세는 채널. 진행 통지도 손으로 흘려보낸다.
class _TrackedChannel implements RunningChannel {
  final progress_ = StreamController<RunProgress>.broadcast();
  final snapshots_ = StreamController<RunSnapshot>.broadcast();
  var closed = false;

  @override
  Stream<WsConnectionState> get states => const Stream.empty();

  @override
  WsConnectionState get state => WsConnectionState.connected;

  @override
  Stream<WsErrorCode> get errors => const Stream.empty();

  @override
  Stream<RunProgress> get progress => progress_.stream;

  @override
  Stream<RunCombo> get combos => const Stream.empty();

  @override
  Stream<RunSnapshot> get snapshots => snapshots_.stream;

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
