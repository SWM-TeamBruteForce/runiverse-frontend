import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 홈에서 위치·신체 활동 권한을 물었는가를 기기에 남긴다.
///
/// ## 왜 남기나
///
/// 홈은 처음 들어올 때 **기기당 한 번만** 묻는다(`HomePermissionAsker`).
/// 안드로이드는 두 번 거절하면 다시 물을 수 없는데, 권한 상태만으로는 "아직 안
/// 물었음"과 "한 번 거절함"을 가를 수 없다(`LocationRepository.checkAccess`).
/// 홈에서 두 번째 거절까지 받아 버리면 러닝 출발 때 물을 기회가 사라진다.
///
/// **안드로이드만 쓴다.** iOS는 거절하면 곧바로 다시 물을 수 없는 상태가 되어
/// 상태만으로 가를 수 있고, 이 값이 Keychain에 남아 앱을 지워도 살아남는다.
///
/// 로그아웃해도 남는다 — 계정이 아니라 기기의 권한 이력이다.
abstract interface class LocationAskStore {
  /// 홈에서 이미 물었는가.
  Future<bool> asked();

  Future<void> markAsked();
}

/// 기기에 남기는 구현.
///
/// 값 하나 때문에 `shared_preferences` 를 새로 들이지 않고 이미 있는 저장소를
/// 쓴다 — `SecureWatchVersionStore` 와 같은 판단이다.
///
/// ⚠️ `auth.*` 와 접두사를 나눈다. 로그아웃이 `auth.*` 만 지우므로 이 값은 남는다.
class SecureLocationAskStore implements LocationAskStore {
  SecureLocationAskStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _keyAsked = 'locationAsk.home';

  @override
  Future<bool> asked() async => await _storage.read(key: _keyAsked) != null;

  @override
  Future<void> markAsked() => _storage.write(key: _keyAsked, value: '1');
}
