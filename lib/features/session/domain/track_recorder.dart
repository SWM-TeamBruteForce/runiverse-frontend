import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/run_numbers.dart';
import 'package:runiverse/features/session/domain/track_point.dart';
import 'package:runiverse/features/session/domain/track_repository.dart';

/// 달리는 동안 좌표를 쌓는다. 번호를 매기고 저장소에 넘긴다.
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
/// ## 번호 둘을 들고 있는다 — 1.1.1 2절
///
/// `sequence`는 일시정지와 무관하게 이어 증가하고, `pauseSegment`는 **일시정지
/// 버튼을 누를 때만** 1 올라간다([markPause]). 둘 다 [RunNumbers]에 묶여
/// 저장되고, 앱이 죽었다 살아나면 [bind]가 되살린다.
///
/// ⚠️ **번호를 매기는 자리가 여기 하나뿐이어야 한다.** 화면이나 전송기가 따로
/// 매기면 둘이 어긋나고, 어긋난 번호는 서버가 배치째로 거부한다.
class TrackRecorder {
  TrackRecorder(this._repository);

  final TrackRepository _repository;

  /// 어느 러닝인가. `null`이면 아직 방이 없다.
  int? _roomId;

  /// 방을 기다리는 좌표들. **번호는 [bind]가 다시 매긴다.**
  final _pending = <TrackPoint>[];

  /// 다음에 쓸 번호 둘.
  var _numbers = RunNumbers.start;

  /// 아직 저장소에 못 쓴 좌표 수. 테스트와 진단에 쓴다.
  int get pendingCount => _pending.length;

  /// 지금 들고 있는 번호. 테스트와 진단에 쓴다.
  RunNumbers get numbers => _numbers;

  /// 방 번호를 알게 됐다. **기다리던 좌표를 전부 쓴다.**
  ///
  /// ## ⚠️ 저장소에 이미 쌓인 것이 있으면 그 뒤부터 매긴다
  ///
  /// 앱이 러닝 도중에 죽으면 이 객체는 사라지고 번호가 처음으로 다시 태어나는데,
  /// **저장소의 좌표는 그대로 남아 있다.** 그 상태로 1번부터 매기면 저장소가
  /// 예전 1번을 덮어쓰고(PK가 `(방, 순번)`이다), 서버는 이미 받은 번호라며
  /// 새 좌표를 전부 버린다 — **재시작 이후 달린 구간이 기록에 안 남는다.**
  ///
  /// 구간 번호는 더 조용히 틀린다. 멈춘 채로 죽었다 살아나면 되살린 번호가
  /// 쌓인 좌표의 번호보다 큰데, 작은 쪽을 쓰면 **배치 전체가
  /// `PAUSE_SEGMENT_DECREASED`로 거부된다.** 그래서 [RunNumbers.mergedWith]로
  /// 언제나 큰 쪽을 따른다.
  ///
  /// ## 기다리던 좌표도 번호를 다시 받는다
  ///
  /// 아직 저장도 전송도 안 된 것이라 밀어도 잃는 것이 없다. 순서는 그대로다.
  Future<void> bind(int runningRoomId) async {
    _roomId = runningRoomId;
    _numbers = _numbers.mergedWith(await _restore(runningRoomId));

    // ⚠️ **여기서 번호를 저장하지 않는다.** 저장이 실패하면 그 예외가 방을
    // 붙이는 길로 터져 나가 **러닝이 아예 시작되지 않는다** — 좌표 하나 때문에
    // 달리기를 멈출 이유가 없다는 원칙을 깬다(`run_flow_test`가 지킨다).
    //
    // 저장을 미뤄도 잃는 것이 없다. 되살린 값은 [_restore]가 쌓인 좌표와 남긴
    // 번호에서 **매번 다시 계산하고**, 첫 좌표가 들어오면 [_write]가 남긴다.
    if (_pending.isEmpty) return;

    // 복사해서 돌린다. 쓰는 동안 새 좌표가 들어와도 목록이 흔들리지 않는다.
    final waiting = List<TrackPoint>.from(_pending);
    _pending.clear();

    for (final point in waiting) {
      await _write(
        runningRoomId,
        point.withNumbers(
          sequence: _numbers.nextSequence,
          pauseSegment: _numbers.pauseSegment,
        ),
      );
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
  }) async {
    final track = TrackPoint.from(
      point,
      sequence: _numbers.nextSequence,
      pauseSegment: _numbers.pauseSegment,
      currentPace: currentPace,
      cadenceSpm: cadenceSpm,
      headingDegrees: headingDegrees,
    );

    final roomId = _roomId;
    if (roomId == null) {
      // ⚠️ **번호를 밀지 않는다.** 방을 알게 되면 [bind]가 되살린 번호로 다시
      // 매긴다. 여기서 밀어 두면 되살린 번호와 겹치거나 앞질러, 쓰이지 않은
      // 번호가 중간에 비어 버린다.
      _pending.add(track);
      return;
    }

    await _write(roomId, track);
  }

  /// 일시정지 버튼을 눌렀다. **구간 번호를 올린다** — 1.1.1 2절.
  ///
  /// ## ⚠️ 메모리를 먼저, 동기로 올린다
  ///
  /// 저장이 느리거나 실패해도 **다음 좌표는 올라간 번호를 달아야 한다.** 서버는
  /// 번호가 올라간 좌표를 받아야 일시정지 경계를 안다. 저장을 기다렸다 올리면
  /// 그 사이에 들어온 좌표가 멈추기 전 번호로 나가고, 서버는 멈춘 적이 없다고
  /// 본다 — 고치려던 바로 그 버그다.
  ///
  /// ## ⚠️ 재개할 때는 부르지 않는다
  ///
  /// 번호는 **멈출 때 한 번만** 올린다. 양쪽에서 올리면 멈춤 한 번이 구간
  /// 두 개가 되고, 서버는 있지도 않은 구간을 거리에서 뺀다.
  ///
  /// ## ⚠️ 자동 정지에는 부르지 않는다
  ///
  /// 신호 대기처럼 버튼을 누르지 않고 멈춘 경우는 번호를 유지한다(가이드 2.3
  /// · `AutoPause`). 서버가 관측 공백으로 따로 판단한다.
  ///
  /// 방을 모르면 메모리만 올린다. [bind]가 그 값을 들고 간다.
  Future<void> markPause() {
    _numbers = _numbers.afterPause();

    final roomId = _roomId;
    if (roomId == null) return Future<void>.value();
    return _repository.saveNumbers(roomId, _numbers);
  }

  /// 이 러닝의 좌표를 전부 지운다. `RUNNING_FINISHED` ack 뒤에 부른다.
  ///
  /// ⚠️ **ack 전에 부르면 안 된다.** 서버가 아직 못 받았을 수 있고, 지우면
  /// 다시 보낼 방법이 없다.
  Future<void> discard() async {
    final roomId = _roomId;
    _pending.clear();
    // 저장소의 `clear`가 좌표와 번호를 함께 지운다.
    if (roomId != null) await _repository.clear(roomId);
    reset();
  }

  /// 다음 러닝을 위해 비운다. **저장소는 건드리지 않는다.**
  void reset() {
    _roomId = null;
    _numbers = RunNumbers.start;
    _pending.clear();
  }

  /// 좌표 하나를 번호와 함께 남긴다.
  ///
  /// ## ⚠️ 번호를 먼저 남긴다
  ///
  /// 좌표 저장이 실패하면 그 번호는 **쓰인 것으로 두고** 다음 좌표가 뒤를
  /// 잇는다. 번호를 아껴 다시 쓰면 서버가 중복으로 버려 그 구간이 빠진다.
  ///
  /// 거꾸로 두면 더 나쁘다. 좌표는 새 번호로 저장됐는데 번호 저장이 실패한
  /// 채 앱이 죽으면, 되살린 구간 번호가 **이미 보낸 좌표보다 작아져** 다음
  /// 배치가 통째로 거부된다.
  Future<void> _write(int runningRoomId, TrackPoint point) async {
    _numbers = _numbers.afterPoint();
    await _repository.saveNumbers(runningRoomId, _numbers);
    await _repository.add(runningRoomId, point);
  }

  /// 저장소가 아는 번호를 되살린다. 아무것도 없으면 [RunNumbers.start].
  ///
  /// ## 두 곳을 함께 본다
  ///
  /// 남겨 둔 번호가 정본이지만, **쌓인 좌표의 최대 순번**도 근거다 — 번호
  /// 저장이 실패한 채 좌표만 남는 경우가 있고, v2에서 올라온 DB에는 좌표만
  /// 있고 번호 행이 없다. 둘 중 앞선 쪽을 따른다.
  ///
  /// ⚠️ **좌표 행의 구간 번호는 보지 않는다.** 멈추면 번호가 올라가는데 그 뒤로
  /// 새 좌표가 안 들어오므로, 쌓인 좌표의 최대값은 언제나 **올리기 전 값**이다.
  /// v2에서 올라온 좌표는 기본값 0이라 그것도 근거가 못 된다.
  Future<RunNumbers> _restore(int runningRoomId) async {
    final stored = await _repository.numbers(runningRoomId);
    final last = await _repository.lastSequence(runningRoomId);
    final fromPoints = RunNumbers(nextSequence: last + 1, pauseSegment: 0);

    return stored == null ? fromPoints : fromPoints.mergedWith(stored);
  }
}
