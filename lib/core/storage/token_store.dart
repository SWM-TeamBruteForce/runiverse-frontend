/// 저장소에서 한 번에 읽어 온 값.
///
/// 읽기를 하나로 합친 이유는 [TokenStore]의 실제 구현이 플랫폼 채널을 건너가기
/// 때문이다. 값마다 따로 읽으면 **스플래시에서만 왕복이 네 번** 생기고,
/// 나눠 읽는 사이에 값이 어긋날 수 있다.
class StoredAuth {
  const StoredAuth({
    this.userId,
    this.accessToken,
    this.refreshToken,
    this.isOnboarded = false,
    this.nickname,
    this.profileImageUrl,
    this.introduction,
  });

  /// 저장된 것이 없으면 `null`. **로그인한 적이 있는지의 판단 기준이다.**
  final String? userId;

  final String? accessToken;
  final String? refreshToken;

  /// 프로필 등록을 마쳤는가. **모르면 `false`다** — 한 번 더 묻는 쪽이
  /// 프로필 없는 사용자를 홈에 들이는 것보다 안전하다.
  final bool isOnboarded;

  /// `GET /users/me`가 마지막으로 답한 값. **토큰이 유효한 동안만 남는다** —
  /// [clearTokens]가 토큰과 함께 지운다.
  ///
  /// 앱을 켜자마자 프로필 탭에 닉네임을 그릴 수 있게 하는 것이 목적이다.
  /// 이것이 없으면 `/me`가 도착할 때까지 회색 자리표시자가 보인다.
  ///
  /// ⚠️ **진실은 여전히 서버다.** 이 값은 `/me` 응답이 오면 덮어쓴다.
  final String? nickname;
  final String? profileImageUrl;
  final String? introduction;
}

/// 로그인 토큰을 어디에 넣어둘 것인가.
///
/// ## 왜 `AuthSession`을 받지 않는가
///
/// `AuthSession`은 `features/auth/domain`에 있다. `core`가 그것을 import하면
/// **`core → features` 방향이 생겨 의존 방향이 뒤집힌다.** 그래서 문자열만 주고받는다.
///
/// ## 왜 전부 `Future`인가
///
/// [InMemoryTokenStore]는 기다릴 것이 없다. 그런데 실제 구현
/// (`flutter_secure_storage` — 안드로이드 Keystore / iOS Keychain)은 플랫폼 채널을
/// 건너가므로 반드시 비동기다. 지금부터 비동기로 맞춰둔다.
///
/// ## 지우는 메서드가 둘인 이유
///
/// [clearTokens]는 토큰만, [clear]는 전부 지운다.
/// 토큰이 만료됐을 때 `userId`까지 지우면 다음 실행에 **온보딩 소개를 다시 보게 된다** —
/// 그 사람은 처음 온 것이 아니라 다시 로그인하면 되는 사람이다.
abstract interface class TokenStore {
  /// 왕복 한 번으로 네 값을 다 읽는다. 빈 문자열은 `null`로 걸러 내보낸다.
  Future<StoredAuth> read();

  /// 로그인 · 가입 성공.
  Future<void> saveSession({
    required String userId,
    required String accessToken,
    required String refreshToken,
    required bool isOnboarded,
  });

  /// 갱신 성공. **토큰 둘만** 덮어쓴다.
  ///
  /// 서버가 리프레시 토큰을 회전시키므로 새 값을 반드시 저장해야 한다.
  /// 덮어쓰지 않으면 다음 갱신이 401로 죽는다 — 유효기간이 남아 있어도.
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  });

  /// 프로필 등록을 마쳤다.
  Future<void> markOnboarded();

  /// `GET /users/me`가 답한 값을 남긴다. **토큰은 건드리지 않는다.**
  ///
  /// ⚠️ `CurrentUser`를 그대로 받지 않고 원시값으로 받는다 — `core`가
  /// `features/auth`를 알게 되면 의존 방향이 뒤집힌다.
  ///
  /// [isOnboarded]도 함께 덮어쓴다. `/me`가 그 값의 유일한 출처이고,
  /// 다른 기기에서 프로필을 채웠으면 이 기기의 저장값이 낡았기 때문이다.
  Future<void> saveCurrentUser({
    required String userId,
    required bool isOnboarded,
    String? nickname,
    String? profileImageUrl,
    String? introduction,
  });

  /// 토큰이 만료됐다. `userId`와 `isOnboarded`는 남기고,
  /// **`/me` 캐시는 토큰과 함께 지운다.**
  Future<void> clearTokens();

  /// 로그아웃. 전부 비운다.
  Future<void> clear();
}

/// 메모리에만 들고 있는 구현.
///
/// **앱을 끄면 사라진다.** 앱에서는 `SecureTokenStore`를 쓰고, 이것은 테스트가 쓴다 —
/// 위젯 테스트는 플랫폼 채널을 부를 수 없다.
class InMemoryTokenStore implements TokenStore {
  String? _userId;
  String? _accessToken;
  String? _refreshToken;
  bool _isOnboarded = false;
  String? _nickname;
  String? _profileImageUrl;
  String? _introduction;

  @override
  Future<StoredAuth> read() async => StoredAuth(
    userId: _blankToNull(_userId),
    accessToken: _blankToNull(_accessToken),
    refreshToken: _blankToNull(_refreshToken),
    isOnboarded: _isOnboarded,
    nickname: _blankToNull(_nickname),
    profileImageUrl: _blankToNull(_profileImageUrl),
    introduction: _blankToNull(_introduction),
  );

  @override
  Future<void> saveSession({
    required String userId,
    required String accessToken,
    required String refreshToken,
    required bool isOnboarded,
  }) async {
    _userId = userId;
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _isOnboarded = isOnboarded;
  }

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
  }

  @override
  Future<void> markOnboarded() async => _isOnboarded = true;

  @override
  Future<void> saveCurrentUser({
    required String userId,
    required bool isOnboarded,
    String? nickname,
    String? profileImageUrl,
    String? introduction,
  }) async {
    _userId = userId;
    _isOnboarded = isOnboarded;
    _nickname = nickname;
    _profileImageUrl = profileImageUrl;
    _introduction = introduction;
  }

  @override
  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    _nickname = null;
    _profileImageUrl = null;
    _introduction = null;
  }

  @override
  Future<void> clear() async {
    _userId = null;
    _accessToken = null;
    _refreshToken = null;
    _isOnboarded = false;
    _nickname = null;
    _profileImageUrl = null;
    _introduction = null;
  }
}

/// 빈 문자열을 `null`로 바꾼다.
///
/// 빈 `refreshToken`을 서버에 보내면 400 `VALIDATION_FAILED`가 온다.
/// 보내기 전에 걸러야 원인이 가까운 곳에 남는다.
String? _blankToNull(String? value) =>
    (value == null || value.isEmpty) ? null : value;
