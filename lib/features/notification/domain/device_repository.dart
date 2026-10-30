/// 푸시 기기 등록이 실패하는 이유.
enum DeviceFailure {
  /// 서버에 닿지 못했거나 5xx다.
  network,

  /// 401인데 토큰 갱신이 안 됐다. ⚠️ 갱신이 망 문제로 실패해도 이것이다.
  sessionExpired,

  /// 403 `APP_UPDATE_REQUIRED`. 다시 보내도 같은 답이다.
  updateRequired,

  /// 400 등. 다시 보내도 같은 답이다 — 버전을 못 읽어 헤더가 빠지면 400이 난다.
  unknown,
}

class DeviceException implements Exception {
  const DeviceException(this.failure);

  final DeviceFailure failure;

  @override
  String toString() => 'DeviceException($failure)';
}

/// 이 기기를 푸시 받을 곳으로 서버에 올린다(명세 2-1).
abstract interface class DeviceRepository {
  /// 등록하거나 덮어쓴다. 같은 값으로 여러 번 불러도 행이 늘지 않는다.
  ///
  /// 플랫폼·앱 버전은 싣지 않는다 — 서버가 모든 요청의 헤더
  /// (`X-App-Platform`·`X-App-Version`)에서 읽는다.
  Future<void> register({required String deviceId, required String pushToken});
}
