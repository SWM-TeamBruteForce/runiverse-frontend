import 'package:runiverse/features/session/domain/track_point.dart';
import 'package:runiverse/features/session/domain/track_repository.dart';

/// 기기 없이 좌표 쌓기를 돌려보기 위한 가짜.
///
/// **위젯 테스트에는 이게 필요하다.** 진짜 저장소는 `getDatabasesPath()`로
/// 플랫폼 채널을 부르는데, 테스트에는 기기가 없어 실패한다. 그 실패를
/// 컨트롤러가 삼키므로 테스트는 통과하지만 **좌표가 쌓이는지는 아무도 확인하지
/// 않는 상태**가 된다.
class FakeTrackRepository implements TrackRepository {
  /// 방 번호별로 쌓인 좌표.
  final saved = <int, List<TrackPoint>>{};

  /// 비운 방 번호들. `RUNNING_FINISHED` ack 뒤에 지우는지 보는 데 쓴다.
  final cleared = <int>[];

  /// 주면 저장이 그 오류로 실패한다. **실패해도 러닝이 계속되는지** 보는 데 쓴다.
  Object? failure;

  /// 어느 방이든 쌓인 좌표를 순서대로 펼친다. 검사할 때 편하다.
  List<TrackPoint> get all =>
      [for (final points in saved.values) ...points]
        ..sort((a, b) => a.sequence.compareTo(b.sequence));

  @override
  Future<void> add(int runningRoomId, TrackPoint point) async {
    final reason = failure;
    if (reason != null) throw reason;
    saved.putIfAbsent(runningRoomId, () => []).add(point);
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

  @override
  Future<int> count(int runningRoomId) async =>
      saved[runningRoomId]?.length ?? 0;
}
