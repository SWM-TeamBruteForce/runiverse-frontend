import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:runiverse/core/storage/token_store.dart';

/// 안드로이드 Keystore · iOS Keychain에 넣는 [TokenStore].
///
/// ## 왜 평문 저장소를 쓰지 않는가
///
/// `refreshToken`은 **60일**짜리다. 유출되면 두 달 동안 계정을 계속 쓸 수 있다.
/// `shared_preferences`는 안드로이드에서 평문 XML이라 루팅 기기나 ADB 백업으로
/// 그대로 읽힌다.
///
/// ## 네 값을 한곳에 둔다
///
/// `isOnboarded`는 민감하지 않지만 여기 같이 넣는다. 저장소를 나누면
/// **토큰은 지웠는데 플래그가 남는 상태**가 생긴다. 한곳에 있으면 지우기가 한 번이다.
///
/// ## ⚠️ iOS에서 앱을 지워도 Keychain은 남는다
///
/// 재설치한 기기에서 이전 사용자의 토큰이 살아난다. 막으려면 "첫 실행이면 한 번
/// 비우기"가 필요하고, 그러려면 **앱과 함께 지워지는 저장소가 하나 더** 있어야 한다.
/// 안드로이드만 돌리는 지금은 미룬다 — iOS 전환 시 할 일이다.
class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // 안드로이드 옵션은 지정하지 않는다. 10.3.1부터 기본이
            // Keystore 기반 cipher다 — 예전 `encryptedSharedPreferences` 플래그는
            // deprecated이고 **넘겨도 무시된다**(Jetpack Security가 폐기됐다).
            //
            // iOS 기본값은 기기 밖으로 백업된다. `first_unlock_this_device`는
            // 백업에 포함되지 않고, 재부팅 후 첫 잠금해제 전에는 읽히지 않는다.
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  static const _keyUserId = 'auth.userId';
  static const _keyAccessToken = 'auth.accessToken';
  static const _keyRefreshToken = 'auth.refreshToken';
  static const _keyIsOnboarded = 'auth.isOnboarded';

  @override
  Future<StoredAuth> read() async {
    // readAll은 왕복 한 번이다. 값마다 read를 부르면 네 번 건너간다.
    final all = await _storage.readAll();
    return StoredAuth(
      userId: _blankToNull(all[_keyUserId]),
      accessToken: _blankToNull(all[_keyAccessToken]),
      refreshToken: _blankToNull(all[_keyRefreshToken]),
      isOnboarded: all[_keyIsOnboarded] == 'true',
    );
  }

  @override
  Future<void> saveSession({
    required String userId,
    required String accessToken,
    required String refreshToken,
    required bool isOnboarded,
  }) async {
    await _storage.write(key: _keyUserId, value: userId);
    await _storage.write(key: _keyAccessToken, value: accessToken);
    await _storage.write(key: _keyRefreshToken, value: refreshToken);
    await _storage.write(key: _keyIsOnboarded, value: '$isOnboarded');
  }

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _keyAccessToken, value: accessToken);
    await _storage.write(key: _keyRefreshToken, value: refreshToken);
  }

  @override
  Future<void> markOnboarded() =>
      _storage.write(key: _keyIsOnboarded, value: 'true');

  @override
  Future<void> clearTokens() async {
    await _storage.delete(key: _keyAccessToken);
    await _storage.delete(key: _keyRefreshToken);
  }

  @override
  Future<void> clear() async {
    // ⚠️ `deleteAll()`을 부르지 않는다. 이 저장소에는 `auth.*` 말고
    // `consent.*`도 산다 — 로그아웃했다고 약관 동의까지 지우면 같은 사람에게
    // 같은 것을 두 번 묻게 된다. **지울 키를 지정한다.**
    await _storage.delete(key: _keyUserId);
    await _storage.delete(key: _keyAccessToken);
    await _storage.delete(key: _keyRefreshToken);
    await _storage.delete(key: _keyIsOnboarded);
  }
}

/// 빈 문자열을 `null`로 바꾼다.
///
/// 빈 `refreshToken`을 서버에 보내면 400 `VALIDATION_FAILED`가 온다.
/// 보내기 전에 걸러야 원인이 가까운 곳에 남는다.
String? _blankToNull(String? value) =>
    (value == null || value.isEmpty) ? null : value;
