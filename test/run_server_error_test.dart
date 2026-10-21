import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/network/ws_client.dart';
import 'package:runiverse/core/network/ws_message.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/session/data/fake_track_repository.dart';
import 'package:runiverse/features/session/domain/run_numbers.dart';
import 'package:runiverse/features/session/domain/run_progress.dart';
import 'package:runiverse/features/session/domain/run_snapshot.dart';
import 'package:runiverse/features/session/domain/running_channel.dart';
import 'package:runiverse/features/session/domain/running_room.dart';
import 'package:runiverse/features/session/domain/track_point.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';
import 'package:runiverse/features/session/domain/finish_outcome.dart';

/// 러닝 중 서버가 보내는 `ERROR`에 연결이 **어떻게 반응하는가.**
///
/// 명세는 오류를 보내도 연결을 끊지 않는다. 그래서 앱이 코드마다 다르게
/// 움직여야 한다 — 저장 실패는 알리기만 하고, 참가자가 아니면 접는다.
void main() {
  late _ErrorChannel channel;
  late FakeTrackRepository track;

  Future<ProviderContainer> makeContainer() async {
    final tokens = InMemoryTokenStore();
    await tokens.saveSession(
      userId: 'u-1',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: true,
    );
    channel = _ErrorChannel();
    track = FakeTrackRepository();
    return ProviderContainer.test(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        trackRepositoryProvider.overrideWithValue(track),
        runningChannelFactoryProvider.overrideWithValue((_) => channel),
      ],
    );
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// 재전송·종료가 다 돌 때까지 기다린다.
  ///
  /// ⚠️ [settle]보다 길어야 한다. 재전송은 배치 사이에 한 박자 쉬고
  /// (`TrackSender.drainGap`), 종료는 저장소까지 들렀다 온다 — 짧게 재면
  /// **아직 안 한 일을 안 했다고 읽는다.**
  Future<void> resent() =>
      Future<void>.delayed(const Duration(milliseconds: 400));

  /// 보낼 좌표를 저장소에 쌓아 둔다. 10초 타이머를 기다리지 않으므로, 이걸
  /// 꺼내 보내는 것은 **오류가 불러낸 재전송**뿐이다.
  Future<void> store(int roomId, int from, int to) async {
    for (var i = from; i <= to; i++) {
      await track.add(
        roomId,
        TrackPoint(
          sequence: i,
          pauseSegment: 0,
          latitude: 37.5 + i * 0.0001,
          longitude: 127.0,
          accuracyMeters: 5,
          speedMetersPerSecond: 2.8,
          recordedAt: DateTime(2026, 10, 21, 19, 10).add(Duration(seconds: i)),
        ),
      );
    }
  }

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

  /// 저장 실패한 배치를 다시 보내는가 — 1.1.1 3절.
  ///
  /// ## ⚠️ 끊기지 않으면 아무도 다시 보내지 않았다
  ///
  /// 전송기는 소켓에 넘긴 것을 보낸 것으로 보고 커서를 옮긴다. 재연결만이
  /// 커서를 되돌렸으므로, **연결이 멀쩡한 채로 저장만 실패하면 그 구간은
  /// 영영 올라가지 않았다** — 한 시간을 안 끊기고 달리면 빠진 채로 확정된다.
  ///
  /// 이 테스트들은 10초 타이머를 기다리지 않는다. 그래서 좌표가 올라갔다면
  /// 그것은 **오류가 불러낸 재전송**뿐이다.
  test('⚠️ 저장 실패면 그 배치를 다시 보낸다', () async {
    final container = await makeContainer();
    await store(125, 1, 5);
    final connection = container.read(runningConnectionProvider.notifier);
    await connection.openMatched(125, targetDistanceMeters: 3000);
    expect(channel.batches, isEmpty);

    channel.errors_.add(WsErrorCode.runningTrackUnavailable);
    await resent();

    expect(channel.batches, hasLength(1));
    expect(channel.batches.single.map((p) => p.sequence), [1, 2, 3, 4, 5]);
  });

  test('⚠️ 연달아 실패해도 간격을 두고 보낸다', () async {
    // 서버 저장이 망가져 있으면 10초마다 같은 답이 온다. 그때마다 다시
    // 보내면 **앱이 서버 장애를 키운다.**
    final container = await makeContainer();
    await store(125, 1, 5);
    final connection = container.read(runningConnectionProvider.notifier);
    await connection.openMatched(125, targetDistanceMeters: 3000);

    channel.errors_.add(WsErrorCode.runningTrackUnavailable);
    await resent();
    channel.errors_.add(WsErrorCode.runningTrackUnavailable);
    await resent();

    expect(channel.batches, hasLength(1));
  });

  /// 구간 번호가 거부됐을 때 — 1.1.1 3절.
  ///
  /// ## ⚠️ 이것만은 저절로 풀리지 않는다
  ///
  /// 앱이 매기는 번호는 줄지 않으므로, 이 답은 서버가 기억하는 번호가 더
  /// 크다는 뜻이다. 다음 배치도 같은 이유로 거부되니 **더 달려도 아무것도
  /// 안 남는다.** 모르는 채로 뛰게 두는 것이 가장 나쁜 결과다.
  group('구간 번호가 거부되면', () {
    test('⚠️ 조기 종료로 러닝을 끝낸다', () async {
      final container = await makeContainer();
      final connection = container.read(runningConnectionProvider.notifier);
      await connection.openMatched(125, targetDistanceMeters: 3000);

      channel.errors_.add(WsErrorCode.pauseSegmentDecreased);
      await resent();

      // 목표를 채우기 전에 끝내는 것이라 `forced`다.
      expect(channel.finished_, [true]);
      final state = container.read(runningConnectionProvider);
      expect(state.trackRejected, isTrue);
      // 화면이 이 번호를 보고 요약으로 간다.
      expect(state.finishedRoomId, 125);
      expect(channel.closed, isTrue);
    });

    test('⚠️ 또 와도 종료는 한 번만 나간다', () async {
      // 오류는 배치마다 온다. 그때마다 끝내려 들면 종료가 겹쳐 나간다.
      final container = await makeContainer();
      final connection = container.read(runningConnectionProvider.notifier);
      await connection.openMatched(125, targetDistanceMeters: 3000);

      channel.errors_.add(WsErrorCode.pauseSegmentDecreased);
      channel.errors_.add(WsErrorCode.pauseSegmentDecreased);
      await resent();

      expect(channel.finished_, hasLength(1));
    });

    test('⚠️ 남은 좌표를 다시 보내지 않는다', () async {
      // 전부 같은 이유로 거부된다. 그대로 흘리면 트랙 전체가 공짜로 한 번 더
      // 나가고 종료만 늦어진다.
      final container = await makeContainer();
      await store(125, 1, 5);
      final connection = container.read(runningConnectionProvider.notifier);
      await connection.openMatched(125, targetDistanceMeters: 3000);

      channel.errors_.add(WsErrorCode.pauseSegmentDecreased);
      await resent();

      expect(channel.batches, isEmpty);
    });
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

  /// 올라간 좌표 묶음들. **몇 번 올라갔는지**가 재전송 판정의 근거다.
  final batches = <List<TrackPoint>>[];

  /// 받은 종료 요청의 `forced` 값. 조기 종료인지 보려면 이것을 본다.
  final finished_ = <bool>[];

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
  Stream<void> get finished => const Stream.empty();

  @override
  Stream<RunSnapshot> get snapshots => const Stream.empty();

  @override
  Stream<RunNumbers> get serverNumbers => const Stream.empty();

  @override
  Future<void> start(int runningRoomId) async {}

  @override
  bool sendLocations(List<TrackPoint> points) {
    batches.add(points);
    return true;
  }

  @override
  bool pause() => true;

  @override
  bool resume() => true;

  @override
  Future<FinishOutcome> finish({bool forced = false}) async {
    finished_.add(forced);
    return const FinishConfirmed();
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
