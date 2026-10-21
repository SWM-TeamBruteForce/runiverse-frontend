import 'package:runiverse/features/app_update/domain/app_update_status.dart';

/// 서버가 정한 버전 기준을 가져온다.
abstract interface class AppVersionRepository {
  /// 이 플랫폼의 최소·최신 버전.
  ///
  /// ⚠️ **실패를 예외로 올린다.** 스플래시가 이것을 기다리므로, 못 받았을 때
  /// "통과"로 눌러 버리면 구버전 앱이 그대로 들어간다. 받지 못한 것과 괜찮은
  /// 것을 섞지 않는다.
  Future<AppVersionPolicy> fetch();
}

/// 버전 기준을 못 받았다.
class AppVersionUnavailable implements Exception {
  const AppVersionUnavailable();

  @override
  String toString() => 'AppVersionUnavailable()';
}
