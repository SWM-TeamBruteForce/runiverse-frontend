/// 로그인 토큰을 어디에 넣어둘 것인가.
///
/// ## 왜 `AuthSession`을 받지 않는가
///
/// `AuthSession`은 `features/auth/domain`에 있다. `core`가 그것을 import하면
/// **`core → features` 방향이 생겨 의존 방향이 뒤집힌다.** 그래서 문자열만 주고받는다.
///
/// ## 왜 전부 `Future`인가
///
/// 지금 구현([InMemoryTokenStore])은 기다릴 것이 없다. 그런데 실제 구현
/// (`flutter_secure_storage` — 안드로이드 Keystore / iOS Keychain)은 플랫폼 채널을
/// 건너가므로 반드시 비동기다. **나중에 시그니처가 바뀌면 부르는 쪽을 전부 고쳐야 한다.**
/// 지금부터 비동기로 맞춰둔다.
abstract interface class TokenStore {
  Future<void> save({
    required String userId,
    required String accessToken,
    required String refreshToken,
  });

  /// 저장된 것이 없으면 `null`. **로그인한 적이 있는지의 판단 기준이다.**
  Future<String?> readUserId();

  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();

  /// 로그아웃. 세 값을 모두 비운다.
  Future<void> clear();
}

/// 메모리에만 들고 있는 구현.
///
/// **앱을 끄면 사라진다.** 그래서 지금은 앱을 다시 켰을 때 자동 로그인이 되지 않는다.
/// 이것을 `flutter_secure_storage` 구현으로 바꾸는 순간 자동 로그인이 살아난다 —
/// 그 외에 고칠 코드는 없다.
class InMemoryTokenStore implements TokenStore {
  String? _userId;
  String? _accessToken;
  String? _refreshToken;

  @override
  Future<void> save({
    required String userId,
    required String accessToken,
    required String refreshToken,
  }) async {
    _userId = userId;
    _accessToken = accessToken;
    _refreshToken = refreshToken;
  }

  @override
  Future<String?> readUserId() async => _userId;

  @override
  Future<String?> readAccessToken() async => _accessToken;

  @override
  Future<String?> readRefreshToken() async => _refreshToken;

  @override
  Future<void> clear() async {
    _userId = null;
    _accessToken = null;
    _refreshToken = null;
  }
}
