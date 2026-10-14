import 'package:runiverse/features/session/domain/user_status.dart';
import 'package:runiverse/features/session/domain/user_status_repository.dart';

/// 서버 없이 상태 분기를 돌려보기 위한 가짜.
///
/// 여섯 조합을 손으로 만들어 넣으면 **앱이 어느 화면으로 가는지**를 서버 없이
/// 시험할 수 있다. 실패도 값으로 넣을 수 있어야 한다 — 상태를 못 읽었을 때
/// 홈으로 폴백하는지가 이 흐름에서 가장 다루기 어려운 자리다.
class FakeUserStatusRepository implements UserStatusRepository {
  FakeUserStatusRepository({
    this.status = const UserStatusIdle(),
    this.latency = Duration.zero,
    this.failure,
  });

  /// 답할 상태. **`final`이 아니다** — 같은 인스턴스가 도중에 답을 바꿔야
  /// 포그라운드 복귀로 상태가 달라지는 상황을 만들 수 있다.
  UserStatus status;

  final Duration latency;

  /// 주면 그 이유로 실패한다.
  UserStatusFailure? failure;

  /// 몇 번 불렸는가. **포그라운드 복귀마다 다시 묻는지** 세는 데 쓴다.
  var calls = 0;

  @override
  Future<UserStatus> fetch() async {
    calls++;
    // ⚠️ **0이면 타이머를 만들지 않는다.** `Future.delayed(zero)` 도 타이머라,
    // 마지막 프레임 뒤에 걸리면 `pumpAndSettle` 이 더 그릴 것이 없어 그냥
    // 끝나고 **"타이머가 남았다"로 트리를 걷을 때 죽는다.** 기다릴 것이 없는데
    // 기다리는 척할 이유가 없다.
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final reason = failure;
    if (reason != null) throw UserStatusException(reason);
    return status;
  }
}
