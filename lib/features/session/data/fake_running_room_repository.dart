import 'package:runiverse/features/session/domain/running_room.dart';
import 'package:runiverse/features/session/domain/running_room_repository.dart';

/// 서버 없이 러닝 흐름을 돌려보기 위한 가짜.
class FakeRunningRoomRepository implements RunningRoomRepository {
  FakeRunningRoomRepository({
    this.latency = Duration.zero,
    this.roomId = 1,
    this.failure,
  });

  final Duration latency;
  final int roomId;

  /// 주면 그 이유로 실패한다. **409 재시도 차단을 보는 데 쓴다.**
  RunningRoomFailure? failure;

  /// 몇 번 불렸는가. 재시도가 도는지, 409에서 멈추는지 세는 데 쓴다.
  var calls = 0;

  @override
  Future<RunningRoom> openSolo() async {
    calls++;
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final reason = failure;
    if (reason != null) throw RunningRoomException(reason);
    return RunningRoom(roomId);
  }
}
