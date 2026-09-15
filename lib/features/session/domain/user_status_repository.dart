import 'package:runiverse/features/session/domain/user_status.dart';

/// 서버가 아는 "지금 무엇을 하는 중인가"를 읽는다.
abstract interface class UserStatusRepository {
  /// 현재 상태를 가져온다. 실패하면 [UserStatusException]을 던진다.
  Future<UserStatus> fetch();
}

/// 상태를 못 읽은 이유.
///
/// ⚠️ **네트워크 실패와 세션 만료를 가른다.** 둘을 묶으면 신호가 잠깐 없을 때
/// 사용자가 로그아웃된다.
enum UserStatusFailure { network, sessionExpired, unknown }

class UserStatusException implements Exception {
  const UserStatusException(this.failure);

  final UserStatusFailure failure;

  @override
  String toString() => 'UserStatusException(${failure.name})';
}
