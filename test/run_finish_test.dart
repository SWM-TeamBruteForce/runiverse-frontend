import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/network/ws_client.dart';
import 'package:runiverse/core/network/ws_message.dart';
import 'package:runiverse/features/session/data/fake_track_repository.dart';
import 'package:runiverse/features/session/domain/running_channel.dart';
import 'package:runiverse/features/session/domain/track_point.dart';
import 'package:runiverse/features/session/domain/track_recorder.dart';
import 'package:runiverse/features/session/domain/track_sender.dart';

/// 러닝 종료 — **무엇을 확인하고 나서 지우는가.**
///
/// 종료는 되돌릴 수 없는 지점이다. 두 가지가 어긋나면 사용자가 뛴 기록이
/// 영영 잘못 남는다.
///
/// 1. 남은 좌표를 안 보내고 끝내면 **그 구간이 빠진 기록이 확정된다**
/// 2. ack 없이 트랙을 지우면 **다시 보낼 방법이 사라진다**
///
/// 좌표에는 ack가 없고 종료에만 있다. 그래서 이 확인 하나가 로컬 트랙을
/// 지워도 되는지의 유일한 근거다.
void main() {
  const roomId = 55;

  late FakeTrackRepository repository;
  late _FinishChannel channel;
  late TrackSender sender;
  late TrackRecorder recorder;

  setUp(() {
    repository = FakeTrackRepository();
    channel = _FinishChannel();
    sender = TrackSender(repository, channel);
    recorder = TrackRecorder(repository);
  });

  tearDown(() => sender.stop());

  TrackPoint point(int sequence) => TrackPoint(
    sequence: sequence,
    latitude: 37.5 + sequence * 0.0001,
    longitude: 127.0,
    accuracyMeters: 5,
    speedMetersPerSecond: 2.8,
    recordedAt: DateTime(2026, 8, 28, 19, 10).add(Duration(seconds: sequence)),
  );

  Future<void> store(int from, int to) async {
    for (var i = from; i <= to; i++) {
      await repository.add(roomId, point(i));
    }
  }

  /// 화면이 하는 것과 같은 순서로 끝낸다.
  Future<bool> finishRun() async {
    await sender.drain();
    sender.stop();
    final acked = await channel.finish();
    if (acked) await recorder.discard();
    return acked;
  }

  group('남은 좌표', () {
    test('⚠️ 끝내기 전에 남은 것을 전부 보낸다', () async {
      // 남겨둔 채 끝내면 그 구간이 빠진 기록이 확정되고 되돌릴 수 없다.
      await store(1, 5);
      sender.start(roomId);

      await finishRun();

      expect(channel.sentSequences, [1, 2, 3, 4, 5]);
    });

    test('⚠️ 한 배치를 넘겨도 전부 보낸다', () async {
      // `flush`는 한 번에 200개까지만 싣는다. 한 번만 부르면 나머지가 남는다.
      await store(1, 500);
      sender.start(roomId);

      await finishRun();

      expect(channel.sentSequences, hasLength(500));
      expect(channel.sentSequences.last, 500);
    });

    test('좌표를 보낸 뒤에 종료를 보낸다', () async {
      // 순서가 뒤집히면 서버가 마지막 좌표를 못 본 채 기록을 확정한다.
      await store(1, 5);
      sender.start(roomId);

      await finishRun();

      expect(channel.order, ['locations', 'finish']);
    });
  });

  group('확인을 받았을 때', () {
    test('로컬 트랙을 지운다', () async {
      await store(1, 5);
      sender.start(roomId);
      await recorder.bind(roomId);

      expect(await finishRun(), isTrue);

      expect(await repository.count(roomId), 0);
      expect(repository.cleared, contains(roomId));
    });
  });

  group('확인을 못 받았을 때', () {
    test('⚠️ 트랙을 지우지 않는다', () async {
      // 지우면 서버에 없는 구간을 다시 보낼 방법이 사라진다.
      // 남겨두면 자리를 차지할 뿐이다.
      channel.ack = false;
      await store(1, 5);
      sender.start(roomId);
      await recorder.bind(roomId);

      expect(await finishRun(), isFalse);

      expect(await repository.count(roomId), 5);
      expect(repository.cleared, isEmpty);
    });

    test('⚠️ 소켓이 끊겨 있으면 기다리지 않는다', () async {
      // ack가 올 리 없다. 여기서 매달리면 요약 화면 뒤가 안 끝난다.
      channel.connected = false;
      await store(1, 5);
      sender.start(roomId);
      await recorder.bind(roomId);

      expect(await finishRun(), isFalse);

      expect(await repository.count(roomId), 5);
    });
  });

  group('오류 코드', () {
    test('명세의 10종을 모두 안다', () {
      const wire = [
        'MALFORMED_MESSAGE',
        'MISSING_MESSAGE_TYPE',
        'UNSUPPORTED_MESSAGE_TYPE',
        'INVALID_REQUEST',
        'RUNNING_NOT_STARTED',
        'RUNNING_SESSION_UNAVAILABLE',
        'RUNNING_TRACK_UNAVAILABLE',
        'ROOM_NOT_FOUND',
        'NOT_ROOM_PLAYER',
        'INVALID_ROOM_STATE',
      ];

      expect(
        wire.map(WsErrorCode.fromWire),
        everyElement(isNot(WsErrorCode.unknown)),
      );
    });

    test('모르는 코드는 unknown이다', () {
      // 서버가 늘려도 앱이 죽지 않아야 한다.
      expect(WsErrorCode.fromWire('훗날_생길_코드'), WsErrorCode.unknown);
      expect(WsErrorCode.fromWire(null), WsErrorCode.unknown);
    });

    test('⚠️ 세션이 없다는 두 코드만 재시작을 요구한다', () {
      // 다시 알리지 않으면 그 뒤 좌표가 전부 같은 오류로 거절되는데,
      // 좌표에는 ack가 없어 앱은 아무것도 모른 채 계속 보낸다.
      expect(WsErrorCode.runningNotStarted.needsRestart, isTrue);
      expect(WsErrorCode.runningSessionUnavailable.needsRestart, isTrue);

      // 좌표 저장 실패는 러닝이 계속된다. 재시작할 이유가 없다.
      expect(WsErrorCode.runningTrackUnavailable.needsRestart, isFalse);
      expect(WsErrorCode.roomNotFound.needsRestart, isFalse);
      expect(WsErrorCode.unknown.needsRestart, isFalse);
    });
  });
}

/// 좌표와 종료를 받아 순서까지 기록하는 채널.
class _FinishChannel implements RunningChannel {
  /// 무엇을 어떤 순서로 받았나.
  final order = <String>[];

  final sentSequences = <int>[];

  /// `false`면 소켓에 못 넘긴 척한다.
  var connected = true;

  /// `false`면 종료 확인이 오지 않은 척한다.
  var ack = true;

  @override
  Stream<WsConnectionState> get states => const Stream.empty();

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
    if (order.isEmpty || order.last != 'locations') order.add('locations');
    sentSequences.addAll(points.map((p) => p.sequence));
    return true;
  }

  @override
  Future<bool> finish({bool forced = false}) async {
    if (!connected) return false;
    order.add('finish');
    return ack;
  }

  @override
  Future<void> close() async {}
}
