import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/session/data/http_user_status_repository.dart';
import 'package:runiverse/features/session/domain/user_status.dart';
import 'package:runiverse/features/session/domain/user_status_repository.dart';

final userStatusRepositoryProvider = Provider<UserStatusRepository>(
  (ref) => HttpUserStatusRepository(
    ref.watch(dioProvider),
    ref.watch(tokenStoreProvider),
    ref.watch(authRepositoryProvider),
  ),
);

/// 마지막으로 읽은 서버 상태. `null`이면 아직 못 읽었다.
///
/// ## ⚠️ 못 읽은 것과 쉬는 중을 섞지 않는다
///
/// 실패했을 때 [UserStatusIdle]로 채우면 **달리는 중인 사람을 홈에 묶어두고도
/// 아무 문제가 없어 보인다.** `null`로 남겨 두면 부르는 쪽이 "모른다"를 다룰 수
/// 있다 — 지금은 홈에 머물되 다음 복귀에서 다시 묻는다.
final userStatusProvider = NotifierProvider<UserStatusController, UserStatus?>(
  UserStatusController.new,
);

/// 서버 상태를 읽어 들고 있는다.
///
/// 앱 진입과 **포그라운드 복귀**에서 부른다. 화면이 소유하지 않는 이유는
/// 여러 화면이 같은 값을 보기 때문이다 — 홈의 배너와 스플래시의 갈림길이
/// 같은 상태를 읽는다.
class UserStatusController extends Notifier<UserStatus?> {
  @override
  UserStatus? build() => null;

  /// 서버에 다시 묻는다. 읽었으면 그 값을, 못 읽었으면 `null`을 돌려준다.
  ///
  /// **실패해도 직전 값을 지운다.** 오래된 상태로 화면을 그리면 이미 끝난
  /// 러닝으로 되돌아가는 일이 생긴다.
  Future<UserStatus?> refresh() async {
    try {
      final status = await ref.read(userStatusRepositoryProvider).fetch();
      state = status;
      return status;
    } on UserStatusException catch (error) {
      debugPrint('[status] 상태를 읽지 못했다 · ${error.failure.name}');
      state = null;
      return null;
    }
  }

  /// 로그아웃·탈퇴처럼 **더 볼 것이 없을 때** 비운다.
  void clear() => state = null;
}
