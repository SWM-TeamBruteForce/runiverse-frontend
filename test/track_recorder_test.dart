import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/run_numbers.dart';
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
            .add(TrackPoint.from(geo(i), sequence: i, pauseSegment: 0));
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

  /// 일시정지 구간 번호 — 1.1.1 2절.
  ///
  /// ## ⚠️ 틀려도 아무 오류가 안 난다
  ///
  /// 번호를 안 올리면 서버는 **멈춘 적이 없다고 보고** 그 사이 이동을 거리에
  /// 넣는다. 앱에는 아무 표시도 없다 — 기록을 받아 보고서야 안다. 그래서
  /// 여기서 못 박는다.
  group('⚠️ 일시정지 구간 번호', () {
    List<int> segmentsOf(int roomId) =>
        (repository.saved[roomId] ?? []).map((p) => p.pauseSegment).toList();

    test('멈추기 전 좌표는 0이다', () async {
      await recorder.bind(7);

      await recorder.add(geo(1));
      await recorder.add(geo(2));

      expect(segmentsOf(7), [0, 0]);
    });

    test('⚠️ 멈춘 뒤 좌표부터 1이다', () async {
      await recorder.bind(7);
      await recorder.add(geo(1));

      await recorder.markPause();
      await recorder.add(geo(2));

      expect(segmentsOf(7), [0, 1]);
    });

    test('⚠️ 이미 쌓인 좌표의 번호는 바뀌지 않는다', () async {
      // 과거 좌표를 재전송하면서 지금 번호로 갈아 끼우면 **경계가 사라져**
      // 멈춘 사이 이동이 거리에 들어간다. 가이드가 못 박은 지점이다.
      await recorder.bind(7);
      await recorder.add(geo(1));
      await recorder.add(geo(2));

      await recorder.markPause();

      expect(segmentsOf(7), [0, 0]);
    });

    test('멈춘 횟수만큼 올라간다', () async {
      await recorder.bind(7);

      await recorder.markPause();
      await recorder.add(geo(1));
      await recorder.markPause();
      await recorder.add(geo(2));

      expect(segmentsOf(7), [1, 2]);
    });

    test('⚠️ 순번은 일시정지와 무관하게 이어진다', () async {
      await recorder.bind(7);
      await recorder.add(geo(1));

      await recorder.markPause();
      await recorder.add(geo(2));

      expect(repository.saved[7]?.map((p) => p.sequence).toList(), [1, 2]);
    });

    test('⚠️ 전송 결과를 기다리지 않고 남긴다', () async {
      // 좌표 전송에는 ack가 없다. 전송이 끝나기를 기다렸다 올리면 연결이
      // 끊기거나 앱이 죽을 때 **증가분이 누락된다.**
      await recorder.bind(7);

      await recorder.markPause();

      expect(repository.numbered[7]?.pauseSegment, 1);
    });

    test('방을 모르면 메모리에만 올리고, 방을 알면 그 번호로 쓴다', () async {
      // 방 생성이 재시도 중인 동안에도 멈출 수 있다.
      await recorder.markPause();
      await recorder.add(geo(1));

      expect(recorder.numbers.pauseSegment, 1);

      await recorder.bind(7);

      expect(segmentsOf(7), [1]);
    });
  });

  /// 멈춘 채로 앱이 죽었다 살아난 자리.
  ///
  /// ## ⚠️ 쌓인 좌표로는 알 수 없다
  ///
  /// 멈추면 번호가 올라가는데 **그 뒤로 새 좌표가 들어오지 않는다.** 그래서
  /// 쌓인 좌표의 최대 구간 번호는 언제나 올리기 전 값이다 — 되살릴 근거가
  /// 저장된 번호뿐이다.
  group('⚠️ 번호 되살리기', () {
    test('저장된 구간 번호를 이어 쓴다', () async {
      repository.numbered[7] = const RunNumbers(
        nextSequence: 120,
        pauseSegment: 2,
      );

      await recorder.bind(7);
      await recorder.add(geo(1));

      expect(repository.saved[7]?.single.pauseSegment, 2);
      expect(repository.saved[7]?.single.sequence, 120);
    });

    test('⚠️ 방을 알기 전에 들어온 좌표도 되살린 번호를 받는다', () async {
      // 0을 그대로 보내면 **번호가 줄어들어 배치 전체가 거부된다.**
      repository.numbered[7] = const RunNumbers(
        nextSequence: 120,
        pauseSegment: 2,
      );

      await recorder.add(geo(1));
      await recorder.add(geo(2));
      await recorder.bind(7);

      expect(repository.saved[7]?.map((p) => p.pauseSegment).toList(), [2, 2]);
      expect(repository.saved[7]?.map((p) => p.sequence).toList(), [120, 121]);
    });

    test('⚠️ 저장된 번호가 뒤처져 있으면 들고 있던 것을 쓴다', () async {
      // 아직 안 보낸 좌표가 있다는 뜻이다. 뒤로 물리면 그 좌표를 덮어쓴다.
      await recorder.bind(7);
      await recorder.markPause();
      await recorder.add(geo(1));

      repository.numbered[7] = const RunNumbers(
        nextSequence: 1,
        pauseSegment: 0,
      );

      await recorder.bind(7);
      await recorder.add(geo(2));

      expect(repository.saved[7]?.last.pauseSegment, 1);
    });

    test('⚠️ 번호 행이 없어도 쌓인 좌표 뒤부터 매긴다', () async {
      // v2에서 올라온 DB가 이 모양이다 — 좌표만 있고 번호 행이 없다.
      repository.saved[7] = [
        TrackPoint.from(geo(1), sequence: 1, pauseSegment: 0),
        TrackPoint.from(geo(2), sequence: 2, pauseSegment: 0),
      ];

      await recorder.bind(7);
      await recorder.add(geo(3));

      expect(repository.saved[7]?.last.sequence, 3);
    });

    test('⚠️ 서버 번호를 받으면 그 뒤부터 매긴다', () async {
      // 러닝 중 재설치의 유일한 탈출구다. 로컬은 1번부터인데 서버는 이미
      // 120번까지 받았다 — 1번을 보내면 중복으로 버려지고, 더 달려 로컬
      // 순번이 120을 넘어서면 구간 번호가 작아 배치가 통째로 거부된다.
      await recorder.bind(7);

      await recorder.applyServerNumbers(
        const RunNumbers(nextSequence: 120, pauseSegment: 2),
      );
      await recorder.add(geo(1));

      expect(repository.saved[7]?.single.sequence, 120);
      expect(repository.saved[7]?.single.pauseSegment, 2);
    });

    test('⚠️ 서버가 뒤처져 있으면 로컬이 남는다', () async {
      // 멀쩡한 러닝에서는 서버가 받은 것보다 로컬이 앞선다 — 아직 안 보낸
      // 좌표가 있어서다. 서버 값을 따르면 그 좌표를 덮어쓴다.
      await recorder.bind(7);
      await recorder.markPause();
      await recorder.add(geo(1));

      await recorder.applyServerNumbers(RunNumbers.serverZero);
      await recorder.add(geo(2));

      expect(repository.saved[7]?.last.sequence, 2);
      expect(repository.saved[7]?.last.pauseSegment, 1);
    });

    test('⚠️ 이미 저장된 좌표의 번호는 바뀌지 않는다', () async {
      // 앞으로 수집할 좌표에만 적용한다(가이드 2절). 저장된 번호를 밀면
      // 서버가 좌표에서 복원하는 일시정지 경계가 어긋난다.
      await recorder.bind(7);
      await recorder.add(geo(1));

      await recorder.applyServerNumbers(
        const RunNumbers(nextSequence: 500, pauseSegment: 5),
      );

      expect(repository.saved[7]?.single.sequence, 1);
      expect(repository.saved[7]?.single.pauseSegment, 0);
    });

    test('맞춘 번호를 저장소에 남긴다', () async {
      // 남기지 않으면 다음 실행이 또 1번부터다.
      await recorder.bind(7);

      await recorder.applyServerNumbers(
        const RunNumbers(nextSequence: 120, pauseSegment: 2),
      );

      expect(
        repository.numbered[7],
        const RunNumbers(nextSequence: 120, pauseSegment: 2),
      );
    });

    test('⚠️ 방을 모르면 메모리만 맞춘다', () async {
      // 방 번호 없이 저장소에 쓸 수 없다(PK가 `(방, 순번)`이다). 그래도
      // 올려 둬야 [bind]가 큰 쪽으로 들고 간다.
      await recorder.applyServerNumbers(
        const RunNumbers(nextSequence: 120, pauseSegment: 2),
      );

      expect(recorder.numbers.nextSequence, 120);
      expect(repository.saves, 0);

      await recorder.bind(7);
      await recorder.add(geo(1));

      expect(repository.saved[7]?.single.sequence, 120);
    });

    test('다시 붙어 같은 값을 또 받아도 번호가 밀리지 않는다', () async {
      // 연결마다 한 번씩 온다. 멱등이어야 재연결이 번호를 앞당기지 않는다.
      await recorder.bind(7);
      final twice = const RunNumbers(nextSequence: 120, pauseSegment: 2);

      await recorder.applyServerNumbers(twice);
      await recorder.applyServerNumbers(twice);
      await recorder.add(geo(1));

      expect(repository.saved[7]?.single.sequence, 120);
    });

    test('다음 러닝은 번호가 처음으로 돌아간다', () async {
      await recorder.bind(7);
      await recorder.markPause();
      await recorder.add(geo(1));

      await recorder.discard();

      expect(recorder.numbers, RunNumbers.start);
      expect(repository.numbered.containsKey(7), isFalse);
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
    // ⚠️ 진짜 저장소처럼 번호도 함께 지운다.
    numbered.remove(runningRoomId);
  }

  /// 방 번호별로 남긴 번호. 테스트가 직접 세팅해 **재시작 뒤 복원**을 만든다.
  final numbered = <int, RunNumbers>{};

  /// 번호를 남긴 횟수. 좌표마다 남기는지 보는 데 쓴다.
  var saves = 0;

  @override
  Future<RunNumbers?> numbers(int runningRoomId) async =>
      numbered[runningRoomId];

  @override
  Future<void> saveNumbers(int runningRoomId, RunNumbers numbers) async {
    saves++;
    numbered[runningRoomId] = numbers;
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
