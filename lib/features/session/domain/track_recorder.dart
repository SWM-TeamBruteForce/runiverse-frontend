import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/track_point.dart';
import 'package:runiverse/features/session/domain/track_repository.dart';

/// 달리는 동안 좌표를 쌓는다. 순번을 매기고 저장소에 넘긴다.
///
/// ## ⚠️ 방이 없어도 좌표를 버리지 않는다
///
/// 저장소의 PK가 `(running_room_id, sequence)`라 방 번호 없이는 쓸 수 없다.
/// 그런데 방 생성이 실패해 재시도 중일 수 있고(설계 문서 4절), 그동안 들어온
/// 좌표를 버리면 **러닝 초반 거리가 통째로 빠진다.** 출발 준비 화면이 막으려던
/// 바로 그 문제다.
///
/// 그래서 방을 알 때까지 메모리에 들고 있다가, [bind]가 불리면 한꺼번에 쓴다.
/// 방은 대개 몇 초 안에 생기므로 쌓이는 양이 적다.
///
/// ## 순번은 방과 무관하게 이어진다
///
/// 좌표를 받은 순서가 곧 순번이다. 방이 늦게 생겨도 번호가 밀리지 않는다 —
/// 서버가 순번으로 경로를 잇기 때문에 **빠진 번호보다 뒤바뀐 번호가 더 나쁘다.**
class TrackRecorder {
  TrackRecorder(this._repository);

  final TrackRepository _repository;

  /// 어느 러닝인가. `null`이면 아직 방이 없다.
  int? _roomId;

  /// 방을 기다리는 좌표들.
  final _pending = <TrackPoint>[];

  /// 마지막으로 매긴 순번. 1부터 센다.
  var _sequence = 0;

  /// 아직 저장소에 못 쓴 좌표 수. 테스트와 진단에 쓴다.
  int get pendingCount => _pending.length;

  /// 방 번호를 알게 됐다. **기다리던 좌표를 전부 쓴다.**
  ///
  /// ## ⚠️ 이미 쌓인 좌표가 있으면 그 뒤부터 매긴다
  ///
  /// 앱이 러닝 도중에 죽으면 이 객체는 사라지고 [_sequence]가 0으로 다시
  /// 태어나는데, **저장소의 좌표는 그대로 남아 있다.** 그 상태로 1번부터
  /// 매기면 저장소가 예전 1번을 덮어쓰고(PK가 `(방, 순번)`이다), 서버는 이미
  /// 받은 번호라며 새 좌표를 전부 버린다 — **재시작 이후 달린 구간이 기록에
  /// 안 남는다.**
  ///
  /// 기다리던 좌표도 같은 이유로 번호를 다시 받는다. 아직 저장도 전송도 안 된
  /// 것이라 밀어도 잃는 것이 없다. 순서는 그대로다.
  Future<void> bind(int runningRoomId) async {
    _roomId = runningRoomId;

    final last = await _repository.lastSequence(runningRoomId);
    if (_pending.isEmpty) {
      if (last > 0) _sequence = last;
      return;
    }

    // 복사해서 돌린다. 쓰는 동안 새 좌표가 들어와도 목록이 흔들리지 않는다.
    final waiting = List<TrackPoint>.from(_pending);
    _pending.clear();

    if (last == 0) {
      // 새 러닝이다. 기다리던 번호가 곧 맞는 번호다.
      for (final point in waiting) {
        await _repository.add(runningRoomId, point);
      }
      return;
    }

    _sequence = last;
    for (final point in waiting) {
      await _repository.add(runningRoomId, point.withSequence(++_sequence));
    }
  }

  /// 좌표 하나를 쌓는다.
  ///
  /// [currentPace]는 **그 시점의 페이스**다. 저장할 때 박아 두면 재전송이
  /// 읽어서 보내기로 끝난다 — 전송 시점에 계산하면 지나간 페이스를 재현해야 한다.
  ///
  /// [headingDegrees]도 마찬가지로 **부르는 쪽이 계산해서 준다.** 직전 좌표가
  /// 있어야 내는 값이라 기록기가 알 수 없다.
  Future<void> add(
    GeoPoint point, {
    Duration? currentPace,
    int? cadenceSpm,
    double? headingDegrees,
  }) {
    _sequence++;
    final track = TrackPoint.from(
      point,
      sequence: _sequence,
      currentPace: currentPace,
      cadenceSpm: cadenceSpm,
      headingDegrees: headingDegrees,
    );

    final roomId = _roomId;
    if (roomId == null) {
      _pending.add(track);
      return Future<void>.value();
    }
    return _repository.add(roomId, track);
  }

  /// 이 러닝의 좌표를 전부 지운다. `RUNNING_FINISHED` ack 뒤에 부른다.
  ///
  /// ⚠️ **ack 전에 부르면 안 된다.** 서버가 아직 못 받았을 수 있고, 지우면
  /// 다시 보낼 방법이 없다.
  Future<void> discard() async {
    final roomId = _roomId;
    _pending.clear();
    if (roomId != null) await _repository.clear(roomId);
    reset();
  }

  /// 다음 러닝을 위해 비운다. **저장소는 건드리지 않는다.**
  void reset() {
    _roomId = null;
    _sequence = 0;
    _pending.clear();
  }
}
