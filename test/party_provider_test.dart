import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/network/ws_client.dart';
import 'package:runiverse/core/network/ws_message.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/session/data/fake_location_repository.dart';
import 'package:runiverse/features/session/data/fake_track_repository.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/run_session_state.dart';
import 'package:runiverse/features/session/domain/run_progress.dart';
import 'package:runiverse/features/session/domain/run_snapshot.dart';
import 'package:runiverse/features/session/domain/running_channel.dart';
import 'package:runiverse/features/session/domain/track_point.dart';
import 'package:runiverse/features/session/domain/user_status.dart';
import 'package:runiverse/features/session/presentation/party_provider.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// 파티 보드가 **통지에 붙는 시점.**
///
/// 방이 열리는 것과 이 provider가 처음 읽히는 것 중 어느 쪽이 먼저인지는
/// 경로마다 다르다. 어느 순서로도 통지를 받아야 한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _PushChannel channel;
  late FakeLocationRepository location;

  /// 세션이 지금 재고 있는 내 거리(m). 달리는 중이 아니면 0.
  int distanceOf(ProviderContainer container) =>
      switch (container.read(runSessionControllerProvider)) {
        RunRunning(:final metrics) ||
        RunPaused(:final metrics) => metrics.distanceMeters.round(),
        _ => 0,
      };

  Future<ProviderContainer> makeContainer() async {
    final tokens = InMemoryTokenStore();
    await tokens.saveSession(
      userId: 'u-1',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: true,
    );
    channel = _PushChannel();
    location = FakeLocationRepository();
    return ProviderContainer.test(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        locationRepositoryProvider.overrideWithValue(location),
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
        // ⚠️ 시작 확인을 받으면 연결이 상태를 다시 읽는다. 기본값(`IDLE`)을
        // 두면 "서버가 이미 끝냈다"로 읽혀 소켓이 닫히고 보드가 비워진다 —
        // 이 파일의 테스트는 전부 **달리는 중**을 전제로 한다.
        userStatusRepositoryProvider.overrideWithValue(
          FakeUserStatusRepository(
            status: UserStatusRunning(
              runningRoomId: 13,
              isSolo: false,
              scheduledStartAt: DateTime(2026, 9, 18, 15, 5),
            ),
          ),
        ),
        runningChannelFactoryProvider.overrideWithValue((_) => channel),
      ],
    );
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// 좌표 하나. 시각은 페이스 계산에 쓰이므로 뒤로 갈수록 늦춘다.
  var clock = DateTime(2026, 9, 18, 15, 5);
  GeoPoint point(double lat, double lon) {
    clock = clock.add(const Duration(seconds: 10));
    return GeoPoint(latitude: lat, longitude: lon, recordedAt: clock);
  }

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

  group('RUNNING_STARTED 스냅샷', () {
    RunSnapshot snapshot({
      required List<RunPlayer> players,
      List<ComboPeer> combos = const [],
      int? target = 3000,
      DateTime? startedAt,
    }) => RunSnapshot(
      runningRoomId: 13,
      players: players,
      combos: RunCombo(combos),
      targetDistanceMeters: target,
      startedAt: startedAt,
    );

    RunPlayer player(String id, String name, int meters, {int? pace}) =>
        RunPlayer(
          userId: id,
          nickname: name,
          distanceMeters: meters,
          currentPaceSecondsPerKm: pace,
        );

    test('이름·사진과 파티원 거리를 한 번에 채운다', () async {
      // 이름은 여기서만 온다. 진행·콤보 통지는 `userId`만 싣는다.
      final container = await makeContainer();
      await container
          .read(runningConnectionProvider.notifier)
          .openMatched(13, targetDistanceMeters: 3000);
      container.read(partyProvider);

      channel.snapshots_.add(
        snapshot(
          players: [
            player('u-1', '러너42', 1200),
            player('u-9', '김도윤', 1800, pace: 321),
          ],
        ),
      );
      await settle();
      await settle();

      final board = container.read(partyProvider);
      expect(board.myUserId, 'u-1');
      expect(board.rows, hasLength(1));
      expect(board.rows.single.userId, 'u-9');
      expect(board.rows.single.member?.nickname, '김도윤');
      expect(board.rows.single.progress?.distanceMeters, 1800);
      expect(board.rows.single.progress?.currentPaceSecondsPerKm, 321);
      // 내 줄은 명단에 있지만 파티원으로 세지 않는다.
      expect(board.lanes.first.isMe, isTrue);
      expect(board.lanes.first.member?.nickname, '러너42');
    });

    test('⚠️ 콤보가 비어 있어도 그대로 얹는다', () async {
      // 시작 직후에는 늘 빈 배열이다. 못 읽은 것과 다르다.
      final container = await makeContainer();
      await container
          .read(runningConnectionProvider.notifier)
          .openMatched(13, targetDistanceMeters: 3000);
      container.read(partyProvider);

      channel.snapshots_.add(
        snapshot(players: [player('u-1', '러너42', 0), player('u-9', '김도윤', 0)]),
      );
      await settle();
      await settle();

      expect(container.read(partyProvider).combos, isEmpty);
      expect(container.read(partyProvider).rows, hasLength(1));
    });

    test('콤보가 실려 오면 최고 기록까지 살아난다', () async {
      // 재연결 직후다. 끊겼다 붙는 사이의 콤보를 여기서 되찾는다.
      final container = await makeContainer();
      await container
          .read(runningConnectionProvider.notifier)
          .openMatched(13, targetDistanceMeters: 3000);
      container.read(partyProvider);

      channel.snapshots_.add(
        snapshot(
          players: [player('u-1', '러너42', 900), player('u-9', '김도윤', 880)],
          combos: const [
            ComboPeer(
              userId: 'u-9',
              gapMeters: -20,
              comboCount: 12,
              maxComboCount: 30,
            ),
          ],
        ),
      );
      await settle();
      await settle();

      final board = container.read(partyProvider);
      expect(board.combos['u-9']?.comboCount, 12);
      expect(board.bestComboOf('u-9'), 30);
      expect(board.rows.single.gapMeters, -20);
    });

    test('⚠️ 내 거리는 스냅샷 값으로 바닥을 메운다', () async {
      // 앱을 껐다 켜면 로컬 누적이 0부터라 화면만 0.00km가 된다.
      final container = await makeContainer();
      final session = container.read(runSessionControllerProvider.notifier);
      await container
          .read(runningConnectionProvider.notifier)
          .openMatched(13, targetDistanceMeters: 3000);
      container.read(partyProvider);

      await session.prepare();
      location.emit(point(37.5, 127));
      await settle();
      // 출발 시각을 받은 러닝 = 이어 붙은 러닝이다.
      session.start(since: DateTime(2026, 9, 18, 15, 5));
      expect(distanceOf(container), 0);

      channel.snapshots_.add(snapshot(players: [player('u-1', '러너42', 1520)]));
      await settle();
      await settle();

      expect(distanceOf(container), 1520);
    });

    test('⚠️ 경과 시간을 서버의 실제 시작 시각으로 맞춘다', () async {
      // 복구는 상태 조회의 **예약 시각**으로 재기 시작한다. 솔로 방은 만들어진
      // 순간이 시작이라 그 값과 갈린다 — 스냅샷이 유일하게 정확하다.
      final container = await makeContainer();
      final session = container.read(runSessionControllerProvider.notifier);
      await container
          .read(runningConnectionProvider.notifier)
          .openMatched(13, targetDistanceMeters: 3000);
      container.read(partyProvider);

      await session.prepare();
      location.emit(point(37.5, 127));
      await settle();
      // 예약 시각을 받은 러닝 = 이어 붙은 러닝이다.
      session.start(since: DateTime.now().subtract(const Duration(minutes: 1)));

      channel.snapshots_.add(
        snapshot(
          players: [player('u-1', '러너42', 0)],
          startedAt: DateTime.now().subtract(const Duration(minutes: 30)),
        ),
      );
      await settle();
      await settle();

      final state = container.read(runSessionControllerProvider);
      expect(state, isA<RunRunning>());
      // 예약 시각(1분 전)이 아니라 실제 시작(30분 전)부터 잰다.
      expect(
        (state as RunRunning).metrics.elapsed,
        greaterThan(const Duration(minutes: 25)),
      );
    });

    test('⚠️ 새로 시작한 러닝은 시작 시각을 덮지 않는다', () async {
      // 앱이 잰 시각이 더 정확하다. 스냅샷은 복구용이다.
      final container = await makeContainer();
      final session = container.read(runSessionControllerProvider.notifier);
      await container
          .read(runningConnectionProvider.notifier)
          .openMatched(13, targetDistanceMeters: 3000);
      container.read(partyProvider);

      await session.prepare();
      location.emit(point(37.5, 127));
      await settle();
      session.start();

      channel.snapshots_.add(
        snapshot(
          players: [player('u-1', '러너42', 0)],
          startedAt: DateTime(2020),
        ),
      );
      await settle();
      await settle();

      final state = container.read(runSessionControllerProvider) as RunRunning;
      expect(state.metrics.elapsed, lessThan(const Duration(minutes: 1)));
    });

    test('⚠️ 새로 시작한 러닝은 스냅샷이 거리를 덮지 않는다', () async {
      // 연결만 끊겼다 붙은 경우가 이렇다. 서버 누적과 앱 누적은 미세하게
      // 다른데, 통지마다 맞추면 화면의 숫자가 툭 뛴다.
      final container = await makeContainer();
      final session = container.read(runSessionControllerProvider.notifier);
      await container
          .read(runningConnectionProvider.notifier)
          .openMatched(13, targetDistanceMeters: 3000);
      container.read(partyProvider);

      await session.prepare();
      location.emit(point(37.5, 127));
      await settle();
      session.start();
      // 앱이 스스로 잰 거리를 만든다. `start()`가 준비 중 좌표를 버리므로
      // 출발 뒤 좌표가 둘은 있어야 거리가 쌓인다.
      location.emit(point(37.5, 127));
      await settle();
      location.emit(point(37.52, 127));
      await settle();
      final local = distanceOf(container);
      expect(local, greaterThan(0));

      channel.snapshots_.add(snapshot(players: [player('u-1', '러너42', 9999)]));
      await settle();
      await settle();

      expect(distanceOf(container), local);
    });
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
  final snapshots_ = StreamController<RunSnapshot>.broadcast();
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
  Stream<RunSnapshot> get snapshots => snapshots_.stream;

  @override
  Future<void> start(int runningRoomId) async {}

  @override
  bool sendLocations(List<TrackPoint> points) => true;

  @override
  Future<bool> finish({bool forced = false}) async => true;

  @override
  Future<void> close() async {}
}
