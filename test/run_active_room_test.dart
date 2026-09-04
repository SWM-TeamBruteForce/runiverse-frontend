import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/network/ws_client.dart';
import 'package:runiverse/core/network/ws_message.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/session/data/fake_running_room_repository.dart';
import 'package:runiverse/features/session/data/fake_track_repository.dart';
import 'package:runiverse/features/session/domain/running_channel.dart';
import 'package:runiverse/features/session/domain/running_room.dart';
import 'package:runiverse/features/session/domain/track_point.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';

/// 끝내지 못한 방 — **앱이 스스로 풀 수 있는가.**
///
/// 러닝 중 앱이 죽으면 서버에 `STARTED` 방이 남고, 그 뒤로 방을 만들 때마다
/// 409가 온다. 서버에는 그 번호를 되찾을 API가 없다 — 409 응답에 번호가 없고
/// `GET /users/me/running-match`는 매칭 조회다.
///
/// **그래서 방을 연 순간 번호를 기기에 남긴다.** 이 테스트가 보는 것은
/// 그 번호가 제때 남고, 제때 쓰이고, 제때 지워지는가다.
void main() {
  const roomId = 700;
  const staleRoom = 699;

  late FakeTrackRepository track;
  late FakeRunningRoomRepository rooms;
  late _RecordingChannel channel;

  setUp(() {
    track = FakeTrackRepository();
    rooms = FakeRunningRoomRepository(roomId: roomId);
    channel = _RecordingChannel();
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

  TrackPoint point(int sequence) => TrackPoint(
    sequence: sequence,
    latitude: 37.5,
    longitude: 127.0,
    accuracyMeters: 5,
    speedMetersPerSecond: 2.8,
    recordedAt: DateTime(2026, 8, 28, 19, 10, sequence),
  );

  group('번호를 남긴다', () {
    test('⚠️ 방을 열면 곧바로 남긴다', () async {
      // 남기기 전에 앱이 죽으면 그 방은 영영 못 끝낸다.
      final container = await make();

      await container.read(runningConnectionProvider.notifier).open();

      expect(track.active, roomId);
    });

    test('⚠️ 좌표가 하나도 없어도 남는다', () async {
      // 방만 만들고 죽는 경우가 가장 풀기 어렵다 — 트랙이 비어 있어
      // 거기서도 번호를 되찾을 수 없다.
      final container = await make();

      await container.read(runningConnectionProvider.notifier).open();

      expect(await track.count(roomId), 0);
      expect(track.active, roomId);
    });
  });

  group('409에서 스스로 푼다', () {
    test('⚠️ 남은 방을 끝내고 다시 시도한다', () async {
      // 이 테스트가 이 기능의 존재 이유다. 예전에는 여기서 계정이 막혔다.
      track.active = staleRoom;
      rooms.failure = RunningRoomFailure.alreadyRunning;

      final container = await make();
      channel.onFinish = () => rooms.failure = null;

      await container.read(runningConnectionProvider.notifier).open();

      expect(channel.startedRooms, contains(staleRoom), reason: '남은 방에 안 붙었다');
      expect(channel.finishes, 1, reason: '남은 방을 안 끝냈다');
      expect(
        container.read(runningConnectionProvider).room?.id,
        roomId,
        reason: '정리한 뒤 새 방을 못 열었다',
      );
    });

    test('⚠️ 남은 방의 좌표를 먼저 보낸다', () async {
      // 그냥 끝내면 서버는 받은 데까지로 기록을 확정한다. 뛴 만큼이 안 남는다.
      track.active = staleRoom;
      for (var i = 1; i <= 5; i++) {
        await track.add(staleRoom, point(i));
      }
      rooms.failure = RunningRoomFailure.alreadyRunning;

      final container = await make();
      channel.onFinish = () => rooms.failure = null;

      await container.read(runningConnectionProvider.notifier).open();

      expect(channel.sent.map((p) => p.sequence), [1, 2, 3, 4, 5]);
      expect(
        channel.order.indexOf('locations'),
        lessThan(channel.order.indexOf('finish')),
        reason: '좌표보다 종료가 먼저 나갔다',
      );
    });

    test('정리한 뒤 남은 방의 흔적을 지운다', () async {
      track.active = staleRoom;
      await track.add(staleRoom, point(1));
      rooms.failure = RunningRoomFailure.alreadyRunning;

      final container = await make();
      channel.onFinish = () => rooms.failure = null;

      await container.read(runningConnectionProvider.notifier).open();

      expect(await track.count(staleRoom), 0);
      expect(track.active, roomId, reason: '새 방 번호로 바뀌어 있어야 한다');
    });

    test('⚠️ 남긴 번호가 없으면 포기한다', () async {
      // 앱을 지웠다 다시 깐 경우다. 앱이 할 수 있는 것이 없다.
      rooms.failure = RunningRoomFailure.alreadyRunning;

      final container = await make();
      await container.read(runningConnectionProvider.notifier).open();

      expect(
        container.read(runningConnectionProvider).failure,
        RunningRoomFailure.alreadyRunning,
      );
      expect(channel.finishes, 0, reason: '모르는 방을 끝내려 들면 안 된다');
    });

    test('⚠️ ack를 못 받으면 번호를 남긴다', () async {
      // 지우면 그 계정은 영영 못 푼다 — 409 응답에 번호가 없어
      // 다시 얻을 데가 없다. 이번 시도는 막히더라도 다음 실행에서
      // 다시 해볼 수 있어야 한다.
      track.active = staleRoom;
      await track.add(staleRoom, point(1));
      rooms.failure = RunningRoomFailure.alreadyRunning;
      channel.ack = false;

      final container = await make();
      await container.read(runningConnectionProvider.notifier).open();

      expect(track.active, staleRoom, reason: '번호를 잃으면 다시 시도할 길이 없다');
      expect(
        await track.count(staleRoom),
        1,
        reason: '좌표까지 잃으면 그 구간을 다시 못 보낸다',
      );
      expect(
        container.read(runningConnectionProvider).failure,
        RunningRoomFailure.alreadyRunning,
      );
    });
  });

  group('끝나면 지운다', () {
    test('⚠️ ack를 받으면 좌표와 번호를 함께 지운다', () async {
      final container = await make();
      final connection = container.read(runningConnectionProvider.notifier);
      await connection.open();
      await track.add(roomId, point(1));

      await connection.finish();

      expect(await track.count(roomId), 0);
      expect(track.active, isNull, reason: '번호만 남으면 다음 러닝이 헛돈다');
    });

    test('⚠️ ack를 못 받으면 둘 다 남긴다', () async {
      // 지우면 서버에 없는 구간을 다시 보낼 방법이 사라진다.
      channel.ack = false;
      final container = await make();
      final connection = container.read(runningConnectionProvider.notifier);
      await connection.open();
      await track.add(roomId, point(1));

      await connection.finish();

      expect(await track.count(roomId), 1);
      expect(track.active, roomId);
    });
  });
}

class _RecordingChannel implements RunningChannel {
  final startedRooms = <int>[];
  final order = <String>[];
  final sent = <TrackPoint>[];

  var finishes = 0;
  var ack = true;

  /// 종료가 나가는 순간 불린다. **서버가 방을 끝내야 409가 풀린다** —
  /// 그 순서를 테스트에서 그대로 만든다.
  void Function()? onFinish;

  @override
  Stream<WsConnectionState> get states => const Stream.empty();

  @override
  WsConnectionState get state => WsConnectionState.connected;

  @override
  Stream<WsErrorCode> get errors => const Stream.empty();

  @override
  Future<void> start(int runningRoomId) async {
    startedRooms.add(runningRoomId);
    order.add('start');
  }

  @override
  bool sendLocations(List<TrackPoint> points) {
    if (points.isEmpty) return true;
    if (order.isEmpty || order.last != 'locations') order.add('locations');
    sent.addAll(points);
    return true;
  }

  @override
  Future<bool> finish({bool forced = false}) async {
    finishes++;
    order.add('finish');
    onFinish?.call();
    return ack;
  }

  @override
  Future<void> close() async {}
}
