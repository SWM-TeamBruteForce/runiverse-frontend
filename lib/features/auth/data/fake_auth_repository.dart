import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/auth_repository.dart';
import 'package:runiverse/features/auth/domain/auth_session.dart';
import 'package:runiverse/features/auth/domain/auth_tokens.dart';
import 'package:runiverse/features/auth/domain/oauth_authorization.dart';
import 'package:runiverse/features/auth/domain/oauth_provider.dart';

/// 서버 없이 로그인 흐름을 돌려보기 위한 가짜 저장소.
///
/// ## 왜 있는가
///
/// 백엔드를 띄우지 않고 화면과 상태 전이를 완성하기 위해서다.
/// 서버가 준비되면 이 클래스를 **지우지 않고 남긴다** — 테스트에서 계속 쓴다.
/// 진짜 서버를 부르는 구현은 같은 인터페이스로 옆에 만든다.
///
/// ## 씨앗 계정
///
/// 빈 저장소로 시작하면 로그인 화면을 열어도 시험해볼 계정이 없다.
/// [seedEmail] / [seedPassword]로 미리 하나 넣어둔다.
/// **비밀번호는 `PasswordRule`을 통과하는 값이다** — 규칙을 바꿀 때 같이 확인한다.
///
/// ## 계정은 앱을 끄면 사라진다
///
/// 메모리에만 있다. 가입해두고 앱을 재시작하면 그 계정으로 로그인할 수 없다.
/// 저장이 필요해지는 시점은 진짜 서버가 붙는 시점과 같아서 따로 만들지 않는다.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.latency = const Duration(milliseconds: 600)});

  static const seedEmail = 'test@runiverse.app';
  static const seedPassword = 'runi123!';

  /// 응답이 즉시 오면 로딩 표시가 화면에 뜨는지 확인할 수 없다.
  /// 테스트에서는 [Duration.zero]를 넣어 기다리지 않는다.
  final Duration latency;

  final Map<String, String> _accounts = {seedEmail: seedPassword};

  /// 온보딩(프로필 등록)을 마친 계정.
  ///
  /// 씨앗 계정은 마친 것으로 시작한다. 그래야 **기존 사용자가 로그인하면 홈으로**와
  /// **새로 가입한 사람은 프로필로** 두 갈래를 서버 없이 시험할 수 있다.
  final Set<String> _onboarded = {seedEmail};

  /// 발급해 준 리프레시 토큰. 모르는 값이 오면 만료로 답한다.
  final Set<String> _issuedRefreshTokens = {};

  /// 갱신할 때마다 값을 바꾸기 위한 번호. 회전을 흉내 낸다.
  int _rotation = 0;

  /// 보낸 인증번호. 이메일 하나당 하나만 산다 — 새로 보내면 옛것은 죽는다.
  final Map<String, String> _codes = {};

  /// 마지막으로 보낸 번호. **테스트가 메일함을 열 수 없으니** 여기서 꺼내 쓴다.
  String? lastCode;

  /// 발급한 티켓 → 이메일. 서버가 Redis에 두는 것과 같은 역할이다.
  final Map<String, String> _tickets = {};

  /// 방금 보낸 이메일. 쿨다운을 흉내 낸다.
  final Set<String> _cooldown = {};

  int _ticketSeq = 0;

  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(latency);

    final key = _normalize(email);
    // 없는 이메일과 틀린 비밀번호를 구분하지 않는다.
    // 구분하면 "이 이메일은 가입돼 있다"가 새어 나간다.
    if (_accounts[key] != password) {
      throw const AuthException(AuthFailure.invalidCredentials);
    }
    return _sessionFor(key);
  }

  @override
  Future<AuthSession> signUp({
    required String verificationTicket,
    required String password,
  }) async {
    await Future<void>.delayed(latency);

    // ⚠️ 서버와 같은 순서다 — 티켓을 **먼저** 소비하고 계정을 만든다.
    // 순서를 바꾸면 실패했을 때 티켓이 남아, 실제 서버에선 안 되는 재시도가
    // 테스트에서만 통과한다.
    final email = consumeTicket(verificationTicket);
    if (email == null) {
      throw const AuthException(AuthFailure.emailNotVerified);
    }

    if (_accounts.containsKey(email)) {
      throw const AuthException(AuthFailure.emailAlreadyExists);
    }
    _accounts[email] = password;
    return _sessionFor(email);
  }

  /// 인가 코드 → 이메일. 서버의 `(provider, providerId)` 조회를 흉내 낸다.
  final Map<String, String> _oauthAccounts = {};

  /// [signInWithOauth]가 몇 번 불렸는가.
  ///
  /// **취소했을 때 서버를 부르지 않는지** 확인하는 데 쓴다.
  var oauthCallCount = 0;

  @override
  Future<AuthSession> signInWithOauth({
    required OauthProvider provider,
    required OauthAuthorization authorization,
  }) async {
    oauthCallCount++;
    await Future<void>.delayed(latency);

    // 심어 두지 않았으면 처음 오는 사람이다. 인가 코드에서 이메일을 만들어
    // **매번 같은 계정이 나오게** 한다.
    final email =
        _oauthAccounts[authorization.authorizationCode] ??
        'kakao-${authorization.authorizationCode}@example.com';

    // 같은 이메일의 로컬 계정이 있으면 서버가 자동 연동하지 않는다.
    if (_accounts.containsKey(email)) {
      throw const AuthException(AuthFailure.emailAlreadyExists);
    }
    return _sessionFor(email);
  }

  /// 어느 인가 코드가 어느 이메일에 대응하는지 심는다. **기다리지 않는다.**
  ///
  /// [isOnboarded]는 **프로필까지 채운 카카오 계정**을 만든다. 로컬 계정을 심어
  /// 대신할 수 없다 — 같은 이메일의 로컬 계정이 있으면 [signInWithOauth]가
  /// `emailAlreadyExists`로 막는다. 그래서 여기서만 만들 수 있다.
  void seedOauthAccount({
    required String code,
    required String email,
    bool isOnboarded = false,
  }) {
    final key = _normalize(email);
    _oauthAccounts[code] = key;
    if (isOnboarded) _onboarded.add(key);
  }

  @override
  Future<void> sendVerificationCode(String email) async {
    await Future<void>.delayed(latency);

    final key = _normalize(email);
    // ⚠️ 중복을 **쿨다운보다 먼저** 본다. 뒤에 두면 이미 가입된 이메일로
    // 두 번 눌렀을 때 두 번째가 sendCooldown이 되어, 같은 조작에 다른 이유가
    // 나온다. 사용자는 무엇이 문제인지 알 수 없다.
    if (_accounts.containsKey(key)) {
      throw const AuthException(AuthFailure.emailAlreadyExists);
    }
    if (!_cooldown.add(key)) {
      throw const AuthException(AuthFailure.sendCooldown);
    }

    // 고정값이다. 무작위로 만들면 테스트가 번호를 알 수 없다.
    const code = '123456';
    _codes[key] = code;
    lastCode = code;
  }

  @override
  Future<String> verifyCode({
    required String email,
    required String code,
  }) async {
    await Future<void>.delayed(latency);

    final key = _normalize(email);
    final issued = _codes[key];
    // 보낸 적이 없는 것과 만료된 것을 서버가 같은 코드로 답한다. 여기도 같게 둔다.
    if (issued == null) {
      throw const AuthException(AuthFailure.codeExpired);
    }
    if (issued != code) {
      throw const AuthException(AuthFailure.invalidCode);
    }

    // 맞은 번호는 지운다. 같은 번호로 티켓을 여러 장 받으면 한 번의 인증으로
    // 계정을 여러 개 만들 수 있다.
    _codes.remove(key);
    // 쿨다운도 푼다. 가입에 실패해 인증부터 다시 해야 할 때 막히면 안 된다.
    _cooldown.remove(key);

    return issueTicket(key);
  }

  @override
  Future<void> signOut() => Future<void>.delayed(latency);

  /// 발급했던 토큰만 받아준다.
  ///
  /// **새 값을 돌려주는 것이 중요하다.** 같은 값을 주면 "저장을 잊어도 동작하는"
  /// 가짜가 되어, 회전을 처리하지 않은 버그를 테스트가 놓친다.
  @override
  Future<AuthTokens> refresh(String refreshToken) async {
    await Future<void>.delayed(latency);

    if (!_issuedRefreshTokens.contains(refreshToken)) {
      throw const AuthException(AuthFailure.sessionExpired);
    }

    _rotation++;
    final rotated = '$refreshToken-r$_rotation';
    // 옛 토큰은 무효가 된다. 서버가 회전 후 무효화한다면 이 동작이 같다.
    _issuedRefreshTokens
      ..remove(refreshToken)
      ..add(rotated);

    return AuthTokens(
      accessToken: 'fake-access-r$_rotation',
      refreshToken: rotated,
    );
  }

  /// **기다리지 않고** 세션을 발급한다. 이미 로그인해 둔 상태를 만들 때 쓴다.
  ///
  /// [signIn]을 쓰면 될 것 같지만 그럴 수 없다. `testWidgets`는 가짜 시간 위에서
  /// 도는데, [latency]의 `Future.delayed`는 그 가짜 타이머를 쓴다.
  /// **`pumpWidget` 전에 그것을 기다리면 시간을 진행시킬 `pump`가 없어 영원히 멈춘다.**
  ///
  /// 발급한 리프레시 토큰은 [refresh]가 받아준다 — 그래야 자동 로그인 경로를
  /// 시험할 수 있다.
  AuthSession issueSession({String email = seedEmail}) =>
      _sessionFor(_normalize(email));

  /// **기다리지 않고** 계정을 심는다. [issueSession]과 같은 이유로 동기다.
  ///
  /// [isOnboarded]를 `false`로 두면 "가입은 했지만 프로필을 안 채운 사람"이 된다.
  void seedAccount({
    required String email,
    required String password,
    bool isOnboarded = false,
  }) {
    final key = _normalize(email);
    _accounts[key] = password;
    if (isOnboarded) _onboarded.add(key);
  }

  /// **기다리지 않고** 티켓을 만든다. 인증을 마친 상태를 세울 때 쓴다.
  ///
  /// [issueSession]과 같은 이유로 동기다 — `testWidgets`는 가짜 시간 위에서 돌고,
  /// `pumpWidget` 전에 `Future`를 기다리면 시간을 진행시킬 `pump`가 없어 멈춘다.
  String issueTicket(String email) {
    _ticketSeq++;
    final ticket = 'fake-ticket-$_ticketSeq';
    _tickets[ticket] = _normalize(email);
    return ticket;
  }

  /// 티켓을 **소비하고** 그 이메일을 돌려준다. 없으면 `null`.
  ///
  /// 서버 `SignUpHandler`가 하는 일과 같다 — 한 번 쓰면 사라지고,
  /// **그 뒤 가입이 실패해도 돌아오지 않는다.**
  String? consumeTicket(String ticket) => _tickets.remove(ticket);

  /// 이메일은 대소문자를 가리지 않는다. `Runner@`와 `runner@`가 다른 계정이 되면
  /// 사용자는 왜 로그인이 안 되는지 알 수 없다.
  String _normalize(String email) => email.trim().toLowerCase();

  /// 같은 이메일이면 항상 같은 `userId`가 나오게 이메일에서 만든다.
  /// 매번 새 번호를 매기면 로그인할 때마다 다른 사람이 된다.
  AuthSession _sessionFor(String email) {
    final session = AuthSession(
      userId: 'fake-${email.hashCode.toRadixString(16)}',
      accessToken: 'fake-access-$email',
      refreshToken: 'fake-refresh-$email',
      isOnboarded: _onboarded.contains(email),
    );
    // 이 토큰만 갱신해 준다. 기억하지 않으면 자동 로그인 경로를 시험할 수 없다.
    _issuedRefreshTokens.add(session.refreshToken);
    return session;
  }
}
