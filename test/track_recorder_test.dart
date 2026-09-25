import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/track_point.dart';
import 'package:runiverse/features/session/domain/track_recorder.dart';
import 'package:runiverse/features/session/domain/track_repository.dart';

/// 좌표 쌓기 — **방이 늦게 생겨도 초반 좌표를 잃지 않는가.**
///
/// 방 생성이 재시도 중일 수 있다(설계 문서 4절). 그동안 들어온 좌표를 버리면
/// 러닝 초반 거리가 통째로 빠진다.
void main() {
  late _FakeRepository repository;
  late TrackRecorder recorder;

  setUp(() {
    repository = _FakeRepository();
    recorder = TrackRecorder(repository);
  });

  GeoPoint geo([int second = 0]) => GeoPoint(
    latitude: 37.5,
    longitude: 127.0,
    recordedAt: DateTime(2026, 8, 26, 19, 10, second),
  );

  group('방이 있을 때', () {
    test('바로 저장된다', () async {
      await recorder.bind(7);

      await recorder.add(geo(1));

      expect(repository.saved[7]?.length, 1);
      expect(recorder.pendingCount, 0);
    });

    test('순번이 1부터 이어진다', () async {
      await recorder.bind(7);

      await recorder.add(geo(1));
      await recorder.add(geo(2));
      await recorder.add(geo(3));

      expect(repository.saved[7]?.map((p) => p.sequence), [1, 2, 3]);
    });
  });

  group('방이 아직 없을 때', () {
    test('⚠️ 좌표를 버리지 않고 들고 있는다', () async {
      await recorder.add(geo(1));
      await recorder.add(geo(2));

      expect(recorder.pendingCount, 2);
      expect(repository.saved, isEmpty);
    });

    test('⚠️ 방이 생기면 기다리던 것이 전부 저장된다', () async {
      await recorder.add(geo(1));
      await recorder.add(geo(2));

      await recorder.bind(7);

      expect(repository.saved[7]?.length, 2);
      expect(recorder.pendingCount, 0);
    });

    test('⚠️ 순번이 밀리지 않는다', () async {
      // 서버가 순번으로 경로를 잇는다. 빠진 번호보다 뒤바뀐 번호가 더 나쁘다.
      await recorder.add(geo(1));
      await recorder.add(geo(2));
      await recorder.bind(7);

      await recorder.add(geo(3));

      expect(repository.saved[7]?.map((p) => p.sequence), [1, 2, 3]);
    });
  });

  group('계산값', () {
    test('그 시점의 페이스가 박힌다', () async {
      await recorder.bind(7);

      await recorder.add(geo(1), currentPace: const Duration(seconds: 345));

      expect(repository.saved[7]?.single.currentPaceSecondsPerKm, 345);
    });

    test('페이스를 못 내면 null로 남는다', () async {
      await recorder.bind(7);

      await recorder.add(geo(1));

      expect(repository.saved[7]?.single.currentPaceSecondsPerKm, isNull);
    });
  });

  group('정리', () {
    test('버리면 저장소도 비운다', () async {
      await recorder.bind(7);
      await recorder.add(geo(1));

      await recorder.discard();

      expect(repository.cleared, contains(7));
    });

    test('⚠️ 다음 러닝은 순번 1부터 시작한다', () async {
      await recorder.bind(7);
      await recorder.add(geo(1));
      await recorder.discard();

      await recorder.bind(8);
      await recorder.add(geo(2));

      expect(repository.saved[8]?.single.sequence, 1);
    });
  });

  /// 앱이 러닝 도중에 죽었다 살아난 자리다. 기록기는 새로 태어나지만 저장소의
  /// 좌표는 남아 있다 — 1번부터 다시 매기면 그것을 덮어쓴다.
  group('⚠️ 이어 달리기', () {
    /// 재시작 전에 쌓여 있던 좌표.
    void seed(int roomId, int count) {
      for (var i = 1; i <= count; i++) {
        repository.saved
            .putIfAbsent(roomId, () => [])
            .add(TrackPoint.from(geo(i), sequence: i));
      }
    }

    test('쌓인 좌표가 있으면 그 뒤 번호부터 매긴다', () async {
      seed(7, 500);

      await recorder.bind(7);
      await recorder.add(geo(1));
      await recorder.add(geo(2));

      expect(
        repository.saved[7]?.map((p) => p.sequence).toList().sublist(500),
        [501, 502],
      );
    });

    test('⚠️ 예전 좌표를 하나도 덮어쓰지 않는다', () async {
      seed(7, 500);

      await recorder.bind(7);
      await recorder.add(geo(1));

      expect(repository.saved[7], hasLength(501));
    });

    test('⚠️ 방을 알기 전에 들어온 좌표도 뒤로 밀린다', () async {
      // 복구 경로에서는 위치 구독이 `bind`보다 먼저 붙는다. 그 좌표들이
      // 1번부터 번호를 받아 놓은 상태로 들어온다.
      seed(7, 500);

      await recorder.add(geo(1));
      await recorder.add(geo(2));
      await recorder.bind(7);

      expect(repository.saved[7], hasLength(502));
      expect(
        repository.saved[7]?.map((p) => p.sequence).toList().sublist(500),
        [501, 502],
      );
    });
  });
}

class _FakeRepository implements TrackRepository {
  final saved = <int, List<TrackPoint>>{};
  final cleared = <int>[];

  @override
  Future<void> add(int runningRoomId, TrackPoint point) async {
    // ⚠️ 진짜 저장소는 PK가 `(방, 순번)`이라 같은 순번을 **덮어쓴다.**
    // 쌓아두면 순번이 겹치는 버그가 여기서만 무해해 보인다.
    final points = saved.putIfAbsent(runningRoomId, () => []);
    final at = points.indexWhere((p) => p.sequence == point.sequence);
    if (at < 0) {
      points.add(point);
    } else {
      points[at] = point;
    }
  }

  @override
  Future<List<TrackPoint>> after(
    int runningRoomId, {
    int afterSequence = 0,
    int limit = 100,
  }) async => (saved[runningRoomId] ?? [])
      .where((p) => p.sequence > afterSequence)
      .take(limit)
      .toList();

  @override
  Future<void> clear(int runningRoomId) async {
    cleared.add(runningRoomId);
    saved.remove(runningRoomId);
  }

  int? active;

  @override
  Future<int?> activeRoom() async => active;

  @override
  Future<void> markActiveRoom(int runningRoomId) async =>
      active = runningRoomId;

  @override
  Future<void> clearActiveRoom() async => active = null;

  @override
  Future<int> count(int runningRoomId) async =>
      saved[runningRoomId]?.length ?? 0;

  @override
  Future<int> lastSequence(int runningRoomId) async {
    final points = saved[runningRoomId];
    if (points == null || points.isEmpty) return 0;
    return points.map((p) => p.sequence).reduce((a, b) => a > b ? a : b);
  }
}
