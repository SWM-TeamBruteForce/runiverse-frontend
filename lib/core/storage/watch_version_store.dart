import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:runiverse/core/version/app_version.dart';

/// 서버가 정한 워치 앱 최소 버전을 기기에 남겨 둔다.
///
/// ## 왜 남기나
///
/// 워치가 `WATCH_SYNC` 를 보내면 폰은 이 값으로 바로 판정한다. 메모리에만 두면
/// 폰 앱을 새로 켤 때마다 서버에 닿기 전까지 판정을 못 해 워치가 기다린다.
///
/// 로그아웃해도 남는다 — 계정이 아니라 앱 버전의 값이다.
abstract interface class WatchVersionStore {
  /// 남겨 둔 최소 버전. 없거나 못 읽으면 `null`.
  Future<AppVersion?> minimum();

  Future<void> rememberMinimum(AppVersion minimum);
}

/// 기기에 남기는 구현.
///
/// 값 하나 때문에 `shared_preferences` 를 새로 들이지 않고 이미 있는 저장소를
/// 쓴다 — `SecureSignInMemoryStore` 와 같은 판단이다.
///
/// ⚠️ `auth.*` 와 접두사를 나눈다. 로그아웃이 `auth.*` 만 지우므로 이 값은 남는다.
class SecureWatchVersionStore implements WatchVersionStore {
  SecureWatchVersionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _keyMinimum = 'watchVersion.minimum';

  @override
  Future<AppVersion?> minimum() async =>
      AppVersion.parse(await _storage.read(key: _keyMinimum));

  @override
  Future<void> rememberMinimum(AppVersion minimum) =>
      _storage.write(key: _keyMinimum, value: minimum.toString());
}

/// 메모리에만 들고 있는 구현. 테스트가 쓴다 —
/// 위젯 테스트는 플랫폼 채널을 부를 수 없다.
class InMemoryWatchVersionStore implements WatchVersionStore {
  InMemoryWatchVersionStore([this._minimum]);

  AppVersion? _minimum;

  @override
  Future<AppVersion?> minimum() async => _minimum;

  @override
  Future<void> rememberMinimum(AppVersion minimum) async => _minimum = minimum;
}
