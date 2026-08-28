import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/network/ws_client.dart';
import 'package:runiverse/core/network/ws_message.dart';
import 'package:runiverse/features/session/data/fake_track_repository.dart';
import 'package:runiverse/features/session/domain/running_channel.dart';
import 'package:runiverse/features/session/domain/track_point.dart';
import 'package:runiverse/features/session/domain/track_sender.dart';

/// 좌표 전송 — **커서가 틀리면 좌표가 조용히 사라진다.**
///
/// 이 기능의 위험은 실패가 눈에 안 보인다는 것이다. `RUNNING_LOCATION_UPDATE`에
/// ack가 없어서, 못 보낸 구간이 생겨도 앱은 아무 말도 하지 않는다. 서버는 그
/// 자리를 직선으로 이어 **거리를 짧게 계산하고**, 사용자는 뛴 만큼 기록이
/// 안 나온 것만 본다.
///
/// 그래서 여기서 보는 것은 "보냈는가"가 아니라 **"빠뜨리지 않는가"**다.
void main() {
  const roomId = 77;

  late FakeTrackRepository repository;
  late _RecordingChannel channel;
  late TrackSender sender;

  setUp(() {
    repository = FakeTrackRepository();
    channel = _RecordingChannel();
    sender = TrackSender(repository, channel);
  });

  tearDown(() => sender.stop());

  TrackPoint point(int sequence) => TrackPoint(
    sequence: sequence,
    latitude: 37.5 + sequence * 0.0001,
    longitude: 127.0,
    accuracyMeters: 5,
    speedMetersPerSecond: 2.8,
    recordedAt: DateTime(
      2026,
      8,
      27,
      19,
      10,
      0,
    ).add(Duration(seconds: sequence)),
  );

  Future<void> store(int from, int to) async {
    for (var i = from; i <= to; i++) {
      await repository.add(roomId, point(i));
    }
  }

  /// 보낸 묶음들의 순번만 펼친다.
  List<int> sentSequences() => [
    for (final batch in channel.batches) ...batch.map((p) => p.sequence),
  ];

  group('보내기', () {
    test('쌓인 것을 보낸다', () async {
      await store(1, 5);
      sender.start(roomId);

      await sender.flush();

      expect(channel.batches, hasLength(1));
      expect(sentSequences(), [1, 2, 3, 4, 5]);
    });

    test('보낼 것이 없으면 아무것도 보내지 않는다', () async {
      sender.start(roomId);

      await sender.flush();

      expect(channel.batches, isEmpty);
    });

    test('⚠️ 같은 좌표를 두 번 보내지 않는다', () async {
      // 매번 처음부터 보내면 30분 러닝의 마지막에는 1,800점을 10초마다 보낸다.
      await store(1, 5);
      sender.start(roomId);
      await sender.flush();

      await store(6, 8);
      await sender.flush();

      expect(channel.batches, hasLength(2));
      expect(channel.batches.last.map((p) => p.sequence), [6, 7, 8]);
    });

    test('시작하지 않았으면 보내지 않는다', () async {
      await store(1, 5);

      await sender.flush();

      expect(channel.batches, isEmpty);
    });
  });

  group('못 보냈을 때', () {
    test('⚠️ 소켓에 못 넘기면 커서를 옮기지 않는다', () async {
      // 여기서 커서를 옮기면 그 구간이 영영 안 간다.
      channel.connected = false;
      await store(1, 5);
      sender.start(roomId);

      await sender.flush();

      expect(sender.lastSent, 0);
      expect(channel.batches, isEmpty);
    });

    test('⚠️ 다시 붙으면 못 보낸 것부터 이어서 보낸다', () async {
      channel.connected = false;
      await store(1, 5);
      sender.start(roomId);
      await sender.flush();

      channel.connected = true;
      await sender.flush();

      expect(sentSequences(), [1, 2, 3, 4, 5], reason: '빠뜨린 것이 있다');
    });

    test('저장소가 실패해도 죽지 않는다', () async {
      repository.failure = StateError('디스크가 죽었다');
      sender.start(roomId);

      await sender.flush();

      expect(channel.batches, isEmpty);
    });
  });

  group('재연결', () {
    test('⚠️ 끊기면 30점 물러서서 다시 보낸다', () async {
      // ack가 없어 서버가 어디까지 받았는지 모른다. 끊기던 순간 날아가던
      // 배치를 덮으려면 겹쳐야 한다.
      await store(1, 100);
      sender.start(roomId);
      await sender.flush();
      expect(sender.lastSent, 100);

      channel.emitState(WsConnectionState.reconnecting);
      await Future<void>.delayed(Duration.zero);

      expect(sender.lastSent, 70);
    });

    test('⚠️ 겹치는 구간을 실제로 다시 보낸다', () async {
      await store(1, 100);
      sender.start(roomId);
      await sender.flush();

      channel.emitState(WsConnectionState.reconnecting);
      await Future<void>.delayed(Duration.zero);
      await sender.flush();

      expect(channel.batches.last.first.sequence, 71);
      expect(channel.batches.last.last.sequence, 100);
    });

    test('아직 보낸 게 없으면 물러설 것도 없다', () async {
      sender.start(roomId);

      channel.emitState(WsConnectionState.reconnecting);
      await Future<void>.delayed(Duration.zero);

      expect(sender.lastSent, 0);
    });

    test('⚠️ 겹침이 시작보다 앞서지 않는다', () async {
      // 음수가 되면 `after`가 무엇을 돌려줄지 알 수 없다.
      await store(1, 10);
      sender.start(roomId);
      await sender.flush();

      channel.emitState(WsConnectionState.reconnecting);
      await Future<void>.delayed(Duration.zero);

      expect(sender.lastSent, 0);
    });
  });

  group('많이 밀렸을 때', () {
    test('⚠️ 한 번에 다 싣지 않고 나눠 보낸다', () async {
      // 몇 분 끊겼다 붙으면 수백 점이다. 한 프레임에 다 실으면 서버가 거절할 수 있다.
      await store(1, 500);
      sender.start(roomId);

      await sender.flush();

      expect(channel.batches.single, hasLength(200));
      expect(sender.lastSent, 200);
    });

    test('⚠️ 나눠 보내도 결국 다 간다', () async {
      // 쌓이는 속도(10점/틱)보다 보내는 속도(200점/틱)가 빨라야 따라잡는다.
      await store(1, 500);
      sender.start(roomId);

      await sender.flush();
      await sender.flush();
      await sender.flush();

      expect(sentSequences(), List.generate(500, (i) => i + 1));
    });
  });

  group('멈추기', () {
    test('멈추면 더 보내지 않는다', () async {
      await store(1, 5);
      sender.start(roomId);

      sender.stop();
      await sender.flush();

      expect(channel.batches, isEmpty);
    });

    test('⚠️ 멈추면 커서가 처음으로 돌아간다', () async {
      // 다음 러닝은 다른 방이고 순번도 1부터 다시 시작한다. 커서가 남으면
      // 새 러닝의 초반 좌표가 통째로 건너뛰어진다.
      await store(1, 5);
      sender.start(roomId);
      await sender.flush();

      sender.stop();

      expect(sender.lastSent, 0);
    });
  });
}

/// 보낸 것을 기록하는 채널.
class _RecordingChannel implements RunningChannel {
  final batches = <List<TrackPoint>>[];

  /// `false`면 소켓에 못 넘긴 척한다.
  var connected = true;

  final _states = StreamController<WsConnectionState>.broadcast();

  void emitState(WsConnectionState next) => _states.add(next);

  @override
  Stream<WsConnectionState> get states => _states.stream;

  @override
  WsConnectionState get state =>
      connected ? WsConnectionState.connected : WsConnectionState.reconnecting;

  @override
  Stream<WsErrorCode> get errors => const Stream.empty();

  @override
  Future<void> start(int runningRoomId) async {}

  @override
  bool sendLocations(List<TrackPoint> points) {
    if (!connected) return false;
    batches.add(points);
    return true;
  }

  @override
  Future<void> close() async {
    await _states.close();
  }
}
